import { Worker } from 'node:worker_threads';
import { fileURLToPath } from 'node:url';
import { encodeInput, parseJson } from './codec.mjs';

const defaultModule = fileURLToPath(new URL('../.build/kernel-model.mjs', import.meta.url));
class KernelInputError extends TypeError {}
class KernelInputRangeError extends RangeError {}
const inputErrors = { TypeError: KernelInputError, RangeError: KernelInputRangeError };
export const isKernelInputRejection = error => error instanceof KernelInputError || error instanceof KernelInputRangeError;

/** The Journal's private conversation with the extracted Rocq program worker. */
export class Kernel {
  #worker;
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
        const { text, programText } = message;
        const response = { value: parseJson(text),
          ...(programText === undefined ? {} : { program: parseJson(programText) }) };
        pending.resolve(response);
      // DEFENSE: An invalid Worker result cannot establish the state of its already executed transition.
      } catch (error) { pending.reject(error); this.#fail(error); }
    });
    this.#worker.on('error', error => this.#fail(error));
    this.#worker.once('exit', code => {
      // DEFENSE: OS/runtime Worker termination outside close leaves the current world unavailable.
      if (!this.#closing) this.#fail(new Error(`Rocq worker exited (${code})`));
    });
  }

  async initialize() {
    const { value, program } = await this.request({ kind: 'command', command: { op: 'describe' } }).result;
    const description = value.reply.result;
    this.maximum = description.limits.frame_bytes;
    return { description, program };
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
    const text = encodeInput(input, this.maximum);
    // Journal persists the same admitted frame that this Worker evaluates.
    return { text, result: this.#submit(text, true) };
  }

  // Replay checks admission without projecting intermediate worlds while the journal opens.
  replay(text) {
    return this.#submit(text, false);
  }

  assess(candidate) {
    return this.#submit(encodeInput(candidate, this.maximum), false, 'assess');
  }

  #submit(text, snapshot, operation = 'packet') {
    return new Promise((resolve, reject) => {
      // DEFENSE: The Worker can exit while idle, before the next journal request observes its failure.
      if (this.#failure) throw this.#failure;
      // DEFENSE: A stalled Worker must not hold an HTTP command or journal reopen indefinitely.
      const timer = setTimeout(() => this.#fail(new Error('Kernel transition timed out')), this.timeout);
      // Journal owns request serialization through the complete SQLite transaction.
      this.#pending = { resolve, reject, timer };
      this.#worker.postMessage({ text, snapshot, operation });
    });
  }

  abort(reason) { this.#fail(reason); }

  close() {
    this.#closing = true;
    return this.#worker.terminate();
  }
}
