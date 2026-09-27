import { EventEmitter } from 'node:events';
import path from 'node:path';
import { realpath } from 'node:fs/promises';
import { Journal } from './journal.mjs';
import { Mcp } from './mcp.mjs';
import { Plugin } from './plugins.mjs';
import { runBash } from './process.mjs';
import { snapshotProject, observeWorkspaceCommand } from './project.mjs';
import { requestModel, ContextLimitError } from './providers.mjs';
import { profileCatalog } from './config.mjs';
import { withAccountModels } from './chatgpt-models.mjs';

/** Interpret committed effects. No task lifecycle or recovery policy lives here. */
export class Service extends EventEmitter {
  #running = new Map();
  #servers = new Map();
  #catalog = new Map();
  #plugins = new Map();
  #pluginCatalog = new Map();
  #continuation;
  #closing = false;
  #failure;
  #catalogTail = Promise.resolve();
  #closePromise;

  static async open({ home, config, cwd = process.cwd(), journalOptions } = {}) {
    if (!['linux', 'darwin'].includes(process.platform)) throw new Error('Selvedge supports Linux and macOS only');
    const service = new Service();
    Object.assign(service, { home, config, declaredConfig: config, cwd: await realpath(cwd) });
    try {
      service.journal = await Journal.open(path.join(home, 'journal.sqlite'), journalOptions);
      service.description = service.journal.description;
      service.limits = service.description.limits;
      service.project = await snapshotProject(service.cwd, service.limits);
      const discovered = await withAccountModels(config, home, {
        onDiagnostic: message => service.notify({ type: 'diagnostic', message }),
      });
      service.config = discovered.config;
      service.accounts = discovered.accounts;
      service.journal.on('commit', decision => {
        service.notify({ type: 'commit', sequence: decision.sequence });
        let ordinal = 0;
        for (const effect of decision.effects) {
          service.#dispatch(effect, decision.sequence, ordinal);
          if (effect.kind === 'plugin_events') ordinal += effect.events.length;
        }
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
      const extensions = Object.entries(config.plugins ?? {});
      if (extensions.length > service.description.plugins.max_plugins) throw new RangeError('Plugin count exceeds the native limit');
      await Promise.all(extensions.map(async ([name, settings]) => {
        const client = new Plugin(name, { ...settings, cwd: settings.cwd ?? service.cwd }, service.limits, service.description.plugins);
        service.#plugins.set(name, client);
        client.on('diagnostic', event => service.notify({ type: 'diagnostic', ...event }));
        const descriptor = await client.initialize();
        service.#pluginCatalog.set(name, { descriptor, tools: client.tools });
        client.on('unavailable', error => {
          service.notify({ type: 'diagnostic', message: `Plugin ${name} is unavailable: ${error.message}` });
          service.#catalogTail = service.#catalogTail.then(async () => {
            if (service.#closing || service.#failure) return;
            service.#pluginCatalog.delete(name);
            await service.#configure();
          }).catch(error => service.#fatal(error));
        });
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
    // Configuration order, not process initialization speed, defines the chain.
    const extensions = Object.keys(this.config.plugins ?? {}).flatMap(name => this.#pluginCatalog.has(name) ? [this.#pluginCatalog.get(name)] : []);
    const decision = await this.journal.execute({ kind: 'configure', profiles: profileCatalog(this.config),
      tools: [...this.#catalog.values(), ...extensions.map(extension => extension.tools)].flat(),
      plugins: extensions.map(extension => extension.descriptor), max_fork: this.config.max_fork, max_descendants: this.config.max_descendants,
      project: this.project });
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

  #dispatch(effect, sequence, firstOrdinal = 0) {
    if (this.#closing || this.#failure) return;
    if (effect.kind === 'plugin_events') {
      effect.events.forEach(({ recipients, ...event }, index) => {
        for (const reference of recipients) {
          const client = this.#plugins.get(reference.name);
          if (client?.matches(reference)) client.enqueue({ sequence, ordinal: firstOrdinal + index, ...event });
          else this.notify({ type: 'diagnostic', message: `Plugin ${reference.name} notification route is unavailable`, event_id: { sequence, ordinal: firstOrdinal + index } });
        }
      });
      return;
    }
    if (effect.kind === 'cancel') {
      for (const active of this.#running.values()) if (active.task === effect.task_id) active.controller.abort(new Error('Task work cancelled'));
      return;
    }
    if (effect.kind === 'cancel_ticket') {
      this.#running.get(`${effect.task_id}:${effect.ticket}`)?.controller.abort(new Error('Operation or model request cancelled'));
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
    if (!['model', 'summary', 'tool', 'hook', 'after_hook'].includes(effect.kind)) { this.#fatal(new Error(`Unknown effect ${effect.kind}`)); return; }
    const key = `${effect.task_id}:${effect.ticket}`;
    if (this.#running.has(key)) { this.#fatal(new Error('The kernel repeated an in-flight effect identity')); return; }
    const controller = new AbortController();
    const active = { task: effect.task_id, controller };
    this.#running.set(key, active);
    active.promise = this.#perform(effect, controller.signal).catch(error => this.#fatal(error)).finally(() => this.#running.delete(key));
  }

  async #perform(effect, signal) {
    let input;
    const cancelPreview = () => this.notify({ type: 'stream_cancel', task_id: effect.task_id, ticket: effect.ticket });
    if (effect.kind === 'model') {
      this.notify({ type: 'stream_start', task_id: effect.task_id, ticket: effect.ticket });
      signal.addEventListener('abort', cancelPreview, { once: true });
    }
    try {
      if (effect.kind === 'model' || effect.kind === 'summary') {
        const items = await requestModel(effect, this.config, this.home, this.limits, {
          signal, onDelta: (text, output_index) => this.notify({ type: 'delta', task_id: effect.task_id, ticket: effect.ticket, output_index, text }),
          onRetry: retry => this.notify({ type: 'retry', task_id: effect.task_id, ticket: effect.ticket, ...retry }),
        });
        input = { kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: true, items };
      } else if (effect.kind === 'hook') {
        const client = this.#plugins.get(effect.plugin.name);
        if (!client) throw new Error('Required plugin route is unavailable');
        const outcome = await client.before(effect, { signal });
        input = { kind: 'hook', task_id: effect.task_id, ticket: effect.ticket, outcome };
      } else if (effect.kind === 'after_hook') {
        const client = this.#plugins.get(effect.plugin.name);
        if (!client) throw new Error('Required plugin route is unavailable');
        const outcome = await client.after(effect, { signal });
        input = { kind: 'after_hook', task_id: effect.task_id, operation_id: effect.operation_id, ticket: effect.ticket, outcome };
      } else {
        let result;
        if (effect.tool.source === 'harness' && effect.tool.name === 'bash') {
          if (!effect.execution) throw new Error('A Bash effect requires a committed task execution plan');
          result = await runBash(effect.call.arguments, this.limits, { signal, execution: effect.execution,
            readOnlyPaths: [this.home], artifactDirectory: path.join(this.home, 'artifacts') });
        } else if (effect.tool.source?.plugin) {
          const client = this.#plugins.get(effect.tool.source.plugin.name);
          if (!client) throw new Error('Plugin tool route is unavailable');
          result = await client.call(effect, { signal });
        } else if (effect.tool.source && typeof effect.tool.source === 'object') {
          const client = this.#servers.get(effect.tool.source.server);
          if (!client) throw new Error('MCP route is unavailable');
          result = await client.call(effect.tool.source.name, effect.call.arguments, { signal });
        } else throw new Error('The kernel requested an unknown external tool');
        input = { kind: 'tool', task_id: effect.task_id, ticket: effect.ticket, ...result };
      }
    } catch (error) {
      input = this.#failureInput(effect, error.message);
      if ((effect.kind === 'model' || effect.kind === 'summary') && error instanceof ContextLimitError) {
        input.failure_kind = 'context_limit';
      }
    }
    signal.removeEventListener('abort', cancelPreview);
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
    if (effect.kind === 'model') {
      this.notify({ type: 'stream_end', task_id: effect.task_id, ticket: effect.ticket, sequence: result.sequence });
    }
  }

  #failureInput(effect, message) {
    message = [...String(message || 'External execution failed').toWellFormed()].slice(0, 1024).join('');
    if (effect.kind === 'hook') return { kind: 'hook', task_id: effect.task_id, ticket: effect.ticket, outcome: { decision: 'failed', reason: message } };
    if (effect.kind === 'after_hook') return { kind: 'after_hook', task_id: effect.task_id, operation_id: effect.operation_id,
      ticket: effect.ticket, outcome: { decision: 'failed', reason: message } };
    return effect.kind === 'model' || effect.kind === 'summary'
      ? { kind: 'model', task_id: effect.task_id, ticket: effect.ticket, ok: false, message }
      : { kind: 'tool', task_id: effect.task_id, ticket: effect.ticket, error: true,
        value: { error: { code: 'external_execution_failed', message } } };
  }

  async command(command) {
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#closing) return Promise.reject(new Error('Service is stopping'));
    const observed = await observeWorkspaceCommand(command, this.limits);
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    return this.journal.execute({ kind: 'command', command: observed });
  }

  refreshAccounts() {
    const next = this.#catalogTail.then(async () => {
      if (this.#closing || this.#failure) throw new Error('Service is unavailable');
      const discovered = await withAccountModels(this.declaredConfig, this.home, { force: true });
      if (this.#closing || this.#failure) throw new Error('Service is unavailable');
      const previous = this.config;
      this.config = discovered.config;
      try { await this.#configure(); }
      catch (error) { this.config = previous; throw error; }
      this.accounts = discovered.accounts;
      return { accounts: this.accounts, profiles: profileCatalog(this.config) };
    });
    // A failed external catalog refresh does not kill a healthy native world.
    this.#catalogTail = next.catch(() => {});
    return next;
  }

  async presentation({ state = null, event } = {}) {
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#closing) return Promise.reject(new Error('Service is stopping'));
    if (event?.type === 'submit') event = { ...event, command: await observeWorkspaceCommand(event.command, this.limits) };
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    return this.journal.execute({ kind: 'ui', state, event });
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
    await Promise.allSettled([...this.#servers.values(), ...this.#plugins.values()].map(client => client.close()));
    await this.#catalogTail;
    await this.journal?.close();
  }
}
