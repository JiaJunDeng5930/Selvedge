From Selvedge.Kernel Require InputRoute.
From Selvedge.Kernel Require CommandResult DecisionComposition.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects TextJson Completion.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Capabilities Compaction CompactionPlan ContextSelection Limits Scheduler Reasoning TicketedRequest.
From Selvedge.Features Require Import Domain State CompactionTypes CompactionCodec CompactionRequest.
Module R := CompactionRequest.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition registry (value : Selvedge.Kernel.State.world) := Selvedge.Features.Domain.feature_compaction (Selvedge.Kernel.State.world_features value).
Definition store (replacement : Selvedge.Features.CompactionTypes.state) (value : Selvedge.Kernel.State.world) :=
 Selvedge.Kernel.State.with_features (Selvedge.Features.State.with_compaction replacement (Selvedge.Kernel.State.world_features value)) value.
Definition find_entry (id : N) (value : Selvedge.Features.CompactionTypes.state) :=
 option_map (@snd N entry) (find (fun pair => N.eqb id (fst pair)) (maintenance_entries value)).
Definition current_entry (id : N) (value : Selvedge.Features.CompactionTypes.state) := match find_entry id value with Some entry => entry | None => empty_entry end.
Definition with_entry (id : N) (entry : entry) (value : Selvedge.Features.CompactionTypes.state) :=
 Receiver.install (Receiver.path (R.compaction_entries id value)) entry value.
Definition acknowledged (accepted : bool) (value : Selvedge.Kernel.State.world) (effects : list Selvedge.Kernel.State.effect) :=
 Selvedge.Kernel.State.accept (JObject [("accepted", JBool accepted)]) value effects.
Definition commit_change (id : N) (entry : entry) (value : Selvedge.Kernel.State.world) (effects : list Selvedge.Features.CompactionTypes.effect) :=
 CommandResult.Change (JObject [("accepted", JBool true)])
   (store (with_entry id entry (registry value)) value) (map Selvedge.Kernel.State.MaintainContext effects).
Definition commit (id : N) (entry : entry) (value : Selvedge.Kernel.State.world) (effects : list Selvedge.Features.CompactionTypes.effect) :=
 CommandResult.accept (commit_change id entry value effects).
Definition configured_target (task : task) (value : Selvedge.Features.CompactionTypes.state) :=
 find (fun target => String.eqb (target_key target) (profile_key (task_current_profile task)))
  (policy_targets (maintenance_policy value)).
Definition enabled_target (task : task) (value : Selvedge.Features.CompactionTypes.state) :=
 if policy_enabled (maintenance_policy value) then configured_target task value else None.
Definition running (task : task) := match task_lifecycle task with Running _ _ => true | _ => false end.
Definition alive (task : task) := match task_lifecycle task with Archived _ => false | _ => true end.
Definition idle (task : task) := match task_activity task, task_operations task with Idle, [] => true | _, _ => false end.
Definition capture_task := R.capture_task.
Definition input_description := R.input_description.
Definition same_description := R.same_description.
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
 | AwaitingContext ticket _ _ | Preparing (RequestEnvelope.Envelope ticket _) | Compacting (RequestEnvelope.Envelope ticket _) | Validating (RequestEnvelope.Envelope ticket _) => Some ticket | _ => None end.
Definition measurement_ticket (value : measurement) := match value with Measuring (RequestEnvelope.Envelope ticket _) => Some ticket | _ => None end.
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
Definition retain_context_wait (id : N) (task : task) (purpose : option reason) (entry : entry)
 (value : Selvedge.Kernel.State.world) :=
 (* A quiet external call can leave an active task idle without publishing
    its result. Retain a requested compaction until that prefix closes;
    resume recaptures the result or announcement before asking for a summary. *)
 let waiting := if TicketedRequest.Scoped.resources_available task value then
   match purpose with Some purpose => Resuming (capture_task task value) purpose | None => NoJob end
   else WaitingForResource purpose in
 commit id (with_observation None (with_measurement Unmeasured (with_job waiting entry))) value [].
Definition wait_for_context_selected {value} (target : TaskScope.task_reference value)
 (purpose : option reason) (entry : entry) :=
 match R.maintenance_context_selected target purpose entry with
 | Some request => R.maintenance_observe request
 | None => retain_context_wait (TaskScope.owner target) (TaskScope.selected target) purpose entry value end.
Definition wait_for_context (id : N) (purpose : option reason) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 match TaskScope.select id value with
 | Some target => wait_for_context_selected target purpose entry
 | None => Selvedge.Kernel.State.ignored value end.
Definition run_request_selected {value} (target : TaskScope.task_reference value)
 (request : R.maintenance_action) :=
 match R.maintenance_selected (TaskScope.owner target)
   request value (TaskScope.selected target) (TaskScope.observed target) with
 | Some admitted => R.maintenance_issue admitted
 | None => let '(purpose,entry) := R.maintenance_waiting_entry request in
   wait_for_context_selected target purpose entry end.
Definition run_request (id : N) (request : R.maintenance_action) (value : Selvedge.Kernel.State.world) :=
 match TaskScope.select id value with
 | Some target => run_request_selected target request
 | None => Selvedge.Kernel.State.ignored value end.
Definition resume (job : job) := match job with
 | NoJob | AwaitingContext _ _ _ => NoJob
 | WaitingForResource purpose => WaitingForResource purpose
 | Resuming input purpose | Preparing (RequestEnvelope.Envelope _ (InspectInput input purpose _))
 | Compacting (RequestEnvelope.Envelope _ (CompactInput input purpose _ _ _)) | Validating (RequestEnvelope.Envelope _ (InspectInput input (Candidate purpose _ _) _)) => Resuming input purpose end.
Definition recover_entry (entry : entry) := with_observation None
 (with_measurement Unmeasured (with_job (resume (entry_job entry)) entry)).
Definition clear_entry (task : task) (entry : entry) :=
 set entry_attempted (fun _ => useful (task_history task))
  (set entry_cache_deadline (fun _ => 0) (with_measurement Unmeasured (with_job NoJob entry))).
Definition cancel (id : N) (task : task) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 commit id (clear_entry task entry) value (cancellations id entry).
Definition begin_scope (id : N) (input : capture) (purpose : option reason) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 run_request id (R.ScopeRequest input purpose entry) value.
Definition dispatch_compact (id : N) (task : task) (input : capture) (purpose : reason) (target : target)
 (progress : compaction_state) (scope : string) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 let ticket := world_next_ticket value in
 let limit := Limits.frame_bytes / 4 in
 let available := limit - Selvedge.Features.CompactionCodec.compact_metadata_bytes id ticket input target scope in
 match Selvedge.Kernel.CompactionPlan.fit_transport progress available with
 | Some fitted =>
   if Selvedge.Kernel.CompactionPlan.transport_fits fitted available &&
     (N.of_nat (String.length (TextJson.render_json (Selvedge.Features.CompactionCodec.compact_json id ticket input target fitted scope))) <=? limit)
   then run_request id (R.CompactRequest (CompactInput input purpose target fitted scope) entry) value
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
   | Compacting _ => commit id entry value []
   | _ => if ContextSelection.closed_prefix (task_history task) then
       start id task input Blocking (set target_method (fun _ => Summary) target) scope (window_tokens (target_budget target)) entry value
     else commit id (with_job (Resuming input Blocking) entry) value [] end end.
(* A native candidate can be rebuilt once in portable form. Rebuilding an
   already portable candidate repeats the same source, including retained
   images and task context, without making the rejected input smaller. *)
Definition oversized_candidate (id : N) (task : task) (scope : string)
 (candidate : option artifact) (entry : entry) (message : string) (value : Selvedge.Kernel.State.world) :=
 match candidate with
 | Some (PortableArtifact _ _ _) => failed id task entry message value
 | _ => force_portable id task scope entry value end.
Definition measured_call (id : N) (task : task) (input : capture) (scope : string) (purpose : R.inspection_purpose)
 (entry : entry) (value : Selvedge.Kernel.State.world) :=
 let request:=R.MeasureRequest input purpose scope entry in
 if N.of_nat (String.length (TextJson.render_json (R.preview_json id (world_next_ticket value) request value))) <=? Limits.frame_bytes / 4
 then run_request id request value
 else oversized_candidate id task scope (R.purpose_candidate purpose) entry
   "The portable summary and retained context exceed the validation transport budget; original history retained" value.
Definition begin_validation (id : N) (task : task) (input : capture) (purpose : reason) (candidate : artifact)
 (entry : entry) (value : Selvedge.Kernel.State.world) :=
 if relevant input task value then
 let preview := ContextSelection.adopt (captured_history input) candidate (task_history task) in
 run_request id (R.ValidationScopeRequest input purpose candidate preview entry) value
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
 else oversized_candidate id task scope (Some candidate) entry
   "The portable summary and retained context exceed the configured model window; original history retained" value
 else begin_validation id task input purpose candidate entry value
 else commit id (with_job NoJob entry) value [].

Definition restart (id : N) (task : task) (purpose : reason) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 begin_scope id (capture_task task value) (Some purpose) (with_job NoJob entry) value.
(** Scope discovery and token counting are one protocol shared by ordinary
    measurement, preparation and candidate validation. A changed scope always
    requests a new count before a token observation can be consumed. *)
Definition inspected_outcome (stage : inspection_stage) (outcome : inspection) :=
 match outcome, stage with
 | InspectionFailed message, _ => InspectionFailed message
 | ScopeObserved scope, InspectScope => ScopeObserved scope
 | ScopeObserved scope, InspectCount expected =>
   if String.eqb expected scope then InspectionFailed "The input meter returned a scope without a token measurement"
   else ScopeObserved scope
 | InputMeasured scope tokens budget, InspectCount expected =>
   if String.eqb expected scope then InputMeasured scope tokens budget else ScopeObserved scope
 | InputMeasured _ _ _, InspectScope => InspectionFailed "The scope observation returned an unexpected token measurement" end.
Definition validation_input (id : N) (task : task) (input : capture) (purpose : reason) (candidate : artifact)
 (preview : list message) (scope : string) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 if ContextSelection.consumes candidate scope then
 measured_call id task input scope (R.ValidateCandidate (Candidate purpose candidate preview)) entry value
 else restart id task purpose entry value.
Definition inspected (id : N) (task : task) (input : capture) (purpose : R.inspection_purpose)
 (stage : inspection_stage) (outcome : inspection) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 if match purpose with R.MeterOnly => true | _ => relevant input task value end then
 match inspected_outcome stage outcome with
 | InspectionFailed message => failed id task entry message value
 | ScopeObserved scope => match purpose with
   | R.ValidateCandidate (Candidate purpose candidate preview) => validation_input id task input purpose candidate preview scope entry value
   | _ => measured_call id task input scope purpose entry value end
 | InputMeasured scope tokens budget => match purpose with
   | R.MeterOnly => finish_measure id task input scope tokens budget entry value
   | R.PrepareFor reason => match configured_target task (registry value) with
     | None => failed id task entry "The selected profile does not support compaction" value
     | Some target => start id task input reason target scope tokens
       (with_measurement (if same_input input task value then Measured input scope tokens budget else Unmeasured) entry) value end
   | R.ValidateCandidate (Candidate purpose candidate preview) =>
     finish_validation id task input purpose candidate preview scope tokens budget entry value end
 end else commit id (with_job NoJob entry) value [].
Definition completion_path id value := Receiver.field world_features
 (Receiver.path (R.compaction_slot id (world_features value))).
Definition stopped_completion id task previous value :=
 if alive task then Some (commit id (recover_entry previous) value (cancellations id previous)) else None.
Definition receive_inspection {phase continuation} (get : entry -> phase) `{setter : SetterWf entry phase get}
 (pending : RequestEnvelope.t (inspection_input continuation) -> phase)
 `{view : Constructor.Case (RequestEnvelope.t (inspection_input continuation)) phase pending}
 (finish : Completion.Row.amendment entry pending) (purpose : continuation -> R.inspection_purpose)
 (id ticket : N) (task : task) (outcome : inspection) (value : Selvedge.Kernel.State.world) :=
 match Completion.Row.consume (completion_path id value) get pending Completion.Ticket ticket
   (fun _ _ => Some finish) value with
 | Some received =>
   let input:=RequestEnvelope.input (Completion.Row.request received) in
   if running task then Some (inspected id task (inspection_capture input) (purpose (inspection_continuation input))
     (inspection_step input) outcome (Completion.Row.updated received) (Completion.Row.after received))
   else stopped_completion id task (Completion.Row.previous received) (Completion.Row.after received)
 | None => None end.
Definition measurement_finished : Completion.Row.amendment entry Measuring :=
 Completion.Row.Amend [] (Completion.done Unmeasured).
Definition job_finished {input} (pending : input -> job) `{view : Constructor.Case input job pending}
 `{closed : @Completion.Retired input job pending view NoJob} : Completion.Row.amendment entry pending :=
 Completion.Row.Amend [] (Completion.done NoJob).
Definition preparation_finished : Completion.Row.amendment entry Preparing := job_finished Preparing.
Definition validation_finished : Completion.Row.amendment entry Validating := job_finished Validating.
Definition compaction_finished : Completion.Row.amendment entry Compacting := job_finished Compacting.
Definition measurement_result (id ticket : N) (task : task) (outcome : inspection)
 (value : Selvedge.Kernel.State.world) : option Selvedge.Kernel.State.decision :=
 match entry_job (current_entry id (registry value)) with
 | Validating _ => receive_inspection entry_job Validating validation_finished R.ValidateCandidate id ticket task outcome value
 | Preparing _ => receive_inspection entry_job Preparing preparation_finished R.PrepareFor id ticket task outcome value
 | _ => receive_inspection entry_measurement Measuring measurement_finished (fun _ => R.MeterOnly) id ticket task outcome value end.
Definition compacted_result (id : N) (task : task) (request : compaction_input)
 (result : json) (error : bool) (entry : entry) (value : Selvedge.Kernel.State.world) :=
 let '(CompactInput input purpose target progress scope):=request in
 if relevant input task value then
 if error then failed id task entry (match string_field "message" result with Some message => message
   | None => "The failed compaction outcome requires a message" end) value
 else if bool_default "scope_changed" result false then restart id task purpose entry value
 else match Selvedge.Kernel.CompactionPlan.receive progress result with
 | Selvedge.Kernel.CompactionPlan.Failed message => failed id task entry message value
 | Selvedge.Kernel.CompactionPlan.Compacted candidate => begin_validation id task input purpose candidate entry value
 | Selvedge.Kernel.CompactionPlan.Next progress => dispatch_compact id task input purpose target progress scope entry value end
 else commit id (with_job NoJob entry) value [].
Definition compact_result (id ticket : N) (task : task) (result : json) (error : bool)
 (value : Selvedge.Kernel.State.world) : option Selvedge.Kernel.State.decision :=
 match Completion.Row.consume (completion_path id value) entry_job Compacting Completion.Ticket ticket
   (fun _ _ => Some compaction_finished) value with
 | Some received =>
   if running task then Some (compacted_result id task (RequestEnvelope.input (Completion.Row.request received))
     result error (Completion.Row.updated received) (Completion.Row.after received))
   else stopped_completion id task (Completion.Row.previous received) (Completion.Row.after received)
 | None => None end.
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
   | MeasuredInput _ ticket outcome => measurement_result id ticket task outcome value
   | Completed _ ticket result error => compact_result id ticket task result error value
   | _ => None end
 end.
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
 | WaitingForResource _ | AwaitingContext _ _ _ | Preparing _ | Validating _ | Resuming _ Manual | Compacting (RequestEnvelope.Envelope _ (CompactInput _ Manual _ _ _)) => true
 | _ => false end.
Definition pending_measurement (measurement : measurement) := match measurement with Measuring _ => true | _ => false end.
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
 | Resuming _ purpose | Preparing (RequestEnvelope.Envelope _ (InspectInput _ purpose _)) | Compacting (RequestEnvelope.Envelope _ (CompactInput _ purpose _ _ _)) | Validating (RequestEnvelope.Envelope _ (InspectInput _ (Candidate purpose _ _) _)) => Some purpose
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
 let previous := find_entry id state in
 let entry := synchronized_entry task (match previous with Some entry => entry | None => empty_entry end) state in
 if negb (alive task) then match previous with Some _ => Some (cancel id task entry value) | None => None end
 else if negb (TicketedRequest.Scoped.resources_available task value) then
   match previous, enabled_target task state with
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
   | None => match previous with Some _ => Some (commit id entry value []) | None => None end
   | Some _ => if validating (entry_job entry) || pending_measurement (entry_measurement entry)
     then Some (commit id entry value [])
     else if idle_due task entry state then Some (begin_scope id (capture_task task value) (Some IdleMaintenance) entry value)
     else if fresh (entry_measurement entry) task value then Some (commit id entry value [])
     else Some (begin_scope id (capture_task task value) None entry value) end end end
 else None.
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
Definition observe_manual (before : Selvedge.Kernel.State.world) (id : N)  : DecisionComposition.step := fun value effects =>
 let entry := current_entry id (registry value) in
 match Selvedge.Kernel.State.find_task id before, Selvedge.Kernel.State.find_task id value with
 | Some previous, Some task =>
   if cancelled_task id (effects) then
     DecisionComposition.from_decision (commit id (clear_entry task entry) value [])
   else match task_activity previous with
   | ObservingContext observed _ =>
     match entry_job (current_entry id (registry before)) with
     | AwaitingContext expected purpose resume_model =>
       if N.eqb expected observed then
       match awaiting_context_demand expected purpose entry with
       | None => DecisionComposition.unchanged value
       | Some demanded =>
       if cancelled_ticket id expected (effects) then
         DecisionComposition.from_decision (commit id (clear_entry task entry) value [])
       else let resume_model := resume_model || demanded in
       match task_activity task, task_lifecycle task with
       | ReadyForModel, Running _ _ =>
         let task := with_activity (resume_activity resume_model) task in
         let value := Selvedge.Kernel.State.put_task id task value in
         let input := capture_task task value in
         let entry := with_observation (Some input) (with_measurement Unmeasured (with_job NoJob entry)) in
         let recorded := commit id entry value [] in
         DecisionComposition.from_decision (begin_scope id input purpose entry (Selvedge.Kernel.State.decision_world recorded))
       | ObservingContext next _, _ =>
         (* A revision retry keeps the same purpose but owns its newly issued
            ticket. A stale receiver cannot claim a later inference read. *)
         DecisionComposition.from_decision (commit id (with_job (AwaitingContext next purpose resume_model) entry) value [])
       | WantsModel, Frozen _ _ | WantsModel, Stopped _ _ =>
         let task := suspended_context_task purpose resume_model task in
         DecisionComposition.from_decision (cancel id task entry (Selvedge.Kernel.State.put_task id task value))
       | WantsModel, Running _ _ =>
         if TicketedRequest.Scoped.resources_available task value then
           DecisionComposition.from_decision (cancel id task entry value)
         else
           let task := with_activity (resume_activity resume_model) task in
           DecisionComposition.from_decision (wait_for_context id purpose entry (Selvedge.Kernel.State.put_task id task value))
       | _, _ => DecisionComposition.from_decision (cancel id task entry value) end end
       else DecisionComposition.unchanged value
     | _ => match task_activity task, task_lifecycle task with
       | ReadyForModel, Running _ _ =>
         DecisionComposition.from_decision (commit id (with_observation (Some (capture_task task value)) entry) value [])
       | _, _ => DecisionComposition.unchanged value end end
   | _ => DecisionComposition.unchanged value end
 | _, _ => DecisionComposition.unchanged value end.
Definition synchronize_task (id : N) : DecisionComposition.step := fun value _ =>
 match Selvedge.Kernel.State.find_task id value with
 | Some current => match synchronize id current value with
   | Some next => DecisionComposition.from_decision next | None => DecisionComposition.unchanged value end
 | None => DecisionComposition.unchanged value end.

Definition entry_deadline (entry : entry) (now lead : N) :=
 let due := entry_cache_deadline entry - lead in
 if (entry_maintained entry <? entry_useful entry) && (entry_attempted entry <? entry_useful entry) &&
    negb (job_pending (entry_job entry)) && (now <? due) then due else 0.
Definition earlier (left right : N) := if N.eqb left 0 || ((0 <? right) && (right <? left)) then right else left.
Definition arm_clock : DecisionComposition.step := fun value _ =>
 let state := registry value in
 let deadline := if policy_enabled (maintenance_policy state) then
 fold_right (fun pair rest => earlier (entry_deadline (snd pair) (maintenance_now state) (policy_idle_lead (maintenance_policy state))) rest)
  0 (maintenance_entries state) else 0 in
 if N.eqb deadline 0 || N.eqb deadline (maintenance_timer state) then DecisionComposition.unchanged value
 else DecisionComposition.Update (store (set maintenance_timer (fun _ => deadline) state) value)
   [Selvedge.Kernel.State.MaintainContext (ArmClock deadline)].
Definition synchronize_all : DecisionComposition.step := fun value effects =>
 let identities := map fst (Selvedge.Foundation.Registry.indexed (fun id task => (id,task)) 0 (Selvedge.Kernel.State.world_tasks value)) in
 DecisionComposition.and_then (DecisionComposition.each identities synchronize_task) arm_clock value effects.
Definition after_transition (before : Selvedge.Kernel.State.world) : DecisionComposition.step := fun value effects =>
 let identities := map fst (Selvedge.Foundation.Registry.indexed (fun id task => (id,task)) 0 (Selvedge.Kernel.State.world_tasks value)) in
 DecisionComposition.and_then (DecisionComposition.each identities (observe_manual before)) synchronize_all value effects.
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
Definition supplied_change (id : N) (task : task) (summary : Compaction.summary) (value : Selvedge.Kernel.State.world) :=
 let history := task_history task in
 let previous := current_entry id (registry value) in
 let entry := checkpoint_entry history previous in
 let task := set task_history (fun _ => ContextSelection.adopt history (ContextSelection.portable (Compaction.summary_text summary)) history) task in
 commit_change id entry (Selvedge.Kernel.State.put_task id task value) (cancellations id previous).
Definition manual_change {value} (target : TaskScope.task_reference value) :=
 let id := TaskScope.owner target in
 let entry := current_entry id (registry value) in
 let result := if job_pending (entry_job entry) then acknowledged false value []
   else wait_for_context_selected target (Some Manual) entry in
 CommandResult.Change (JObject [("task_id", number id)]) (Selvedge.Kernel.State.decision_world result)
   ((map Selvedge.Kernel.State.MaintainContext (if job_pending (entry_job entry) then [] else cancellations id entry)) ++
     Selvedge.Kernel.State.decision_effects result)%list.
Definition handle_compact_result (payload : Selvedge.Generated.Commands.compact_payload)
 (_caller : option N) (value : Selvedge.Kernel.State.world) : CommandResult.result CommandResult.change :=

   let id := Selvedge.Generated.Commands.compact_task_id payload in
   match TaskScope.select id value with
   | None => CommandResult.refuse "task_not_found" "The task does not exist"
   | Some target => let task := TaskScope.selected target in
     if negb (alive task) then CommandResult.refuse "task_archived" "An archived task cannot be changed"
     else match Selvedge.Generated.Commands.compact_summary_admitted payload with
       | None => match task_activity task with
         | Idle => if running task then CommandResult.Accepted (manual_change target) else CommandResult.refuse "task_busy" "Model compaction requires an active idle task"
         | _ => CommandResult.refuse "task_busy" "Model compaction requires an active idle task" end
       | Some summary =>
         let invalid := CommandResult.refuse "invalid_summary"
           "A checkpoint requires settled tool calls" in
         if idle task then if ContextSelection.closed_prefix (task_history task)
         then CommandResult.Accepted (supplied_change id task summary value)
         else invalid
         else match task_activity task with
         | Idle => invalid
         | _ => CommandResult.refuse "task_busy" "Compaction requires an idle task" end end end.

Definition handle_compact (payload : Selvedge.Generated.Commands.compact_payload)
 (caller : option N) (value : Selvedge.Kernel.State.world) :=
 CommandResult.decide value (handle_compact_result payload caller value).

Definition completion (event : Selvedge.Features.CompactionTypes.completion) (value : Selvedge.Kernel.State.world) :=
 (true,true,match resolve event value with
 | None => acknowledged false value [] | Some result => result end).
Definition completion_inputs := List.map (InputRoute.map completion) Selvedge.Features.CompactionCodec.completion_inputs.
Definition prepare_model_effects (value : Selvedge.Kernel.State.world) (effects : list Selvedge.Kernel.State.effect) :=
 map (fun effect => match effect with
 | Selvedge.Kernel.State.RequestModel request =>
   let id := Selvedge.Kernel.ModelRequest.owner request in
   match entry_measurement (current_entry id (registry value)) with
   | Measured _ scope _ budget | Oversized _ scope budget =>
     Selvedge.Kernel.State.RequestModel (Selvedge.Kernel.ModelRequest.with_context scope (reserve_tokens budget) request)
   | _ => effect end
 | _ => effect end) effects.
Definition attach_context : DecisionComposition.transformation := fun _ value effects =>
 (value,prepare_model_effects value effects).
Definition attach := DecisionComposition.transform attach_context.
