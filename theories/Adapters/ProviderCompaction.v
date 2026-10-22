From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Import Context Conversation.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Record request_content := RequestContent {
  opaque_content : bool;
  encrypted_content_present : bool;
  image_count : N
}.
Definition combine_content (left right : request_content) :=
  RequestContent (opaque_content left || opaque_content right)
    (encrypted_content_present left || encrypted_content_present right)
    (image_count left + image_count right).
Definition empty_content := RequestContent false false 0.
(* Image handles and encrypted continuations cannot be bounded by their textual
   representation. The complete request, rather than an IO assertion, owns this fact. *)
Fixpoint classify_content (value : json) : request_content :=
  match value with
  | JArray values =>
      (fix scan (remaining : list json) :=
       match remaining with [] => empty_content
       | head :: tail => combine_content (classify_content head) (scan tail) end) values
  | JObject fields =>
      (fix scan (remaining : list (string * json)) :=
       match remaining with [] => empty_content
       | (name, item) :: tail =>
         let image := String.eqb name "image_asset" && is_object item in
         let encrypted := String.eqb name "encrypted_content" && is_text item &&
           negb (String.eqb (text item) "") in
         combine_content (RequestContent (image || encrypted) encrypted (if image then 1 else 0))
           (combine_content (classify_content item) (scan tail)) end) fields
  | _ => empty_content
  end.
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
    ("model",get original "model"); ("sampling",get original "sampling");
    ("tools",JArray []); ("callable",JArray []); ("history",JArray history)].
Definition portable_request (source : json) :=
  set (get source "request") "max_output_tokens"
    (get (get (get source "effect") "plan") "output_reserve_tokens").
Definition meter_result (source : json) :=
  let count := get (get source "response") "input_tokens" in
  (* DEFENSE: External token counters can return nonnumeric or negative counts. *)
  match natural count with
  | None => err "The provider returned an invalid input token count"
  | Some _ => success (JObject [("scope",get source "scope");
      ("input_tokens",count); ("tokenizer",JString "provider")]) end.
Definition native_result (source : json) :=
  let response := get source "response" in
  (* DEFENSE: A provider replacement window must be an array before it enters history. *)
  if is_array (get response "output") then success (JObject [
    ("action",JString "native"); ("format",JString "native"); ("scope",get source "scope");
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
Definition bind_item (scope item : json) :=
  if String.eqb (str item "type") "context" then
    JObject [("type",JString "context"); ("part",get item "part"); ("value",JObject [
      ("type",JString "provider_receipt"); ("scope",scope); ("item",get item "value");
      ("markdown_fences",get item "markdown_fences")])]
  else item.
Definition bind_output (source : json) := success (JArray
  (map (bind_item (get source "scope")) (items (get source "items")))).
Definition headers (source : json) := success (JString
  (if equal (get source "status") (number 401) && boolean_field source "authorization" &&
      negb (boolean_field source "refreshed") then "refresh"
   else if boolean_field source "ok" then "continue" else "read_error")).
Definition scope_changed (source : json) :=
  let effect := get source "effect" in success (JObject [
    ("action",JString "scope_changed"); ("scope",get source "scope");
    ("scope_changed",JBool ((boolean_field effect "context_selected" ||
      String.eqb (str effect "kind") "context_compaction") &&
      is_text (get effect "context_scope") &&
      negb (equal (get effect "context_scope") (get source "scope"))))]).
Definition local_measurement (source : json) (content : request_content) :=
  let plaintext := negb (opaque_content content) in success (JObject [
    ("action",JString "local"); ("scope",get source "scope");
    ("input_tokens",if plaintext && N.ltb (num source "window_tokens") (num source "bytes")
      then get source "bytes" else get source "window_tokens");
    ("tokenizer",JString (if plaintext then "utf8_upper_bound" else "request_bytes_exceeded"))]).
Definition measurement_plan (source : json) :=
  let request := get source "request" in
  (* DEFENSE: Token accounting must inspect the full request, never a host classification. *)
  if negb (is_object request) then err "Context measurement requires the complete encoded request"
  else let content := classify_content request in let images := N.ltb 0 (image_count content) in
  if String.eqb (str (get source "profile") "provider") "chatgpt" && images &&
     negb (encrypted_content_present content) then
    (* The account transport does not promise the public token-count endpoint.
       This estimate covers image plus readable text; encrypted continuations
       must use provider metering, whose unsupported-route fallback rejects them. *)
    success (JObject [("action",JString "local"); ("scope",get source "scope");
      ("input_tokens",number (N.of_nat (String.length (TextJson.render_json request)) +
        1844 * image_count content)); ("tokenizer",JString "codex_image_estimate")])
  else if N.leb (num source "bytes") (if images then 33554432 else num (get source "limits") "frame_bytes")
  then success (JObject [("action",JString "remote")]) else local_measurement source content.
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
  if negb (opaque_content (classify_content (get source "request"))) &&
     is_object (get source "request") && unsupported_route source then
    success (JObject [("action",JString "local"); ("scope",get source "scope");
      ("input_tokens",get source "bytes"); ("tokenizer",JString "utf8_upper_bound")])
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
