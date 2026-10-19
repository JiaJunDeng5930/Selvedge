import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { parseJson, stringifyJson } from './codec.mjs';
import { capture, killGroup } from './process.mjs';
import { boundary } from './public/model-boundary.mjs';

/** Bounded, language-neutral transport. It has no agent or extension policy. */
export class StdioRpc extends EventEmitter {
  #child;
  #pending = new Map();
  #nextId = 1;
  #parts = [];
  #bytes = 0;
  #failure;
  #closing = false;

  #decide(operation, observation = {}) {
    return boundary(operation, {
      label: this.label, name: this.name,
      state: {
        pending: [...this.#pending.keys()], nextId: this.#nextId,
        failure: this.#failure === undefined ? null : { message: this.#failure.message },
        closing: this.#closing,
      },
      ...observation,
    });
  }

  #apply(decision) {
    this.#nextId = decision.nextId;
    this.#pending = new Map(decision.nextPending.map(id => [id, this.#pending.get(id)]));
  }

  get available() { return this.#decide('rpc.available'); }

  constructor(name, config, limits, { label = 'RPC', timeoutMs = 30_000, maxPending = 128, decodeMessage = message => message, decodeResult = value => value } = {}) {
    super();
    Object.assign(this, { name, config, limits, label, timeoutMs: config.timeout_ms ?? timeoutMs, maxPending });
    this.decodeMessage = decodeMessage;
    this.decodeResult = decodeResult;
    this.stderr = capture(limits.tool_output_bytes);
    this.#child = spawn(config.command, config.args ?? [], {
      cwd: config.cwd ?? process.cwd(), env: { ...process.env, ...config.env }, detached: true, stdio: ['pipe', 'pipe', 'pipe'],
    });
    this.#child.stdout.on('data', chunk => this.#read(chunk));
    this.#child.stderr.on('data', chunk => this.stderr.add(chunk));
    this.#child.on('error', error => this.#fail(error));
    this.#child.stdin.on('error', error => this.#fail(error));
    this.closed = new Promise(resolve => {
      this.#child.once('exit', () => killGroup(this.#child));
      this.#child.once('close', (code, signal) => {
        // DEFENSE: Bun emits an undefined close signal when spawn fails (for example ENOENT); observe the absent signal as null.
        const decision = this.#decide('rpc.exit', { code, signal: signal ?? null });
        // DEFENSE: A plugin/MCP process can exit before pending replies arrive; reject those requests and withdraw its routes.
        if (decision.action === 'fail') this.#fail(new Error(decision.error));
        resolve();
      });
    });
  }

  #fail(error) {
    const decision = this.#decide('rpc.lifecycle', { event: 'failure' });
    // DEFENSE: One process failure can raise stdin, child-error and close events; retire its requests only once.
    if (decision.action === 'ignore') return;
    const retiring = decision.retired.map(id => this.#pending.get(id));
    this.#failure = error;
    this.#apply(decision);
    for (const pending of retiring) pending.reject(error);
    killGroup(this.#child);
    this.emit('unavailable', error);
  }

  #write(value) {
    // Serialization is an external observation and follows native availability
    // admission, preserving the original failure ordering.
    const preflight = this.#decide('rpc.write', { message: value, bytes: 0, queuedBytes: 0, frameLimit: this.limits.frame_bytes });
    // DEFENSE: An earlier pipe/process error may have retired this connection before a queued callback attempts a write.
    if (preflight.action === 'external_failure') throw this.#failure;
    const text = stringifyJson(preflight.message);
    try {
      this.#decide('rpc.write', {
        message: preflight.message, bytes: Buffer.byteLength(text),
        queuedBytes: this.#child.stdin.writableLength, frameLimit: this.limits.frame_bytes,
      });
    } catch (error) {
      // DEFENSE: An external request payload can exceed the RPC frame budget; expose the transport's range rejection as RangeError.
      if (error.code === 'range') throw new RangeError(error.message);
      throw error;
    }
    this.#child.stdin.write(`${text}\n`, error => {
      // DEFENSE: The child can close stdin after the write was queued; fail pending requests instead of leaving them unresolved.
      if (error) this.#fail(error);
    });
  }

  notify(method, params) {
    this.#write(this.#decide('rpc.notification', { method, params }).message);
  }

  #read(chunk) {
    let offset = 0;
    while (offset < chunk.length) {
      const newline = chunk.indexOf(10, offset);
      const end = newline < 0 ? chunk.length : newline;
      const piece = chunk.subarray(offset, end);
      this.#parts.push(piece);
      this.#bytes += piece.length;
      try { this.#decide('rpc.frame', { bytes: this.#bytes, frameLimit: this.limits.frame_bytes }); }
      // DEFENSE: A peer can emit an oversized or unterminated line; stop reading before buffering beyond the frame budget.
      catch (error) { this.#fail(error); return; }
      if (newline < 0) return;
      try {
        const text = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(this.#parts, this.#bytes));
        this.#parts = [];
        this.#bytes = 0;
        this.#message(parseJson(text));
      // DEFENSE: Peer stdout can contain malformed UTF-8, JSON or JSON-RPC; retire this transport rather than accept an uncorrelated result.
      } catch (error) { this.#fail(error); return; }
      offset = newline + 1;
    }
  }

  #message(message) {
    const decision = this.#decide('rpc.message', { message: this.decodeMessage(message) });
    const execute = {
      ignore: () => {},
      notify: () => this.emit('notification', decision.message),
      write: () => this.#write(decision.message),
      resolve: () => {
        const pending = this.#pending.get(decision.id);
        this.#apply(decision);
        pending.resolve(this.decodeResult(decision.value, message));
      },
      reject: () => {
        const pending = this.#pending.get(decision.id);
        this.#apply(decision);
        pending.reject(new Error(decision.error));
      },
    };
    execute[decision.action]();
  }

  request(method, params, { signal, timeoutMs = this.timeoutMs } = {}) {
    let decision;
    try { decision = this.#decide('rpc.request', { method, params, maxPending: this.maxPending, aborted: signal?.aborted ?? false }); }
    // DEFENSE: Queue pressure, exhausted request identities or a closed process can reject a new RPC call; report it through the request promise.
    catch (error) { return Promise.reject(error); }
    // DEFENSE: The task may have been cancelled or the process may have failed before this RPC starts.
    if (decision.action === 'abort') signal.throwIfAborted();
    if (decision.action === 'external_failure') return Promise.reject(this.#failure);
    const id = decision.id;
    return new Promise((resolve, reject) => {
      const finish = callback => value => {
        clearTimeout(timer);
        signal?.removeEventListener('abort', cancel);
        callback(value);
      };
      const retire = reason => {
        const retirement = this.#decide('rpc.retire', {
          id, reason, timeoutMs, externalReason: signal?.reason !== undefined && signal?.reason !== null,
        });
        if (retirement.action === 'ignore') return;
        const pending = this.#pending.get(retirement.id);
        this.#apply(retirement);
        try { this.#write(retirement.message); }
        // DEFENSE: A full or failed pipe can prevent the cancellation notification; withdraw the connection and keep the request's cancellation/timeout result.
        catch (error) { this.#fail(error); }
        pending.reject(retirement.externalReason ? signal.reason : new Error(retirement.error));
      };
      const cancel = () => retire('cancel');
      const timer = setTimeout(() => retire('timeout'), timeoutMs);
      this.#pending.set(id, { resolve: finish(resolve), reject: finish(reject) });
      this.#apply(decision);
      signal?.addEventListener('abort', cancel, { once: true });
      try { this.#write(decision.message); }
      // DEFENSE: A request larger than the frame/pipe budget must retire its allocated promise and reject the caller.
      catch (error) {
        const retirement = this.#decide('rpc.finish', { id });
        const pending = this.#pending.get(retirement.id);
        this.#apply(retirement);
        pending.reject(error);
      }
    });
  }

  async close() {
    const decision = this.#decide('rpc.lifecycle', { event: 'close' });
    // DEFENSE: Initialization cleanup and service shutdown may both close the same transport.
    if (decision.action === 'ignore') return this.closed;
    const retiring = decision.retired.map(id => this.#pending.get(id));
    this.#closing = true;
    this.#apply(decision);
    for (const pending of retiring) pending.reject(new Error(decision.error));
    killGroup(this.#child);
    // DEFENSE: Descendants can retain inherited stdout/stderr after the parent exits; bound shutdown's wait for those pipes.
    const timer = setTimeout(() => { this.#child.stdout.destroy(); this.#child.stderr.destroy(); }, 2000);
    await this.closed;
    clearTimeout(timer);
  }
}
