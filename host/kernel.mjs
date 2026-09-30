import { Worker } from 'node:worker_threads';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { encodeFrame, parseJson } from './codec.mjs';

const defaultModule = fileURLToPath(new URL('../.build/kernel-model.mjs', import.meta.url));

/** One serialized conversation with the compiled pure Bend worker. */
export class Kernel {
  #worker;
  #tail = Promise.resolve();
  #pending;
  #failure;
  #closing = false;

  constructor({ module = defaultModule, timeout = 30_000 } = {}) {
    this.timeout = timeout;
    this.maximum = 128 * 1024;
    this.#worker = new Worker(new URL('./kernel-worker.mjs', import.meta.url), { workerData: { module } });
    this.#worker.on('message', message => {
      if (message.error) { this.#fail(new Error(message.error)); return; }
      const pending = this.#pending;
      if (!pending) { this.#fail(new Error('Unexpected kernel output')); return; }
      this.#pending = undefined;
      clearTimeout(pending.timer);
      try { pending.resolve({ ...message, value: parseJson(message.text) }); }
      catch (error) { pending.reject(error); this.#fail(error); }
    });
    this.#worker.on('error', error => this.#fail(error));
    this.exited = new Promise(resolve => this.#worker.once('exit', code => {
      if (!this.#closing || this.#pending) this.#fail(new Error(`Bend worker exited (${code})`));
      resolve({ code, signal: null });
    }));
  }

  async initialize() {
    const { value, program } = await this.request({ kind: 'command', command: { op: 'describe' } });
    if (!value.reply?.ok || !Number.isInteger(value.reply.result?.limits?.frame_bytes)) {
      this.abort(new Error('Kernel did not provide its boundary contract'));
      throw new Error('Kernel did not provide its boundary contract');
    }
    this.initialProgram = program;
    this.description = value.reply.result;
    this.maximum = this.description.limits.frame_bytes;
    return this.description;
  }

  #fail(error) {
    if (this.#failure) return;
    this.#failure = error;
    const pending = this.#pending;
    this.#pending = undefined;
    if (pending) { clearTimeout(pending.timer); pending.reject(error); }
    void this.#worker.terminate();
  }

  request(input) {
    const frame = encodeFrame(input, this.maximum);
    const result = this.#tail.then(() => {
      if (this.#failure) throw this.#failure;
      if (this.#closing) throw new Error('Kernel is closed');
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => this.#fail(new Error('Kernel transition timed out')), this.timeout);
        this.#pending = { resolve, reject, timer };
        try { this.#worker.postMessage({ frame, maximum: this.maximum }); }
        catch (error) { this.#fail(error); }
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
    await this.#worker.terminate();
    return this.exited;
  }
}

export async function buildIdentity() {
  return JSON.parse(await readFile(new URL('../.build/kernel.json', import.meta.url), 'utf8'));
}
