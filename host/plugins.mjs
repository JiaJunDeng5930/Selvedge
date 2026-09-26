import { StdioRpc } from './stdio-rpc.mjs';
import { stringifyJson } from './codec.mjs';

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const keys = (value, allowed) => object(value) && Object.keys(value).every(key => allowed.includes(key));
const namePattern = /^[A-Za-z][A-Za-z0-9_]{0,63}$/;
const text = value => typeof value === 'string' && value.trim().length > 0;

export const validPluginName = name => typeof name === 'string' && namePattern.test(name);

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
    const manifest = await this.request('initialize', {
      protocolVersion: this.definition.protocolVersion,
      clientInfo: { name: 'selvedge-bend', version: '0.1.0' },
      workspace: this.config.cwd,
      events: this.definition.events,
      limits: { frame_bytes: this.limits.frame_bytes, catalog_tools: this.limits.plugin_catalog_tools },
    });
    if (!this.available) throw new Error(`Plugin ${this.name} became unavailable during initialization`);
    if (!keys(manifest, ['protocolVersion', 'revision', 'beforeTool', 'events', 'tools']) ||
        manifest.protocolVersion !== this.definition.protocolVersion || !text(manifest.revision) ||
        Buffer.byteLength(manifest.revision) > 128 || typeof manifest.beforeTool !== 'boolean' ||
        !Array.isArray(manifest.events) || manifest.events.some(event => !this.definition.events.includes(event)) ||
        new Set(manifest.events).size !== manifest.events.length || !Array.isArray(manifest.tools)) {
      throw new TypeError(`Plugin ${this.name} returned an invalid manifest`);
    }
    this.reference = Object.freeze({ name: this.name, revision: manifest.revision });
    this.descriptor = Object.freeze({ reference: this.reference, before_tool: manifest.beforeTool, events: Object.freeze([...manifest.events]) });
    const names = new Set();
    let size = 0;
    this.tools = manifest.tools.map(tool => {
      if (!keys(tool, ['name', 'description', 'inputSchema']) || !validPluginName(tool.name) ||
          !text(tool.description) || !object(tool.inputSchema) || tool.inputSchema.type !== 'object') {
        throw new TypeError(`Plugin ${this.name} returned an invalid tool definition`);
      }
      const name = `plugin__${this.name}__${tool.name}`;
      if (names.has(name)) throw new TypeError(`Plugin tool name collision: ${name}`);
      names.add(name);
      const entry = { name, description: tool.description, schema: tool.inputSchema, plugin: this.reference, remote: tool.name };
      size += Buffer.byteLength(stringifyJson(entry));
      if (names.size > this.limits.plugin_catalog_tools || size > this.limits.frame_bytes) throw new RangeError('Plugin catalog exceeds limits');
      return entry;
    });
    return this.descriptor;
  }

  matches(reference) { return reference?.name === this.reference?.name && reference?.revision === this.reference?.revision; }

  async before(effect, { signal } = {}) {
    if (!this.matches(effect.plugin) || !this.descriptor.before_tool) throw new Error('Required plugin revision is unavailable');
    const outcome = await this.request('beforeTool', {
      task_id: effect.task_id, ticket: effect.ticket, plugin: effect.plugin, tool: effect.tool, call: effect.call,
    }, { signal });
    if (!object(outcome)) throw new TypeError('Plugin returned an invalid hook decision');
    const shape = outcome.decision === 'allow' ? ['decision'] : outcome.decision === 'rewrite' ? ['decision', 'arguments'] : ['decision', 'reason'];
    if (!keys(outcome, shape) || Object.keys(outcome).length !== shape.length ||
        !['allow', 'rewrite', 'deny'].includes(outcome.decision) ||
        (outcome.decision === 'rewrite' && !object(outcome.arguments)) ||
        (outcome.decision === 'deny' && (!text(outcome.reason) || Buffer.byteLength(outcome.reason) > 4096))) {
      throw new TypeError('Plugin returned an invalid hook decision');
    }
    return outcome;
  }

  async call(effect, { signal } = {}) {
    const source = effect.tool.source;
    if (!this.matches(source?.plugin)) throw new Error('Plugin tool revision is unavailable');
    const result = await this.request('callTool', {
      name: source.name, arguments: effect.call.arguments,
      context: { task_id: effect.task_id, operation_id: effect.ticket, call_id: effect.call.id },
    }, { signal });
    if (!keys(result, ['value', 'error']) || !Object.hasOwn(result, 'value') || typeof result.error !== 'boolean') {
      throw new TypeError('Plugin returned an invalid tool result');
    }
    return result;
  }

  // Observer attempts are ordered per plugin and bounded in both count and
  // bytes. They never serialize tool authorization, veto commits or replay on
  // recovery. sequence/ordinal allows an extension to make its own sink idempotent.
  enqueue(event) {
    if (this.#stopping) return false;
    const bytes = Buffer.byteLength(stringifyJson(event));
    if (this.#queue.length >= (this.config.event_queue ?? this.limits.plugin_event_queue) ||
        this.#queuedBytes + bytes > this.limits.frame_bytes * 2) {
      this.emit('diagnostic', { message: `Plugin ${this.name} event queue is full; notification was not delivered`,
        event_id: { sequence: event.sequence, ordinal: event.ordinal } });
      return false;
    }
    this.#queue.push({ event, bytes });
    this.#queuedBytes += bytes;
    this.#startPump();
    return true;
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
