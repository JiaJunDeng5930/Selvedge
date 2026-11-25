import { cloneJson } from './codec.mjs';
import { boundary } from './public/model-boundary.mjs';
import { requireAudioAdmission, interpretBrowserObservation, browseDirectoryLocation, interpretAudioControl } from './model-api.ts';
import { EventEmitter } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { launchEffect, settleEffect } from './effect-lifecycle.ts';
import { DispatchControl } from './dispatch-control.mjs';
import { materializeCallArguments } from './public/call-wire.mjs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { createChatGPTAudio } from './chatgpt-audio.mjs';
import { realpath } from 'node:fs/promises';
import { Journal, isDefiniteRejection, transactionOutcome } from './journal.mjs';
import { naturalKey, stringifyJson } from './public/json-tokens.mjs';
import { dispatchEffect, performEffect, modelEffect, workspaceOperation, compactionOperation, workspaceEffect, clockDelay } from './effect-dispatch.ts';
import { Mcp, discoverMcp, completeSharedMcp } from './mcp.mjs';
import { Plugin } from './plugins.mjs';
import { startBash, runReadImage } from './process.mjs';
import { ProcessRegistry } from './process-registry.mjs';
import { snapshotProject, snapshotGlobalInstructions, observeWorkspaceCommand, admitRawWorkspaceCommand, hasRootTaskCreation, workspaceCommandPlan } from './project.mjs';
import { observeContextSources, observeSkillCatalog } from './context-sources.mjs';
import { requestApproval } from './approvals.mjs';
import { requestTaskText } from './task-text.mjs';
import { browserHistoryReply } from './history-preview.mjs';
import { browserOutline, programTask, programWithTaskArray, selectUpdateHistory } from './public/program-updates.mjs';
import { observeBoardCommand, observeMessageImages } from './board-files.mjs';
import { requestModel, requestCompaction, observeModelRequest, cancelModelTask, ContextLimitError } from './providers.mjs';
import { canonicalWorkspace } from './sandbox.mjs';
import { browseDirectories, directoryListingFailure } from './directories.mjs';
import { profileCatalog, compactionSettings } from './config.mjs';
import { withAccountModels } from './chatgpt-models.mjs';
import { connectionGrants } from './chatgpt-plugin.mjs';
import { WebRequestStore } from './chatgpt-web-store.mjs';
import { ExecutionEnvironments, receiveExecution } from './shared-execution.mjs';
import { RemoteControl } from './remote-control.mjs';
import { observeWorkspaceGit } from './worktrees.mjs';
import { createTaskWorkspace, archiveTaskWorkspace, reconcileTaskWorkspace, rollbackTaskWorkspaceCreation,
  taskWorkspaceEnvironment, observeCloudRepository } from './task-workspaces.mjs';

const TOOL_OUTPUT_INTERVAL_MS = 160;
const TOOL_OUTPUT_PREVIEW_POINTS = 4096;
const TOOL_SNAPSHOT_PREVIEW_POINTS = 32768;
const PROCESS_RESULT_JOIN_MS = 500;

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

export class ServiceDrainingError extends Error {
  constructor() {
    super('Selvedge is draining for an update');
    this.name = 'ServiceDrainingError';
    this.status = 503;
  }
}

export class Service extends EventEmitter {
  #running = new Map();
  #submissions = new Set();
  #effectControl = new DispatchControl();
  #processRegistry = new ProcessRegistry();
  #providerCancellations = new Set();
  #servers = new Map();
  #catalog = new Map();
  #plugins = new Map();
  #pluginCatalog = new Map();
  #continuation;
  #continuationInFlight = false;
  #continuationPending = false;
  #compactionTimer;
  #compactionClock;
  #heldStartup;
  #activation;
  #drainPromise;
  #drainProgress;
  #closing = false;
  #failure;
  #catalogTail = Promise.resolve();
  #observationTail = Promise.resolve();
  #catalogRefreshes = new Map();
  #sharedMcp = new Map();
  #closePromise;
  #streams = new Map();
  #toolActivity = new Set();
  #audioSessions = new Map();
  #contextDiscovery = new Map();
  #recentProcesses = new Map();

  static async open({ home, config, cwd = process.cwd(), remoteOptions, audioOptions,
    audioFactory = createChatGPTAudio, holdEffects = false, journal } = {}) {
    // DEFENSE: The process sandbox supports only the Linux and macOS implementations; refuse other OS launches.
    if (!['linux', 'darwin'].includes(process.platform)) throw new Error('Selvedge supports Linux and macOS only');
    const service = new Service();
    if (holdEffects) service.#heldStartup = { decisions: [], worktrees: [] };
    Object.assign(service, { home, config, declaredConfig: config, cwd: await realpath(cwd) });
    try {
      service.journal = journal ?? await Journal.open(path.join(home, 'journal.sqlite'));
      service.description = service.journal.description;
      service.limits = service.description.limits;
      service.executionEnvironments = new ExecutionEnvironments(config.execution_environments ?? []);
      service.project = await snapshotProject(service.cwd, service.limits);
      service.instructions = { configured: config.instructions,
        global: await snapshotGlobalInstructions(home, service.limits) };
      const discovered = await withAccountModels(config, home, {
        onDiagnostic: message => service.notify({ type: 'diagnostic', message }),
      });
      service.config = discovered.config;
      service.accounts = discovered.accounts;
      service.journal.on('transient', decision => {
        if (service.#heldStartup) service.#heldStartup.decisions.push(decision);
        else service.#scheduleContinuation();
      });
      service.journal.on('commit', (decision, browserRequest) => {
        const update = service.journal.programUpdates(decision.sequence - 1, decision.sequence)?.[0];
        for (const row of update?.tasks ?? [])
          if (!row.value.working) service.#contextDiscovery.delete(String(row.id));
        service.notify({ type: 'commit', sequence: decision.sequence, browser_request_id: browserRequest });
        if (service.#heldStartup) service.#heldStartup.decisions.push(decision);
        else service.#deliverEffects(decision);
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
          // DEFENSE: A plugin can exit after update drain freezes new catalog work.
          if (service.draining) return;
          service.#catalogTail = service.#catalogTail.then(async () => {
            // DEFENSE: An unavailable-plugin callback may be queued when service shutdown or a journal failure begins.
            if (service.#closing || service.#failure) return;
            service.#pluginCatalog.delete(name);
            await service.#publishCatalog();
          }).catch(error => service.#fatal(error));
        });
      }));
      await service.#discoverSharedMcp(config.shared_mcp ?? []);
      await service.#publishCatalog();
      service.#watchSharedMcp();
      await service.#publishCompactionPolicy();
      const recovery = await service.journal.execute({ kind: 'recover' });
      // DEFENSE: Recovery resends pending model effects; their combined payload can exceed the complete-decision budget and leave recovery uncommitted.
      if (!recovery.reply.ok) throw new Error(`Recovery rejected: ${recovery.reply.error.message}`);
      const worktrees = await service.#pendingWorktrees();
      if (service.#heldStartup) service.#heldStartup.worktrees = worktrees;
      else await service.#reconcileWorktrees(worktrees);
      const grants = await service.command({ op: 'configure_chatgpt_connections', connections: connectionGrants(config.chatgpt_plugin) });
      // DEFENSE: Saved connection grants can refer to projects removed from the current journal; startup must report native configuration rejection.
      if (!grants.reply.ok) throw new Error(`ChatGPT connection configuration rejected: ${grants.reply.error.message}`);
      service.remote = await RemoteControl.open(service, { ...remoteOptions, deferConnect: holdEffects });
      service.audio = audioFactory({ config: () => service.declaredConfig, home, ...audioOptions,
        onEvent: event => service.#audioEvent(event) });
      const receiver = config.execution_receiver;
      if (receiver) {
        service.executionReceiver = await receiveExecution({
          home, host: receiver.host, port: receiver.port, certFile: receiver.cert_file,
          keyFile: receiver.key_file, tokenFile: receiver.token_file, receiptHome: receiver.receipt_home,
          localMcp: service.#servers, mcpExports: receiver.mcp_servers,
          accepting: () => !service.draining && !service.#closing && !service.#failure,
        });
      }
      // DEFENSE: Asynchronous catalog failure can retire a service while startup is awaiting external configuration.
      if (service.#failure) throw service.#failure;
      return service;
    // DEFENSE: Account, filesystem or subprocess initialization can fail after the journal and clients opened; release those acquired resources.
    } catch (error) {
      await service.close();
      throw error;
    }
  }

  activate() {
    const startup = this.#heldStartup;
    if (!startup) return;
    this.#heldStartup = undefined;
    this.#activation = this.#activate(startup).catch(error => this.#fatal(error));
  }

  async #activate({ decisions, worktrees }) {
    for (const decision of decisions) this.#deliverEffects(decision);
    await this.#reconcileWorktrees(worktrees);
    await this.remote.reconcile();
  }

  notify(event) {
    event = { ...event, namespace: this.journal.namespace };
    for (const observer of this.listeners('notice')) observer(event);
  }

  #publishStreamNotice(event) {
    const key = `${naturalKey(event.task_id)}:${naturalKey(event.ticket)}`;
    const current = this.#streams.get(key);
    const { state } = boundary('browser.host_stream_step', { state: current ? [current] : [], notice: event });
    if (state.length) this.#streams.set(key, state[0]);
    else this.#streams.delete(key);
    this.notify(event);
  }

  #fatal(error) {
    // DEFENSE: Several active operations can observe the same journal/Worker failure while shutdown is already in progress.
    if (this.#failure || this.#closing) return;
    this.#failure = error;
    this.notify({ type: 'fatal', message: error.message });
    this.#cancelRunning({ kind: 'shutdown' }, error);
    this.journal.abort(error);
  }

  async #publishCatalog(maintenance) {
    // Configuration order, not process initialization speed, defines the chain.
    const extensions = Object.keys(this.config.plugins).flatMap(name => this.#pluginCatalog.has(name) ? [this.#pluginCatalog.get(name)] : []);
    const catalog = { profiles: profileCatalog(this.config),
      tools: [...this.#catalog.values(), ...extensions.map(extension => extension.tools)].flat(),
      plugins: extensions.map(extension => extension.descriptor), max_fork: this.config.max_fork, max_descendants: this.config.max_descendants,
      project: this.project, instructions: this.instructions };
    const decision = await this.journal.execute({ kind: 'configure_catalog', catalog, maintenance });
    // DEFENSE: Independently supplied MCP/plugin catalogs can conflict or exceed native configuration limits.
    if (!decision.reply.ok) throw new Error(`Catalog rejected: ${decision.reply.error.message}`);
  }

  async #publishCompactionPolicy() {
    const compaction = await this.journal.execute({ kind: 'configure_compaction_policy', policy: compactionSettings(this.config), now: Date.now() });
    // DEFENSE: Account-advertised context windows can make configured compaction budgets invalid or too large for a complete decision.
    if (!compaction.reply.ok) throw new Error(`Compaction configuration rejected: ${compaction.reply.error.message}`);
  }

  async #discoverSharedMcp(imports) {
    for (const route of imports) {
      const { peer } = this.executionEnvironments.get(route.environment);
      this.#sharedMcp.set(route.name, {
        route, peer, discover: () => discoverMcp(route, this.limits, this.limits.mcp_timeout_ms,
          (cursor, options) => peer.mcpPage(route.server, cursor, options)),
      });
    }
    await Promise.all([...this.#sharedMcp].map(async ([name, client]) => {
      try { this.#catalog.set(name, await client.discover()); }
      // DEFENSE: A configured receiver can be offline while the local service starts.
      catch (error) { this.notify({ type: 'diagnostic', message: `MCP ${name}: ${error.message}` }); }
    }));
  }

  #watchSharedMcp() {
    const peers = new Map();
    for (const client of this.#sharedMcp.values()) {
      const routes = peers.get(client.peer) ?? [];
      routes.push(client.route);
      peers.set(client.peer, routes);
    }
    for (const [peer, routes] of peers) peer.watchMcp((available, server) => {
      for (const route of routes) {
        if (server === undefined || route.server === server) this.#refreshCatalog(route.name, available);
      }
    });
  }

  #refreshCatalog(name, discover) {
    // DEFENSE: An MCP server can send a catalog notification while the update drains existing work.
    if (this.draining) return;
    const queued = this.#catalogRefreshes.has(name);
    this.#catalogRefreshes.set(name, discover);
    // DEFENSE: A server can send repeated list_changed notifications before
    // its queued query starts; that query observes their latest catalog.
    if (queued) return;
    this.#catalogTail = this.#catalogTail.then(async () => {
      const discover = this.#catalogRefreshes.get(name);
      this.#catalogRefreshes.delete(name);
      // DEFENSE: A queued subprocess catalog refresh can outlive service shutdown or a fatal journal failure.
      if (this.#closing || this.#failure) return;
      if (discover) {
        const client = this.#servers.get(name) ?? this.#sharedMcp.get(name);
        try { this.#catalog.set(name, await client.discover()); }
        // DEFENSE: MCP rediscovery can time out, return malformed tools or lose its process; withdraw that live catalog and diagnose the failure.
        catch (error) { this.#catalog.delete(name); this.notify({ type: 'diagnostic', message: `MCP ${name}: ${error.message}` }); }
      } else this.#catalog.delete(name);
      // DEFENSE: Shutdown can start while MCP rediscovery awaits the subprocess.
      if (!this.#closing) await this.#publishCatalog();
    }).catch(error => this.#fatal(error));
  }

  #dispatchControl(observation) {
    return this.#effectControl.step(observation);
  }

  #cancelRunning(observation, reason) {
    for (const action of this.#dispatchControl(observation).cancellations) {
      const active = this.#running.get(naturalKey(action.generation));
      // Keep the registered invocation through synchronous receipt retirement;
      // aborting its observer must not retarget a later task request.
      if (action.provider) this.#cancelProvider(active.effect);
      active.controller.abort(reason);
    }
  }

  #deliverEffects({ sequence, effects, reconcileRemote }) {
    if (reconcileRemote) this.remote?.reconcile();
    let ordinal = 0;
    for (const effect of effects) ordinal += this.#dispatch(effect, sequence, ordinal);
  }

  #scheduleContinuation() {
    this.#continuationPending = true;
    if (this.draining || this.#continuationInFlight) return;
    this.#continuation ??= setImmediate(() => {
      this.#continuation = undefined;
      this.#continuationPending = false;
      // DEFENSE: Shutdown can retire this scheduled observation before it runs.
      if (this.#closing || this.#failure) return;
      // A commit can request more scheduling while this one is still queued.
      // Keep one follow-up so scheduling cannot fill the journal ahead of a command.
      this.#continuationInFlight = true;
      this.#trackSubmission(this.journal.execute({ kind: 'continue' }).then(result => {
        // DEFENSE: A full resulting decision can exceed the kernel output budget.
        if (!result.reply.ok) throw new Error(`Scheduling could not advance: ${result.reply.error.message}`);
      }).catch(error => this.#fatal(error)).finally(() => {
        this.#continuationInFlight = false;
        if (this.#continuationPending && !this.#closing && !this.#failure) this.#scheduleContinuation();
      }));
    });
  }

  #scheduleCompactionClock(effect) {
    this.#compactionClock = effect;
    if (this.draining) return;
    clearTimeout(this.#compactionTimer);
    this.#compactionTimer = setTimeout(() => {
      this.#compactionTimer = undefined;
      this.#compactionClock = undefined;
      // DEFENSE: Shutdown can retire this clock observation before it runs.
      if (!this.#closing && !this.#failure) this.#trackSubmission(this.journal.execute({ kind: 'compaction_clock', now: Date.now() })
        .then(result => {
          // DEFENSE: Clock-triggered work can exceed the complete-decision budget.
          if (!result.reply.ok) throw new Error(`Clock observation rejected: ${result.reply.error.message}`);
        }).catch(error => this.#fatal(error)));
    }, clockDelay(effect, Date.now()));
    this.#compactionTimer.unref();
  }

  #dispatch(effect, sequence, firstOrdinal) {
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
        this.#contextDiscovery.delete(naturalKey(effect.task_id));
        this.#cancelProvider(effect.task_id);
        this.#cancelRunning({ kind: 'cancel_task', effect }, new Error('Task work cancelled'));
      },
      cancelKey: effect => this.#cancelRunning({ kind: 'cancel_key', effect }, new Error('Operation cancelled')),
      continue: () => this.#scheduleContinuation(),
      clock: effect => this.#scheduleCompactionClock(effect),
      start: effect => {
        // Background execution observes failures separately; the runner retains its rejecting promise.
        void this.#launch(effect, (handle, signal) => effect.kind === 'tool'
          ? this.#performObservedTool(effect, signal, handle)
          : this.#perform(effect, signal, handle))
          .catch(error => this.#fatal(error));
      },
    });
  }

  #launch(effect, run) {
    const result = launchEffect(observation => this.#dispatchControl(observation), this.#running, effect, run);
    this.#drainProgress?.();
    if (effect.kind === 'tool' && effect.tool.source.kind === 'native' && effect.tool.source.program.kind === 'Process') {
      const owner = naturalKey(effect.task_id);
      const processes = this.#recentProcesses.get(owner) ?? new Set();
      this.#recentProcesses.set(owner, processes);
      const process = { result, until: performance.now() + PROCESS_RESULT_JOIN_MS };
      processes.add(process);
      return result.finally(() => {
        processes.delete(process);
        if (!processes.size) this.#recentProcesses.delete(owner);
        this.#drainProgress?.();
      });
    }
    return result.finally(() => this.#drainProgress?.());
  }

  async #joinProcessResults(task, signal) {
    const processes = this.#recentProcesses.get(naturalKey(task));
    if (!processes) return;
    // Context preparation overlaps this bounded wait. An early process result
    // can then be included in the imminent request.
    const now = performance.now();
    const joined = [...processes].filter(process => process.until > now);
    if (!joined.length) return;
    const deadline = Math.max(...joined.map(process => process.until));
    const timer = new AbortController();
    try {
      await Promise.race([
        Promise.allSettled(joined.map(process => process.result)),
        delay(Math.ceil(deadline - now), undefined, { signal: AbortSignal.any([signal, timer.signal]), ref: false }),
      ]);
    } finally { timer.abort(); }
  }

  #cancelProvider(task) {
    const promise = cancelModelTask(task, this.config, this.home, this.limits)
      // DEFENSE: The provider can reject or lose a remote Stop request; keep local cancellation and report its unconfirmed remote outcome.
      .catch(error => this.notify({ type: 'diagnostic', message: `Remote cancellation was not confirmed: ${error.message}` }))
      .finally(() => this.#providerCancellations.delete(promise));
    this.#providerCancellations.add(promise);
  }

  #toolActivitySnapshot(activity, previewLimit = TOOL_OUTPUT_PREVIEW_POINTS) {
    const { identity, startedAt, readOutput } = activity;
    return { ...identity, started_at: startedAt,
      ...(readOutput && previewLimit > 0 ? { output: readOutput(previewLimit) } : {}) };
  }

  async #performObservedTool(effect, signal, handle) {
    const identity = { task_id: effect.task_id, operation_id: effect.operation_id, call_id: effect.call.id };
    const activity = { identity, startedAt: Date.now(), readOutput: undefined, outputTimer: undefined };
    this.#toolActivity.add(activity);
    try {
      this.notify({ type: 'tool_activity', ...this.#toolActivitySnapshot(activity) });
      await this.#perform(effect, signal, handle, activity);
    } finally {
      clearTimeout(activity.outputTimer);
      this.#toolActivity.delete(activity);
      // Settlement publishes its commit before releasing this observation.
      this.notify({ type: 'tool_activity', ...identity, started_at: null });
    }
  }

  #scheduleToolOutput(activity, readOutput) {
    activity.readOutput = readOutput;
    activity.outputTimer ??= setTimeout(() => {
      activity.outputTimer = undefined;
      this.notify({ type: 'tool_activity', ...this.#toolActivitySnapshot(activity) });
    }, TOOL_OUTPUT_INTERVAL_MS);
  }

  async #runProcess(effect, signal, activity) {
    const key = `${naturalKey(effect.task_id)}:${naturalKey(effect.operation_id)}`;
    // Register before observing the checkout or preparing the sandbox: a sibling
    // read/write effect can run while the original process is still starting.
    const arguments_ = materializeCallArguments(effect.call);
    const session = this.#processRegistry.register(key, arguments_.mode ?? 'pipe');
    const prepared = Promise.resolve().then(async () => {
      const onOutput = readOutput => this.#scheduleToolOutput(activity, readOutput);
      const { execution } = effect;
      if (execution.workspace.environment) {
        return this.executionEnvironments.get(execution.workspace.environment, signal).peer.operation(
          this.#sharedOperationId(effect), 'bash', arguments_, execution,
          { signal, onOutput, onDiagnostic: message => this.notify({ type: 'diagnostic', message }) });
      }
      const { managedWorktreeRoot, environment } = await this.#resourceWorkspace(execution.resource, signal);
      return startBash(arguments_, this.limits, { signal, execution, managedWorktreeRoot, environment, onOutput,
        readOnlyPaths: [this.home], ...(environment ? {} : { artifactDirectory: path.join(this.home, 'artifacts') }) });
    });
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
        const value = session.read ? await session.read(arguments_.cursor) : pending;
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
        : active.effect.task_id === undefined ? undefined : this.#worktree(active.effect.task_id)));
      const plan = this.#dispatchControl({ kind: 'workspace_barrier', effect,
        running: running.map((active, index) => ({ generation: active.handle.generation,
          task: active.effect.task_id ?? null, resource: resources[index] ?? null,
          local_overlap: effect.backend === 'local' && !!active.effect.execution && !resources[index] &&
            (active.effect.execution.workspace.environment ?? null) === (effect.environment ?? null) &&
            active.effect.execution.workspace.roots.some(root => directoriesOverlap(root, effect.root)) })) });
      await Promise.all(plan.awaits.map(generation => this.#running.get(naturalKey(generation))?.promise));
    }
    const completion = await (workspaceOperation(effect) === 'create' ? createTaskWorkspace : archiveTaskWorkspace)(effect,
      this.#workspaceOptions(signal));
    // DEFENSE: Shutdown can finish before the physical operation; preserve its receipt for recovery.
    if (!this.#closing && !this.#failure) await this.#settleWorkspaceCompletion(effect, completion, handle);
  }


  async #perform(effect, signal, handle, activity) {
    let input;
    let observation;
    const model = modelEffect(effect);
    const cancelPreview = () => this.#publishStreamNotice({ type: 'stream_cancel', task_id: effect.task_id, ticket: effect.ticket });
    try {
      const performed = await performEffect(effect, {
        workspace: effect => this.#performWorkspace(effect, signal, handle),
        context: async effect => {
          const { environment } = await this.#executionWorkspace(effect.settings.workspace, effect.resource, signal);
          signal?.throwIfAborted();
          const owner = naturalKey(effect.task_id);
          const scope = stringifyJson([effect.turn, effect.settings.workspace, effect.resource]);
          let observed = this.#contextDiscovery.get(owner);
          if (observed?.scope !== scope) {
            observed = { scope, entries: new Map() };
            this.#contextDiscovery.set(owner, observed);
          }
          const [observations] = await Promise.all([
            observeContextSources(effect, { home: this.home, config: this.declaredConfig, limits: this.limits, signal, environment,
              discovery: observed.entries,
              onDiagnostic: message => this.notify({ type: 'diagnostic', message }) }),
            this.#joinProcessResults(effect.task_id, signal),
          ]);
          return { observations };
        },
        chatgpt: async effect => {
          const { execution } = effect;
          if (execution.workspace.environment) {
            return this.executionEnvironments.get(execution.workspace.environment, signal).peer.operation(
              `${this.journal.namespace}:connection:${naturalKey(effect.operation_id)}`, 'bash', effect.arguments, execution, { signal }).result;
          }
          const resource = await this.#resourceWorkspace(effect.execution.resource, signal);
          return startBash(effect.arguments, this.limits, { signal, execution: effect.execution, ...resource, readOnlyPaths: [this.home] }).result;
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
          this.#publishStreamNotice({ type: 'stream_start', task_id: effect.task_id, ticket: effect.ticket });
          signal.addEventListener('abort', cancelPreview, { once: true });
          return requestModel(effect, this.config, this.home, this.limits, {
            signal,
            realtime: () => {
              if (!effect.realtime_context.length) return undefined;
              const now = Date.now();
              return { now, current_time: new Date(now).toISOString(), started_at: this.journal.taskCreatedAt(effect.task_id) };
            },
            onObservation: value => { observation = value; },
            onDelta: (text, output_index) => this.#publishStreamNotice({ type: 'delta', task_id: effect.task_id, ticket: effect.ticket, output_index, text }),
            onSnapshot: (text, output_index) => this.#publishStreamNotice({ type: 'snapshot', task_id: effect.task_id, ticket: effect.ticket, output_index, text }),
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
            if (effect.tool.source.program.kind === 'Process') return this.#runProcess(effect, signal, activity);
            if (effect.tool.source.program.kind === 'ReadImage') {
              if (effect.execution.workspace.environment) {
                return this.executionEnvironments.readImage(this.#sharedOperationId(effect),
                  materializeCallArguments(effect.call), effect.execution, { signal, home: this.home });
              }
              const executionOptions = { signal, execution: effect.execution,
                ...await this.#resourceWorkspace(effect.execution.resource, signal), readOnlyPaths: [this.home], home: this.home };
              return runReadImage(materializeCallArguments(effect.call), executionOptions);
            }
            return this.#processTool(effect);
          }
          if (effect.tool.source.plugin) {
            const client = this.#plugins.get(effect.tool.source.plugin.name);
            // DEFENSE: A frozen tool can outlive its configured plugin process.
            if (!client) throw new Error('Plugin tool route is unavailable');
            return client.call(effect, { signal });
          }
          const { environment, server, name } = effect.tool.source;
          if (environment !== undefined) {
            const { peer } = this.executionEnvironments.get(environment, signal);
            const value = await peer.mcpCall(this.#sharedOperationId(effect), server, name,
              materializeCallArguments(effect.call), { signal, onDiagnostic: message => this.notify({ type: 'diagnostic', message }) });
            return completeSharedMcp(value, this.home, signal);
          }
          const client = this.#servers.get(server);
          // DEFENSE: A frozen tool can name a server removed from configuration.
          if (!client) throw new Error('MCP route is unavailable');
          return client.call(name, materializeCallArguments(effect.call), { signal });
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
          source_length: effect.source_length, now: observation.now });
        // DEFENSE: A provider activity clock can be rejected by native admission or the complete-decision budget.
        if (!activity.reply.ok) throw new Error(`Cache observation rejected: ${activity.reply.error.message}`);
      }
      this.#publishStreamNotice({ type: 'stream_end', task_id: effect.task_id, ticket: effect.ticket, sequence: result.sequence });
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
    return { home: this.home, limits: this.limits, namespace: this.journal.namespace, cloud: this.config.cloud, signal,
      executionEnvironments: this.executionEnvironments,
      onDiagnostic: message => this.notify({ type: 'diagnostic', message }) };
  }

  #settleCompletion(input, failure, handle) {
    return settleEffect(observation => this.#dispatchControl(observation), handle, input,
      value => this.#commitEffectObservation(value), failure,
      error => isDefiniteRejection(error) && error instanceof RangeError ? 'input_limit'
        : transactionOutcome(error) === 'unknown' ? 'uncertain' : 'rejected');
  }

  #commitEffectObservation(input) {
    if (input.kind !== 'context_observed' && input.kind !== 'compaction_measured')
      return this.journal.execute(input);
    // Independent observations from many recovered conversations can arrive
    // together. Only one of them needs a place in the shared journal queue.
    const next = this.#observationTail.then(() => this.journal.execute(input));
    // DEFENSE: One refused observation has its own effect settlement and
    // must not prevent later observations from entering the journal.
    this.#observationTail = next.catch(() => {});
    return next;
  }

  async #settleWorkspaceCompletion(effect, completion, handle) {
    return this.#settleCompletion(completion, () =>
      this.#dispatchControl({ kind: 'workspace_limit', effect, completion }).rollbackWorkspace
        ? rollbackTaskWorkspaceCreation(effect, { ...this.#workspaceOptions(), message: 'Cloud workspace completion exceeds the kernel boundary' })
        : boundary('effect.completion', { effect, result: { ok: false, root: completion.root,
          message: 'Managed worktree completion exceeds the kernel boundary; the checkout has been retained' } }), handle);
  }

  #sharedOperationId(effect) {
    return `${this.journal.namespace}:${naturalKey(effect.task_id)}:${naturalKey(effect.ticket)}`;
  }

  #executionWorkspace(workspace, resource, signal) {
    return workspace.environment
      ? { environment: this.executionEnvironments.get(workspace.environment, signal) }
      : this.#resourceWorkspace(resource, signal);
  }

  async #resourceWorkspace(resource, signal) {
    if (!resource) return {};
    // A child can retain this frozen resource after its owner selects another local workspace.
    // Read ownership by ID rather than re-resolving the owner's current execution binding.
    const { reply } = await this.journal.execute({ kind: 'read_worktree_owner', task_id: resource.task_id });
    // DEFENSE: A frozen effect must retain its exact committed workspace binding.
    if (!reply.ok || reply.result.backend !== resource.backend) {
      throw new Error('The committed task workspace binding is unavailable');
    }
    return this.#readyWorkspace(reply.result, signal);
  }

  async #readyWorkspace(entry, signal) {
    // DEFENSE: A frozen effect or a requested observation can find an archived or unfinished resource.
    if (entry.status !== 'ready') throw new Error('The committed task workspace binding is unavailable');
    if (entry.environment) return { environment: this.executionEnvironments.get(entry.environment, signal) };
    return entry.backend === 'local' ? { managedWorktreeRoot: entry.root }
      : { environment: await taskWorkspaceEnvironment(entry, this.#workspaceOptions(signal)) };
  }

  async #taskWorkspace(taskId, signal) {
    const entry = await this.#worktree(taskId);
    return entry ? this.#readyWorkspace(entry, signal) : {};
  }

  async #observationEnvironment(observation) {
    return Object.hasOwn(observation, 'task_id') ? (await this.#taskWorkspace(observation.task_id)).environment : undefined;
  }

  async #pendingWorktrees() {
    const result = await this.journal.execute({ kind: 'command', command: { op: 'list_worktrees' } });
    // DEFENSE: A persisted collection of managed checkouts can exceed the query reply's frame budget.
    if (!result.reply.ok) throw new Error(`Managed worktree recovery query rejected: ${result.reply.error.message}`);
    return result.reply.result.worktrees.filter(entry => ['creating', 'creating_archived', 'archiving'].includes(entry.status));
  }

  async #reconcileWorktrees(entries) {
    for (const entry of entries) {
      // DEFENSE: A deferred reconciliation can finish one checkout after activated service shutdown begins.
      if (this.#closing || this.#failure) return;
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

  #admitSubmission(command, remote = false) {
    this.#publicCommand(command);
    // DEFENSE: A local request or relay RPC can arrive while an update waits for existing work.
    if (this.draining && !boundary('http.command_read_only', { command, remote })) throw new ServiceDrainingError();
  }

  #trackSubmission(result) {
    if (this.draining) return result;
    this.#submissions.add(result);
    const settled = () => this.#submissions.delete(result);
    void result.then(settled, settled);
    return result;
  }

  async assess(candidate, { signal } = {}) {
    this.#publicCommand(candidate.command);
    // DEFENSE: An HTTP assessment can be cancelled or arrive after the worker stops.
    signal?.throwIfAborted();
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    const command = await this.#observeCommandInput(candidate.command);
    // DEFENSE: Shutdown or a fatal error can occur during filesystem observations.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    return this.journal.assess({ ...candidate, command }, { signal });
  }

  async command(command, browserRequest) {
    this.#admitSubmission(command);
    // DEFENSE: HTTP commands already in flight can reach the service after a fatal operation or shutdown.
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#closing) return Promise.reject(new Error('Service is stopping'));
    return this.#trackSubmission(this.#submitCommand(command, browserRequest));
  }

  /** Remote intent, authorization and receipt share the ordinary native commit. */
  remoteCommand(controller_id, grant_epoch, request) {
    this.#admitSubmission(request?.command, true);
    // DEFENSE: Authenticated remote JSON-RPC commands can omit their params or required command/receipt fields; preserve absence for native rejection.
    const intent = cloneJson(request?.command);
    const envelope = { controller_id, grant_epoch, request_id: request?.request_id, intent };
    return this.#trackSubmission(this.#remoteSubmit(envelope));
  }

  async #remoteSubmit(envelope) {
    // DEFENSE: A queued remote request can outlive service shutdown or a fatal journal failure.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    if (boundary('http.command_read_only', { command: envelope.intent, remote: true })) {
      const result = await this.journal.execute({ kind: 'remote_command', ...envelope,
        command: envelope.intent, configuration: null });
      return { sequence: result.sequence, reply: result.reply };
    }
    const probe = await this.journal.execute({ kind: 'remote_probe', ...envelope });
    // DEFENSE: The remote owner can revoke a grant or a client can send invalid receipt coordinates; do no filesystem work for a rejected intent.
    if (!probe.reply.ok) return { sequence: probe.sequence, reply: probe.reply };
    if (probe.reply.result?.replayed) return { sequence: probe.sequence, reply: probe.reply.result.reply };
    let command;
    let rootFacts;
    try {
      const localGuidance = hasRootTaskCreation(envelope.intent) ? new Map() : undefined;
      command = await observeBoardCommand(admitRawWorkspaceCommand(envelope.intent), this.home);
      command = await observeMessageImages(command, this.home);
      command = await this.#observeCommandWorkspace(command, localGuidance);
      if (localGuidance) rootFacts = await this.#observeCreationFacts(localGuidance);
    // DEFENSE: A remote command can name unreadable files or unavailable workspaces; distinguish observation failure from an already committed command.
    } catch (cause) { throw new CommandNotSubmitted(cause); }
    // DEFENSE: Shutdown or a journal failure can occur during the awaited filesystem observations.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    const result = await this.journal.execute(rootFacts
      ? { kind: 'remote_root_command', ...envelope, command, creation_facts: rootFacts }
      : { kind: 'remote_command', ...envelope, command, configuration: null });
    return { sequence: result.sequence, reply: result.reply };
  }

  remoteCheck(controller_id, grant_epoch, observe) {
    // DEFENSE: A relay authorization check can arrive after local shutdown or a journal failure.
    if (this.#failure) return Promise.reject(this.#failure);
    if (this.#closing) return Promise.reject(new Error('Service is stopping'));
    return this.journal.execute({ kind: 'remote_check', controller_id, grant_epoch }, observe);
  }

  async #observeCommandWorkspace(command, localGuidance) {
    const plan = workspaceCommandPlan(command);
    // DEFENSE: A stale task command needs domain rejection, not an unrelated workspace lookup failure.
    if (!plan.observe) return command;
    // DEFENSE: A direct command or a retained draft can request an unconfigured cloud backend.
    if (plan.worktree && command.backend === 'tencent_cvm' && this.config.cloud?.backend !== command.backend) {
      throw new TypeError('Tencent Cloud CVM is not configured on this Selvedge host');
    }
    // Cloud tasks inherit a fixed workspace. Core admits or rejects their options;
    // local repository observations cannot establish facts about that environment.
    if (command.task_id !== undefined) {
      const task = await this.#workspaceTask(command.task_id);
      if (task.kind === 'cloud' || task.kind === 'unknown') return command;
    }
    const selectedSettings = command.settings;
    const projects = new Map();
    const projectWorkspace = project_id => {
      const key = naturalKey(project_id);
      if (!projects.has(key)) projects.set(key,
        this.journal.execute({ kind: 'command', command: { op: 'read_project', project_id } })
          .then(({ reply }) => reply.ok ? reply.result.workspace : undefined));
      return projects.get(key);
    };
    let observed = await observeWorkspaceCommand(plan, this.limits, {
      workspaceEnvironment: async selection => {
        const result = await this.journal.execute({ kind: 'command', command: { op: 'resolve_workspace', ...selection } });
        // DEFENSE: A selected cloud resource can be ambiguous, unavailable or archived before directory observation.
        if (!result.reply.ok) throw new Error(result.reply.error.message);
        const { resource, workspace_binding } = result.reply.result;
        const selected = selection.workspace;
        return { resource, workspace_binding, ...await this.#executionWorkspace(selected ?? {}, resource) };
      },
      projectWorkspace, localGuidance,
    });
    if (plan.worktree) {
      if (!observed.settings?.workspace) {
        const withWorkspace = { ...observed,
          settings: { ...observed.settings, workspace: { roots: [this.cwd], primary_root: this.cwd } } };
        observed = await observeWorkspaceCommand(workspaceCommandPlan(withWorkspace), this.limits, { localGuidance });
      }
      const primary = observed.settings.workspace.primary_root ?? observed.settings.workspace.roots[0];
      const machine = observed.settings.workspace.environment;
      if (command.backend === 'tencent_cvm') {
        // DEFENSE: Cloud provisioning requires a source repository on the task service host.
        if (machine) throw new TypeError('Cloud task workspaces require a source on the Selvedge host');
        let projectPrimary = primary;
        if (selectedSettings?.project_id !== undefined && selectedSettings.project_id !== null) {
          const workspace = await projectWorkspace(selectedSettings.project_id);
          if (workspace) projectPrimary = workspace.primary_root ?? workspace.roots[0];
        }
        // DEFENSE: Cloud setup requires a committed GitHub source at the project's primary workspace.
        if (!await observeCloudRepository(projectPrimary)) throw new TypeError('Cloud task workspaces require a GitHub remote in the project primary workspace');
      // DEFENSE: A requested local worktree workspace may lack a commit to check out.
      } else if (!await observeWorkspaceGit(primary, { environment: machine ? this.executionEnvironments.get(machine) : undefined })) {
        throw new TypeError('Create worktree requires a Git repository with an initial commit in the primary workspace');
      }
    }
    return observed;
  }

  async #observeCreationFacts(localGuidance) {
    const [project, global] = await Promise.all([
      localGuidance.get(this.cwd) ?? snapshotProject(this.cwd, this.limits),
      snapshotGlobalInstructions(this.home, this.limits),
    ]);
    return { project, global };
  }

  async #observeCommandInput(command, localGuidance) {
    try {
      const imagesObserved = await observeMessageImages(admitRawWorkspaceCommand(command), this.home);
      const boardObserved = await observeBoardCommand(imagesObserved, this.home);
      return await this.#observeCommandWorkspace(boardObserved, localGuidance);
    // DEFENSE: Client-supplied paths or image references can fail their trusted host observation before domain submission.
    } catch (cause) { throw new CommandNotSubmitted(cause); }
  }

  async #submitCommand(command, browserRequest) {
    const localGuidance = hasRootTaskCreation(command) ? new Map() : undefined;
    const observed = await this.#observeCommandInput(command, localGuidance);
    let facts;
    if (localGuidance) {
      try { facts = await this.#observeCreationFacts(localGuidance); }
      // DEFENSE: Unreadable guidance prevents collecting the observations for a new root.
      catch (cause) { throw new CommandNotSubmitted(cause); }
    }
    // DEFENSE: Shutdown or a fatal operation can occur while command filesystem observations are awaited.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    return this.journal.execute(facts
      ? { kind: 'root_command', command: observed, creation_facts: facts }
      : { kind: 'command', command: observed }, undefined, browserRequest);
  }

  refreshAccounts() {
    // DEFENSE: A browser can request a catalog mutation after update drain starts.
    if (this.draining) return Promise.reject(new ServiceDrainingError());
    const next = this.#catalogTail.then(async () => {
      // DEFENSE: A queued account refresh can begin after shutdown or a fatal journal failure.
      if (this.#closing || this.#failure) throw new Error('Service is unavailable');
      const discovered = await withAccountModels(this.declaredConfig, this.home, { force: true });
      // DEFENSE: Account discovery awaits the network and may finish after the service has stopped.
      if (this.#closing || this.#failure) throw new Error('Service is unavailable');
      const previous = this.config;
      this.config = discovered.config;
      try { await this.#publishCatalog({ policy: compactionSettings(this.config), now: Date.now() }); }
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

  audioLogin(options) {
    // DEFENSE: A sign-in HTTP request can already be in flight when service shutdown starts.
    if (this.#closing || this.#failure) throw this.#failure ?? new Error('Service is stopping');
    return this.audio.startLogin(options);
  }

  async audioTranscribe({ connection, audio, mime, language, elapsed_ms, signal }) {
    this.#audioAdmission('transcribe', { body_bytes: audio.byteLength, elapsed_ms, mime });
    return this.audio.transcribe({ connection, audio, mime, language, signal });
  }

  async audioCreate({ browser_id, connection, task_id, sdp }, { signal } = {}) {
    let session;
    const read = this.journal.execute({ kind: 'read_audio_context', task_id }, ({ reply }) => {
      // DEFENSE: Competing requests can read the same Task. Reserve the browser before the next read can finish.
      const session_count = [...this.#audioSessions.values()].filter(session => session.control.owner === browser_id).length;
      const plan = this.#audioAdmission('create', { browser_id, session_count, task_valid: reply.ok });
      const id = randomUUID();
      const generation = randomUUID();
      session = { id, task_id, generation, started: Date.now(), progress: Promise.resolve(),
        maximum: plan.session_max_ms, connectMaximum: plan.connect_timeout_ms,
        control: boundary('control.audio.session_initial', { id, task_id, generation, browser_id, cursor: reply.result.cursor }) };
      this.#audioSessions.set(id, session);
    });
    const { reply: { result: page } } = await this.#trackSubmission(read);
    const { id, generation } = session;
    try {
      const initial_items = boundary('audio.initial_context', { messages: page.messages });
      const result = await this.audio.createSession({ id, generation, connection, task_id, sdp, initial_items, signal });
      // DEFENSE: A page can disappear after receiving the SDP response but before opening its owner event stream.
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
    return null;
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
      if (!event.error) {
        try { await this.refreshAccounts(); }
        // DEFENSE: A completed sign-in can outlive the service or succeed while the model catalog is unavailable.
        catch (error) { this.notify({ type: 'diagnostic', message: error.message }); }
      }
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

  #browserProgram(program) {
    return { ...program, configured_cloud_backend: this.config.cloud?.backend ?? null,
      execution_environments: this.executionEnvironments.choices() };
  }

  #browserPublication(program, sequence, after, outline, historyTasks) {
    let updates = this.journal.programUpdates(after, sequence);
    const publication = { namespace: this.journal.namespace, sequence };
    if (updates === undefined)
      return { ...publication, program: this.#browserProgram(outline ? browserOutline(program) : programWithTaskArray(program)) };
    if (historyTasks !== undefined) updates = updates.map(update => selectUpdateHistory(update, historyTasks));
    if (updates.length) {
      const latest = updates.at(-1);
      updates[updates.length - 1] = { ...latest, shared: this.#browserProgram(latest.shared) };
    }
    return { ...publication, after, updates };
  }

  browserSnapshot(after, outline = false, historyTasks) {
    // DEFENSE: A browser/relay request may reach snapshot delivery after shutdown or a fatal journal failure.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    return this.#browserPublication(this.journal.program, this.journal.sequence, after, outline, historyTasks);
  }

  browserTaskHistory(id, after) {
    // DEFENSE: A browser history request can race service shutdown or a journal failure.
    if (this.#failure) throw this.#failure;
    if (this.#closing) throw new Error('Service is stopping');
    const task = programTask(this.journal.program.tasks, id);
    if (task === undefined) return null;
    // DEFENSE: A requested cursor can exceed the committed history.
    if (after > task.history.length) throw new RangeError('Invalid conversation history cursor');
    return { namespace: this.journal.namespace, task_id: task.id, after,
      history: after === 0 ? task.history : task.history.slice(after), tools: task.tools };
  }

  browserStreams() {
    return structuredClone([...this.#streams.values()]).map(stream => ({ ...stream, namespace: this.journal.namespace }));
  }

  browserToolActivity() {
    const active = [...this.#toolActivity];
    const outputSources = active.filter(activity => activity.readOutput).length;
    // Concurrent Bash previews share the reconnect frame while each start time stays visible.
    const previewLimit = Math.min(TOOL_OUTPUT_PREVIEW_POINTS,
      Math.floor(TOOL_SNAPSHOT_PREVIEW_POINTS / Math.max(1, outputSources)));
    return active.map(activity => this.#toolActivitySnapshot(activity, previewLimit));
  }

  async browserCommand(command, browserRequest, after, outline = false) {
    const result = await this.command(command, browserRequest);
    return { ...this.#browserPublication(result.program, result.sequence, after, outline),
      reply: browserHistoryReply(command, result) };
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
        const environment = plan.environment === undefined ? await this.#observationEnvironment(plan)
          : this.executionEnvironments.get(plan.environment);
        try {
          const available = await observeWorkspaceGit(plan.primary, { environment });
          return boundary('browser.observation', { phase: 'complete', kind: plan.kind, available });
        }
        finally { await environment?.filesystem.close(); }
      },
      cloudRepository: async plan => {
        const available = (await observeCloudRepository(plan.primary)) !== null;
        return boundary('browser.observation', { phase: 'complete', kind: plan.kind, available });
      },
      browseDirectories: async plan => {
        let environment;
        let outcome;
        try {
          environment = plan.environment === undefined
            ? await this.#observationEnvironment(plan) : this.executionEnvironments.get(plan.environment);
          const location = await browseDirectoryLocation(plan, () => boundary('browser.observation', {
            phase: 'resolve', plan, task_environment_present: Boolean(environment),
            task_root: plan.environment === undefined ? environment?.root : '/'
          }), async location => (await canonicalWorkspace({ roots: [location] })).primary_root);
          const result = await browseDirectories(location, this.limits.frame_bytes, { filesystem: environment?.filesystem });
          outcome = result.ok ? { ok: true, value: result } : result;
        // DEFENSE: A browser's selected directory can disappear or deny access while it is being listed; return the browsing error to that form.
        } catch (error) {
          outcome = directoryListingFailure(error);
        } finally { await environment?.filesystem.close(); }
        return boundary('browser.observation', { phase: 'complete', kind: plan.kind, ...outcome });
      },
      directories: async plan => {
        const environment = plan.workspace.environment
          ? this.executionEnvironments.get(plan.workspace.environment) : await this.#observationEnvironment(plan);
        try {
          const workspace = await canonicalWorkspace(plan.workspace, { filesystem: environment?.filesystem });
          const primary = workspace.primary_root ?? workspace.roots[0];
          const guidance = primary ? await snapshotProject(primary, this.limits, { filesystem: environment?.filesystem }) : null;
          return boundary('browser.observation', { phase: 'complete', kind: plan.kind, value: {
            workspace: { ...workspace, ...(plan.workspace.environment ? { environment: plan.workspace.environment } : {}) }, guidance } });
        } finally { await environment?.filesystem.close(); }
      },
      skillCatalog: async plan => {
        let environment;
        let outcome;
        try {
          environment = plan.workspace.environment
            ? this.executionEnvironments.get(plan.workspace.environment) : await this.#observationEnvironment(plan);
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

  get draining() { return this.#drainPromise !== undefined; }

  #pauseTimers() {
    clearImmediate(this.#continuation);
    this.#continuation = undefined;
    clearTimeout(this.#compactionTimer);
    this.#compactionTimer = undefined;
  }

  drain(onProgress, signal) {
    this.#pauseTimers();
    this.#drainPromise ??= Promise.resolve().then(() => this.#drain(onProgress, signal));
    return this.#drainPromise;
  }

  async #drain(onProgress, signal) {
    const interrupted = Promise.withResolvers();
    const abort = () => interrupted.reject(signal.reason);
    const wait = work => signal ? Promise.race([work, interrupted.promise]) : work;
    let previous;
    this.#drainProgress = () => {
      const operations = [...this.#running.values()].map(({ effect }) =>
        effect.kind === 'tool' ? `tool ${effect.tool.name}` : effect.kind).sort();
      const signature = JSON.stringify(operations);
      if (signature !== previous) onProgress(operations);
      previous = signature;
    };
    try {
      signal?.throwIfAborted();
      this.#drainProgress();
      signal?.throwIfAborted();
      signal?.addEventListener('abort', abort, { once: true });
      // Public command callers observe their own admission refusals. A journal or effect failure retires the service separately.
      await wait(Promise.all([this.#catalogTail, this.#activation, Promise.allSettled(this.#submissions)]));
      for (;;) {
        await wait(this.journal.whenIdle());
        if (this.#failure) throw this.#failure;
        // DEFENSE: An OS signal can close the service while a drain is waiting for a callback.
        if (this.#closing) throw new Error('Service stopped before update drain completed');
        const operations = [...this.#running.values()].map(active => active.promise);
        operations.push(...this.#providerCancellations);
        if (this.executionReceiver) operations.push(...this.executionReceiver.pending());
        if (!operations.length) return;
        await wait(Promise.all(operations));
      }
    } catch (error) {
      // DEFENSE: The updater can disconnect while a tool is still running; release admission and restore deferred scheduling.
      if (signal?.aborted && !this.#failure && !this.#closing) {
        this.#drainPromise = undefined;
        if (this.#continuationPending) this.#scheduleContinuation();
        if (this.#compactionClock) this.#scheduleCompactionClock(this.#compactionClock);
      }
      throw error;
    } finally {
      signal?.removeEventListener('abort', abort);
      this.#drainProgress = undefined;
    }
  }

  close() {
    // DEFENSE: Fatal notices, OS signals and failed startup can request shutdown concurrently; all receive the same completion.
    this.#closePromise ??= this.#close();
    return this.#closePromise;
  }

  async #close() {
    this.#closing = true;
    this.#pauseTimers();
    // DEFENSE: Network/process cleanup can fail; finish releasing all resources, then report every failed close to the caller.
    const settled = await Promise.allSettled([this.remote?.close(), this.executionReceiver?.close(),
      ...[...this.#audioSessions.keys()].map(id => this.#stopAudio(id))]);
    settled.push(...await Promise.allSettled([this.audio?.close()]));
    this.#cancelRunning({ kind: 'shutdown' }, new Error('Server stopped'));
    settled.push(...await Promise.allSettled([...this.#running.values()].map(active => active.promise)));
    settled.push(...await Promise.allSettled([this.#activation]));
    this.executionEnvironments?.close();
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
