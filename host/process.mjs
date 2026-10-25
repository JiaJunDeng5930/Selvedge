import { boundary } from './public/model-boundary.mjs';
import { spawn } from 'node:child_process';
import { mkdtemp, open, readdir, readFile } from 'node:fs/promises';
import { readSync, writeSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { StringDecoder } from 'node:string_decoder';
import { prepareSandbox } from './sandbox.mjs';
import { storeImageContent } from './files.mjs';
import { durableDirectory, syncDirectory } from './file-io.mjs';

export function killGroup(child, signal = 'SIGKILL') {
  // DEFENSE: A failed spawn has no PID and therefore owns no process group.
  if (!child?.pid) return;
  try { process.kill(-child.pid, signal); }
  // DEFENSE: The shell or its process group may exit before cancellation/exit cleanup sends its signal.
  catch (error) { if (error.code !== 'ESRCH') throw error; }
}

let sessionLibrary;

/** Job control creates additional process groups inside the detached Bash session. */
async function killSession(session) {
  function terminate(pid) {
    try { process.kill(pid, 'SIGKILL'); }
    // DEFENSE: A session member can exit between the OS membership observation and signalling it.
    catch (error) { if (error.code !== 'ESRCH') throw error; }
  }
  if (process.platform === 'darwin') {
    const { dlopen, ptr } = await import('bun:ffi');
    sessionLibrary ??= dlopen('/usr/lib/libSystem.B.dylib', {
      proc_listpids: { args: ['u32', 'u32', 'ptr', 'i32'], returns: 'i32' },
      getsid: { args: ['i32'], returns: 'i32' },
    });
    const { proc_listpids, getsid } = sessionLibrary.symbols;
    const size = proc_listpids(1, 0, null, 0);
    if (size <= 0) throw new Error('Could not enumerate process sessions');
    // DEFENSE: Other applications can spawn processes between the size query and list query.
    const pids = new Int32Array(Math.ceil(size / 4) + 1024);
    const bytes = proc_listpids(1, 0, ptr(pids), pids.byteLength);
    if (bytes <= 0) throw new Error('Could not enumerate process sessions');
    for (let index = 0; index < bytes / 4; index++) {
      // DEFENSE: Listed PIDs can exit before getsid, which then returns -1 rather than a matching session.
      if (pids[index] > 0 && getsid(pids[index]) === session) terminate(pids[index]);
    }
  } else {
    for (const name of (await readdir('/proc')).filter(name => /^\d+$/.test(name))) {
      let stat;
      try { stat = await readFile(`/proc/${name}/stat`, 'utf8'); }
      // DEFENSE: A process can exit after listing /proc but before reading its stat entry.
      catch (error) { if (['ENOENT', 'ESRCH'].includes(error.code)) continue; throw error; }
      // The parenthesized command can contain spaces and closing parentheses.
      const fields = stat.slice(stat.lastIndexOf(')') + 2).trim().split(/\s+/);
      if (Number(fields[3]) === session) terminate(Number(name));
    }
  }
}

export function capture(limit) {
  const chunks = [];
  let retained = 0;
  let total = 0;
  return {
    add(chunk) {
      total += chunk.length;
      const keep = Math.min(chunk.length, Math.max(0, limit - retained));
      if (keep) { chunks.push(Buffer.from(chunk.subarray(0, keep))); retained += keep; }
    },
    result() { return { text: new TextDecoder().decode(Buffer.concat(chunks, retained), { stream: total > retained }),
      truncated: total > retained, total_bytes: total }; },
  };
}

class UnicodeTail {
  #tail = boundary('control.process.tail_initial', {});
  #points = [];
  constructor(capacity) { this.capacity = capacity; }
  add(text, combined) {
    const points = Array.from(text);
    const next = boundary('control.process.output_append', {
      capacity: this.capacity, tail: this.#tail, combined: combined.#tail, count: points.length,
    });
    this.#apply(next.tail, points);
    combined.#apply(next.combined, points);
  }
  #apply(plan, points) {
    this.#tail = plan.tail;
    this.#points = this.#points.slice(plan.old_drop).concat(points.slice(plan.new_drop));
  }
  read(cursor = '0') {
    const { prefix, offset, ...snapshot } = boundary('control.process.tail_read', { tail: this.#tail, cursor });
    return { ...snapshot, output: prefix + this.#points.slice(offset).join('') };
  }
}

function processOutput(limit, combined) {
  const tail = new UnicodeTail(limit);
  const decoder = new StringDecoder('utf8');
  let bytes = 0;
  function retain(text) { tail.add(text, combined); }
  return {
    add(chunk) { bytes += chunk.length; retain(decoder.write(chunk)); },
    end() { retain(decoder.end()); },
    result() {
      const result = tail.read();
      return { text: result.output, truncated: result.omitted_characters > 0, total_bytes: bytes,
        total_characters: Number(result.next_cursor), omitted_characters: result.omitted_characters };
    },
  };
}

// A disk ring keeps the latest bytes without rewriting the retained file on every chunk.
function outputArtifact(file, filename, limit) {
  let ring = boundary('control.process.ring_initial', {});
  let failed = false;
  function writeAll(bytes, offset) {
    for (let written = 0; written < bytes.length;) {
      written += writeSync(file.fd, bytes, written, bytes.length - written, offset + written);
    }
  }
  return {
    add(chunk) {
      const plan = boundary('control.process.ring_append', { ring, capacity: limit, count: chunk.length });
      ring = plan.ring;
      // PTY callbacks cannot await writes; bounded synchronous writes apply disk backpressure.
      for (const part of plan.writes) writeAll(chunk.subarray(part.start, part.start + part.count), part.offset);
    },
    fail() { failed = true; },
    async finish() {
      const physical = Buffer.alloc(ring.length);
      try {
        for (let offset = 0; offset < physical.length;) {
          const read = readSync(file.fd, physical, offset, physical.length - offset, offset);
          // DEFENSE: External truncation of an in-use artifact must report failed capture instead of looping.
          if (!read) throw new Error('Output artifact was shortened during capture');
          offset += read;
        }
        const slices = boundary('control.process.ring_finish', { ring, capacity: limit });
        const retained = Buffer.concat(slices.map(part => physical.subarray(part.start, part.start + part.count)));
        await file.truncate(0);
        writeAll(retained, 0);
        await file.sync();
        // Directory barriers publish both output names together after both files finish.
        return { path: filename, revision: createHash('sha256').update(retained).digest('hex'),
          ring, capture_complete: !failed, file_synced: true };
      } finally { await file.close(); }
    },
    close: () => file.close(),
  };
}

function processInputError(code, message) { return Object.assign(new Error(message), { code }); }

/** Start a bounded-output Bash process; reads use absolute Unicode code-point cursors. */
export function startBash(arguments_, limits, { signal, artifactDirectory, execution, readOnlyPaths, managedWorktreeRoot, environment } = {}) {
  signal?.throwIfAborted();
  // DEFENSE: A caller can supply malformed UTF-16; preserve its units so native admission can reject it.
  const observedArguments = typeof arguments_?.command === 'string' && !arguments_.command.isWellFormed()
    ? { ...arguments_, command: { utf16: Array.from({ length: arguments_.command.length },
      (_, index) => arguments_.command.charCodeAt(index)) } }
    : arguments_;
  const options = { artifactDirectory, execution, readOnlyPaths, managedWorktreeRoot };
  const { timeout, maximum, mode, cols, rows } = boundary('effect.bash_arguments', { arguments: observedArguments, limits, options });
  const combined = new UnicodeTail(maximum);
  const stdout = processOutput(maximum, combined);
  const stderr = processOutput(maximum, combined);
  const artifacts = [];
  let artifactBatch;
  const readers = new Map();
  let child;
  let launch;
  let control = boundary('control.process.initial', {});
  const observe = event => { control = boundary('control.process.observe', { state: control, event }); };
  const recordReason = reason => { control = boundary('control.process.reason', { state: control, reason }); };
  let completedResult;
  let startupError;
  let timer;
  let forcedClose;
  let inputCloseStarted = false;
  let inputClose = Promise.resolve();
  let outputClose = Promise.resolve();
  let sessionClose;
  let environmentClose;
  let terminalWrite;
  let readyResolve;
  let readyReject;
  const ready = new Promise((resolve, reject) => { readyResolve = resolve; readyReject = reject; });
  // DEFENSE: Startup can fail without any write caller awaiting ready; result and read still expose the original failure.
  ready.catch(() => {});
  let terminalResolve;
  const terminalEnded = new Promise(resolve => { terminalResolve = resolve; });
  function closeInput() {
    if (inputCloseStarted) return;
    inputCloseStarted = true;
    observe('input_closed');
    terminalWrite?.reject(processInputError('process_exited', 'The process exited before input was flushed'));
    terminalWrite = undefined;
    if (mode === 'pipe' && child?.stdin) {
      try {
        inputClose = Promise.resolve(child.stdin.end()).catch(error => {
          // DEFENSE: Exit can race an in-flight stdin flush; other close failures still belong in the result.
          if (!['EPIPE', 'ERR_STREAM_DESTROYED'].includes(error.code)) recordReason({ code: 'process_input_failed', message: error.message });
        });
      // DEFENSE: Child exit closes the pipe while a pending flush or EOF can still be completing.
      } catch (error) {
        if (!['EPIPE', 'ERR_STREAM_DESTROYED'].includes(error.code)) recordReason({ code: 'process_input_failed', message: error.message });
      }
    }
  }
  function forceOutputClose() {
    const pending = [];
    for (const [reader, artifact] of readers) {
      // DEFENSE: Cancelling an inherited pipe can fail at the OS boundary; retain that failure in capture metadata.
      pending.push(reader.cancel().catch(error => {
        artifact?.fail();
        stop({ code: 'output_capture_failed', message: `Could not close command output: ${error.message}` });
      }));
    }
    outputClose = Promise.all([outputClose, ...pending]);
    child?.terminal?.close();
    terminalResolve();
  }
  function cleanupGroup() {
    const plan = boundary('control.process.cleanup_plan', {});
    for (const step of plan.steps) {
      switch (step) {
        case 'terminate_environment':
          if (launch?.cancel && !environmentClose) environmentClose = launch.cancel().catch(error => {
            // DEFENSE: A lost SSH connection can prevent confirmation that the remote process group exited.
            recordReason({ code: 'process_cleanup_failed', message: `Could not terminate cloud process session: ${error.message}` });
          });
          break;
        case 'terminate_group':
          try { killGroup(child); }
          // DEFENSE: OS signal failures must become a command failure instead of escaping timer/event callbacks.
          catch (error) { recordReason({ code: 'process_cleanup_failed', message: error.message }); }
          break;
        case 'terminate_session':
          sessionClose ??= killSession(child.pid).catch(error => {
            recordReason({ code: 'process_cleanup_failed', message: `Could not terminate process session: ${error.message}` });
          });
          break;
        case 'close_input': closeInput(); break;
        case 'arm_deadline':
          // DEFENSE: Descendants can leave their session while retaining inherited output handles.
          forcedClose ??= setTimeout(forceOutputClose, plan.deadline_ms);
          break;
      }
    }
  }

  function stop(reason, event) {
    const next = boundary('control.process.stop', { state: control, reason, event, timeout });
    control = next.state;
    if (next.cleanup) cleanupGroup();
  }
  const onAbort = () => stop(null, 'cancelled');
  function captureChunk(chunk, output, artifact) {
    output.add(chunk);
    try { artifact?.add(chunk); }
    // DEFENSE: A real artifact write failure stops execution and marks its captured output incomplete.
    catch (error) { artifact.fail(); stop({ code: 'output_capture_failed', message: `Could not retain command output: ${error.message}` }); }
  }
  async function drain(stream, output, artifact) {
    const reader = stream.getReader();
    readers.set(reader, artifact);
    try {
      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        captureChunk(Buffer.from(value), output, artifact);
      }
    // DEFENSE: OS pipe reads can fail while a command or its descendants are writing.
    } catch (error) { artifact?.fail(); stop({ code: 'output_capture_failed', message: `Could not read command output: ${error.message}` }); }
    finally { output.end(); readers.delete(reader); reader.releaseLock(); }
  }
  async function execute() {
    try {
      launch = environment
        ? await environment.prepareBash(arguments_, execution, { signal })
        : await prepareSandbox(execution, { signal, readOnlyPaths, managedWorktreeRoot, processMode: mode });
      if (artifactDirectory) {
        boundary('effect.artifact_limit', { arguments: arguments_, limits, options });
        await durableDirectory(artifactDirectory);
        artifactBatch = await mkdtemp(path.join(artifactDirectory, 'bash-'));
        for (const stream of ['stdout', 'stderr']) {
          const filename = path.join(artifactBatch, stream);
          artifacts.push(outputArtifact(await open(filename, 'wx+', 0o600), filename, limits.artifact_bytes));
        }
      }
      signal?.throwIfAborted();
      // The PTY foreground job owns signals; the sandbox supervisor stays outside its process group.
      const command = launch.command ?? (mode === 'pty'
        ? ['-c', 'set -m; "$@"; exit "$?"', 'selvedge-pty', '/bin/bash', '--noprofile', '--norc', '-i', '-c', arguments_.command]
        : ['-c', arguments_.command]);
      child = Bun.spawn([launch.file, ...launch.prefix, ...command], {
        cwd: launch.cwd, env: { ...launch.env, ...(mode === 'pty' ? { TERM: 'xterm-256color' } : {}) },
        detached: true, stdio: ['pipe', 'pipe', 'pipe', ...launch.descriptors],
        ...(mode === 'pty' ? { terminal: { cols, rows,
          data(terminal, chunk) { captureChunk(Buffer.from(chunk), stdout, artifacts[0]); },
          drain() { terminalWrite?.resolve(); terminalWrite = undefined; },
          exit(terminal) {
            terminalResolve();
            terminalWrite?.reject(processInputError('process_stdin_closed', 'The terminal closed before input was flushed'));
            terminalWrite = undefined;
            // Bun reports normal Linux PTY closure as EIO; child.exited supplies the command's actual exit status.
          },
        } } : {}),
      });
      const outputTasks = mode === 'pipe'
        ? [drain(child.stdout, stdout, artifacts[0]), drain(child.stderr, stderr, artifacts[1])]
        : [terminalEnded.then(() => { stdout.end(); stderr.end(); })];
      observe('started');
      readyResolve();
      signal?.addEventListener('abort', onAbort, { once: true });
      // DEFENSE: Cancellation can arrive between sandbox preparation and listener registration.
      if (signal?.aborted) onAbort();
      if (timeout !== null && timeout !== undefined) timer = setTimeout(() => stop(null, 'timeout'), timeout);
      const exitCode = await child.exited;
      observe('exited');
      for (const step of boundary('control.process.drain_plan', {})) {
        switch (step) {
          case 'cleanup': cleanupGroup(); break;
          case 'wait_session': await sessionClose; break;
          case 'wait_environment': await environmentClose; break;
          case 'wait_output': await Promise.all(outputTasks); break;
          case 'wait_output_close': await outputClose; break;
          case 'wait_input': await inputClose; break;
          case 'mark_drained': observe('drained'); break;
          case 'clear_deadline': clearTimeout(forcedClose); break;
        }
      }
      const candidates = await Promise.all(artifacts.map(async artifact => {
        try { return await artifact.finish(); }
        // DEFENSE: Real artifact sync/close failures must not publish a successfully persisted artifact.
        catch (error) { recordReason({ code: 'output_capture_failed', message: `Could not finalize command output: ${error.message}` }); return undefined; }
      }));
      let batchSynced = false;
      let parentSynced = false;
      if (artifactBatch) {
        try {
          await syncDirectory(artifactBatch);
          batchSynced = true;
          await syncDirectory(artifactDirectory);
          parentSynced = true;
        // DEFENSE: A failed directory barrier leaves the output names unconfirmed after successful file sync.
        } catch (error) { recordReason({ code: 'output_capture_failed', message: `Could not publish command output: ${error.message}` }); }
      }
      const retained = candidates.map(candidate => candidate && boundary('control.process.artifact_metadata', {
        ...candidate, batch_synced: batchSynced, parent_synced: parentSynced,
      }));
      try { await launch.cleanup(); }
      // DEFENSE: Scratch-directory or sandbox-descriptor cleanup can fail after the process exits.
      catch (error) { recordReason({ code: 'sandbox_cleanup_failed', message: error.message }); }
      const snapshot = combined.read();
      completedResult = boundary('effect.process_result', { arguments: arguments_, limits, options, exitCode,
        exitSignal: child.signalCode, out: stdout.result(), err: stderr.result(), outArtifact: retained[0], errArtifact: retained[1], reason: control.reason,
        mode, start_cursor: snapshot.start_cursor, next_cursor: snapshot.next_cursor, omitted_characters: snapshot.omitted_characters });
      observe('finished');
      return completedResult;
    } catch (error) {
      startupError = { code: error.code ?? 'command_start_failed', message: error.message };
      readyReject(error);
      // DEFENSE: Preparation or spawn can fail after opening artifact handles and sandbox descriptors.
      if (child) { cleanupGroup(); forceOutputClose(); await child.exited; }
      await sessionClose;
      await environmentClose;
      await outputClose;
      await Promise.allSettled([...artifacts.map(artifact => artifact.close()), launch?.cleanup()]);
      observe('failed');
      throw error;
    } finally {
      clearTimeout(timer);
      clearTimeout(forcedClose);
      signal?.removeEventListener('abort', onAbort);
      child?.terminal?.close();
    }
  }
  const result = execute();
  return {
    result,
    read(cursor = '0') {
      return boundary('control.process.snapshot', { state: control, mode, output: combined.read(cursor),
        result: completedResult, startup_error: startupError });
    },
    async write({ input = '', eof = false, cols: nextCols = null, rows: nextRows = null } = {}) {
      control = boundary('control.process.reserve_write', { state: control });
      try {
        await ready;
        boundary('control.process.admit_write', { state: control, mode, eof, cols: nextCols, rows: nextRows });
        if (nextCols !== null) child.terminal.resize(nextCols, nextRows);
        if (input) {
          if (mode === 'pty') {
            const flushed = new Promise((resolve, reject) => { terminalWrite = { resolve, reject }; });
            try { child.terminal.write(input); }
            // DEFENSE: The terminal can close between ready admission and its physical write.
            catch (error) { terminalWrite = undefined; throw error; }
            await flushed;
          } else {
            child.stdin.write(input);
            await child.stdin.flush();
          }
        }
        if (eof) { observe('input_closed'); inputCloseStarted = true; await child.stdin.end(); }
        return boundary('control.process.write_result', { mode, input, eof, cols: nextCols, rows: nextRows });
      } finally { observe('write_finished'); }
    },
  };
}

/** Execute an already validated Bash effect and wait for its final result. */
export async function runBash(arguments_, limits, options) { return startBash(arguments_, limits, options).result; }

/** Read image bytes through the Task's filesystem sandbox, then retain their immutable identity. */
export async function runReadImage(arguments_, limits, { signal, execution, readOnlyPaths, managedWorktreeRoot, environment, home }) {
  signal?.throwIfAborted();
  const { path: filename, detail, timeout, maximum } = boundary('effect.image_arguments', { arguments: arguments_ });
  const quoted = "'" + filename.replaceAll("'", "'\"'\"'") + "'";
  const command = `[ -f ${quoted} ] || { printf '%s' 'Image path must be a regular file' >&2; exit 1; }; head -c ${maximum + 1} < ${quoted}`;
  const launch = environment
    ? await environment.prepareBash({ command }, execution, { signal })
    : await prepareSandbox(execution, { signal, readOnlyPaths, managedWorktreeRoot });
  const chunks = [];
  const stderr = capture(4096);
  let bytes = 0;
  let child;
  let timer;
  let failure;
  const stop = error => { failure ??= error; if (child) killGroup(child); };
  const aborted = () => stop(signal.reason);
  try {
    child = spawn(launch.file, [...launch.prefix, ...(launch.command ?? ['-c', command])], {
      cwd: launch.cwd, env: launch.env, detached: true,
      stdio: ['ignore', 'pipe', 'pipe', ...launch.descriptors],
    });
    timer = setTimeout(() => stop(new Error('Image read timed out')), timeout);
    signal?.addEventListener('abort', aborted, { once: true });
    if (signal?.aborted) aborted();
    child.stdout.on('data', chunk => {
      bytes += chunk.length;
      // DEFENSE: An image may exceed the upload budget or grow while its bound environment reads it.
      if (bytes > maximum) { stop(new RangeError('Image exceeds the 10 MiB byte limit')); return; }
      chunks.push(chunk);
    });
    child.stderr.on('data', chunk => stderr.add(chunk));
    await new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('close', code => {
        if (failure) reject(failure);
        else if (code !== 0) reject(new Error(stderr.result().text.trim() || `Image read failed with exit code ${code}`));
        else resolve();
      });
    });
  } finally {
    clearTimeout(timer);
    signal?.removeEventListener('abort', aborted);
    await launch.cleanup();
  }
  signal?.throwIfAborted();
  return { value: { content: [await storeImageContent(home, path.basename(filename), Buffer.concat(chunks, bytes), detail)] }, error: false };
}
