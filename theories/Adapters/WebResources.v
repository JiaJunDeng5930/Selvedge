From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Adapters Require Export WebCommon.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Inductive response_status := InProgress | RequiresAction | Completed | Interrupted | ResponseCancelled.
Definition parse_status value := match value with
  | "in_progress" => Some InProgress | "requires_action" => Some RequiresAction
  | "completed" => Some Completed | "interrupted" => Some Interrupted
  | "cancelled" => Some ResponseCancelled | _ => None end.
Definition resource_identity value :=
  nonempty (member value "id") && String.eqb (member_text value "object") "web.response" &&
  String.eqb (member_text value "protocol") "chatgpt-web.v1" && natural (member value "created_at") &&
  is_array (member value "output") && match parse_status (member_text value "status") with Some _ => true | None => false end.
Definition same_model_request value model body :=
  same (member value "model") model && D.present (Json.lookup "previous_response_id" value) &&
  same (member value "previous_response_id") (get body "previous_response_id").
Definition output_text parts := forallb (fun part => eq part "type" "output_text" && is_text (get part "text")) parts.
Definition assistant_output values := match values with
  | [item] => eq item "type" "message" && eq item "role" "assistant" &&
    is_array (get item "content") && negb (Nat.eqb (List.length (items (get item "content"))) 0) &&
    output_text (items (get item "content"))
  | _ => false end.
Definition usage value := is_null value || (is_object value && boolean_field value "estimated" &&
  natural (get value "input_tokens") && natural (get value "output_tokens") && natural (get value "total_tokens")).
Definition authority value := match parse_status (member_text value "status") with
  | Some Completed => assistant_output (items (member value "output")) && D.present (Json.lookup "usage" value) && usage (member value "usage")
  | Some RequiresAction => negb (Nat.eqb (List.length (items (member value "output"))) 0) && D.present (Json.lookup "usage" value) && is_null (member value "usage")
  | _ => Nat.eqb (List.length (items (member value "output"))) 0 && D.present (Json.lookup "usage" value) && is_null (member value "usage") end.
Fixpoint declared_calls calls tools := match calls with [] => true | call::rest =>
  eq call "type" "function_call" && is_text (get call "id") && nonempty (get call "call_id") &&
  negb (contains_name rest "call_id" (get call "call_id")) &&
  contains_name tools "name" (get call "name") && (match CallWire.parse_arguments CallWire.callback_argument_nesting (str call "arguments_json") with
  | Some _ => true | None => false end) && declared_calls rest tools end.
Definition declared_batch value tools :=
  negb (String.eqb (member_text value "status") "requires_action") || declared_calls (items (member value "output")) tools.
Definition resource_admissible value model body tools := resource_identity value && same_model_request value model body &&
  authority value && declared_batch value tools.
Definition resource_object value model body tools :=
  if resource_admissible value model body tools then success (JObject value)
  else if negb (resource_identity value && same_model_request value model body)
  then err "ChatGPT Web returned an invalid response resource"
  else
    match parse_status (member_text value "status") with
    | Some Completed => err (if assistant_output (items (member value "output"))
        then "ChatGPT Web returned invalid estimated usage" else "ChatGPT Web returned an invalid assistant message")
    | Some RequiresAction => err (if negb (Nat.eqb (List.length (items (member value "output"))) 0) &&
        D.present (Json.lookup "usage" value) && is_null (member value "usage")
        then "ChatGPT Web returned an invalid or undeclared function call" else "ChatGPT Web returned an invalid tool batch")
    | _ => err "ChatGPT Web returned output without a committed response" end.
Definition resource value model body tools := match value with
 | JObject fields => resource_object fields model body tools
 | _ => err "ChatGPT Web returned an invalid response resource" end.
Definition public_codes := ["idempotency_conflict";"previous_response_pending";"previous_response_consumed";
  "previous_response_unavailable";"messages_required";"tool_results_required";"tool_results_mismatch";
  "operation_interrupted";"operation_cancelled";"message_too_large";"tools_disabled";"invalid_request";
  "unauthorized";"model_unavailable";"invalid_output";"output_validation_failed"].
Definition retained_message record := "ChatGPT Web request retained (" ++ member_text record "request_key" ++
  (if truthy (member record "response_id") then ", response " ++ member_text record "response_id" else "") ++
  "); inspect or resume that request before continuing, or explicitly compact to start a new page".
Definition retained record := success (JObject [
  ("message",JString (retained_message record)); ("request_key",member record "request_key"); ("response_id",member record "response_id")]).
Definition failure_result record code status :=
  let code := if existsb (String.eqb (text code)) public_codes then text code else "upstream_error" in
  success (JObject [("message",JString ("ChatGPT Web " ++
    (if truthy status then "HTTP " ++ TextJson.render_json status ++ ", " else "") ++
    code ++ ". " ++ retained_message record)); ("code",JString code);
    ("request_key",member record "request_key"); ("response_id",member record "response_id")]).
Definition event_kind name event := if String.eqb name "message" then str event "type" else name.
Definition event_action action event extras := success (JObject
  (("action",JString action)::(optional (truthy (get event "response_id"))
    "response_id" (get event "response_id") ++ extras))).
Definition event_dispatch name event body model tools index :=
  match event_kind name event with
  | "response.in_progress" => if truthy (get event "response_id") && has event "previous_response_id" &&
      same (get event "previous_response_id") (get body "previous_response_id")
      then event_action "continue" event [] else err "ChatGPT Web progress does not belong to this request"
  | "response.output_text.snapshot" => if truthy (get event "response_id") && boolean_field event "provisional" &&
      is_text (get event "text") then event_action "snapshot" event [("text",get event "text");("index",index)]
      else err "ChatGPT Web returned an invalid snapshot"
  | "response.completed" | "response.requires_action" =>
      let result := resource (get event "response") model body tools in
      if boolean_field result "ok" then
        if String.eqb (event_kind name event) ("response." ++ str (get result "value") "status")
        then event_action "terminal" event [("resource",get result "value")]
        else err "ChatGPT Web terminal event disagrees with its resource" else result
  | "error" => event_action "failure" event [("code",get event "code")]
  | _ => err "ChatGPT Web returned an unsupported SSE event" end.
(* Event identity is derived by parsing the original frame. No host tokenization
   or separately normalized JSON value can grant authority to a different event. *)
Definition event (header : bool) name data body model tools index :=
  if String.eqb data "[DONE]" then event_action "stop" JNull []
  else let parsed := decode_provider_text data in
    if negb (boolean_field parsed "ok") then parsed
    else let value := get parsed "value" in
      if negb (is_object value) then err "ChatGPT Web returned an invalid SSE event"
      else if has value "type" && negb (eq value "type" (event_kind name value))
      then err "ChatGPT Web returned conflicting SSE event names"
      else if header then event_action "identify" value [] else event_dispatch name value body model tools index.
Definition frame data := if String.eqb data "[DONE]" then success JNull else decode_provider_text data.
Definition http_json (response_ok : bool) source := match TextJson.parse_json_members source with
  | Some value => success (JObject [("present",JBool true);("value",value)])
  | None => if response_ok then failure "http_json_parse" "The service returned invalid JSON"
    else success (JObject [("present",JBool false)]) end.
Definition commit value :=
  if eq value "status" "completed" || eq value "status" "requires_action"
  then success (JObject [("action",JString "finish")])
  else success (JObject [("action",JString "failure");("code",if is_null (get (get value "error") "code")
    then JString ("operation_" ++ str value "status") else get (get value "error") "code")]).
Definition http record status := success (JObject [("reject",JBool (negb (truthy (member record "response_id")) &&
  existsb (fun candidate => N.eqb candidate status) [400;401;403;404;413;422]))]).
Definition request_bounds body deferred frame_bytes :=
  if Nat.eqb (List.length (items (get body "input"))) 0
  then err "ChatGPT Web requires new input to continue"
  else if (N.of_nat (String.length (TextJson.render_json body)) <=? frame_bytes) &&
    (N.of_nat (String.length (TextJson.render_json deferred)) <=? frame_bytes)
  then success JNull else range_error "ChatGPT Web request exceeds the configured limit".
