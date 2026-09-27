import { spawn } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { parseJson, encodeFrame } from './codec.mjs';

const defaultBinary = fileURLToPath(new URL('../.build/selvedge-kernel', import.meta.url));

/** One serialized conversation with the native, state-owning Bend process. */
export class Kernel {
  #process;
  #tail = Promise.resolve();
  #pending;
  #failure;
  #output = [];
  #outputBytes = 0;
  #stderr = '';
  #closing = false;

  constructor({ binary = defaultBinary, timeout = 30_000 } = {}) {
    this.timeout = timeout;
    // Bootstrap is deliberately small; describe supplies the domain's actual bound.
    this.maximum = 128 * 1024;
    this.#process = spawn(binary, [], { stdio: ['pipe', 'pipe', 'pipe'] });
    this.#process.stdout.on('data', chunk => this.#read(chunk));
    this.#process.stderr.on('data', chunk => { this.#stderr = (this.#stderr + chunk.toString()).slice(-8192); });
    this.#process.on('error', error => this.#fail(error));
    this.#process.stdin.on('error', error => this.#fail(error));
    this.exited = new Promise(resolve => {
      this.#process.once('close', (code, signal) => {
        if (!this.#closing || this.#pending) this.#fail(new Error(`Bend kernel exited (${signal ?? code}): ${this.#stderr.trim()}`));
        resolve({ code, signal });
      });
    });
  }

  async initialize() {
    const { value } = await this.request({ kind: 'command', command: { op: 'describe' } });
    if (!value.reply?.ok || !Number.isInteger(value.reply.result?.limits?.frame_bytes)) {
      throw new Error('Kernel did not provide its boundary contract');
    }
    this.description = value.reply.result;
    this.maximum = this.description.limits.frame_bytes;
    return this.description;
  }

  #read(chunk) {
    let offset = 0;
    while (offset < chunk.length) {
      const newline = chunk.indexOf(10, offset);
      const end = newline < 0 ? chunk.length : newline;
      const piece = chunk.subarray(offset, end);
      this.#output.push(piece);
      this.#outputBytes += piece.length;
      if (this.#outputBytes > this.maximum) {
        this.#fail(new Error('Kernel output exceeds its frame limit'));
        return;
      }
      if (newline < 0) return;
      const text = Buffer.concat(this.#output, this.#outputBytes).toString('utf8');
      this.#output = [];
      this.#outputBytes = 0;
      const pending = this.#pending;
      if (!pending) { this.#fail(new Error('Unexpected kernel output')); return; }
      this.#pending = undefined;
      clearTimeout(pending.timer);
      try {
        const value = parseJson(text);
        if (typeof value.durable !== 'boolean' || typeof value.reply?.ok !== 'boolean' || !Array.isArray(value.effects)) {
          throw new Error('Malformed kernel decision');
        }
        pending.resolve({ value, text });
      } catch (error) {
        pending.reject(error);
        this.#fail(error);
      }
      offset = newline + 1;
    }
  }

  #fail(error) {
    if (this.#failure) return;
    this.#failure = error;
    const pending = this.#pending;
    this.#pending = undefined;
    if (pending) { clearTimeout(pending.timer); pending.reject(error); }
    this.#process.kill('SIGKILL');
  }

  request(input) {
    const frame = encodeFrame(input, this.maximum);
    const result = this.#tail.then(() => {
      if (this.#failure) throw this.#failure;
      if (this.#closing) throw new Error('Kernel is closed');
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => this.#fail(new Error('Kernel transition timed out')), this.timeout);
        this.#pending = { resolve, reject, timer };
        this.#process.stdin.write(frame, error => { if (error) this.#fail(error); });
      });
    });
    this.#tail = result.catch(() => {});
    return result;
  }

  abort(reason = new Error('Kernel transaction aborted')) { this.#fail(reason); }

  async close() {
    if (this.#closing) return this.exited;
    this.#closing = true;
    await this.#tail;
    this.#process.stdin.end();
    const timeout = setTimeout(() => this.#process.kill('SIGKILL'), 2000);
    const result = await this.exited;
    clearTimeout(timeout);
    return result;
  }
}

export async function buildIdentity() {
  return JSON.parse(await readFile(new URL('../.build/kernel.json', import.meta.url), 'utf8'));
}
