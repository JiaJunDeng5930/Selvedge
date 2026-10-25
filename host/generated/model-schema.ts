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
function decodeEnum0(value: unknown): "TypeError" | "RangeError" {
 switch (value) { case "TypeError": return "TypeError"; case "RangeError": return "RangeError";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum1(value: unknown): "account_refresh" | "audio_create" | "audio_login" | "remote_pair" | "remote_enable" | "remote_disable" | "remote_approve" | "remote_revoke" | "browser_command" | "browser_observation" | "command" | "assess" | "connection_command" {
 switch (value) { case "account_refresh": return "account_refresh"; case "audio_create": return "audio_create"; case "audio_login": return "audio_login"; case "remote_pair": return "remote_pair"; case "remote_enable": return "remote_enable"; case "remote_disable": return "remote_disable"; case "remote_approve": return "remote_approve"; case "remote_revoke": return "remote_revoke"; case "browser_command": return "browser_command"; case "browser_observation": return "browser_observation"; case "command": return "command"; case "assess": return "assess"; case "connection_command": return "connection_command";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum2(value: unknown): "plain" | "interactive-v1" {
 switch (value) { case "plain": return "plain"; case "interactive-v1": return "interactive-v1";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum3(value: unknown): "local" | "tencent_cvm" {
 switch (value) { case "local": return "local"; case "tencent_cvm": return "tencent_cvm";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum4(value: unknown): "parent" | "environment" {
 switch (value) { case "parent": return "parent"; case "environment": return "environment";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum5(value: unknown): "allow" | "deny" {
 switch (value) { case "allow": return "allow"; case "deny": return "deny";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum6(value: unknown): "user" | "assistant" {
 switch (value) { case "user": return "user"; case "assistant": return "assistant";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum7(value: unknown): "completed" | "interrupted" {
 switch (value) { case "completed": return "completed"; case "interrupted": return "interrupted";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}

function decodeEnum8(value: unknown): "send" | "steer" {
 switch (value) { case "send": return "send"; case "steer": return "steer";
 // DEFENSE: A model enum must contain one of its declared wire values.
 default: throw new TypeError('Unknown model enum'); }
}
export function decodeHttpReplyStatus(input: unknown): number { return decodeSafeNatural(input); }
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
    case "throw": exactFields(source, ["action","kind","message"]); return {"action": "throw", "kind": decodeEnum0(source["kind"]), "message": decodeText(source["message"])};
    case "observe_content_type": exactFields(source, ["action","target"]); return {"action": "observe_content_type", "target": decodeEnum1(source["target"])};
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
  | {"kind": "cancel"; "generation": DomainNatural; "provider": boolean}
  | {"kind": "retry_failure"; }
  | {"kind": "settled"; }
  | {"kind": "retire"; };
export function decodeDispatchAction(input: unknown): DispatchAction {
  const source = decodeObject(input);
  switch (source["kind"]) {
    case "start": exactFields(source, ["kind","generation"]); return {"kind": "start", "generation": decodeNatural(source["generation"])};
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
  | {"type": "read"; "after": DomainNatural}
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
    case "read": exactFields(source, ["type","after"]); return {"type": "read", "after": decodeNatural(source["after"])};
    case "stop": exactFields(source, ["type"]); return {"type": "stop"};
    case "release": exactFields(source, ["type"]); return {"type": "release"};
    case "timer": exactFields(source, ["type"]); return {"type": "timer"};
    case "connect_timer": exactFields(source, ["type"]); return {"type": "connect_timer"};
    case "reject": exactFields(source, ["type","message"]); return {"type": "reject", "message": decodeText(source["message"])};
    // DEFENSE: External boundary values must name a declared AudioAction variant.
    default: throw new TypeError('Unknown AudioAction discriminant');
  }
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
  | {"kind": "approval"; "task_id": DomainNatural; "ticket": DomainNatural; "model": JsonValue; "settings": JsonValue; "call": JsonValue; "instructions": string; "user_requests": Array<string>}
  | {"kind": "hook"; "task_id": DomainNatural; "ticket": DomainNatural; "plugin": JsonValue; "tool": JsonValue; "call": JsonValue}
  | {"kind": "after_hook"; "task_id": DomainNatural; "ticket": DomainNatural; "operation_id": DomainNatural; "plugin": JsonValue; "call": JsonValue; "value": JsonValue; "error": boolean}
  | {"kind": "plugin_events"; "events": Array<JsonValue>}
  | {"kind": "reset_model_session"; "task_id": DomainNatural}
  | {"kind": "cancel"; "task_id": DomainNatural}
  | {"kind": "cancel_ticket"; "task_id": DomainNatural; "ticket": DomainNatural}
  | {"kind": "continue"; }
  | {"kind": "worktree_create"; "task_id": DomainNatural; "backend": "local" | "tencent_cvm"; "source_root": string; "workspace": JsonValue}
  | {"kind": "worktree_archive"; "task_id": DomainNatural; "backend": "local" | "tencent_cvm"; "source_root": string; "root": string}
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
    case "model": exactFields(source, ["kind","task_id","ticket","model","output_mode","settings","resource","sampling","history","context_selected","context_scope","context_replacement_source","output_reserve_tokens","source_length","tools","callable"]); return {"kind": "model", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"]), "output_mode": decodeEnum2(source["output_mode"]), "settings": decodeJson(source["settings"]), "resource": decodeJson(source["resource"]), "sampling": decodeJson(source["sampling"]), "history": decodeArray(source["history"], item => decodeJson(item)), "context_selected": decodeBoolean(source["context_selected"]), "context_scope": decodeText(source["context_scope"]), ...(source["context_replacement_source"] === undefined ? {} : {"context_replacement_source": source["context_replacement_source"] === null ? null : decodeNatural(source["context_replacement_source"])}), "output_reserve_tokens": decodeNatural(source["output_reserve_tokens"]), "source_length": decodeNatural(source["source_length"]), "tools": decodeArray(source["tools"], item => decodeJson(item)), "callable": decodeArray(source["callable"], item => decodeText(item))};
    case "reasoning": exactFields(source, ["kind","task_id","ticket","model","history","project_context","history_preview","history_preview_bytes"]); return {"kind": "reasoning", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"]), "history": decodeArray(source["history"], item => decodeJson(item)), "project_context": decodeJson(source["project_context"]), "history_preview": decodeBoolean(source["history_preview"]), "history_preview_bytes": decodeNatural(source["history_preview_bytes"])};
    case "tool": exactFields(source, ["kind","task_id","ticket","operation_id","tool","call","execution"]); return {"kind": "tool", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "operation_id": decodeNatural(source["operation_id"]), "tool": decodeJson(source["tool"]), "call": decodeJson(source["call"]), "execution": decodeJson(source["execution"])};
    case "approval": exactFields(source, ["kind","task_id","ticket","model","settings","call","instructions","user_requests"]); return {"kind": "approval", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "model": decodeJson(source["model"]), "settings": decodeJson(source["settings"]), "call": decodeJson(source["call"]), "instructions": decodeText(source["instructions"]), "user_requests": decodeArray(source["user_requests"], item => decodeText(item))};
    case "hook": exactFields(source, ["kind","task_id","ticket","plugin","tool","call"]); return {"kind": "hook", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "plugin": decodeJson(source["plugin"]), "tool": decodeJson(source["tool"]), "call": decodeJson(source["call"])};
    case "after_hook": exactFields(source, ["kind","task_id","ticket","operation_id","plugin","call","value","error"]); return {"kind": "after_hook", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"]), "operation_id": decodeNatural(source["operation_id"]), "plugin": decodeJson(source["plugin"]), "call": decodeJson(source["call"]), "value": decodeJson(source["value"]), "error": decodeBoolean(source["error"])};
    case "plugin_events": exactFields(source, ["kind","events"]); return {"kind": "plugin_events", "events": decodeArray(source["events"], item => decodeJson(item))};
    case "reset_model_session": exactFields(source, ["kind","task_id"]); return {"kind": "reset_model_session", "task_id": decodeNatural(source["task_id"])};
    case "cancel": exactFields(source, ["kind","task_id"]); return {"kind": "cancel", "task_id": decodeNatural(source["task_id"])};
    case "cancel_ticket": exactFields(source, ["kind","task_id","ticket"]); return {"kind": "cancel_ticket", "task_id": decodeNatural(source["task_id"]), "ticket": decodeNatural(source["ticket"])};
    case "continue": exactFields(source, ["kind"]); return {"kind": "continue"};
    case "worktree_create": exactFields(source, ["kind","task_id","backend","source_root","workspace"]); return {"kind": "worktree_create", "task_id": decodeNatural(source["task_id"]), "backend": decodeEnum3(source["backend"]), "source_root": decodeText(source["source_root"]), "workspace": decodeJson(source["workspace"])};
    case "worktree_archive": exactFields(source, ["kind","task_id","backend","source_root","root"]); return {"kind": "worktree_archive", "task_id": decodeNatural(source["task_id"]), "backend": decodeEnum3(source["backend"]), "source_root": decodeText(source["source_root"]), "root": decodeText(source["root"])};
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
  | {"op": "configure_task_execution"; "task_id": DomainNatural; "profile"?: string | null; "reasoning"?: string | null; "sandbox"?: JsonValue | null; "approval"?: JsonValue | null}
  | {"op": "create"; "profile": string; "reasoning"?: string | null; "message"?: JsonValue | null; "images"?: Array<JsonValue> | null; "settings"?: JsonValue | null}
  | {"op": "create_idle"; "profile": string; "reasoning"?: string | null; "settings"?: JsonValue | null; "work_id"?: DomainNatural | null; "create_worktree"?: boolean | null}
  | {"op": "send"; "task_id": DomainNatural; "message"?: JsonValue | null; "images"?: Array<JsonValue> | null}
  | {"op": "steer"; "task_id": DomainNatural; "message"?: JsonValue | null; "images"?: Array<JsonValue> | null}
  | {"op": "cancel_operation"; "task_id": DomainNatural; "operation_id": DomainNatural}
  | {"op": "freeze"; "task_id": DomainNatural}
  | {"op": "unfreeze"; "task_id": DomainNatural}
  | {"op": "stop"; "task_id": DomainNatural}
  | {"op": "interrupt"; "task_id": DomainNatural}
  | {"op": "archive"; "task_id": DomainNatural}
  | {"op": "fork"; "task_id": DomainNatural; "child_count": DomainNatural; "messages"?: Array<JsonValue> | null; "settings"?: JsonValue | null; "settings_origin"?: "parent" | "environment" | null}
  | {"op": "open_side_conversation"; "task_id": DomainNatural; "message"?: JsonValue | null; "images"?: Array<JsonValue> | null}
  | {"op": "return_side_conversation"; "task_id": DomainNatural}
  | {"op": "compact"; "task_id": DomainNatural; "summary"?: string | null}
  | {"op": "read"; "task_id": DomainNatural; "after"?: DomainNatural | null; "limit"?: DomainNatural | null}
  | {"op": "search_history"; "query": string; "project_id"?: DomainNatural | null; "work_id"?: DomainNatural | null; "after"?: DomainNatural | null; "limit"?: DomainNatural | null}
  | {"op": "list"; }
  | {"op": "describe"; }
  | {"op": "create_project"; "name": string; "workspace": JsonValue; "guidance"?: JsonValue | null; "create_worktree"?: boolean | null; "workspace_binding"?: JsonValue | null}
  | {"op": "update_project"; "project_id": DomainNatural; "name"?: string | null; "workspace"?: JsonValue | null; "guidance"?: JsonValue | null; "create_worktree"?: boolean | null; "workspace_binding"?: JsonValue | null}
  | {"op": "delete_project"; "project_id": DomainNatural}
  | {"op": "list_projects"; }
  | {"op": "read_project"; "project_id": DomainNatural}
  | {"op": "review_approval"; "task_id": DomainNatural; "operation_id": DomainNatural; "decision": "allow" | "deny"; "reason"?: string | null}
  | {"op": "record_speech_transcript"; "task_id": DomainNatural; "session_id": string; "item_id": string; "speaker": "user" | "assistant"; "completion": "completed" | "interrupted"; "text": string}
  | {"op": "accept_speech_delegation"; "task_id": DomainNatural; "session_id": string; "delegation_id": string; "message": string; "mode": "send" | "steer"}
  | {"op": "create_card"; "observed_at"?: string | null; "title"?: string; "description"?: string; "status"?: string; "priority"?: string; "assignee"?: string; "project"?: string; "labels"?: Array<string>; "attachments"?: Array<JsonValue>; "assisted"?: boolean | null; "draft_profile"?: string | null}
  | {"op": "update_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string | null; "title"?: string; "description"?: string; "status"?: string; "priority"?: string; "assignee"?: string; "project"?: string; "labels"?: Array<string>; "attachments"?: Array<JsonValue>}
  | {"op": "move_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string | null; "status"?: string | null; "before_card"?: string | null}
  | {"op": "archive_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string | null}
  | {"op": "restore_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string | null}
  | {"op": "delete_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string | null}
  | {"op": "run_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string | null}
  | {"op": "link_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string | null; "task_id"?: DomainNatural | null}
  | {"op": "regenerate_card_title"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string | null; "draft_profile"?: string | null}
  | {"op": "pin_card"; "card_id": DomainNatural; "revision": DomainNatural; "observed_at"?: string | null; "pinned"?: boolean | null}
  | {"op": "board_settings"; "automatic": boolean; "draft_profile": string}
  | {"op": "save_board_agent"; "agent": string; "revision": DomainNatural; "name": string; "profile": string; "reasoning": string; "instructions": string; "settings"?: JsonValue | null; "concurrency": DomainNatural}
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
  | {"op": "create_task_graph"; "work_id"?: DomainNatural | null; "name": string; "nodes": Array<JsonValue>; "rules": Array<JsonValue>}
  | {"op": "update_task_graph"; "graph_id": DomainNatural; "name": string; "nodes": Array<JsonValue>; "rules": Array<JsonValue>}
  | {"op": "delete_task_graph"; "graph_id": DomainNatural}
  | {"op": "list_task_graphs"; }
  | {"op": "read_task_graph"; "graph_id": DomainNatural}
  | {"op": "read_title_settings"; }
  | {"op": "configure_title_settings"; "revision": DomainNatural; "task_prompt": string; "agent_prompt": string}
  | {"op": "create_work"; "name"?: string | null}
  | {"op": "rename_work"; "work_id": DomainNatural; "name": string}
  | {"op": "create_work_task"; "work_id": DomainNatural; "profile": string; "reasoning"?: string | null; "message"?: JsonValue | null; "images"?: Array<JsonValue> | null; "settings"?: JsonValue | null; "create_worktree"?: boolean | null}
  | {"op": "list_works"; }
  | {"op": "read_work"; "work_id": DomainNatural}
  | {"op": "read_work_ui"; }
  | {"op": "apply_work_ui_patch"; "patch": string; "revision": DomainNatural}
  | {"op": "create_worktree_task"; "profile": string; "reasoning"?: string | null; "message"?: JsonValue | null; "images"?: Array<JsonValue> | null; "settings"?: JsonValue | null}
  | {"op": "create_workspace_task"; "backend": "local" | "tencent_cvm"; "profile": string; "reasoning"?: string | null; "message"?: JsonValue | null; "images"?: Array<JsonValue> | null; "settings"?: JsonValue | null; "work_id"?: DomainNatural | null}
  | {"op": "list_worktrees"; }
  | {"op": "read_worktree"; "task_id": DomainNatural}
  | {"op": "retry_worktree_archive"; "task_id": DomainNatural}
  | {"op": "resolve_workspace"; "workspace"?: JsonValue | null; "project_id"?: DomainNatural | null};
export function decodeCommand(input: unknown): Command {
  const source = decodeObject(input);
  switch (source["op"]) {
    case "configure_task_execution": exactFields(source, ["op","task_id","profile","reasoning","sandbox","approval"]); return {"op": "configure_task_execution", "task_id": decodeNatural(source["task_id"]), ...(source["profile"] === undefined ? {} : {"profile": source["profile"] === null ? null : decodeText(source["profile"])}), ...(source["reasoning"] === undefined ? {} : {"reasoning": source["reasoning"] === null ? null : decodeText(source["reasoning"])}), ...(source["sandbox"] === undefined ? {} : {"sandbox": source["sandbox"] === null ? null : decodeJson(source["sandbox"])}), ...(source["approval"] === undefined ? {} : {"approval": source["approval"] === null ? null : decodeJson(source["approval"])})};
    case "create": exactFields(source, ["op","profile","reasoning","message","images","settings"]); return {"op": "create", "profile": decodeText(source["profile"]), ...(source["reasoning"] === undefined ? {} : {"reasoning": source["reasoning"] === null ? null : decodeText(source["reasoning"])}), ...(source["message"] === undefined ? {} : {"message": source["message"] === null ? null : decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": source["images"] === null ? null : decodeArray(source["images"], item => decodeJson(item))}), ...(source["settings"] === undefined ? {} : {"settings": source["settings"] === null ? null : decodeJson(source["settings"])})};
    case "create_idle": exactFields(source, ["op","profile","reasoning","settings","work_id","create_worktree"]); return {"op": "create_idle", "profile": decodeText(source["profile"]), ...(source["reasoning"] === undefined ? {} : {"reasoning": source["reasoning"] === null ? null : decodeText(source["reasoning"])}), ...(source["settings"] === undefined ? {} : {"settings": source["settings"] === null ? null : decodeJson(source["settings"])}), ...(source["work_id"] === undefined ? {} : {"work_id": source["work_id"] === null ? null : decodeNatural(source["work_id"])}), ...(source["create_worktree"] === undefined ? {} : {"create_worktree": source["create_worktree"] === null ? null : decodeBoolean(source["create_worktree"])})};
    case "send": exactFields(source, ["op","task_id","message","images"]); return {"op": "send", "task_id": decodeNatural(source["task_id"]), ...(source["message"] === undefined ? {} : {"message": source["message"] === null ? null : decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": source["images"] === null ? null : decodeArray(source["images"], item => decodeJson(item))})};
    case "steer": exactFields(source, ["op","task_id","message","images"]); return {"op": "steer", "task_id": decodeNatural(source["task_id"]), ...(source["message"] === undefined ? {} : {"message": source["message"] === null ? null : decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": source["images"] === null ? null : decodeArray(source["images"], item => decodeJson(item))})};
    case "cancel_operation": exactFields(source, ["op","task_id","operation_id"]); return {"op": "cancel_operation", "task_id": decodeNatural(source["task_id"]), "operation_id": decodeNatural(source["operation_id"])};
    case "freeze": exactFields(source, ["op","task_id"]); return {"op": "freeze", "task_id": decodeNatural(source["task_id"])};
    case "unfreeze": exactFields(source, ["op","task_id"]); return {"op": "unfreeze", "task_id": decodeNatural(source["task_id"])};
    case "stop": exactFields(source, ["op","task_id"]); return {"op": "stop", "task_id": decodeNatural(source["task_id"])};
    case "interrupt": exactFields(source, ["op","task_id"]); return {"op": "interrupt", "task_id": decodeNatural(source["task_id"])};
    case "archive": exactFields(source, ["op","task_id"]); return {"op": "archive", "task_id": decodeNatural(source["task_id"])};
    case "fork": exactFields(source, ["op","task_id","child_count","messages","settings","settings_origin"]); return {"op": "fork", "task_id": decodeNatural(source["task_id"]), "child_count": decodeNatural(source["child_count"]), ...(source["messages"] === undefined ? {} : {"messages": source["messages"] === null ? null : decodeArray(source["messages"], item => decodeJson(item))}), ...(source["settings"] === undefined ? {} : {"settings": source["settings"] === null ? null : decodeJson(source["settings"])}), ...(source["settings_origin"] === undefined ? {} : {"settings_origin": source["settings_origin"] === null ? null : decodeEnum4(source["settings_origin"])})};
    case "open_side_conversation": exactFields(source, ["op","task_id","message","images"]); return {"op": "open_side_conversation", "task_id": decodeNatural(source["task_id"]), ...(source["message"] === undefined ? {} : {"message": source["message"] === null ? null : decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": source["images"] === null ? null : decodeArray(source["images"], item => decodeJson(item))})};
    case "return_side_conversation": exactFields(source, ["op","task_id"]); return {"op": "return_side_conversation", "task_id": decodeNatural(source["task_id"])};
    case "compact": exactFields(source, ["op","task_id","summary"]); return {"op": "compact", "task_id": decodeNatural(source["task_id"]), ...(source["summary"] === undefined ? {} : {"summary": source["summary"] === null ? null : decodeText(source["summary"])})};
    case "read": exactFields(source, ["op","task_id","after","limit"]); return {"op": "read", "task_id": decodeNatural(source["task_id"]), ...(source["after"] === undefined ? {} : {"after": source["after"] === null ? null : decodeNatural(source["after"])}), ...(source["limit"] === undefined ? {} : {"limit": source["limit"] === null ? null : decodeNatural(source["limit"])})};
    case "search_history": exactFields(source, ["op","query","project_id","work_id","after","limit"]); return {"op": "search_history", "query": decodeText(source["query"]), ...(source["project_id"] === undefined ? {} : {"project_id": source["project_id"] === null ? null : decodeNatural(source["project_id"])}), ...(source["work_id"] === undefined ? {} : {"work_id": source["work_id"] === null ? null : decodeNatural(source["work_id"])}), ...(source["after"] === undefined ? {} : {"after": source["after"] === null ? null : decodeNatural(source["after"])}), ...(source["limit"] === undefined ? {} : {"limit": source["limit"] === null ? null : decodeNatural(source["limit"])})};
    case "list": exactFields(source, ["op"]); return {"op": "list"};
    case "describe": exactFields(source, ["op"]); return {"op": "describe"};
    case "create_project": exactFields(source, ["op","name","workspace","guidance","create_worktree","workspace_binding"]); return {"op": "create_project", "name": decodeText(source["name"]), "workspace": decodeJson(source["workspace"]), ...(source["guidance"] === undefined ? {} : {"guidance": source["guidance"] === null ? null : decodeJson(source["guidance"])}), ...(source["create_worktree"] === undefined ? {} : {"create_worktree": source["create_worktree"] === null ? null : decodeBoolean(source["create_worktree"])}), ...(source["workspace_binding"] === undefined ? {} : {"workspace_binding": source["workspace_binding"] === null ? null : decodeJson(source["workspace_binding"])})};
    case "update_project": exactFields(source, ["op","project_id","name","workspace","guidance","create_worktree","workspace_binding"]); return {"op": "update_project", "project_id": decodeNatural(source["project_id"]), ...(source["name"] === undefined ? {} : {"name": source["name"] === null ? null : decodeText(source["name"])}), ...(source["workspace"] === undefined ? {} : {"workspace": source["workspace"] === null ? null : decodeJson(source["workspace"])}), ...(source["guidance"] === undefined ? {} : {"guidance": source["guidance"] === null ? null : decodeJson(source["guidance"])}), ...(source["create_worktree"] === undefined ? {} : {"create_worktree": source["create_worktree"] === null ? null : decodeBoolean(source["create_worktree"])}), ...(source["workspace_binding"] === undefined ? {} : {"workspace_binding": source["workspace_binding"] === null ? null : decodeJson(source["workspace_binding"])})};
    case "delete_project": exactFields(source, ["op","project_id"]); return {"op": "delete_project", "project_id": decodeNatural(source["project_id"])};
    case "list_projects": exactFields(source, ["op"]); return {"op": "list_projects"};
    case "read_project": exactFields(source, ["op","project_id"]); return {"op": "read_project", "project_id": decodeNatural(source["project_id"])};
    case "review_approval": exactFields(source, ["op","task_id","operation_id","decision","reason"]); return {"op": "review_approval", "task_id": decodeNatural(source["task_id"]), "operation_id": decodeNatural(source["operation_id"]), "decision": decodeEnum5(source["decision"]), ...(source["reason"] === undefined ? {} : {"reason": source["reason"] === null ? null : decodeText(source["reason"])})};
    case "record_speech_transcript": exactFields(source, ["op","task_id","session_id","item_id","speaker","completion","text"]); return {"op": "record_speech_transcript", "task_id": decodeNatural(source["task_id"]), "session_id": decodeText(source["session_id"]), "item_id": decodeText(source["item_id"]), "speaker": decodeEnum6(source["speaker"]), "completion": decodeEnum7(source["completion"]), "text": decodeText(source["text"])};
    case "accept_speech_delegation": exactFields(source, ["op","task_id","session_id","delegation_id","message","mode"]); return {"op": "accept_speech_delegation", "task_id": decodeNatural(source["task_id"]), "session_id": decodeText(source["session_id"]), "delegation_id": decodeText(source["delegation_id"]), "message": decodeText(source["message"]), "mode": decodeEnum8(source["mode"])};
    case "create_card": exactFields(source, ["op","observed_at","title","description","status","priority","assignee","project","labels","attachments","assisted","draft_profile"]); return {"op": "create_card", ...(source["observed_at"] === undefined ? {} : {"observed_at": source["observed_at"] === null ? null : decodeText(source["observed_at"])}), ...(source["title"] === undefined ? {} : {"title": decodeText(source["title"])}), ...(source["description"] === undefined ? {} : {"description": decodeText(source["description"])}), ...(source["status"] === undefined ? {} : {"status": decodeText(source["status"])}), ...(source["priority"] === undefined ? {} : {"priority": decodeText(source["priority"])}), ...(source["assignee"] === undefined ? {} : {"assignee": decodeText(source["assignee"])}), ...(source["project"] === undefined ? {} : {"project": decodeText(source["project"])}), ...(source["labels"] === undefined ? {} : {"labels": decodeArray(source["labels"], item => decodeText(item))}), ...(source["attachments"] === undefined ? {} : {"attachments": decodeArray(source["attachments"], item => decodeJson(item))}), ...(source["assisted"] === undefined ? {} : {"assisted": source["assisted"] === null ? null : decodeBoolean(source["assisted"])}), ...(source["draft_profile"] === undefined ? {} : {"draft_profile": source["draft_profile"] === null ? null : decodeText(source["draft_profile"])})};
    case "update_card": exactFields(source, ["op","card_id","revision","observed_at","title","description","status","priority","assignee","project","labels","attachments"]); return {"op": "update_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": source["observed_at"] === null ? null : decodeText(source["observed_at"])}), ...(source["title"] === undefined ? {} : {"title": decodeText(source["title"])}), ...(source["description"] === undefined ? {} : {"description": decodeText(source["description"])}), ...(source["status"] === undefined ? {} : {"status": decodeText(source["status"])}), ...(source["priority"] === undefined ? {} : {"priority": decodeText(source["priority"])}), ...(source["assignee"] === undefined ? {} : {"assignee": decodeText(source["assignee"])}), ...(source["project"] === undefined ? {} : {"project": decodeText(source["project"])}), ...(source["labels"] === undefined ? {} : {"labels": decodeArray(source["labels"], item => decodeText(item))}), ...(source["attachments"] === undefined ? {} : {"attachments": decodeArray(source["attachments"], item => decodeJson(item))})};
    case "move_card": exactFields(source, ["op","card_id","revision","observed_at","status","before_card"]); return {"op": "move_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": source["observed_at"] === null ? null : decodeText(source["observed_at"])}), ...(source["status"] === undefined ? {} : {"status": source["status"] === null ? null : decodeText(source["status"])}), ...(source["before_card"] === undefined ? {} : {"before_card": source["before_card"] === null ? null : decodeText(source["before_card"])})};
    case "archive_card": exactFields(source, ["op","card_id","revision","observed_at"]); return {"op": "archive_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": source["observed_at"] === null ? null : decodeText(source["observed_at"])})};
    case "restore_card": exactFields(source, ["op","card_id","revision","observed_at"]); return {"op": "restore_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": source["observed_at"] === null ? null : decodeText(source["observed_at"])})};
    case "delete_card": exactFields(source, ["op","card_id","revision","observed_at"]); return {"op": "delete_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": source["observed_at"] === null ? null : decodeText(source["observed_at"])})};
    case "run_card": exactFields(source, ["op","card_id","revision","observed_at"]); return {"op": "run_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": source["observed_at"] === null ? null : decodeText(source["observed_at"])})};
    case "link_card": exactFields(source, ["op","card_id","revision","observed_at","task_id"]); return {"op": "link_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": source["observed_at"] === null ? null : decodeText(source["observed_at"])}), ...(source["task_id"] === undefined ? {} : {"task_id": source["task_id"] === null ? null : decodeNatural(source["task_id"])})};
    case "regenerate_card_title": exactFields(source, ["op","card_id","revision","observed_at","draft_profile"]); return {"op": "regenerate_card_title", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": source["observed_at"] === null ? null : decodeText(source["observed_at"])}), ...(source["draft_profile"] === undefined ? {} : {"draft_profile": source["draft_profile"] === null ? null : decodeText(source["draft_profile"])})};
    case "pin_card": exactFields(source, ["op","card_id","revision","observed_at","pinned"]); return {"op": "pin_card", "card_id": decodeNatural(source["card_id"]), "revision": decodeNatural(source["revision"]), ...(source["observed_at"] === undefined ? {} : {"observed_at": source["observed_at"] === null ? null : decodeText(source["observed_at"])}), ...(source["pinned"] === undefined ? {} : {"pinned": source["pinned"] === null ? null : decodeBoolean(source["pinned"])})};
    case "board_settings": exactFields(source, ["op","automatic","draft_profile"]); return {"op": "board_settings", "automatic": decodeBoolean(source["automatic"]), "draft_profile": decodeText(source["draft_profile"])};
    case "save_board_agent": exactFields(source, ["op","agent","revision","name","profile","reasoning","instructions","settings","concurrency"]); return {"op": "save_board_agent", "agent": decodeText(source["agent"]), "revision": decodeNatural(source["revision"]), "name": decodeText(source["name"]), "profile": decodeText(source["profile"]), "reasoning": decodeText(source["reasoning"]), "instructions": decodeText(source["instructions"]), ...(source["settings"] === undefined ? {} : {"settings": source["settings"] === null ? null : decodeJson(source["settings"])}), "concurrency": decodeNatural(source["concurrency"])};
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
    case "create_task_graph": exactFields(source, ["op","work_id","name","nodes","rules"]); return {"op": "create_task_graph", ...(source["work_id"] === undefined ? {} : {"work_id": source["work_id"] === null ? null : decodeNatural(source["work_id"])}), "name": decodeText(source["name"]), "nodes": decodeArray(source["nodes"], item => decodeJson(item)), "rules": decodeArray(source["rules"], item => decodeJson(item))};
    case "update_task_graph": exactFields(source, ["op","graph_id","name","nodes","rules"]); return {"op": "update_task_graph", "graph_id": decodeNatural(source["graph_id"]), "name": decodeText(source["name"]), "nodes": decodeArray(source["nodes"], item => decodeJson(item)), "rules": decodeArray(source["rules"], item => decodeJson(item))};
    case "delete_task_graph": exactFields(source, ["op","graph_id"]); return {"op": "delete_task_graph", "graph_id": decodeNatural(source["graph_id"])};
    case "list_task_graphs": exactFields(source, ["op"]); return {"op": "list_task_graphs"};
    case "read_task_graph": exactFields(source, ["op","graph_id"]); return {"op": "read_task_graph", "graph_id": decodeNatural(source["graph_id"])};
    case "read_title_settings": exactFields(source, ["op"]); return {"op": "read_title_settings"};
    case "configure_title_settings": exactFields(source, ["op","revision","task_prompt","agent_prompt"]); return {"op": "configure_title_settings", "revision": decodeNatural(source["revision"]), "task_prompt": decodeText(source["task_prompt"]), "agent_prompt": decodeText(source["agent_prompt"])};
    case "create_work": exactFields(source, ["op","name"]); return {"op": "create_work", ...(source["name"] === undefined ? {} : {"name": source["name"] === null ? null : decodeText(source["name"])})};
    case "rename_work": exactFields(source, ["op","work_id","name"]); return {"op": "rename_work", "work_id": decodeNatural(source["work_id"]), "name": decodeText(source["name"])};
    case "create_work_task": exactFields(source, ["op","work_id","profile","reasoning","message","images","settings","create_worktree"]); return {"op": "create_work_task", "work_id": decodeNatural(source["work_id"]), "profile": decodeText(source["profile"]), ...(source["reasoning"] === undefined ? {} : {"reasoning": source["reasoning"] === null ? null : decodeText(source["reasoning"])}), ...(source["message"] === undefined ? {} : {"message": source["message"] === null ? null : decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": source["images"] === null ? null : decodeArray(source["images"], item => decodeJson(item))}), ...(source["settings"] === undefined ? {} : {"settings": source["settings"] === null ? null : decodeJson(source["settings"])}), ...(source["create_worktree"] === undefined ? {} : {"create_worktree": source["create_worktree"] === null ? null : decodeBoolean(source["create_worktree"])})};
    case "list_works": exactFields(source, ["op"]); return {"op": "list_works"};
    case "read_work": exactFields(source, ["op","work_id"]); return {"op": "read_work", "work_id": decodeNatural(source["work_id"])};
    case "read_work_ui": exactFields(source, ["op"]); return {"op": "read_work_ui"};
    case "apply_work_ui_patch": exactFields(source, ["op","patch","revision"]); return {"op": "apply_work_ui_patch", "patch": decodeText(source["patch"]), "revision": decodeNatural(source["revision"])};
    case "create_worktree_task": exactFields(source, ["op","profile","reasoning","message","images","settings"]); return {"op": "create_worktree_task", "profile": decodeText(source["profile"]), ...(source["reasoning"] === undefined ? {} : {"reasoning": source["reasoning"] === null ? null : decodeText(source["reasoning"])}), ...(source["message"] === undefined ? {} : {"message": source["message"] === null ? null : decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": source["images"] === null ? null : decodeArray(source["images"], item => decodeJson(item))}), ...(source["settings"] === undefined ? {} : {"settings": source["settings"] === null ? null : decodeJson(source["settings"])})};
    case "create_workspace_task": exactFields(source, ["op","backend","profile","reasoning","message","images","settings","work_id"]); return {"op": "create_workspace_task", "backend": decodeEnum3(source["backend"]), "profile": decodeText(source["profile"]), ...(source["reasoning"] === undefined ? {} : {"reasoning": source["reasoning"] === null ? null : decodeText(source["reasoning"])}), ...(source["message"] === undefined ? {} : {"message": source["message"] === null ? null : decodeJson(source["message"])}), ...(source["images"] === undefined ? {} : {"images": source["images"] === null ? null : decodeArray(source["images"], item => decodeJson(item))}), ...(source["settings"] === undefined ? {} : {"settings": source["settings"] === null ? null : decodeJson(source["settings"])}), ...(source["work_id"] === undefined ? {} : {"work_id": source["work_id"] === null ? null : decodeNatural(source["work_id"])})};
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
