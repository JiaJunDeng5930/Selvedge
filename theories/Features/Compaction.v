From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects TextJson.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Capabilities Compaction CompactionPlan ContextSelection Limits Scheduler Reasoning TicketedRequest.
From Selvedge.Features Require Import Domain State CompactionTypes CompactionCodec.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition registry (value : Selvedge.Kernel.State.world) := Selvedge.Features.Domain.feature_compaction (Selvedge.Kernel.State.world_features value).
Definition store (replacement : Selvedge.Features.CompactionTypes.state) (value : Selvedge.Kernel.State.world) :=
 Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_compaction replacement (Selvedge.Kernel.State.world_features value)) value.
Definition find_entry (id : N) (value : Selvedge.Features.CompactionTypes.state) :=
 option_map (@snd N entry) (find (fun pair => N.eqb (fst pair) id) (maintenance_entries value)).
Definition current_entry (id : N) (value : Selvedge.Features.CompactionTypes.state) := match find_entry id value with Some entry => entry | None => empty_entry end.
Definition with_entry (id : N) (entry : entry) (value : Selvedge.Features.CompactionTypes.state) :=
 set maintenance_entries (fun entries => (id, entry) :: filter (fun pair => negb (N.eqb (fst pair) id)) entries) value.
Definition acknowledged (accepted : bool) (value : Selvedge.Kernel.State.world) (effects : list Selvedge.Kernel.State.effect) :=
 Selvedge.Kernel.State.accept (JObject [("accepted", JBool accepted)]) value effects.
Definition commit (id : N) (entry : entry) (value : Selvedge.Kernel.State.world) (effects : list Selvedge.Features.CompactionTypes.effect) :=
 acknowledged true (store (with_entry id entry (registry value)) value) (map Selvedge.Kernel.State.MaintainContext effects).
Definition configured_target (task : task) (value : Selvedge.Features.CompactionTypes.state) :=
 find (fun target => String.eqb (target_key target) (profile_key (task_current_profile task)))
  (policy_targets (maintenance_policy value)).
Definition enabled_target (task : task) (value : Selvedge.Features.CompactionTypes.state) :=
 if policy_enabled (maintenance_policy value) then configured_target task value else None.
Definition running (task : task) := match task_lifecycle task with Running _ _ => true | _ => false end.
Definition alive (task : task) := match task_lifecycle task with Archived _ => false | _ => true end.
Definition idle (task : task) := match task_activity task, task_operations task with Idle, [] => true | _, _ => false end.
Definition capture_task := TicketedRequest.Scoped.capture_task.
Definition input_description := TicketedRequest.Scoped.input_description.
Definition same_description := TicketedRequest.Scoped.same_description.
Definition same_history (before after : list message) :=
 JsonObjects.equivalent (JArray (ContextSelection.history_json 0 before)) (JArray (ContextSelection.history_json 0 after)).
Definition same_input (input : capture) (task : task) (value : Selvedge.Kernel.State.world) :=
 same_description input task value && same_history (captured_history input) (task_history task).
Definition relevant (input : capture) (task : task) (value : Selvedge.Kernel.State.world) :=
 alive task && same_description input task value && ContextSelection.history_extends (captured_history input) (task_history task).
Definition useful (history : list message) := N.of_nat (List.length (filter (fun message => match message with
 | ContextReplacement _ | ReasoningRecord _ _ _ _ | FailureMessage _ => false | _ => true end) history)).
Definition job_pending (value : job) := match value with NoJob => false | _ => true end.
Definition job_ticket (value : job) := match value with
 | AwaitingContext ticket _ _ | Preparing ticket _ _ _ | Compacting ticket _ _ _ _ | Validating ticket _ _ _ _ _ => Some ticket | _ => None end.
Definition measurement_ticket (value : measurement) := match value with Measuring ticket _ _ => Some ticket | _ => None end.
Definition cancellations (id : N) (entry : entry) :=
 ((match measurement_ticket (entry_measurement entry) with Some ticket => [Cancel id ticket] | None => [] end) ++
 (match job_ticket (entry_job entry) with Some ticket => [Cancel id ticket] | None => [] end))%list.
Definition pending_cancellations (state : Selvedge.Features.CompactionTypes.state) :=
 flat_map (fun pair => cancellations (fst pair) (snd pair)) (maintenance_entries state).
Definition must_wait (policy : policy) (tokens : N) (budget : token_budget) :=
 (policy_enabled policy && (window_tokens budget * policy_blocking policy <=? tokens * 100)) ||
 negb (tokens + reserve_tokens budget <=? window_tokens budget).
Definition selected_reason (policy : policy) (tokens : N) (budget : token_budget) :=
 if must_wait policy tokens budget then Some Blocking
 else if policy_enabled policy && (window_tokens budget * policy_background policy <=? tokens * 100) then Some Background else None.
Definition fresh (observation : measurement) (task : task) (value : Selvedge.Kernel.State.world) := match observation with
 | Measured input _ _ _ | Oversized input _ _ | MeasurementFailed input => same_input input task value | _ => false end.
Definition with_measurement (measurement : measurement) (value : entry) := set entry_measurement (fun _ => measurement) value.
Definition with_job (job : job) (value : entry) := set entry_job (fun _ => job) value.
Definition failed (id : N) (task : task) (entry : entry) (reason : string) (value : Selvedge.Kernel.State.world) :=
 let task := with_activity (match task_activity task with ReadyForModel => Idle | phase => phase end)
  (set task_history (fun history => (history ++ [FailureMessage ("Context compaction: " ++ reason)])%list) task) in
 let entry := set entry_attempted (fun _ => useful (task_history task))
  (set entry_cache_deadline (fun _ => 0) (with_job NoJob (with_measurement (MeasurementFailed (capture_task task value)) entry))) in
 commit id entry (Selvedge.Kernel.State.put_task id task value) [].
Definition provider_job_ticket (value : job) := match value with
 | AwaitingContext _ _ _ => None | _ => job_ticket value end.
Definition with_observation (input : option capture) (value : entry) := set entry_observation (fun _ => input) value.
Definition resume_activity (resume_model : bool) := if resume_model then ReadyForModel else Idle.
Definition wait_for_context (id : N) (purpose : option reason) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 match Selvedge.Kernel.State.find_task id value with
 | None => Selvedge.Kernel.State.ignored value
 | Some task =>
   match TicketedRequest.Scoped.maintenance_context id purpose entry value with
   | Some request => TicketedRequest.Scoped.maintenance_observe request
   | None =>
     (* A quiet external call can leave an active task idle without publishing
        its result. Retain a requested compaction until that prefix closes;
        resume recaptures the result or announcement before asking for a summary. *)
     let waiting := if TicketedRequest.Scoped.resources_available task value then
       match purpose with Some purpose => Resuming (capture_task task value) purpose | None => NoJob end
       else WaitingForResource purpose in
     commit id (with_observation None (with_measurement Unmeasured
       (with_job waiting entry))) value []
   end end.
Definition run_request (id : N) (request : TicketedRequest.Scoped.maintenance_action) (value : Selvedge.Kernel.State.world) :=
 match TicketedRequest.Scoped.feature (TicketedRequest.Scoped.MaintainRequest id request) value with
 | Some admitted => TicketedRequest.Scoped.feature_issue admitted
 | None => let '(purpose,entry) := match request with
   | TicketedRequest.Scoped.ScopeRequest _ purpose entry
   | TicketedRequest.Scoped.MeasureRequest _ purpose _ _ entry => (purpose,entry)
   | TicketedRequest.Scoped.ValidationScopeRequest _ purpose _ _ entry
   | TicketedRequest.Scoped.CompactRequest _ purpose _ _ _ entry => (Some purpose,entry) end in
   wait_for_context id purpose entry value end.
Definition begin_scope (id : N) (input : capture) (purpose : option reason) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 run_request id (TicketedRequest.Scoped.ScopeRequest input purpose entry) value.
Definition dispatch_compact (id : N) (task : task) (input : capture) (purpose : reason) (target : target)
 (progress : compaction_state) (scope : string) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 let ticket := world_next_ticket value in
 let limit := Limits.frame_bytes / 4 in
 let available := limit - Selvedge.Features.CompactionCodec.compact_metadata_bytes id ticket input target scope in
 match Selvedge.Kernel.CompactionPlan.fit_transport progress available with
 | Some fitted =>
   if Selvedge.Kernel.CompactionPlan.transport_fits fitted available &&
     (N.of_nat (String.length (TextJson.render_json (Selvedge.Features.CompactionCodec.compact_json id ticket input target fitted scope))) <=? limit)
   then run_request id (TicketedRequest.Scoped.CompactRequest input purpose target fitted scope entry) value
   else failed id task entry "The configured compaction request exceeds the transport budget" value
 | None => failed id task entry "Compaction history is not valid UTF-8" value end.
Definition start (id : N) (task : task) (input : capture) (purpose : reason) (target : target)
 (scope : string) (tokens : N) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 let messages := ContextSelection.history_json id (captured_history input) in
 (* Argument text is a transport representation. Image selection observes the
    original member AST through the shared serializer's public call projection. *)
 let semantic := map (Codec.public_message_json id) (captured_history input) in
 let images := Selvedge.Kernel.CompactionPlan.contains_image
   (JArray (ContextSelection.dialogue (ContextSelection.target_messages semantic scope))) ||
   Selvedge.Kernel.CompactionPlan.contains_image
   (JArray (ContextSelection.dialogue (ContextSelection.raw_messages semantic))) in
 match Selvedge.Kernel.CompactionPlan.start_with_images images (JArray (ContextSelection.dialogue (ContextSelection.target_messages messages scope)))
   (JArray (ContextSelection.dialogue (ContextSelection.raw_messages messages)))
   (profile_provider (captured_profile input)) (target_method target) tokens
   (window_tokens (target_budget target)) (reserve_tokens (target_budget target)) with
 | Some progress => dispatch_compact id task input purpose target progress scope entry value
 | None => failed id task entry "Compaction history is not valid UTF-8" value end.
Definition force_portable (id : N) (task : task) (scope : string) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 match configured_target task (registry value) with
 | None => failed id task entry "The selected profile does not support compaction" value
 | Some target =>
   let input := capture_task task value in
   let entry := with_measurement (Oversized input scope (target_budget target)) entry in
   match entry_job entry with
   | Compacting _ _ _ _ _ => commit id entry value []
   | _ => if ContextSelection.closed_prefix (task_history task) then
       start id task input Blocking (set target_method (fun _ => Summary) target) scope (window_tokens (target_budget target)) entry value
     else commit id (with_job (Resuming input Blocking) entry) value [] end end.
Definition measured_call (id : N) (task : task) (input : capture) (scope : string) (purpose : option reason)
 (candidate : option (artifact * list message)) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 let request:=TicketedRequest.Scoped.MeasureRequest input purpose candidate scope entry in
 let effect:=snd (TicketedRequest.Scoped.maintenance_build id (world_next_ticket value) request) in
 if N.of_nat (String.length (TextJson.render_json (Selvedge.Features.CompactionCodec.effect_json effect))) <=? Limits.frame_bytes / 4
 then run_request id request value
 else force_portable id task scope entry value.
Definition begin_validation (id : N) (task : task) (input : capture) (purpose : reason) (candidate : artifact)
 (entry : entry) (value : Selvedge.Kernel.State.world) :=
 if relevant input task value then
 let preview := ContextSelection.adopt (captured_history input) candidate (task_history task) in
 run_request id (TicketedRequest.Scoped.ValidationScopeRequest input purpose candidate preview entry) value
 else commit id (with_job NoJob entry) value [].
Definition finish_measure (id : N) (task : task) (input : capture) (scope : string) (tokens : N) (budget : token_budget)
 (entry : entry) (value : Selvedge.Kernel.State.world) :=
 let current := same_input input task value in
 let entry := with_measurement (if current then Measured input scope tokens budget else Unmeasured) entry in
 if current && negb (job_pending (entry_job entry)) && ContextSelection.closed_prefix (task_history task) then
 match selected_reason (maintenance_policy (registry value)) tokens budget, configured_target task (registry value) with
 | Some purpose, Some target => if (entry_attempted entry <? useful (task_history task)) ||
     must_wait (maintenance_policy (registry value)) tokens budget
   then start id task input purpose target scope tokens entry value else commit id entry value []
 | _, _ => commit id entry value [] end else commit id entry value [].
Definition finish_validation (id : N) (task : task) (input : capture) (purpose : reason) (candidate : artifact)
 (preview : list message) (scope : string) (tokens : N) (budget : token_budget) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 if relevant input task value && ContextSelection.consumes candidate scope then
 if same_history preview (ContextSelection.adopt (captured_history input) candidate (task_history task)) then
 if (tokens + reserve_tokens budget <=? window_tokens budget) &&
    negb (match candidate with NativeArtifact _ _ _ _ _ =>
     policy_enabled (maintenance_policy (registry value)) &&
       (window_tokens budget * policy_blocking (maintenance_policy (registry value)) <=? tokens * 100)
     | _ => false end) then
 let task := set task_history (fun _ => preview) task in
 let entry := set entry_maintained (N.max (useful (captured_history input)))
   (set entry_attempted (N.max (useful (captured_history input)))
   (with_job NoJob (with_measurement (Measured (capture_task task value) scope tokens budget) entry))) in
 commit id entry (Selvedge.Kernel.State.put_task id task value) []
 else force_portable id task scope entry value
 else begin_validation id task input purpose candidate entry value
 else commit id (with_job NoJob entry) value [].

Definition resume (job : job) := match job with
 | NoJob | AwaitingContext _ _ _ => NoJob
 | WaitingForResource purpose => WaitingForResource purpose
 | Resuming input purpose | Preparing _ input purpose _
 | Compacting _ input purpose _ _ | Validating _ input purpose _ _ _ => Resuming input purpose end.
Definition recover_entry (entry : entry) := with_observation None
 (with_measurement Unmeasured (with_job (resume (entry_job entry)) entry)).
Definition clear_entry (task : task) (entry : entry) :=
 set entry_attempted (fun _ => useful (task_history task))
  (set entry_cache_deadline (fun _ => 0) (with_measurement Unmeasured (with_job NoJob entry))).
Definition cancel (id : N) (task : task) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 commit id (clear_entry task entry) value (cancellations id entry).
Definition restart (id : N) (task : task) (purpose : reason) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 begin_scope id (capture_task task value) (Some purpose) (with_job NoJob entry) value.
Definition ordinary_inspected (id : N) (task : task) (ticket : N) (input : capture) (stage : inspection_stage)
 (outcome : inspection) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 match outcome, stage with
 | InspectionFailed message, _ => failed id task entry message value
 | ScopeObserved scope, InspectScope => measured_call id task input scope None None entry value
 | ScopeObserved scope, InspectCount expected =>
   if String.eqb expected scope then failed id task entry "The input meter returned a scope without a token measurement" value
   else measured_call id task input scope None None entry value
 | InputMeasured scope tokens budget, InspectCount expected =>
   if String.eqb expected scope then finish_measure id task input scope tokens budget entry value
   else measured_call id task input scope None None entry value
 | InputMeasured _ _ _, InspectScope => failed id task entry "The scope observation returned an unexpected token measurement" value end.
Definition preparing_inspected (id : N) (task : task) (input : capture) (purpose : reason) (stage : inspection_stage)
 (outcome : inspection) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 if relevant input task value then match outcome, stage with
 | InspectionFailed message, _ => failed id task entry message value
 | ScopeObserved scope, InspectScope => measured_call id task input scope (Some purpose) None entry value
 | ScopeObserved scope, InspectCount expected =>
   if String.eqb expected scope then failed id task entry "The input meter returned a scope without a token measurement" value
   else measured_call id task input scope (Some purpose) None entry value
 | InputMeasured scope tokens budget, InspectCount expected =>
   if String.eqb expected scope then match configured_target task (registry value) with
   | None => failed id task entry "The selected profile does not support compaction" value
   | Some target => start id task input purpose target scope tokens
     (with_measurement (if same_input input task value then Measured input scope tokens budget else Unmeasured) entry) value end
   else measured_call id task input scope (Some purpose) None entry value
 | InputMeasured _ _ _, InspectScope => failed id task entry "The scope observation returned an unexpected token measurement" value end
 else commit id (with_job NoJob entry) value [].
Definition validation_input (id : N) (task : task) (input : capture) (purpose : reason) (candidate : artifact)
 (preview : list message) (scope : string) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 if ContextSelection.consumes candidate scope then
 measured_call id task input scope (Some purpose) (Some (candidate,preview)) entry value
 else restart id task purpose entry value.
Definition validation_inspected (id : N) (task : task) (input : capture) (purpose : reason) (candidate : artifact)
 (preview : list message) (stage : inspection_stage) (outcome : inspection) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 if relevant input task value then match outcome, stage with
 | InspectionFailed message, _ => failed id task entry message value
 | ScopeObserved scope, InspectScope => validation_input id task input purpose candidate preview scope entry value
 | ScopeObserved scope, InspectCount expected =>
   if String.eqb expected scope then failed id task entry "The input meter returned a scope without a token measurement" value
   else validation_input id task input purpose candidate preview scope entry value
 | InputMeasured scope tokens budget, InspectCount expected =>
   if String.eqb expected scope then finish_validation id task input purpose candidate preview scope tokens budget entry value
   else validation_input id task input purpose candidate preview scope entry value
 | InputMeasured _ _ _, InspectScope => failed id task entry "The scope observation returned an unexpected token measurement" value end
 else commit id (with_job NoJob entry) value [].
Definition measurement_result (id ticket : N) (task : task) (outcome : inspection) (entry : entry) (value : Selvedge.Kernel.State.world) : option Selvedge.Kernel.State.decision :=
 match entry_job entry with
 | Validating expected input purpose candidate preview stage =>
   if N.eqb ticket expected then Some (validation_inspected id task input purpose candidate preview stage outcome entry value) else None
 | Preparing expected input purpose stage =>
   if N.eqb ticket expected then Some (preparing_inspected id task input purpose stage outcome entry value) else None
 | _ => match entry_measurement entry with
   | Measuring expected input stage => if N.eqb ticket expected then Some (ordinary_inspected id task ticket input stage outcome entry value) else None
   | _ => None end end.
Definition compact_result (id ticket : N) (task : task) (result : json) (error : bool) (entry : entry) (value : Selvedge.Kernel.State.world) : option Selvedge.Kernel.State.decision :=
 match entry_job entry with
 | Compacting expected input purpose progress scope =>
   if N.eqb ticket expected then Some (
     if relevant input task value then
     if error then failed id task entry (match string_field "message" result with Some message => message
       | None => "The failed compaction outcome requires a message" end) value
     else if bool_default "scope_changed" result false then restart id task purpose entry value
     else match Selvedge.Kernel.CompactionPlan.receive progress result with
     | Selvedge.Kernel.CompactionPlan.Failed message => failed id task entry message value
     | Selvedge.Kernel.CompactionPlan.Compacted candidate => begin_validation id task input purpose candidate entry value
     | Selvedge.Kernel.CompactionPlan.Next progress => match configured_target task (registry value) with
       | Some target => dispatch_compact id task input purpose target progress scope entry value
       | None => commit id (with_job NoJob entry) value [] end end
     else commit id (with_job NoJob entry) value []) else None
 | _ => None end.
Definition with_now (now : N) (value : Selvedge.Features.CompactionTypes.state) := set maintenance_now (N.max now) value.
Definition activity_result (id source now : N) (scope : string) (task : task) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 if source <=? N.of_nat (List.length (task_history task)) then
 let deadline := match configured_target task (registry value) with
 | Some target => if N.eqb (target_cache_ttl target) 0 then 0 else now + target_cache_ttl target | None => 0 end in
 let entry := set entry_last_activity (fun _ => now) (set entry_cache_deadline (fun _ => deadline)
   (set entry_cache_scope (fun _ => scope) (set entry_cache_history (fun _ => firstn (N.to_nat source) (task_history task)) entry))) in
 Some (commit id entry (store (with_now now (registry value)) value) [])
 else None.
Definition resolve_task_completion (id : N) (completion : completion) (value : Selvedge.Kernel.State.world) :=
 match Selvedge.Kernel.State.find_task id value with
 | None => None
 | Some task => let entry := current_entry id (registry value) in
   match completion with
   | Activity _ source now scope => activity_result id source now scope task entry value
   | MeasuredInput _ ticket outcome => if running task then measurement_result id ticket task outcome entry value else
       if alive task && (match entry_job entry with
       | Preparing expected _ _ _ | Validating expected _ _ _ _ _ => N.eqb ticket expected
       | _ => match measurement_ticket (entry_measurement entry) with Some expected => N.eqb ticket expected | None => false end end)
       then Some (commit id (recover_entry entry) value (cancellations id entry)) else None
   | Completed _ ticket result error => if running task then compact_result id ticket task result error entry value else
       if alive task && (match entry_job entry with Compacting expected _ _ _ _ => N.eqb ticket expected | _ => false end)
       then Some (commit id (recover_entry entry) value (cancellations id entry)) else None
   | _ => None end end.
(* Summary-context reads are not inference demand. Restart retires their
   exact receiver before the ordinary task recovery rule resumes inference. *)
Definition recover_context_task (state : Selvedge.Features.CompactionTypes.state) (id : N) (task : task) :=
 match entry_job (current_entry id state), task_activity task with
 | AwaitingContext expected _ resume_model, ObservingContext actual _ =>
   if N.eqb expected actual then with_activity (if resume_model then WantsModel else Idle) task else task
 | _, _ => task end.
Definition recover_context_tasks (state : Selvedge.Features.CompactionTypes.state) (value : Selvedge.Kernel.State.world) :=
 Selvedge.Kernel.State.with_tasks
   (Selvedge.Foundation.Registry.indexed (recover_context_task state) 0 (Selvedge.Kernel.State.world_tasks value)) value.
Definition resolve (completion : completion) (value : Selvedge.Kernel.State.world) : option Selvedge.Kernel.State.decision :=
 match completion with
 | Configure policy now =>
   let before := registry value in
   Some (acknowledged true (store (MaintenanceState policy (map (fun pair => (fst pair, recover_entry (snd pair)))
       (maintenance_entries before)) (N.max now (maintenance_now before)) 0) (recover_context_tasks before value))
     (map Selvedge.Kernel.State.MaintainContext (pending_cancellations before)))
 | Clock now => Some (acknowledged true (store (set maintenance_timer (fun _ => 0) (with_now now (registry value))) value) [])
 | Activity id _ _ _ | MeasuredInput id _ _ | Completed id _ _ _ => resolve_task_completion id completion value end.

Definition validating (job : job) := match job with
 | WaitingForResource _ | AwaitingContext _ _ _ | Preparing _ _ _ _ | Validating _ _ _ _ _ _ | Resuming _ Manual | Compacting _ _ Manual _ _ => true
 | _ => false end.
Definition pending_measurement (measurement : measurement) := match measurement with Measuring _ _ _ => true | _ => false end.
Definition blocked (task : task) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 validating (entry_job entry) || match enabled_target task (registry value) with
 | None => false
 | Some _ => (match entry_measurement entry with MeasurementFailed _ => true | _ => false end) ||
   pending_measurement (entry_measurement entry) || negb (fresh (entry_measurement entry) task value) ||
   match entry_measurement entry with
   | Oversized _ _ _ => true
   | Measured _ _ tokens budget => must_wait (maintenance_policy (registry value)) tokens budget && job_pending (entry_job entry)
   | _ => false end end.
Definition can_schedule_task (id : N) (value : Selvedge.Kernel.State.world) := match Selvedge.Kernel.State.find_task id value with
 | None => false
 | Some task => match task_lifecycle task with
   | Running ReadyForModel operations =>
     (* Ready operations precede the model step. A live asynchronous operation
        alone does not make a changed model input exempt from measurement. *)
     match Scheduler.ready_operation operations with
     | Some _ => true
     | None => negb (blocked task (current_entry id (registry value)) value)
     end
   | _ => true end end.
Definition idle_due (task : task) (entry : entry) (state : Selvedge.Features.CompactionTypes.state) :=
 policy_enabled (maintenance_policy state) && idle task && alive task && negb (job_pending (entry_job entry)) &&
 (entry_maintained entry <? useful (task_history task)) && (entry_attempted entry <? useful (task_history task)) &&
 ContextSelection.closed_prefix (task_history task) && (0 <? entry_cache_deadline entry) &&
 (entry_cache_deadline entry - policy_idle_lead (maintenance_policy state) <=? maintenance_now state) &&
 ContextSelection.history_extends (entry_cache_history entry) (task_history task).
Definition synchronized_entry (task : task) (entry : entry) (state : Selvedge.Features.CompactionTypes.state) :=
 if entry_useful entry <? useful (task_history task) then
 set entry_useful (fun _ => useful (task_history task)) (set entry_last_activity (fun _ => maintenance_now state) entry)
 else entry.
Definition resource_wait_purpose (value : job) := match value with
 | WaitingForResource purpose | AwaitingContext _ purpose _ => purpose
 | Resuming _ purpose | Preparing _ _ purpose _ | Compacting _ _ purpose _ _ | Validating _ _ purpose _ _ _ => Some purpose
 | NoJob => None end.
Definition release_context_receiver (entry : entry) (task : task) :=
 match entry_job entry, task_activity task with
 | AwaitingContext expected _ resume_model, ObservingContext actual _ =>
   if N.eqb expected actual then with_activity (resume_activity resume_model) task else task
 | _, _ => task end.
Definition wait_for_resource (id : N) (task : task) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 commit id (with_observation None (with_measurement Unmeasured
   (with_job (WaitingForResource (resource_wait_purpose (entry_job entry))) entry)))
  (Selvedge.Kernel.State.put_task id (release_context_receiver entry task) value) (cancellations id entry).
Definition synchronize (id : N) (task : task) (value : Selvedge.Kernel.State.world) : option Selvedge.Kernel.State.decision :=
 let state := registry value in
 let entry := synchronized_entry task (current_entry id state) state in
 if negb (alive task) then match find_entry id state with Some _ => Some (cancel id task entry value) | None => None end
 else if negb (TicketedRequest.Scoped.resources_available task value) then
   match find_entry id state, enabled_target task state with
   | None, None => None
   | _, _ => Some (wait_for_resource id task entry value) end
 else if running task then
 (* Model input is measured after the admitted workspace observation. Holding
    WantsModel here would prevent the observation that makes the count current. *)
 match task_activity task with WantsModel | ObservingContext _ _ => None | _ =>
 match entry_job entry with
 | WaitingForResource purpose => Some (begin_scope id (capture_task task value) purpose (with_job NoJob entry) value)
 | AwaitingContext _ _ _ => None
 | Resuming input purpose =>
   if relevant input task value then
    if ContextSelection.closed_prefix (task_history task)
    then Some (restart id task purpose entry value) else None
   else Some (cancel id task entry value)
 | _ => match enabled_target task state with
   | None => match find_entry id state with Some _ => Some (commit id entry value []) | None => None end
   | Some _ => if validating (entry_job entry) || pending_measurement (entry_measurement entry)
     then Some (commit id entry value [])
     else if idle_due task entry state then Some (begin_scope id (capture_task task value) (Some IdleMaintenance) entry value)
     else if fresh (entry_measurement entry) task value then Some (commit id entry value [])
     else Some (begin_scope id (capture_task task value) None entry value) end end end
 else None.
Definition combine (first second : Selvedge.Kernel.State.decision) :=
 Selvedge.Kernel.State.Decision (Selvedge.Kernel.State.decision_world second) (Selvedge.Kernel.State.decision_reply first) (Selvedge.Kernel.State.decision_effects first ++ Selvedge.Kernel.State.decision_effects second)%list.
Definition cancelled_task (id : N) (effects : list Selvedge.Kernel.State.effect) :=
 existsb (fun effect => match effect with Selvedge.Kernel.State.CancelTask owner => N.eqb owner id | _ => false end) effects.
Definition cancelled_ticket (id ticket : N) (effects : list Selvedge.Kernel.State.effect) :=
 existsb (fun effect => match effect with
 | Selvedge.Kernel.State.CancelTicket owner expected => N.eqb owner id && N.eqb ticket expected
 | _ => false end) effects.
Definition suspended_context_task (purpose : option reason) (resume_model : bool) (task : task) :=
 let task := match purpose with Some Manual => append_history
   [FailureMessage "Context summary was not sent because the task is frozen or stopped; original history retained"] task
   | _ => task end in
 Tasks.promote (with_activity (if resume_model then WantsModel else Idle) task).
Definition same_context_purpose (first second : option reason) := match first, second with
 | None, None | Some Background, Some Background | Some Blocking, Some Blocking
 | Some IdleMaintenance, Some IdleMaintenance | Some Manual, Some Manual => true
 | _, _ => false end.
Definition awaiting_context_demand (ticket : N) (purpose : option reason) (entry : entry) :=
 match entry_job entry with
 | AwaitingContext actual current demanded =>
   if N.eqb actual ticket && same_context_purpose current purpose then Some demanded else None
 | _ => None end.
Definition observe_manual (before : Selvedge.Kernel.State.world) (id : N) (result : Selvedge.Kernel.State.decision) :=
 let value := Selvedge.Kernel.State.decision_world result in
 let entry := current_entry id (registry value) in
 match Selvedge.Kernel.State.find_task id before, Selvedge.Kernel.State.find_task id value with
 | Some previous, Some task =>
   if cancelled_task id (Selvedge.Kernel.State.decision_effects result) then
     combine result (commit id (clear_entry task entry) value [])
   else match task_activity previous with
   | ObservingContext observed _ =>
     match entry_job (current_entry id (registry before)) with
     | AwaitingContext expected purpose resume_model =>
       if N.eqb expected observed then
       match awaiting_context_demand expected purpose entry with
       | None => result
       | Some demanded =>
       if cancelled_ticket id expected (Selvedge.Kernel.State.decision_effects result) then
         combine result (commit id (clear_entry task entry) value [])
       else let resume_model := resume_model || demanded in
       match task_activity task, task_lifecycle task with
       | ReadyForModel, Running _ _ =>
         let task := with_activity (resume_activity resume_model) task in
         let value := Selvedge.Kernel.State.put_task id task value in
         let input := capture_task task value in
         let entry := with_observation (Some input) (with_measurement Unmeasured (with_job NoJob entry)) in
         let recorded := commit id entry value [] in
         combine result (begin_scope id input purpose entry (Selvedge.Kernel.State.decision_world recorded))
       | ObservingContext next _, _ =>
         (* A revision retry keeps the same purpose but owns its newly issued
            ticket. A stale receiver cannot claim a later inference read. *)
         combine result (commit id (with_job (AwaitingContext next purpose resume_model) entry) value [])
       | WantsModel, Frozen _ _ | WantsModel, Stopped _ _ =>
         let task := suspended_context_task purpose resume_model task in
         combine result (cancel id task entry (Selvedge.Kernel.State.put_task id task value))
       | WantsModel, Running _ _ =>
         if TicketedRequest.Scoped.resources_available task value then
           combine result (cancel id task entry value)
         else
           let task := with_activity (resume_activity resume_model) task in
           combine result (wait_for_context id purpose entry (Selvedge.Kernel.State.put_task id task value))
       | _, _ => combine result (cancel id task entry value) end end
       else result
     | _ => match task_activity task, task_lifecycle task with
       | ReadyForModel, Running _ _ =>
         combine result (commit id (with_observation (Some (capture_task task value)) entry) value [])
       | _, _ => result end end
   | _ => result end
 | _, _ => result end.
Definition synchronize_task (id : N) (result : Selvedge.Kernel.State.decision) :=
 match Selvedge.Kernel.State.find_task id (Selvedge.Kernel.State.decision_world result) with
 | Some task => match synchronize id task (Selvedge.Kernel.State.decision_world result) with Some next => combine result next | None => result end
 | None => result end.
Definition entry_deadline (entry : entry) (now lead : N) :=
 let due := entry_cache_deadline entry - lead in
 if (entry_maintained entry <? entry_useful entry) && (entry_attempted entry <? entry_useful entry) &&
    negb (job_pending (entry_job entry)) && (now <? due) then due else 0.
Definition earlier (left right : N) := if N.eqb left 0 || ((0 <? right) && (right <? left)) then right else left.
Definition arm_clock (result : Selvedge.Kernel.State.decision) :=
 let value := Selvedge.Kernel.State.decision_world result in
 let state := registry value in
 let deadline := if policy_enabled (maintenance_policy state) then
 fold_right (fun pair rest => earlier (entry_deadline (snd pair) (maintenance_now state) (policy_idle_lead (maintenance_policy state))) rest)
  0 (maintenance_entries state) else 0 in
 if N.eqb deadline 0 || N.eqb deadline (maintenance_timer state) then result
 else combine result (acknowledged true (store (set maintenance_timer (fun _ => deadline) state) value) [Selvedge.Kernel.State.MaintainContext (ArmClock deadline)]).
Definition synchronize_all (result : Selvedge.Kernel.State.decision) :=
 let identities := map fst (Selvedge.Foundation.Registry.indexed (fun id task => (id,task)) 0 (Selvedge.Kernel.State.world_tasks (Selvedge.Kernel.State.decision_world result))) in
 arm_clock (fold_left (fun result id => synchronize_task id result) identities result).
Definition after_transition (before : Selvedge.Kernel.State.world) (result : Selvedge.Kernel.State.decision) :=
 let identities := map fst (Selvedge.Foundation.Registry.indexed (fun id task => (id,task)) 0 (Selvedge.Kernel.State.world_tasks (Selvedge.Kernel.State.decision_world result))) in
 let result := fold_left (fun result id => observe_manual before id result) identities result in
 synchronize_all result.
Definition recover (value : Selvedge.Kernel.State.world) :=
 let state := registry value in
 store (MaintenanceState (maintenance_policy state)
  (map (fun pair => (fst pair, recover_entry (snd pair))) (maintenance_entries state)) (maintenance_now state) 0)
   (recover_context_tasks state value).
(* A live catalog change has physical requests to retire. Their exact tickets
   must be collected before recovery clears the corresponding receivers. A
   process restart still uses [recover], since the new process has no running
   handles for its old requests. Recovery does not confirm remote cancellation. *)
Definition reconfigure (value : Selvedge.Kernel.State.world) :=
 acknowledged true (recover value)
   (map Selvedge.Kernel.State.MaintainContext (pending_cancellations (registry value))).
Definition checkpoint_entry (history : list message) (entry : entry) :=
 set entry_useful (fun _ => useful history) (set entry_maintained (N.max (useful history))
  (set entry_attempted (N.max (useful history)) (set entry_cache_deadline (fun _ => 0)
  (with_measurement Unmeasured (with_job NoJob entry))))).
Definition supplied (id : N) (task : task) (summary : string) (value : Selvedge.Kernel.State.world) :=
 let history := task_history task in
 let entry := checkpoint_entry history (current_entry id (registry value)) in
 let task := set task_history (fun _ => ContextSelection.adopt history (ContextSelection.portable summary) history) task in
 commit id entry (Selvedge.Kernel.State.put_task id task value) (cancellations id (current_entry id (registry value))).
Definition manual (id : N) (task : task) (value : Selvedge.Kernel.State.world) :=
 let entry := current_entry id (registry value) in
 let result := if job_pending (entry_job entry) then acknowledged false value []
   else wait_for_context id (Some Manual) entry value in
 Selvedge.Kernel.State.Decision (Selvedge.Kernel.State.decision_world result)
   (Selvedge.Kernel.State.success (JObject [("task_id", number id)]))
   ((map Selvedge.Kernel.State.MaintainContext (if job_pending (entry_job entry) then [] else cancellations id entry)) ++
     Selvedge.Kernel.State.decision_effects result)%list.
Definition handle_compact (payload : Selvedge.Generated.Commands.compact_payload)
 (_caller : option N) (value : Selvedge.Kernel.State.world) : Selvedge.Kernel.State.decision :=

   let id := Selvedge.Generated.Commands.compact_task_id payload in
   match Selvedge.Kernel.State.find_task id value with
   | None => Selvedge.Kernel.State.reject "task_not_found" "The task does not exist" value
   | Some task => if negb (alive task) then Selvedge.Kernel.State.reject "task_archived" "An archived task cannot be changed" value
     else match Selvedge.Generated.Commands.compact_summary payload with
       | None => match task_activity task with
         | Idle => if running task then manual id task value else Selvedge.Kernel.State.reject "task_busy" "Model compaction requires an active idle task" value
         | _ => Selvedge.Kernel.State.reject "task_busy" "Model compaction requires an active idle task" value end
       | Some summary =>
         let invalid := Selvedge.Kernel.State.reject "invalid_summary"
           "A checkpoint requires a nonempty bounded summary and settled tool calls" value in
         if idle task then if negb (String.eqb summary "") &&
         (N.of_nat (String.length summary) <=? Compaction.summary_limit_bytes) &&
         ContextSelection.closed_prefix (task_history task)
         then supplied id task summary value
         else invalid
         else match task_activity task with
         | Idle => invalid
         | _ => Selvedge.Kernel.State.reject "task_busy" "Compaction requires an idle task" value end end end.

Definition owns_kind (kind : string) := match Selvedge.Features.CompactionCodec.completion_decoder kind with Some _ => true | None => false end.
Definition completion (source : json) (value : Selvedge.Kernel.State.world) : option (bool * bool * Selvedge.Kernel.State.decision) :=
 match string_field "kind" source with
 | Some kind => if owns_kind kind then Some (match Selvedge.Features.CompactionCodec.decode_completion kind source with
   | None => (false,false,Selvedge.Kernel.State.reject "invalid_input" "Malformed compaction observation" value)
   | Some completion => match resolve completion value with
     | None => (true,true,acknowledged false value [])
     | Some result => (true,true,result) end end) else None
 | None => None end.
Definition prepare_model_effects (value : Selvedge.Kernel.State.world) (effects : list Selvedge.Kernel.State.effect) :=
 map (fun effect => match effect with
 | Selvedge.Kernel.State.RequestModel request =>
   let id := Selvedge.Kernel.ModelRequest.owner request in
   match entry_measurement (current_entry id (registry value)) with
   | Measured _ scope _ budget | Oversized _ scope budget =>
     Selvedge.Kernel.State.RequestModel (Selvedge.Kernel.ModelRequest.with_context scope (reserve_tokens budget) request)
   | _ => effect end
 | _ => effect end) effects.
Definition attach (result : Selvedge.Kernel.State.decision) :=
 Selvedge.Kernel.State.Decision (Selvedge.Kernel.State.decision_world result)
  (Selvedge.Kernel.State.decision_reply result)
  (prepare_model_effects (Selvedge.Kernel.State.decision_world result) (Selvedge.Kernel.State.decision_effects result)).
