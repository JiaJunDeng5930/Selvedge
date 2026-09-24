import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { parseJson, stringifyJson } from './codec.mjs';
import { capture, killGroup } from './process.mjs';

const supportedVersions = new Set(['2024-11-05', '2025-03-26', '2025-06-18', '2025-11-25']);
const normalize = name => name.replace(/[^A-Za-z0-9_]/g, '_');

/** A bounded JSON-RPC stdio connection; task policy remains in Bend. */
export class Mcp extends EventEmitter {
  #child;
  #pending = new Map();
  #nextId = 1;
  #parts = [];
  #bytes = 0;
  #failure;
  #closing = false;

  constructor(name, config, limits) {
    super();
    this.name = name;
    this.config = config;
    this.limits = limits;
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
        if (!this.#closing) this.#fail(new Error(`MCP ${name} exited (${signal ?? code})`));
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
    if (this.#closing) throw new Error(`MCP ${this.name} is closed`);
    const text = stringifyJson(value);
    if (Buffer.byteLength(text) > this.limits.frame_bytes) throw new RangeError('MCP request exceeds frame limit');
    if (this.#child.stdin.writableLength + Buffer.byteLength(text) > this.limits.frame_bytes * 2) {
      throw new Error('MCP outbound queue is full');
    }
    this.#child.stdin.write(`${text}\n`, error => { if (error) this.#fail(error); });
  }

  #read(chunk) {
    let offset = 0;
    while (offset < chunk.length) {
      const newline = chunk.indexOf(10, offset);
      const end = newline < 0 ? chunk.length : newline;
      const piece = chunk.subarray(offset, end);
      this.#parts.push(piece);
      this.#bytes += piece.length;
      if (this.#bytes > this.limits.frame_bytes) { this.#fail(new Error('MCP frame exceeds limit')); return; }
      if (newline < 0) return;
      const text = Buffer.concat(this.#parts, this.#bytes).toString('utf8');
      this.#parts = [];
      this.#bytes = 0;
      try { this.#message(parseJson(text)); }
      catch (error) { this.#fail(error); return; }
      offset = newline + 1;
    }
  }

  #message(message) {
    if (!message || message.jsonrpc !== '2.0') throw new Error('Malformed MCP JSON-RPC message');
    if (typeof message.method === 'string') {
      if (message.id !== undefined) {
        this.#write(message.method === 'ping'
          ? { jsonrpc: '2.0', id: message.id, result: {} }
          : { jsonrpc: '2.0', id: message.id, error: { code: -32601, message: 'Client method is not supported' } });
      } else if (message.method === 'notifications/tools/list_changed') this.emit('toolsChanged');
      return;
    }
    const pending = this.#pending.get(message.id);
    if (!pending) return; // Timed-out or cancelled replies carry no new task authority.
    this.#pending.delete(message.id);
    if (message.error) pending.reject(new Error(`MCP ${this.name}: ${message.error.message ?? 'request failed'}`));
    else if (Object.hasOwn(message, 'result')) pending.resolve(message.result);
    else pending.reject(new Error('MCP response has neither result nor error'));
  }

  request(method, params, { signal } = {}) {
    signal?.throwIfAborted();
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#nextId >= Number.MAX_SAFE_INTEGER) return Promise.reject(new Error('MCP request identity exhausted'));
    const id = this.#nextId++;
    const timeout = this.config.timeout_ms ?? this.limits.mcp_timeout_ms;
    return new Promise((resolve, reject) => {
      const finish = callback => value => {
        clearTimeout(timer);
        signal?.removeEventListener('abort', cancel);
        this.#pending.delete(id);
        callback(value);
      };
      const cancel = () => {
        try { this.#write({ jsonrpc: '2.0', method: 'notifications/cancelled', params: { requestId: id, reason: 'Client cancelled' } }); } catch {}
        finish(reject)(signal?.reason ?? new Error('MCP request cancelled'));
      };
      const timer = setTimeout(() => {
        try { this.#write({ jsonrpc: '2.0', method: 'notifications/cancelled', params: { requestId: id, reason: 'Deadline exceeded' } }); } catch {}
        finish(reject)(new Error(`MCP request timed out after ${timeout} milliseconds; its external outcome may be unknown`));
      }, timeout);
      this.#pending.set(id, { resolve: finish(resolve), reject: finish(reject) });
      signal?.addEventListener('abort', cancel, { once: true });
      if (signal?.aborted) { cancel(); return; }
      try { this.#write({ jsonrpc: '2.0', id, method, params }); }
      catch (error) { finish(reject)(error); }
    });
  }

  async initialize() {
    const initialized = await this.request('initialize', {
      protocolVersion: '2025-11-25', capabilities: {}, clientInfo: { name: 'selvedge-bend', version: '0.1.0' },
    });
    if (!supportedVersions.has(initialized?.protocolVersion)) throw new Error('MCP server selected an unsupported protocol version');
    this.#write({ jsonrpc: '2.0', method: 'notifications/initialized' });
    return this.discover();
  }

  async discover() {
    const tools = [];
    const cursors = new Set();
    const names = new Set();
    let cursor;
    let size = 0;
    do {
      const page = await this.request('tools/list', cursor === undefined ? {} : { cursor });
      if (!Array.isArray(page?.tools)) throw new Error('MCP tools/list did not return tools');
      for (const tool of page.tools) {
        if (typeof tool.name !== 'string' || !tool.name || !tool.inputSchema || typeof tool.inputSchema !== 'object' || Array.isArray(tool.inputSchema)) {
          throw new Error('MCP returned an invalid tool definition');
        }
        if (tool.execution?.taskSupport === 'required') throw new Error(`MCP tool ${tool.name} requires unsupported task-mode execution`);
        const name = `mcp__${normalize(this.name)}__${normalize(tool.name)}`;
        if (names.has(name)) throw new Error(`MCP tool name collision: ${name}`);
        names.add(name);
        const entry = { name, description: tool.description || `Call ${this.name}/${tool.name}`, schema: tool.inputSchema, server: this.name, remote: tool.name };
        size += Buffer.byteLength(stringifyJson(entry));
        tools.push(entry);
        if (tools.length > this.limits.mcp_catalog_tools || size > this.limits.frame_bytes) throw new Error('MCP catalog exceeds limits');
      }
      cursor = page.nextCursor;
      if (cursor !== undefined && (typeof cursor !== 'string' || cursors.has(cursor))) throw new Error('MCP returned an invalid or repeated pagination cursor');
      if (cursor !== undefined) cursors.add(cursor);
    } while (cursor !== undefined);
    return tools;
  }

  async call(name, arguments_, options) {
    const value = await this.request('tools/call', { name, arguments: arguments_ }, options);
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('MCP returned a malformed tool result');
    return { value, error: value.isError === true };
  }

  async close() {
    if (this.#closing) return this.closed;
    this.#closing = true;
    for (const pending of this.#pending.values()) pending.reject(new Error('MCP connection closed'));
    this.#pending.clear();
    try { killGroup(this.#child); } catch {}
    const timer = setTimeout(() => { this.#child.stdout.destroy(); this.#child.stderr.destroy(); }, 2000);
    await this.closed;
    clearTimeout(timer);
  }
}
