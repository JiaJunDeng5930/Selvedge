From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects.
From Selvedge.Adapters Require Import Common ProviderCatalog BackendHistory BackendResponses BackendRequests BackendRetry ProviderCompaction OutputObservations.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition catalog := success (JArray ProviderCatalog.catalog).
Definition profile_head source :=
  let profile := get source "profile" in let key := str source "key" in
  if negb (nonempty (get source "key")) then err "profile key must be a nonempty string"
  else if negb (is_object profile) then err ("profile " ++ key ++ " must be an object")
  else match find (fun field => negb (existsb (String.eqb (fst field))
    (List.app connection_keys ["model";"api_key_env";"adaptive_reasoning"]))) (object_fields profile) with
  | Some field => err ("Unknown profile " ++ key ++ " field: " ++ fst field)
  | None => match backend profile with
    | None => err ("Unknown provider for " ++ key)
    | Some _ => if negb (nonempty (get profile "model")) then err ("model for " ++ key ++ " must be a nonempty string")
      else success profile end end.
Definition chosen_endpoint source := success (if uses_endpoint (get source "profile") then endpoint (get source "profile") else JNull).
Definition profile source :=
  let original := get source "profile" in
  let profile := if has original "timeout_ms" then original else set original "timeout_ms" (number 300000) in
  let adaptive := get source "adaptive" in let key := str source "key" in
  let web := ProviderCatalog.web profile in
  if is_object adaptive && (match connection_of profile with Some Offline => true | _ => false end) then
    err "The offline echo provider cannot select model reasoning effort"
  else if web && negb (existsb (String.eqb (str profile "model"))
    ["chatgpt-web/light";"chatgpt-web/medium";"chatgpt-web/high";"chatgpt-web/xhigh";"chatgpt-web/pro"])
    then err ("Invalid ChatGPT Web model for " ++ key)
  else if web && is_object adaptive then err "ChatGPT Web fixes effort at the root; adaptive reasoning is not supported"
  else let profile := if is_object adaptive then set profile "adaptive_reasoning" adaptive else without profile "adaptive_reasoning" in
  if negb (canonical_natural (get profile "timeout_ms") &&
    (100 <=? num profile "timeout_ms") && (num profile "timeout_ms" <=? 1800000))
    then err ("timeout for " ++ key ++ " must be in 100..1800000")
  else if negb (uses_endpoint profile) then success profile
  else let profile := set profile "endpoint" (endpoint profile) in
  if negb (nonempty (get profile "endpoint")) then err ("endpoint for " ++ key ++ " must be a nonempty string")
  else let url := get source "endpoint_observation" in
  if negb (is_object url) then err "Invalid URL"
  else if negb (existsb (String.eqb (str url "protocol")) ["http:";"https:"] &&
    String.eqb (str url "username") "" && String.eqb (str url "password") "" && String.eqb (str url "hash") "")
    then err ("Invalid endpoint for " ++ key)
  else if negb (String.eqb (str url "protocol") "https:" || existsb (String.eqb (str url "hostname"))
    ["localhost";"127.0.0.1";"[::1]"]) then err ("endpoint for " ++ key ++ " requires HTTPS except on loopback")
  else if web && negb (ends (str url "pathname") "/v1/responses" && String.eqb (str url "search") "")
    then err "ChatGPT Web endpoint must end in /v1/responses without a query"
  else let credential := ProviderCatalog.credential profile in
  if is_text credential && env_name (text credential) then success (set profile "api_key_env" credential)
  else err ("Invalid API key environment variable for " ++ key).
Definition authorization source :=
  (* DEFENSE: A frozen task can outlive an account switch in the host. *)
  let bound := get (get source "profile") "bound_account_id" in
  if negb (String.eqb (text bound) "") &&
    negb (JsonObjects.equivalent bound (get (get source "authorization") "account_id")) then
    err "This task belongs to a different ChatGPT account; restore that account or create a new task"
  else success JNull.
Definition credentials source :=
  (* DEFENSE: Environment credentials may be absent when the configured provider is first used. *)
  if is_text (get source "key") && negb (String.eqb (str source "key") "") then success (get source "key")
  else err ("Set " ++ display_field (get source "profile") "api_key_env" ++ " to use this provider").
Definition request_size source :=
  (* DEFENSE: Encoded history can exceed the host request budget before network IO. *)
  if canonical_natural (get (get source "limits") "frame_bytes") && canonical_natural (get source "bytes") &&
    (num source "bytes" <=? if wire_content_has_images (items (get (get source "request") "input"))
      then 33554432 else num (get source "limits") "frame_bytes")
  then success JNull else range_error "Provider request exceeds the configured limit".
Definition context_limit source := success (JBool
  (JsonObjects.equivalent (get source "status") (number 400) && String.eqb (str source "code") "context_length_exceeded" &&
   negb (boolean_field source "output_started"))).
Definition http_headers source :=
  if JsonObjects.equivalent (get source "status") (number 401) && boolean_field source "authorization" &&
    negb (boolean_field source "refreshed") then action "refresh"
  else if negb (boolean_field source "ok") then action "read_error"
  else if is_null (get source "content_type") || contains_text "text/event-stream" (lower_ascii (str source "content_type"))
    then action "continue"
  else success (JObject [("action",JString "failure");("message",JString "Provider did not return an SSE response");("cancel",JBool true)]).
Definition http_failure source := success (JObject [("action",JString "failure");
  ("message",JString ("Model request failed with HTTP " ++ display_field source "status"));
  ("recoverable",get (context_limit source) "value")]).
Definition support source :=
  let profile := get source "profile" in let effect := get source "effect" in
  if negb (account profile) && history_has_images (items (get effect "history")) then
    err "Image input requires a ChatGPT account model; this model backend does not support image input"
  else if negb (is_object profile && JsonObjects.equivalent (get profile "provider") (get (get effect "model") "provider")) then
    err "The frozen model provider is no longer configured"
  else match backend profile with
  | None => err "The frozen model provider is no longer configured"
  | Some backend =>
    if connection_live (provider_connection backend) then success (descriptor backend)
    else let kind := str effect "kind" in
      if String.eqb kind "board_text" then err "The offline echo profile cannot generate board descriptions; configure a model provider"
      else if String.eqb kind "approval" then err "The offline echo profile cannot review an approval; configure a model provider"
      else if String.eqb kind "context_compaction" then err "The offline echo profile cannot compact context; configure a model provider"
      else success (descriptor backend) end.
Definition echo source :=
  if history_has_images (items (get source "history")) then err "Image input is not supported by the offline echo backend"
  else let last := fold_left (fun fallback item => if String.eqb (str item "role") "user" then
    default (get item "content") (JString "Task resumed.") else fallback)
    (items (get source "history")) (JString "Task resumed.") in
  success (JArray [JObject [("type",JString "text");("part",number 0);
    ("text",JString ("[Offline demo] " ++ content_text_value last))]]).
Definition profile_catalog_entry key profile :=
  let levels := items (get (get profile "model_info") "supported_reasoning_levels") in
  JObject ([("key",JString key);("provider",get profile "provider");("name",get profile "model");
    ("reasoning_options",match levels with [] => JNull | _ => JObject [
      ("default",get (get profile "model_info") "default_reasoning_level");
      ("values",JArray (map (fun level => get level "effort") levels))] end)] ++
    optional (truthy (get profile "adaptive_reasoning")) "adaptive_reasoning" (get profile "adaptive_reasoning")).
Definition profile_catalog source := success (JArray (map (fun field => profile_catalog_entry (fst field) (snd field))
  (object_fields (get (get source "config") "profiles")))).
Definition call (select_history : list json -> string -> list json) operation source :=
  if String.eqb operation "backend.catalog" then catalog
  else if String.eqb operation "backend.profile_catalog" then profile_catalog source
  else if String.eqb operation "backend.profile_head" then profile_head source
  else if String.eqb operation "backend.endpoint" then chosen_endpoint source
  else if String.eqb operation "backend.profile" then profile source
  else if String.eqb operation "backend.prepare" then BackendRequests.prepare source
  else if String.eqb operation "backend.input" then BackendRequests.input select_history source
  else if String.eqb operation "backend.output" then BackendResponses.output source
  else if String.eqb operation "backend.observe_text_output" then OutputObservations.observe_text_output source
  else if String.eqb operation "backend.request" then BackendRequests.request select_history source
  else if String.eqb operation "backend.authorization" then authorization source
  else if String.eqb operation "backend.credentials" then credentials source
  else if String.eqb operation "backend.request_size" then request_size source
  else if String.eqb operation "backend.http_headers" then http_headers source
  else if String.eqb operation "backend.http_failure" then http_failure source
  else if String.eqb operation "backend.stream_step" then BackendResponses.stream_step source
  else if String.eqb operation "backend.stream_end" then BackendResponses.stream_end source
  else if String.eqb operation "backend.retry" then BackendRetry.retry source
  else if String.eqb operation "backend.context_limit" then context_limit source
  else if String.eqb operation "backend.support" then support source
  else if String.eqb operation "backend.echo" then echo source
  else if String.eqb operation "backend.image_content" then image_content source
  else if String.eqb operation "backend.image_materialized" then image_materialized source
  else if String.eqb operation "backend.image_request_budget" then image_request_budget source
  else if String.eqb operation "backend.compaction_model_request" then BackendRequests.measurement_request select_history source
  else if starts operation "backend.compaction_" then ProviderCompaction.call operation source
  else err ("Unknown backend operation: " ++ operation).
