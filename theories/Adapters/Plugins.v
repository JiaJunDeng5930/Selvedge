From Selvedge.Programming Require Callback.
From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require Import CallWire Json Utf8 TextJson.
From Selvedge.Kernel Require Import ChatgptProtocol ChatgptArguments.
From Selvedge.Kernel Require CallbackDeclarations.
Module CD := CallbackDeclarations.
From Selvedge.Adapters Require Import Common Observation PluginConnections PluginCatalog Attachments.
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
Definition callback_request effect (after : bool) := JObject (map (fun key => (key,if String.eqb key "call" then CallWire.external (get effect key) else get effect key))
  (if after then ["task_id";"operation_id";"ticket";"plugin";"call";"value";"error"] else ["task_id";"ticket";"plugin";"tool";"call"])).
Definition hook_request source (after : bool) := let effect := get source "effect" in
  if matching (get effect "plugin") (get source "reference") && boolean_field (get source "descriptor") (if after then "after_tool" else "before_tool")
  then success (callback_request effect after) else err "Required plugin revision is unavailable".
Definition call_request source := let effect := get source "effect" in let tool_source := get (get effect "tool") "source" in
  if matching (get tool_source "plugin") (get source "reference") then success (JObject [("name",get tool_source "name");
    ("arguments",get (CallWire.external (get effect "call")) "arguments");("context",JObject [("task_id",get effect "task_id");
      ("operation_id",get effect "ticket");("call_id",get (get effect "call") "id")])]) else err "Plugin tool revision is unavailable".
(** Plugins choose allow, rewrite or deny; transport failures are emitted by the host. *)
Definition external_hook_choice {Allow Rewrite Failure : Set}
 (value : (Allow + (Rewrite + (D.denote (CD.reason "deny" (Callback.diagnostic_text ModelDeclarations.Hook)) + Failure)))%type) :=
 match value with
 | inl _ | inr (inl _) => true
 | inr (inr (inl reason)) => Utf8.nonblank (proj1_sig (fst (snd (proj1_sig reason))))
 | inr (inr (inr _)) => false end.
Definition hook_result source (after : bool) :=
 let description := if after then CD.after_schema else CD.hook_schema in
 let invalid := type_error (if after then "Plugin returned an invalid result decision" else "Plugin returned an invalid hook decision") in
 match D.decode description (get source "outcome") with
 | Some outcome =>
   if (if after as mode return D.denote (if mode then CD.after_schema else CD.hook_schema) -> bool
       then external_hook_choice else external_hook_choice) outcome
   then success (D.encode description outcome)
   else invalid
 | None => invalid end.
Definition call_result_declaration := D.Object [F.required "value" D.Any;F.required "error" (D.Value Schema.KBool)].
Definition call_result source := match D.decode call_result_declaration (get source "result") with
 | Some value => success (D.encode call_result_declaration value)
 | None => type_error "Plugin returned an invalid tool result" end.
Definition mcp_result source := let value := get source "result" in
  if is_object value then success (JObject [("value",value);("error",JBool (boolean_field value "isError"))])
  else err "MCP returned a malformed tool result".
Definition mcp_media_part (part observation : json) :=
  if String.eqb (str part "type") "image" then
    is_text (get part "data") && boolean_field observation "canonical" &&
    bound (get observation "bytes") 1 Images.image_byte_limit &&
    existsb (String.eqb (str (attachment_media_type observation) "value")) Images.mime_types
  else true.
Definition mcp_media_pairs source := combine (items (get (get source "result") "content")) (items (get source "observations")).
Definition mcp_media_images source := filter (fun pair => String.eqb (str (fst (snd pair)) "type") "image")
  (combine (seq 0 (List.length (items (get (get source "result") "content")))) (mcp_media_pairs source)).
Definition mcp_media_bytes source := fold_left (fun total pair => total + num (snd (snd pair)) "bytes") (mcp_media_images source) 0.
Definition mcp_media_admitted source :=
  Nat.eqb (List.length (items (get (get source "result") "content"))) (List.length (items (get source "observations"))) &&
  forallb (fun pair => mcp_media_part (fst pair) (snd pair)) (mcp_media_pairs source) &&
  (mcp_media_bytes source <=? num source "maximum").
Definition mcp_media_plan source :=
  if negb (is_object (get source "result")) then err "MCP returned a malformed tool result"
  else if mcp_media_admitted source
  then success (JObject [("indices",JArray (map (fun pair => number (N.of_nat (fst pair))) (mcp_media_images source)));
    ("bytes",number (mcp_media_bytes source))])
  else type_error "MCP image content must use canonical base64, supported image bytes and the response byte budget".
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
 ("plugin.mcp_media_plan",mcp_media_plan);
 ("plugin.tools",fun _ => success tools);("plugin.instructions",fun _ => success instructions);
 ("plugin.connection_failure",fun _ => connection_failure);("plugin.http_response",http_response)].
Definition call operation source := match find (fun handler => String.eqb operation (fst handler)) handlers with
  | Some (_,handler) => handler source | None => err ("Unknown plugin model operation: " ++ operation) end.
