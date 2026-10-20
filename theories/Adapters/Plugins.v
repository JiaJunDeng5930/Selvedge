From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import Json Utf8 TextJson.
From Selvedge.Kernel Require Import ChatgptProtocol ChatgptArguments.
From Selvedge.Adapters Require Import Common Observation PluginConnections PluginCatalog.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition command_value connection route args :=
  JObject (("op",JString (native_name route))::("connection_id",connection)::
    match route with Execute => [("project_id",get args "project_id");("request_id",get args "request_id");
      ("arguments",JObject [("command",get args "command");("timeout_ms",default_value (get args "timeout_ms") (number ChatgptArguments.default_timeout_ms));
        ("max_output_length",default_value (get args "max_output_length") (number ChatgptArguments.default_max_output_length))])]
    | _ => object_fields args end).
Definition command source := let body := get source "body" in
  if negb (keys body ["tool";"arguments"]) then type_error "Invalid ChatGPT tool envelope" else
  match find_route (str body "tool") with None => type_error "Unknown ChatGPT tool"
  | Some route => if keys (get body "arguments") (client_keys route)
    then success (command_value (get source "connection") route (get body "arguments"))
    else type_error "Invalid ChatGPT tool arguments" end.
Definition callback_request effect (after : bool) := JObject (map (fun key => (key,get effect key))
  (if after then ["task_id";"operation_id";"ticket";"plugin";"call";"value";"error"] else ["task_id";"ticket";"plugin";"tool";"call"])).
Definition hook_request source (after : bool) := let effect := get source "effect" in
  if matching (get effect "plugin") (get source "reference") && boolean_field (get source "descriptor") (if after then "after_tool" else "before_tool")
  then success (callback_request effect after) else err "Required plugin revision is unavailable".
Definition call_request source := let effect := get source "effect" in let tool_source := get (get effect "tool") "source" in
  if matching (get tool_source "plugin") (get source "reference") then success (JObject [("name",get tool_source "name");
    ("arguments",get (get effect "call") "arguments");("context",JObject [("task_id",get effect "task_id");
      ("operation_id",get effect "ticket");("call_id",get (get effect "call") "id")])]) else err "Plugin tool revision is unavailable".
Definition hook_valid outcome (after : bool) :=
  if String.eqb (str outcome "decision") "allow" then exact_fields ["decision"] outcome
  else if String.eqb (str outcome "decision") "rewrite" then
    if after then exact_fields ["decision";"value"] outcome else exact_fields ["decision";"arguments"] outcome && is_object (get outcome "arguments")
  else if String.eqb (str outcome "decision") "deny" then exact_fields ["decision";"reason"] outcome &&
    Utf8.nonblank (str outcome "reason") && (N.of_nat (String.length (str outcome "reason")) <=? 4096)
  else false.
Definition hook_result source (after : bool) := let outcome := get source "outcome" in
  if hook_valid outcome after then success outcome
  else type_error (if after then "Plugin returned an invalid result decision" else "Plugin returned an invalid hook decision").
Definition call_result source := let value := get source "result" in
  if keys value ["value";"error"] && has value "value" && is_bool (get value "error") then success value
  else type_error "Plugin returned an invalid tool result".
Definition mcp_result source := let value := get source "result" in
  if is_object value then success (JObject [("value",value);("error",JBool (boolean_field value "isError"))])
  else err "MCP returned a malformed tool result".
Definition client_info := JObject [("name",JString "selvedge-rocq");("version",JString "0.1.0")].
Definition initialize_request source := let definition := get source "definition" in let limits := get source "limits" in
  JObject [("protocolVersion",get definition "protocolVersion");("clientInfo",client_info);("workspace",get source "workspace");
    ("events",get definition "events");("limits",JObject [("frame_bytes",get limits "frame_bytes");("catalog_tools",get limits "plugin_catalog_tools")])].
Definition mcp_initialize_request := JObject [("protocolVersion",JString "2025-11-25");("capabilities",JObject []);("clientInfo",client_info)].
Definition mcp_version source := if existsb (String.eqb (str (get source "initialized") "protocolVersion"))
  ["2024-11-05";"2025-03-26";"2025-06-18";"2025-11-25"] then success JNull else err "MCP server selected an unsupported protocol version".
Definition enqueue_stopped source := [("accepted",JBool false);("next_queued_bytes",get source "queued_bytes");
  ("next_queue_count",get source "queue_count");("append",JArray [])].
Definition enqueue source :=
  if boolean_field source "stopping" then success (JObject (enqueue_stopped source)) else
  let maximum := nat_value (default_value (get (get source "config") "event_queue") (get (get source "limits") "plugin_event_queue")) in
  let next_bytes := num source "queued_bytes" + num source "event_bytes" in
  if (maximum <=? num source "queue_count") || negb (next_bytes <=? 2 * num (get source "limits") "frame_bytes") then
    success (JObject (enqueue_stopped source ++ [("diagnostic",JObject [("message",JString ("Plugin " ++ str source "name" ++ " event queue is full; notification was not delivered"));
      ("event_id",JObject [("sequence",get (get source "event") "sequence");("ordinal",get (get source "event") "ordinal")])])]))
  else success (JObject [("accepted",JBool true);("next_queued_bytes",number next_bytes);("next_queue_count",number (num source "queue_count" + 1));
    ("append",JArray [JObject [("event",get source "event");("bytes",get source "event_bytes")]])]).
Definition response_content value error := success (JObject [("content",JArray [JObject [("type",JString "text");("text",JString (render_json value))]]);
  ("structuredContent",value);("isError",JBool error)]).
Definition connection_failure := response_content (JObject [("error",JObject [("code",JString "connection_failed");
  ("message",JString "The Selvedge connection failed. An accepted operation may still be running. Reconnect and query the operation, or retry exec with the identical request_id and arguments; do not invent a new ID.")])]) true.
Definition receipt_shape value := is_object value && has value "value" && is_bool (get value "error").
Definition reply_result_shape route value := match route with
  | Projects | Operations => is_array value | Project => is_object value
  | Operation | Execute | Cancel => receipt_shape value
  | Forget => is_object value && uint32 (get value "operation_id") end.
Definition reply_valid route reply := is_object reply && is_bool (get reply "ok") &&
  if boolean_field reply "ok" then keys reply ["ok";"result";"sequence"] && has reply "result" && reply_result_shape route (get reply "result")
  else keys reply ["ok";"error";"sequence"] && keys (get reply "error") ["code";"message"] &&
    Utf8.nonblank (str (get reply "error") "code") && is_text (get (get reply "error") "message").
Definition receipt_error route reply := if negb (boolean_field reply "ok") then true else
  match route with Operation | Execute | Cancel => boolean_field (get reply "result") "error" | _ => false end.
Fixpoint lowercase value := match value with EmptyString => EmptyString | String ch rest =>
  let code := nat_of_ascii ch in String (if Nat.leb 65 code && Nat.leb code 90 then ascii_of_nat (code + 32)%nat else ch) (lowercase rest) end.
Definition http_response source := let content_type := lowercase (str source "content_type") in
  if negb (String.eqb content_type "application/json" || starts content_type "application/json;") then err "Selvedge returned a non-JSON response"
  else match parse_json (str source "text"),find_route (str source "tool") with
  | Some reply,Some route =>
    if boolean_field reply "ok" && (300 <=? num source "status") then err ("Selvedge returned HTTP " ++ str source "status_text")
    else if reply_valid route reply then response_content (JObject [(if boolean_field reply "ok" then "result" else "error",
      get reply (if boolean_field reply "ok" then "result" else "error"))]) (receipt_error route reply)
    else err "Malformed Selvedge response"
  | _,_ => err "Malformed Selvedge response" end.

Definition handlers : list (string * (json -> json)) := [
 ("plugin.command",command);("plugin.connection_config",connection_config);("plugin.connection_grants",connection_grants);
 ("plugin.credential_plan",fun _ => success credential_plan);("plugin.client_settings",client_settings);("plugin.settings_file",settings_file);
 ("plugin.valid_name",fun s => success (JBool (valid_name (str s "name"))));
 ("plugin.matches",fun s => success (JBool (matching (get s "reference") (get s "expected"))));
 ("plugin.enqueue",enqueue);("plugin.initialize_request",fun s => success (initialize_request s));
 ("plugin.mcp_initialize_request",fun _ => success mcp_initialize_request);
 ("plugin.mcp_call_request",fun s => success (JObject [("name",get s "name");("arguments",get s "arguments")]));
 ("plugin.manifest",manifest);("plugin.before_request",fun s => hook_request s false);("plugin.after_request",fun s => hook_request s true);
 ("plugin.call_request",call_request);("plugin.before_result",fun s => hook_result s false);("plugin.after_result",fun s => hook_result s true);
 ("plugin.call_result",call_result);("plugin.mcp_result",mcp_result);("plugin.mcp_page",mcp_page);("plugin.mcp_version",mcp_version);
 ("plugin.tools",fun _ => success tools);("plugin.instructions",fun _ => success instructions);
 ("plugin.connection_failure",fun _ => connection_failure);("plugin.http_response",http_response)].
Definition call operation source := match find (fun handler => String.eqb operation (fst handler)) handlers with
  | Some (_,handler) => handler source | None => err ("Unknown plugin model operation: " ++ operation) end.
