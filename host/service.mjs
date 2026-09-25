import { EventEmitter } from 'node:events';
import path from 'node:path';
import { realpath } from 'node:fs/promises';
import { Journal } from './journal.mjs';
import { Mcp } from './mcp.mjs';
import { runBash } from './process.mjs';
import { runFileTool } from './file-tools.mjs';
import { requestModel } from './providers.mjs';
import { profileCatalog } from './config.mjs';

/** Interpret committed effects. No task lifecycle or recovery policy lives here. */
export class Service extends EventEmitter {
  #running = new Map();
  #servers = new Map();
  #catalog = new Map();
  #continuation;
  #closing = false;
  #failure;
  #catalogTail = Promise.resolve();
  #closePromise;

  static async open({ home, config, cwd = process.cwd(), journalOptions } = {}) {
    const service = new Service();
    Object.assign(service, { home, config, cwd: await realpath(cwd) });
    try {
      service.journal = await Journal.open(path.join(home, 'journal.sqlite'), { ...journalOptions, cwd: service.cwd });
      service.description = service.journal.description;
      service.limits = service.description.limits;
      service.journal.on('commit', decision => {
        service.notify({ type: 'commit', sequence: decision.sequence });
        for (const effect of decision.effects) service.#dispatch(effect);
      });
      service.journal.on('observerFailure', error => service.#fatal(error));
      await Promise.all(Object.entries(config.mcp).map(async ([name, settings]) => {
        const client = new Mcp(name, settings, service.limits);
        service.#servers.set(name, client);
        // Initialization failures abort startup. Later failures remove routes
        // through a committed Configure input; frozen task definitions remain.
        service.#catalog.set(name, await client.initialize());
        client.on('unavailable', error => {
          service.notify({ type: 'diagnostic', message: `MCP ${name} is unavailable: ${error.message}` });
          service.#refreshCatalog(name, false);
        });
        client.on('toolsChanged', () => service.#refreshCatalog(name, true));
      }));
      await service.#configure();
      const recovery = await service.journal.execute({ kind: 'recover' });
      if (!recovery.reply.ok) throw new Error(`Recovery rejected: ${recovery.reply.error.message}`);
      return service;
    } catch (error) {
      await service.close();
      throw error;
    }
  }

  notify(event) {
    for (const observer of this.listeners('notice')) {
      try { observer(event); } catch { /* An observer cannot roll back a commit. */ }
    }
  }

  #fatal(error) {
    if (this.#failure || this.#closing) return;
    this.#failure = error;
    this.notify({ type: 'fatal', message: error.message });
    for (const active of this.#running.values()) active.controller.abort(error);
    this.journal?.kernel.abort(error);
  }

  async #configure() {
    const decision = await this.journal.execute({ kind: 'configure', profiles: profileCatalog(this.config),
      tools: [...this.#catalog.values()].flat(), max_fork: this.config.max_fork, max_descendants: this.config.max_descendants });
    if (!decision.reply.ok) throw new Error(`Catalog rejected: ${decision.reply.error.message}`);
  }

  #refreshCatalog(name, discover) {
    this.#catalogTail = this.#catalogTail.then(async () => {
      if (this.#closing || this.#failure) return;
      if (discover) {
        try { this.#catalog.set(name, await this.#servers.get(name).discover()); }
        catch (error) { this.#catalog.delete(name); this.notify({ type: 'diagnostic', message: `MCP ${name}: ${error.message}` }); }
      } else this.#catalog.delete(name);
      if (!this.#closing) await this.#configure();
    }).catch(error => this.#fatal(error));
  }

  #dispatch(effect) {
    if (this.#closing || this.#failure) return;
    if (effect.kind === 'cancel') {
      for (const active of this.#running.values()) if (active.task === effect.task_id) active.controller.abort(new Error('Task work cancelled'));
      return;
    }
    if (effect.kind === 'continue') {
      this.#continuation ??= setImmediate(() => {
        this.#continuation = undefined;
        if (!this.#closing && !this.#failure) this.journal.execute({ kind: 'continue' }).then(result => {
          if (!result.reply.ok) throw new Error(`Scheduling could not advance: ${result.reply.error.message}`);
        }).catch(error => this.#fatal(error));
      });
      return;
    }
    if (!['model', 'summary', 'tool'].includes(effect.kind)) { this.#fatal(new Error(`Unknown effect ${effect.kind}`)); return; }
    const key = `${effect.task_id}:${effect.ticket}`;
    if (this.#running.has(key)) { this.#fatal(new Error('The kernel repeated an in-flight effect identity')); return; }
    const controller = new AbortController();
    const active = { task: effect.task_id, controller };
    this.#running.set(key, active);
    active.promise = this.#perform(effect, controller.signal).catch(error => this.#fatal(error)).finally(() => this.#running.delete(key));
  }

  async #perform(effect, signal) {
    let input;
    try {
      if (effect.kind === 'model' || effect.kind === 'summary') {
        const items = await requestModel(effect, this.config, this.home, this.limits, {
          signal, onDelta: text => this.notify({ type: 'delta', task_id: effect.task_id, ticket: effect.ticket, text }),
          onRetry: retry => this.notify({ type: 'retry', task_id: effect.task_id, ticket: effect.ticket, ...retry }),
        });
        input = { kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: true, items };
      } else {
        let result;
        if (effect.tool.source === 'harness' && effect.tool.name === 'bash') {
          result = await runBash(effect.call.arguments, this.limits, { signal, cwd: this.cwd,
            artifactDirectory: path.join(this.home, 'artifacts') });
        } else if (effect.tool.source === 'harness' && ['read_file', 'write_file', 'edit_file'].includes(effect.tool.name)) {
          result = await runFileTool(effect.tool.name, effect.call.arguments, this.limits, { signal, cwd: this.cwd });
        } else if (effect.tool.source && typeof effect.tool.source === 'object') {
          const client = this.#servers.get(effect.tool.source.server);
          if (!client) throw new Error('MCP route is unavailable');
          result = await client.call(effect.tool.source.name, effect.call.arguments, { signal });
        } else throw new Error('The kernel requested an unknown external tool');
        input = { kind: 'tool', task_id: effect.task_id, ticket: effect.ticket, ...result };
      }
    } catch (error) {
      input = this.#failureInput(effect, error.message);
    }
    if (this.#closing || this.#failure) return;
    let result;
    try { result = await this.journal.execute(input); }
    catch (error) {
      // A synchronous encoder rejection precedes any kernel mutation. A large
      // external result must settle as an error instead of stranding its ticket.
      if (!(error instanceof RangeError || error instanceof TypeError)) throw error;
      result = await this.journal.execute(this.#failureInput(effect, 'External result cannot fit the input contract'));
    }
    if (!result.reply.ok && result.reply.error?.code === 'output_limit') {
      result = await this.journal.execute(this.#failureInput(effect, 'External result cannot fit the complete decision'));
    }
    if (!result.reply.ok) throw new Error(`Effect settlement rejected: ${result.reply.error.message}`);
  }

  #failureInput(effect, message) {
    message = String(message).slice(0, 1024);
    return effect.kind === 'model' || effect.kind === 'summary'
      ? { kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: false, message }
      : { kind: 'tool', task_id: effect.task_id, ticket: effect.ticket, error: true,
        value: { error: { code: 'external_execution_failed', message } } };
  }

  command(command) {
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#closing) return Promise.reject(new Error('Service is stopping'));
    return this.journal.execute({ kind: 'command', command });
  }

  close() {
    this.#closePromise ??= this.#close();
    return this.#closePromise;
  }

  async #close() {
    this.#closing = true;
    if (this.#continuation) clearImmediate(this.#continuation);
    for (const active of this.#running.values()) active.controller.abort(new Error('Server stopped'));
    await Promise.allSettled([...this.#running.values()].map(active => active.promise));
    await Promise.allSettled([...this.#servers.values()].map(client => client.close()));
    await this.#catalogTail;
    await this.journal?.close();
  }
}
