From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import WebCommon WebResources WebHistory ProviderCatalog.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition continuation_receipt source := get (nth_history (items (get (get source "effect") "history"))
  (num source "receipt_position")) "content".
Definition cancelled source := eq (get source "effect") "kind" "model" && retired_as Cancelled (get source "previous").
Definition configuration_reset source := eq (get source "effect") "kind" "model" && retired_as ConfigurationChanged (get source "previous").
Definition replaced_root source :=
  let suffix := replacement_suffix (get source "effect") in
  negb (String.eqb suffix "") && negb (natural (get source "receipt_position")) &&
  negb (same (get (get source "previous") "owner") (get source "owner") &&
    ProviderCatalog.ends (str (get source "previous") "invocation") suffix).
Definition page_reset source := cancelled source || configuration_reset source || replaced_root source.
Definition continuation_owner source := let effect := get source "effect" in let receipt := continuation_receipt source in
  eq effect "kind" "model" && natural (get source "receipt_position") &&
  same (receipt_index (items (get effect "history")) 0 JNull) (get source "receipt_position") &&
  same (get receipt "task_id") (get effect "task_id") && negb (cancelled source || configuration_reset source).
Definition continuation_binding source := let receipt := continuation_receipt source in
  same (get receipt "store_id") (get source "store_identity") && same (get receipt "binding") (get source "binding") &&
  same (get receipt "contract") (get source "contract") && WebCommon.nonempty (get receipt "response_id") && is_array (get receipt "deferred").
Definition continuation_span source := let receipt := continuation_receipt source in
  natural (get receipt "input_count") && natural (get receipt "output_count") && (0 <? num receipt "output_count") &&
  (num receipt "output_count" <=? num source "receipt_position") &&
  (num receipt "input_count" <=? num source "receipt_position" - num receipt "output_count") &&
  same (get receipt "input_hash") (get source "history_digest").
Definition continuation_suffix source := let receipt := continuation_receipt source in
  let history := items (get (get source "effect") "history") in
  List.app (firstn (N.to_nat (num source "receipt_position" - num receipt "output_count" - num receipt "input_count"))
    (skipn (N.to_nat (num receipt "input_count")) history)) (skipn (N.to_nat (num source "receipt_position")) history).
Definition continuation_result body deferred source := success (JObject [
  ("body",body);("deferred",JArray deferred);("input_count",number (array_count (get (get source "effect") "history")));
  ("receipt_position",get source "receipt_position");("reset",JBool (page_reset source))]).
Definition result_items values := filter (fun item => eq item "role" "function_output") values.
Definition later_items values := filter (fun item => negb (eq item "role" "function_output")) values.
Definition result_find values id := match find (fun item => same (get item "call_id") id) values with Some value => value | None => JNull end.
Definition call_output call result := JObject (("type",JString "function_call_output")::
  (subset call ["call_id"] ++ [("output",JString (TextJson.render_json
    (JObject (("value",get result "content")::subset result ["is_error"]))))])).
Definition call_outputs calls results := map (fun call => call_output call (result_find results (get call "call_id"))) calls.
Fixpoint unique_call_count calls := match calls with [] => 0 | call::rest =>
  (if contains_name rest "call_id" (get call "call_id") then 0 else 1) + unique_call_count rest end.
Fixpoint results_match results calls := match results with [] => true | item::rest =>
  contains_name calls "call_id" (get item "call_id") && negb (contains_name rest "call_id" (get item "call_id")) && results_match rest calls end.
Definition continuation_batch_matches source := let calls := get (continuation_receipt source) "calls" in
  is_array calls && (0 <? array_count calls) && results_match (result_items (continuation_suffix source)) (items calls).
Definition continuation_batch_complete source :=
  N.eqb (N.of_nat (List.length (result_items (continuation_suffix source))))
    (unique_call_count (items (get (continuation_receipt source) "calls"))).
Definition root_body (structured_text : json -> json -> json) source values :=
  let request := get source "request" in structured_text (JObject
    ([("model",get (get (get source "effect") "model") "name");("input",JArray values);("stream",JBool true);("tools",get source "tools")] ++
      optional (truthy (get request "instructions")) "instructions" (get request "instructions"))) (get source "effect").
Definition continuation (structured_text : json -> json -> json) source :=
  if truthy (get (get (get source "effect") "model") "adaptive_reasoning")
  then err "ChatGPT Web effort is fixed by its model profile"
  else if negb (configuration_reset source || negb (cancelled source) || same (get (get source "previous") "binding") (get source "binding"))
    then err "The cancelled ChatGPT Web request belongs to a different connection"
  else if negb (continuation_owner source) then
    match history (items (get (get source "request") "history")) with
    | Rejected code message => failure code message
    | Accepted values => continuation_result (root_body structured_text source values) [] source end
  else if negb (continuation_binding source) then err "ChatGPT Web continuation connection or contract changed; restore it or create a new task"
  else if negb (continuation_span source) then err "ChatGPT Web continuation history no longer matches its committed input receipt"
  else let receipt := continuation_receipt source in
    if eq receipt "status" "completed" then
      match history (continuation_suffix source) with
      | Rejected code message => failure code message
      | Accepted values => continuation_result (successor_body (get receipt "response_id")
        (List.app (items (get receipt "deferred")) values)) [] source end
    else if eq receipt "status" "requires_action" then
      if continuation_batch_matches source && continuation_batch_complete source then
        match history (later_items (continuation_suffix source)) with
        | Rejected code message => failure code message
        | Accepted values => continuation_result (successor_body (get receipt "response_id")
          (call_outputs (items (get receipt "calls")) (result_items (continuation_suffix source))))
          (List.app (items (get receipt "deferred")) values) source end
      else err "ChatGPT Web requires the complete tool-result batch"
    else err "ChatGPT Web receipt is not committed".
Definition receipt_source source := let effect := get source "effect" in let record := get source "record" in
  let response := get source "resource" in
  eq effect "kind" "model" && is_object response && is_object record && is_array (get source "deferred") &&
  is_array (get effect "history") && natural (get source "output_count") && (0 <? num source "output_count") &&
  WebCommon.nonempty (get source "input_hash") && WebCommon.nonempty (get source "store_identity") &&
  (eq response "status" "completed" || eq response "status" "requires_action") &&
  same (get record "response_id") (get response "id") && same (get record "binding") (get source "binding") &&
  same (get record "owner") (owner_value effect) &&
  match TextJson.parse_json (str record "response"),TextJson.parse_json (str record "body") with
  | Some persisted,Some body => same response persisted && resource_admissible (JObject [
    ("value",response);("body",body);("model",get (get effect "model") "name");("tools",get source "tools")])
  | _,_ => false end.
Definition receipt source := let effect := get source "effect" in let resource := get source "resource" in
  success (JObject [("type",JString "provider_receipt");("provider",JString "chatgpt-web");("store_id",get source "store_identity");
    ("task_id",get effect "task_id");("binding",get source "binding");("contract",get source "contract");
    ("request_key",get (get source "record") "request_key");("response_id",get resource "id");("status",get resource "status");
    ("input_count",number (array_count (get effect "history")));("input_hash",get source "input_hash");("output_count",get source "output_count");
    ("calls",JArray (if eq resource "status" "requires_action" then
      map (fun call => JObject (subset call ["call_id";"name"])) (items (get resource "output")) else []));("deferred",get source "deferred")]).
Definition emitted_call call : outcome json :=
  match CallWire.parse_arguments CallWire.callback_argument_nesting
    (str call "arguments_json") with
  | Some arguments => Accepted (CallWire.encode_item (str call "call_id") (str call "name") arguments)
  (* DEFENSE: web.settle can be called directly with an unadmitted resource. *)
  | None => reject "ChatGPT Web returned invalid function arguments" end.
Definition settle source := let index := get source "index" in let resource := get source "resource" in
  if negb (natural index && (same index (number 0) || same index (number 1)))
  then err "Unsupported ChatGPT Web output stage; only parts 0 and 1 are defined"
  else if eq resource "status" "completed" then
    let answer := String.concat "" (map (fun part => str part "text")
      (items (get (first_item (items (get resource "output"))) "content"))) in
    let pending := 0 <? array_count (get source "deferred") in
    success (JObject [("items",JArray [JObject [("type",JString "text");("part",index);("text",JString answer)]]);
      ("snapshot",JString answer);("continue",JBool pending);("deferred",if pending then JArray [] else get source "deferred");
      ("body",if pending then successor_body (get resource "id") (items (get source "deferred")) else get source "body")])
  else render_outcome (fun calls => JObject [("items",JArray calls);("snapshot",JString "");
    ("continue",JBool false);("deferred",get source "deferred");("body",get source "body")])
    (traverse emitted_call (items (get resource "output"))).
