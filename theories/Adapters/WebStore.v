From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import WebCommon WebResources ProviderCatalog.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition writes updates := success (JObject [("updates",JObject updates)]).
Definition bind_identity (current : response_stage) (id : json) : string + response_stage :=
 if negb (response_identity id) then inl "ChatGPT Web returned an invalid response identity"
 else match current with
 | AwaitingResponse | RejectedResponse => inr (IdentifiedResponse (text id))
 | IdentifiedResponse _ | CommittedResponse _ _ =>
   if same (response_id current) id then inr current else inl "ChatGPT Web changed the response identity"
 end.
Definition store_identify current id :=
 match bind_identity current id with
 | inl message => err message
 | inr next => writes (member_subset (response_fields next) ["response_id";"rejected"])
 end.
Definition parsed_matches raw expected := match TextJson.parse_json (text raw) with
 | Some value => same value expected | None => false end.
Definition commit_response (current : response_stage) (response : list (string * json)) : string + response_stage :=
 let id := member response "id" in
 match bind_identity current id with
 | inl message => inl message
 | inr identified =>
   let completed := CommittedResponse (text (response_id identified)) (TextJson.render_json (JObject response)) in
   match current with
   | CommittedResponse _ body =>
     if parsed_matches (JString body) (JObject response) then inr completed
     else inl "ChatGPT Web changed a committed response"
   | _ => inr completed end
 end.
Definition store_finish current response :=
 match commit_response current response with
 | inl message => err message
 | inr next => writes (response_fields next)
 end.
Definition store_reject current := match current with
 | AwaitingResponse | RejectedResponse => writes (member_subset (response_fields RejectedResponse) ["rejected"])
 | _ => success (JObject [("updates",JNull)])
 end.
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
    negb (stored_as Active previous &&
      match previous.(stored_response) with
      | CommittedResponse id _ => same (JString id) (member request.(request_body) "previous_response_id")
      | _ => false end)
  else negb (truthy request.(request_reset)).
Definition reuse_decision record := success (JObject [
 ("action",JString "reuse");("record",stored_json record);
 ("updates",match record.(stored_response) with
   | RejectedResponse => JObject (member_subset (response_fields AwaitingResponse) ["rejected"])
   | _ => JNull end)]).
Definition store_prepare record request previous key := match record with
 | Some record => if negb (stored_as Active record) then prepare_decision "retained" (stored_json record)
   else if prepare_identity record request then reuse_decision record
   else err "A committed ChatGPT Web request cannot change its body or connection"
 | None => let retained := match previous with
   | Some previous => if predecessor_blocked previous request then Some (stored_json previous) else None
   | None => None end in match retained with
   | Some record => prepare_decision "retained" record
   | None => prepare_decision "insert" (stored_json (StoredRequest [
     ("invocation",request.(request_invocation));("owner",request.(request_owner));
     ("profile",request.(request_profile));("endpoint",request.(request_endpoint));
     ("binding",request.(request_binding));("request_key",JString key);
     ("body",JString (TextJson.render_json (JObject request.(request_body))))]
     Active AwaitingResponse)) end end.
Definition invocation_ticket invocation ticket := String.eqb invocation ticket || String.prefix (ticket ++ ":context:") invocation.
Definition retire_match record invocation_prefix :=
  match record.(stored_response) with RejectedResponse => false | _ => true end &&
 match invocation_prefix with None => true | Some prefix =>
    invocation_ticket (text (stored_member record "invocation")) (prefix ++ ":0") ||
    invocation_ticket (text (stored_member record "invocation")) (prefix ++ ":1") end.
Definition retire_candidate records invocation_prefix := fold_right (fun record selected =>
  if retire_match record invocation_prefix then Some (match selected with None => record | Some previous =>
    if nat_value (stored_member previous "ordinal") <? nat_value (stored_member record "ordinal") then record else previous end) else selected) None records.
Definition current_format := "selvedge-chatgpt-web-3".
Definition metadata_reply identity := success (JObject [
  ("identity",identity);("format",JString current_format)]).
Definition metadata_error := err "ChatGPT Web receipts are not in the current format".
Definition store_metadata rows new_identity (created : bool) := match rows with
  | [] => if created then metadata_reply (JString new_identity) else metadata_error
  | [row] => if is_text (get row "format") && eq row "format" current_format && WebCommon.nonempty (get row "identity")
      then metadata_reply (get row "identity") else metadata_error
  | _ => metadata_error end.
Definition retire_existing rows records owner ticket := let result := store_metadata rows "" false in
  if boolean_field result "ok" then success (match retire_candidate records
      (option_map (fun ticket => owner ++ ":" ++ name_or_number ticket) ticket) with
    | Some record => JObject [("record",stored_json record);
        ("updates",JObject [("retired",retirement_code Cancelled)])]
    | None => JNull end) else result.
Definition reset_session rows records := let result := store_metadata rows "" false in
  if boolean_field result "ok" then success (JArray (map (fun record =>
    JObject [("request_key",get record "request_key");("updates",JObject [("retired",retirement_code ConfigurationChanged)])])
    records)) else result.
Definition store_latest records := success (match retire_candidate records None with
  | Some record => stored_json record | None => JNull end).
Definition cancellation record := success (JString (match record with
 | Some record => if truthy (response_id record.(stored_response)) then "cancel" else "retained"
 | None => "none" end)).
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
(* Connection admission precedes the host's credential read. Only the observed
   binding is new evidence when this continuation constructs the recovery action. *)
Definition recovery action confirm record binding :=
  if negb (same binding (stored_member record "binding")) then err "The ChatGPT Web request belongs to a different connection"
  else let id := response_id record.(stored_response) in
  success (JObject [("retire",JBool (match action with Cancel => true | _ => false end));
    ("retained",JBool (is_null id));("response_id",id);
    ("method",JString (match action with Inspect => "GET" | _ => "POST" end));
    ("body",JObject (optional (match action with Resume => confirm | _ => false end) "confirm" (JBool true)))]).
Definition recovery_result action value record := let inspect := String.eqb (text action) "inspect" in
  if (if inspect then same (get value "id") (response_id record.(stored_response)) && eq value "protocol" "chatgpt-web.v1"
      else boolean_field value "ok" && same (get value "response_id") (response_id record.(stored_response)))
  then success value else err (if inspect then "ChatGPT Web inspection returned a different resource"
    else "ChatGPT Web did not accept the recovery action").
Definition invocation effect profile body owner stage binding reset :=
  success (JObject [("invocation",JString (owner ++ ":" ++ name_or_number (member effect "ticket") ++ ":" ++
    decimal stage ++ replacement_suffix (member_text effect "kind") (member effect "context_replacement_source")));
    ("owner",JString owner);("profile",get (member effect "model") "profile");("endpoint",member profile "endpoint");
    ("binding",binding);("body",JObject body);("reset",JBool reset)]).
Definition exchange_start record body model tools :=
  match record.(stored_response) with
  | CommittedResponse _ raw =>
    let decoded := decode_text raw in
    if boolean_field decoded "ok" then
      let result := resource (get decoded "value") model body tools in
      if boolean_field result "ok" then success (JObject [("action",JString "cached");("resource",get result "value")]) else result
    else decoded
  | _ => success (JObject [("action",JString "send")]) end.
Definition exchange_result resource := success (JObject [("retained",JBool (negb (truthy resource)))]).
Definition catch record error := success (JObject [("retained",JBool (truthy record && negb (truthy (get error "request_key"))))]).
