From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation CloudConfiguration.
From Selvedge.Foundation Require Import Utf8.
From Selvedge.Kernel Require Import Context.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition compaction_defaults := JObject [("enabled",JBool true);
  ("background_percent",number 65);("blocking_percent",number 90);
  ("idle_lead_ms",number 60000);("targets",JArray [])].
Definition defaulted (source : json) (key : string) (fallback : json) :=
  match field key source with Some value => value | None => fallback end.
Definition compaction_value (source : json) :=
  defaulted (get source "config") "compaction" compaction_defaults.
Definition policy_field (source : json) (key : string) :=
  defaulted (compaction_value source) key (get compaction_defaults key).
Definition target_reserve (target : json) := defaulted target "output_reserve_tokens"
  (number (N.min 8192 (num target "window_tokens" / 8))).
Definition target_method (target : json) := defaulted target "method" (JString "auto").
Definition supported_provider (profile : json) :=
  existsb (String.eqb (str profile "provider")) ["responses";"chatgpt"].
Definition target_budget (legal_budget : N -> N -> bool) (target : json) :=
  bound (get target "window_tokens") 0 4294967295 && bound (target_reserve target) 0 4294967295 &&
  legal_budget (num target "window_tokens") (nat_value (target_reserve target)).
Definition target_value (target : json) := JObject [("profile",get target "profile");
  ("window_tokens",get target "window_tokens");("output_reserve_tokens",target_reserve target);
  ("cache_ttl_ms",get target "cache_ttl_ms");("method",target_method target)].
Definition target_valid (legal_budget : N -> N -> bool) (profiles : json) (lead : N)
  (seen : list string) (target : json) :=
  let profile := str target "profile" in let cache := get target "cache_ttl_ms" in
  plain_fields_only ["profile";"window_tokens";"output_reserve_tokens";"cache_ttl_ms";"method"] target &&
  negb (String.eqb profile "") && negb (existsb (String.eqb profile) seen) &&
  (negb (has profiles profile) || supported_provider (get profiles profile)) &&
  target_budget legal_budget target &&
  existsb (String.eqb (text (target_method target))) ["auto";"summary"] &&
  (is_null cache || (bound cache 1 9007199254740991 && (lead <? nat_value cache))).
Fixpoint targets_valid (legal_budget : N -> N -> bool) (profiles : json) (lead : N)
  (seen : list string) (targets : list json) :=
  match targets with [] => true | target::rest =>
    target_valid legal_budget profiles lead seen target &&
    targets_valid legal_budget profiles lead (str target "profile"::seen) rest end.
Definition thresholds_valid (source : json) :=
  plain_fields_only ["enabled";"background_percent";"blocking_percent";"idle_lead_ms";"targets"] (compaction_value source) &&
  is_bool (policy_field source "enabled") &&
  bound (policy_field source "background_percent") 1 98 &&
  bound (policy_field source "blocking_percent") 2 99 &&
  (nat_value (policy_field source "background_percent") <? nat_value (policy_field source "blocking_percent")) &&
  bound (policy_field source "idle_lead_ms") 0 9007199254740991.
Definition compaction_policy (source : json) (targets : list json) :=
  JObject [("enabled",policy_field source "enabled");
    ("background_percent",policy_field source "background_percent");
    ("blocking_percent",policy_field source "blocking_percent");
    ("idle_lead_ms",policy_field source "idle_lead_ms");("targets",JArray targets)].
Definition compaction (legal_budget : N -> N -> bool) (source : json) :=
  let targets := policy_field source "targets" in
  (* DEFENSE: User compaction settings can reverse thresholds or duplicate model targets. *)
  if thresholds_valid source && is_array targets &&
     targets_valid legal_budget (get source "profiles")
       (nat_value (policy_field source "idle_lead_ms")) [] (items targets)
  then success (compaction_policy source (map target_value (items targets)))
  else err "Invalid compaction settings: require 1 <= background < blocking < 100, unique Responses-model targets, valid window/reserve headroom and cache TTL greater than idle lead".
Fixpoint find_target (targets : list json) (key : string) :=
  match targets with [] => JNull | target::rest =>
    if String.eqb (str target "profile") key then target else find_target rest key end.
Definition discovered_target (key : string) (profile : json) :=
  let model := get profile "model_info" in
  let percent := defaulted model "effective_context_window_percent" (number 100) in
  target_value (JObject [("profile",JString key);
    ("window_tokens",number (num model "context_window" * nat_value percent / 100))]).
Definition runtime_target (targets : list json) (entry : string * json) :=
  let explicit := find_target targets (fst entry) in
  if is_null explicit then discovered_target (fst entry) (snd entry) else explicit.
Definition compaction_runtime (legal_budget : N -> N -> bool) (source : json) :=
  let config := get source "config" in let profiles := get config "profiles" in
  let targets := items (get (get config "compaction") "targets") in
  let settings := JObject [("config",config);("profiles",profiles)] in
  if thresholds_valid settings && is_array (policy_field settings "targets") &&
    targets_valid legal_budget profiles (nat_value (policy_field settings "idle_lead_ms")) [] targets &&
    forallb (fun target => has profiles (str target "profile") &&
    supported_provider (get profiles (str target "profile"))) targets then
    let resolved := map (runtime_target targets) (object_fields profiles) in
    let admitted := filter (fun target => supported_provider (get profiles (str target "profile")) &&
      target_budget legal_budget target) resolved in
    success (compaction_policy (JObject [("config",config);("profiles",profiles)]) admitted)
  else err "Compaction target must resolve to an available responses or chatgpt model profile".

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

(** Defaults are data, so provider admission and reconstruction consume one table. *)
Definition evaluator_providers := [
  ("vercel",[("model",JString "typesafe-ai/jev");("endpoint",JString "https://ai-gateway.vercel.sh/v1/evaluate")]);
  ("typesafe",[("model",JString "jev-latest");("endpoint",JString "https://api.typesafe.ai/v1/systemone")]);
  ("openrouter",[("model",JString "typesafe/jev-1.13");("endpoint",JString "https://openrouter.ai/api/alpha/decisions")])].
Definition evaluator_plan (source : json) :=
  let entry := get source "entry" in let provider := observed_field entry "provider" in
  let selected_provider := find (fun p => if nullish provider then String.eqb (fst p) "vercel"
    else equal_text provider (fst p)) evaluator_providers in
  if negb (identifier (get source "name")) then invalid "Invalid reasoning evaluator name"
  else if negb (fields_only ["provider";"model";"endpoint";"api_key_env";"timeout_ms";"max_attempts"] entry)
    then invalid "Invalid reasoning evaluator configuration fields"
  else match selected_provider with
  | None => invalid "Unknown Jev API provider"
  | Some (name,values) =>
    if (negb (present (observed_field entry "model")) || identifier (observed_field entry "model")) &&
       (negb (present (observed_field entry "api_key_env")) || variable (observed_field entry "api_key_env"))
    then plan_object (Some (get entry "ref"))
      (plan_field "provider" (literal (JString name)) ::
        map (fun pair => plan_field (fst pair) (selected (observed_field entry (fst pair)) (snd pair)))
          (values ++ [("api_key_env",JString "JEV_API_KEY");("timeout_ms",number 30000);("max_attempts",number 3)]))
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
Fixpoint effort_entries (efforts bytes seen : list json) :=
  match efforts,bytes with
  | [],[] => true
  | effort::rest,bytes::tail => identifier effort && negb (equal_text effort "auto") && bound bytes 0 64 &&
      negb (member_text seen effort) && effort_entries rest tail (effort::seen)
  | _,_ => false
  end.
Definition adaptive_policy (source : json) :=
  let value := get source "value" in let efforts := observed_field value "efforts" in
  let choices := items (get efforts "items") in
  if kind value "undefined" || kind value "null" || (kind value "boolean" && negb (boolean_field value "boolean"))
  then literal JNull
  else if negb (fields_only ["evaluator";"efforts";"baseline";"transport";"max_lease"] value)
  then invalid "Invalid adaptive reasoning configuration fields"
  else if identifier (observed_field value "evaluator") && kind efforts "array" &&
    (1 <=? N.of_nat (List.length choices)) && (N.of_nat (List.length choices) <=? 16) &&
    effort_entries choices (items (get source "bytes")) [] &&
    member_text choices (observed_field value "baseline") &&
    (equal_text (observed_field value "transport") "configuration_update" || equal_text (observed_field value "transport") "request_effort") &&
    optional_bound (observed_field value "max_lease") 1 10
  then plan_object (Some (get value "ref")) [
    plan_field "max_lease" (selected (observed_field value "max_lease") (number 10));
    plan_field "efforts" (JObject [("array",JArray (map reference choices))])]
  else invalid "Adaptive reasoning requires bounded distinct efforts, an included baseline and a valid lease".
Fixpoint unique_efforts (values seen : list json) :=
  match values with [] => [] | value::rest =>
    let effort := observed_field value "effort" in
    if member_text seen effort then unique_efforts rest seen
    else effort::unique_efforts rest (effort::seen) end.
Definition auto_preset (source : json) :=
  let descriptor := get source "descriptor" in
  let efforts := unique_efforts (items (get (observed_field descriptor "supported_reasoning_levels") "items")) [] in
  let baseline := observed_field descriptor "default_reasoning_level" in
  if equal_text (observed_field descriptor "slug") "gpt-6-astra" &&
    negb (Nat.eqb (List.length efforts) 0%nat) && negb (existsb (fun x => equal_text x "auto") efforts)
  then plan_object None [plan_field "evaluator" (literal (JString "jev"));
    plan_field "efforts" (JObject [("array",JArray (map reference efforts))]);
    plan_field "baseline" (reference (if member_text efforts baseline then baseline else hd JNull efforts));
    plan_field "transport" (literal (JString "configuration_update"));
    plan_field "max_lease" (literal (number 10))]
  else JObject [("undefined",JBool true)].
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

Definition call (definitions : json) (instructions : string) (legal_budget : N -> N -> bool)
  (operation : string) (source : json) : json :=
  if String.eqb operation "config.defaults" then success (defaults definitions instructions)
  else if String.eqb operation "config.configuration_head" then success (configuration_head definitions instructions source)
  else if String.eqb operation "config.configuration_transport" then success (configuration_transport definitions source)
  else if String.eqb operation "config.configuration_extensions" then success (extensions source)
  else if String.eqb operation "config.context_definitions" then success definitions
  else if String.eqb operation "config.context_transport" then success (context_transport definitions source)
  else if String.eqb operation "config.context_field" then context_field definitions source
  else if String.eqb operation "config.compaction" then compaction legal_budget source
  else if String.eqb operation "config.compaction_runtime" then compaction_runtime legal_budget source
  else if String.eqb operation "config.evaluators" then success
    (if String.eqb (str source "kind") "object" && bound (get source "count") 0 32
     then get source "positions" else invalid "reasoning_evaluators must be a bounded object")
  else if String.eqb operation "config.evaluator_plan" then success (evaluator_plan source)
  else if String.eqb operation "config.evaluator_entry" then success (evaluator_entry source)
  else if String.eqb operation "config.adaptive_policy" then success (adaptive_policy source)
  else if String.eqb operation "config.auto_preset" then success (auto_preset source)
  else if String.eqb operation "config.cloud" then CloudConfiguration.call source
  else if String.eqb operation "config.remote" then remote source
  else err ("Unknown host model operation: " ++ operation).
