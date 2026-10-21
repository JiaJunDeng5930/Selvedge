From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Adapters Require Export AccountCatalog.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition login_account source := let config := get source "config" in
  if has source "key" then let profile := get (get config "profiles") (str source "key") in
    if same (get profile "provider") (JString "chatgpt") then success profile
    else err "Select a ChatGPT profile or omit the profile to sign in"
  else let profile := match find (fun entry => same (get (snd entry) "provider") (JString "chatgpt"))
      (object_fields (get config "profiles")) with Some (_,value) => value | None => JNull end in
    if is_null profile && same (get config "chatgpt") (JBool false)
    then err "Automatic ChatGPT account discovery is disabled in this configuration"
    else success (if is_object profile then profile else if is_object (get config "chatgpt")
      then get config "chatgpt" else AccountContracts.defaults).
Definition candidate profile primary := JObject [("profile",profile);("primary",JBool primary)].
Definition candidates source := let config := get source "config" in success (JArray
  (map (fun entry => candidate (snd entry) false) (filter
    (fun entry => same (get (snd entry) "provider") (JString "chatgpt")) (object_fields (get config "profiles"))) ++
   if same (get config "chatgpt") (JBool false) then []
   else [candidate (default (get config "chatgpt") AccountContracts.defaults) true])).
Definition configured_path all path := existsb (fun item =>
  negb (boolean_field item "primary") && same (get item "path") path) all.
Fixpoint select_candidates all seen values := match values with [] => [] | value::rest =>
  if (boolean_field value "primary" && configured_path all (get value "path")) ||
    existsb (String.eqb (str value "identity")) seen
  then select_candidates all seen rest
  else get value "profile" :: select_candidates all (str value "identity"::seen) rest end.
Definition candidate_paths source := let values := items (get source "candidates") in
  success (JArray (select_candidates values [] values)).
Fixpoint unique_efforts seen values := match values with [] => [] | value::rest =>
  let effort := str value "effort" in
  if existsb (String.eqb effort) seen then unique_efforts seen rest
  else effort :: unique_efforts (effort::seen) rest end.
Definition effort_name value := slug value && utf16_within 128 value &&
  negb (contains_text ":" value) && Nat.leb (String.length value) 64.
Definition auto_policy profile model : outcome (option json) :=
  if same (get model "slug") (JString "gpt-6-astra") && is_array (get model "supported_reasoning_levels") then
    let values := unique_efforts [] (items (get model "supported_reasoning_levels")) in
    if Nat.eqb (List.length values) 0 || existsb (String.eqb "auto") values then Accepted None
    else if Nat.leb (List.length values) 16 && forallb effort_name values then
      Accepted (Some (set profile "adaptive_reasoning" (JObject [
        ("evaluator",JString "jev");("efforts",JArray (map JString values));
        ("baseline",if existsb (String.eqb (str model "default_reasoning_level")) values
          then get model "default_reasoning_level" else JString (hd "" values));
        ("transport",JString "configuration_update");("max_lease",number 10)])))
    else reject "Adaptive reasoning requires an evaluator, distinct actual efforts, a supported baseline, transport, and a lease bound of 1..10"
  else Accepted None.
Definition auto_preset source := render_outcome (fun value => match value with Some value => value | None => JNull end)
  (auto_policy (get source "profile") (get source "descriptor")).
Definition review_info model :=
  if existsb (String.eqb "low") (unique_efforts [] (items (get model "supported_reasoning_levels")))
  then JObject ([("default_reasoning_level",JString "low")] ++ selected_fields model
    ["slug";"display_name";"visibility";"priority";"supported_reasoning_levels";"context_window";"effective_context_window_percent"])
  else model.
Definition model_profile source model := JObject (object_fields (get source "connection") ++
  [("model",get model "slug");("bound_account_id",get (get source "result") "account_id");("model_info",model)]).
Definition materialize_model source model generated key :=
  if has (get (get source "config") "profiles") key then reject "A configured profile conflicts with an account model"
  else let profile := model_profile source model in
    let generated := List.app generated [(key,profile)] in
    bind (auto_policy profile model) (fun automatic => match automatic with
    | None => Accepted generated
    | Some value => let automatic_key := AccountNamespace.auto_key key in
        if has (get (get source "config") "profiles") automatic_key then Accepted generated
        else Accepted (List.app generated [(automatic_key,value)]) end).
Definition same_reviewer_connection profile source configured_path :=
  let connection := profile_connection_value profile in let selected := get source "connection" in
  let auth_path := get source "auth_path" in
  same (get profile "provider") (JString "chatgpt") &&
  same (get connection "endpoint") (get selected "endpoint") &&
  same (get connection "issuer") (get selected "issuer") &&
  nonempty auth_path && nonempty configured_path && same auth_path configured_path &&
  (negb (has profile "bound_account_id") || same (get profile "bound_account_id") (get (get source "result") "account_id")).
Fixpoint reviewer_aliases source model profiles generated := match profiles with
  | [] => Accepted generated | (key,profile)::rest =>
    let action := if same_reviewer_connection profile source (get (get source "configured_auth_paths") key) &&
        negb (same (get profile "model") (JString ModelCapabilities.codex_auto_review_model))
      then materialize_model source model generated
        (AccountNamespace.reviewer_key key
          (substring (String.length AccountNamespace.prefix) (String.length (str source "namespace")) (str source "namespace")))
      else Accepted generated in
    bind action (fun generated => reviewer_aliases source model rest generated) end.
Fixpoint materialize_list source (reviewers : bool) models generated := match models with
  | [] => Accepted generated | model::rest =>
    bind (materialize_model source model generated (AccountNamespace.model_key (str source "namespace") (str model "slug"))) (fun generated =>
      bind (if reviewers then reviewer_aliases source model (object_fields (get (get source "config") "profiles")) generated
        else Accepted generated) (fun generated => materialize_list source reviewers rest generated)) end.
Definition materialize source :=
  if negb (AccountNamespace.is_namespace (str source "namespace")) then err "Invalid ChatGPT account namespace" else
  render_outcome JObject (bind (admit_models [] (items (get (get source "result") "models"))) (fun values =>
    let models := map model_json values in
    bind (materialize_list source false (selectable models) []) (fun generated =>
      materialize_list source true (map review_info (review_models models)) generated))).

Definition namespace_discovered key profile configured_path discoveries := existsb (fun discovery =>
  starts key (str discovery "namespace" ++ "/") && same_reviewer_connection profile discovery configured_path) discoveries.
Definition configured_namespace_valid source :=
  forallb (fun entry => let '(key,profile) := entry in
    negb (AccountNamespace.is_profile_key key) || namespace_discovered key profile
      (get (get source "configured_auth_paths") key) (items (get source "discoveries")))
    (object_fields (get (get source "config") "profiles")).
Definition config_materialized source :=
  if configured_namespace_valid source then
    let config := get source "config" in let profiles := get config "profiles" in let generated := get source "generated" in
    let merged := JObject (map (fun entry => (fst entry,supplied profiles (fst entry) (snd entry))) (object_fields generated) ++
      filter (fun entry => negb (has generated (fst entry))) (object_fields profiles)) in
    success (set config "profiles" merged)
  else failure "account_namespace_mismatch"
    "A configured ChatGPT account profile could not verify its account connection; use the original account connection or a new profile key".
Definition materialization_diagnostic source :=
  let result := get source "result" in let stale := boolean_field result "stale" in
  let reviewer := negb (Nat.eqb (List.length (review_models (items (get result "models")))) 0) in
  success (match stale,reviewer with
  | false,true => JNull
  | true,true => JString "ChatGPT is temporarily unavailable; using this account’s cached model catalog"
  | false,false => JString "This ChatGPT connection does not advertise codex-auto-review; automatic review defaults to the task model unless a reviewer is selected explicitly"
  | true,false => JString "ChatGPT is temporarily unavailable; using this account’s cached model catalog. This connection does not advertise codex-auto-review; automatic review defaults to the task model unless a reviewer is selected explicitly" end).
Definition materialization_failure source := success (JObject [("rethrow",get source "force");("message",get source "message")]).
