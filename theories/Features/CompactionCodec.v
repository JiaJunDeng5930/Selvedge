From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Import Numbers Codec Compaction CompactionPlan ContextSelection.
From Selvedge.Features Require Import CompactionTypes.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition compact_metadata (id ticket : N) (input : capture) (target : target) (scope : string) := [
 ("kind", JString "context_compaction"); ("task_id", number id); ("ticket", number ticket);
 ("model", Codec.model_json (captured_profile input)); ("context_selected", JBool true);
 ("context_scope", JString scope); ("method", JString (method_name (target_method target)));
 ("window_tokens", number (window_tokens (target_budget target)));
 ("output_reserve_tokens", number (reserve_tokens (target_budget target)))].
Definition compact_json (id ticket : N) (input : capture) (target : target) (progress : compaction_state) (scope : string) :=
 JObject (compact_metadata id ticket input target scope ++ [("plan", CompactionPlan.plan_json progress)])%list.
Definition compact_metadata_bytes (id ticket : N) (input : capture) (target : target) (scope : string) :=
 N.of_nat (String.length (TextJson.render_json (JObject (compact_metadata id ticket input target scope)))) + 8.
Definition effect_json (value : effect) := match value with
 | Scope id ticket input => JObject [("kind", JString "context_scope"); ("task_id", number id);
   ("ticket", number ticket); ("model", Codec.model_json (captured_profile input))]
 | Measure id ticket input scope validating => JObject [
   ("kind", JString "context_measure"); ("task_id", number id); ("ticket", number ticket);
   ("model", Codec.model_json (captured_profile input));
   ("history", JArray (ContextSelection.target_messages (ContextSelection.history_json id (captured_history input)) scope));
   ("context_selected", JBool true); ("context_scope", JString scope);
   ("tools", JArray (map Codec.tool_json (captured_tools input)));
   ("settings", Codec.settings_json (captured_settings input));
   ("callable", JArray (map JString (captured_callable input))); ("validating", JBool validating)]
 | Compact id ticket input target progress scope => compact_json id ticket input target progress scope
 | ArmClock deadline => JObject [("kind", JString "compaction_clock"); ("deadline", number deadline)]
 | Cancel id ticket => JObject [("kind", JString "compaction_cancel"); ("task_id", number id); ("ticket", number ticket)] end.

Definition target_json (value : target) := JObject [
 ("profile", JString (target_key value)); ("window_tokens", number (window_tokens (target_budget value)));
 ("output_reserve_tokens", number (reserve_tokens (target_budget value)));
 ("cache_ttl_ms", number (target_cache_ttl value)); ("method", JString (method_name (target_method value)))].
Definition policy_json (value : policy) := JObject [
 ("enabled", JBool (policy_enabled value)); ("background_percent", number (policy_background value));
 ("blocking_percent", number (policy_blocking value)); ("idle_lead_ms", number (policy_idle_lead value));
 ("targets", JArray (map target_json (policy_targets value)))].
Definition job_name (value : job) := match value with NoJob => "idle" | Resuming _ _ => "waiting"
 | Preparing _ _ _ _ => "preparing" | Compacting _ _ _ _ _ => "compacting" | Validating _ _ _ _ _ _ => "validating" end.
Definition entry_json (id : N) (value : entry) := JObject [
 ("task_id", number id); ("state", JString (job_name (entry_job value)));
 ("useful_revision", number (entry_useful value)); ("maintained_revision", number (entry_maintained value));
 ("cache_deadline", number (entry_cache_deadline value))].
Definition state_json (value : state) := JObject [("policy", policy_json (maintenance_policy value));
 ("tasks", JArray (map (fun pair => entry_json (fst pair) (snd pair)) (maintenance_entries value)))].

Definition decode_budget (window reserve : N) : option token_budget :=
 if Compaction.legal_budget window reserve then
 Some (TokenBudget (reserve - minimum_reserve) (window - N.max minimum_window (4 * reserve))) else None.
Definition decode_target (value : json) :=
 let ttl := match field "cache_ttl_ms" value with
   | None | Some JNull => Some 0
   | Some supplied => natural supplied
   end in
 match string_field "profile" value, natural_field "window_tokens" value, natural_field "output_reserve_tokens" value,
       ttl, string_field "method" value with
 | Some (String head tail), Some window, Some reserve, Some ttl, Some method =>
   match decode_budget window reserve, method with
   | Some budget, "auto" => Some (Target (head, tail) budget ttl Automatic)
   | Some budget, "summary" => Some (Target (head, tail) budget ttl Summary)
   | _, _ => None end
 | _, _, _, _, _ => None end.
Fixpoint decode_targets (values : list json) : option (list target) := match values with
 | [] => Some [] | value :: rest => match decode_target value, decode_targets rest with
   Some target, Some targets => Some (target :: targets) | _, _ => None end end.
Definition make_policy (enabled : bool) (background blocking lead : N) (targets : list target) : option policy.
Proof.
 destruct ((0 <? background) && (background <? blocking) && (blocking <=? 100)) eqn:valid.
 - exact (Some (Policy enabled background blocking lead targets valid)).
 - exact None.
Defined.
Definition decode_policy (value : json) := match bool_field "enabled" value,
 natural_field "background_percent" value, natural_field "blocking_percent" value,
 natural_field "idle_lead_ms" value, array_field "targets" value with
 | Some enabled, Some background, Some blocking, Some lead, Some targets =>
   match decode_targets targets with Some targets => make_policy enabled background blocking lead targets | None => None end
 | _, _, _, _, _ => None end.
Definition decode_inspection (error : bool) (value : json) : option inspection :=
 if error then option_map InspectionFailed (string_field "message" value) else
 match string_field "scope" value with
 | None => None
 | Some scope => match field "input_tokens" value, field "window_tokens" value, field "output_reserve_tokens" value with
   | None, None, None => Some (ScopeObserved scope)
   | Some tokens, Some window, Some reserve => match natural tokens, natural window, natural reserve with
     | Some tokens, Some window, Some reserve => option_map (InputMeasured scope tokens) (decode_budget window reserve)
     | _, _, _ => None end
   | _, _, _ => None end end.
Definition decode_configure (value : json) : option completion :=
 match field "policy" value, natural_field "now" value with
 | Some value, Some now => option_map (fun policy => Configure policy now) (decode_policy value) | _, _ => None end.
Definition decode_activity (value : json) : option completion := match natural_field "task_id" value,
 natural_field "source_length" value, natural_field "now" value, string_field "scope" value with
 | Some id, Some source, Some now, Some scope => Some (Activity id source now scope) | _, _, _, _ => None end.
Definition decode_outcome (completed : bool) (value : json) : option completion :=
 match natural_field "task_id" value, natural_field "ticket" value, bool_field "error" value, field "result" value with
 | Some id, Some ticket, Some error, Some (JObject fields) =>
   if completed then
     if error then match string_field "message" (JObject fields) with Some _ => Some (Completed id ticket (JObject fields) error) | None => None end
     else Some (Completed id ticket (JObject fields) error)
   else option_map (MeasuredInput id ticket) (decode_inspection error (JObject fields))
 | _, _, _, _ => None end.
Definition completion_decoders : list (string * (json -> option completion)) := [
 ("compaction_configure", decode_configure);
 ("compaction_clock", fun value => option_map Clock (natural_field "now" value));
 ("compaction_activity", decode_activity);
 ("compaction_measured", decode_outcome false);
 ("compaction_completed", decode_outcome true)].
Definition completion_decoder (kind : string) :=
 option_map (@snd string (json -> option completion))
  (find (fun pair => String.eqb kind (fst pair)) completion_decoders).
Definition decode_completion (kind : string) (value : json) :=
 match completion_decoder kind with Some decode => decode value | None => None end.
