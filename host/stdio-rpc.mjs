import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { parseJson, stringifyJson } from './codec.mjs';
import { capture, killGroup } from './process.mjs';

/** Bounded, language-neutral transport. It has no agent or extension policy. */
export class StdioRpc extends EventEmitter {
  #child;
  #pending = new Map();
  #nextId = 1;
  #parts = [];
  #bytes = 0;
  #failure;
  #closing = false;

  get available() { return !this.#failure && !this.#closing; }

  constructor(name, config, limits, { label = 'RPC', timeoutMs = 30_000, maxPending = 128 } = {}) {
    super();
    Object.assign(this, { name, config, limits, label, timeoutMs: config.timeout_ms ?? timeoutMs, maxPending });
    this.stderr = capture(limits.tool_output_bytes);
    this.#child = spawn(config.command, config.args ?? [], {
      cwd: config.cwd ?? process.cwd(), env: { ...process.env, ...config.env }, detached: true, stdio: ['pipe', 'pipe', 'pipe'],
    });
    this.#child.stdout.on('data', chunk => this.#read(chunk));
    this.#child.stderr.on('data', chunk => this.stderr.add(chunk));
    this.#child.on('error', error => this.#fail(error));
    this.#child.stdin.on('error', error => this.#fail(error));
    this.closed = new Promise(resolve => {
      this.#child.once('exit', () => { try { killGroup(this.#child); } catch {} });
      this.#child.once('close', (code, signal) => {
        if (!this.#closing) this.#fail(new Error(`${label} ${name} exited (${signal ?? code})`));
        resolve();
      });
    });
  }

  #fail(error) {
    if (this.#failure) return;
    this.#failure = error;
    for (const pending of this.#pending.values()) pending.reject(error);
    this.#pending.clear();
    try { killGroup(this.#child); } catch {}
    this.emit('unavailable', error);
  }

  #write(value) {
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error(`${this.label} ${this.name} is closed`);
    const text = stringifyJson(value);
    const bytes = Buffer.byteLength(text);
    if (bytes > this.limits.frame_bytes) throw new RangeError(`${this.label} request exceeds frame limit`);
    if (this.#child.stdin.writableLength + bytes > this.limits.frame_bytes * 2) throw new Error(`${this.label} outbound queue is full`);
    this.#child.stdin.write(`${text}\n`, error => { if (error) this.#fail(error); });
  }

  notify(method, params) {
    this.#write({ jsonrpc: '2.0', method, ...(params === undefined ? {} : { params }) });
  }

  #read(chunk) {
    let offset = 0;
    while (offset < chunk.length) {
      const newline = chunk.indexOf(10, offset);
      const end = newline < 0 ? chunk.length : newline;
      const piece = chunk.subarray(offset, end);
      this.#parts.push(piece);
      this.#bytes += piece.length;
      if (this.#bytes > this.limits.frame_bytes) { this.#fail(new Error(`${this.label} frame exceeds limit`)); return; }
      if (newline < 0) return;
      try {
        const text = new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(this.#parts, this.#bytes));
        this.#parts = [];
        this.#bytes = 0;
        this.#message(parseJson(text));
      } catch (error) { this.#fail(error); return; }
      offset = newline + 1;
    }
  }

  #message(message) {
    if (!message || Array.isArray(message) || message.jsonrpc !== '2.0') throw new Error(`Malformed ${this.label} JSON-RPC message`);
    if (typeof message.method === 'string') {
      if (message.id !== undefined) {
        this.#write(message.method === 'ping'
          ? { jsonrpc: '2.0', id: message.id, result: {} }
          : { jsonrpc: '2.0', id: message.id, error: { code: -32601, message: 'Client method is not supported' } });
      } else this.emit('notification', message);
      return;
    }
    const pending = this.#pending.get(message.id);
    if (!pending) return; // A late response has no transport or native ticket authority.
    this.#pending.delete(message.id);
    if (Object.hasOwn(message, 'result') === Object.hasOwn(message, 'error')) {
      pending.reject(new Error(`${this.label} response must have exactly one of result or error`));
    } else if (message.error) pending.reject(new Error(`${this.label} ${this.name}: ${message.error.message ?? 'request failed'}`));
    else if (Object.hasOwn(message, 'result')) pending.resolve(message.result);
    else pending.reject(new Error(`Malformed ${this.label} error response`));
  }

  request(method, params, { signal, timeoutMs = this.timeoutMs } = {}) {
    signal?.throwIfAborted();
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#pending.size >= this.maxPending) return Promise.reject(new Error(`${this.label} request queue is full`));
    if (this.#nextId >= Number.MAX_SAFE_INTEGER) return Promise.reject(new Error(`${this.label} request identity exhausted`));
    const id = this.#nextId++;
    return new Promise((resolve, reject) => {
      const finish = callback => value => {
        clearTimeout(timer);
        signal?.removeEventListener('abort', cancel);
        this.#pending.delete(id);
        callback(value);
      };
      const cancel = () => {
        try { this.notify('notifications/cancelled', { requestId: id, reason: 'Client cancelled' }); } catch {}
        finish(reject)(signal?.reason ?? new Error(`${this.label} request cancelled`));
      };
      const timer = setTimeout(() => {
        try { this.notify('notifications/cancelled', { requestId: id, reason: 'Deadline exceeded' }); } catch {}
        finish(reject)(new Error(`${this.label} request timed out after ${timeoutMs} milliseconds; its external outcome may be unknown`));
      }, timeoutMs);
      this.#pending.set(id, { resolve: finish(resolve), reject: finish(reject) });
      signal?.addEventListener('abort', cancel, { once: true });
      if (signal?.aborted) { cancel(); return; }
      try { this.#write({ jsonrpc: '2.0', id, method, params }); }
      catch (error) { finish(reject)(error); }
    });
  }

  async close() {
    if (this.#closing) return this.closed;
    this.#closing = true;
    for (const pending of this.#pending.values()) pending.reject(new Error(`${this.label} connection closed`));
    this.#pending.clear();
    try { killGroup(this.#child); } catch {}
    const timer = setTimeout(() => { this.#child.stdout.destroy(); this.#child.stderr.destroy(); }, 2000);
    await this.closed;
    clearTimeout(timer);
  }
}
