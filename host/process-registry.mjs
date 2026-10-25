import { boundary } from './public/model-boundary.mjs';

/** Physical handles follow the extracted registry's admission and retention. */
export class ProcessRegistry {
  #state = boundary('control.process.registry_initial', {});
  #handles = new Map();

  clear() {
    this.#state = boundary('control.process.registry_initial', {});
    this.#handles.clear();
  }

  register(key, mode) {
    this.#state = boundary('control.process.registry_register', { registry: this.#state, key, mode });
    const session = {};
    this.#handles.set(key, session);
    return session;
  }

  failed(key, reason) {
    this.#state = boundary('control.process.registry_failed', { registry: this.#state, key, reason });
  }

  admitWrite(key) {
    boundary('control.process.registry_admit_write', { registry: this.#state, key });
  }

  complete(key) {
    const next = boundary('control.process.registry_complete', { registry: this.#state, key });
    this.#state = next.registry;
    for (const retired of next.retired) this.#handles.delete(retired);
  }

  lookup(key) {
    const pending = boundary('control.process.registry_lookup', { registry: this.#state, key });
    return { session: this.#handles.get(key), pending };
  }
}
