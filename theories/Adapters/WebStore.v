From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import WebCommon WebResources ProviderCatalog.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition updated record updates := match record with JObject fields =>
  JObject (map (fun pair => (fst pair,if has updates (fst pair) then get updates (fst pair) else snd pair)) fields)
  | _ => record end.
Definition writes record updates := success (JObject [("record",updated record updates);("updates",updates)]).
Definition identity value := WebCommon.nonempty value && match Utf8.decode (text value) with
  | None => false | Some codes =>
      (fold_left (fun count code => count + if code <? 65536 then 1 else 2) codes 0 <=? 256) &&
      forallb (fun code => (33 <=? code) && negb (N.eqb code 127)) codes end.
Definition store_identify source :=
  if negb (identity (get source "id")) then err "ChatGPT Web returned an invalid response identity"
  else if truthy (get (get source "current") "response_id") &&
    negb (same (get (get source "current") "response_id") (get source "id"))
  then err "ChatGPT Web changed the response identity"
  else writes (get source "record") (JObject [("response_id",get source "id");("rejected",number 0)]).
Definition parsed_matches raw expected := match TextJson.parse_json (text raw) with
  | Some value => same value expected | None => false end.
Definition store_finish source :=
  let result := store_identify (JObject (("id",get (get source "response") "id")::subset source ["record";"current"])) in
  if negb (boolean_field result "ok") then result
  else if truthy (get (get source "current") "response") &&
    negb (parsed_matches (get (get source "current") "response") (get source "response"))
  then err "ChatGPT Web changed a committed response"
  else writes (get source "record") (JObject [("response_id",get (get source "response") "id");
    ("response",JString (TextJson.render_json (get source "response")));("rejected",number 0)]).
Definition store_reject source := success (JObject [("updates",if truthy (get (get source "record") "response_id")
  then JNull else JObject [("rejected",number 1)])]).
Definition store_retire (source : json) := success (JObject [("updates",JObject [("retired",retirement_code Cancelled)])]).
Definition prepare_decision action record := success (JObject [("action",JString action);("record",record)]).
Definition prepare_identity source := let record := get source "record" in let request := get source "request" in
  same (get record "owner") (get request "owner") && same (get record "endpoint") (get request "endpoint") &&
  same (get record "binding") (get request "binding") && parsed_matches (get record "body") (get request "body").
Definition predecessor_blocked previous request :=
  if truthy (get (get request "body") "previous_response_id") then
    negb (retired_as Active previous) || negb (same (get previous "response_id") (get (get request "body") "previous_response_id")) ||
    negb (truthy (get previous "response"))
  else negb (truthy (get request "reset")).
Definition store_prepare source := let record := get source "record" in let request := get source "request" in
  if truthy record then if negb (retired_as Active record) then prepare_decision "retained" record
    else if prepare_identity source then prepare_decision "reuse" record
    else err "A committed ChatGPT Web request cannot change its body or connection"
  else if truthy (get source "previous") && predecessor_blocked (get source "previous") request
    then prepare_decision "retained" (get source "previous")
  else prepare_decision "insert" (JObject (subset request ["invocation";"owner";"profile";"endpoint";"binding"] ++ [
    ("request_key",get source "new_key");("body",JString (TextJson.render_json (get request "body")));
    ("response_id",JNull);("response",JNull);("rejected",number 0);("retired",retirement_code Active)])).
Definition invocation_ticket invocation ticket := String.eqb invocation ticket || String.prefix (ticket ++ ":context:") invocation.
Definition retire_match record source := same (get record "owner") (get source "owner") &&
  same (get record "rejected") (number 0) &&
  (negb (has source "ticket") ||
    invocation_ticket (str record "invocation") (str source "owner" ++ ":" ++ name_or_number (get source "ticket") ++ ":0") ||
    invocation_ticket (str record "invocation") (str source "owner" ++ ":" ++ name_or_number (get source "ticket") ++ ":1")).
Definition retire_candidates records source := fold_right (fun record selected =>
  if retire_match record source then match selected with [] => [record] | previous::_ =>
    [if num previous "ordinal" <? num record "ordinal" then record else previous] end else selected) [] records.
Definition retire_writes records := map (fun record => JObject [("record",record);("request_key",get record "request_key");
  ("updates",JObject [("retired",retirement_code Cancelled)])]) records.
Definition current_format := "selvedge-chatgpt-web-3".
Definition metadata_reply create identity := success (JObject [("create",JBool create);
  ("identity",identity);("format",JString current_format)]).
Definition metadata_error := err "ChatGPT Web receipts are not in the current format".
Definition store_metadata source := match items (get source "rows") with
  | [] => if boolean_field source "created" then metadata_reply true (get source "new_identity") else metadata_error
  | [row] => if is_text (get row "format") && eq row "format" current_format && WebCommon.nonempty (get row "identity")
      then metadata_reply false (get row "identity") else metadata_error
  | _ => metadata_error end.
Definition retire_existing source := let result := store_metadata source in
  if boolean_field result "ok" then success (JArray (retire_writes (retire_candidates (items (get source "records")) source))) else result.
Definition reset_session source := let result := store_metadata source in
  if boolean_field result "ok" then success (JArray (map (fun record =>
    JObject [("request_key",get record "request_key");("updates",JObject [("retired",retirement_code ConfigurationChanged)])])
    (filter (fun record => eq record "owner" ("task:" ++ name_or_number (get source "task_id"))) (items (get source "records"))))) else result.
Definition store_latest source := success (first_item (retire_candidates (items (get source "records")) source)).
Definition cancellation source := success (JString (if truthy (get source "record") then
  if truthy (get (get source "record") "response_id") then "cancel" else "retained" else "none")).
Definition cancel_owner source := let task := get source "task" in
  success (JObject (if is_object task then ("owner",owner_value task)::subset task ["ticket"]
    else [("owner",JString ("task:" ++ name_or_number task))])).
Definition recovery_shape source := check ((existsb (String.eqb (str source "action")) ["inspect";"resume";"cancel"]) &&
  Json.is_bool (get source "confirm")) JNull "Invalid ChatGPT Web recovery action".
Definition recovery_connected source := eq (get source "profile") "provider" "chatgpt-web" &&
  same (get (get source "profile") "endpoint") (get (get source "record") "endpoint").
Definition recovery_connection source := check (recovery_connected source) JNull "The ChatGPT Web connection is no longer configured".
Definition recovery source :=
  if negb (boolean_field (recovery_shape source) "ok") then err "Invalid ChatGPT Web recovery action"
  else if negb (recovery_connected source) then err "The ChatGPT Web connection is no longer configured"
  else if negb (same (get source "binding") (get (get source "record") "binding"))
    then err "The ChatGPT Web request belongs to a different connection"
  else success (JObject [("retire",JBool (eq source "action" "cancel"));
    ("retained",JBool (negb (truthy (get (get source "record") "response_id"))));
    ("method",JString (if eq source "action" "inspect" then "GET" else "POST"));
    ("body",JObject (optional (eq source "action" "resume" && boolean_field source "confirm") "confirm" (JBool true)))]).
Definition recovery_result source := let inspect := eq source "action" "inspect" in let value := get source "value" in
  if (if inspect then same (get value "id") (get (get source "record") "response_id") && eq value "protocol" "chatgpt-web.v1"
      else boolean_field value "ok" && same (get value "response_id") (get (get source "record") "response_id"))
  then success value else err (if inspect then "ChatGPT Web inspection returned a different resource"
    else "ChatGPT Web did not accept the recovery action").
Definition invocation source := let effect := get source "effect" in
  success (JObject [("invocation",JString (str source "owner" ++ ":" ++ name_or_number (get effect "ticket") ++ ":" ++
    name_or_number (get source "stage") ++ replacement_suffix effect));("owner",get source "owner");
    ("profile",get (get effect "model") "profile");("endpoint",get (get source "profile") "endpoint");
    ("binding",get source "binding");("body",get source "body");("reset",get source "reset")]).
Definition exchange_start source :=
  if truthy (get (get source "record") "response") then
    let decoded := decode_text (str (get source "record") "response") in
    if boolean_field decoded "ok" then
      let result := resource (JObject (("value",get decoded "value")::subset source ["body";"model";"tools"])) in
      if boolean_field result "ok" then success (JObject [("action",JString "cached");("resource",get result "value")]) else result
    else decoded
  else success (JObject [("action",JString "send")]).
Definition exchange_result source := success (JObject [("retained",JBool (negb (truthy (get source "resource"))))]).
Definition catch source := success (JObject [("retained",JBool
  (truthy (get source "record") && negb (truthy (get (get source "error") "request_key"))))]).
