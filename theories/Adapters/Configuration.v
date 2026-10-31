From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation CloudConfiguration.
From Selvedge.Adapters Require ProviderCatalog.
From Selvedge.Foundation Require Import Utf8.
From Selvedge.Programming Require Schema ArgumentDeclaration DeclarationFields.
From Selvedge.Foundation Require OptionList KeyedCollection.
From Selvedge.Features Require CompactionTypes CompactionCodec.
From Selvedge.Kernel Require Import Context.
From Selvedge.Kernel Require Domain.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Module D := ArgumentDeclaration.
Module F := DeclarationFields.
Module C := CompactionTypes.
Module CC := CompactionCodec.
Definition default_policy := C.Policy true 65 90 60000 C.Targets.empty eq_refl.
Definition compaction_defaults := CC.policy_json default_policy.
Definition defaulted (source : json) (key : string) (fallback : json) :=
  match field key source with Some value => value | None => fallback end.
Definition supported_provider := ProviderCatalog.supports_compaction.
Definition target_fields := [F.required "profile" (D.Value Schema.KText);F.required "window_tokens" (D.Natural 0 D.maximum_natural);
 F.optional "output_reserve_tokens" (D.Natural 0 D.maximum_natural);
 F.optional "cache_ttl_ms" (D.nullable (D.Natural 1 9007199254740991));
 F.optional "method" (D.Value (Schema.KEnum "auto" ["summary"]))].
Definition policy_fields := [F.optional "enabled" D.Boolean;F.optional "background_percent" (D.Value Schema.KNatural);
 F.optional "blocking_percent" (D.Value Schema.KNatural);F.optional "idle_lead_ms" (D.Natural 0 9007199254740991);
 F.optional "targets" (D.Array (D.Object target_fields))].
Definition supplied_value {A : Set} (value : option A) (fallback : A) := match value with Some value => value | None => fallback end.
Definition ttl_value (value : option (D.denote (D.nullable (D.Natural 1 9007199254740991)))) := match value with
 | Some (inl ttl) => proj1_sig ttl | None | Some (inr (inl _)) => 0
 | Some (inr (inr impossible)) => match impossible with end end.
Definition method_value (value : option (D.denote (D.Value (Schema.KEnum "auto" ["summary"])))) := match value with
 | Some value => if String.eqb (proj1_sig value) "auto" then Kernel.Compaction.Automatic else Kernel.Compaction.Summary
 | None => Kernel.Compaction.Automatic end.
Definition default_reserve window := N.min 8192 (window / 8).
Definition admit_target profiles lead (source : D.denote (D.Object target_fields)) : option C.target :=
 let '(profile,(window,(reserve,(ttl,(method,_))))) := proj1_sig source in
 let window := proj1_sig window in
 let reserve := match reserve with Some reserve => proj1_sig reserve | None => default_reserve window end in
 let ttl := ttl_value ttl in
 match profile,CC.decode_budget window reserve with
 | String head tail,Some budget =>
   if (negb (has profiles profile) || supported_provider (get profiles profile)) && (N.eqb ttl 0 || (lead <? ttl))
   then Some (C.Target (head,tail) budget ttl (method_value method)) else None
 | _,_ => None end.
Definition admit_policy config profiles := match field "compaction" config with
 | None => Some default_policy
 | Some source => match D.decode (D.Object policy_fields) source with
 | None => None
 | Some fields => let '(enabled,(background,(blocking,(lead,(targets,_))))) := proj1_sig fields in
   let background := supplied_value background (C.policy_background default_policy) in
   let blocking := supplied_value blocking (C.policy_blocking default_policy) in
   let lead := match lead with Some value => proj1_sig value | None => C.policy_idle_lead default_policy end in
   if blocking <? 100 then
     match OptionList.traverse (admit_target profiles lead) (supplied_value targets []) with
     | Some values => match C.Targets.admit values with
       | Some values => CC.make_policy (supplied_value enabled (C.policy_enabled default_policy)) background blocking lead values
       | None => None end
     | None => None end
   else None end end.
Definition compaction source := match admit_policy (get source "config") (get source "profiles") with
 | Some value => success (CC.policy_json value)
 (* DEFENSE: User settings can reverse thresholds, repeat a target key or select
    a budget/cache lease that cannot support the maintenance protocol. *)
 | None => err "Invalid compaction settings: require 1 <= background < blocking < 100, unique Responses-model targets, valid window/reserve headroom and cache TTL greater than idle lead" end.
Definition model_budget_fields := [F.required "context_window" (D.Natural 1 D.maximum_natural);
 F.optional "effective_context_window_percent" (D.Natural 1 100)].
Definition discovered_target (key : string) (profile : json) :=
 match key,D.decode (D.OpenObject model_budget_fields) (get profile "model_info") with
 | String head tail,Some fields => let '(window,(percent,_)) := proj1_sig fields in
   let percent := match percent with Some value => proj1_sig value | None => 100 end in
   let window := proj1_sig window * percent / 100 in
   option_map (fun budget => C.Target (head,tail) budget 0 Kernel.Compaction.Automatic)
     (CC.decode_budget window (default_reserve window))
 | _,_ => None end.
Definition runtime_target (targets : C.Targets.t) (entry : string * json) :=
 if supported_provider (snd entry) then
 match find (fun target => String.eqb (C.target_key target) (fst entry)) (C.Targets.values targets) with
 | Some target => Some target | None => discovered_target (fst entry) (snd entry) end
 else None.
Definition runtime_targets targets profiles := C.Targets.distinct
 (flat_map (fun entry => match runtime_target targets entry with Some value => [value] | None => [] end) profiles).
Definition compaction_runtime source :=
 let config := get source "config" in let profiles := get config "profiles" in
 match admit_policy config profiles with
 | Some policy => if forallb (fun target => has profiles (C.target_key target) && supported_provider (get profiles (C.target_key target)))
     (C.policy_targets policy)
   then success (CC.policy_json (C.with_targets
     (runtime_targets (C.policy_target_collection policy) (object_fields profiles)) policy))
   else err "Compaction target must resolve to an available responses or chatgpt model profile"
 | None => err "Compaction target must resolve to an available responses or chatgpt model profile" end.

Definition context_configured (definition : json) :=
  existsb (String.eqb (str (get definition "observer") "type")) ["config_text";"config_files"].
Definition context_setting (definition : json) := str (get definition "observer") "setting".
Definition context_fallback (definition : json) :=
  if String.eqb (str (get definition "observer") "type") "config_text" then JString "" else JArray [].
Definition base_defaults (instructions : string) :=
  JObject [("format",JString "selvedge-rocq-config-1");("host",JString "127.0.0.1");
    ("port",number 7421);("max_fork",number 4);("max_descendants",number 64);
    ("instructions",JString instructions);("profiles",JObject [("demo",JObject
      [("provider",JString "echo");("model",JString "echo")])]);
    ("mcp",JObject []);("plugins",JObject []);("skills",JArray []);
    ("remote",JBool false);("cloud",JBool false);("compaction",compaction_defaults)].
Definition defaults (definitions : json) (instructions : string) :=
  let base := base_defaults instructions in
  JObject (object_fields base ++ map (fun d => (context_setting d,context_fallback d))
    (filter (fun d => context_configured d && negb (has base (context_setting d))) (items definitions))).
Definition configuration_keys (definitions : json) : list string :=
  ["format";"host";"port";"max_fork";"max_descendants";"profiles";"chatgpt";"mcp";
   "plugins";"reasoning_evaluators";"chatgpt_plugin";"remote";"cloud";"compaction"] ++
  map context_setting (filter context_configured (items definitions)).
Definition configuration_head (definitions : json) (instructions : string) (source : json) :=
  let value := get source "value" in
  let unknown := unknown (configuration_keys definitions) (items (get value "fields")) in
  if negb (kind value "object") then invalid "configuration must be an object"
  else if negb (is_null unknown) then plan_error "TypeError"
    [literal (JString "Unknown configuration field: ");reference unknown]
  else if negb (equal_text (observed_field value "format") "selvedge-rocq-config-1")
    then plan_error "Error" [literal (JString "The configuration is not in the current Rocq format")]
  else plan_object (Some (get value "ref"))
    (map (fun entry => plan_field (fst entry)
      (selected (observed_field value (fst entry)) (snd entry))) (object_fields (defaults definitions instructions))).
Definition path_observation (value observed : json) :=
  kind value "string" && negb (Nat.eqb (List.length (items (get value "units"))) 0%nat) &&
  boolean_field observed "well_formed" && bound (get observed "bytes") 0 4096.
Fixpoint paths_observation (values observations : list json) :=
  match values,observations with
  | [],[] => true
  | value::rest,observed::tail => path_observation value observed && paths_observation rest tail
  | _,_ => false
  end.
Definition context_observation (definition value observed : json) :=
  if String.eqb (str (get definition "observer") "type") "config_text"
  then kind value "string" && boolean_field observed "well_formed" && bound (get observed "bytes") 0 Context.project_limit
  else kind value "array" && (N.of_nat (List.length (items (get value "items"))) <=? 64) &&
    paths_observation (items (get value "items")) (items (get observed "items")).
Definition context_transport_valid (definitions : json) (source : json) :=
  (* DEFENSE: The skill catalog requests a subset of sources; supplied definitions
     must still name declared sources rather than invent configuration fields. *)
  is_array (get source "definitions") &&
  forallb (fun requested => existsb (equal requested) (items definitions))
    (items (get source "definitions")) &&
  forallb (fun definition => negb (context_configured definition) ||
    context_observation definition (get (get source "values") (context_setting definition))
      (get (get source "observations") (context_setting definition)))
    (items (get source "definitions")).
Definition context_transport (definitions : json) (source : json) :=
  if context_transport_valid definitions source then literal JNull
  else invalid "context settings must contain bounded UTF-8 text or at most 64 bounded file paths".
Definition context_field (definitions : json) (source : json) :=
  let definition := get source "definition" in
  let identity := boolean_field source "identity" in
  let axis := if identity then "identity" else "fields" in
  let schema := find (fun f => String.eqb (str f "name") (str source "field"))
    (items (get definition axis)) in
  let canonical := existsb (fun d => equal d definition) (items definitions) in
  match schema,as_string (get source "value") with
  | Some schema,Some value =>
    if canonical && is_text (get source "field") && is_bool (get source "identity") &&
      Utf8.well_formed value && Utf8.no_nul value &&
      (negb (boolean_field schema "required") || negb (String.eqb value "")) &&
      (N.of_nat (String.length value) <=? if identity then 4096 else Context.project_limit)
    then success (JString value)
    else type_error "Context field must satisfy its definition and UTF-8 byte bound"
  | _,_ => type_error "Context field must satisfy its definition and UTF-8 byte bound"
  end.
Definition configuration_transport (definitions : json) (source : json) :=
  let value := get source "transport" in
  if negb (equal_text (get value "host") "127.0.0.1" || equal_text (get value "host") "::1")
  then invalid "The local server requires a loopback address"
  else if negb (observed_bound (get value "port") 0 65535) then invalid "port must be in 0..65535"
  else if negb (observed_bound (get value "max_fork") 1 4294967295) then invalid "max_fork must be in 1..4294967295"
  else if negb (observed_bound (get value "max_descendants") 1 4294967295) then invalid "max_descendants must be in 1..4294967295"
  else if negb (kind (get value "profiles") "object") then invalid "profiles must be an object"
  else context_transport definitions (get source "context").
Definition extension_keys (plugin : bool) : list string :=
  ["command";"args";"cwd";"env";"timeout_ms"] ++ if plugin then ["event_timeout_ms";"event_queue"] else [].
Definition extension_entry (plugin : bool) (name value : json) :=
  let prefix := if plugin then "plugin " else "MCP " in
  let failure := fun text => plan_error "TypeError" [literal (JString prefix);reference name;literal (JString text)] in
  let unknown := unknown (extension_keys plugin) (items (get value "fields")) in
  if negb (if plugin then plugin_name name else nonempty name)
  then if plugin then plan_error "TypeError" [literal (JString "Invalid plugin name: ");reference name]
       else invalid "MCP server name must be a nonempty string"
  else if negb (kind value "object") then failure " must be an object"
  else if negb (is_null unknown) then plan_error "TypeError"
    [literal (JString ("Unknown " ++ prefix));reference name;literal (JString " field: ");reference unknown]
  else if negb (nonempty (observed_field value "command")) then failure " command must be a nonempty string"
  else if negb (optional_strings (observed_field value "args")) then failure " arguments are invalid"
  else if negb (optional_text (observed_field value "cwd")) then failure " cwd must be a nonempty string"
  else if negb (optional_bound (observed_field value "timeout_ms") 100 1800000) then failure " timeout must be in 100..1800000"
  else if plugin && negb (optional_bound (observed_field value "event_timeout_ms") 100 60000) then failure " event timeout must be in 100..60000"
  else if plugin && negb (optional_bound (observed_field value "event_queue") 1 4096) then failure " event queue must be in 1..4096"
  else if negb (environment (observed_field value "env")) then failure " environment is invalid"
  else literal JNull.
Fixpoint extension_entries (plugin : bool) (entries : list json) :=
  match entries with [] => literal JNull | entry::rest =>
    let result := extension_entry plugin (get entry "key") (get entry "value") in
    if has_error result then result else extension_entries plugin rest end.
Definition extensions (source : json) :=
  if negb (kind (get source "mcp") "object") then invalid "mcp must be an object"
  else let result := extension_entries false (items (get (get source "mcp") "fields")) in
    if has_error result then result else
      if negb (kind (get source "plugins") "object") then invalid "plugins must be an object"
      else extension_entries true (items (get (get source "plugins") "fields")).

Record evaluator_provider := EvaluatorProvider {
  evaluator_name : string;
  evaluator_model : string;
  evaluator_endpoint : string
}.
Definition evaluator_providers := [
  EvaluatorProvider "vercel" "typesafe-ai/jev" "https://ai-gateway.vercel.sh/v1/evaluate";
  EvaluatorProvider "typesafe" "jev-latest" "https://api.typesafe.ai/v1/systemone";
  EvaluatorProvider "openrouter" "typesafe/jev-1.13" "https://openrouter.ai/api/alpha/decisions"].
Definition evaluator_defaults (provider : evaluator_provider) :=
  [("model",JString (evaluator_model provider));("endpoint",JString (evaluator_endpoint provider));
   ("api_key_env",JString "JEV_API_KEY");("timeout_ms",number 30000);("max_attempts",number 3)].
Definition evaluator_plan (source : json) :=
  let entry := get source "entry" in let provider := observed_field entry "provider" in
  let selected_provider := find (fun p => if nullish provider then String.eqb (evaluator_name p) "vercel"
    else equal_text provider (evaluator_name p)) evaluator_providers in
  if negb (identifier (get source "name")) then invalid "Invalid reasoning evaluator name"
  else if negb (fields_only ["provider";"model";"endpoint";"api_key_env";"timeout_ms";"max_attempts"] entry)
    then invalid "Invalid reasoning evaluator configuration fields"
  else match selected_provider with
  | None => invalid "Unknown Jev API provider"
  | Some provider =>
    if (negb (present (observed_field entry "model")) || identifier (observed_field entry "model")) &&
       (negb (present (observed_field entry "api_key_env")) || variable (observed_field entry "api_key_env"))
    then plan_object (Some (get entry "ref"))
      (plan_field "provider" (literal (JString (evaluator_name provider))) ::
        map (fun pair => plan_field (fst pair) (selected (observed_field entry (fst pair)) (snd pair)))
          (evaluator_defaults provider))
    else invalid "Invalid evaluator model or API-key environment variable"
  end.
Definition evaluator_endpoint_valid (url : json) :=
  String.eqb (str url "username") "" && String.eqb (str url "password") "" &&
  String.eqb (str url "hash") "" && String.eqb (str url "search") "" &&
  (String.eqb (str url "protocol") "https:" || (String.eqb (str url "protocol") "http:" &&
    existsb (String.eqb (str url "hostname")) ["localhost";"127.0.0.1";"[::1]"])).
Definition evaluator_entry (source : json) :=
  let entry := get source "entry" in
  if negb (evaluator_endpoint_valid (get source "url")) then invalid "The evaluator endpoint requires HTTPS except on loopback, without embedded credentials"
  else if optional_bound (observed_field entry "timeout_ms") 100 120000 &&
          optional_bound (observed_field entry "max_attempts") 1 3
  then literal JNull else invalid "Invalid evaluator deadline or same-provider retry bound".
(** Identifiers contain only ASCII code units. Their byte length is that same
    unit count, so a second host-supplied length cannot disagree with the name. *)
Definition effort_admissible value := identifier value && negb (equal_text value "auto") &&
 Nat.leb (List.length (items (get value "units"))) 64.
Definition effort := D.checked effort_admissible.
Module EffortEntries.
 Definition t := effort.
 Definition key := list N.
 Definition key_of (value : t) := map nat_value (items (get (proj1_sig value) "units")).
 Definition key_eq_dec := list_eq_dec N.eq_dec.
End EffortEntries.
Module Efforts := KeyedCollection.Make EffortEntries.
Definition effort_choices := D.checked (fun values : Efforts.t =>
 Nat.leb 1 (Efforts.size values) && Nat.leb (Efforts.size values) 16).
Definition effort_array := D.OpenObject [F.required "kind" (D.Const (JString "array"));F.required "items" (D.Array D.Any)].
Definition admit_efforts value : option effort_choices := match D.decode effort_array value with
 | Some fields => match OptionList.traverse (D.admit effort_admissible) (fst (snd (proj1_sig fields))) with
   | Some values => match Efforts.admit values with
     | Some values => D.admit (fun values => Nat.leb 1 (Efforts.size values) && Nat.leb (Efforts.size values) 16) values
     | None => None end
   | None => None end
 | None => None end.
Definition adaptive_failure := invalid "Adaptive reasoning requires an evaluator, bounded distinct efforts, an included baseline, a supported transport and a lease bound of 1..10".
Definition adaptive_policy (source : json) :=
  let value := get source "value" in
  if kind value "undefined" || kind value "null" || (kind value "boolean" && negb (boolean_field value "boolean"))
  then literal JNull
  else if negb (fields_only (map Schema.field_name Domain.reasoning_policy_schema) value)
  then invalid "Invalid adaptive reasoning configuration fields"
  else match admit_efforts (observed_field value "efforts") with
  | None => adaptive_failure
  | Some choices => let choices := Efforts.values (proj1_sig choices) in
    match find (fun choice => same_units (proj1_sig choice) (observed_field value "baseline")) choices with
    | None => adaptive_failure
    | Some baseline => if identifier (observed_field value "evaluator") &&
        (equal_text (observed_field value "transport") "configuration_update" || equal_text (observed_field value "transport") "request_effort") &&
        optional_bound (observed_field value "max_lease") 1 10
      then plan_object (Some (get value "ref")) [
        plan_field "max_lease" (selected (observed_field value "max_lease") (number 10));
        plan_field "efforts" (JObject [("array",JArray (map (fun choice => reference (proj1_sig choice)) choices))]);
        plan_field "baseline" (reference (proj1_sig baseline))]
      else adaptive_failure end end.
Definition remote (source : json) :=
  let value := get source "remote" in let url := get source "endpoint_observation" in
  match value with
  | JBool false => success value
  | _ => if plain_fields_only ["relay_url"] value && is_text (get value "relay_url") &&
    negb (String.eqb (str value "relay_url") "") &&
    String.eqb (str url "protocol") "https:" &&
    negb (String.eqb (str url "hostname") "") && String.eqb (str url "port") "" &&
    String.eqb (str url "username") "" && String.eqb (str url "password") "" &&
    String.eqb (str url "pathname") "/" && String.eqb (str url "search") "" && String.eqb (str url "hash") ""
    then success (JObject [("relay_url",get url "origin")])
    else type_error "remote requires only relay_url: an HTTPS origin on TCP 443 without credentials, path, query or fragment"
  end.

Definition call (definitions : json) (instructions : string)
  (operation : string) (source : json) : json :=
  if String.eqb operation "config.defaults" then success (defaults definitions instructions)
  else if String.eqb operation "config.configuration_head" then success (configuration_head definitions instructions source)
  else if String.eqb operation "config.configuration_transport" then success (configuration_transport definitions source)
  else if String.eqb operation "config.configuration_extensions" then success (extensions source)
  else if String.eqb operation "config.context_definitions" then success definitions
  else if String.eqb operation "config.context_transport" then success (context_transport definitions source)
  else if String.eqb operation "config.context_field" then context_field definitions source
  else if String.eqb operation "config.compaction" then compaction source
  else if String.eqb operation "config.compaction_runtime" then compaction_runtime source
  else if String.eqb operation "config.evaluators" then success
    (if String.eqb (str source "kind") "object" && bound (get source "count") 0 32
     then get source "positions" else invalid "reasoning_evaluators must be a bounded object")
  else if String.eqb operation "config.evaluator_plan" then success (evaluator_plan source)
  else if String.eqb operation "config.evaluator_entry" then success (evaluator_entry source)
  else if String.eqb operation "config.adaptive_policy" then success (adaptive_policy source)
  else if String.eqb operation "config.cloud" then CloudConfiguration.call source
  else if String.eqb operation "config.remote" then remote source
  else err ("Unknown host model operation: " ++ operation).
