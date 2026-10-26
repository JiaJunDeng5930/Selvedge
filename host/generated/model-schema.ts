// Generated from the executable Kernel model declarations. Do not edit.
import { JsonNumber, naturalKey, safeInteger } from '../public/json-tokens.mjs';
export type DomainNatural = number | JsonNumber;
export type DomainInteger = number | JsonNumber;
export type JsonValue = null | boolean | string | number | JsonNumber | JsonValue[] | {[key: string]: JsonValue};
function isObject(value: unknown): value is Record<string, unknown> { return typeof value === 'object' && value !== null && !Array.isArray(value) && !(value instanceof JsonNumber); }
function decodeObject(value: unknown): Record<string, unknown> {
  // DEFENSE: A boundary payload may be a scalar or array rather than its declared record.
  if (!isObject(value)) throw new TypeError('Expected model object'); return value;
}
function isArray(value: unknown): value is unknown[] { return Array.isArray(value); }
function decodeArray<T>(value: unknown, decode: (item: unknown) => T): T[] {
  // DEFENSE: A wire array field can contain a scalar.
  if (!isArray(value)) throw new TypeError('Expected model array'); return value.map(decode);
}
function exactFields(value: Record<string, unknown>, names: readonly string[]): void {
  // DEFENSE: Unknown wire fields cannot silently acquire meaning at a later consumer.
  if (Object.keys(value).some(name => !names.includes(name))) throw new TypeError('Unknown model field');
}
function decodeText(value: unknown): string {
  // DEFENSE: A declared model text field may contain another JSON type.
  if (typeof value !== 'string') throw new TypeError('Expected model text'); return value;
}
function decodeBoolean(value: unknown): boolean {
  // DEFENSE: A declared model Boolean field may contain another JSON type.
  if (typeof value !== 'boolean') throw new TypeError('Expected model Boolean'); return value;
}
function decodeNatural(value: unknown): DomainNatural {
  // DEFENSE: The exact-number ABI admits canonical natural tokens without converting them to rounded numbers.
  if (typeof value !== 'number' && !(value instanceof JsonNumber)) throw new TypeError('Expected model natural'); naturalKey(value); return value;
}
function decodeInteger(value: unknown): DomainInteger {
  // DEFENSE: Core integers retain their strict decimal lexical contract.
  if (value instanceof JsonNumber && /^-?(0|[1-9]\d*)$/.test(value.source)) return value;
  if (typeof value === 'number' && Number.isSafeInteger(value)) return value; throw new TypeError('Expected model integer');
}
function decodeSafeNatural(value: unknown): number { const number = safeInteger(value);
  // DEFENSE: Transport durations and limits must fit the physical runtime's nonnegative safe integer range.
  if (number === undefined || number < 0) throw new TypeError('Expected bounded model natural'); return number;
}
function decodeDecimal(value: unknown): JsonNumber | number {
  // DEFENSE: External JSON decimal tokens must have JSON number syntax; numerical observations must be finite.
  if (value instanceof JsonNumber && /^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$/.test(value.source)) return value;
  if (typeof value === 'number' && Number.isFinite(value)) return value; throw new TypeError('Expected model decimal');
}
export function decodeJson(value: unknown): JsonValue {
  if (value === null || typeof value === 'boolean' || typeof value === 'string') return value;
  if (typeof value === 'number' || value instanceof JsonNumber) return decodeDecimal(value);
  if (isArray(value)) return value.map(decodeJson);
  const object = decodeObject(value); return Object.fromEntries(Object.entries(object).map(([key,item]) => [key,decodeJson(item)]));
}
function decodeEnum0(value: unknown): "snapshot" | "subscribe" | "unsubscribe" {
 switch (value) { case "snapshot": return "snapshot"; case "subscribe": return "subscribe"; case "unsubscribe": return "unsubscribe";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum1(value: unknown): "TypeError" | "RangeError" {
 switch (value) { case "TypeError": return "TypeError"; case "RangeError": return "RangeError";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum2(value: unknown): "account_refresh" | "audio_create" | "audio_login" | "remote_pair" | "remote_enable" | "remote_disable" | "remote_approve" | "remote_revoke" | "browser_command" | "browser_observation" | "command" | "assess" | "connection_command" {
 switch (value) { case "account_refresh": return "account_refresh"; case "audio_create": return "audio_create"; case "audio_login": return "audio_login"; case "remote_pair": return "remote_pair"; case "remote_enable": return "remote_enable"; case "remote_disable": return "remote_disable"; case "remote_approve": return "remote_approve"; case "remote_revoke": return "remote_revoke"; case "browser_command": return "browser_command"; case "browser_observation": return "browser_observation"; case "command": return "command"; case "assess": return "assess"; case "connection_command": return "connection_command";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum3(value: unknown): "ignore" | "installed" | "retire" | "pairing" | "pending" | "expired" | "grants" | "enqueue" | "dequeue" | "disconnect" | "ready" | "controller_open" | "controller_close" | "request" | "pair_request" | "pong" | "notice" | "snapshot" | "unsubscribed" | "deliver" {
 switch (value) { case "ignore": return "ignore"; case "installed": return "installed"; case "retire": return "retire"; case "pairing": return "pairing"; case "pending": return "pending"; case "expired": return "expired"; case "grants": return "grants"; case "enqueue": return "enqueue"; case "dequeue": return "dequeue"; case "disconnect": return "disconnect"; case "ready": return "ready"; case "controller_open": return "controller_open"; case "controller_close": return "controller_close"; case "request": return "request"; case "pair_request": return "pair_request"; case "pong": return "pong"; case "notice": return "notice"; case "snapshot": return "snapshot"; case "unsubscribed": return "unsubscribed"; case "deliver": return "deliver";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum4(value: unknown): "persist" | "allocate" | "prepare" | "credentials" | "scan" | "terminate" | "finish" | "local_reserve" | "local_create" | "local_prepare" | "local_classify" | "local_release" | "local_remove" | "local_archive" | "local_observe" | "local_sync_registration" | "local_sync_ready" | "local_sync_archive" | "local_sync_release" {
 switch (value) { case "persist": return "persist"; case "allocate": return "allocate"; case "prepare": return "prepare"; case "credentials": return "credentials"; case "scan": return "scan"; case "terminate": return "terminate"; case "finish": return "finish"; case "local_reserve": return "local_reserve"; case "local_create": return "local_create"; case "local_prepare": return "local_prepare"; case "local_classify": return "local_classify"; case "local_release": return "local_release"; case "local_remove": return "local_remove"; case "local_archive": return "local_archive"; case "local_observe": return "local_observe"; case "local_sync_registration": return "local_sync_registration"; case "local_sync_ready": return "local_sync_ready"; case "local_sync_archive": return "local_sync_archive"; case "local_sync_release": return "local_sync_release";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum5(value: unknown): "plain" | "interactive-v1" {
 switch (value) { case "plain": return "plain"; case "interactive-v1": return "interactive-v1";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum6(value: unknown): "local" | "tencent_cvm" {
 switch (value) { case "local": return "local"; case "tencent_cvm": return "tencent_cvm";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum7(value: unknown): "parent" | "environment" {
 switch (value) { case "parent": return "parent"; case "environment": return "environment";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum8(value: unknown): "allow" | "deny" {
 switch (value) { case "allow": return "allow"; case "deny": return "deny";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum9(value: unknown): "user" | "assistant" {
 switch (value) { case "user": return "user"; case "assistant": return "assistant";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum10(value: unknown): "completed" | "interrupted" {
 switch (value) { case "completed": return "completed"; case "interrupted": return "interrupted";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum11(value: unknown): "send" | "steer" {
 switch (value) { case "send": return "send"; case "steer": return "steer";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}
export function decodeHttpReplyStatus(input: unknown): number { return decodeSafeNatural(input); }
export type RemoteConnectorSessionState =
  | {"phase": "offline"; "generation": number; "pairing": JsonValue; "notice_sequence": number}
  | {"phase": "negotiating"; "generation": number; "pairing": JsonValue; "notice_sequence": number}
  | {"phase": "ready"; "generation": number; "pairing": JsonValue; "notice_sequence": number; "grants": Array<JsonValue>; "connections": Array<JsonValue>; "pending": Array<JsonValue>};
export function decodeRemoteConnectorSessionState(input: unknown): RemoteConnectorSessionState {
  const source = decodeObject(input);
  switch (source["phase"]) {
    case "offline": exactFields(source, ["phase","generation","pairing","notice_sequence"]); return {"phase": "offline", "generation": decodeSafeNatural(source["generation"]), "pairing": decodeJson(source["pairing"]), "notice_sequence": decodeSafeNatural(source["notice_sequence"])};
    case "negotiating": exactFields(source, ["phase","generation","pairing","notice_sequence"]); return {"phase": "negotiating", "generation": decodeSafeNatural(source["generation"]), "pairing": decodeJson(source["pairing"]), "notice_sequence": decodeSafeNatural(source["notice_sequence"])};
    case "ready": exactFields(source, ["phase","generation","pairing","notice_sequence","grants","connections","pending"]); return {"phase": "ready", "generation": decodeSafeNatural(source["generation"]), "pairing": decodeJson(source["pairing"]), "notice_sequence": decodeSafeNatural(source["notice_sequence"]), "grants": decodeArray(source["grants"], item => decodeJson(item)), "connections": decodeArray(source["connections"], item => decodeJson(item)), "pending": decodeArray(source["pending"], item => decodeJson(item))};
    // DEFENSE: External boundary values must name a declared RemoteConnectorSessionState variant.
    default: throw new TypeError('Unknown RemoteConnectorSessionState discriminant');
  }
}

export type RemoteConnectorSessionObservation =
  | {"kind": "install"; "generation": number}
  | {"kind": "retire"; "generation": number}
  | {"kind": "pair"; "generation": number; "now": number; "frame": JsonValue}
  | {"kind": "pairing_current"; "generation": number; "now": number}
  | {"kind": "grants"; "generation": number; "grants": Array<JsonValue>}
  | {"kind": "enqueue"; "generation": number; "connection_id": string; "bytes": number; "notice_sequence": JsonValue}
  | {"kind": "dequeue"; "generation": number; "connection_id": string; "bytes": number; "notice_sequence": JsonValue}
  | {"kind": "notice"; }
  | {"kind": "capture"; "generation": number; "connection_id": string; "method": "snapshot" | "subscribe" | "unsubscribe"}
  | {"kind": "deliver"; "generation": number; "connection_id": string; "notice_sequence": number}
  | {"kind": "frame"; "generation": number; "frame": JsonValue};
export function decodeRemoteConnectorSessionObservation(input: unknown): RemoteConnectorSessionObservation {
  const source = decodeObject(input);
  switch (source["kind"]) {
    case "install": exactFields(source, ["kind","generation"]); return {"kind": "install", "generation": decodeSafeNatural(source["generation"])};
    case "retire": exactFields(source, ["kind","generation"]); return {"kind": "retire", "generation": decodeSafeNatural(source["generation"])};
    case "pair": exactFields(source, ["kind","generation","now","frame"]); return {"kind": "pair", "generation": decodeSafeNatural(source["generation"]), "now": decodeSafeNatural(source["now"]), "frame": decodeJson(source["frame"])};
    case "pairing_current": exactFields(source, ["kind","generation","now"]); return {"kind": "pairing_current", "generation": decodeSafeNatural(source["generation"]), "now": decodeSafeNatural(source["now"])};
    case "grants": exactFields(source, ["kind","generation","grants"]); return {"kind": "grants", "generation": decodeSafeNatural(source["generation"]), "grants": decodeArray(source["grants"], item => decodeJson(item))};
    case "enqueue": exactFields(source, ["kind","generation","connection_id","bytes","notice_sequence"]); return {"kind": "enqueue", "generation": decodeSafeNatural(source["generation"]), "connection_id": decodeText(source["connection_id"]), "bytes": decodeSafeNatural(source["bytes"]), "notice_sequence": decodeJson(source["notice_sequence"])};
    case "dequeue": exactFields(source, ["kind","generation","connection_id","bytes","notice_sequence"]); return {"kind": "dequeue", "generation": decodeSafeNatural(source["generation"]), "connection_id": decodeText(source["connection_id"]), "bytes": decodeSafeNatural(source["bytes"]), "notice_sequence": decodeJson(source["notice_sequence"])};
    case "notice": exactFields(source, ["kind"]); return {"kind": "notice"};
    case "capture": exactFields(source, ["kind","generation","connection_id","method"]); return {"kind": "capture", "generation": decodeSafeNatural(source["generation"]), "connection_id": decodeText(source["connection_id"]), "method": decodeEnum0(source["method"])};
    case "deliver": exactFields(source, ["kind","generation","connection_id","notice_sequence"]); return {"kind": "deliver", "generation": decodeSafeNatural(source["generation"]), "connection_id": decodeText(source["connection_id"]), "notice_sequence": decodeSafeNatural(source["notice_sequence"])};
    case "frame": exactFields(source, ["kind","generation","frame"]); return {"kind": "frame", "generation": decodeSafeNatural(source["generation"]), "frame": decodeJson(source["frame"])};
    // DEFENSE: External boundary values must name a declared RemoteConnectorSessionObservation variant.
    default: throw new TypeError('Unknown RemoteConnectorSessionObservation discriminant');
  }
}

export type CloudReadinessAction =
  | {"kind": "probe"; "timeout": DomainNatural}
  | {"kind": "delay"; "milliseconds": DomainNatural}
  | {"kind": "connected"; }
  | {"kind": "reject"; "message": string};
export function decodeCloudReadinessAction(input: unknown): CloudReadinessAction {
  const source = decodeObject(input);
  switch (source["kind"]) {
    case "probe": exactFields(source, ["kind","timeout"]); return {"kind": "probe", "timeout": decodeNatural(source["timeout"])};
    case "delay": exactFields(source, ["kind","milliseconds"]); return {"kind": "delay", "milliseconds": decodeNatural(source["milliseconds"])};
    case "connected": exactFields(source, ["kind"]); return {"kind": "connected"};
    case "reject": exactFields(source, ["kind","message"]); return {"kind": "reject", "message": decodeText(source["message"])};
    // DEFENSE: External boundary values must name a declared CloudReadinessAction variant.
    default: throw new TypeError('Unknown CloudReadinessAction discriminant');
  }
}

export type RemoteTransportState =
  | {"phase": "stopped"; "generation": number}
  | {"phase": "connecting"; "generation": number; "attempt": number}
  | {"phase": "negotiating"; "generation": number; "attempt": number}
  | {"phase": "online"; "generation": number; "last_pong": number}
  | {"phase": "retrying"; "generation": number; "attempt": number; "deadline": number}
  | {"phase": "auth_failed"; "generation": number};
export function decodeRemoteTransportState(input: unknown): RemoteTransportState {
  const source = decodeObject(input);
  switch (source["phase"]) {
    case "stopped": exactFields(source, ["phase","generation"]); return {"phase": "stopped", "generation": decodeSafeNatural(source["generation"])};
    case "connecting": exactFields(source, ["phase","generation","attempt"]); return {"phase": "connecting", "generation": decodeSafeNatural(source["generation"]), "attempt": decodeSafeNatural(source["attempt"])};
    case "negotiating": exactFields(source, ["phase","generation","attempt"]); return {"phase": "negotiating", "generation": decodeSafeNatural(source["generation"]), "attempt": decodeSafeNatural(source["attempt"])};
    case "online": exactFields(source, ["phase","generation","last_pong"]); return {"phase": "online", "generation": decodeSafeNatural(source["generation"]), "last_pong": decodeSafeNatural(source["last_pong"])};
    case "retrying": exactFields(source, ["phase","generation","attempt","deadline"]); return {"phase": "retrying", "generation": decodeSafeNatural(source["generation"]), "attempt": decodeSafeNatural(source["attempt"]), "deadline": decodeSafeNatural(source["deadline"])};
    case "auth_failed": exactFields(source, ["phase","generation"]); return {"phase": "auth_failed", "generation": decodeSafeNatural(source["generation"])};
    // DEFENSE: External boundary values must name a declared RemoteTransportState variant.
    default: throw new TypeError('Unknown RemoteTransportState discriminant');
  }
}

export type RemoteTransportAction =
  | {"kind": "connect"; "generation": number}
  | {"kind": "open"; "generation": number}
  | {"kind": "retry"; "generation": number; "deadline": number}
  | {"kind": "heartbeat"; "generation": number; "deadline": number}
  | {"kind": "online"; "generation": number}
  | {"kind": "ping"; "generation": number}
  | {"kind": "retire"; }
  | {"kind": "stopped"; }
  | {"kind": "auth_failed"; };
export function decodeRemoteTransportAction(input: unknown): RemoteTransportAction {
  const source = decodeObject(input);
  switch (source["kind"]) {
    case "connect": exactFields(source, ["kind","generation"]); return {"kind": "connect", "generation": decodeSafeNatural(source["generation"])};
    case "open": exactFields(source, ["kind","generation"]); return {"kind": "open", "generation": decodeSafeNatural(source["generation"])};
    case "retry": exactFields(source, ["kind","generation","deadline"]); return {"kind": "retry", "generation": decodeSafeNatural(source["generation"]), "deadline": decodeSafeNatural(source["deadline"])};
    case "heartbeat": exactFields(source, ["kind","generation","deadline"]); return {"kind": "heartbeat", "generation": decodeSafeNatural(source["generation"]), "deadline": decodeSafeNatural(source["deadline"])};
    case "online": exactFields(source, ["kind","generation"]); return {"kind": "online", "generation": decodeSafeNatural(source["generation"])};
    case "ping": exactFields(source, ["kind","generation"]); return {"kind": "ping", "generation": decodeSafeNatural(source["generation"])};
    case "retire": exactFields(source, ["kind"]); return {"kind": "retire"};
    case "stopped": exactFields(source, ["kind"]); return {"kind": "stopped"};
    case "auth_failed": exactFields(source, ["kind"]); return {"kind": "auth_failed"};
    // DEFENSE: External boundary values must name a declared RemoteTransportAction variant.
    default: throw new TypeError('Unknown RemoteTransportAction discriminant');
  }
}

export type RemoteTransportObservation =
  | {"kind": "enable"; }
  | {"kind": "stop"; }
  | {"kind": "probe"; "generation": number; "now": number; "sample": number; "status": number}
  | {"kind": "lost"; "generation": number; "now": number; "sample": number}
  | {"kind": "rejected"; "generation": number}
  | {"kind": "negotiated"; "generation": number; "now": number}
  | {"kind": "pong"; "generation": number; "now": number}
  | {"kind": "heartbeat"; "generation": number; "now": number; "sample": number}
  | {"kind": "retry"; "generation": number; "now": number};
export function decodeRemoteTransportObservation(input: unknown): RemoteTransportObservation {
  const source = decodeObject(input);
  switch (source["kind"]) {
    case "enable": exactFields(source, ["kind"]); return {"kind": "enable"};
    case "stop": exactFields(source, ["kind"]); return {"kind": "stop"};
    case "probe": exactFields(source, ["kind","generation","now","sample","status"]); return {"kind": "probe", "generation": decodeSafeNatural(source["generation"]), "now": decodeSafeNatural(source["now"]), "sample": decodeSafeNatural(source["sample"]), "status": decodeSafeNatural(source["status"])};
    case "lost": exactFields(source, ["kind","generation","now","sample"]); return {"kind": "lost", "generation": decodeSafeNatural(source["generation"]), "now": decodeSafeNatural(source["now"]), "sample": decodeSafeNatural(source["sample"])};
    case "rejected": exactFields(source, ["kind","generation"]); return {"kind": "rejected", "generation": decodeSafeNatural(source["generation"])};
    case "negotiated": exactFields(source, ["kind","generation","now"]); return {"kind": "negotiated", "generation": decodeSafeNatural(source["generation"]), "now": decodeSafeNatural(source["now"])};
    case "pong": exactFields(source, ["kind","generation","now"]); return {"kind": "pong", "generation": decodeSafeNatural(source["generation"]), "now": decodeSafeNatural(source["now"])};
    case "heartbeat": exactFields(source, ["kind","generation","now","sample"]); return {"kind": "heartbeat", "generation": decodeSafeNatural(source["generation"]), "now": decodeSafeNatural(source["now"]), "sample": decodeSafeNatural(source["sample"])};
    case "retry": exactFields(source, ["kind","generation","now"]); return {"kind": "retry", "generation": decodeSafeNatural(source["generation"]), "now": decodeSafeNatural(source["now"])};
    // DEFENSE: External boundary values must name a declared RemoteTransportObservation variant.
    default: throw new TypeError('Unknown RemoteTransportObservation discriminant');
  }
}

export type RemoteAuthorizationState =
  | {"phase": "first"; }
  | {"phase": "second"; }
  | {"phase": "third"; }
  | {"phase": "last"; }
  | {"phase": "authorized"; }
  | {"phase": "denied"; }
  | {"phase": "revision_changed"; };
export function decodeRemoteAuthorizationState(input: unknown): RemoteAuthorizationState {
  const source = decodeObject(input);
  switch (source["phase"]) {
    case "first": exactFields(source, ["phase"]); return {"phase": "first"};
    case "second": exactFields(source, ["phase"]); return {"phase": "second"};
    case "third": exactFields(source, ["phase"]); return {"phase": "third"};
    case "last": exactFields(source, ["phase"]); return {"phase": "last"};
    case "authorized": exactFields(source, ["phase"]); return {"phase": "authorized"};
    case "denied": exactFields(source, ["phase"]); return {"phase": "denied"};
    case "revision_changed": exactFields(source, ["phase"]); return {"phase": "revision_changed"};
    // DEFENSE: External boundary values must name a declared RemoteAuthorizationState variant.
    default: throw new TypeError('Unknown RemoteAuthorizationState discriminant');
  }
}

export type RemoteAuthorizationAction =
  | {"kind": "check"; }
  | {"kind": "capture"; }
  | {"kind": "deny"; }
  | {"kind": "disconnect"; };
export function decodeRemoteAuthorizationAction(input: unknown): RemoteAuthorizationAction {
  const source = decodeObject(input);
  switch (source["kind"]) {
    case "check": exactFields(source, ["kind"]); return {"kind": "check"};
    case "capture": exactFields(source, ["kind"]); return {"kind": "capture"};
    case "deny": exactFields(source, ["kind"]); return {"kind": "deny"};
    case "disconnect": exactFields(source, ["kind"]); return {"kind": "disconnect"};
    // DEFENSE: External boundary values must name a declared RemoteAuthorizationAction variant.
    default: throw new TypeError('Unknown RemoteAuthorizationAction discriminant');
  }
}

export type HttpPlan =
  | {"action": "respond"; "status": number; "value": JsonValue}
  | {"action": "throw"; "kind": "TypeError" | "RangeError"; "message": string}
  | {"action": "observe_content_type"; "target": "account_refresh" | "audio_create" | "audio_login" | "remote_pair" | "remote_enable" | "remote_disable" | "remote_approve" | "remote_revoke" | "browser_command" | "browser_observation" | "command" | "assess" | "connection_command"}
  | {"action": "observe_host"; }
  | {"action": "parse_url"; }
  | {"action": "observe_connection_authorization"; }
  | {"action": "connection_method_origin"; }
  | {"action": "observe_local_authorization"; }
  | {"action": "local_origin"; }
  | {"action": "asset"; }
  | {"action": "audio_capabilities"; }
  | {"action": "audio_transcribe"; }
  | {"action": "audio_events"; }
  | {"action": "audio_stop"; }
  | {"action": "attachment_upload"; }
  | {"action": "attachment_download"; }
  | {"action": "browser_state"; }
  | {"action": "describe"; }
  | {"action": "remote_status"; }
  | {"action": "remote_pending"; }
  | {"action": "events"; }
  | {"action": "event_page"; }
  | {"action": "health"; }
  | {"action": "account_refresh"; "body"?: JsonValue}
  | {"action": "audio_create"; "body"?: JsonValue}
  | {"action": "audio_login"; "body"?: JsonValue}
  | {"action": "remote_pair"; "body"?: JsonValue}
  | {"action": "remote_enable"; "body"?: JsonValue}
  | {"action": "remote_disable"; "body"?: JsonValue}
  | {"action": "remote_approve"; "body"?: JsonValue}
  | {"action": "remote_revoke"; "body"?: JsonValue}
  | {"action": "browser_command"; "body"?: JsonValue}
  | {"action": "browser_observation"; "body"?: JsonValue}
  | {"action": "command"; "body"?: JsonValue}
  | {"action": "assess"; "body"?: JsonValue}
  | {"action": "connection_command"; "body"?: JsonValue};
export function decodeHttpPlan(input: unknown): HttpPlan {
  const source = decodeObject(input);
  switch (source["action"]) {
    case "respond": exactFields(source, ["action","status","value"]); return {"action": "respond", "status": decodeSafeNatural(source["status"]), "value": decodeJson(source["value"])};
    case "throw": exactFields(source, ["action","kind","message"]); return {"action": "throw", "kind": decodeEnum1(source["kind"]), "message": decodeText(source["message"])};
    case "observe_content_type": exactFields(source, ["action","target"]); return {"action": "observe_content_type", "target": decodeEnum2(source["target"])};
    case "observe_host": exactFields(source, ["action"]); return {"action": "observe_host"};
    case "parse_url": exactFields(source, ["action"]); return {"action": "parse_url"};
    case "observe_connection_authorization": exactFields(source, ["action"]); return {"action": "observe_connection_authorization"};
    case "connection_method_origin": exactFields(source, ["action"]); return {"action": "connection_method_origin"};
    case "observe_local_authorization": exactFields(source, ["action"]); return {"action": "observe_local_authorization"};
    case "local_origin": exactFields(source, ["action"]); return {"action": "local_origin"};
    case "asset": exactFields(source, ["action"]); return {"action": "asset"};
    case "audio_capabilities": exactFields(source, ["action"]); return {"action": "audio_capabilities"};
    case "audio_transcribe": exactFields(source, ["action"]); return {"action": "audio_transcribe"};
    case "audio_events": exactFields(source, ["action"]); return {"action": "audio_events"};
    case "audio_stop": exactFields(source, ["action"]); return {"action": "audio_stop"};
    case "attachment_upload": exactFields(source, ["action"]); return {"action": "attachment_upload"};
    case "attachment_download": exactFields(source, ["action"]); return {"action": "attachment_download"};
    case "browser_state": exactFields(source, ["action"]); return {"action": "browser_state"};
    case "describe": exactFields(source, ["action"]); return {"action": "describe"};
    case "remote_status": exactFields(source, ["action"]); return {"action": "remote_status"};
    case "remote_pending": exactFields(source, ["action"]); return {"action": "remote_pending"};
    case "events": exactFields(source, ["action"]); return {"action": "events"};
    case "event_page": exactFields(source, ["action"]); return {"action": "event_page"};
    case "health": exactFields(source, ["action"]); return {"action": "health"};
    case "account_refresh": exactFields(source, ["action","body"]); return {"action": "account_refresh", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "audio_create": exactFields(source, ["action","body"]); return {"action": "audio_create", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "audio_login": exactFields(source, ["action","body"]); return {"action": "audio_login", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "remote_pair": exactFields(source, ["action","body"]); return {"action": "remote_pair", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "remote_enable": exactFields(source, ["action","body"]); return {"action": "remote_enable", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "remote_disable": exactFields(source, ["action","body"]); return {"action": "remote_disable", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "remote_approve": exactFields(source, ["action","body"]); return {"action": "remote_approve", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "remote_revoke": exactFields(source, ["action","body"]); return {"action": "remote_revoke", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "browser_command": exactFields(source, ["action","body"]); return {"action": "browser_command", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "browser_observation": exactFields(source, ["action","body"]); return {"action": "browser_observation", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "command": exactFields(source, ["action","body"]); return {"action": "command", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "assess": exactFields(source, ["action","body"]); return {"action": "assess", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    case "connection_command": exactFields(source, ["action","body"]); return {"action": "connection_command", ...(source["body"] === undefined ? {} : {"body": decodeJson(source["body"])})};
    // DEFENSE: External boundary values must name a declared HttpPlan variant.
    default: throw new TypeError('Unknown HttpPlan discriminant');
  }
}

export type BrowserObservationPlan =
  | {"kind": "streams"; }
  | {"kind": "workspace-git"; "primary": string; "task_id"?: JsonValue}
  | {"kind": "browse-directories"; "path": JsonValue; "default_path": boolean; "project_root": JsonValue; "task_id"?: JsonValue}
  | {"kind": "directories"; "workspace": JsonValue; "task_id"?: JsonValue}
  | {"kind": "skill-catalog"; "workspace": JsonValue; "task_id"?: JsonValue};
export function decodeBrowserObservationPlan(input: unknown): BrowserObservationPlan {
  const source = decodeObject(input);
  switch (source["kind"]) {
    case "streams": exactFields(source, ["kind"]); return {"kind": "streams"};
    case "workspace-git": exactFields(source, ["kind","primary","task_id"]); return {"kind": "workspace-git", "primary": decodeText(source["primary"]), ...(source["task_id"] === undefined ? {} : {"task_id": decodeJson(source["task_id"])})};
    case "browse-directories": exactFields(source, ["kind","path","default_path","project_root","task_id"]); return {"kind": "browse-directories", "path": decodeJson(source["path"]), "default_path": decodeBoolean(source["default_path"]), "project_root": decodeJson(source["project_root"]), ...(source["task_id"] === undefined ? {} : {"task_id": decodeJson(source["task_id"])})};
    case "directories": exactFields(source, ["kind","workspace","task_id"]); return {"kind": "directories", "workspace": decodeJson(source["workspace"]), ...(source["task_id"] === undefined ? {} : {"task_id": decodeJson(source["task_id"])})};
    case "skill-catalog": exactFields(source, ["kind","workspace","task_id"]); return {"kind": "skill-catalog", "workspace": decodeJson(source["workspace"]), ...(source["task_id"] === undefined ? {} : {"task_id": decodeJson(source["task_id"])})};
    // DEFENSE: External boundary values must name a declared BrowserObservationPlan variant.
    default: throw new TypeError('Unknown BrowserObservationPlan discriminant');
  }
}

export type DispatchAction =
  | {"kind": "start"; "generation": DomainNatural}
  | {"kind": "rollback_workspace"; }
  | {"kind": "retain_workspace"; }
  | {"kind": "await"; "generation": DomainNatural}
  | {"kind": "cancel"; "generation": DomainNatural; "provider": boolean}
  | {"kind": "retry_failure"; }
  | {"kind": "settled"; }
  | {"kind": "retire"; };
export function decodeDispatchAction(input: unknown): DispatchAction {
  const source = decodeObject(input);
  switch (source["kind"]) {
    case "start": exactFields(source, ["kind","generation"]); return {"kind": "start", "generation": decodeNatural(source["generation"])};
    case "rollback_workspace": exactFields(source, ["kind"]); return {"kind": "rollback_workspace"};
    case "retain_workspace": exactFields(source, ["kind"]); return {"kind": "retain_workspace"};
    case "await": exactFields(source, ["kind","generation"]); return {"kind": "await", "generation": decodeNatural(source["generation"])};
    case "cancel": exactFields(source, ["kind","generation","provider"]); return {"kind": "cancel", "generation": decodeNatural(source["generation"]), "provider": decodeBoolean(source["provider"])};
    case "retry_failure": exactFields(source, ["kind"]); return {"kind": "retry_failure"};
    case "settled": exactFields(source, ["kind"]); return {"kind": "settled"};
    case "retire": exactFields(source, ["kind"]); return {"kind": "retire"};
    // DEFENSE: External boundary values must name a declared DispatchAction variant.
    default: throw new TypeError('Unknown DispatchAction discriminant');
  }
}

export type AudioAction =
  | {"type": "emit"; "event": JsonValue}
  | {"type": "journal"; "token": JsonValue; "command": JsonValue}
  | {"type": "context"; "context": JsonValue}
  | {"type": "contexts"; "token": JsonValue; "contexts": Array<JsonValue>}
  | {"type": "read"; "token": JsonValue; "after": DomainNatural}
  | {"type": "stop"; }
  | {"type": "release"; }
  | {"type": "timer"; }
  | {"type": "connect_timer"; }
  | {"type": "reject"; "message": string};
export function decodeAudioAction(input: unknown): AudioAction {
  const source = decodeObject(input);
  switch (source["type"]) {
    case "emit": exactFields(source, ["type","event"]); return {"type": "emit", "event": decodeJson(source["event"])};
    case "journal": exactFields(source, ["type","token","command"]); return {"type": "journal", "token": decodeJson(source["token"]), "command": decodeJson(source["command"])};
    case "context": exactFields(source, ["type","context"]); return {"type": "context", "context": decodeJson(source["context"])};
    case "contexts": exactFields(source, ["type","token","contexts"]); return {"type": "contexts", "token": decodeJson(source["token"]), "contexts": decodeArray(source["contexts"], item => decodeJson(item))};
    case "read": exactFields(source, ["type","token","after"]); return {"type": "read", "token": decodeJson(source["token"]), "after": decodeNatural(source["after"])};
    case "stop": exactFields(source, ["type"]); return {"type": "stop"};
    case "release": exactFields(source, ["type"]); return {"type": "release"};
    case "timer": exactFields(source, ["type"]); return {"type": "timer"};
    case "connect_timer": exactFields(source, ["type"]); return {"type": "connect_timer"};
    case "reject": exactFields(source, ["type","message"]); return {"type": "reject", "message": decodeText(source["message"])};
    // DEFENSE: External boundary values must name a declared AudioAction variant.
    default: throw new TypeError('Unknown AudioAction discriminant');
  }
}

export type AudioTransportAction =
  | {"type": "connect"; "attempt": DomainNatural}
  | {"type": "retry"; "attempt": DomainNatural; "delay": DomainNatural}
  | {"type": "ready"; }
  | {"type": "emit"; "event": JsonValue}
  | {"type": "close"; "event": JsonValue};
export function decodeAudioTransportAction(input: unknown): AudioTransportAction {
  const source = decodeObject(input);
  switch (source["type"]) {
    case "connect": exactFields(source, ["type","attempt"]); return {"type": "connect", "attempt": decodeNatural(source["attempt"])};
    case "retry": exactFields(source, ["type","attempt","delay"]); return {"type": "retry", "attempt": decodeNatural(source["attempt"]), "delay": decodeNatural(source["delay"])};
    case "ready": exactFields(source, ["type"]); return {"type": "ready"};
    case "emit": exactFields(source, ["type","event"]); return {"type": "emit", "event": decodeJson(source["event"])};
    case "close": exactFields(source, ["type","event"]); return {"type": "close", "event": decodeJson(source["event"])};
    // DEFENSE: External boundary values must name a declared AudioTransportAction variant.
    default: throw new TypeError('Unknown AudioTransportAction discriminant');
  }
}
export type RemoteConnectorSessionTransition = {"state": JsonValue; "action": "ignore" | "installed" | "retire" | "pairing" | "pending" | "expired" | "grants" | "enqueue" | "dequeue" | "disconnect" | "ready" | "controller_open" | "controller_close" | "request" | "pair_request" | "pong" | "notice" | "snapshot" | "unsubscribed" | "deliver"};
export function decodeRemoteConnectorSessionTransition(input: unknown): RemoteConnectorSessionTransition {
 const source = decodeObject(input); exactFields(source, ["state","action"]); return {"state": decodeJson(source["state"]), "action": decodeEnum3(source["action"])};
}

export type CloudReadinessTransition = {"state": JsonValue; "actions": Array<JsonValue>};
export function decodeCloudReadinessTransition(input: unknown): CloudReadinessTransition {
 const source = decodeObject(input); exactFields(source, ["state","actions"]); return {"state": decodeJson(source["state"]), "actions": decodeArray(source["actions"], item => decodeJson(item))};
}

export type ResourceTransition = {"state": JsonValue; "effects": Array<"persist" | "allocate" | "prepare" | "credentials" | "scan" | "terminate" | "finish" | "local_reserve" | "local_create" | "local_prepare" | "local_classify" | "local_release" | "local_remove" | "local_archive" | "local_observe" | "local_sync_registration" | "local_sync_ready" | "local_sync_archive" | "local_sync_release">};
export function decodeResourceTransition(input: unknown): ResourceTransition {
 const source = decodeObject(input); exactFields(source, ["state","effects"]); return {"state": decodeJson(source["state"]), "effects": decodeArray(source["effects"], item => decodeEnum4(item))};
}

export type RemoteTransportTransition = {"state": JsonValue; "actions": Array<JsonValue>};
export function decodeRemoteTransportTransition(input: unknown): RemoteTransportTransition {
 const source = decodeObject(input); exactFields(source, ["state","actions"]); return {"state": decodeJson(source["state"]), "actions": decodeArray(source["actions"], item => decodeJson(item))};
}

export type RemoteAuthorizationTransition = {"state": JsonValue; "action": JsonValue};
export function decodeRemoteAuthorizationTransition(input: unknown): RemoteAuthorizationTransition {
 const source = decodeObject(input); exactFields(source, ["state","action"]); return {"state": decodeJson(source["state"]), "action": decodeJson(source["action"])};
}

export type WorkspaceCommandPlan = {"root_task": boolean; "worktree": boolean; "selections": Array<JsonValue>};
export function decodeWorkspaceCommandPlan(input: unknown): WorkspaceCommandPlan {
 const source = decodeObject(input); exactFields(source, ["root_task","worktree","selections"]); return {"root_task": decodeBoolean(source["root_task"]), "worktree": decodeBoolean(source["worktree"]), "selections": decodeArray(source["selections"], item => decodeJson(item))};
}

export type WorkspaceSelectionPlan = {"value": JsonValue; "resolve_project": boolean};
export function decodeWorkspaceSelectionPlan(input: unknown): WorkspaceSelectionPlan {
 const source = decodeObject(input); exactFields(source, ["value","resolve_project"]); return {"value": decodeJson(source["value"]), "resolve_project": decodeBoolean(source["resolve_project"])};
}

export type WorkspaceSettingsPlan = {"project_id"?: DomainNatural | null; "observe_workspace": boolean};
export function decodeWorkspaceSettingsPlan(input: unknown): WorkspaceSettingsPlan {
 const source = decodeObject(input); exactFields(source, ["project_id","observe_workspace"]); return {...(source["project_id"] === undefined ? {} : {"project_id": source["project_id"] === null ? null : decodeNatural(source["project_id"])}), "observe_workspace": decodeBoolean(source["observe_workspace"])};
}

export type BrowserPath = {"path": JsonValue; "canonicalize": boolean};
export function decodeBrowserPath(input: unknown): BrowserPath {
 const source = decodeObject(input); exactFields(source, ["path","canonicalize"]); return {"path": decodeJson(source["path"]), "canonicalize": decodeBoolean(source["canonicalize"])};
}

export type DispatchTransition = {"state": JsonValue; "effects": Array<JsonValue>};
export function decodeDispatchTransition(input: unknown): DispatchTransition {
 const source = decodeObject(input); exactFields(source, ["state","effects"]); return {"state": decodeJson(source["state"]), "effects": decodeArray(source["effects"], item => decodeJson(item))};
}

export type AudioTransportBegin = {"token": DomainNatural; "effect": JsonValue};
export function decodeAudioTransportBegin(input: unknown): AudioTransportBegin {
 const source = decodeObject(input); exactFields(source, ["token","effect"]); return {"token": decodeNatural(source["token"]), "effect": decodeJson(source["effect"])};
}

export type AudioTransition = {"state": JsonValue; "actions": Array<JsonValue>};
export function decodeAudioTransition(input: unknown): AudioTransition {
 const source = decodeObject(input); exactFields(source, ["state","actions"]); return {"state": decodeJson(source["state"]), "actions": decodeArray(source["actions"], item => decodeJson(item))};
}

export type HttpRemoteApprovalBody = {"request_id": string; "permissions": JsonValue};
export function decodeHttpRemoteApprovalBody(input: unknown): HttpRemoteApprovalBody {
 const source = decodeObject(input); exactFields(source, ["request_id","permissions"]); return {"request_id": decodeText(source["request_id"]), "permissions": decodeJson(source["permissions"])};
}

export type HttpRemotePermissions = {"read": boolean; "control": boolean; "configure": boolean; "approve": boolean};
export function decodeHttpRemotePermissions(input: unknown): HttpRemotePermissions {
 const source = decodeObject(input); exactFields(source, ["read","control","configure","approve"]); return {"read": decodeBoolean(source["read"]), "control": decodeBoolean(source["control"]), "configure": decodeBoolean(source["configure"]), "approve": decodeBoolean(source["approve"])};
}

export type HttpRemoteRevokeBody = {"controller_id": string};
export function decodeHttpRemoteRevokeBody(input: unknown): HttpRemoteRevokeBody {
 const source = decodeObject(input); exactFields(source, ["controller_id"]); return {"controller_id": decodeText(source["controller_id"])};
}

export type HttpBrowserCommandBody = {"command": JsonValue};
export function decodeHttpBrowserCommandBody(input: unknown): HttpBrowserCommandBody {
 const source = decodeObject(input); exactFields(source, ["command"]); return {"command": decodeJson(source["command"])};
}

export type Effect =
  | {"kind": "observe_context"; "task_id": DomainNatural; "ticket": DomainNatural; "settings": JsonValue; "resource": JsonValue; "definitions": Array<JsonValue>; "bindings": Array<JsonValue>}
  | {"kind": "model"; "task_id": DomainNatural; "ticket": DomainNatural; "model": JsonValue; "output_mode": "plain" | "interactive-v1"; "settings": JsonValue; "resource": JsonValue; "sampling": JsonValue; "history": Array<JsonValue>; "context_selected": boolean; "context_scope": string; "context_replacement_source"?: DomainNatural | null; "output_reserve_tokens": DomainNatural; "source_length": DomainNatural; "tools": Array<JsonValue>; "callable": Array<string>}
  | {"kind": "reasoning"; "task_id": DomainNatural; "ticket": DomainNatural; "model": JsonValue; "history": Array<JsonValue>; "project_context": JsonValue; "history_preview": boolean; "history_preview_bytes": DomainNatural}
  | {"kind": "tool"; "task_id": DomainNatural; "ticket": DomainNatural; "operation_id": DomainNatural; "tool": JsonValue; "call": JsonValue; "execution": JsonValue}
  | {"kind": "approval"; "task_id": DomainNatural; "ticket": DomainNatural; "model": JsonValue; "call": JsonValue; "settings": JsonValue; "instructions": string; "user_requests": Array<string>}
  | {"kind": "hook"; "task_id": DomainNatural; "ticket": DomainNatural; "plugin": JsonValue; "tool": JsonValue; "call": JsonValue}
  | {"kind": "after_hook"; "task_id": DomainNatural; "ticket": DomainNatural; "operation_id": DomainNatural; "plugin": JsonValue; "call": JsonValue; "value": JsonValue; "error": boolean}
  | {"kind": "plugin_events"; "events": Array<JsonValue>}
  | {"kind": "reset_model_session"; "task_id": DomainNatural}
  | {"kind": "cancel"; "task_id": DomainNatural}
  | {"kind": "cancel_ticket"; "task_id": DomainNatural; "ticket": DomainNatural}
  | {"kind": "continue"; }
  | {"kind": "worktree_create"; "backend": "local" | "tencent_cvm"; "task_id": DomainNatural; "source_root": string; "workspace": JsonValue}
  | {"kind": "worktree_archive"; "backend": "local" | "tencent_cvm"; "task_id": DomainNatural; "root": string; "source_root": string}
  | {"kind": "task_title"; "task_id": DomainNatural; "ticket": DomainNatural; "model": JsonValue; "prompt": string}
  | {"kind": "board_text"; "card_id": DomainNatural; "ticket": DomainNatural; "model": JsonValue; "prompt": string; "retitle": boolean}
  | {"kind": "chatgpt_exec"; "operation_id": DomainNatural; "arguments": JsonValue; "execution": JsonValue}
  | {"kind": "chatgpt_cancel"; "operation_id": DomainNatural}
  | {"kind": "context_scope"; "task_id": DomainNatural; "ticket": DomainNatural; "model": JsonValue}
  | {"kind": "context_measure"; "task_id": DomainNatural; "ticket": DomainNatural; "model": JsonValue; "history": Array<JsonValue>; "context_selected": boolean; "context_scope": string; "tools": Array<JsonValue>; "settings": JsonValue; "callable": Array<string>; "validating": boolean}
  | {"kind": "context_compaction"; "task_id": DomainNatural; "ticket": DomainNatural; "model": JsonValue; "context_selected": boolean; "context_scope": string; "method": string; "window_tokens": DomainNatural; "output_reserve_tokens": DomainNatural; "plan": JsonValue}
  | {"kind": "compaction_clock"; "deadline": DomainNatural}
  | {"kind": "compaction_cancel"; "task_id": DomainNatural; "ticket": DomainNatural};
export function decodeEffect(input: unknown): Effect {
  const source = decodeObject(input);
  switch (source["kind"]) {
    case "observe_context": exactFields(source, ["kind","task_id","ticket","settings","resource","definitions","bindings"]); return {"kind": "observe_context", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "settings": decodeJson(source["settings"]), "resource": decodeJson(source["resource"]), "definitions": decodeArray(source["definitions"], item => decodeJson(item)), "bindings": decodeArray(source["bindings"], item => decodeJson(item))};
    case "model": exactFields(source, ["kind","task_id","ticket","model","output_mode","settings","resource","sampling","history","context_selected","context_scope","context_replacement_source","output_reserve_tokens","source_length","tools","callable"]); return {"kind": "model", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"]), "output_mode": decodeEnum5(source["output_mode"]), "settings": decodeJson(source["settings"]), "resource": decodeJson(source["resource"]), "sampling": decodeJson(source["sampling"]), "history": decodeArray(source["history"], item => decodeJson(item)), "context_selected": decodeBoolean(source["context_selected"]), "context_scope": decodeText(source["context_scope"]), ...(source["context_replacement_source"] === undefined ? {} : {"context_replacement_source": source["context_replacement_source"] === null ? null : decodeNatural(source["context_replacement_source"])}), "output_reserve_tokens": decodeNatural(source["output_reserve_tokens"]), "source_length": decodeNatural(source["source_length"]), "tools": decodeArray(source["tools"], item => decodeJson(item)), "callable": decodeArray(source["callable"], item => decodeText(item))};
    case "reasoning": exactFields(source, ["kind","task_id","ticket","model","history","project_context","history_preview","history_preview_bytes"]); return {"kind": "reasoning", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"]), "history": decodeArray(source["history"], item => decodeJson(item)), "project_context": decodeJson(source["project_context"]), "history_preview": decodeBoolean(source["history_preview"]), "history_preview_bytes": decodeNatural(source["history_preview_bytes"])};
    case "tool": exactFields(source, ["kind","task_id","ticket","operation_id","tool","call","execution"]); return {"kind": "tool", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "operation_id": decodeNatural(source["operation_id"]), "tool": decodeJson(source["tool"]), "call": decodeJson(source["call"]), "execution": decodeJson(source["execution"])};
    case "approval": exactFields(source, ["kind","task_id","ticket","model","call","settings","instructions","user_requests"]); return {"kind": "approval", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"]), "call": decodeJson(source["call"]), "settings": decodeJson(source["settings"]), "instructions": decodeText(source["instructions"]), "user_requests": decodeArray(source["user_requests"], item => decodeText(item))};
    case "hook": exactFields(source, ["kind","task_id","ticket","plugin","tool","call"]); return {"kind": "hook", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "plugin": decodeJson(source["plugin"]), "tool": decodeJson(source["tool"]), "call": decodeJson(source["call"])};
    case "after_hook": exactFields(source, ["kind","task_id","ticket","operation_id","plugin","call","value","error"]); return {"kind": "after_hook", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "operation_id": decodeNatural(source["operation_id"]), "plugin": decodeJson(source["plugin"]), "call": decodeJson(source["call"]), "value": decodeJson(source["value"]), "error": decodeBoolean(source["error"])};
    case "plugin_events": exactFields(source, ["kind","events"]); return {"kind": "plugin_events", "events": decodeArray(source["events"], item => decodeJson(item))};
    case "reset_model_session": exactFields(source, ["kind","task_id"]); return {"kind": "reset_model_session", "task_id": decodeNatural(source["task_id"])};
    case "cancel": exactFields(source, ["kind","task_id"]); return {"kind": "cancel", "task_id": decodeNatural(source["task_id"])};
    case "cancel_ticket": exactFields(source, ["kind","task_id","ticket"]); return {"kind": "cancel_ticket", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"])};
    case "continue": exactFields(source, ["kind"]); return {"kind": "continue"};
    case "worktree_create": exactFields(source, ["kind","backend","task_id","source_root","workspace"]); return {"kind": "worktree_create", "backend": decodeEnum6(source["backend"]), "task_id": decodeNatural(source["task_id"]), "source_root": decodeText(source["source_root"]), "workspace": decodeJson(source["workspace"])};
    case "worktree_archive": exactFields(source, ["kind","backend","task_id","root","source_root"]); return {"kind": "worktree_archive", "backend": decodeEnum6(source["backend"]), "task_id": decodeNatural(source["task_id"]), "root": decodeText(source["root"]), "source_root": decodeText(source["source_root"])};
    case "task_title": exactFields(source, ["kind","task_id","ticket","model","prompt"]); return {"kind": "task_title", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"]), "prompt": decodeText(source["prompt"])};
    case "board_text": exactFields(source, ["kind","card_id","ticket","model","prompt","retitle"]); return {"kind": "board_text", "card_id": decodeNatural(source["card_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"]), "prompt": decodeText(source["prompt"]), "retitle": decodeBoolean(source["retitle"])};
    case "chatgpt_exec": exactFields(source, ["kind","operation_id","arguments","execution"]); return {"kind": "chatgpt_exec", "operation_id": decodeNatural(source["operation_id"]), "arguments": decodeJson(source["arguments"]), "execution": decodeJson(source["execution"])};
    case "chatgpt_cancel": exactFields(source, ["kind","operation_id"]); return {"kind": "chatgpt_cancel", "operation_id": decodeNatural(source["operation_id"])};
    case "context_scope": exactFields(source, ["kind","task_id","ticket","model"]); return {"kind": "context_scope", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"])};
    case "context_measure": exactFields(source, ["kind","task_id","ticket","model","history","context_selected","context_scope","tools","settings","callable","validating"]); return {"kind": "context_measure", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"]), "history": decodeArray(source["history"], item => decodeJson(item)), "context_selected": decodeBoolean(source["context_selected"]), "context_scope": decodeText(source["context_scope"]), "tools": decodeArray(source["tools"], item => decodeJson(item)), "settings": decodeJson(source["settings"]), "callable": decodeArray(source["callable"], item => decodeText(item)), "validating": decodeBoolean(source["validating"])};
    case "context_compaction": exactFields(source, ["kind","task_id","ticket","model","context_selected","context_scope","method","window_tokens","output_reserve_tokens","plan"]); return {"kind": "context_compaction", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"]), "context_selected": decodeBoolean(source["context_selected"]), "context_scope": decodeText(source["context_scope"]), "method": decodeText(source["method"]), "window_tokens": decodeNatural(source["window_tokens"]), "output_reserve_tokens": decodeNatural(source["output_reserve_tokens"]), "plan": decodeJson(source["plan"])};
    case "compaction_clock": exactFields(source, ["kind","deadline"]); return {"kind": "compaction_clock", "deadline": decodeNatural(source["deadline"])};
    case "compaction_cancel": exactFields(source, ["kind","task_id","ticket"]); return {"kind": "compaction_cancel", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"])};
    // DEFENSE: External boundary values must name a declared Effect variant.
    default: throw new TypeError('Unknown Effect discriminant');
  }
}

export type AudioAdmission =
  | {"allowed": true; "max_bytes": number; "timeout_ms": number; "connect_timeout_ms": number; "session_max_ms": number}
  | {"allowed": false; "message": string};
export function decodeAudioAdmission(input: unknown): AudioAdmission {
  const source = decodeObject(input);
  switch (source["allowed"]) {
    case true: exactFields(source, ["allowed","max_bytes","timeout_ms","connect_timeout_ms","session_max_ms"]); return {"allowed": true, "max_bytes": decodeSafeNatural(source["max_bytes"]), "timeout_ms": decodeSafeNatural(source["timeout_ms"]), "connect_timeout_ms": decodeSafeNatural(source["connect_timeout_ms"]), "session_max_ms": decodeSafeNatural(source["session_max_ms"])};
    case false: exactFields(source, ["allowed","message"]); return {"allowed": false, "message": decodeText(source["message"])};
    // DEFENSE: External boundary values must name a declared AudioAdmission variant.
    default: throw new TypeError('Unknown AudioAdmission discriminant');
  }
}

export type Command =
  | {"op": "configure_task_execution"; "task_id": DomainNatural; "profile"?: string; "reasoning"?: string; "sandbox"?: JsonValue; "approval"?: JsonValue}
  | {"op": "create"; "profile": string; "reasoning"?: string; "message"?: JsonValue; "images"?: Array<JsonValue>; "settings"?: JsonValue}
  | {"op": "create_idle"; "profile": string; "reasoning"?: string; "settings"?: JsonValue; "work_id"?: DomainNatural; "create_worktree"?: boolean}
  | {"op": "send"; "task_id": DomainNatural; "message"?: JsonValue; "images"?: Array<JsonValue>}
  | {"op": "steer"; "task_id": DomainNatural; "message"?: JsonValue; "images"?: Array<JsonValue>}
  | {"op": "cancel_operation"; "task_id": DomainNatural; "operation_id": DomainNatural}
  | {"op": "freeze"; "task_id": DomainNatural}
  | {"op": "unfreeze"; "task_id": DomainNatural}
  | {"op": "stop"; "task_id": DomainNatural}
  | {"op": "interrupt"; "task_id": DomainNatural}
  | {"op": "archive"; "task_id": DomainNatural}
  | {"op": "fork"; "task_id": DomainNatural; "child_count": DomainNatural; "messages"?: Array<JsonValue>; "settings"?: JsonValue; "settings_origin"?: "parent" | "environment" | null}
  | {"op": "open_side_conversation"; "task_id": DomainNatural; "message"?: JsonValue; "images"?: Array<JsonValue>}
  | {"op": "return_side_conversation"; "task_id": DomainNatural}
  | {"op": "compact"; "task_id": DomainNatural; "summary"?: string}
  | {"op": "read"; "task_id": DomainNatural; "after"?: DomainNatural; "limit"?: DomainNatural}
  | {"op": "search_history"; "query": string; "project_id"?: DomainNatural; "work_id"?: DomainNatural; "after"?: DomainNatural; "limit"?: DomainNatural}
  | {"op": "list"; }
  | {"op": "describe"; }
  | {"op": "create_project"; "name": string; "workspace": JsonValue; "guidance"?: JsonValue; "create_worktree"?: boolean; "workspace_binding"?: JsonValue}
  | {"op": "update_project"; "project_id": DomainNatural; "name"?: string; "workspace"?: JsonValue; "guidance"?: JsonValue; "create_worktree"?: boolean; "workspace_binding"?: JsonValue}
  | {"op": "delete_project"; "project_id": DomainNatural}
  | {"op": "list_projects"; }
  | {"op": "read_project"; "project_id": DomainNatural}
  | {"op": "review_approval"; "task_id": DomainNatural; "operation_id": DomainNatural; "decision": "allow" | "deny"; "reason"?: string}
  | {"op": "record_speech_transcript"; "task_id": DomainNatural; "session_id": string; "item_id": string; "speaker": "user" | "assistant"; "completion": "completed" | "interrupted"; "text": string}
  | {"op": "accept_speech_delegation"; "task_id": DomainNatural; "session_id": string; "delegation_id": string; "message": string; "mode": "send" | "steer"}
  | {"op": "create_card"; "observed_at"?: string; "title"?: string; "description"?: string; "status"?: string; "priority"?: string; "assignee"?: string; "project"?: string; "labels"?: Array<string>; "attachments"?: Array<JsonValue>; "assisted"?: boolean; "draft_profile"?: string}
  | {"op": "update_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string; "title"?: string; "description"?: string; "status"?: string; "priority"?: string; "assignee"?: string; "project"?: string; "labels"?: Array<string>; "attachments"?: Array<JsonValue>}
  | {"op": "move_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string; "status"?: string; "before_card"?: string}
  | {"op": "archive_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string}
  | {"op": "restore_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string}
  | {"op": "delete_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string}
  | {"op": "run_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string}
  | {"op": "link_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string; "task_id"?: DomainNatural}
  | {"op": "regenerate_card_title"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string; "draft_profile"?: string}
  | {"op": "pin_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string; "pinned"?: boolean}
  | {"op": "board_settings"; "automatic": boolean; "draft_profile": string}
  | {"op": "save_board_agent"; "agent": string; "revision": DomainNatural; "name": string; "profile": string; "reasoning": string; "instructions": string; "settings"?: JsonValue; "concurrency": DomainNatural}
  | {"op": "delete_board_agent"; "agent_id": DomainNatural; "revision": DomainNatural}
  | {"op": "list_cards"; }
  | {"op": "read_card"; "card_id": DomainNatural}
  | {"op": "list_board_agents"; }
  | {"op": "configure_chatgpt_connections"; "connections": Array<JsonValue>}
  | {"op": "chatgpt_exec"; "connection_id": DomainNatural; "project_id": DomainNatural; "request_id": string; "arguments": JsonValue}
  | {"op": "chatgpt_cancel"; "connection_id": DomainNatural; "project_id": DomainNatural; "operation_id": DomainNatural}
  | {"op": "chatgpt_forget"; "connection_id": DomainNatural; "project_id": DomainNatural; "operation_id": DomainNatural}
  | {"op": "chatgpt_projects"; "connection_id": DomainNatural}
  | {"op": "chatgpt_project"; "connection_id": DomainNatural; "project_id": DomainNatural}
  | {"op": "chatgpt_operation"; "connection_id": DomainNatural; "project_id": DomainNatural; "operation_id": DomainNatural}
  | {"op": "chatgpt_operations"; "connection_id": DomainNatural; "project_id": DomainNatural}
  | {"op": "remote_enable"; }
  | {"op": "remote_disable"; }
  | {"op": "remote_grant"; "controller_id": string; "permissions": JsonValue}
  | {"op": "remote_revoke"; "controller_id": string}
  | {"op": "remote_status"; }
  | {"op": "create_task_graph"; "work_id"?: DomainNatural; "name": string; "nodes": Array<JsonValue>; "rules": Array<JsonValue>}
  | {"op": "update_task_graph"; "graph_id": DomainNatural; "name": string; "nodes": Array<JsonValue>; "rules": Array<JsonValue>}
  | {"op": "delete_task_graph"; "graph_id": DomainNatural}
  | {"op": "list_task_graphs"; }
  | {"op": "read_task_graph"; "graph_id": DomainNatural}
  | {"op": "read_title_settings"; }
  | {"op": "configure_title_settings"; "revision": DomainNatural; "task_prompt": string; "agent_prompt": string}
  | {"op": "create_work"; "name"?: string}
  | {"op": "rename_work"; "work_id": DomainNatural; "name": string}
  | {"op": "create_work_task"; "work_id": DomainNatural; "profile": string; "reasoning"?: string; "message"?: JsonValue; "images"?: Array<JsonValue>; "settings"?: JsonValue; "create_worktree"?: boolean}
  | {"op": "list_works"; }
  | {"op": "read_work"; "work_id": DomainNatural}
  | {"op": "read_work_ui"; }
  | {"op": "apply_work_ui_patch"; "patch": string; "revision": DomainNatural}
  | {"op": "create_worktree_task"; "profile": string; "reasoning"?: string; "message"?: JsonValue; "images"?: Array<JsonValue>; "settings"?: JsonValue}
  | {"op": "create_workspace_task"; "backend": "local" | "tencent_cvm"; "profile": string; "reasoning"?: string; "message"?: JsonValue; "images"?: Array<JsonValue>; "settings"?: JsonValue; "work_id"?: DomainNatural}
  | {"op": "list_worktrees"; }
  | {"op": "read_worktree"; "task_id": DomainNatural}
  | {"op": "retry_worktree_archive"; "task_id": DomainNatural}
  | {"op": "resolve_workspace"; "workspace"?: JsonValue | null; "project_id"?: DomainNatural | null};
export function decodeCommand(input: unknown): Command {
  const source = decodeObject(input);
  switch (source["op"]) {
    case "configure_task_execution": exactFields(source, ["op","task_id","profile","reasoning","sandbox","approval"]); return {"op": "configure_task_execution", "task_id": decodeNatural(source["task_id"]), ...(source["profile"] === undefined ? {} : {"profile": decodeText(source["profile"])}), ...(source["reasoning"] === undefined ? {} : {"reasoning": decodeText(source["reasoning"])}), ...(source["sandbox"] === undefined ? {} : {"sandbox": decodeJson(source["sandbox"])}), ...(source["approval"] === undefined ? {} : {"approval": decodeJson(source["approval"])})};
    case "create": exactFields(source, ["op","profile","reasoning","message","images","settings"]); return {"op": "create", "profile": decodeText(source["profile"]), ...(source["reasoning"] === undefined ? {} : {"reasoning": decodeText(source["reasoning"])}), ...(source["message"] === undefined ? {} : {"message": decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": decodeArray(source["images"], item => decodeJson(item))}), ...(source["settings"] === undefined ? {} : {"settings": decodeJson(source["settings"])})};
    case "create_idle": exactFields(source, ["op","profile","reasoning","settings","work_id","create_worktree"]); return {"op": "create_idle", "profile": decodeText(source["profile"]), ...(source["reasoning"] === undefined ? {} : {"reasoning": decodeText(source["reasoning"])}), ...(source["settings"] === undefined ? {} : {"settings": decodeJson(source["settings"])}), ...(source["work_id"] === undefined ? {} : {"work_id": decodeNatural(source["work_id"])}), ...(source["create_worktree"] === undefined ? {} : {"create_worktree": decodeBoolean(source["create_worktree"])})};
    case "send": exactFields(source, ["op","task_id","message","images"]); return {"op": "send", "task_id": decodeNatural(source["task_id"]), ...(source["message"] === undefined ? {} : {"message": decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": decodeArray(source["images"], item => decodeJson(item))})};
    case "steer": exactFields(source, ["op","task_id","message","images"]); return {"op": "steer", "task_id": decodeNatural(source["task_id"]), ...(source["message"] === undefined ? {} : {"message": decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": decodeArray(source["images"], item => decodeJson(item))})};
    case "cancel_operation": exactFields(source, ["op","task_id","operation_id"]); return {"op": "cancel_operation", "task_id": decodeNatural(source["task_id"]), "operation_id": decodeNatural(source["operation_id"])};
    case "freeze": exactFields(source, ["op","task_id"]); return {"op": "freeze", "task_id": decodeNatural(source["task_id"])};
    case "unfreeze": exactFields(source, ["op","task_id"]); return {"op": "unfreeze", "task_id": decodeNatural(source["task_id"])};
    case "stop": exactFields(source, ["op","task_id"]); return {"op": "stop", "task_id": decodeNatural(source["task_id"])};
    case "interrupt": exactFields(source, ["op","task_id"]); return {"op": "interrupt", "task_id": decodeNatural(source["task_id"])};
    case "archive": exactFields(source, ["op","task_id"]); return {"op": "archive", "task_id": decodeNatural(source["task_id"])};
    case "fork": exactFields(source, ["op","task_id","child_count","messages","settings","settings_origin"]); return {"op": "fork", "task_id": decodeNatural(source["task_id"]), "child_count": decodeNatural(source["child_count"]), ...(source["messages"] === undefined ? {} : {"messages": decodeArray(source["messages"], item => decodeJson(item))}), ...(source["settings"] === undefined ? {} : {"settings": decodeJson(source["settings"])}), ...(source["settings_origin"] === undefined ? {} : {"settings_origin": source["settings_origin"] === null ? null : decodeEnum7(source["settings_origin"])})};
    case "open_side_conversation": exactFields(source, ["op","task_id","message","images"]); return {"op": "open_side_conversation", "task_id": decodeNatural(source["task_id"]), ...(source["message"] === undefined ? {} : {"message": decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": decodeArray(source["images"], item => decodeJson(item))})};
    case "return_side_conversation": exactFields(source, ["op","task_id"]); return {"op": "return_side_conversation", "task_id": decodeNatural(source["task_id"])};
    case "compact": exactFields(source, ["op","task_id","summary"]); return {"op": "compact", "task_id": decodeNatural(source["task_id"]), ...(source["summary"] === undefined ? {} : {"summary": decodeText(source["summary"])})};
    case "read": exactFields(source, ["op","task_id","after","limit"]); return {"op": "read", "task_id": decodeNatural(source["task_id"]), ...(source["after"] === undefined ? {} : {"after": decodeNatural(source["after"])}), ...(source["limit"] === undefined ? {} : {"limit": decodeNatural(source["limit"])})};
    case "search_history": exactFields(source, ["op","query","project_id","work_id","after","limit"]); return {"op": "search_history", "query": decodeText(source["query"]), ...(source["project_id"] === undefined ? {} : {"project_id": decodeNatural(source["project_id"])}), ...(source["work_id"] === undefined ? {} : {"work_id": decodeNatural(source["work_id"])}), ...(source["after"] === undefined ? {} : {"after": decodeNatural(source["after"])}), ...(source["limit"] === undefined ? {} : {"limit": decodeNatural(source["limit"])})};
    case "list": exactFields(source, ["op"]); return {"op": "list"};
    case "describe": exactFields(source, ["op"]); return {"op": "describe"};
    case "create_project": exactFields(source, ["op","name","workspace","guidance","create_worktree","workspace_binding"]); return {"op": "create_project", "name": decodeText(source["name"]), "workspace": decodeJson(source["workspace"]), ...(source["guidance"] === undefined ? {} : {"guidance": decodeJson(source["guidance"])}), ...(source["create_worktree"] === undefined ? {} : {"create_worktree": decodeBoolean(source["create_worktree"])}), ...(source["workspace_binding"] === undefined ? {} : {"workspace_binding": decodeJson(source["workspace_binding"])})};
    case "update_project": exactFields(source, ["op","project_id","name","workspace","guidance","create_worktree","workspace_binding"]); return {"op": "update_project", "project_id": decodeNatural(source["project_id"]), ...(source["name"] === undefined ? {} : {"name": decodeText(source["name"])}), ...(source["workspace"] === undefined ? {} : {"workspace": decodeJson(source["workspace"])}), ...(source["guidance"] === undefined ? {} : {"guidance": decodeJson(source["guidance"])}), ...(source["create_worktree"] === undefined ? {} : {"create_worktree": decodeBoolean(source["create_worktree"])}), ...(source["workspace_binding"] === undefined ? {} : {"workspace_binding": decodeJson(source["workspace_binding"])})};
    case "delete_project": exactFields(source, ["op","project_id"]); return {"op": "delete_project", "project_id": decodeNatural(source["project_id"])};
    case "list_projects": exactFields(source, ["op"]); return {"op": "list_projects"};
    case "read_project": exactFields(source, ["op","project_id"]); return {"op": "read_project", "project_id": decodeNatural(source["project_id"])};
    case "review_approval": exactFields(source, ["op","task_id","operation_id","decision","reason"]); return {"op": "review_approval", "task_id": decodeNatural(source["task_id"]), "operation_id": decodeNatural(source["operation_id"]), "decision": decodeEnum8(source["decision"]), ...(source["reason"] === undefined ? {} : {"reason": decodeText(source["reason"])})};
    case "record_speech_transcript": exactFields(source, ["op","task_id","session_id","item_id","speaker","completion","text"]); return {"op": "record_speech_transcript", "task_id": decodeNatural(source["task_id"]), "session_id": decodeText(source["session_id"]), "item_id": decodeText(source["item_id"]), "speaker": decodeEnum9(source["speaker"]), "completion": decodeEnum10(source["completion"]), "text": decodeText(source["text"])};
    case "accept_speech_delegation": exactFields(source, ["op","task_id","session_id","delegation_id","message","mode"]); return {"op": "accept_speech_delegation", "task_id": decodeNatural(source["task_id"]), "session_id": decodeText(source["session_id"]), "delegation_id": decodeText(source["delegation_id"]), "message": decodeText(source["message"]), "mode": decodeEnum11(source["mode"])};
    case "create_card": exactFields(source, ["op","observed_at","title","description","status","priority","assignee","project","labels","attachments","assisted","draft_profile"]); return {"op": "create_card", ...(source["observed_at"] === undefined ? {} : {"observed_at": decodeText(source["observed_at"])}), ...(source["title"] === undefined ? {} : {"title": decodeText(source["title"])}), ...(source["description"] === undefined ? {} : {"description": decodeText(source["description"])}), ...(source["status"] === undefined ? {} : {"status": decodeText(source["status"])}), ...(source["priority"] === undefined ? {} : {"priority": decodeText(source["priority"])}), ...(source["assignee"] === undefined ? {} : {"assignee": decodeText(source["assignee"])}), ...(source["project"] === undefined ? {} : {"project": decodeText(source["project"])}), ...(source["labels"] === undefined ? {} : {"labels": decodeArray(source["labels"], item => decodeText(item))}), ...(source["attachments"] === undefined ? {} : {"attachments": decodeArray(source["attachments"], item => decodeJson(item))}), ...(source["assisted"] === undefined ? {} : {"assisted": decodeBoolean(source["assisted"])}), ...(source["draft_profile"] === undefined ? {} : {"draft_profile": decodeText(source["draft_profile"])})};
    case "update_card": exactFields(source, ["op","card_id","revision","observed_at","title","description","status","priority","assignee","project","labels","attachments"]); return {"op": "update_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": decodeText(source["observed_at"])}), ...(source["title"] === undefined ? {} : {"title": decodeText(source["title"])}), ...(source["description"] === undefined ? {} : {"description": decodeText(source["description"])}), ...(source["status"] === undefined ? {} : {"status": decodeText(source["status"])}), ...(source["priority"] === undefined ? {} : {"priority": decodeText(source["priority"])}), ...(source["assignee"] === undefined ? {} : {"assignee": decodeText(source["assignee"])}), ...(source["project"] === undefined ? {} : {"project": decodeText(source["project"])}), ...(source["labels"] === undefined ? {} : {"labels": decodeArray(source["labels"], item => decodeText(item))}), ...(source["attachments"] === undefined ? {} : {"attachments": decodeArray(source["attachments"], item => decodeJson(item))})};
    case "move_card": exactFields(source, ["op","card_id","revision","observed_at","status","before_card"]); return {"op": "move_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": decodeText(source["observed_at"])}), ...(source["status"] === undefined ? {} : {"status": decodeText(source["status"])}), ...(source["before_card"] === undefined ? {} : {"before_card": decodeText(source["before_card"])})};
    case "archive_card": exactFields(source, ["op","card_id","revision","observed_at"]); return {"op": "archive_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": decodeText(source["observed_at"])})};
    case "restore_card": exactFields(source, ["op","card_id","revision","observed_at"]); return {"op": "restore_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": decodeText(source["observed_at"])})};
    case "delete_card": exactFields(source, ["op","card_id","revision","observed_at"]); return {"op": "delete_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": decodeText(source["observed_at"])})};
    case "run_card": exactFields(source, ["op","card_id","revision","observed_at"]); return {"op": "run_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": decodeText(source["observed_at"])})};
    case "link_card": exactFields(source, ["op","card_id","revision","observed_at","task_id"]); return {"op": "link_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": decodeText(source["observed_at"])}), ...(source["task_id"] === undefined ? {} : {"task_id": decodeNatural(source["task_id"])})};
    case "regenerate_card_title": exactFields(source, ["op","card_id","revision","observed_at","draft_profile"]); return {"op": "regenerate_card_title", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": decodeText(source["observed_at"])}), ...(source["draft_profile"] === undefined ? {} : {"draft_profile": decodeText(source["draft_profile"])})};
    case "pin_card": exactFields(source, ["op","card_id","revision","observed_at","pinned"]); return {"op": "pin_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": decodeText(source["observed_at"])}), ...(source["pinned"] === undefined ? {} : {"pinned": decodeBoolean(source["pinned"])})};
    case "board_settings": exactFields(source, ["op","automatic","draft_profile"]); return {"op": "board_settings", "automatic": decodeBoolean(source["automatic"]), "draft_profile": decodeText(source["draft_profile"])};
    case "save_board_agent": exactFields(source, ["op","agent","revision","name","profile","reasoning","instructions","settings","concurrency"]); return {"op": "save_board_agent", "agent": decodeText(source["agent"]), "revision": decodeNatural(source["revision"]), "name": decodeText(source["name"]), "profile": decodeText(source["profile"]), "reasoning": decodeText(source["reasoning"]), "instructions": decodeText(source["instructions"]), ...(source["settings"] === undefined ? {} : {"settings": decodeJson(source["settings"])}), "concurrency": decodeNatural(source["concurrency"])};
    case "delete_board_agent": exactFields(source, ["op","agent_id","revision"]); return {"op": "delete_board_agent", "agent_id": decodeNatural(source["agent_id"]), "revision": decodeNatural(source["revision"])};
    case "list_cards": exactFields(source, ["op"]); return {"op": "list_cards"};
    case "read_card": exactFields(source, ["op","card_id"]); return {"op": "read_card", "card_id": decodeNatural(source["card_id"])};
    case "list_board_agents": exactFields(source, ["op"]); return {"op": "list_board_agents"};
    case "configure_chatgpt_connections": exactFields(source, ["op","connections"]); return {"op": "configure_chatgpt_connections", "connections": decodeArray(source["connections"], item => decodeJson(item))};
    case "chatgpt_exec": exactFields(source, ["op","connection_id","project_id","request_id","arguments"]); return {"op": "chatgpt_exec", "connection_id": decodeNatural(source["connection_id"]), "project_id": decodeNatural(source["project_id"]), "request_id": decodeText(source["request_id"]), "arguments": decodeJson(source["arguments"])};
    case "chatgpt_cancel": exactFields(source, ["op","connection_id","project_id","operation_id"]); return {"op": "chatgpt_cancel", "connection_id": decodeNatural(source["connection_id"]), "project_id": decodeNatural(source["project_id"]), "operation_id": decodeNatural(source["operation_id"])};
    case "chatgpt_forget": exactFields(source, ["op","connection_id","project_id","operation_id"]); return {"op": "chatgpt_forget", "connection_id": decodeNatural(source["connection_id"]), "project_id": decodeNatural(source["project_id"]), "operation_id": decodeNatural(source["operation_id"])};
    case "chatgpt_projects": exactFields(source, ["op","connection_id"]); return {"op": "chatgpt_projects", "connection_id": decodeNatural(source["connection_id"])};
    case "chatgpt_project": exactFields(source, ["op","connection_id","project_id"]); return {"op": "chatgpt_project", "connection_id": decodeNatural(source["connection_id"]), "project_id": decodeNatural(source["project_id"])};
    case "chatgpt_operation": exactFields(source, ["op","connection_id","project_id","operation_id"]); return {"op": "chatgpt_operation", "connection_id": decodeNatural(source["connection_id"]), "project_id": decodeNatural(source["project_id"]), "operation_id": decodeNatural(source["operation_id"])};
    case "chatgpt_operations": exactFields(source, ["op","connection_id","project_id"]); return {"op": "chatgpt_operations", "connection_id": decodeNatural(source["connection_id"]), "project_id": decodeNatural(source["project_id"])};
    case "remote_enable": exactFields(source, ["op"]); return {"op": "remote_enable"};
    case "remote_disable": exactFields(source, ["op"]); return {"op": "remote_disable"};
    case "remote_grant": exactFields(source, ["op","controller_id","permissions"]); return {"op": "remote_grant", "controller_id": decodeText(source["controller_id"]), "permissions": decodeJson(source["permissions"])};
    case "remote_revoke": exactFields(source, ["op","controller_id"]); return {"op": "remote_revoke", "controller_id": decodeText(source["controller_id"])};
    case "remote_status": exactFields(source, ["op"]); return {"op": "remote_status"};
    case "create_task_graph": exactFields(source, ["op","work_id","name","nodes","rules"]); return {"op": "create_task_graph", ...(source["work_id"] === undefined ? {} : {"work_id": decodeNatural(source["work_id"])}), "name": decodeText(source["name"]), "nodes": decodeArray(source["nodes"], item => decodeJson(item)), "rules": decodeArray(source["rules"], item => decodeJson(item))};
    case "update_task_graph": exactFields(source, ["op","graph_id","name","nodes","rules"]); return {"op": "update_task_graph", "graph_id": decodeNatural(source["graph_id"]), "name": decodeText(source["name"]), "nodes": decodeArray(source["nodes"], item => decodeJson(item)), "rules": decodeArray(source["rules"], item => decodeJson(item))};
    case "delete_task_graph": exactFields(source, ["op","graph_id"]); return {"op": "delete_task_graph", "graph_id": decodeNatural(source["graph_id"])};
    case "list_task_graphs": exactFields(source, ["op"]); return {"op": "list_task_graphs"};
    case "read_task_graph": exactFields(source, ["op","graph_id"]); return {"op": "read_task_graph", "graph_id": decodeNatural(source["graph_id"])};
    case "read_title_settings": exactFields(source, ["op"]); return {"op": "read_title_settings"};
    case "configure_title_settings": exactFields(source, ["op","revision","task_prompt","agent_prompt"]); return {"op": "configure_title_settings", "revision": decodeNatural(source["revision"]), "task_prompt": decodeText(source["task_prompt"]), "agent_prompt": decodeText(source["agent_prompt"])};
    case "create_work": exactFields(source, ["op","name"]); return {"op": "create_work", ...(source["name"] === undefined ? {} : {"name": decodeText(source["name"])})};
    case "rename_work": exactFields(source, ["op","work_id","name"]); return {"op": "rename_work", "work_id": decodeNatural(source["work_id"]), "name": decodeText(source["name"])};
    case "create_work_task": exactFields(source, ["op","work_id","profile","reasoning","message","images","settings","create_worktree"]); return {"op": "create_work_task", "work_id": decodeNatural(source["work_id"]), "profile": decodeText(source["profile"]), ...(source["reasoning"] === undefined ? {} : {"reasoning": decodeText(source["reasoning"])}), ...(source["message"] === undefined ? {} : {"message": decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": decodeArray(source["images"], item => decodeJson(item))}), ...(source["settings"] === undefined ? {} : {"settings": decodeJson(source["settings"])}), ...(source["create_worktree"] === undefined ? {} : {"create_worktree": decodeBoolean(source["create_worktree"])})};
    case "list_works": exactFields(source, ["op"]); return {"op": "list_works"};
    case "read_work": exactFields(source, ["op","work_id"]); return {"op": "read_work", "work_id": decodeNatural(source["work_id"])};
    case "read_work_ui": exactFields(source, ["op"]); return {"op": "read_work_ui"};
    case "apply_work_ui_patch": exactFields(source, ["op","patch","revision"]); return {"op": "apply_work_ui_patch", "patch": decodeText(source["patch"]), "revision": decodeNatural(source["revision"])};
    case "create_worktree_task": exactFields(source, ["op","profile","reasoning","message","images","settings"]); return {"op": "create_worktree_task", "profile": decodeText(source["profile"]), ...(source["reasoning"] === undefined ? {} : {"reasoning": decodeText(source["reasoning"])}), ...(source["message"] === undefined ? {} : {"message": decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": decodeArray(source["images"], item => decodeJson(item))}), ...(source["settings"] === undefined ? {} : {"settings": decodeJson(source["settings"])})};
    case "create_workspace_task": exactFields(source, ["op","backend","profile","reasoning","message","images","settings","work_id"]); return {"op": "create_workspace_task", "backend": decodeEnum6(source["backend"]), "profile": decodeText(source["profile"]), ...(source["reasoning"] === undefined ? {} : {"reasoning": decodeText(source["reasoning"])}), ...(source["message"] === undefined ? {} : {"message": decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": decodeArray(source["images"], item => decodeJson(item))}), ...(source["settings"] === undefined ? {} : {"settings": decodeJson(source["settings"])}), ...(source["work_id"] === undefined ? {} : {"work_id": decodeNatural(source["work_id"])})};
    case "list_worktrees": exactFields(source, ["op"]); return {"op": "list_worktrees"};
    case "read_worktree": exactFields(source, ["op","task_id"]); return {"op": "read_worktree", "task_id": decodeNatural(source["task_id"])};
    case "retry_worktree_archive": exactFields(source, ["op","task_id"]); return {"op": "retry_worktree_archive", "task_id": decodeNatural(source["task_id"])};
    case "resolve_workspace": exactFields(source, ["op","workspace","project_id"]); return {"op": "resolve_workspace", ...(source["workspace"] === undefined ? {} : {"workspace": source["workspace"] === null ? null : decodeJson(source["workspace"])}), ...(source["project_id"] === undefined ? {} : {"project_id": source["project_id"] === null ? null : decodeNatural(source["project_id"])})};
    // DEFENSE: External boundary values must name a declared Command variant.
    default: throw new TypeError('Unknown Command discriminant');
  }
}

export const commandOwners = {"configure_task_execution":"WorktreeChange","create":"WorktreeChange","create_idle":"WorktreeChange","send":"KernelChange","steer":"KernelChange","cancel_operation":"KernelChange","freeze":"KernelChange","unfreeze":"KernelChange","stop":"KernelChange","interrupt":"KernelChange","archive":"KernelChange","fork":"KernelChange","open_side_conversation":"KernelChange","return_side_conversation":"KernelChange","compact":"CompactionChange","read":"KernelQuery","search_history":"KernelQuery","list":"KernelQuery","describe":"KernelQuery","create_project":"KernelChange","update_project":"KernelChange","delete_project":"KernelChange","list_projects":"KernelQuery","read_project":"KernelQuery","review_approval":"KernelChange","record_speech_transcript":"KernelChange","accept_speech_delegation":"KernelChange","create_card":"BoardChange","update_card":"BoardChange","move_card":"BoardChange","archive_card":"BoardChange","restore_card":"BoardChange","delete_card":"BoardChange","run_card":"BoardChange","link_card":"BoardChange","regenerate_card_title":"BoardChange","pin_card":"BoardChange","board_settings":"BoardChange","save_board_agent":"BoardChange","delete_board_agent":"BoardChange","list_cards":"BoardQuery","read_card":"BoardQuery","list_board_agents":"BoardQuery","configure_chatgpt_connections":"ChatgptChange","chatgpt_exec":"ChatgptChange","chatgpt_cancel":"ChatgptChange","chatgpt_forget":"ChatgptChange","chatgpt_projects":"ChatgptQuery","chatgpt_project":"ChatgptQuery","chatgpt_operation":"ChatgptQuery","chatgpt_operations":"ChatgptQuery","remote_enable":"RemoteChange","remote_disable":"RemoteChange","remote_grant":"RemoteChange","remote_revoke":"RemoteChange","remote_status":"RemoteQuery","create_task_graph":"TaskGraphChange","update_task_graph":"TaskGraphChange","delete_task_graph":"TaskGraphChange","list_task_graphs":"TaskGraphQuery","read_task_graph":"TaskGraphQuery","read_title_settings":"TitleQuery","configure_title_settings":"TitleChange","create_work":"WorkChange","rename_work":"WorkChange","create_work_task":"WorktreeChange","list_works":"WorkQuery","read_work":"WorkQuery","read_work_ui":"WorkQuery","apply_work_ui_patch":"WorkChange","create_worktree_task":"WorktreeChange","create_workspace_task":"WorktreeChange","list_worktrees":"WorktreeQuery","read_worktree":"WorktreeQuery","retry_worktree_archive":"WorktreeChange","resolve_workspace":"WorktreeQuery"} satisfies Record<Command['op'], string>;

export const effectCallbacks = {"observe_context":"context_observed","model":"model","reasoning":"reasoning","tool":"tool","approval":"approval","hook":"hook","after_hook":"after_hook","plugin_events":null,"reset_model_session":null,"cancel":null,"cancel_ticket":null,"continue":null,"worktree_create":"worktree_created","worktree_archive":"worktree_archived","task_title":"task_title","board_text":"board_text","chatgpt_exec":"chatgpt_result","chatgpt_cancel":null,"context_scope":"compaction_measured","context_measure":"compaction_measured","context_compaction":"compaction_completed","compaction_clock":null,"compaction_cancel":null} satisfies Record<Effect['kind'], string | null>;
