From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson ModelWire.
From Selvedge.Programming Require Import DeclarationFields.
From Selvedge.Kernel Require Import Context Conversation.
From Selvedge.Adapters Require Import Common.
From Selvedge.Adapters Require ProviderCatalog OutputObservations.
From Selvedge.Programming Require AdapterResult.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition input_parts (item : json) := items (get item
  (if String.eqb (str item "type") "function_call_output" then "output" else "content")).
Definition input_images (request : json) := filter (fun part => String.eqb (str part "type") "input_image")
  (flat_map input_parts (items (get request "input"))).
Definition request_image_count (request : json) := N.of_nat (List.length (input_images request)).
Definition encrypted_input_item (item : json) :=
  (String.eqb (str item "type") "reasoning" || String.eqb (str item "type") "compaction") &&
  is_text (get item "encrypted_content") && negb (String.eqb (str item "encrypted_content") "").
(* Only input content carries images or provider continuations. JSON Schema
   examples and defaults can use the same field names as ordinary text data. *)
Definition opaque_request (request : json) :=
  existsb encrypted_input_item (items (get request "input")) || N.ltb 0 (request_image_count request).
Definition selected_request (meter : bool) (source : json) : json :=
  let names := List.app ["model"; "input"; "instructions"]
    (if meter then ["tools"; "tool_choice"; "parallel_tool_calls"] else []) in
  JObject (filter (fun field => existsb (String.eqb (fst field)) names)
    (object_fields (get source "request"))).
Definition capability_message (message : json) : bool :=
  let change := get message "change" in
  let kind := definition_kind Context.interactive_markdown in
  String.eqb (str message "role") "task_context" &&
    (String.eqb (str (get change "key") "type") kind ||
     String.eqb (str (get (get change "snapshot") "key") "type") kind).
Definition helper_history (history : list json) := filter (fun m => negb (capability_message m)) history.
Definition effect (source : json) : json :=
  let original := get source "effect" in let plan := get original "plan" in
  let history := if String.eqb (str plan "method") "native"
    then helper_history (items (get plan "history"))
    else [JObject [("role",JString "user"); ("content",JString
      (str plan "prompt" ++ "

Previous continuation note:
" ++ str plan "carry" ++
       "

Next quoted history fragment:
" ++ str plan "chunk"))]] in
  JObject [("kind",JString "context_compaction"); ("context_selected",JBool true);
    ("model",get original "model"); ("history",JArray history)].
Definition portable_request (source : json) :=
  set (get source "request") "max_output_tokens"
    (get (get (get source "effect") "plan") "output_reserve_tokens").
Definition meter_result (source : json) :=
  let count := get (get source "response") "input_tokens" in
  (* DEFENSE: External token counters can return fractional, negative or out-of-range counts. *)
  match wire_natural count with
  | None => err "The provider returned an invalid input token count"
  | Some count => success (JObject [("scope",get source "scope");
      ("input_tokens",number count)]) end.
Definition native_result (source : json) :=
  let response := get source "response" in
  (* DEFENSE: A provider replacement window must be an array before it enters history. *)
  if is_array (get response "output") then success (JObject [
    ("format",JString "native"); ("scope",get source "scope");
    ("items",JArray [JObject [("role",JString "model_context"); ("content",get response "output")]]);
    ("usage",get response "usage")])
  else err "The native compactor returned an invalid replacement window".
Definition summary_result (source : json) := success (JObject [
  ("summary_text", JString (String.concat "" (map (fun item =>
    String.concat "" (map (fun part => str part "text")
      (items (get (Conversation.provider_value (get item "value")) "content"))))
      (items (get source "items")))));
  ("scope",get source "scope"); ("usage",get source "usage")]).
Definition scope (source : json) := success (JString (TextJson.render_json (JArray [
  get (get source "profile") "provider"; get (get source "profile") "endpoint";
  get source "model"; get source "account_id"]))).
Definition bind_item (scope item : json) : AdapterResult.outcome ModelWire.value :=
 if String.eqb (str item "type") "context" then
   match DeclarationFields.decode OutputObservations.provider_fields item with
   | Some fields => AdapterResult.Accepted (ModelWire.context (fst (snd fields)) [
       ("type",JString "provider_receipt");("scope",scope);("item",JObject (fst (snd (snd fields))));
       ("markdown_fences",OutputObservations.encode_fences (fst (snd (snd (snd fields)))))])
   | None => AdapterResult.reject "Provider context observation is malformed" end
 else match ModelWire.decode item with
   | Some result => AdapterResult.Accepted result
   | None => AdapterResult.reject "Model output is malformed" end.
Definition bind_output (source : json) := AdapterResult.render_outcome ModelWire.encode_items
 (AdapterResult.traverse (bind_item (get source "scope")) (items (get source "items"))).
Definition headers (source : json) := success (JString
  (if equal (get source "status") (number 401) && boolean_field source "authorization" &&
      negb (boolean_field source "refreshed") then "refresh"
   else if boolean_field source "ok" then "continue" else "read_error")).
Definition scope_changed (source : json) :=
  let effect := get source "effect" in success (JObject [
    ("scope",get source "scope");
    ("scope_changed",JBool ((boolean_field effect "context_selected" ||
      String.eqb (str effect "kind") "context_compaction") &&
      is_text (get effect "context_scope") &&
      negb (equal (get effect "context_scope") (get source "scope"))))]).
Definition measurement_plan (source : json) :=
  let request := get source "request" in
  let images := request_image_count request in
  if ProviderCatalog.account (get source "profile") && N.ltb 0 images then
    (* The account transport does not promise the public token-count endpoint.
       Keep image requests usable with an encrypted continuation as well: the
       estimate includes the complete encoded request and each image. *)
    success (JObject [("action",JString "local"); ("scope",get source "scope");
      ("input_tokens",number (N.of_nat (String.length (TextJson.render_json request)) +
        1844 * images))])
  else success (JObject [("action",JString "remote")]).
Definition code_in (source : json) (codes : list string) :=
  existsb (String.eqb (str source "code")) codes.
Definition status_is (source : json) (status : N) := equal (get source "status") (number status).
Definition unsupported_route (source : json) :=
  negb (String.eqb (str source "code") "model_not_found") &&
    (status_is source 404 || status_is source 405 || status_is source 501 ||
      (status_is source 400 && code_in source
        ["unsupported_route"; "unsupported_endpoint"; "route_not_found"; "not_implemented"])).
Definition action (name : string) := success (JObject [("action",JString name)]).
Definition meter_fallback (source : json) :=
  (* DEFENSE: Only explicit route-capability failures allow local measurement;
     encrypted continuations and image handles have no textual token bound. *)
  if negb (opaque_request (get source "request")) && unsupported_route source then
    success (JObject [("action",JString "local"); ("scope",get source "scope");
      ("input_tokens",get source "bytes")])
  else action "error".
Definition native_failure (source : json) :=
  (* DEFENSE: Only unsupported route/model responses authorize portable compaction. *)
  if unsupported_route source || (status_is source 400 && code_in source
    ["unsupported_operation"; "operation_not_supported"; "unsupported_model";
     "model_not_supported"; "model_not_supported_for_compaction"; "compaction_not_supported"])
  then action "native_unavailable" else action "error".
Definition budget (source : json) := success (JString
  (if N.leb (num source "input_tokens" + num (get source "plan") "output_reserve_tokens")
    (num (get source "plan") "window_tokens") then "dispatch" else "resize")).
Definition call (operation : string) (source : json) : json :=
  if String.eqb operation "backend.compaction_meter_request" then success (selected_request true source)
  else if String.eqb operation "backend.compaction_request" then success (selected_request false source)
  else if String.eqb operation "backend.compaction_effect" then success (effect source)
  else if String.eqb operation "backend.compaction_portable_request" then success (portable_request source)
  else if String.eqb operation "backend.compaction_meter_result" then meter_result source
  else if String.eqb operation "backend.compaction_native_result" then native_result source
  else if String.eqb operation "backend.compaction_summary_result" then summary_result source
  else if String.eqb operation "backend.compaction_budget" then budget source
  else if String.eqb operation "backend.compaction_scope" then scope source
  else if String.eqb operation "backend.compaction_bind_output" then bind_output source
  else if String.eqb operation "backend.compaction_headers" then headers source
  else if String.eqb operation "backend.compaction_measurement_plan" then measurement_plan source
  else if String.eqb operation "backend.compaction_scope_changed" then scope_changed source
  else if String.eqb operation "backend.compaction_meter_fallback" then meter_fallback source
  else if String.eqb operation "backend.compaction_native_failure" then native_failure source
  else err ("Unknown compaction adapter operation: " ++ operation).
