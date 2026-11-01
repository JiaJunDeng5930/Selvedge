import { Worker } from 'node:worker_threads';
import { fileURLToPath } from 'node:url';
import { encodeInput, parseJson } from './codec.mjs';

const defaultModule = fileURLToPath(new URL('../.build/kernel-model.mjs', import.meta.url));
class KernelInputError extends TypeError {}
class KernelInputRangeError extends RangeError {}
const inputErrors = { TypeError: KernelInputError, RangeError: KernelInputRangeError };
export const isKernelInputRejection = error => error instanceof KernelInputError || error instanceof KernelInputRangeError;

/** One serialized conversation with the extracted Rocq program worker. */
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
      // DEFENSE: A response can arrive after timeout or journal failure retired this Worker.
      if (this.#failure) return;
      const pending = this.#pending;
      // DEFENSE: An extracted transition can throw after touching its Worker world; retire that world.
      if (Object.hasOwn(message, 'error')) { this.#fail(new Error(message.error)); return; }
      this.#pending = undefined;
      clearTimeout(pending.timer);
      if (message.inputError) {
        const ErrorType = inputErrors[message.inputError.name];
        pending.reject(new ErrorType(message.inputError.message));
        return;
      }
      try {
        const { programText, ...result } = message;
        const response = { ...result, value: parseJson(message.text),
          ...(programText === undefined ? {} : { program: parseJson(programText) }) };
        pending.resolve(response);
      // DEFENSE: An invalid Worker result cannot establish the state of its already executed transition.
      } catch (error) { pending.reject(error); this.#fail(error); }
    });
    this.#worker.on('error', error => this.#fail(error));
    this.exited = new Promise(resolve => this.#worker.once('exit', code => {
      // DEFENSE: OS/runtime Worker termination outside close leaves the current world unavailable.
      if (!this.#closing || this.#pending) this.#fail(new Error(`Rocq worker exited (${code})`));
      resolve({ code, signal: null });
    }));
  }

  async initialize() {
    const { value, program } = await this.request({ kind: 'command', command: { op: 'describe' } });
    this.initialProgram = program;
    this.description = value.reply.result;
    this.maximum = this.description.limits.frame_bytes;
    return this.description;
  }

  #fail(error) {
    // DEFENSE: Worker error, exit and timeout can report the same failure; settle the pending request once.
    if (this.#failure) return;
    this.#failure = error;
    const pending = this.#pending;
    this.#pending = undefined;
    if (pending) { clearTimeout(pending.timer); pending.reject(error); }
    void this.#worker.terminate();
  }

  request(input) {
    return this.#request(input, true);
  }

  // Replay checks admission without projecting intermediate worlds while the journal opens.
  replay(input) {
    return this.#request(input, false);
  }

  assess(candidate) {
    return this.#request(candidate, false, 'assess');
  }

  #request(input, snapshot, operation = 'packet') {
    const text = encodeInput(input, this.maximum);
    const result = this.#tail.then(() => {
      // DEFENSE: A queued request can reach its turn after an earlier transition failed or shutdown started.
      if (this.#failure) throw this.#failure;
      if (this.#closing) throw new Error('Kernel is closed');
      return new Promise((resolve, reject) => {
        // DEFENSE: A stalled Worker must not hold an HTTP command or journal reopen indefinitely.
        const timer = setTimeout(() => this.#fail(new Error('Kernel transition timed out')), this.timeout);
        // The queue admits one request until this Worker returns its single response.
        this.#pending = { resolve, reject, timer };
        this.#worker.postMessage({ text, snapshot, operation });
      });
    });
    // DEFENSE: The request's returned promise reports its failure; the queue must still admit close and reject later callers explicitly.
    this.#tail = result.catch(() => {});
    return result;
  }

  abort(reason = new Error('Kernel transaction aborted')) { this.#fail(reason); }

  async close() {
    // DEFENSE: Startup cleanup and normal shutdown can both close the same Worker.
    if (this.#closing) return this.exited;
    this.#closing = true;
    await this.#tail;
    await this.#worker.terminate();
    return this.exited;
  }
}
