From Selvedge.Programming Require Callback Variant.
From Selvedge.Programming Require InputRoute.
From Selvedge.Kernel Require Import ModelDeclarations.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Programming Require Import Schema.
From Selvedge.Foundation Require OptionList.
From Selvedge.Kernel Require Import Numbers Codec Compaction CompactionPlan ContextSelection.
From Selvedge.Features Require Import CompactionTypes.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition scope_fields (input : capture) :=
 Schema.of_tuple (Variant.request_body_fields ModelDeclarations.context_scope_request)
 [!Codec.model_json (captured_profile input)!].
Definition measure_fields owner (input : capture) scope validating :=
 Schema.of_tuple (Variant.request_body_fields ModelDeclarations.context_measure_request)
 [!Codec.model_json (captured_profile input);
  ContextSelection.target_messages (ContextSelection.history_json owner (captured_history input)) scope;
  true;scope;map Codec.tool_json (captured_tools input);Codec.settings_json (captured_settings input);
  captured_callable input;validating!].
Definition compact_fields (input : capture) (target : target) (scope : string) plan :=
 Schema.of_tuple (Variant.request_body_fields ModelDeclarations.context_compaction_request)
 [!Codec.model_json (captured_profile input);true;scope;method_name (target_method target);
  window_tokens (target_budget target);reserve_tokens (target_budget target);plan!].
Definition compact_values (id ticket : N) (input : capture) (target : target) (scope : string) plan :=
 Variant.Packet ModelDeclarations.context_compaction
   (Variant.request_fields ModelDeclarations.context_compaction_request id ticket
     (compact_fields input target scope plan)).
Definition compact_metadata id ticket input target scope :=
 match Variant.encode_packet (compact_values id ticket input target scope JNull) with
 | JObject fields => Json.remove_field "plan" fields | _ => [] end.
Definition compact_json id ticket input target progress scope :=
 Variant.encode_packet (compact_values id ticket input target scope (CompactionPlan.plan_json progress)).
Definition compact_metadata_bytes (id ticket : N) (input : capture) (target : target) (scope : string) :=
 N.of_nat (String.length (TextJson.render_json (JObject (compact_metadata id ticket input target scope)))) + 8.
Definition effect_packet (value : effect) := match value with
 | ArmClock deadline => Variant.pack ModelDeclarations.compaction_clock [!deadline!]
 | Cancel id ticket => Variant.pack ModelDeclarations.compaction_cancel [!id;ticket!] end.
Definition effect_fields value := Schema.encode_fields (Variant.packet_fields (effect_packet value)).
Definition effect_json value := Variant.encode_packet (effect_packet value).

Definition target_json (value : target) := JObject [
 ("profile", JString (target_key value)); ("window_tokens", number (window_tokens (target_budget value)));
 ("output_reserve_tokens", number (reserve_tokens (target_budget value)));
 ("cache_ttl_ms", if N.eqb (target_cache_ttl value) 0 then JNull else number (target_cache_ttl value));
 ("method", JString (method_name (target_method value)))].
Definition policy_json (value : policy) := JObject [
 ("enabled", JBool (policy_enabled value)); ("background_percent", number (policy_background value));
 ("blocking_percent", number (policy_blocking value)); ("idle_lead_ms", number (policy_idle_lead value));
 ("targets", JArray (map target_json (policy_targets value)))].
Definition job_name (value : job) := match value with NoJob => "idle"
 | WaitingForResource _ => "waiting_for_resource" | AwaitingContext _ _ _ => "observing_context" | Resuming _ _ => "waiting"
 | Preparing _ => "preparing" | Compacting _ => "compacting" | Validating _ => "validating" end.
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
Definition decode_targets values := match OptionList.traverse decode_target values with
 | Some values => Targets.admit values | None => None end.
Definition make_policy (enabled : bool) (background blocking lead : N) (targets : Targets.t) : option policy.
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
Definition outcome_from_values (completed : bool)
 (received : Callback.decoded (ModelDeclarations.Compaction completed)) : option completion :=
 let '(existT _ ok (address,values)) := received in
 let id := Schema.head address in let ticket := Schema.head (Schema.tail address) in
 (if ok as ok return DeclarationFields.values (Callback.payload (ModelDeclarations.Compaction completed) ok) -> option completion
  then fun values => let result := JObject (fst values) in
    if completed then Some (Completed id ticket result false)
    else option_map (MeasuredInput id ticket) (decode_inspection false result)
  else fun values => let message := proj1_sig (fst (proj1_sig (fst values))) in
    if completed then Some (Completed id ticket (JObject [("message",JString message)]) true)
    else Some (MeasuredInput id ticket (InspectionFailed message))) values.
Definition completion_inputs : list (InputRoute.t completion) := [
 InputRoute.object "compaction_configure" [Field "policy" KJson;Field "now" KNatural]
   (fun fields => option_map (fun policy => Configure policy (head (tail fields))) (decode_policy (head fields)));
 InputRoute.object "compaction_clock" [Field "now" KNatural] (fun fields => Some (Clock (head fields)));
 InputRoute.object "compaction_activity"
   [Field "task_id" KNatural;Field "source_length" KNatural;Field "now" KNatural;Field "scope" KText]
   (fun fields => Some (Activity (head fields) (head (tail fields)) (head (tail (tail fields))) (head (tail (tail (tail fields))))));
 InputRoute.callback (ModelDeclarations.Compaction false) (outcome_from_values false);
 InputRoute.callback (ModelDeclarations.Compaction true) (outcome_from_values true)].
