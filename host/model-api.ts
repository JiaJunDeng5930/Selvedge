import {
  decodeAudioAdmission, decodeHttpPlan, decodeHttpRemoteApprovalBody, decodeHttpRemoteRevokeBody,
  decodeHttpRemotePermissions, decodeHttpBrowserCommandBody, decodeHttpReplyStatus, decodeBrowserObservationPlan, decodeBrowserPath,
  decodeDispatchTransition, decodeDispatchAction, decodeAudioTransition, decodeAudioAction,
  decodeWorkspaceCommandPlan, decodeWorkspaceSelectionPlan, decodeWorkspaceSettingsPlan,
  type AudioAdmission, type JsonValue, type BrowserObservationPlan, type DomainNatural, type HttpRemotePermissions,
} from './generated/model-schema.ts';

export type AllowedAudio = Extract<AudioAdmission, { allowed: true }>;

/** The checked consumer keeps the rejection field tied to its Gallina declaration. */
export function requireAudioAdmission(input: unknown, rejection: 'type' | 'range' = 'type'): AllowedAudio {
  const plan = decodeAudioAdmission(input);
  switch (plan.allowed) {
    case true: return plan;
    // DEFENSE: Authenticated clients can exceed the audio resource contract or name another browser's session.
    case false:
      if (rejection === 'range') throw new RangeError(plan.message);
      throw new TypeError(plan.message);
  }
  const unreachable: never = plan;
  return unreachable;
}

export interface HttpPrimitives {
  respond(status: number, value: JsonValue): void;
  observe_content_type(target: string): unknown;
  readBody(target: string, maximum: number): Promise<unknown>;
  observe_host(): unknown;
  parse_url(): unknown;
  observe_connection_authorization(): unknown;
  connection_method_origin(): unknown;
  observe_local_authorization(): unknown;
  local_origin(): unknown;
  asset(): Promise<void> | void;
  audio_capabilities(): Promise<void> | void;
  audio_transcribe(): Promise<void> | void;
  audio_events(): Promise<void> | void;
  audio_stop(): Promise<void> | void;
  attachment_upload(): Promise<void> | void;
  attachment_download(): Promise<void> | void;
  browser_state(): Promise<void> | void;
  describe(): Promise<void> | void;
  remote_status(): Promise<void> | void;
  remote_pending(): Promise<void> | void;
  events(): Promise<void> | void;
  event_page(): Promise<void> | void;
  health(): Promise<void> | void;
  account_refresh(body: JsonValue): Promise<void> | void;
  audio_create(body: JsonValue): Promise<void> | void;
  audio_login(body: JsonValue): Promise<void> | void;
  remote_pair(body: JsonValue): Promise<void> | void;
  remote_enable(body: JsonValue): Promise<void> | void;
  remote_disable(body: JsonValue): Promise<void> | void;
  browser_observation(body: JsonValue): Promise<void> | void;
  command(body: JsonValue): Promise<void> | void;
  assess(body: JsonValue): Promise<void> | void;
  connection_command(body: JsonValue): Promise<void> | void;
  remote_approve(requestId: string, permissions: HttpRemotePermissions): Promise<void>;
  remote_revoke(controllerId: string): Promise<void>;
  browser_command(command: JsonValue): Promise<void>;
}
/** The only HTTP plan consumer selects physical primitives after generated decoding. */
export async function interpretHttpPlan(input: unknown, bodyObserved: boolean, frameBytes: number, io: HttpPrimitives): Promise<unknown | null> {
  const plan = decodeHttpPlan(input);
  switch (plan.action) {
    case 'respond': io.respond(plan.status, plan.value); return null;
    case 'throw':
      switch (plan.kind) {
        case 'TypeError': throw new TypeError(plan.message);
        case 'RangeError': throw new RangeError(plan.message);
      }
      break;
    case 'observe_content_type': return io.observe_content_type(plan.target);
    case 'observe_host': return io.observe_host();
    case 'parse_url': return io.parse_url();
    case 'observe_connection_authorization': return io.observe_connection_authorization();
    case 'connection_method_origin': return io.connection_method_origin();
    case 'observe_local_authorization': return io.observe_local_authorization();
    case 'local_origin': return io.local_origin();
    case 'asset': await io.asset(); return null;
    case 'audio_capabilities': await io.audio_capabilities(); return null;
    case 'audio_transcribe': await io.audio_transcribe(); return null;
    case 'audio_events': await io.audio_events(); return null;
    case 'audio_stop': await io.audio_stop(); return null;
    case 'attachment_upload': await io.attachment_upload(); return null;
    case 'attachment_download': await io.attachment_download(); return null;
    case 'browser_state': await io.browser_state(); return null;
    case 'describe': await io.describe(); return null;
    case 'remote_status': await io.remote_status(); return null;
    case 'remote_pending': await io.remote_pending(); return null;
    case 'events': await io.events(); return null;
    case 'event_page': await io.event_page(); return null;
    case 'health': await io.health(); return null;
    case 'account_refresh':
    case 'audio_create':
    case 'audio_login':
    case 'remote_pair':
    case 'remote_enable':
    case 'remote_disable':
    case 'remote_approve':
    case 'remote_revoke':
    case 'browser_command':
    case 'browser_observation':
    case 'command':
    case 'assess':
    case 'connection_command':
      if (!bodyObserved) {
        const maximum = plan.action === 'account_refresh' || plan.action === 'audio_login' ? 1024
          : plan.action === 'remote_pair' || plan.action === 'remote_enable' || plan.action === 'remote_disable'
            || plan.action === 'remote_approve' || plan.action === 'remote_revoke' ? 8192 : frameBytes;
        return io.readBody(plan.action, maximum);
      }
      // DEFENSE: The HTTP body stage must attach its admitted JSON value before an execution primitive can run.
      if (plan.body === undefined) throw new TypeError('HTTP body plan has no body');
      switch (plan.action) {
        case 'account_refresh': { await io.account_refresh(plan.body); return null; }
        case 'audio_create': { await io.audio_create(plan.body); return null; }
        case 'audio_login': { await io.audio_login(plan.body); return null; }
        case 'remote_pair': { await io.remote_pair(plan.body); return null; }
        case 'remote_enable': { await io.remote_enable(plan.body); return null; }
        case 'remote_disable': { await io.remote_disable(plan.body); return null; }
        case 'remote_approve': { const body = decodeHttpRemoteApprovalBody(plan.body); await io.remote_approve(body.request_id, decodeHttpRemotePermissions(body.permissions)); return null; }
        case 'remote_revoke': { const body = decodeHttpRemoteRevokeBody(plan.body); await io.remote_revoke(body.controller_id); return null; }
        case 'browser_command': { const body = decodeHttpBrowserCommandBody(plan.body); await io.browser_command(body.command); return null; }
        case 'browser_observation': { await io.browser_observation(plan.body); return null; }
        case 'command': { await io.command(plan.body); return null; }
        case 'assess': { await io.assess(plan.body); return null; }
        case 'connection_command': { await io.connection_command(plan.body); return null; }
      }
  }
  const unreachable: never = plan;
  return unreachable;
}
export function httpReplyStatus(input: unknown): number { return decodeHttpReplyStatus(input); }

export interface BrowserObservationPrimitives {
  streams(): unknown;
  workspaceGit(plan: Extract<BrowserObservationPlan, {kind: 'workspace-git'}>): Promise<unknown>;
  browseDirectories(plan: Extract<BrowserObservationPlan, {kind: 'browse-directories'}>): Promise<unknown>;
  directories(plan: Extract<BrowserObservationPlan, {kind: 'directories'}>): Promise<unknown>;
  skillCatalog(plan: Extract<BrowserObservationPlan, {kind: 'skill-catalog'}>): Promise<unknown>;
}
export async function interpretBrowserObservation(input: unknown, io: BrowserObservationPrimitives): Promise<unknown> {
  const plan = decodeBrowserObservationPlan(input);
  switch (plan.kind) {
    case 'streams': return io.streams();
    case 'workspace-git': return io.workspaceGit(plan);
    case 'browse-directories': return io.browseDirectories(plan);
    case 'directories': return io.directories(plan);
    case 'skill-catalog': return io.skillCatalog(plan);
  }
  const unreachable: never = plan;
  return unreachable;
}
export function resolveBrowserPath(input: unknown, canonicalize: (value: JsonValue) => Promise<JsonValue>): Promise<JsonValue> {
  const plan = decodeBrowserPath(input);
  return plan.canonicalize ? canonicalize(plan.path) : Promise.resolve(plan.path);
}
export interface DispatchControlPrimitives {
  state(state: JsonValue): void;
  start(generation: DomainNatural): void;
  cancel(generation: DomainNatural, provider: boolean): void;
  retryFailure(): void;
  settled(): void;
  retire(): void;
}
export function interpretDispatchControl(input: unknown, io: DispatchControlPrimitives): void {
  const transition = decodeDispatchTransition(input);
  io.state(transition.state);
  for (const raw of transition.effects) {
    const action = decodeDispatchAction(raw);
    switch (action.kind) {
      case 'start': io.start(action.generation); break;
      case 'cancel': io.cancel(action.generation, action.provider); break;
      case 'retry_failure': io.retryFailure(); break;
      case 'settled': io.settled(); break;
      case 'retire': io.retire(); break;
      default: { const unreachable: never = action; return unreachable; }
    }
  }
}
export interface AudioControlPrimitives {
  state(state: JsonValue): void;
  emit(event: JsonValue): void;
  journal(token: JsonValue, command: JsonValue): Promise<void>;
  context(context: JsonValue): Promise<void>;
  read(after: DomainNatural): void;
  stop(): Promise<void>;
  release(): void;
  timer(): void;
  connectTimer(): void;
}
export async function interpretAudioControl(input: unknown, io: AudioControlPrimitives): Promise<void> {
  const transition = decodeAudioTransition(input);
  io.state(transition.state);
  for (const raw of transition.actions) {
    const action = decodeAudioAction(raw);
    switch (action.type) {
      case 'emit': io.emit(action.event); break;
      case 'journal': await io.journal(action.token, action.command); break;
      case 'context': await io.context(action.context); break;
      case 'read': io.read(action.after); break;
      case 'stop': await io.stop(); break;
      case 'release': io.release(); break;
      case 'timer': io.timer(); break;
      case 'connect_timer': io.connectTimer(); break;
      // DEFENSE: A browser can address a session owned by another browser or an already retired generation.
      case 'reject': throw new Error(action.message);
      default: { const unreachable: never = action; return unreachable; }
    }
  }
}

export function dispatchControlResult(input: unknown) {
  const starts: DomainNatural[] = [], cancellations: Array<{generation: DomainNatural; provider: boolean}> = [];
  let state: JsonValue = null, settled = false, retryFailure = false, retire = false;
  interpretDispatchControl(input, {
    state: value => { state = value; }, start: generation => { starts.push(generation); },
    cancel: (generation, provider) => { cancellations.push({ generation, provider }); },
    settled: () => { settled = true; }, retryFailure: () => { retryFailure = true; }, retire: () => { retire = true; },
  });
  return { state, starts, cancellations, settled, retryFailure, retire };
}
export function browseDirectoryLocation(plan: Extract<BrowserObservationPlan, {kind: 'browse-directories'}>,
  resolve: () => unknown, canonicalize: (value: JsonValue) => Promise<JsonValue>): Promise<JsonValue> {
  return plan.default_path ? resolveBrowserPath(resolve(), canonicalize) : Promise.resolve(plan.path);
}

export function workspaceCommandResult(input: unknown) {
  const plan = decodeWorkspaceCommandPlan(input);
  const selections = plan.selections.map(decodeWorkspaceSelectionPlan);
  return { rootTask: plan.root_task, worktree: plan.worktree, observe: selections.length > 0 || plan.worktree, selections };
}
export async function interpretWorkspaceSettings(input: unknown, io: {
  project(projectId: DomainNatural): Promise<boolean>;
  observe(projectId: DomainNatural | null): Promise<unknown>;
}): Promise<unknown> {
  const plan = decodeWorkspaceSettingsPlan(input);
  // Schema.KOptional interprets an omitted field as None, represented here by canonical null.
  const projectId = plan.project_id ?? null;
  if (projectId !== null) {
    if (!await io.project(projectId)) return {};
  } else if (!plan.observe_workspace) return {};
  return io.observe(projectId);
}
