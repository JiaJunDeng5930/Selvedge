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
Definition resource_identity source := let value := get source "value" in
  is_object value && nonempty (get value "id") && eq value "object" "web.response" &&
  eq value "protocol" "chatgpt-web.v1" && natural (get value "created_at") &&
  is_array (get value "output") && match parse_status (str value "status") with Some _ => true | None => false end.
Definition same_model_request source := let value := get source "value" in
  same (get value "model") (get source "model") && has value "previous_response_id" &&
  same (get value "previous_response_id") (get (get source "body") "previous_response_id").
Definition output_text parts := forallb (fun part => eq part "type" "output_text" && is_text (get part "text")) parts.
Definition assistant_output values := match values with
  | [item] => eq item "type" "message" && eq item "role" "assistant" &&
    is_array (get item "content") && negb (Nat.eqb (List.length (items (get item "content"))) 0) &&
    output_text (items (get item "content"))
  | _ => false end.
Definition usage value := is_null value || (is_object value && boolean_field value "estimated" &&
  natural (get value "input_tokens") && natural (get value "output_tokens") && natural (get value "total_tokens")).
Definition authority value := match parse_status (str value "status") with
  | Some Completed => assistant_output (items (get value "output")) && has value "usage" && usage (get value "usage")
  | Some RequiresAction => negb (Nat.eqb (List.length (items (get value "output"))) 0) && has value "usage" && is_null (get value "usage")
  | _ => Nat.eqb (List.length (items (get value "output"))) 0 && has value "usage" && is_null (get value "usage") end.
Fixpoint declared_calls calls tools := match calls with [] => true | call::rest =>
  eq call "type" "function_call" && is_text (get call "id") && nonempty (get call "call_id") &&
  negb (contains_name rest "call_id" (get call "call_id")) &&
  contains_name tools "name" (get call "name") && is_object (get call "arguments") && declared_calls rest tools end.
Definition declared_batch source := let value := get source "value" in
  negb (eq value "status" "requires_action") || declared_calls (items (get value "output")) (items (get source "tools")).
Definition resource_admissible source := resource_identity source && same_model_request source &&
  authority (get source "value") && declared_batch source.
Definition resource source :=
  if resource_admissible source then success (get source "value")
  else if negb (resource_identity source && same_model_request source)
  then err "ChatGPT Web returned an invalid response resource"
  else let value := get source "value" in
    match parse_status (str value "status") with
    | Some Completed => err (if assistant_output (items (get value "output"))
        then "ChatGPT Web returned invalid estimated usage" else "ChatGPT Web returned an invalid assistant message")
    | Some RequiresAction => err (if negb (Nat.eqb (List.length (items (get value "output"))) 0) &&
        has value "usage" && is_null (get value "usage")
        then "ChatGPT Web returned an invalid or undeclared function call" else "ChatGPT Web returned an invalid tool batch")
    | _ => err "ChatGPT Web returned output without a committed response" end.
Definition public_codes := ["idempotency_conflict";"previous_response_pending";"previous_response_consumed";
  "previous_response_unavailable";"messages_required";"tool_results_required";"tool_results_mismatch";
  "operation_interrupted";"operation_cancelled";"message_too_large";"tools_disabled";"invalid_request";
  "unauthorized";"model_unavailable";"invalid_output";"output_validation_failed"].
Definition retained_message record := "ChatGPT Web request retained (" ++ str record "request_key" ++
  (if truthy (get record "response_id") then ", response " ++ str record "response_id" else "") ++
  "); inspect or resume that request before continuing, or explicitly compact to start a new page".
Definition retained source := let record := get source "record" in success (JObject [
  ("message",JString (retained_message record)); ("request_key",get record "request_key"); ("response_id",get record "response_id")]).
Definition failure_result source := let record := get source "record" in
  let code := if existsb (String.eqb (str source "code")) public_codes then str source "code" else "upstream_error" in
  success (JObject [("message",JString ("ChatGPT Web " ++
    (if truthy (get source "status") then "HTTP " ++ TextJson.render_json (get source "status") ++ ", " else "") ++
    code ++ ". " ++ retained_message record)); ("code",JString code);
    ("request_key",get record "request_key"); ("response_id",get record "response_id")]).
Definition event_kind source := if eq (get source "frame") "event" "message"
  then str (get source "event") "type" else str (get source "frame") "event".
Definition event_action action source extras := success (JObject
  (("action",JString action)::(optional (truthy (get (get source "event") "response_id"))
    "response_id" (get (get source "event") "response_id") ++ extras))).
Definition event_dispatch source := let event := get source "event" in
  match event_kind source with
  | "response.in_progress" => if truthy (get event "response_id") && has event "previous_response_id" &&
      same (get event "previous_response_id") (get (get source "body") "previous_response_id")
      then event_action "continue" source [] else err "ChatGPT Web progress does not belong to this request"
  | "response.output_text.snapshot" => if truthy (get event "response_id") && boolean_field event "provisional" &&
      is_text (get event "text") then event_action "snapshot" source [("text",get event "text");("index",get source "index")]
      else err "ChatGPT Web returned an invalid snapshot"
  | "response.completed" | "response.requires_action" =>
      let result := resource (JObject (("value",get event "response")::subset source ["body";"model";"tools"])) in
      if boolean_field result "ok" then
        if String.eqb (event_kind source) ("response." ++ str (get result "value") "status")
        then event_action "terminal" source [("resource",get result "value")]
        else err "ChatGPT Web terminal event disagrees with its resource" else result
  | "error" => event_action "failure" source [("code",get event "code")]
  | _ => err "ChatGPT Web returned an unsupported SSE event" end.
(* Event identity is derived by parsing the original frame. No host tokenization
   or separately normalized JSON value can grant authority to a different event. *)
Definition event (header : bool) source :=
  if eq (get source "frame") "data" "[DONE]" then
    event_action "stop" (set source "event" JNull) []
  else match TextJson.parse_json (str (get source "frame") "data") with
    | None => failure "SyntaxError" "Invalid ChatGPT Web JSON"
    | Some value => let source := set source "event" value in
      if negb (is_object value) then err "ChatGPT Web returned an invalid SSE event"
      else if has value "type" && negb (eq value "type" (event_kind source))
      then err "ChatGPT Web returned conflicting SSE event names"
      else if header then event_action "identify" source [] else event_dispatch source end.

Definition frame source := if eq (get source "frame") "data" "[DONE]" then success JNull
  else decode_text (str (get source "frame") "data").
Definition http_json source := match TextJson.parse_json (str source "text") with
  | Some value => success (JObject [("present",JBool true);("value",value)])
  | None => if boolean_field (get source "response") "ok"
    then failure "http_json_parse" "The service returned invalid JSON"
    else success (JObject [("present",JBool false)]) end.
Definition commit source := let value := get source "resource" in
  if eq value "status" "completed" || eq value "status" "requires_action"
  then success (JObject [("action",JString "finish")])
  else success (JObject [("action",JString "failure");("code",if is_null (get (get value "error") "code")
    then JString ("operation_" ++ str value "status") else get (get value "error") "code")]).
Definition http source := success (JObject [("reject",JBool (negb (truthy (get (get source "record") "response_id")) &&
  existsb (fun status => N.eqb status (num source "status")) [400;401;403;404;413;422]))]).
Definition request_bounds source :=
  if Nat.eqb (List.length (items (get (get source "body") "input"))) 0
  then err "ChatGPT Web requires new input to continue"
  else if (N.of_nat (String.length (TextJson.render_json (get source "body"))) <=? num (get source "limits") "frame_bytes") &&
    (N.of_nat (String.length (TextJson.render_json (get source "deferred"))) <=? num (get source "limits") "frame_bytes")
  then success JNull else range_error "ChatGPT Web request exceeds the configured limit".
