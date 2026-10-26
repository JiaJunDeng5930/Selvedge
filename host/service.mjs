import { cloneJson } from './codec.mjs';
import { boundary } from './public/model-boundary.mjs';
import { requireAudioAdmission, interpretBrowserObservation, browseDirectoryLocation, dispatchControlResult, interpretAudioControl } from './model-api.ts';
import { EventEmitter } from 'node:events';
import { launchEffect, settleEffect } from './effect-lifecycle.ts';
import { materializeCallArguments } from './public/call-wire.mjs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { createChatGPTAudio } from './chatgpt-audio.mjs';
import { realpath } from 'node:fs/promises';
import { Journal, isDefiniteRejection, transactionOutcome } from './journal.mjs';
import { naturalKey, sameNatural } from './public/json-tokens.mjs';
import { dispatchEffect, performEffect, modelEffect, workspaceOperation, compactionOperation, workspaceEffect, clockDelay } from './effect-dispatch.ts';
import { Mcp } from './mcp.mjs';
import { Plugin } from './plugins.mjs';
import { runBash, startBash, runReadImage } from './process.mjs';
import { ProcessRegistry } from './process-registry.mjs';
import { snapshotProject, snapshotGlobalInstructions, observeWorkspaceCommand, admitRawWorkspaceCommand, hasRootTaskCreation, workspaceCommandPlan } from './project.mjs';
import { observeContextSources, observeSkillCatalog } from './context-sources.mjs';
import { requestApproval } from './approvals.mjs';
import { requestTaskText } from './task-text.mjs';
import { observeBoardCommand, observeMessageImages } from './board-files.mjs';
import { requestModel, requestCompaction, observeModelRequest, cancelModelTask, ContextLimitError } from './providers.mjs';
import { canonicalWorkspace } from './sandbox.mjs';
import { browseDirectories } from './directories.mjs';
import { profileCatalog, compactionSettings } from './config.mjs';
import { withAccountModels } from './chatgpt-models.mjs';
import { connectionGrants } from './chatgpt-plugin.mjs';
import { WebRequestStore } from './chatgpt-web-store.mjs';
import { RemoteControl } from './remote-control.mjs';
import { observeWorkspaceGit } from './worktrees.mjs';
import { createTaskWorkspace, archiveTaskWorkspace, reconcileTaskWorkspace, rollbackTaskWorkspaceCreation,
  taskWorkspaceEnvironment, observeCloudRepository } from './task-workspaces.mjs';

function directoriesOverlap(left, right) {
  return [path.relative(left, right), path.relative(right, left)].some(relative =>
    relative !== '..' && !relative.startsWith(`..${path.sep}`));
}

/** Interpret committed effects. No task lifecycle or recovery policy lives here. */
export class CommandNotSubmitted extends Error {
  constructor(cause) {
    super(cause.message, { cause });
    this.name = 'CommandNotSubmitted';
  }
}

export class Service extends EventEmitter {
  #running = new Map();
  #dispatchState = boundary('control.dispatch.initial', {});
  #processRegistry = new ProcessRegistry();
  #providerCancellations = new Set();
  #servers = new Map();
  #catalog = new Map();
  #plugins = new Map();
  #pluginCatalog = new Map();
  #continuation;
  #compactionTimer;
  #closing = false;
  #failure;
  #catalogTail = Promise.resolve();
  #closePromise;
  #streams = [];
  #audioSessions = new Map();

  static async open({ home, config, cwd = process.cwd(), journalOptions, remoteOptions, audioOptions, audioFactory = createChatGPTAudio } = {}) {
    // DEFENSE: The process sandbox supports only the Linux and macOS implementations; refuse other OS launches.
    if (!['linux', 'darwin'].includes(process.platform)) throw new Error('Selvedge supports Linux and macOS only');
    const service = new Service();
    Object.assign(service, { home, config, declaredConfig: config, cwd: await realpath(cwd) });
    try {
      service.journal = await Journal.open(path.join(home, 'journal.sqlite'), journalOptions);
      service.description = service.journal.description;
      service.limits = service.description.limits;
      service.project = await snapshotProject(service.cwd, service.limits);
      service.instructions = { configured: config.instructions,
        global: await snapshotGlobalInstructions(home, service.limits) };
      const discovered = await withAccountModels(config, home, {
        onDiagnostic: message => service.notify({ type: 'diagnostic', message }),
      });
      service.config = discovered.config;
      service.accounts = discovered.accounts;
      service.journal.on('commit', decision => {
        service.notify({ type: 'commit', sequence: decision.sequence });
        service.remote?.reconcile();
        let ordinal = 0;
        for (const effect of decision.effects) {
          ordinal += service.#dispatch(effect, decision.sequence, ordinal);
        }
      });
      service.journal.on('observerFailure', error => service.#fatal(error));
      service.journal.on('retired', error => service.#fatal(error));
      await Promise.all(Object.entries(config.mcp).map(async ([name, settings]) => {
        const client = new Mcp(name, settings, service.limits, { home: service.home });
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
      const extensions = Object.entries(config.plugins);
      // DEFENSE: User configuration can exceed the kernel's published plugin-count budget.
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
            // DEFENSE: An unavailable-plugin callback may be queued when service shutdown or a journal failure begins.
            if (service.#closing || service.#failure) return;
            service.#pluginCatalog.delete(name);
            await service.#configure();
          }).catch(error => service.#fatal(error));
        });
      }));
      await service.#configure();
      const recovery = await service.journal.execute({ kind: 'recover' });
      // DEFENSE: Recovery resends pending model effects; their combined payload can exceed the complete-decision budget and leave recovery uncommitted.
      if (!recovery.reply.ok) throw new Error(`Recovery rejected: ${recovery.reply.error.message}`);
      await service.#reconcileWorktrees();
      const grants = await service.command({ op: 'configure_chatgpt_connections', connections: connectionGrants(config.chatgpt_plugin) });
      // DEFENSE: Saved connection grants can refer to projects removed from the current journal; startup must report native configuration rejection.
      if (!grants.reply.ok) throw new Error(`ChatGPT connection configuration rejected: ${grants.reply.error.message}`);
      service.remote = await RemoteControl.open(service, remoteOptions);
      service.audio = audioFactory({ config: () => service.config, home, ...audioOptions,
        onEvent: event => service.#audioEvent(event) });
      return service;
    // DEFENSE: Account, filesystem or subprocess initialization can fail after the journal and clients opened; release those acquired resources.
    } catch (error) {
      await service.close();
      throw error;
    }
  }

  notify(event) {
    event = { ...event, namespace: this.journal.namespace };
    this.#streams = boundary('browser.host_stream_step', { state: this.#streams, notice: event }).state;
    for (const observer of this.listeners('notice')) observer(event);
  }

  #fatal(error) {
    // DEFENSE: Several active operations can observe the same journal/Worker failure while shutdown is already in progress.
    if (this.#failure || this.#closing) return;
    this.#failure = error;
    this.notify({ type: 'fatal', message: error.message });
    this.#cancelRunning({ kind: 'shutdown' }, error);
    this.journal.kernel.abort(error);
  }

  #configuration({ project = this.project, instructions = this.instructions } = {}) {
    // Configuration order, not process initialization speed, defines the chain.
    const extensions = Object.keys(this.config.plugins).flatMap(name => this.#pluginCatalog.has(name) ? [this.#pluginCatalog.get(name)] : []);
    return { kind: 'configure', profiles: profileCatalog(this.config),
      tools: [...this.#catalog.values(), ...extensions.map(extension => extension.tools)].flat(),
      plugins: extensions.map(extension => extension.descriptor), max_fork: this.config.max_fork, max_descendants: this.config.max_descendants,
      project, instructions };
  }

  async #configure() {
    const decision = await this.journal.execute(this.#configuration());
    // DEFENSE: Independently supplied MCP/plugin catalogs can conflict or exceed native configuration limits.
    if (!decision.reply.ok) throw new Error(`Catalog rejected: ${decision.reply.error.message}`);
    const compaction = await this.journal.execute({ kind: 'compaction_configure', policy: compactionSettings(this.config), now: Date.now() });
    // DEFENSE: Account-advertised context windows can make configured compaction budgets invalid or too large for a complete decision.
    if (!compaction.reply.ok) throw new Error(`Compaction configuration rejected: ${compaction.reply.error.message}`);
  }

  #refreshCatalog(name, discover) {
    this.#catalogTail = this.#catalogTail.then(async () => {
      // DEFENSE: A queued subprocess catalog refresh can outlive service shutdown or a fatal journal failure.
      if (this.#closing || this.#failure) return;
      if (discover) {
        try { this.#catalog.set(name, await this.#servers.get(name).discover()); }
        // DEFENSE: MCP rediscovery can time out, return malformed tools or lose its process; withdraw that live catalog and diagnose the failure.
        catch (error) { this.#catalog.delete(name); this.notify({ type: 'diagnostic', message: `MCP ${name}: ${error.message}` }); }
      } else this.#catalog.delete(name);
      // DEFENSE: Shutdown can start while MCP rediscovery awaits the subprocess.
      if (!this.#closing) await this.#configure();
    }).catch(error => this.#fatal(error));
  }

  #dispatchControl(observation) {
    const transition = dispatchControlResult(boundary('control.dispatch.step', { state: this.#dispatchState, observation }));
    this.#dispatchState = transition.state;
    return transition;
  }

  #cancelRunning(observation, reason) {
    for (const action of this.#dispatchControl(observation).cancellations) {
      const active = this.#running.get(naturalKey(action.generation));
      // DEFENSE: A promise can finish after cancellation was planned and before its AbortController is visited.
      if (!active) continue;
      // Keep the registered invocation through synchronous receipt retirement;
      // aborting its observer must not retarget a later task request.
      if (action.provider) this.#cancelProvider(active.effect);
      active.controller.abort(reason);
    }
  }

  #dispatch(effect, sequence, firstOrdinal = 0) {
    // DEFENSE: A commit observer can reach later effects after an earlier effect retired the service.
    if (this.#closing || this.#failure) return 0;
    return dispatchEffect(effect, {
      reset: effect => {
        try { WebRequestStore.resetExisting(this.home, effect.task_id); }
        // DEFENSE: The committed reset must surface a SQLite failure.
        catch (error) { this.#fatal(error); }
      },
      notifyPlugins: effect => {
        effect.events.forEach(({ recipients, ...event }, index) => {
          for (const reference of recipients) {
            const client = this.#plugins.get(reference.name);
            // DEFENSE: A frozen task can name a plugin removed from the current configuration.
            if (client?.matches(reference)) client.enqueue({ sequence, ordinal: firstOrdinal + index, ...event });
            else this.notify({ type: 'diagnostic', message: `Plugin ${reference.name} notification route is unavailable`, event_id: { sequence, ordinal: firstOrdinal + index } });
          }
        });
      },
      cancelTask: effect => {
        this.#cancelProvider(effect.task_id);
        this.#cancelRunning({ kind: 'cancel_task', effect }, new Error('Task work cancelled'));
      },
      cancelKey: effect => this.#cancelRunning({ kind: 'cancel_key', effect }, new Error('Operation cancelled')),
      continue: () => {
        this.#continuation ??= setImmediate(() => {
          this.#continuation = undefined;
          // DEFENSE: Shutdown can retire this scheduled observation before it runs.
          if (!this.#closing && !this.#failure) this.journal.execute({ kind: 'continue' }).then(result => {
            // DEFENSE: A full resulting decision can exceed the kernel output budget.
            if (!result.reply.ok) throw new Error(`Scheduling could not advance: ${result.reply.error.message}`);
          }).catch(error => this.#fatal(error));
        });
      },
      clock: effect => {
        if (this.#compactionTimer) clearTimeout(this.#compactionTimer);
        this.#compactionTimer = setTimeout(() => {
          this.#compactionTimer = undefined;
          // DEFENSE: Shutdown can retire this clock observation before it runs.
          if (!this.#closing && !this.#failure) this.journal.execute({ kind: 'compaction_clock', now: Date.now() })
            .then(result => {
              // DEFENSE: Clock-triggered work can exceed the complete-decision budget.
              if (!result.reply.ok) throw new Error(`Clock observation rejected: ${result.reply.error.message}`);
            }).catch(error => this.#fatal(error));
        }, clockDelay(effect, Date.now()));
        this.#compactionTimer.unref();
      },
      start: effect => {
        // Background execution observes failures separately; the runner retains its rejecting promise.
        void this.#launch(effect, (handle, signal) => this.#perform(effect, signal, handle))
          .catch(error => this.#fatal(error));
      },
    });
  }

  #launch(effect, run) {
    return launchEffect(observation => this.#dispatchControl(observation), this.#running, effect, run);
  }

  #cancelProvider(task) {
    const promise = cancelModelTask(task, this.config, this.home, this.limits)
      // DEFENSE: The provider can reject or lose a remote Stop request; keep local cancellation and report its unconfirmed remote outcome.
      .catch(error => this.notify({ type: 'diagnostic', message: `Remote cancellation was not confirmed: ${error.message}` }))
      .finally(() => this.#providerCancellations.delete(promise));
    this.#providerCancellations.add(promise);
  }

  async #runProcess(effect, signal) {
    const key = `${naturalKey(effect.task_id)}:${naturalKey(effect.operation_id)}`;
    // Register before observing the checkout or preparing the sandbox: a sibling
    // read/write effect can run while the original process is still starting.
    const arguments_ = materializeCallArguments(effect.call);
    const session = this.#processRegistry.register(key, arguments_.mode ?? 'pipe');
    const prepared = this.#resourceWorkspace(effect.execution.resource, signal).then(({ managedWorktreeRoot, environment }) =>
      startBash(arguments_, this.limits, { signal, execution: effect.execution, managedWorktreeRoot, environment,
        readOnlyPaths: [this.home], ...(environment ? {} : { artifactDirectory: path.join(this.home, 'artifacts') }) }));
    session.ready = prepared.then(({ read, write }) => { session.read = read; session.write = write; },
      error => {
        this.#processRegistry.failed(key, { code: error.code ?? 'command_start_failed', message: error.message });
      });
    try {
      const runtime = await prepared;
      return await runtime.result;
    } finally {
      this.#processRegistry.complete(key);
    }
  }

  async #processTool(effect) {
    const reading = effect.tool.source.program.kind === 'ProcessRead';
    const arguments_ = boundary(reading ? 'effect.process_read_arguments' : 'effect.process_write_arguments',
      { arguments: materializeCallArguments(effect.call) });
    try {
      const { session, pending } = this.#processRegistry.lookup(`${naturalKey(effect.task_id)}:${naturalKey(arguments_.operation_id)}`);
      if (reading) {
        const value = session.read ? session.read(arguments_.cursor) : pending;
        return { error: false, value: { operation_id: arguments_.operation_id, ...value } };
      }
      await session.ready;
      this.#processRegistry.admitWrite(`${naturalKey(effect.task_id)}:${naturalKey(arguments_.operation_id)}`);
      const { operation_id, ...input } = arguments_;
      return { error: false, value: { operation_id, ...await session.write(input) } };
    } catch (error) {
      // DEFENSE: Live process reads/writes can report invalid cursors, closed
      // stdin, exited terminals or OS I/O failures without cancelling Bash.
      return { error: true, value: { error: { code: error.code ?? 'process_io_failed', message: error.message } } };
    }
  }

  async #performWorkspace(effect, signal, handle) {
    if (workspaceOperation(effect) === 'archive') {
      // Committed cancellation can precede the underlying process or filesystem operation finishing.
      const running = [...this.#running.values()].filter(active => !workspaceEffect(active.effect));
      const resources = await Promise.all(running.map(active => active.effect.execution
        ? active.effect.execution.resource
        : Object.hasOwn(active.effect, 'resource') ? active.effect.resource
        : active.task === undefined ? undefined : this.#worktree(active.task)));
      const plan = this.#dispatchControl({ kind: 'workspace_barrier', effect,
        running: running.map((active, index) => ({ generation: active.handle.generation,
          task: active.task ?? null, resource: resources[index] ?? null,
          local_overlap: effect.backend === 'local' && !!active.effect.execution && !resources[index] &&
            active.effect.execution.workspace.roots.some(root => directoriesOverlap(root, effect.root)) })) });
      await Promise.all(plan.awaits.map(generation => this.#running.get(naturalKey(generation))?.promise));
    }
    const completion = await (workspaceOperation(effect) === 'create' ? createTaskWorkspace : archiveTaskWorkspace)(effect,
      this.#workspaceOptions(signal));
    // DEFENSE: Shutdown can finish before the physical operation; preserve its receipt for recovery.
    if (!this.#closing && !this.#failure) await this.#settleWorkspaceCompletion(effect, completion, handle);
  }


  async #perform(effect, signal, handle) {
    let input;
    let observation;
    const model = modelEffect(effect);
    const cancelPreview = () => this.notify({ type: 'stream_cancel', task_id: effect.task_id, ticket: effect.ticket });
    try {
      const performed = await performEffect(effect, {
        workspace: effect => this.#performWorkspace(effect, signal, handle),
        context: async effect => {
          const { environment } = await this.#resourceWorkspace(effect.resource, signal);
          const observations = await observeContextSources(effect, { home: this.home, config: this.declaredConfig, limits: this.limits, signal, environment,
            onDiagnostic: message => this.notify({ type: 'diagnostic', message }) });
          return { observations };
        },
        chatgpt: async effect => {
          const resource = await this.#resourceWorkspace(effect.execution.resource, signal);
          return runBash(effect.arguments, this.limits, { signal, execution: effect.execution, ...resource, readOnlyPaths: [this.home] });
        },
        text: effect => requestTaskText(effect, this.config, this.home, this.limits, { signal }),
        approval: effect => requestApproval(effect, this.config, this.home, this.limits, { signal }),
        reasoning: async effect => {
          const { requestReasoning } = await import('./jev.mjs');
          return requestReasoning(effect, this.config, this.limits, { signal });
        },
        compaction: effect => compactionOperation(effect) === 'observe'
          ? observeModelRequest(effect, this.config, this.home, this.limits, { signal })
          : requestCompaction(effect, this.config, this.home, this.limits, { signal }),
        model: async effect => {
          this.notify({ type: 'stream_start', task_id: effect.task_id, ticket: effect.ticket });
          signal.addEventListener('abort', cancelPreview, { once: true });
          return requestModel(effect, this.config, this.home, this.limits, {
            signal, onObservation: value => { observation = value; },
            onDelta: (text, output_index) => this.notify({ type: 'delta', task_id: effect.task_id, ticket: effect.ticket, output_index, text }),
            onSnapshot: (text, output_index) => this.notify({ type: 'snapshot', task_id: effect.task_id, ticket: effect.ticket, output_index, text }),
            onRetry: retry => this.notify({ type: 'retry', task_id: effect.task_id, ticket: effect.ticket, ...retry }),
          });
        },
        hook: async effect => {
          const client = this.#plugins.get(effect.plugin.name);
          // DEFENSE: A frozen hook can outlive its configured plugin process.
          if (!client) throw new Error('Required plugin route is unavailable');
          return client.before(effect, { signal });
        },
        afterHook: async effect => {
          const client = this.#plugins.get(effect.plugin.name);
          // DEFENSE: A frozen after-hook can outlive its configured plugin process.
          if (!client) throw new Error('Required plugin route is unavailable');
          return client.after(effect, { signal });
        },
        tool: async effect => {
          if (effect.tool.source.kind === 'native') {
            if (effect.tool.source.program.kind === 'Process') return this.#runProcess(effect, signal);
            if (effect.tool.source.program.kind === 'ReadImage') {
              const executionOptions = { signal, execution: effect.execution,
                ...await this.#resourceWorkspace(effect.execution.resource, signal), readOnlyPaths: [this.home], home: this.home };
              return runReadImage(materializeCallArguments(effect.call), this.limits, executionOptions);
            }
            return this.#processTool(effect);
          }
          if (effect.tool.source.plugin) {
            const client = this.#plugins.get(effect.tool.source.plugin.name);
            // DEFENSE: A frozen tool can outlive its configured plugin process.
            if (!client) throw new Error('Plugin tool route is unavailable');
            return client.call(effect, { signal });
          }
          const client = this.#servers.get(effect.tool.source.server);
          // DEFENSE: A frozen tool can name a server removed from configuration.
          if (!client) throw new Error('MCP route is unavailable');
          return client.call(effect.tool.source.name, materializeCallArguments(effect.call), { signal });
        },
      });
      if (performed.kind === 'settled') return;
      input = performed.input;
    // DEFENSE: External IO can fail; resource settlement errors retain their receipt and must not become a second callback.
    } catch (error) {
      if (workspaceEffect(effect)) throw error;
      input = this.#failureInput(effect, error.message, error instanceof ContextLimitError);
    } finally { signal.removeEventListener('abort', cancelPreview); }
    // DEFENSE: Shutdown can abort an operation while its external failure/success continuation is resuming.
    if (this.#closing || this.#failure) return;
    const result = await this.#settleCompletion(input, () => this.#failureInput(effect,
      'External result cannot fit the kernel boundary'), handle);
    this.#queueAudioProgress(effect.task_id);
    if (model) {
      // DEFENSE: Cancellation may occur while model completion is committing; do not record stale cache activity after the request was aborted.
      if (observation && !signal.aborted) {
        const activity = await this.journal.execute({ kind: 'compaction_activity', task_id: effect.task_id,
          source_length: effect.source_length, now: observation.now, scope: observation.scope });
        // DEFENSE: A provider scope/clock observation can be rejected by native admission or the complete-decision budget.
        if (!activity.reply.ok) throw new Error(`Cache observation rejected: ${activity.reply.error.message}`);
      }
      this.notify({ type: 'stream_end', task_id: effect.task_id, ticket: effect.ticket, sequence: result.sequence });
    }
  }

  #failureInput(effect, message, context_limit = false) {
    // DEFENSE: External diagnostic text can contain lone UTF-16 surrogates; normalize it for the scalar-string kernel ABI.
    return boundary('effect.failure', { effect, message: message.toWellFormed(), context_limit });
  }

  async #workspaceTask(taskId) {
    const result = await this.journal.execute({ kind: 'command', command: { op: 'read_worktree', task_id: taskId } });
    if (!result.reply.ok) {
      if (result.reply.error.code === 'not_found') return { kind: 'local' };
      if (result.reply.error.code === 'task_not_found') return { kind: 'unknown' };
      throw new Error(`Task workspace lookup rejected: ${result.reply.error.message}`);
    }
    return { kind: result.reply.result.backend === 'tencent_cvm' ? 'cloud' : 'local', entry: result.reply.result };
  }

  async #worktree(taskId) {
    return (await this.#workspaceTask(taskId)).entry;
  }

  #workspaceOptions(signal) {
    return { home: this.home, limits: this.limits, namespace: this.journal.namespace, cloud: this.config.cloud, signal };
  }

  #settleCompletion(input, failure, handle) {
    return settleEffect(observation => this.#dispatchControl(observation), handle, input,
      value => this.journal.execute(value), failure,
      error => isDefiniteRejection(error) && error instanceof RangeError ? 'input_limit'
        : transactionOutcome(error) === 'unknown' ? 'uncertain' : 'rejected');
  }

  async #settleWorkspaceCompletion(effect, completion, handle) {
    return this.#settleCompletion(completion, () =>
      this.#dispatchControl({ kind: 'workspace_limit', effect, completion }).rollbackWorkspace
        ? rollbackTaskWorkspaceCreation(effect, { ...this.#workspaceOptions(), message: 'Cloud workspace completion exceeds the kernel boundary' })
        : boundary('effect.completion', { effect, result: { ok: false, root: completion.root ?? null,
          message: 'Managed worktree completion exceeds the kernel boundary; the checkout has been retained' } }), handle);
  }

  async #resourceWorkspace(resource, signal) {
    if (!resource) return {};
    // A child can retain this frozen resource after its owner selects another local workspace.
    // Read ownership by ID rather than re-resolving the owner's current execution binding.
    const result = await this.journal.execute({ kind: 'command', command: { op: 'list_worktrees' } });
    if (!result.reply.ok) throw new Error(`Task resource lookup rejected: ${result.reply.error.message}`);
    const entry = result.reply.result.worktrees.find(entry => sameNatural(entry.task_id, resource.task_id));
    // DEFENSE: A frozen effect can race managed-resource archival; never substitute the host filesystem.
    if (!entry || !sameNatural(entry.task_id, resource.task_id) || entry.backend !== resource.backend || entry.status !== 'ready') {
      throw new Error('The committed task workspace binding is unavailable');
    }
    return entry.backend === 'local' ? { managedWorktreeRoot: entry.root }
      : { environment: await taskWorkspaceEnvironment(entry, this.#workspaceOptions(signal)) };
  }

  async #taskWorkspace(taskId, signal) {
    const entry = await this.#worktree(taskId);
    return entry ? this.#resourceWorkspace({ task_id: entry.task_id, backend: entry.backend }, signal) : {};
  }

  async #workspaceEnvironment(resource, signal) {
    return (await this.#resourceWorkspace(resource, signal)).environment;
  }

  async #observationEnvironment(observation) {
    return Object.hasOwn(observation, 'task_id') ? (await this.#taskWorkspace(observation.task_id)).environment : undefined;
  }

  async #reconcileWorktrees() {
    const result = await this.journal.execute({ kind: 'command', command: { op: 'list_worktrees' } });
    // DEFENSE: A persisted collection of managed checkouts can exceed the query reply's frame budget.
    if (!result.reply.ok) throw new Error(`Managed worktree recovery query rejected: ${result.reply.error.message}`);
    for (const entry of result.reply.result.worktrees) {
      if (!['creating', 'creating_archived', 'archiving'].includes(entry.status)) continue;
      const effect = { ...entry, kind: entry.status === 'archiving' ? 'worktree_archive' : 'worktree_create' };
      // Recovery observes the existing resource; it must never replay create or archive IO.
      await this.#launch(effect, async (handle, signal) => {
        const completion = await reconcileTaskWorkspace(entry, this.#workspaceOptions(signal));
        await this.#settleWorkspaceCompletion(effect, completion, handle);
      });
    }
  }

  #publicCommand(command) {
    // DEFENSE: Browser, CLI and remote clients can forge sideband-only commands; any public admission failure occurs before journal submission.
    try { boundary('http.public_command', { command }); }
    catch (cause) { throw new CommandNotSubmitted(cause); }
  }

  assess(candidate) {
    this.#publicCommand(candidate.command);
    // DEFENSE: An HTTP assessment can already be in flight when the service closes or loses its worker.
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#closing) return Promise.reject(new Error('Service is stopping'));
    const result = this.#catalogTail.then(async () => {
      // DEFENSE: Catalog work queued before assessment can fail, or shutdown can finish while it waits.
      if (this.#failure) throw this.#failure;
      if (this.#closing) throw new Error('Service is stopping');
      const command = await this.#observeCommandInput(candidate.command);
      // DEFENSE: Shutdown or a fatal operation can occur during the same filesystem preparation used by submission.
      if (this.#failure) throw this.#failure;
      if (this.#closing) throw new Error('Service is stopping');
      return this.journal.assess({ ...candidate, command });
    });
    // DEFENSE: A refused filesystem observation reports its own error without blocking later catalog work.
    this.#catalogTail = result.catch(() => {});
    return result;
  }

  async command(command) {
    this.#publicCommand(command);
    // DEFENSE: HTTP commands already in flight can reach the service after a fatal operation or shutdown.
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#closing) return Promise.reject(new Error('Service is stopping'));
    if (hasRootTaskCreation(command)) {
      // Keep each root's observed defaults adjacent to its command even when
      // catalog refreshes and other root births arrive concurrently.
      const next = this.#catalogTail.then(() => this.#createRoot(command));
      // DEFENSE: A failed filesystem observation rejects this command's returned promise; it must not prevent later commands from reaching their own admission.
      this.#catalogTail = next.catch(() => {});
      return next;
    }
    return this.#submitCommand(command);
  }

  /** Remote intent, authorization and receipt share the ordinary native commit. */
  remoteCommand(controller_id, grant_epoch, request) {
    this.#publicCommand(request?.command);
    // DEFENSE: Authenticated remote JSON-RPC commands can omit their params or required command/receipt fields; preserve absence for native rejection.
    const intent = cloneJson(request?.command);
    const envelope = { controller_id, grant_epoch, request_id: request?.request_id, intent };
    const submit = () => this.#remoteSubmit(envelope);
    if (hasRootTaskCreation(intent)) {
      const next = this.#catalogTail.then(submit);
      // DEFENSE: One rejected remote command is reported by its returned promise and must not poison the shared configuration queue.
      this.#catalogTail = next.catch(() => {});
      return next;
    }
    return submit();
  }

  async #remoteSubmit(envelope) {
    // DEFENSE: A queued remote request can outlive service shutdown or a fatal journal failure.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    const probe = await this.journal.execute({ kind: 'remote_probe', ...envelope });
    // DEFENSE: The remote owner can revoke a grant or a client can send invalid receipt coordinates; do no filesystem work for a rejected intent.
    if (!probe.reply.ok) return { sequence: probe.sequence, reply: probe.reply };
    if (probe.reply.result?.replayed) return { sequence: probe.sequence, reply: probe.reply.result.reply };
    let command;
    let configuration;
    let rootFacts;
    try {
      command = await observeBoardCommand(admitRawWorkspaceCommand(envelope.intent), this.home);
      command = await observeMessageImages(command, this.home);
      command = await this.#observeCommandWorkspace(command);
      if (hasRootTaskCreation(envelope.intent)) {
        rootFacts = { project: await snapshotProject(this.cwd, this.limits), instructions: {
          configured: this.config.instructions,
          global: await snapshotGlobalInstructions(this.home, this.limits),
        } };
        configuration = this.#configuration(rootFacts);
      }
    // DEFENSE: A remote command can name unreadable files or unavailable workspaces; distinguish observation failure from an already committed command.
    } catch (cause) { throw new CommandNotSubmitted(cause); }
    // DEFENSE: Shutdown or a journal failure can occur during the awaited filesystem observations.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    const result = await this.journal.execute({ kind: 'remote_command', ...envelope, command,
      configuration: configuration ?? null });
    if (rootFacts && result.reply.ok) Object.assign(this, rootFacts);
    return { sequence: result.sequence, reply: result.reply };
  }

  remoteCheck(controller_id, grant_epoch) {
    // DEFENSE: A relay authorization check can arrive after local shutdown or a journal failure.
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#closing) return Promise.reject(new Error('Service is stopping'));
    return this.journal.execute({ kind: 'remote_check', controller_id, grant_epoch });
  }

  async #observeCommandWorkspace(command) {
    const plan = workspaceCommandPlan(command);
    // DEFENSE: A stale task command needs domain rejection, not an unrelated workspace lookup failure.
    if (!plan.observe) return cloneJson(command);
    // Cloud tasks inherit a fixed workspace. Core admits or rejects their options;
    // local repository observations cannot establish facts about that environment.
    if (command.task_id !== undefined) {
      const task = await this.#workspaceTask(command.task_id);
      if (task.kind === 'cloud' || task.kind === 'unknown') return cloneJson(command);
    }
    const selectedSettings = command.settings;
    let observed = await observeWorkspaceCommand(command, this.limits, {
      workspaceEnvironment: async selection => {
        const result = await this.journal.execute({ kind: 'command', command: { op: 'resolve_workspace', ...selection } });
        // DEFENSE: A selected cloud resource can be ambiguous, unavailable or archived before directory observation.
        if (!result.reply.ok) throw new Error(result.reply.error.message);
        const resource = result.reply.result.resource;
        return { resource, workspace_binding: result.reply.result.workspace_binding, ...await this.#resourceWorkspace(resource) };
      },
      projectWorkspace: async project_id => {
        const result = await this.journal.execute({ kind: 'command', command: { op: 'read_project', project_id } });
        return result.reply.ok ? result.reply.result.workspace : undefined;
      },
    });
    if (plan.worktree) {
      if (!observed.settings?.workspace) {
        observed = await observeWorkspaceCommand({ ...observed,
          settings: { ...observed.settings, workspace: { roots: [this.cwd], primary_root: this.cwd } } }, this.limits);
      }
      const primary = observed.settings.workspace.primary_root ?? observed.settings.workspace.roots[0];
      // DEFENSE: A requested worktree workspace may not be a Git repository with a commit to check out.
      if (!await observeWorkspaceGit(primary)) throw new TypeError('Create worktree requires a Git repository with an initial commit in the primary workspace');
      if (command.backend === 'tencent_cvm') {
        let projectPrimary = primary;
        if (selectedSettings?.project_id !== undefined && selectedSettings.project_id !== null) {
          const project = await this.journal.execute({ kind: 'command', command: { op: 'read_project', project_id: selectedSettings.project_id } });
          if (project.reply.ok) projectPrimary = project.reply.result.workspace.primary_root ?? project.reply.result.workspace.roots[0];
        }
        // DEFENSE: A project without a GitHub remote cannot be cloned into a task cloud environment.
        if (!await observeCloudRepository(projectPrimary)) throw new TypeError('Cloud task workspaces require a GitHub remote in the project primary workspace');
      }
    }
    return observed;
  }

  async #createRoot(command) {
    try {
      // DEFENSE: Root creation can wait behind catalog refresh while shutdown or another operation fails.
      if (this.#failure) throw this.#failure;
      if (this.#closing) throw new Error('Service is stopping');
      const instructions = { configured: this.config.instructions,
        global: await snapshotGlobalInstructions(this.home, this.limits) };
      const project = await snapshotProject(this.cwd, this.limits);
      const observed = await this.#observeCommandInput(command);
      const previous = { project: this.project, instructions: this.instructions };
      Object.assign(this, { project, instructions });
      try { await this.#configure(); }
      // DEFENSE: External catalog/configuration rejection must not publish this root's unaccepted observed defaults to later requests.
      catch (error) { Object.assign(this, previous); throw error; }
      return this.journal.execute({ kind: 'command', command: observed });
    // DEFENSE: Unreadable guidance or invalid workspace observations occur before command submission; return that distinct outcome to the caller.
    } catch (cause) { throw new CommandNotSubmitted(cause); }
  }

  async #observeCommandInput(command) {
    try {
      const imagesObserved = await observeMessageImages(admitRawWorkspaceCommand(command), this.home);
      const boardObserved = await observeBoardCommand(imagesObserved, this.home);
      return await this.#observeCommandWorkspace(boardObserved);
    // DEFENSE: Client-supplied paths or image references can fail their trusted host observation before domain submission.
    } catch (cause) { throw new CommandNotSubmitted(cause); }
  }

  async #submitCommand(command) {
    const observed = await this.#observeCommandInput(command);
    // DEFENSE: Shutdown or a fatal operation can occur while command filesystem observations are awaited.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    return this.journal.execute({ kind: 'command', command: observed });
  }

  refreshAccounts() {
    const next = this.#catalogTail.then(async () => {
      // DEFENSE: A queued account refresh can begin after shutdown or a fatal journal failure.
      if (this.#closing || this.#failure) throw new Error('Service is unavailable');
      const discovered = await withAccountModels(this.declaredConfig, this.home, { force: true });
      // DEFENSE: Account discovery awaits the network and may finish after the service has stopped.
      if (this.#closing || this.#failure) throw new Error('Service is unavailable');
      const previous = this.config;
      this.config = discovered.config;
      try { await this.#configure(); }
      // DEFENSE: A newly discovered external catalog can fail native configuration; restore the last accepted host configuration.
      catch (error) { this.config = previous; throw error; }
      this.accounts = discovered.accounts;
      return { accounts: this.accounts, profiles: profileCatalog(this.config) };
    });
    // DEFENSE: The refresh caller receives network/catalog failures; later queued commands must still run against the prior accepted configuration.
    this.#catalogTail = next.catch(() => {});
    return next;
  }

  #audioAdmission(kind, observations) {
    return requireAudioAdmission(boundary('http.audio', { kind, ...observations }));
  }

  audioCapabilities(options) {
    // DEFENSE: An already accepted HTTP request may resume during service shutdown.
    if (this.#closing || this.#failure) throw this.#failure ?? new Error('Service is stopping');
    return this.audio.capabilities(options);
  }

  audioLogin({ browser_id }, options) {
    // DEFENSE: A sign-in HTTP request can already be in flight when service shutdown starts.
    if (this.#closing || this.#failure) throw this.#failure ?? new Error('Service is stopping');
    return this.audio.startLogin(options);
  }

  async audioTranscribe({ browser_id, connection, audio, mime, language, elapsed_ms, signal }) {
    this.#audioAdmission('transcribe', { browser_id, body_bytes: audio.byteLength, elapsed_ms, mime });
    return this.audio.transcribe({ connection, audio, mime, language, signal });
  }

  async audioCreate({ browser_id, connection, task_id, sdp }, { signal } = {}) {
    // DEFENSE: Browser requests can race a previous connect before its upstream call is ready; reserve ownership before awaiting the call.
    const task = await this.command({ op: 'read', task_id });
    const session_count = [...this.#audioSessions.values()].filter(session => session.control.owner === browser_id).length;
    const plan = this.#audioAdmission('create', { browser_id, session_count, task_valid: task.reply.ok });
    const id = randomUUID();
    const generation = randomUUID();
    const session = { id, task_id, generation, started: Date.now(), progress: Promise.resolve(), maximum: plan.session_max_ms,
      control: boundary('control.audio.session_initial', { id, task_id, generation, browser_id, cursor: task.reply.result.cursor }) };
    this.#audioSessions.set(id, session);
    try {
      const contextPlan = boundary('audio.initial_context_plan', { cursor: task.reply.result.cursor });
      const observed = await this.command({ op: 'read', task_id, ...contextPlan });
      if (!observed.reply.ok) throw new Error(observed.reply.error.message);
      const page = observed.reply.result;
      const initial_items = boundary('audio.initial_context', { messages: page.messages, task: page.task });
      await this.#applyAudio(session, { kind: 'cursor', page, generation });
      const result = await this.audio.createSession({ id, generation, connection, task_id, sdp, initial_items, signal });
      // DEFENSE: A page can disappear after receiving the SDP response but before opening its owner event stream.
      session.connectMaximum = plan.connect_timeout_ms;
      await this.#applyAudio(session, { kind: 'connected', generation });
      return result;
    } catch (error) {
      await this.#applyAudio(session, { kind: 'creation_failed', generation });
      throw error;
    }
  }

  #audioTimer(session, duration) {
    clearTimeout(session.timer);
    session.timer = setTimeout(() => this.#stopAudio(session.id).catch(error => this.notify({ type: 'diagnostic', message: error.message })), duration);
    session.timer.unref();
  }

  #ownedAudio(id, browser_id) {
    const session = this.#audioSessions.get(id);
    const ownership = session ? boundary('control.audio.owner', { state: session.control }) : { owner: null, exists: false };
    this.#audioAdmission('session', { browser_id, ...ownership, elapsed_ms: session ? Date.now() - session.started : 0 });
    return session;
  }

  audioSubscribe(id, browser_id, observer) {
    const session = this.#ownedAudio(id, browser_id);
    this.#audioTimer(session, session.maximum - (Date.now() - session.started));
    const receive = event => { if (event.type === 'account_changed' || event.session_id === id) observer(event); };
    this.on('audio', receive);
    observer({ type: session.control.phase, session_id: id, task_id: session.task_id });
    return () => this.off('audio', receive);
  }

  async audioDisconnect(id, browser_id) {
    // DEFENSE: The stop response can close SSE after the same physical session has already been released.
    if (!this.#audioSessions.has(id)) return;
    this.#ownedAudio(id, browser_id);
    return this.#stopAudio(id);
  }

  async audioStop(id, browser_id) {
    this.#ownedAudio(id, browser_id);
    await this.#stopAudio(id);
    return { stopped: true };
  }

  async #stopAudio(id) {
    const session = this.#audioSessions.get(id);
    // DEFENSE: The SSE connection and explicit stop request can close the same physical session concurrently.
    if (!session) return;
    session.stopping ??= this.#applyAudio(session, { kind: 'stop', generation: session.generation });
    await session.stopping;
    await session.progress;
  }

  #speechCommand(command) {
    // The live connection fixes Task/session identity. These observations need no filesystem work and may flush while Service.close is releasing audio.
    return this.journal.execute({ kind: 'command', command });
  }

  async #applyAudio(session, observation) {
    return interpretAudioControl(boundary('control.audio.session_step', { state: session.control, observation }), {
      state: state => { session.control = state; },
      emit: event => { this.emit('audio', event); },
      journal: async (token, command) => {
        let result;
        try { result = await this.#speechCommand(command); }
        // DEFENSE: A journal failure leaves the speech commit outcome unresolved; retire this session instead of acknowledging or retrying it.
        catch (error) {
          await this.#applyAudio(session, { kind: 'journal_failed', generation: observation.generation, message: error.message });
          throw error;
        }
        await this.#applyAudio(session, { kind: 'ack', generation: observation.generation, token, reply: result.reply });
      },
      context: context => this.audio.appendContext(session.id, context),
      contexts: async (token, contexts) => {
        try {
          for (const context of contexts) await this.audio.appendContext(session.id, context);
          await this.#applyAudio(session, { kind: 'delivered', generation: observation.generation, token });
        } catch (error) {
          await this.#applyAudio(session, { kind: 'progress_failed', generation: observation.generation, token, message: error.message });
        }
      },
      timer: () => this.#audioTimer(session, session.maximum - (Date.now() - session.started)),
      connectTimer: () => this.#audioTimer(session, session.connectMaximum),
      stop: async () => {
        await this.audio.stopSession(session.id);
        await this.#applyAudio(session, { kind: 'event', generation: observation.generation, event: { type: 'closed' } });
      },
      release: () => {
        clearTimeout(session.timer);
        if (this.#audioSessions.get(session.id) === session) this.#audioSessions.delete(session.id);
      },
      read: (token, after) => {
        session.progress = session.progress.then(async () => {
          // DEFENSE: A queued progress read can outlive service shutdown; shutdown owns cancellation of physical IO.
          if (this.#closing || this.#failure) return;
          const result = await this.command({ op: 'read', task_id: session.task_id, after, limit: 100 });
          if (!result.reply.ok) throw new Error(result.reply.error.message);
          await this.#applyAudio(session, { kind: 'page', generation: observation.generation, token, page: result.reply.result });
        }).catch(error => this.#applyAudio(session, { kind: 'progress_failed', generation: observation.generation, token, message: error.message }));
      },
    });
  }

  async #audioEvent(event) {
    // NOTE: The local account authority constructs this event; the upstream sideband decoder cannot produce it.
    if (event.type === 'account_changed') {
      this.notify(event);
      this.emit('audio', event);
      return;
    }
    const session = this.#audioSessions.get(event.session_id);
    // DEFENSE: A physical callback can arrive after the matching session has been released.
    if (!session) return;
    await this.#applyAudio(session, { kind: 'event', event, generation: event.generation });
  }

  #queueAudioProgress(task_id) {
    for (const session of this.#audioSessions.values()) {
      if (!boundary('control.audio.task_matches', { state: session.control, task_id })) continue;
      void this.#applyAudio(session, { kind: 'progress', generation: session.generation });
    }
  }

  browserSnapshot() {
    // DEFENSE: A browser/relay request may reach snapshot delivery after shutdown or a fatal journal failure.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    return { namespace: this.journal.namespace, sequence: this.journal.sequence, program: this.journal.program };
  }

  browserStreams() {
    return structuredClone(this.#streams).map(stream => ({ ...stream, namespace: this.journal.namespace }));
  }

  async browserCommand(command) {
    const result = await this.command(command);
    return { namespace: this.journal.namespace, sequence: result.sequence, program: result.program, reply: result.reply };
  }

  async browserObservation(observation) {
    // DEFENSE: Browser requests already in flight can reach this method after the service stops.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    return interpretBrowserObservation(boundary('browser.observation', {
      phase: 'plan', observation, cwd: this.cwd, project_root: this.project.workspace
    }), {
      streams: () => {
        return { kind: 'streams', namespace: this.journal.namespace, streams: this.browserStreams() };
      },
      workspaceGit: async plan => {
        const environment = await this.#observationEnvironment(plan);
        try {
          const available = await observeWorkspaceGit(plan.primary, { environment });
          return boundary('browser.observation', { phase: 'complete', kind: plan.kind, available });
        }
        finally { await environment?.filesystem.close(); }
      },
      browseDirectories: async plan => {
        let environment;
        let outcome;
        try {
          environment = await this.#observationEnvironment(plan);
          const location = await browseDirectoryLocation(plan, () => boundary('browser.observation', {
            phase: 'resolve', plan, task_environment_present: Boolean(environment), task_root: environment?.root
          }), async location => (await canonicalWorkspace({ roots: [location] })).primary_root);
          const result = await browseDirectories(location, this.limits.frame_bytes, { filesystem: environment?.filesystem });
          outcome = result.ok ? { ok: true, value: result } : { ok: false, error: result.error };
        // DEFENSE: A browser's selected directory can disappear or deny access while it is being listed; return the browsing error to that form.
        } catch (error) {
          outcome = { ok: false, error: error.message };
        } finally { await environment?.filesystem.close(); }
        return boundary('browser.observation', { phase: 'complete', kind: plan.kind, ...outcome });
      },
      directories: async plan => {
        const environment = await this.#observationEnvironment(plan);
        try {
          const workspace = await canonicalWorkspace(plan.workspace, { filesystem: environment?.filesystem });
          const primary = workspace.primary_root ?? workspace.roots[0];
          const guidance = primary ? await snapshotProject(primary, this.limits, { filesystem: environment?.filesystem }) : null;
          return boundary('browser.observation', { phase: 'complete', kind: plan.kind, value: { workspace, guidance } });
        } finally { await environment?.filesystem.close(); }
      },
      skillCatalog: async plan => {
        let environment;
        let outcome;
        try {
          environment = await this.#observationEnvironment(plan);
          const workspace = await canonicalWorkspace(plan.workspace, { filesystem: environment?.filesystem });
          const skills = await observeSkillCatalog(workspace,
            { home: this.home, config: this.declaredConfig, limits: this.limits, environment });
          outcome = { ok: true, value: skills };
        // DEFENSE: A selected workspace, configuration or discovered skill file
        // can disappear or deny access while the user is opening the skill menu.
        } catch (error) {
          outcome = { ok: false, error: error.message };
        } finally { await environment?.filesystem.close(); }
        return boundary('browser.observation', { phase: 'complete', kind: plan.kind, ...outcome });
      },
    });
  }

  close() {
    // DEFENSE: Fatal notices, OS signals and failed startup can request shutdown concurrently; all receive the same completion.
    this.#closePromise ??= this.#close();
    return this.#closePromise;
  }

  async #close() {
    this.#closing = true;
    // DEFENSE: Network/process cleanup can fail; finish releasing all resources, then report every failed close to the caller.
    const settled = await Promise.allSettled([this.remote?.close(),
      ...[...this.#audioSessions.keys()].map(id => this.#stopAudio(id))]);
    settled.push(...await Promise.allSettled([this.audio?.close()]));
    if (this.#continuation) clearImmediate(this.#continuation);
    if (this.#compactionTimer) clearTimeout(this.#compactionTimer);
    this.#cancelRunning({ kind: 'shutdown' }, new Error('Server stopped'));
    settled.push(...await Promise.allSettled([...this.#running.values()].map(active => active.promise)));
    this.#processRegistry.clear();
    settled.push(...await Promise.allSettled([...this.#providerCancellations]));
    settled.push(...await Promise.allSettled([...this.#servers.values(), ...this.#plugins.values()].map(client => client.close())));
    settled.push(...await Promise.allSettled([this.#catalogTail]));
    settled.push(...await Promise.allSettled([this.journal?.close()]));
    const errors = settled.filter(result => result.status === 'rejected').map(result => result.reason);
    // DEFENSE: A denied process-group kill or failed SQLite/network close must remain visible after the rest of shutdown finishes.
    if (errors.length) throw new AggregateError(errors, 'Service shutdown failed');
  }
}
