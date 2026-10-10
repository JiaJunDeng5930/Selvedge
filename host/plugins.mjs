import { StdioRpc } from './stdio-rpc.mjs';
import { stringifyJson } from './codec.mjs';
import { boundary } from './public/model-boundary.mjs';

export const validPluginName = name => boundary('plugin.valid_name', { name });

/** Executable plugins are trusted local processes, not a security sandbox. */
export class Plugin extends StdioRpc {
  #queue = [];
  #queuedBytes = 0;
  #pump;
  #stopping = false;
  #observer = new AbortController();

  constructor(name, config, limits, definition) {
    if (!validPluginName(name)) throw new TypeError('Invalid plugin name');
    super(name, config, limits, { label: 'Plugin', timeoutMs: limits.plugin_timeout_ms });
    this.definition = definition;
    this.on('unavailable', () => {
      this.#stopping = true;
      this.#queue = [];
      this.#queuedBytes = 0;
    });
  }

  async initialize() {
    const request = boundary('plugin.initialize_request', { definition: this.definition,
      workspace: this.config.cwd, limits: this.limits });
    const manifest = await this.request('initialize', request);
    if (!this.available) throw new Error(`Plugin ${this.name} became unavailable during initialization`);
    const admitted = boundary('plugin.manifest', { name: this.name, manifest,
      definition: this.definition, limits: this.limits });
    this.reference = Object.freeze(admitted.reference);
    this.descriptor = Object.freeze({ ...admitted.descriptor, reference: this.reference,
      events: Object.freeze(admitted.descriptor.events) });
    this.tools = admitted.tools;
    return this.descriptor;
  }

  matches(reference) {
    return boundary('plugin.matches', { reference: reference ?? null, expected: this.reference ?? null });
  }

  async before(effect, { signal } = {}) {
    const request = boundary('plugin.before_request', { effect, reference: this.reference, descriptor: this.descriptor });
    const outcome = await this.request('beforeTool', request, { signal });
    return boundary('plugin.before_result', { outcome });
  }

  async call(effect, { signal } = {}) {
    const request = boundary('plugin.call_request', { effect, reference: this.reference });
    const result = await this.request('callTool', request, { signal });
    return boundary('plugin.call_result', { result });
  }

  async after(effect, { signal } = {}) {
    const request = boundary('plugin.after_request', { effect, reference: this.reference, descriptor: this.descriptor });
    const outcome = await this.request('afterTool', request, { signal });
    return boundary('plugin.after_result', { outcome });
  }

  // Observer attempts are ordered per plugin and bounded in both count and
  // bytes. They never serialize tool authorization, veto commits or replay on
  // recovery. sequence/ordinal allows an extension to make its own sink idempotent.
  enqueue(event) {
    const bytes = Buffer.byteLength(stringifyJson(event));
    const decision = boundary('plugin.enqueue', { stopping: this.#stopping,
      queue_count: this.#queue.length, queued_bytes: this.#queuedBytes, event, event_bytes: bytes,
      config: this.config, limits: this.limits, name: this.name });
    if (decision.diagnostic) this.emit('diagnostic', decision.diagnostic);
    this.#queue.push(...decision.append);
    this.#queuedBytes = decision.next_queued_bytes;
    if (decision.accepted) this.#startPump();
    return decision.accepted;
  }

  #startPump() {
    if (this.#pump || this.#stopping) return;
    this.#pump = Promise.resolve().then(() => this.#drain()).finally(() => {
      this.#pump = undefined;
      if (this.#queue.length && !this.#stopping) this.#startPump();
    });
  }

  async #drain() {
    while (this.#queue.length && !this.#stopping) {
      const { event, bytes } = this.#queue.shift();
      this.#queuedBytes -= bytes;
      try { await this.request('event', event, { signal: this.#observer.signal, timeoutMs: this.config.event_timeout_ms ?? this.limits.plugin_event_timeout_ms }); }
      catch (error) {
        if (!this.#stopping) this.emit('diagnostic', { message: `Plugin ${this.name} observer failed: ${error.message}`,
          event_id: { sequence: event.sequence, ordinal: event.ordinal } });
      }
    }
  }

  async close() {
    this.#stopping = true;
    this.#queue = [];
    this.#queuedBytes = 0;
    this.#observer.abort(new Error('Plugin observer stopped'));
    await super.close();
    await this.#pump;
  }
}
