import { boundary } from './public/model-boundary.mjs';
import { EventEmitter } from 'node:events';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { createChatGPTAudio } from './chatgpt-audio.mjs';
import { realpath } from 'node:fs/promises';
import { Journal } from './journal.mjs';
import { Mcp } from './mcp.mjs';
import { Plugin } from './plugins.mjs';
import { runBash, startBash, runReadImage } from './process.mjs';
import { snapshotProject, snapshotGlobalInstructions, observeWorkspaceCommand, hasRootTaskCreation, workspaceCommandPlan } from './project.mjs';
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
import { createTaskWorkspace, archiveTaskWorkspace, reconcileTaskWorkspace, rollbackTaskWorkspaceCreation, taskWorkspaceEnvironment, observeCloudRepository } from './task-workspaces.mjs';

/** Interpret committed effects. No task lifecycle or recovery policy lives here. */
export class CommandNotSubmitted extends Error {
  constructor(cause) {
    super(cause.message, { cause });
    this.name = 'CommandNotSubmitted';
  }
}

export class Service extends EventEmitter {
  #running = new Map();
  #processSessions = new Map();
  #completedProcesses = new Set();
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
          service.#dispatch(effect, decision.sequence, ordinal);
          if (effect.kind === 'plugin_events') ordinal += effect.events.length;
        }
      });
      service.journal.on('observerFailure', error => service.#fatal(error));
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
    for (const active of this.#running.values()) active.controller.abort(error);
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

  #dispatch(effect, sequence, firstOrdinal = 0) {
    // DEFENSE: A commit observer can reach later effects after an earlier effect made the service fatal or started shutdown.
    if (this.#closing || this.#failure) return;
    if (effect.kind === 'reset_model_session') {
      try { WebRequestStore.resetExisting(this.home, effect.task_id); }
      // DEFENSE: Resetting persisted Web receipts can fail in SQLite; the committed reset cannot be silently skipped.
      catch (error) { this.#fatal(error); }
      return;
    }
    if (effect.kind === 'plugin_events') {
      effect.events.forEach(({ recipients, ...event }, index) => {
        for (const reference of recipients) {
          const client = this.#plugins.get(reference.name);
          // DEFENSE: A frozen task can still name a plugin removed from current configuration or whose process has exited.
          if (client?.matches(reference)) client.enqueue({ sequence, ordinal: firstOrdinal + index, ...event });
          else this.notify({ type: 'diagnostic', message: `Plugin ${reference.name} notification route is unavailable`, event_id: { sequence, ordinal: firstOrdinal + index } });
        }
      });
      return;
    }
    if (effect.kind === 'cancel') {
      this.#cancelProvider(effect.task_id);
      for (const active of this.#running.values()) if (active.task === effect.task_id && !active.effect.kind.startsWith('worktree_')) {
        if (['approval'].includes(active.effect.kind)) this.#cancelProvider(active.effect);
        active.controller.abort(new Error('Task work cancelled'));
      }
      return;
    }
    if (effect.kind === 'cancel_ticket') {
      const active = this.#running.get(`${effect.task_id}:${effect.ticket}`);
      // DEFENSE: The physical operation may already have completed when its native cancellation is dispatched.
      if (active && ['model', 'approval'].includes(active.effect.kind)) this.#cancelProvider(active.effect);
      active?.controller.abort(new Error('Operation or model request cancelled'));
      return;
    }
    if (effect.kind === 'continue') {
      this.#continuation ??= setImmediate(() => {
        this.#continuation = undefined;
        // DEFENSE: Shutdown or a concurrent external failure can retire this scheduled callback before it runs.
        if (!this.#closing && !this.#failure) this.journal.execute({ kind: 'continue' }).then(result => {
          // DEFENSE: Advancing pending work can produce an output-limit rejection; report it instead of silently dropping scheduling.
          if (!result.reply.ok) throw new Error(`Scheduling could not advance: ${result.reply.error.message}`);
        }).catch(error => this.#fatal(error));
      });
      return;
    }
    if (effect.kind === 'compaction_clock') {
      if (this.#compactionTimer) clearTimeout(this.#compactionTimer);
      // The committed deadline is the scheduling decision. The timer supplies
      // only a clock observation, including after suspension or a delayed wake.
      this.#compactionTimer = setTimeout(() => {
        this.#compactionTimer = undefined;
        // DEFENSE: A clock callback queued before shutdown must not submit another journal input afterward.
        if (!this.#closing && !this.#failure) this.journal.execute({ kind: 'compaction_clock', now: Date.now() })
          .then(result => {
            // DEFENSE: Clock-triggered compaction can exceed the complete-decision budget; surface the native rejection.
            if (!result.reply.ok) throw new Error(`Clock observation rejected: ${result.reply.error.message}`);
          })
          .catch(error => this.#fatal(error));
      }, Math.min(2_147_483_647, Math.max(0, effect.deadline - Date.now())));
      this.#compactionTimer.unref();
      return;
    }
    if (effect.kind === 'compaction_cancel') {
      // DEFENSE: The compaction's physical request can already have finished before its cancellation effect is dispatched.
      this.#running.get(`${effect.task_id}:${effect.ticket}`)?.controller.abort(new Error('Compaction cancelled'));
      return;
    }
    if (effect.kind === 'chatgpt_cancel') {
      // DEFENSE: A ChatGPT subprocess can already have exited when the native cancellation arrives.
      this.#running.get(`chatgpt:${effect.operation_id}`)?.controller.abort(new Error('ChatGPT operation cancelled'));
      return;
    }
    const key = effect.kind.startsWith('worktree_') ? `${effect.kind}:${effect.task_id}` : effect.kind === 'chatgpt_exec' ? `chatgpt:${effect.operation_id}` :
      effect.kind === 'board_text' ? `board:${effect.card_id}:${effect.ticket}` : `${effect.task_id}:${effect.ticket}`;
    const controller = new AbortController();
    const active = { task: effect.task_id, effect, controller };
    this.#running.set(key, active);
    // DEFENSE: Journal settlement or an external interpreter can fail after dispatch; retire the service rather than execute further uncommitted work.
    active.promise = this.#perform(effect, controller.signal).catch(error => this.#fatal(error)).finally(() => this.#running.delete(key));
  }

  #cancelProvider(task) {
    const promise = cancelModelTask(task, this.config, this.home, this.limits)
      // DEFENSE: The provider can reject or lose a remote Stop request; keep local cancellation and report its unconfirmed remote outcome.
      .catch(error => this.notify({ type: 'diagnostic', message: `Remote cancellation was not confirmed: ${error.message}` }))
      .finally(() => this.#providerCancellations.delete(promise));
    this.#providerCancellations.add(promise);
  }

  async #runProcess(effect, signal) {
    const key = `${effect.task_id}:${effect.operation_id}`;
    const session = { mode: effect.call.arguments.mode ?? 'pipe' };
    // Register before observing the checkout or preparing the sandbox: a sibling
    // read/write effect can run while the original process is still starting.
    this.#processSessions.set(key, session);
    const prepared = this.#taskWorkspace(effect.task_id, signal).then(({ managedWorktreeRoot, environment }) =>
      startBash(effect.call.arguments, this.limits, { signal, execution: effect.execution, managedWorktreeRoot, environment,
        readOnlyPaths: [this.home], ...(environment ? {} : { artifactDirectory: path.join(this.home, 'artifacts') }) }));
    session.ready = prepared.then(({ read, write }) => { session.read = read; session.write = write; },
      error => { session.failure = { code: error.code ?? 'command_start_failed', message: error.message }; });
    try {
      const runtime = await prepared;
      return await runtime.result;
    } finally {
      this.#completedProcesses.add(key);
      while (this.#completedProcesses.size > 64) {
        const retired = this.#completedProcesses.values().next().value;
        this.#completedProcesses.delete(retired);
        this.#processSessions.delete(retired);
      }
    }
  }

  async #processTool(effect) {
    const reading = effect.tool.source.program.kind === 'ProcessRead';
    const arguments_ = boundary(reading ? 'effect.process_read_arguments' : 'effect.process_write_arguments',
      { arguments: effect.call.arguments });
    const session = this.#processSessions.get(`${effect.task_id}:${arguments_.operation_id}`);
    // DEFENSE: A caller can name another task's operation, an evicted completed
    // process, or an operation from before this service was restarted.
    if (!session) return { error: true, value: { error: { code: 'unknown_process',
      message: 'No retained Bash process exists for this task and operation_id' } } };
    try {
      if (reading) {
        const value = session.read ? session.read(arguments_.cursor) : {
          status: session.failure ? 'completed' : 'starting', mode: session.mode, output: '',
          start_cursor: '0', next_cursor: '0', omitted_characters: 0,
          ...(session.failure ? { completion: { error: true, exit_code: null, signal: null, reason: session.failure } } : {}),
        };
        return { error: false, value: { operation_id: arguments_.operation_id, ...value } };
      }
      await session.ready;
      // DEFENSE: Checkout observation or sandbox preparation can fail before a
      // writable process session is available to this already accepted call.
      if (session.failure) return { error: true, value: { error: session.failure } };
      const { operation_id, ...input } = arguments_;
      return { error: false, value: { operation_id, ...await session.write(input) } };
    } catch (error) {
      // DEFENSE: Live process reads/writes can report invalid cursors, closed
      // stdin, exited terminals or OS I/O failures without cancelling Bash.
      return { error: true, value: { error: { code: error.code ?? 'process_io_failed', message: error.message } } };
    }
  }

  async #perform(effect, signal) {
    if (effect.kind.startsWith('worktree_')) {
      if (effect.kind === 'worktree_archive') {
        // NOTE: An archived borrower can still be finishing subprocess cancellation.
        const running = [...this.#running.values()].filter(active => !active.effect.kind.startsWith('worktree_'));
        const resources = await Promise.all(running.map(active => active.task === undefined ? undefined : this.#worktree(active.task)));
        await Promise.all(running.filter((active, index) => active.task === effect.task_id || resources[index]?.root === effect.root)
          .map(active => active.promise));
      }
      const completion = await (effect.kind === 'worktree_create' ? createTaskWorkspace : archiveTaskWorkspace)(effect,
        this.#workspaceOptions(signal));
      // DEFENSE: A filesystem operation may finish after service shutdown; leave its physical receipt for recovery rather than submit a late input.
      if (!this.#closing && !this.#failure) {
        await this.#settleWorkspaceCompletion(effect, completion);
      }
      return;
    }
    let input;
    let observation;
    const cancelPreview = () => this.notify({ type: 'stream_cancel', task_id: effect.task_id, ticket: effect.ticket });
    if (effect.kind === 'model') {
      this.notify({ type: 'stream_start', task_id: effect.task_id, ticket: effect.ticket });
      signal.addEventListener('abort', cancelPreview, { once: true });
    }
    try {
      if (effect.kind === 'observe_context') {
        const { environment } = await this.#taskWorkspace(effect.task_id, signal);
        const observations = await observeContextSources(effect, { home: this.home, config: this.declaredConfig, limits: this.limits, signal, environment,
          onDiagnostic: message => this.notify({ type: 'diagnostic', message }) });
        input = boundary('effect.completion', { effect, result: { observations } });
      } else if (effect.kind === 'chatgpt_exec') {
        const environment = await this.#workspaceEnvironment(effect.execution.workspace);
        const result = await runBash(effect.arguments, this.limits, { signal, execution: effect.execution, environment, readOnlyPaths: [this.home] });
        input = boundary('effect.completion', { effect, result });
      } else if (effect.kind === 'board_text' || effect.kind === 'task_title') {
        input = boundary('effect.completion', { effect, result: await requestTaskText(effect, this.config, this.home, this.limits, { signal }) });
      } else if (effect.kind === 'approval') {
        input = boundary('effect.completion', { effect, result: await requestApproval(effect, this.config, this.home, this.limits, { signal }) });
      } else if (effect.kind === 'reasoning') {
        // A live native lease bypasses this branch entirely. The tokenizer and
        // evaluator are loaded only for a committed external observation.
        const { requestReasoning } = await import('./jev.mjs');
        const selected = await requestReasoning(effect, this.config, this.limits, { signal });
        input = boundary('effect.completion', { effect, result: selected });
      } else if (effect.kind === 'context_scope' || effect.kind === 'context_measure' || effect.kind === 'context_compaction') {
        const result = effect.kind === 'context_measure' || effect.kind === 'context_scope'
          ? await observeModelRequest(effect, this.config, this.home, this.limits, { signal })
          : await requestCompaction(effect, this.config, this.home, this.limits, { signal });
        input = boundary('effect.completion', { effect, result });
      } else if (effect.kind === 'model') {
        const items = await requestModel(effect, this.config, this.home, this.limits, {
          signal, onObservation: value => { observation = value; }, onDelta: (text, output_index) => this.notify({ type: 'delta', task_id: effect.task_id, ticket: effect.ticket, output_index, text }),
          onSnapshot: (text, output_index) => this.notify({ type: 'snapshot', task_id: effect.task_id, ticket: effect.ticket, output_index, text }),
          onRetry: retry => this.notify({ type: 'retry', task_id: effect.task_id, ticket: effect.ticket, ...retry }),
        });
        input = boundary('effect.completion', { effect, result: items });
      } else if (effect.kind === 'hook') {
        const client = this.#plugins.get(effect.plugin.name);
        // DEFENSE: A saved task can retain a required plugin whose configured process was removed on restart.
        if (!client) throw new Error('Required plugin route is unavailable');
        const outcome = await client.before(effect, { signal });
        input = boundary('effect.completion', { effect, result: outcome });
      } else if (effect.kind === 'after_hook') {
        const client = this.#plugins.get(effect.plugin.name);
        // DEFENSE: A saved after-hook can refer to a plugin removed from current configuration.
        if (!client) throw new Error('Required plugin route is unavailable');
        const outcome = await client.after(effect, { signal });
        input = boundary('effect.completion', { effect, result: outcome });
      } else {
        let result;
        if (effect.tool.source.kind === 'native') {
          if (effect.tool.source.program.kind === 'Process') result = await this.#runProcess(effect, signal);
          else if (effect.tool.source.program.kind === 'ReadImage') {
            const executionOptions = { signal, execution: effect.execution,
              ...await this.#taskWorkspace(effect.task_id, signal),
              readOnlyPaths: [this.home], home: this.home };
            result = await runReadImage(effect.call.arguments, this.limits, executionOptions);
          } else result = await this.#processTool(effect);
        } else if (effect.tool.source.plugin) {
          const client = this.#plugins.get(effect.tool.source.plugin.name);
          // DEFENSE: A frozen plugin tool contract can outlive that plugin's configured process.
          if (!client) throw new Error('Plugin tool route is unavailable');
          result = await client.call(effect, { signal });
        } else {
          const client = this.#servers.get(effect.tool.source.server);
          // DEFENSE: A frozen MCP tool contract can name a server removed from configuration on restart.
          if (!client) throw new Error('MCP route is unavailable');
          result = await client.call(effect.tool.source.name, effect.call.arguments, { signal });
        }
        input = boundary('effect.completion', { effect, result });
      }
    // DEFENSE: Filesystem/process/provider/plugin operations can fail or be cancelled; settle the committed effect with its typed error input.
    } catch (error) {
      input = this.#failureInput(effect, error.message, error instanceof ContextLimitError);
    }
    signal.removeEventListener('abort', cancelPreview);
    // DEFENSE: Shutdown can abort an operation while its external failure/success continuation is resuming.
    if (this.#closing || this.#failure) return;
    let result;
    try { result = await this.journal.execute(input); }
    catch (error) {
      // DEFENSE: An external result can exceed the frame limit before the kernel runs; settle that live ticket as a bounded error.
      if (!(error instanceof RangeError)) throw error;
      result = await this.journal.execute(this.#failureInput(effect, 'External result cannot fit the input contract'));
    }
    // DEFENSE: A result can fit the input frame but exceed the budget of its complete resulting decision.
    if (!result.reply.ok && result.reply.error.code === 'output_limit') {
      result = await this.journal.execute(this.#failureInput(effect, 'External result cannot fit the complete decision'));
    }
    // DEFENSE: Even the reduced failure completion can exceed a full world's output budget; surface the rejected settlement.
    if (!result.reply.ok) throw new Error(`Effect settlement rejected: ${result.reply.error.message}`);
    this.#queueAudioProgress(effect.task_id);
    if (effect.kind === 'model') {
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

  async #worktree(taskId) {
    const result = await this.journal.execute({ kind: 'command', command: { op: 'read_worktree', task_id: taskId } });
    if (!result.reply.ok) {
      if (result.reply.error.code === 'not_found') return undefined;
      // DEFENSE: A query can exceed its reply budget; losing that observation must not switch a cloud task to local execution.
      throw new Error(`Task workspace lookup rejected: ${result.reply.error.message}`);
    }
    return result.reply.result;
  }

  #workspaceOptions(signal) {
    return { home: this.home, limits: this.limits, namespace: this.journal.namespace, cloud: this.config.cloud, signal };
  }

  async #settleWorkspaceCompletion(effect, completion) {
    let failed;
    const submitFailure = async () => {
      failed ??= effect.kind === 'worktree_create' && effect.backend === 'tencent_cvm' && completion.ok
        ? rollbackTaskWorkspaceCreation(effect, { ...this.#workspaceOptions(), message: 'Cloud workspace completion exceeds the kernel boundary' })
        : boundary('effect.completion', { effect, result: { ok: false, root: completion.root ?? null,
          message: 'Managed worktree completion exceeds the kernel boundary; the checkout has been retained' } });
      return this.journal.execute(await failed);
    };
    let result;
    try { result = await this.journal.execute(completion); }
    // DEFENSE: Observed workspace metadata can exceed the input-frame budget after cloud allocation and setup completed.
    catch (error) {
      if (!(error instanceof RangeError)) throw error;
      result = await submitFailure();
    }
    // DEFENSE: A workspace completion can fit the input while its resulting decision exceeds the output budget.
    if (!result.reply.ok && result.reply.error.code === 'output_limit') result = await submitFailure();
    // DEFENSE: A reduced failure can still exceed the output budget; the physical rollback receipt must remain available for recovery.
    if (!result.reply.ok) throw new Error(`Managed worktree settlement rejected: ${result.reply.error.message}`);
    return result;
  }

  async #taskWorkspace(taskId, signal) {
    const entry = await this.#worktree(taskId);
    if (!entry) return {};
    if (entry.backend !== 'local') {
      // DEFENSE: A CVM archive API call can fail; the resource stays cloud-bound and an unavailable receipt must fail instead of selecting local execution.
      return { environment: await taskWorkspaceEnvironment(entry, this.#workspaceOptions(signal)) };
    }
    return entry.status === 'ready' ? { managedWorktreeRoot: entry.root } : {};
  }

  async #workspaceEnvironment(workspace) {
    if (!Array.isArray(workspace?.roots)) return undefined;
    const result = await this.journal.execute({ kind: 'command', command: { op: 'list_worktrees' } });
    if (!result.reply.ok) throw new Error(`Task workspace lookup rejected: ${result.reply.error.message}`);
    const contains = (root, candidate) => typeof candidate === 'string' && (candidate === root || candidate.startsWith(root + '/'));
    const entry = result.reply.result.worktrees.find(entry => entry.backend === 'tencent_cvm' &&
      workspace.roots.some(root => contains(entry.root, root)));
    if (!entry) return undefined;
    // DEFENSE: An explicit workspace selection can combine local roots or roots belonging to different cloud instances.
    if (workspace.roots.some(root => !contains(entry.root, root))) throw new TypeError('A workspace cannot combine different task environments');
    return taskWorkspaceEnvironment(entry, this.#workspaceOptions());
  }

  async #reconcileWorktrees() {
    const result = await this.journal.execute({ kind: 'command', command: { op: 'list_worktrees' } });
    // DEFENSE: A persisted collection of managed checkouts can exceed the query reply's frame budget.
    if (!result.reply.ok) throw new Error(`Managed worktree recovery query rejected: ${result.reply.error.message}`);
    for (const entry of result.reply.result.worktrees) {
      if (!['creating', 'creating_archived', 'archiving'].includes(entry.status)) continue;
      const completion = await reconcileTaskWorkspace(entry, this.#workspaceOptions());
      const settled = entry.backend === 'tencent_cvm'
        ? await this.#settleWorkspaceCompletion({ ...entry,
          kind: completion.kind === 'worktree_created' ? 'worktree_create' : 'worktree_archive' }, completion)
        : await this.journal.execute(completion);
      // DEFENSE: Recovered filesystem metadata must still pass native completion admission and complete-decision limits.
      if (!settled.reply.ok) throw new Error(`Managed worktree recovery rejected: ${settled.reply.error.message}`);
    }
  }

  #publicCommand(command) {
    // DEFENSE: Browser, CLI and remote command clients can forge upstream transcript and delegation objects; only the live sideband callback has that authority.
    if (!boundary('http.public_command', { command }).allowed) throw new CommandNotSubmitted(new TypeError('Speech observations require a live upstream session'));
  }

  async command(command) {
    this.#publicCommand(command);
    // DEFENSE: HTTP commands already in flight can reach the service after a fatal operation or shutdown.
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#closing) return Promise.reject(new Error('Service is stopping'));
    command = await observeMessageImages(command, this.home);
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
    const intent = structuredClone(request?.command);
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
      command = await observeBoardCommand(envelope.intent, this.home);
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
    const selectedSettings = command.settings;
    if (command.task_id !== undefined && selectedSettings &&
        (Object.hasOwn(selectedSettings, 'workspace') || Object.hasOwn(selectedSettings, 'project_id'))) {
      const owner = await this.#worktree(command.task_id);
      // DEFENSE: A fork request can explicitly select a local path for a task bound to a cloud environment.
      if (owner?.backend === 'tencent_cvm') throw new TypeError('Cloud task workspaces are fixed; omit workspace and project_id to inherit the environment');
    }
    let observed = await observeWorkspaceCommand(command, this.limits, {
      workspaceEnvironment: workspace => this.#workspaceEnvironment(workspace),
      projectWorkspace: async project_id => {
        const result = await this.journal.execute({ kind: 'command', command: { op: 'read_project', project_id } });
        return result.reply.ok ? result.reply.result.workspace : undefined;
      },
    });
    if (workspaceCommandPlan(command).worktree) {
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
      const observed = await this.#observeCommandWorkspace(command);
      const previous = { project: this.project, instructions: this.instructions };
      Object.assign(this, { project, instructions });
      try { await this.#configure(); }
      // DEFENSE: External catalog/configuration rejection must not publish this root's unaccepted observed defaults to later requests.
      catch (error) { Object.assign(this, previous); throw error; }
      return this.journal.execute({ kind: 'command', command: observed });
    // DEFENSE: Unreadable guidance or invalid workspace observations occur before command submission; return that distinct outcome to the caller.
    } catch (cause) { throw new CommandNotSubmitted(cause); }
  }

  async #submitCommand(command) {
    const boardObserved = await observeBoardCommand(command, this.home);
    let observed;
    try { observed = await observeWorkspaceCommand(boardObserved, this.limits); }
    // DEFENSE: Workspace paths supplied in a public command can be inaccessible or invalid before the native command is submitted.
    catch (cause) { throw new CommandNotSubmitted(cause); }
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
    const plan = boundary('http.audio', { kind, ...observations });
    // DEFENSE: Authenticated clients can exceed the native audio resource contract or name another browser's live session.
    if (!plan.allowed) throw new TypeError(plan.message);
    return plan;
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
    const session_count = [...this.#audioSessions.values()].filter(session => session.browser_id === browser_id).length;
    const plan = this.#audioAdmission('create', { browser_id, session_count, task_valid: task.reply.ok });
    const id = randomUUID();
    const session = { id, browser_id, task_id, started: Date.now(), cursor: task.reply.result.cursor,
      progress: Promise.resolve(), delegations: new Set(), state: 'connecting', maximum: plan.session_max_ms };
    this.#audioSessions.set(id, session);
    try {
      const contextPlan = boundary('audio.initial_context_plan', { cursor: task.reply.result.cursor });
      const observed = await this.command({ op: 'read', task_id, ...contextPlan });
      if (!observed.reply.ok) throw new Error(observed.reply.error.message);
      const page = observed.reply.result;
      const initial_items = boundary('audio.initial_context', { messages: page.messages, task: page.task });
      session.cursor = page.after + page.messages.length;
      const result = await this.audio.createSession({ id, connection, task_id, sdp, initial_items, signal });
      // DEFENSE: A page can disappear after receiving the SDP response but before opening its owner event stream.
      this.#audioTimer(session, plan.connect_timeout_ms);
      return result;
    } catch (error) {
      clearTimeout(session.timer);
      this.#audioSessions.delete(id);
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
    this.#audioAdmission('session', { browser_id, owner: session?.browser_id ?? null, exists: Boolean(session),
      elapsed_ms: session ? Date.now() - session.started : 0 });
    return session;
  }

  audioSubscribe(id, browser_id, observer) {
    const session = this.#ownedAudio(id, browser_id);
    this.#audioTimer(session, session.maximum - (Date.now() - session.started));
    const receive = event => { if (event.type === 'account_changed' || event.session_id === id) observer(event); };
    this.on('audio', receive);
    observer({ type: session.state, session_id: id, task_id: session.task_id });
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
    session.stopping ??= (async () => {
      await this.audio.stopSession(id);
      await session.progress;
      clearTimeout(session.timer);
      this.#audioSessions.delete(id);
      this.emit('audio', { type: 'stopped', session_id: id, task_id: session.task_id });
    })();
    return session.stopping;
  }

  #speechCommand(command) {
    // The live connection fixes Task/session identity. These observations need no filesystem work and may flush while Service.close is releasing audio.
    return this.journal.execute({ kind: 'command', command });
  }

  async #audioEvent(event) {
    // NOTE: The local account authority constructs this event; the upstream sideband decoder cannot produce it.
    if (event.type === 'account_changed') {
      this.notify(event);
      this.emit('audio', event);
      return;
    }
    const session = this.#audioSessions.get(event.session_id);
    // DEFENSE: A socket can deliver a final close notification after its physical session was released.
    if (!session) return;
    if (event.type === 'ready') {
      session.state = 'ready';
      this.emit('audio', { type: 'ready', session_id: session.id, task_id: session.task_id });
      this.#queueAudioProgress(session.task_id);
    } else if (event.type === 'transcript' && event.final) {
      const result = await this.#speechCommand({ op: 'record_speech_transcript', task_id: session.task_id,
        session_id: session.id, item_id: event.item_id, speaker: event.role, text: event.text,
        completion: event.completion ?? 'completed' });
      // DEFENSE: The trusted upstream can send conflicting item content or a Task may already have been removed.
      if (!result.reply.ok) throw new Error(result.reply.error.message);
      this.emit('audio', { ...event, task_id: session.task_id });
    } else if (event.type === 'delegation') {
      const result = await this.#speechCommand({ op: 'accept_speech_delegation', task_id: session.task_id,
        session_id: session.id, delegation_id: event.delegation_id, message: event.text, mode: event.mode ?? 'send' });
      // The durable receipt and queued Task input have committed before the sideband is told that work was accepted.
      await this.audio.appendContext(session.id, { delegation_item_id: event.delegation_id, channel: 'commentary',
        text: result.reply.ok ? `Task #${session.task_id} accepted the requested work.` : `The work was rejected: ${result.reply.error.message}` });
      if (result.reply.ok) {
        session.delegations.add(event.delegation_id);
        this.#queueAudioProgress(session.task_id);
      }
    } else if (event.type === 'delta') {
      this.emit('audio', { ...event, type: 'transcript', final: false, task_id: session.task_id });
    } else if (event.type === 'error') {
      this.emit('audio', { ...event, message: event.error ?? event.message, task_id: session.task_id });
    } else if (event.type === 'closed' || event.type === 'stopped') {
      clearTimeout(session.timer);
      this.emit('audio', { type: 'stopped', session_id: session.id, task_id: session.task_id, reason: event.reason });
      this.#audioSessions.delete(session.id);
    }
  }

  #queueAudioProgress(task_id) {
    for (const session of this.#audioSessions.values()) {
      if (session.task_id !== task_id || session.state !== 'ready' || session.stopping) continue;
      session.progress = session.progress.then(async () => {
        // DEFENSE: A queued progress read can outlive the voice connection or service shutdown.
        if (!this.#audioSessions.has(session.id) || this.#closing || this.#failure) return;
        const delegations = [...session.delegations];
        let page;
        do {
          const result = await this.command({ op: 'read', task_id, after: session.cursor, limit: 100 });
          if (!result.reply.ok) throw new Error(result.reply.error.message);
          page = result.reply.result;
          const updates = boundary('audio.task_progress', { messages: page.messages, task: page.task });
          session.cursor = page.after + page.messages.length;
          for (const update of updates) for (const delegation_item_id of delegations.length ? delegations : [undefined]) await this.audio.appendContext(session.id, {
            delegation_item_id, channel: update.channel,
            text: `Task #${task_id} progress (accepted requests can be combined): ${update.text}` });
        } while (page.has_more);
        if (page.task.phase === 'idle') for (const id of delegations) session.delegations.delete(id);
      }).catch(error => {
        // DEFENSE: An upstream close during delivery or a rejected native read must remain visible while ordinary Task execution continues.
        this.emit('audio', { type: 'error', session_id: session.id, task_id, message: error.message });
      });
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
    // DEFENSE: Authenticated HTTP clients can submit JSON null, arrays or scalars instead of an observation request.
    if (!observation || typeof observation !== 'object' || Array.isArray(observation)) throw new TypeError('Expected an observation request');
    // DEFENSE: Browser observation requests are external JSON; each admitted variant requires its declared fields and types.
    if (observation.kind === 'streams' && Object.keys(observation).length === 1) {
      return { kind: 'streams', namespace: this.journal.namespace, streams: this.browserStreams() };
    }
    if (observation.kind === 'workspace-git' && Object.keys(observation).length === 2 && typeof observation.primary === 'string') {
      const primary = observation.primary === '' ? this.cwd : observation.primary;
      return { kind: 'workspace-git', available: await observeWorkspaceGit(primary) };
    }
    if (observation.kind === 'browse-directories' && Object.keys(observation).length === 2) {
      let environment;
      try {
        let location = observation.path;
        if (location === '') {
          const workspace = await canonicalWorkspace({ roots: [this.project.workspace] });
          location = workspace.primary_root;
        }
        environment = await this.#workspaceEnvironment({ roots: [location] });
        return await browseDirectories(location, this.limits.frame_bytes, { filesystem: environment?.filesystem });
      // DEFENSE: A browser's selected directory can disappear or deny access while it is being listed; return the browsing error to that form.
      } catch (error) {
        return { ok: false, error: error.message };
      } finally { await environment?.filesystem.close(); }
    }
    if (observation.kind === 'directories' && Object.keys(observation).length === 2 && observation.workspace) {
      const environment = await this.#workspaceEnvironment(observation.workspace);
      try {
        const workspace = await canonicalWorkspace(observation.workspace, { filesystem: environment?.filesystem });
        const primary = workspace.primary_root ?? workspace.roots[0];
        const guidance = primary ? await snapshotProject(primary, this.limits, { filesystem: environment?.filesystem }) : null;
        return { kind: 'directories', workspace, guidance };
      } finally { await environment?.filesystem.close(); }
    }
    if (observation.kind === 'skill-catalog' && Object.keys(observation).length === 2 && observation.workspace) {
      let environment;
      try {
        environment = await this.#workspaceEnvironment(observation.workspace);
        const workspace = await canonicalWorkspace(observation.workspace, { filesystem: environment?.filesystem });
        const skills = await observeSkillCatalog(workspace,
          { home: this.home, config: this.declaredConfig, limits: this.limits, environment });
        return { kind: 'skill-catalog', ok: true, skills };
      // DEFENSE: A selected workspace, configuration or discovered skill file
      // can disappear or deny access while the user is opening the skill menu.
      } catch (error) {
        return { kind: 'skill-catalog', ok: false, error: error.message };
      } finally { await environment?.filesystem.close(); }
    }
    // DEFENSE: A client can send an unknown observation kind or fields outside its declared request variant.
    throw new TypeError('Unknown browser observation');
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
    for (const active of this.#running.values()) active.controller.abort(new Error('Server stopped'));
    settled.push(...await Promise.allSettled([...this.#running.values()].map(active => active.promise)));
    this.#processSessions.clear();
    this.#completedProcesses.clear();
    settled.push(...await Promise.allSettled([...this.#providerCancellations]));
    settled.push(...await Promise.allSettled([...this.#servers.values(), ...this.#plugins.values()].map(client => client.close())));
    settled.push(...await Promise.allSettled([this.#catalogTail]));
    settled.push(...await Promise.allSettled([this.journal?.close()]));
    const errors = settled.filter(result => result.status === 'rejected').map(result => result.reason);
    // DEFENSE: A denied process-group kill or failed SQLite/network close must remain visible after the rest of shutdown finishes.
    if (errors.length) throw new AggregateError(errors, 'Service shutdown failed');
  }
}
