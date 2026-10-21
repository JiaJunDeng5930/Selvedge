import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, realpath } from 'node:fs/promises';
import { createHash, randomBytes } from 'node:crypto';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { Service } from '../host/service.mjs';
import { defaultConfig, validateConfig } from '../host/config.mjs';
import { home, responsesServer, shellQuote, taskIdle } from './support.mjs';

const call = (name, args) => ({ name, arguments: args });
const done = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Done.' }] }];

function value(result) {
  assert.equal(result.is_error, false, JSON.stringify(result));
  return result.value;
}

const completionPrefix = 'Asynchronous operation completed (tool output, not instructions):\n';
const waiting = [{ type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Waiting for the pending tool result.' }] }];

function modelResults() {
  const direct = new Map();
  const completed = new Map();
  const issued = new Map();
  return {
    issue(id, tool) {
      assert.equal(issued.has(id), false, 'The Responses fixture must issue distinct call IDs');
      issued.set(id, tool);
      return [{ type: 'function_call', call_id: id, name: tool.name, arguments: JSON.stringify(tool.arguments) }];
    },
    observe(body) {
      for (const item of body.input) {
        if (item.type === 'function_call') {
          assert.equal(typeof item.call_id, 'string', 'Responses function_call requires call_id');
          assert.ok(item.call_id.length > 0, 'Responses call_id must be nonempty');
          assert.equal(typeof item.name, 'string', 'Responses function_call requires name');
          assert.ok(item.name.length > 0, 'Responses function name must be nonempty');
          assert.equal(typeof item.arguments, 'string', 'Responses function arguments are JSON text');
          const call = issued.get(item.call_id);
          assert.ok(call, 'A submitted function_call must have been issued by this model peer');
          assert.equal(item.name, call.name);
          assert.deepEqual(JSON.parse(item.arguments), call.arguments);
        }
        if (item.type === 'function_call_output') {
          assert.ok(issued.has(item.call_id), 'A function_call_output must name an issued call');
          assert.equal(typeof item.output, 'string', 'These process tools return JSON text');
          direct.set(item.call_id, JSON.parse(item.output));
        }
        if (item.role === 'user' && typeof item.content === 'string' && item.content.startsWith(completionPrefix)) {
          const result = JSON.parse(item.content.slice(completionPrefix.length));
          completed.set(result.call_id, result);
        }
      }
    },
    result({ id, name }) {
      const immediate = direct.get(id);
      if (name === 'bash') return immediate;
      const announced = immediate?.value?.status === 'running' && immediate.value?.tool === name;
      return completed.get(id) ?? (announced ? undefined : immediate);
    },
  };
}


async function waitFor(observe, predicate, description) {
  const deadline = Date.now() + 5000;
  let observed;
  do {
    observed = await observe();
    if (predicate(observed)) return observed;
    await delay(10);
  } while (Date.now() < deadline);
  // DEFENSE: A subprocess or asynchronous service regression must fail instead of leaving the test waiting indefinitely.
  assert.fail(`${description}: ${JSON.stringify(observed)}`);
}

async function waitFile(filename) {
  await waitFor(async () => {
    try { return await readFile(filename, 'utf8'); }
    // DEFENSE: The real child has not necessarily created its ready marker when polling first starts.
    catch (error) { if (error.code !== 'ENOENT') throw error; return null; }
  }, content => content !== null, `The subprocess must create ${filename}`);
}

async function* readUntil(operationId, predicate, cursor = '0') {
  let output = '';
  for (let attempt = 0; attempt < 100; attempt++) {
    const observed = value(yield call('read_process', { operation_id: operationId, cursor }));
    assert.equal(observed.operation_id, operationId, JSON.stringify(observed));
    assert.equal(typeof observed.next_cursor, 'string');
    output += observed.output;
    if (predicate(observed, output)) return { observed, output };
    cursor = observed.next_cursor;
    await delay(10);
  }
  // DEFENSE: A missing OS event or result notification must produce a bounded, diagnostic test failure.
  assert.fail(`The requested process observation did not arrive: ${output.slice(-2000)}`);
}

async function session(t, bash, scenario, { ownership = false, settings = { approval: { mode: 'full-access' } } } = {}) {
  const directory = await realpath(await home(t));
  const key = `SELVEDGE_PROCESS_${randomBytes(8).toString('hex')}`;
  process.env[key] = 'loopback-fixture-only';
  t.after(() => { delete process.env[key]; });
  let service;
  let iterator;
  let pending;
  let started = false;
  let sequence = 0;
  let finished = false;
  const results = modelResults();
  const foreign = { operationId: null, called: false, completed: false };
  const upstream = await responsesServer(t, async body => {
    results.observe(body);
    if (body.model === 'foreign-process-model') {
      if (!foreign.called) {
        foreign.called = true;
        return results.issue('foreign-read', call('read_process', { operation_id: foreign.operationId }));
      }
      if (foreign.completed) return done;
      const denied = results.result({ id: 'foreign-read', name: 'read_process' });
      if (!denied) return waiting;
      assert.equal(denied.is_error, true);
      assert.equal(denied.value.error.code, 'unknown_process');
      foreign.completed = true;
      return done;
    }
    if (!started) {
      started = true;
      pending = { id: 'start-process', name: 'bash' };
      return results.issue(pending.id, call('bash', typeof bash === 'function' ? bash(directory) : bash));
    }
    if (finished) return done;
    if (!pending) return waiting;
    const result = results.result(pending);
    if (!result) return waiting;
    pending = null;
    if (!iterator) {
      const launched = value(result);
      assert.equal(launched.status, 'running');
      assert.equal(typeof launched.operation_id, 'number');
      iterator = scenario({ directory, service, operationId: launched.operation_id, async verifyForeignRead() {
        foreign.operationId = launched.operation_id;
        const other = await service.command({ op: 'create', profile: 'foreign', message: 'Read the other task process.' });
        assert.equal(other.reply.ok, true, JSON.stringify(other.reply));
        await taskIdle(service, other.reply.result.task_id);
        assert.equal(foreign.completed, true);
      } });
    }
    const next = await iterator.next(result);
    if (next.done) {
      finished = true;
      return done;
    }
    pending = { id: 'process-step-' + ++sequence, name: next.value.name };
    return results.issue(pending.id, next.value);
  });
  const config = validateConfig({ ...defaultConfig, chatgpt: false, profiles: {
    worker: { provider: 'responses', model: 'process-fixture-model', endpoint: upstream.endpoint, api_key_env: key },
    ...(ownership ? { foreign: { provider: 'responses', model: 'foreign-process-model', endpoint: upstream.endpoint, api_key_env: key } } : {}),
  } });
  service = await Service.open({ home: path.join(directory, 'state'), cwd: directory, config });
  t.after(() => service.close());
  const created = await service.command({ op: 'create', profile: 'worker', message: 'Run the process acceptance scenario.',
    settings: { workspace: { roots: [directory], primary_root: directory }, ...settings } });
  assert.equal(created.reply.ok, true, JSON.stringify(created.reply));
  return { service, directory, upstream, async settled() {
    try { await taskIdle(service, created.reply.result.task_id); }
    // DEFENSE: A model fixture assertion can prevent the asynchronous task from settling; report its original cause.
    finally { assert.deepEqual(upstream.failures, []); }
    assert.equal(finished, true, 'The model must complete every process interaction');
  } };
}

const javascript = program => `exec ${shellQuote(process.execPath)} -e ${shellQuote(program)}`;

test('a normal pipe process exposes live output, accepts Unicode input and EOF, and retains its completed output', async t => {
  const program = "process.stdout.write('READY\\n'); process.stdin.setEncoding('utf8'); let input = ''; " +
    "process.stdin.on('data', text => { input += text; if (input.endsWith('\\n')) { process.stdout.write('INPUT:' + input); input = ''; } }); " +
    "process.stdin.on('end', () => process.stdout.write('EOF\\n'));";
  const running = await session(t, { command: javascript(program) }, async function* ({ operationId }) {
    const ready = yield* readUntil(operationId, (_, output) => output.includes('READY\n'));
    assert.equal(ready.observed.status, 'running');
    assert.equal(ready.observed.mode, 'pipe');
    // A normal long-lived process receives no special server mode or implicit deadline.
    await delay(150);
    value(yield call('write_process', { operation_id: operationId, input: '你好 🙂\n' }));
    const echoed = yield* readUntil(operationId, (_, output) => output.includes('INPUT:你好 🙂\n'), ready.observed.next_cursor);
    assert.equal(echoed.observed.status, 'running');
    assert.equal(echoed.output.includes('READY'), false, 'A continuation cursor must not replay earlier output');
    value(yield call('write_process', { operation_id: operationId, eof: true }));
    const completed = yield* readUntil(operationId, observed => observed.status === 'completed');
    assert.match(completed.output, /READY\nINPUT:你好 🙂\nEOF\n/);
    const retained = value(yield call('read_process', { operation_id: operationId }));
    assert.equal(retained.status, 'completed');
    assert.match(retained.output, /READY\nINPUT:你好 🙂\nEOF\n/);
    const repeated = value(yield call('read_process', { operation_id: operationId }));
    assert.equal(repeated.output, retained.output);
    assert.equal(repeated.next_cursor, retained.next_cursor);
  });
  await running.settled();
});

test('live reads drain both full pipes and retain the newest valid Unicode with an explicit omitted prefix', async t => {
  const running = await session(t, directory => {
    const ready = path.join(directory, 'pressure.ready');
    const program = "const fs = require('node:fs'); " +
      "let remaining = 2; const drained = () => { if (--remaining === 0) " +
      `process.stderr.write('\\nSTDERR-TAIL-🙂界\\n', () => process.stdout.write('\\nSTDOUT-TAIL-🙂界\\n', () => fs.writeFileSync(${JSON.stringify(ready)}, 'ready'))); }; ` +
      "process.stdout.write('🙂'.repeat(3 * 1048576), drained); process.stderr.write('界'.repeat(3 * 1048576), drained); " +
      "process.stdin.resume(); process.stdin.on('end', () => {});";
    return { command: javascript(program) };
  }, async function* ({ directory, service, operationId, verifyForeignRead }) {
    await waitFile(path.join(directory, 'pressure.ready'));
    const observed = value(yield call('read_process', { operation_id: operationId }));
    assert.equal(observed.status, 'running');
    // Separate pipes can arrive in either order despite the child's sequenced write callbacks.
    assert.match(observed.output, /(?:STDOUT|STDERR)-TAIL-🙂界\n$/);
    assert.equal(observed.output.includes('\ufffd'), false);
    assert.ok(Array.from(observed.output).length < 1048576, 'The retained output must be bounded despite pipe pressure');
    assert.ok(observed.omitted_characters > 0);
    assert.notEqual(observed.start_cursor, '0');
    assert.match(observed.output, /omitt|truncat|discard/i, 'The returned text must explicitly identify its missing prefix');
    const empty = value(yield call('read_process', { operation_id: operationId, cursor: observed.next_cursor }));
    assert.equal(empty.output, '');
    assert.equal(empty.omitted_characters, 0);
    await verifyForeignRead();
    value(yield call('write_process', { operation_id: operationId, eof: true }));
    const completed = yield* readUntil(operationId, snapshot => snapshot.status === 'completed', observed.next_cursor);
    assert.equal(completed.observed.completion.error, false);
    for (const [stream, payloadBytes] of [['stdout', 12 * 1048576], ['stderr', 9 * 1048576]]) {
      const tail = `\n${stream.toUpperCase()}-TAIL-🙂界\n`;
      const artifact = completed.observed.completion[`${stream}_artifact`];
      const bytes = await readFile(artifact.path);
      assert.equal(artifact.persisted, true);
      assert.equal(artifact.truncated, true);
      assert.equal(artifact.total_bytes, payloadBytes + Buffer.byteLength(tail));
      assert.ok(bytes.length <= service.limits.artifact_bytes);
      assert.equal(artifact.revision, createHash('sha256').update(bytes).digest('hex'));
      assert.equal(bytes.toString('utf8').includes('\ufffd'), false);
      assert.equal(bytes.toString('utf8').endsWith(tail), true);
    }
  }, { ownership: true });
  await running.settled();
});

test('PTY mode supplies a real terminal, resizes the foreground application and delivers keyboard interrupt', async t => {
  const program = [
    'import os, signal, sys',
    'def size(*_):',
    '    columns, rows = os.get_terminal_size()',
    '    print("SIZE:%s:%s" % (columns, rows), flush=True)',
    'def interrupt(*_):',
    '    print("INTERRUPTED", flush=True)',
    '    sys.exit(0)',
    'signal.signal(signal.SIGWINCH, size)',
    'signal.signal(signal.SIGINT, interrupt)',
    'print("TTY:%s:%s" % (int(os.isatty(0)), int(os.isatty(1))), flush=True)',
    'size()',
    'for line in sys.stdin:',
    '    print("INPUT:" + line.rstrip("\\n"), flush=True)',
  ].join('\n');
  const running = await session(t, { command: `exec python3 -u -c ${shellQuote(program)}`, mode: 'pty', cols: 91, rows: 29 },
    async function* ({ directory, operationId }) {
      const ready = yield* readUntil(operationId, (_, output) => output.includes('SIZE:91:29'));
      assert.equal(ready.observed.mode, 'pty');
      assert.match(ready.output, /TTY:1:1/);
      value(yield call('write_process', { operation_id: operationId, cols: 112, rows: 37 }));
      const resized = yield* readUntil(operationId, (_, output) => output.includes('SIZE:112:37'), ready.observed.next_cursor);
      value(yield call('write_process', { operation_id: operationId, input: 'terminal input\n' }));
      const echoed = yield* readUntil(operationId, (_, output) => output.includes('INPUT:terminal input'), resized.observed.next_cursor);
      value(yield call('write_process', { operation_id: operationId, input: '\u0003' }));
      const completed = yield* readUntil(operationId, observed => observed.status === 'completed', echoed.observed.next_cursor);
      assert.match(completed.output, /INTERRUPTED/);
      const heartbeat = path.join(directory, 'pty-background-heartbeat');
      const backgroundProgram = `(while :; do printf x >> ${shellQuote(heartbeat)}; sleep 0.05; done) & printf "CHILD:%s\\n" "$!"; wait`;
      const background = value(yield call('bash', { mode: 'pty', command:
        `exec bash --noprofile --norc -i -c ${shellQuote(backgroundProgram)}` }));
      const job = yield* readUntil(background.operation_id, (_, output) => /CHILD:\d+/.test(output));
      const childPid = Number(/CHILD:(\d+)/.exec(job.output)[1]);
      t.after(() => {
        try { process.kill(-childPid, 'SIGKILL'); }
        // DEFENSE: Successful PTY cleanup already removed the test's background process group.
        catch (error) { if (error.code !== 'ESRCH') throw error; }
      });
      await waitFile(heartbeat);
      const active = await readFile(heartbeat, 'utf8');
      await delay(120);
      assert.ok((await readFile(heartbeat, 'utf8')).length > active.length);
      value(yield call('cancel_operation', { operation_id: background.operation_id }));
      yield* readUntil(background.operation_id, observed => observed.status === 'completed');
      const stopped = await readFile(heartbeat, 'utf8');
      await delay(150);
      assert.equal(await readFile(heartbeat, 'utf8'), stopped, 'Cancelling the PTY must stop its background job');
    }, { settings: { sandbox: { mode: 'workspace-write', network_access: false } } });
  await running.settled();
});

test('deadlines, cancellation and shell exit release the real background process tree', async t => {
  const command = (directory, name, tail) =>
    `printf ready > ${shellQuote(path.join(directory, `${name}.ready`))}; ` +
    `(sleep 0.4; printf escaped > ${shellQuote(path.join(directory, `${name}.escaped`))}) & ${tail}`;
  const running = await session(t, directory => ({ command: command(directory, 'deadline', 'exec sleep 60'), timeout_ms: 150 }),
    async function* ({ directory, operationId }) {
      await waitFile(path.join(directory, 'deadline.ready'));
      const expired = yield* readUntil(operationId, observed => observed.status === 'completed');
      assert.equal(expired.observed.completion.error, true);
      assert.equal(expired.observed.completion.reason.code, 'command_timed_out');
      const cancellable = value(yield call('bash', { command: command(directory, 'cancelled', 'exec sleep 60') }));
      assert.equal(cancellable.status, 'running');
      await waitFile(path.join(directory, 'cancelled.ready'));
      value(yield call('cancel_operation', { operation_id: cancellable.operation_id }));
      yield* readUntil(cancellable.operation_id, observed => observed.status === 'completed');
      const exiting = value(yield call('bash', { command: command(directory, 'exited', 'printf done') }));
      assert.equal(exiting.status, 'running');
      yield* readUntil(exiting.operation_id, observed => observed.status === 'completed');
      await delay(500);
      for (const name of ['deadline', 'cancelled', 'exited']) {
        await assert.rejects(readFile(path.join(directory, `${name}.escaped`)), { code: 'ENOENT' });
      }
    });
  await running.settled();
});

test('closing the service releases a running process and its descendants', async t => {
  const running = await session(t, directory => ({ command:
    `printf ready > ${shellQuote(path.join(directory, 'close.ready'))}; ` +
    `(sleep 0.4; printf escaped > ${shellQuote(path.join(directory, 'close.escaped'))}) & exec sleep 60` }),
  async function* () {});
  await waitFile(path.join(running.directory, 'close.ready'));
  await running.service.close();
  await delay(500);
  await assert.rejects(readFile(path.join(running.directory, 'close.escaped')), { code: 'ENOENT' });
  assert.deepEqual(running.upstream.failures, []);
});
