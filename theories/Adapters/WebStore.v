From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import WebCommon WebResources ProviderCatalog.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition updated record updates := JObject (map (fun pair =>
  (fst pair,match Json.lookup (fst pair) updates with Some value => value | None => snd pair end)) record).
Definition writes record updates := success (JObject [("record",updated record updates);("updates",JObject updates)]).
Definition identity value := WebCommon.nonempty value && match Utf8.decode (text value) with
  | None => false | Some codes =>
      (fold_left (fun count code => count + if code <? 65536 then 1 else 2) codes 0 <=? 256) &&
      forallb (fun code => (33 <=? code) && negb (N.eqb code 127)) codes end.
Definition store_identify record current id :=
  if negb (identity id) then err "ChatGPT Web returned an invalid response identity"
  else if truthy (member current "response_id") && negb (same (member current "response_id") id)
  then err "ChatGPT Web changed the response identity"
  else writes record [("response_id",id);("rejected",number 0)].
Definition parsed_matches raw expected := match TextJson.parse_json (text raw) with
  | Some value => same value expected | None => false end.
Definition store_finish record current response :=
  let result := store_identify record current (member response "id") in
  if negb (boolean_field result "ok") then result
  else if truthy (member current "response") && negb (parsed_matches (member current "response") (JObject response))
  then err "ChatGPT Web changed a committed response"
  else writes record [("response_id",member response "id");
    ("response",JString (TextJson.render_json (JObject response)));("rejected",number 0)].
Definition store_reject record := success (JObject [("updates",if truthy (member record "response_id")
  then JNull else JObject [("rejected",number 1)])]).
Definition store_retire := success (JObject [("updates",JObject [("retired",retirement_code Cancelled)])]).
Record new_request := NewRequest {
 request_body : list (string * json); request_invocation : json; request_owner : json;
 request_profile : json; request_endpoint : json; request_binding : json; request_reset : json }.
Definition request_fields := [required "body" D.RawObject; raw "invocation"; raw "owner";
 raw "profile"; raw "endpoint"; raw "binding"; raw "reset"].
Definition request_value := O.project request_fields (fun body invocation owner profile endpoint binding reset =>
 NewRequest body (missing invocation) (missing owner) (missing profile) (missing endpoint) (missing binding) (missing reset)).
Definition prepare_decision action record := success (JObject [("action",JString action);("record",record)]).
Definition prepare_identity record request :=
  same (stored_member record "owner") request.(request_owner) &&
  same (stored_member record "endpoint") request.(request_endpoint) &&
  same (stored_member record "binding") request.(request_binding) &&
  parsed_matches (stored_member record "body") (JObject request.(request_body)).
Definition predecessor_blocked previous request :=
  if truthy (member request.(request_body) "previous_response_id") then
    negb (stored_as Active previous) ||
    negb (same (stored_member previous "response_id") (member request.(request_body) "previous_response_id")) ||
    negb (truthy (stored_member previous "response"))
  else negb (truthy request.(request_reset)).
Definition store_prepare record request previous key := match record with
 | Some record => if negb (stored_as Active record) then prepare_decision "retained" (stored_json record)
   else if prepare_identity record request then prepare_decision "reuse" (stored_json record)
   else err "A committed ChatGPT Web request cannot change its body or connection"
 | None => let retained := match previous with
   | Some previous => if predecessor_blocked previous request then Some (stored_json previous) else None
   | None => None end in match retained with
   | Some record => prepare_decision "retained" record
   | None => prepare_decision "insert" (JObject [
     ("invocation",request.(request_invocation));("owner",request.(request_owner));("profile",request.(request_profile));
     ("endpoint",request.(request_endpoint));("binding",request.(request_binding));("request_key",JString key);
     ("body",JString (TextJson.render_json (JObject request.(request_body))));
     ("response_id",JNull);("response",JNull);("rejected",number 0);("retired",retirement_code Active)]) end end.
Definition invocation_ticket invocation ticket := String.eqb invocation ticket || String.prefix (ticket ++ ":context:") invocation.
Definition retire_match record owner ticket := String.eqb (str record "owner") owner &&
  same (get record "rejected") (number 0) && match ticket with None => true | Some ticket =>
    invocation_ticket (str record "invocation") (owner ++ ":" ++ name_or_number ticket ++ ":0") ||
    invocation_ticket (str record "invocation") (owner ++ ":" ++ name_or_number ticket ++ ":1") end.
Definition retire_candidates records owner ticket := fold_right (fun record selected =>
  if retire_match record owner ticket then match selected with [] => [record] | previous::_ =>
    [if num previous "ordinal" <? num record "ordinal" then record else previous] end else selected) [] records.
Definition retire_writes records := map (fun record => JObject [("record",record);("request_key",get record "request_key");
  ("updates",JObject [("retired",retirement_code Cancelled)])]) records.
Definition current_format := "selvedge-chatgpt-web-3".
Definition metadata_reply create identity := success (JObject [("create",JBool create);
  ("identity",identity);("format",JString current_format)]).
Definition metadata_error := err "ChatGPT Web receipts are not in the current format".
Definition store_metadata rows new_identity (created : bool) := match rows with
  | [] => if created then metadata_reply true (JString new_identity) else metadata_error
  | [row] => if is_text (get row "format") && eq row "format" current_format && WebCommon.nonempty (get row "identity")
      then metadata_reply false (get row "identity") else metadata_error
  | _ => metadata_error end.
Definition retire_existing rows records owner ticket := let result := store_metadata rows "" false in
  if boolean_field result "ok" then success (JArray (retire_writes (retire_candidates records owner ticket))) else result.
Definition reset_session rows records task := let result := store_metadata rows "" false in
  if boolean_field result "ok" then success (JArray (map (fun record =>
    JObject [("request_key",get record "request_key");("updates",JObject [("retired",retirement_code ConfigurationChanged)])])
    (filter (fun record => eq record "owner" ("task:" ++ decimal task)) records))) else result.
Definition store_latest records owner ticket := success (first_item (retire_candidates records owner ticket)).
Definition cancellation record := success (JString (if truthy record then
  if truthy (get record "response_id") then "cancel" else "retained" else "none")).
Definition cancel_owner task := success (JObject (match task with
 | JObject fields => ("owner",owner_value fields)::member_subset fields ["ticket"]
 | _ => [("owner",JString ("task:" ++ name_or_number task))] end)).
Inductive recovery_action := Inspect | Resume | Cancel.
Definition recovery_declaration := D.Value (Schema.KEnum "inspect" ["resume";"cancel"]).
Definition recovery_action_value (value : D.denote recovery_declaration) :=
 if String.eqb (proj1_sig value) "inspect" then Inspect
 else if String.eqb (proj1_sig value) "resume" then Resume else Cancel.
Definition recovery_fields := [required "action" recovery_declaration; required "confirm" D.Boolean].
Definition recovery_connected profile record := eq profile "provider" "chatgpt-web" &&
  same (get profile "endpoint") (get record "endpoint").
Definition recovery_connection profile record := check (recovery_connected profile record) JNull "The ChatGPT Web connection is no longer configured".
Definition recovery action confirm profile record binding :=
  if negb (recovery_connected profile record) then err "The ChatGPT Web connection is no longer configured"
  else if negb (same binding (get record "binding")) then err "The ChatGPT Web request belongs to a different connection"
  else success (JObject [("retire",JBool (match action with Cancel => true | _ => false end));
    ("retained",JBool (negb (truthy (get record "response_id"))));
    ("method",JString (match action with Inspect => "GET" | _ => "POST" end));
    ("body",JObject (optional (match action with Resume => confirm | _ => false end) "confirm" (JBool true)))]).
Definition recovery_result action value record := let inspect := String.eqb (text action) "inspect" in
  if (if inspect then same (get value "id") (get record "response_id") && eq value "protocol" "chatgpt-web.v1"
      else boolean_field value "ok" && same (get value "response_id") (get record "response_id"))
  then success value else err (if inspect then "ChatGPT Web inspection returned a different resource"
    else "ChatGPT Web did not accept the recovery action").
Definition invocation effect profile body owner stage binding reset :=
  success (JObject [("invocation",JString (owner ++ ":" ++ name_or_number (member effect "ticket") ++ ":" ++
    decimal stage ++ replacement_suffix (member_text effect "kind") (member effect "context_replacement_source")));
    ("owner",JString owner);("profile",get (member effect "model") "profile");("endpoint",member profile "endpoint");
    ("binding",binding);("body",JObject body);("reset",JBool reset)]).
Definition exchange_start record body model tools :=
  if truthy (get record "response") then
    let decoded := decode_text (str record "response") in
    if boolean_field decoded "ok" then
      let result := resource (get decoded "value") model body tools in
      if boolean_field result "ok" then success (JObject [("action",JString "cached");("resource",get result "value")]) else result
    else decoded
  else success (JObject [("action",JString "send")]).
Definition exchange_result resource := success (JObject [("retained",JBool (negb (truthy resource)))]).
Definition catch record error := success (JObject [("retained",JBool (truthy record && negb (truthy (get error "request_key"))))]).
