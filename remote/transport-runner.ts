import { remoteControl } from './control-model.mjs';
import {
  decodeRemoteTransportState, decodeRemoteTransportTransition, decodeRemoteTransportAction,
  decodeRemoteAuthorizationState, decodeRemoteAuthorizationTransition, decodeRemoteAuthorizationAction,
  decodeRemoteConnectorSessionState, decodeRemoteConnectorSessionTransition, decodeRemoteConnectorSessionAction,
  type RemoteTransportState, type RemoteTransportObservation, type RemoteAuthorizationState, type DomainNatural,
  type RemoteConnectorSessionState, type RemoteConnectorSessionObservation, type RemoteConnectorSessionAction, type JsonValue,
} from '../host/generated/model-schema.ts';

export interface TransportSettings {
  retry_base: number; retry_max: number; heartbeat: number; heartbeat_timeout: number;
}
export interface TransportIO {
  install(state: RemoteTransportState): void;
  connect(generation: number): void;
  open(generation: number): void;
  retry(generation: number, deadline: number): void;
  heartbeat(generation: number, deadline: number): void;
  online(generation: number): void;
  ping(generation: number): void;
  retire(): void;
  stopped(): void;
  authenticationFailed(): void;
}
export const initialTransport = (): RemoteTransportState => decodeRemoteTransportState(remoteControl('transport_initial', {}));
export const transportRunning = (state: RemoteTransportState): boolean => remoteControl('transport_running', { state });
export const transportCurrent = (state: RemoteTransportState, generation: number): boolean => remoteControl('transport_current', { state, generation });

/** Install every transition before invoking primitives that can synchronously
 * deliver a socket callback. Timers report observations; they never choose policy. */
export function observeTransport(state: RemoteTransportState, observation: RemoteTransportObservation,
  settings: TransportSettings, io: TransportIO): void {
  const result = decodeRemoteTransportTransition(remoteControl('transport', { state, observation, settings }));
  io.install(decodeRemoteTransportState(result.state));
  for (const raw of result.actions) {
    const action = decodeRemoteTransportAction(raw);
    switch (action.kind) {
      case 'connect': io.connect(action.generation); continue;
      case 'open': io.open(action.generation); continue;
      case 'retry': io.retry(action.generation, action.deadline); continue;
      case 'heartbeat': io.heartbeat(action.generation, action.deadline); continue;
      case 'online': io.online(action.generation); continue;
      case 'ping': io.ping(action.generation); continue;
      case 'retire': io.retire(); continue;
      case 'stopped': io.stopped(); continue;
      case 'auth_failed': io.authenticationFailed(); continue;
    }
    const exhaustive: never = action;
    throw new TypeError(`Unknown remote transport action: ${String(exhaustive)}`);
  }
}
export const initialAuthorization = (): RemoteAuthorizationState => decodeRemoteAuthorizationState(remoteControl('authorization_initial', {}));
export function observeAuthorization(state: RemoteAuthorizationState, active: boolean, allowed: boolean,
  checked: DomainNatural, current: DomainNatural): {state: RemoteAuthorizationState; action: 'check' | 'capture' | 'deny' | 'disconnect'} {
  const result = decodeRemoteAuthorizationTransition(remoteControl('authorization', { state, active, allowed, checked, current }));
  const next = decodeRemoteAuthorizationState(result.state);
  const action = decodeRemoteAuthorizationAction(result.action);
  switch (action.kind) {
    case 'check': case 'capture': case 'deny': case 'disconnect': return { state: next, action: action.kind };
  }
  const exhaustive: never = action;
  throw new TypeError(`Unknown remote authorization action: ${String(exhaustive)}`);
}

type SessionAction = RemoteConnectorSessionAction;
export const initialConnectorSession = (): RemoteConnectorSessionState => decodeRemoteConnectorSessionState(remoteControl('connector_initial', {}));
export function observeConnectorSession(state: RemoteConnectorSessionState, event: RemoteConnectorSessionObservation):
  {state: RemoteConnectorSessionState; action: SessionAction} {
  const result = decodeRemoteConnectorSessionTransition(remoteControl('connector', { state, event }));
  return { state: decodeRemoteConnectorSessionState(result.state), action: decodeRemoteConnectorSessionAction(result.action) };
}
export interface ConnectorFrameIO {
  disconnect(): void; ready(): void;
  opened(value: Extract<SessionAction, {kind: 'controller_open'}>): void;
  closed(connectionId: string): void;
  request(value: Extract<SessionAction, {kind: 'request'}>): void;
  pairRequest(value: JsonValue): void; pong(): void;
}
/** A relay-frame observation is interpreted once, after its session state is installed. */
export function interpretConnectorFrame(action: SessionAction, io: ConnectorFrameIO): void {
  switch (action.kind) {
    case 'ignore': return;
    case 'disconnect': io.disconnect(); return;
    case 'ready': io.ready(); return;
    case 'controller_open': io.opened(action); return;
    case 'controller_close': io.closed(action.connection_id); return;
    case 'request': io.request(action); return;
    case 'pair_request': io.pairRequest(action.request); return;
    case 'pong': io.pong(); return;
    // DEFENSE: The session ABI only emits frame actions for a relay-frame observation.
    case 'installed': case 'retire': case 'pairing': case 'pending': case 'expired':
    case 'grants': case 'enqueue': case 'dequeue': case 'notice': case 'snapshot':
    case 'unsubscribed': case 'deliver': throw new TypeError('Unexpected connector frame action');
  }
  const exhaustive: never = action;
  throw new TypeError(`Unknown connector action: ${String(exhaustive)}`);
}
export function interpretConnectorCapture(action: SessionAction, io: {snapshot(): void; unsubscribed(): void}): void {
  switch (action.kind) {
    case 'ignore': return;
    case 'snapshot': io.snapshot(); return;
    case 'unsubscribed': io.unsubscribed(); return;
    // DEFENSE: A capture observation cannot authorize a transport or notice action.
    case 'installed': case 'retire': case 'pairing': case 'pending': case 'expired': case 'grants':
    case 'enqueue': case 'dequeue': case 'disconnect': case 'ready': case 'controller_open':
    case 'controller_close': case 'request': case 'pair_request': case 'pong': case 'notice':
    case 'deliver': throw new TypeError('Unexpected connector capture action');
  }
  const exhaustive: never = action;
  throw new TypeError(`Unknown connector action: ${String(exhaustive)}`);
}
export function interpretConnectorDelivery(action: SessionAction, deliver: () => void): void {
  switch (action.kind) {
    case 'ignore': return;
    case 'deliver': deliver(); return;
    // DEFENSE: Only the model's queued, fresh cursor decision authorizes delivery.
    case 'installed': case 'retire': case 'pairing': case 'pending': case 'expired': case 'grants':
    case 'enqueue': case 'dequeue': case 'disconnect': case 'ready': case 'controller_open':
    case 'controller_close': case 'request': case 'pair_request': case 'pong': case 'notice':
    case 'snapshot': case 'unsubscribed': throw new TypeError('Unexpected connector delivery action');
  }
  const exhaustive: never = action;
  throw new TypeError(`Unknown connector action: ${String(exhaustive)}`);
}
export interface RemoteOperationQueue {
  active: boolean;
  tail: Promise<void>;
}
export interface RemoteQueueIO {
  current(): boolean;
  observe(action: 'enqueue' | 'dequeue', bytes: number): SessionAction;
  disconnect(reason: string): void;
}
export function enqueueRemoteOperation(connection: RemoteOperationQueue, bytes: number,
  operation: () => Promise<void>, io: RemoteQueueIO): void {
  // DEFENSE: A controller can close while an earlier request or notice is still queued.
  if (!connection.active || !io.current()) return;
  const action = io.observe('enqueue', bytes);
  switch (action.kind) {
    case 'ignore': return;
    case 'disconnect': io.disconnect('request_queue_full'); return;
    case 'enqueue': break;
    // DEFENSE: The queue ABI must acknowledge admission before a physical operation is chained.
    case 'installed': case 'retire': case 'pairing': case 'pending': case 'expired': case 'grants':
    case 'dequeue': case 'ready': case 'controller_open': case 'controller_close': case 'request':
    case 'pair_request': case 'pong': case 'notice': case 'snapshot': case 'unsubscribed':
    case 'deliver': throw new TypeError('Unexpected connector queue action');
    default: { const exhaustive: never = action; throw new TypeError(String(exhaustive)); }
  }
  connection.tail = connection.tail.then(async () => {
    if (connection.active && io.current()) await operation();
  // DEFENSE: A queued native command can fail after its kernel or journal stops; retire transport without replaying it.
  }).catch(() => { io.disconnect('request_processing_failed'); }).finally(() => { io.observe('dequeue', bytes); });
}
export interface RemoteAuthorizationIO {
  check(): Promise<{reply: {ok: boolean}; sequence: DomainNatural}>;
  active(): boolean;
  currentSequence(): DomainNatural;
  capture(): void;
  deny(): void;
  disconnect(): void;
}
export async function authorizeRemoteCapture(io: RemoteAuthorizationIO): Promise<boolean> {
  let state = initialAuthorization();
  while (true) {
    const check = await io.check();
    const result = observeAuthorization(state, io.active(), check.reply.ok, check.sequence, io.currentSequence());
    state = result.state;
    switch (result.action) {
      case 'check': continue;
      case 'capture': io.capture(); return true;
      case 'deny': io.deny(); return false;
      case 'disconnect': io.disconnect(); return false;
    }
    const exhaustive: never = result.action;
    throw new TypeError(String(exhaustive));
  }
}
