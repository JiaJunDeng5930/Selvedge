From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import ModelWire.
From Selvedge.Adapters Require Import WebCommon WebResources WebHistory ProviderCatalog BackendRequests.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Record history_effect := HistoryEffect {
 effect_history : list json; effect_kind : string; effect_model : json; effect_task : json;
 effect_ticket : json; effect_replacement : json; effect_retitle : bool; effect_tools_value : json; effect_instructions : json }.
Definition history_fields := [required "history" (D.Array D.Any);raw "kind";raw "model";raw "task_id";
 raw "ticket";raw "context_replacement_source";raw "retitle";raw "tools";raw "instructions"].
Definition history_value := project history_fields (fun history kind model task ticket replacement retitle tools instructions =>
 HistoryEffect history (text (missing kind)) (missing model) (missing task) (missing ticket)
   (missing replacement) (flag (missing retitle)) (missing tools) (missing instructions)).
Record continuation_input := ContinuationInput {
 continuation_effect : history_effect;
 previous_request : option stored_request; continuation_owner_value : json; continuation_store : json;
 continuation_binding_value : json; continuation_contract : json; continuation_digest : json }.
Definition selected_position source := cursor source.(continuation_effect).(effect_kind) source.(continuation_effect).(effect_history).
Definition continuation_receipt source := get (nth_history source.(continuation_effect).(effect_history)
  (nat_value (selected_position source))) "content".
Definition previous_as reason source := match source.(previous_request) with
 | Some value => stored_as reason value | None => false end.
Definition previous_field source name := match source.(previous_request) with
 | Some value => stored_member value name | None => JNull end.
Definition cancelled source := String.eqb source.(continuation_effect).(effect_kind) "model" && previous_as Cancelled source.
Definition configuration_reset source := String.eqb source.(continuation_effect).(effect_kind) "model" && previous_as ConfigurationChanged source.
Definition replaced_root source :=
  let suffix := replacement_suffix source.(continuation_effect).(effect_kind) source.(continuation_effect).(effect_replacement) in
  negb (String.eqb suffix "") && is_null (selected_position source) &&
  negb (same (previous_field source "owner") source.(continuation_owner_value) &&
    ProviderCatalog.ends (text (previous_field source "invocation")) suffix).
Definition page_reset source := cancelled source || configuration_reset source || replaced_root source.
Definition continuation_owner source :=
  negb (is_null (selected_position source)) &&
  same (get (continuation_receipt source) "task_id") source.(continuation_effect).(effect_task) &&
  negb (cancelled source || configuration_reset source).
Definition nonempty_text := D.Text (D.TextConstraints 1 D.maximum_natural D.maximum_natural false false false None).
Definition positive_natural := D.Natural 1 9007199254740991.
Definition receipt_fields := [required "response_id" nonempty_text;required "deferred" (D.Array D.Any);
 required "input_count" safe_natural;required "output_count" positive_natural;
 required "status" (D.Value (Schema.KEnum "completed" ["requires_action"]));
 required "calls" (D.Array D.Any);raw "store_id";raw "binding";raw "contract";raw "input_hash"].
Record receipt_context := ReceiptContext {
 receipt_response : D.denote nonempty_text; receipt_deferred : list json;
 receipt_input_count : D.denote safe_natural; receipt_output_count : D.denote positive_natural;
 receipt_requires_action : bool; receipt_calls : list json;
 receipt_store : json; receipt_binding : json; receipt_contract : json; receipt_hash : json }.
Definition receipt_value := project receipt_fields (fun response deferred inputs outputs status calls store binding contract hash =>
 ReceiptContext response deferred inputs outputs (String.eqb (proj1_sig status) "requires_action") calls
   (missing store) (missing binding) (missing contract) (missing hash)).
Definition continuation_binding source receipt :=
  same receipt.(receipt_store) source.(continuation_store) &&
  same receipt.(receipt_binding) source.(continuation_binding_value) &&
  same receipt.(receipt_contract) source.(continuation_contract).
(* A continuation suffix is produced only from a receipt whose counted span
   fits the selected history and whose input digest still identifies that span. *)
Definition continuation_suffix source receipt : option (list json) :=
  let position := nat_value (selected_position source) in
  let inputs := proj1_sig receipt.(receipt_input_count) in
  let outputs := proj1_sig receipt.(receipt_output_count) in
  if (outputs <=? position) && (inputs <=? position - outputs) && same receipt.(receipt_hash) source.(continuation_digest)
  then let history := source.(continuation_effect).(effect_history) in
    Some (List.app (firstn (N.to_nat (position - outputs - inputs)) (skipn (N.to_nat inputs) history))
      (skipn (N.to_nat position) history))
  else None.
Definition continuation_result body deferred source := success (JObject [
  ("body",body);("deferred",JArray deferred);("input_count",number (N.of_nat (List.length source.(continuation_effect).(effect_history))));
  ("receipt_position",if is_null (selected_position source) then JNumber "-1" else selected_position source);
  ("reset",JBool (page_reset source))]).
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
Definition continuation_batch_matches calls suffix :=
  (0 <? N.of_nat (List.length calls)) && results_match (result_items suffix) calls.
Definition continuation_batch_complete calls suffix :=
  N.eqb (N.of_nat (List.length (result_items suffix))) (unique_call_count calls).
Definition root_body source values := let effect := source.(continuation_effect) in
  bind (WebHistory.effect_tools effect.(effect_kind) effect.(effect_tools_value)) (fun tools =>
  Accepted (BackendRequests.structured_text_fields (JObject
    ([("model",get effect.(effect_model) "name");("input",JArray values);("stream",JBool true);("tools",JArray tools)] ++
      optional (truthy effect.(effect_instructions)) "instructions" effect.(effect_instructions))) effect.(effect_kind) effect.(effect_retitle))).
Definition continue_receipt source receipt suffix :=
 if receipt.(receipt_requires_action) then
   if continuation_batch_matches receipt.(receipt_calls) suffix && continuation_batch_complete receipt.(receipt_calls) suffix then
     match history (later_items suffix) with
     | Rejected code message => failure code message
     | Accepted values => continuation_result (successor_body (JString (proj1_sig receipt.(receipt_response)))
       (call_outputs receipt.(receipt_calls) (result_items suffix)))
       (List.app receipt.(receipt_deferred) values) source end
   else err "ChatGPT Web requires the complete tool-result batch"
 else match history suffix with
   | Rejected code message => failure code message
   | Accepted values => continuation_result (successor_body (JString (proj1_sig receipt.(receipt_response)))
     (List.app receipt.(receipt_deferred) values)) [] source end.
Definition continuation source :=
  if truthy (get source.(continuation_effect).(effect_model) "adaptive_reasoning")
  then err "ChatGPT Web effort is fixed by its model profile"
  else if negb (configuration_reset source || negb (cancelled source) || same (previous_field source "binding") source.(continuation_binding_value))
    then err "The cancelled ChatGPT Web request belongs to a different connection"
  else if negb (continuation_owner source) then
    match history source.(continuation_effect).(effect_history) with
    | Rejected code message => failure code message
    | Accepted values => match root_body source values with
      | Accepted body => continuation_result body [] source
      | Rejected code message => failure code message end end
  else match D.decode (D.OpenObject receipt_fields) (continuation_receipt source) with
  (* DEFENSE: Persisted provider context can contain an incomplete receipt or
     an uncommitted status; neither can supply a continuation span. *)
  | None => err "ChatGPT Web receipt is not committed"
  | Some decoded => let receipt := receipt_value decoded in
    if negb (continuation_binding source receipt) then err "ChatGPT Web continuation connection or contract changed; restore it or create a new task"
    else match continuation_suffix source receipt with
    | None => err "ChatGPT Web continuation history no longer matches its committed input receipt"
    | Some suffix => continue_receipt source receipt suffix end end.
Definition model_history_fields := [required "kind" (D.Const (JString "model"));required "history" (D.Array D.Any);raw "model";raw "task_id"].
Definition model_history_value := project model_history_fields (fun _ history model task => (history,missing model,missing task)).
Definition receipt (history : list json) model task response record deferred
 (output_count : D.denote positive_natural) (input_hash store_identity : D.denote nonempty_text) binding contract tools :=
  if (String.eqb (member_text response "status") "completed" || String.eqb (member_text response "status") "requires_action") &&
     same (member record "response_id") (member response "id") && same (member record "binding") binding &&
     same (member record "owner") (owner_parts "model" task JNull JNull) &&
     (match TextJson.parse_json (member_text record "response"),TextJson.parse_json (member_text record "body") with
      | Some persisted,Some body => same (JObject response) persisted && resource_admissible response (get model "name") body tools
      | _,_ => false end)
  then success (JObject [
    ("type",JString "provider_receipt");("provider",JString "chatgpt-web");("store_id",JString (proj1_sig store_identity));
    ("task_id",task);("binding",binding);("contract",contract);("request_key",member record "request_key");
    ("response_id",member response "id");("status",member response "status");
    ("input_count",number (N.of_nat (List.length history)));("input_hash",JString (proj1_sig input_hash));
    ("output_count",number (proj1_sig output_count));
    ("calls",JArray (if String.eqb (member_text response "status") "requires_action" then
      map (fun call => JObject (subset call ["call_id";"name"])) (items (member response "output")) else []));("deferred",JArray deferred)])
  else err "Invalid ChatGPT Web JSON source".
Definition emitted_call call : outcome json :=
 match CallWire.from_text CallWire.callback_argument_nesting
   (str call "call_id") (str call "name") (str call "arguments_json") with
 | Some invocation => Accepted (ModelWire.encode (ModelWire.call invocation))
 (* DEFENSE: web.settle is a public boundary and can receive an invalid call. *)
 | None => reject "ChatGPT Web returned an invalid function call" end.
Definition stage := D.Natural 0 1.
Definition settle (index : D.denote stage) resource deferred body :=
  if String.eqb (member_text resource "status") "completed" then
    let answer := String.concat "" (map (fun part => str part "text")
      (items (get (first_item (items (member resource "output"))) "content"))) in
    match ModelWire.text_from_string (proj1_sig index) answer with
    (* DEFENSE: A public settlement must satisfy the model item's text contract,
       including the byte limit after all assistant parts are concatenated. *)
    | None => err "ChatGPT Web returned invalid assistant text"
    | Some output => let pending := negb (Nat.eqb (List.length deferred) 0) in
      success (JObject [("items",JArray [ModelWire.encode output]);("snapshot",JString answer);("continue",JBool pending);
        ("deferred",if pending then JArray [] else JArray deferred);
        ("body",if pending then successor_body (member resource "id") deferred else body)]) end
  else render_outcome (fun calls => JObject [("items",JArray calls);("snapshot",JString "");
    ("continue",JBool false);("deferred",JArray deferred);("body",body)])
    (traverse emitted_call (items (member resource "output"))).
