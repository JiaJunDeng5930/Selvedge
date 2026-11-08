From Selvedge.Kernel Require TaskWake.
From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Programming Require CommandResult DecisionComposition TaskResult TaskScope.
From Selvedge.Kernel Require TicketedRequest.
From Selvedge.Foundation Require Import Json JsonObjectsProofs Registry RegistryProofs.
From Selvedge.Programming Require Import OptionObservationProofs CompletionProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State LifecycleProofs.
From Selvedge.Programming Require Import ProtocolProofs.
From Selvedge.Kernel Require Import ContextSelection ContextSelectionProofs Tasks Reasoning Recovery CompactionPlan CompactionPlanProofs.
From Selvedge.Programming Require Import FeatureRequestProofs TaskScopeProofs.
From Selvedge.Kernel Require Import ScopedRequestProofs.
From Selvedge.Features Require Import CompactionTypes CompactionCodec Compaction CompactionRequestProofs.
Module R := CompactionRequest.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module K := Selvedge.Kernel.State.
Module C := Selvedge.Features.CompactionTypes.
Module CC := Selvedge.Features.CompactionCodec.
Module A := Selvedge.Features.Compaction.
Module P := Selvedge.Kernel.CompactionPlan.
Module G := Selvedge.Generated.Commands.

Lemma admitted_maintenance_runs_its_resolved_plan : forall id request before,
 maintenance_admission id request before = true ->
 exists reference : R.maintenance_reference before id request,
   A.run_request id request before = R.maintenance_issue reference.
Proof.
 intros id request before Ready; pose proof Ready as HasOwner.
 unfold maintenance_admission in HasOwner.
 destruct (K.find_task id before) as [current|] eqn:Found; [|discriminate].
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [[owner selected Observed] [Selected [Owner Current]]].
 cbn in Owner,Current; subst owner.
 destruct (admitted_maintenance_has_a_selected_plan before id request selected Observed Ready)
   as [admitted Resolved].
 exists admitted.
 unfold A.run_request; rewrite Selected; unfold A.run_request_selected.
 cbn [TaskScope.owner TaskScope.selected TaskScope.observed]; now rewrite Resolved.
Qed.

Lemma a_blocked_model_waits_with_live_operations : forall id value task operations,
 K.find_task id value = Some task ->
 task_lifecycle task = Running ReadyForModel operations ->
 Scheduler.ready_operation operations = None ->
 A.blocked task (A.current_entry id (A.registry value)) value = true ->
 A.can_schedule_task id value = false.
Proof.
 intros id value task operations found running pending budget.
 unfold A.can_schedule_task. now rewrite found, running, pending, budget.
Qed.

Theorem measuring_model_waits_with_live_operations : forall id value task operations target ticket input stage,
 K.find_task id value = Some task ->
 task_lifecycle task = Running ReadyForModel operations ->
 Scheduler.ready_operation operations = None ->
 A.enabled_target task (A.registry value) = Some target ->
 C.entry_measurement (A.current_entry id (A.registry value)) = C.Measuring (RequestEnvelope.Envelope ticket (InspectInput input tt stage)) ->
 A.can_schedule_task id value = false.
Proof.
 intros id value task operations target ticket input stage found running pending enabled measuring.
 eapply a_blocked_model_waits_with_live_operations; eauto.
 unfold A.blocked. rewrite enabled, measuring. cbn.
 now destruct (A.validating (C.entry_job (A.current_entry id (A.registry value)))).
Qed.

Theorem ready_operations_do_not_wait_for_model_measurement : forall id value task operations operation,
 K.find_task id value = Some task ->
 task_lifecycle task = Running ReadyForModel operations ->
 Scheduler.ready_operation operations = Some operation ->
 A.can_schedule_task id value = true.
Proof.
 intros id value task operations operation found running ready.
 unfold A.can_schedule_task. now rewrite found, running, ready.
Qed.

(** A new side-parent observation can invalidate a previously completed count.
    The shared synchronization step starts a request for that actual current
    capture; it does not leave the ready model waiting on the old count. *)
Theorem a_stale_ready_measurement_is_planned_again :
 forall id value current operations target entry input scope tokens budget,
 task_lifecycle current = Running ReadyForModel operations ->
 TicketedRequest.Scoped.resources_available current value = true ->
 A.enabled_target current (A.registry value) = Some target ->
 entry = A.synchronized_entry current (A.current_entry id (A.registry value)) ->
 entry_job entry = NoJob -> entry_measurement entry = Measured input scope tokens budget ->
 A.fresh (entry_measurement entry) current value = false ->
 A.synchronize id current value = Some (A.begin_scope id (A.capture_task current value) None entry value).
Proof.
 intros id value current operations target entry input scope tokens budget
   Lifecycle Available Enabled Entry Job Measured Stale.
 assert (Phase : task_activity current = ReadyForModel)
   by (unfold task_activity; now rewrite Lifecycle).
 assert (NotIdle : A.idle_due current entry (A.registry value) = false).
 { unfold A.idle_due,A.idle; rewrite Phase; now rewrite !andb_false_r. }
 unfold A.synchronize; cbv beta zeta; unfold A.current_entry in Entry; rewrite <- Entry.
 unfold A.alive,A.running; rewrite Lifecycle,Available; cbn.
 rewrite Phase,Job,Enabled,Measured; cbn [A.validating A.pending_measurement].
 rewrite NotIdle; rewrite Measured in Stale; now rewrite Stale.
Qed.

(** Already decoded observations retain their journal and scheduler role even
    when their owned request has expired. Receiver admission is shared. *)
Theorem an_unresolved_observation_retains_journal_ordering : forall event value,
 A.resolve event value = None ->
 A.completion event value = (true,true,A.acknowledged value []).
Proof. intros; unfold A.completion; now rewrite H. Qed.
Theorem clock_observation_uses_monotone_time : forall now value,
 A.completion (Clock now) value = (true,true,
 A.acknowledged (A.store (set maintenance_timer (fun _ => 0) (A.with_now now (A.registry value))) value) []).
Proof. reflexivity. Qed.
Lemma storing_maintenance_preserves_tasks : forall id state value,
 K.find_task id (A.store state value) = K.find_task id value.
Proof. reflexivity. Qed.
Lemma supplied_history_is_an_append : forall id task summary value,
 K.find_task id value = Some task ->
 exists stored, K.find_task id (CommandResult.change_world (A.supplied_change id task summary value)) = Some stored /\
 task_history stored = (task_history task ++ [ContextSelection.record (task_history task) (ContextSelection.portable (Selvedge.Kernel.Compaction.summary_text summary))])%list.
Proof.
 intros. unfold A.supplied_change,A.commit_change.
 cbn -[A.store K.put_task ContextSelection.adopt]. rewrite storing_maintenance_preserves_tasks.
 eexists. split; [eapply find_put_task;exact H|].
 change (ContextSelection.adopt (task_history task) (ContextSelection.portable (Selvedge.Kernel.Compaction.summary_text summary)) (task_history task) =
 (task_history task ++ [ContextSelection.record (task_history task) (ContextSelection.portable (Selvedge.Kernel.Compaction.summary_text summary))])%list).
 apply a_current_snapshot_can_be_adopted.
Qed.
(** This positive contract constrains the actual typed command entry, excluding
    implementations that reject every checkpoint or discard its source history. *)
Theorem a_valid_checkpoint_preserves_its_original_records : forall payload id summary caller task value,
 G.compact_task_id payload = id -> G.compact_summary_admitted payload = Some summary ->
 K.find_task id value = Some task -> A.alive task = true -> A.idle task = true ->
 ContextSelection.closed_prefix (task_history task) = true ->
 A.handle_compact_result payload caller value = CommandResult.Accepted (A.supplied_change id task summary value) /\
 exists stored, K.find_task id (CommandResult.change_world (A.supplied_change id task summary value)) = Some stored /\
 task_history stored = (task_history task ++ [ContextSelection.record (task_history task) (ContextSelection.portable (Selvedge.Kernel.Compaction.summary_text summary))])%list.
Proof.
 intros payload id summary caller task value Id Summary H H0 H1 H2. split.
 - destruct (selecting_an_existing_task_retains_its_key id value task H)
     as [[owner current Observed] [Selected [Owner Current]]].
   cbn in Owner,Current; subst owner current.
   unfold A.handle_compact_result; rewrite Id,Summary.
   rewrite Selected; cbn [TaskScope.selected]; rewrite H0,H1; cbn; now rewrite H2.
 - apply supplied_history_is_an_append. assumption.
Qed.
Theorem measured_scope_and_reserve_reach_the_executed_request : forall request scope tokens budget input value,
 entry_measurement (A.current_entry (Selvedge.Kernel.ModelRequest.owner request) (A.registry value)) = Measured input scope tokens budget ->
 A.prepare_model_effects value [K.RequestModel request] =
 [K.RequestModel (Selvedge.Kernel.ModelRequest.with_context scope (reserve_tokens budget) request)].
Proof. intros. unfold A.prepare_model_effects. cbn. now rewrite H. Qed.


Theorem manual_compaction_captures_context_before_any_summary_request :
 forall value (target : TaskScope.task_reference value) entry,
 let id := TaskScope.owner target in let current := TaskScope.selected target in
 R.can_observe_maintenance current value = true ->
 ContextSelection.closed_prefix (task_history current) = true ->
 entry = A.current_entry id (A.registry value) ->
 A.job_pending (entry_job entry) = false ->
 CommandResult.change_effects (A.manual_change target) =
 (map K.MaintainContext (A.cancellations id entry) ++
  [K.ObserveContext id (K.world_next_ticket value) current])%list.
Proof.
 intros value target entry; cbn zeta; intros ObserveAllowed Closed Entry Ready.
 destruct (maintenance_observation_uses_the_current_task value target
   (Some Manual) entry ObserveAllowed Closed) as [request [Planned Effects]].
 unfold A.manual_change; rewrite <- Entry,Ready.
 unfold A.wait_for_context_selected; rewrite Planned.
 cbn [CommandResult.change_effects]; now rewrite Effects.
Qed.

Definition manual_waiting_entry (current : task) (entry : C.entry) (before : K.world) :=
 A.with_observation None (A.with_measurement Unmeasured
   (A.with_job (Resuming (A.capture_task current before) Manual) entry)).
Definition manual_waiting_world (id : N) (current : task) (before : K.world) :=
 A.store (A.with_entry id
   (manual_waiting_entry current (A.current_entry id (A.registry before)) before)
   (A.registry before)) before.
(** This is the public command with a live operation, not an assumed accepted
    helper result. The wait keeps the task, operation and queued demand intact;
    only obsolete maintenance requests are cancelled. *)
Theorem manual_compaction_accepts_an_open_prefix_and_waits :
 forall payload id current operations caller before,
 G.compact_task_id payload = id -> G.compact_summary_admitted payload = None ->
 K.find_task id before = Some current ->
 task_lifecycle current = Running Idle operations ->
 TicketedRequest.Scoped.resources_available current before = true ->
 A.job_pending (entry_job (A.current_entry id (A.registry before))) = false ->
 ContextSelection.closed_prefix (task_history current) = false ->
 let result := A.handle_compact payload caller before in
 bool_default "ok" (K.decision_reply result) false = true /\
 K.decision_world result = manual_waiting_world id current before /\
 K.decision_effects result =
   map K.MaintainContext (A.cancellations id (A.current_entry id (A.registry before))).
Proof.
 intros payload id current operations caller before Id Summary Found Lifecycle Available NoJob Open.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [[owner task Observed] [Selected [Owner Current]]].
 cbn in Owner,Current; subst owner task.
 pose proof (an_open_summary_prefix_has_no_context_plan before
   (TaskScope.TaskReference before id current Observed) Manual
   (A.current_entry id (A.registry before)) Open) as NoPlan.
 assert (Alive : A.alive current = true) by (unfold A.alive; now rewrite Lifecycle).
 assert (RunningTask : A.running current = true) by (unfold A.running; now rewrite Lifecycle).
 assert (Phase : task_activity current = Idle) by (unfold task_activity; now rewrite Lifecycle).
 unfold A.handle_compact,A.handle_compact_result; rewrite Id,Summary.
 rewrite Selected; cbn [TaskScope.selected]; rewrite Alive,Phase,RunningTask; cbn [CommandResult.decide].
 unfold A.manual_change,CommandResult.accept; cbn [TaskScope.owner]; rewrite NoJob.
 change (A.R.maintenance_context_selected
   (TaskScope.TaskReference before id current Observed) (Some Manual)
   (A.current_entry id (A.registry before)) = None) in NoPlan.
 unfold A.wait_for_context_selected; rewrite NoPlan.
 cbn [TaskScope.owner TaskScope.selected].
 unfold A.retain_context_wait; rewrite Available.
 unfold manual_waiting_world, manual_waiting_entry.
 cbn [A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_world K.decision_effects].
 rewrite app_nil_r; repeat split; reflexivity.
Qed.

Theorem an_open_manual_wait_preserves_all_task_state : forall id current before,
 K.world_tasks (manual_waiting_world id current before) = K.world_tasks before /\
 entry_job (A.current_entry id (A.registry
   (manual_waiting_world id current before))) =
 Resuming (A.capture_task current before) Manual.
Proof.
 intros; split; [reflexivity|].
 unfold manual_waiting_world, manual_waiting_entry,
   A.current_entry, A.find_entry, A.registry, A.store, A.with_entry, R.compaction_entries, Receiver.install, Receiver.field, Receiver.inject, Receiver.keyed, A.with_observation,
   A.with_measurement, A.with_job, K.with_features, Selvedge.Features.State.with_compaction, set;
 cbn. now rewrite N.eqb_refl.
Qed.

(** Results, cancellations and running announcements may close the source.
    Synchronization then captures the whole current prefix, including those
    records; it never reuses the open prefix saved when the request arrived. *)
Theorem a_closed_manual_wait_recaptures_its_current_prefix :
 forall id current before input entry operations phase,
 task_lifecycle current = Running phase operations ->
 phase <> WantsModel -> (forall ticket revision continuation, phase <> ObservingContext ticket revision continuation) ->
 TicketedRequest.Scoped.resources_available current before = true ->
 entry = A.synchronized_entry current (A.current_entry id (A.registry before)) ->
 entry_job entry = Resuming input Manual ->
 A.relevant input current before = true ->
 ContextSelection.closed_prefix (task_history current) = true ->
 A.synchronize id current before =
 Some (A.begin_scope id (A.capture_task current before) (Some Manual) (A.with_job NoJob entry) before).
Proof.
 intros id current before input entry operations phase Lifecycle NoDemand NoObservation
   Available Entry Job Relevant Closed.
 assert (Phase : task_activity current = phase) by (unfold task_activity; now rewrite Lifecycle).
 unfold A.synchronize; cbv beta zeta; unfold A.current_entry in Entry; rewrite <- Entry.
 unfold A.alive, A.running; rewrite Lifecycle, Available; cbn.
 rewrite Phase. destruct phase; try contradiction;
 try (exfalso; eapply NoObservation; reflexivity);
 rewrite Job, Relevant, Closed; reflexivity.
Qed.

Theorem an_open_manual_wait_keeps_waiting_without_io :
 forall id current before input entry operations,
 task_lifecycle current = Running Idle operations ->
 TicketedRequest.Scoped.resources_available current before = true ->
 entry = A.synchronized_entry current (A.current_entry id (A.registry before)) ->
 entry_job entry = Resuming input Manual ->
 A.relevant input current before = true ->
 ContextSelection.closed_prefix (task_history current) = false ->
 A.synchronize id current before = None.
Proof.
 intros id current before input entry operations Lifecycle Available Entry Job Relevant Open.
 assert (Phase : task_activity current = Idle) by (unfold task_activity; now rewrite Lifecycle).
 unfold A.synchronize; cbv beta zeta; unfold A.current_entry in Entry; rewrite <- Entry.
 unfold A.alive, A.running; rewrite Lifecycle, Available; cbn.
 now rewrite Phase, Job, Relevant, Open.
Qed.

Theorem a_closed_manual_wait_starts_a_fresh_context_read :
 forall id current before input entry operations phase,
 K.find_task id before = Some current ->
 task_lifecycle current = Running phase operations ->
 (phase = Idle \/ phase = ReadyForModel) ->
 TicketedRequest.Scoped.resources_available current before = true ->
 entry = A.synchronized_entry current (A.current_entry id (A.registry before)) ->
 entry_job entry = Resuming input Manual ->
 entry_observation (A.current_entry id (A.registry before)) = None ->
 A.relevant input current before = true ->
 ContextSelection.closed_prefix (task_history current) = true ->
 exists result, A.synchronize id current before = Some result /\
 K.decision_effects result = [K.ObserveContext id (K.world_next_ticket before) current].
Proof.
 intros id current before input entry operations phase Found Lifecycle Phase Available Entry Job Unobserved Relevant Closed.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [[owner selected Observed] [Selected [Owner Current]]].
 cbn in Owner,Current; subst owner selected.
 assert (CanObserve : R.can_observe_maintenance current before = true).
 { unfold R.can_observe_maintenance; rewrite Available,Lifecycle;
   destruct Phase as [Phase|Phase]; subst phase; reflexivity. }
 destruct (maintenance_observation_uses_the_current_task before
   (TaskScope.TaskReference before id current Observed) (Some Manual) (A.with_job NoJob entry) CanObserve Closed)
   as [request [Planned Effects]].
 change (A.R.maintenance_context_selected
   (TaskScope.TaskReference before id current Observed) (@Some A.R.C.reason Manual)
   (A.with_job NoJob entry) = Some request) in Planned.
 exists (A.begin_scope id (A.capture_task current before) (Some Manual) (A.with_job NoJob entry) before).
 split.
 - eapply a_closed_manual_wait_recaptures_its_current_prefix; eauto;
     destruct Phase as [Phase|Phase]; subst phase; discriminate.
 - unfold A.begin_scope,A.run_request; rewrite Selected.
   unfold A.run_request_selected,R.maintenance_selected;
     cbn [TaskScope.owner TaskScope.selected TaskScope.observed].
   apply observe_cases.
   + intros stored Stored.
     assert (Missing : entry_observation stored = None).
     { unfold A.current_entry in Unobserved.
       change (A.find_entry id (A.registry before) = Some stored) in Stored.
       now rewrite Stored in Unobserved. }
     unfold R.maintenance_observed,R.boolean_admission.
     destruct (Bool.bool_dec _ true) as [Eligible|Unavailable].
     { exfalso; unfold R.maintenance_ready_from in Eligible.
       rewrite Missing,!andb_false_r in Eligible; discriminate. }
     cbn [option_map R.maintenance_waiting_entry R.ScopeRequest R.initial_purpose R.request_entry R.purpose_reason].
     unfold A.wait_for_context_selected; rewrite Planned; exact Effects.
   + intros Absent; cbn [R.maintenance_waiting_entry R.ScopeRequest R.initial_purpose R.request_entry R.purpose_reason].
     unfold A.wait_for_context_selected; rewrite Planned; exact Effects.
Qed.

Theorem suspended_manual_context_completion_cancels_its_job :
 forall id ticket revision before result previous task operations,
 K.find_task id before = Some previous ->
 task_activity previous = ObservingContext ticket revision (ForMaintenance (Some Manual) false) ->
 K.find_task id (K.decision_world result) = Some task ->
 A.cancelled_task id (K.decision_effects result) = false ->
 A.cancelled_ticket id ticket (K.decision_effects result) = false ->
 (task_lifecycle task = Frozen WantsModel operations \/ task_lifecycle task = Stopped WantsModel operations) ->
 exists reason,
 let cancelled := TaskWake.promote (with_activity Idle (append_history [FailureMessage reason] task)) in
 DecisionComposition.run (A.observe_transition before (Some (id,ticket)) id) result =
 DecisionComposition.follow result (A.cancel id cancelled (A.current_entry id (A.registry (K.decision_world result)))
   (K.put_task id cancelled (K.decision_world result))) /\
 task_activity cancelled = Idle /\
 entry_job (A.clear_entry cancelled (A.current_entry id (A.registry (K.decision_world result)))) = NoJob.
Proof.
 intros id ticket revision before result previous task operations Previous Phase Found NotCancelled NotSteered Paused.
 exists "Context summary was not sent because the task is frozen or stopped; original history retained"; intro cancelled.
 unfold DecisionComposition.run, DecisionComposition.transform, DecisionComposition.maintain, A.observe_transition; rewrite Previous, Found, NotCancelled, Phase, NotSteered, !N.eqb_refl.
 cbn [andb]. unfold A.finish_context.
 destruct Paused as [FrozenTask|StoppedTask].
 - assert (Activity : task_activity task = WantsModel) by (unfold task_activity; rewrite FrozenTask; reflexivity).
   rewrite Activity, FrozenTask. split; [reflexivity|]. split; [|reflexivity].
   unfold cancelled. destruct task as [contract profile settings lifecycle history queued lineage handoff consumed].
   cbn in FrozenTask; subst lifecycle; reflexivity.
 - assert (Activity : task_activity task = WantsModel) by (unfold task_activity; rewrite StoppedTask; reflexivity).
   rewrite Activity, StoppedTask. split; [reflexivity|]. split; [|reflexivity].
   unfold cancelled. destruct task as [contract profile settings lifecycle history queued lineage handoff consumed].
   cbn in StoppedTask; subst lifecycle; destruct queued; reflexivity.
Qed.

Theorem a_suspended_observation_preserves_exactly_its_model_demand :
 forall purpose demand current operations,
 (task_lifecycle current = Frozen WantsModel operations \/ task_lifecycle current = Stopped WantsModel operations) ->
 task_activity (A.suspended_context_task purpose demand current) = if demand then WantsModel else Idle.
Proof.
 intros purpose demand [contract profile settings lifecycle history queued lineage handoff consumed] operations Status.
 cbn in Status. destruct Status as [Status|Status]; subst lifecycle;
   unfold A.suspended_context_task; destruct purpose as [purpose|]; try destruct purpose;
   destruct demand; destruct queued; reflexivity.
Qed.

Theorem a_replaced_context_never_consumes_the_new_task_demand :
 forall id ticket revision purpose resume_model before result previous current,
 K.find_task id before = Some previous ->
 task_activity previous = ObservingContext ticket revision (ForMaintenance purpose resume_model) ->
 K.find_task id (K.decision_world result) = Some current ->
 A.cancelled_ticket id ticket (K.decision_effects result) = true ->
 K.world_tasks (K.decision_world (DecisionComposition.run (A.observe_transition before None id) result)) = K.world_tasks (K.decision_world result) /\
 K.decision_effects (DecisionComposition.run (A.observe_transition before None id) result) = K.decision_effects result.
Proof.
 intros id ticket revision purpose resume_model before result previous current Previous Phase Current Cancelled.
 unfold DecisionComposition.run, DecisionComposition.transform, DecisionComposition.maintain, A.observe_transition.
 rewrite Previous, Current.
 destruct (A.cancelled_task id (K.decision_effects result)); [|rewrite Phase, Cancelled];
 split; cbn [A.commit A.commit_change K.decision_world K.decision_effects];
 try rewrite app_nil_r; reflexivity.
Qed.

Theorem a_stale_context_completion_preserves_the_selected_maintenance :
 forall id ticket stale revision purpose resume_model before result previous current,
 K.find_task id before = Some previous ->
 task_activity previous = ObservingContext ticket revision (ForMaintenance purpose resume_model) ->
 K.find_task id (K.decision_world result) = Some current ->
 A.cancelled_task id (K.decision_effects result) = false ->
 A.cancelled_ticket id ticket (K.decision_effects result) = false ->
 N.eqb ticket stale = false ->
 DecisionComposition.run (A.observe_transition before (Some (id,stale)) id) result = result.
Proof.
 intros id ticket stale revision purpose resume_model before result previous current Previous Phase Current Task Ticket Stale.
 unfold DecisionComposition.run, DecisionComposition.transform, DecisionComposition.maintain, A.observe_transition.
 rewrite Previous, Current, Task, Phase, Ticket, N.eqb_refl, Stale.
 destruct result; cbn; now rewrite app_nil_r.
Qed.

Theorem recovery_of_pending_operations_creates_the_retained_frozen_demand :
 forall id current ticket revision purpose operations,
 task_lifecycle current = Frozen (ObservingContext ticket revision (ForMaintenance purpose false)) operations ->
 operations <> [] ->
 task_activity (Recovery.recover_task id (A.retire_context_task current)) = WantsModel.
Proof.
 intros id current ticket revision purpose operations Lifecycle Pending.
 assert (Phase : task_activity current = ObservingContext ticket revision (ForMaintenance purpose false))
   by (unfold task_activity; now rewrite Lifecycle).
 unfold A.retire_context_task; rewrite Phase.
 destruct current as [contract profile settings lifecycle history queued lineage handoff consumed].
 cbn in Lifecycle; subst lifecycle; destruct operations; [contradiction|reflexivity].
Qed.

Theorem manual_context_recovery_does_not_invent_model_demand :
 forall task ticket revision,
 task_activity task = ObservingContext ticket revision (ForMaintenance (Some Manual) false) ->
 A.retire_context_task task = with_activity Idle task.
Proof. intros; unfold A.retire_context_task; now rewrite H. Qed.

Lemma cancellations_name_exact_pending_tickets : forall owner id ticket entry,
 In (Cancel owner ticket) (A.cancellations id entry) <->
 owner = id /\ (A.measurement_ticket (entry_measurement entry) = Some ticket \/
   A.job_ticket (entry_job entry) = Some ticket).
Proof.
 intros; unfold A.cancellations.
 destruct (A.measurement_ticket (entry_measurement entry));
 destruct (A.job_ticket (entry_job entry)); cbn; intuition congruence.
Qed.

Theorem live_reconfiguration_cancels_exactly_the_retired_requests : forall value id ticket,
 In (K.MaintainContext (Cancel id ticket)) (K.decision_effects (A.reconfigure value)) <->
 exists entry, In (id,entry) (maintenance_entries (A.registry value)) /\
   (A.measurement_ticket (entry_measurement entry) = Some ticket \/
    A.job_ticket (entry_job entry) = Some ticket \/
    exists task, K.find_task id value = Some task /\
      maintenance_context_ticket (task_activity task) = Some ticket).
Proof.
 intros value id ticket; cbn [A.reconfigure A.acknowledged K.accept K.decision_effects].
 rewrite in_map_iff; unfold A.pending_cancellations; setoid_rewrite in_flat_map.
 assert (Context : forall owner,
   In (Cancel id ticket) (match K.find_task owner value with
     | Some task => A.context_cancellations owner task | None => [] end) <->
   owner = id /\ exists task, K.find_task owner value = Some task /\
     maintenance_context_ticket (task_activity task) = Some ticket).
 { intro owner; unfold A.context_cancellations.
   destruct (K.find_task owner value) as [task|].
   - destruct (maintenance_context_ticket (task_activity task)) as [expected|] eqn:Ticket.
     + cbn. split.
       * intros [Same|[]]. inversion Same; subst. split; [reflexivity|].
         exists task; auto.
       * intros [Same [current [Found Current]]]. inversion Found; subst.
         rewrite Ticket in Current; inversion Current; now left.
     + split; [contradiction|].
       intros [_ [current [Found Current]]]. inversion Found; subst; congruence.
   - split; [contradiction|]. intros [_ [current [Found _]]]; discriminate. }
 split.
 - intros [request [Same [[owner entry] [Present Pending]]]]. inversion Same; subst request; cbn in Pending.
   apply in_app_or in Pending as [Compaction|Observation].
   + apply cancellations_name_exact_pending_tickets in Compaction as [Owner [Measured|Job]];
       subst owner; exists entry; firstorder.
   + apply Context in Observation as [Owner Observation]; subst owner; exists entry; firstorder.
 - intros [entry [Present Pending]].
   exists (Cancel id ticket); split; [reflexivity|].
   exists (id,entry); split; [exact Present|]. cbn.
   apply in_or_app. destruct Pending as [Measured|[Job|Observation]].
   + left; apply cancellations_name_exact_pending_tickets; auto.
   + left; apply cancellations_name_exact_pending_tickets; auto.
   + right; apply Context; auto.
Qed.

Theorem live_reconfiguration_uses_the_existing_recovery_state : forall value,
 K.decision_world (A.reconfigure value) = A.recover value.
Proof. reflexivity. Qed.

Lemma recovered_entries_retain_no_pending_ticket : forall entry,
 A.measurement_ticket (entry_measurement (A.recover_entry entry)) = None /\
 A.job_ticket (entry_job (A.recover_entry entry)) = None.
Proof.
 intros; unfold A.recover_entry, A.with_observation, A.with_measurement, A.with_job, set; cbn.
 split; [reflexivity|]. unfold A.resume, A.job_ticket.
 destruct (entry_job entry) as [|purpose|input purpose|
   [ticket [input purpose stage]]|[ticket [input purpose progress scope]]|
   [ticket [input [purpose candidate preview] stage]]]; reflexivity.
Qed.

Lemma live_reconfiguration_recovers_the_selected_task : forall value id task,
 K.find_task id value = Some task ->
 K.find_task id (K.decision_world (A.reconfigure value)) =
 Some (A.retire_context_task task).
Proof.
 intros value id task Found; rewrite live_reconfiguration_uses_the_existing_recovery_state.
 unfold A.recover; rewrite storing_maintenance_preserves_tasks.
 unfold A.retire_context_tasks, K.find_task, K.with_tasks, set; cbn.
 unfold K.find_task in Found.
 rewrite registry_lookup_commutes_with_mapping, Found; reflexivity.
Qed.

Theorem live_reconfiguration_retains_the_saved_inference_demand :
 forall value id task ticket revision purpose resume_model,
 K.find_task id value = Some task ->
 task_activity task = ObservingContext ticket revision (ForMaintenance purpose resume_model) ->
 K.find_task id (K.decision_world (A.reconfigure value)) =
 Some (with_activity (if resume_model then WantsModel else Idle) task).
Proof.
 intros; rewrite (live_reconfiguration_recovers_the_selected_task value id task H).
 unfold A.retire_context_task; now rewrite H0.
Qed.

Theorem live_reconfiguration_preserves_an_unrelated_context_receiver :
 forall value id task ticket revision,
 K.find_task id value = Some task ->
 task_activity task = ObservingContext ticket revision ForInference ->
 K.find_task id (K.decision_world (A.reconfigure value)) = Some task.
Proof.
 intros value id task ticket revision Found Phase.
 rewrite (live_reconfiguration_recovers_the_selected_task value id task Found).
 unfold A.retire_context_task; now rewrite Phase.
Qed.

Theorem manual_compaction_waits_without_resource_io : forall value
 (target : TaskScope.task_reference value) entry,
 let id := TaskScope.owner target in let current := TaskScope.selected target in
 TicketedRequest.Scoped.resources_available current value = false ->
 entry = A.current_entry id (A.registry value) ->
 A.job_pending (entry_job entry) = false ->
 CommandResult.change_effects (A.manual_change target) = map K.MaintainContext (A.cancellations id entry) /\
 entry_job (A.current_entry id (A.registry (CommandResult.change_world (A.manual_change target)))) =
   WaitingForResource (Some Manual).
Proof.
 intros value target entry; cbn zeta; intros Unavailable Entry Ready.
 assert (NoObservation : R.can_observe_maintenance (TaskScope.selected target) value = false).
 { unfold R.can_observe_maintenance; now rewrite Unavailable. }
 pose proof (unavailable_maintenance_observation_has_no_plan value target (Some Manual) entry NoObservation) as NoPlan.
 change (A.R.maintenance_context_selected target (Some Manual) entry = None) in NoPlan.
 unfold A.manual_change; rewrite <- Entry,Ready.
 unfold A.wait_for_context_selected; rewrite NoPlan.
 unfold A.retain_context_wait; rewrite Unavailable.
 split.
 - cbn [A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_effects]. apply app_nil_r.
 - cbn [A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_world].
   unfold A.current_entry,A.find_entry,A.registry,A.store,A.with_entry, R.compaction_entries, Receiver.install, Receiver.field, Receiver.inject, Receiver.keyed,A.with_observation,
     A.with_measurement,A.with_job,K.with_features,Selvedge.Features.State.with_compaction,set;
   cbn; now rewrite N.eqb_refl.
Qed.

Theorem captured_images_select_structured_summary :
 forall id task input purpose target scope tokens entry value observed image,
 In observed (captured_history input) -> In image (History.message_images observed) ->
 let messages := ContextSelection.history_json id (captured_history input) in
 A.start id task input purpose target scope tokens entry value =
 A.dispatch_compact id task input purpose
   (Selvedge.Kernel.Compaction.CompactionState
     (Selvedge.Kernel.Compaction.StructuredSource
       (JArray (ContextSelection.target_messages messages scope))
       (JArray (ContextSelection.target_messages messages ""))) ""
     (window_tokens (target_budget target)) (window_tokens (target_budget target))
     (reserve_tokens (target_budget target))) scope entry value.
Proof.
 intros id task input purpose target scope tokens entry value observed image Present Image messages.
 unfold A.start.
 rewrite (images_select_structured_summary (captured_history input) observed image
   _ _ _ _ _ _ _ Present Image). reflexivity.
Qed.

Theorem an_oversized_compaction_request_stops :
 forall id task input purpose progress scope entry value fitted,
 P.fit_transport progress (Limits.frame_bytes / 4 -
   CC.compact_metadata_bytes id (K.world_next_ticket value) input scope) = Some fitted ->
 Limits.frame_bytes / 4 < N.of_nat (String.length (TextJson.render_json
   (CC.compact_json id (K.world_next_ticket value) input fitted scope))) ->
 exists reason, A.dispatch_compact id task input purpose progress scope entry value =
   A.failed id task entry reason value.
Proof.
 intros id task input purpose progress scope entry value fitted Fitted Oversized.
 unfold A.dispatch_compact; rewrite Fitted.
 apply N.leb_gt in Oversized; rewrite Oversized, andb_false_r.
 eexists; reflexivity.
Qed.

Theorem a_nonempty_zero_width_compaction_request_stops :
 forall id task input purpose progress scope entry value unread carry window reserve,
 P.fit_transport progress (Limits.frame_bytes / 4 -
   CC.compact_metadata_bytes id (K.world_next_ticket value) input scope) =
   Some (Selvedge.Kernel.Compaction.CompactionState
     (Selvedge.Kernel.Compaction.PortableSource unread) carry 0 window reserve) ->
 unread <> [] ->
 exists reason, A.dispatch_compact id task input purpose progress scope entry value =
   A.failed id task entry reason value.
Proof.
 intros id task input purpose progress scope entry value unread carry window reserve Fitted Nonempty.
 unfold A.dispatch_compact; rewrite Fitted.
 destruct unread; [contradiction|]. eexists; reflexivity.
Qed.

Theorem a_resize_callback_reduces_width_or_stops :
 forall id task input purpose progress scope entry value,
 A.relevant input task value = true ->
 (exists smaller,
   (forall fitted, P.fit_transport smaller (Limits.frame_bytes / 4 -
     CC.compact_metadata_bytes id (K.world_next_ticket value) input scope) = Some fitted ->
     Selvedge.Kernel.Compaction.compaction_chunk_chars fitted <
       Selvedge.Kernel.Compaction.compaction_chunk_chars progress) /\
   A.compacted_result id task (CompactInput input purpose progress scope)
     (JObject [("action",JString "resize")]) false entry value =
   A.dispatch_compact id task input purpose smaller scope entry value) \/
 (exists reason, A.compacted_result id task (CompactInput input purpose progress scope)
   (JObject [("action",JString "resize")]) false entry value = A.failed id task entry reason value).
Proof.
 intros id task input purpose progress scope entry value Relevant.
 destruct (resize_reduces_width_or_fails progress) as [[smaller [Resized Smaller]]|[reason Failed]].
 - left; exists smaller; split.
   + intros fitted Fitted. eapply N.le_lt_trans; [|exact Smaller].
     eapply fitted_transport_does_not_increase_width; exact Fitted.
   + change (P.receive progress (JObject [("action",JString "resize")]) = P.Next smaller) in Resized.
     unfold A.compacted_result; now rewrite Relevant, Resized.
 - right; exists reason.
   change (P.receive progress (JObject [("action",JString "resize")]) = P.Failed reason) in Failed.
   unfold A.compacted_result; now rewrite Relevant, Failed.
Qed.

(** The feature callback forwards the recovered summary plan with its
    captured input and scope. *)
Theorem native_unavailable_callback_dispatches_summary :
 forall id task input purpose progress scope entry value summary,
 A.relevant input task value = true ->
 P.receive progress (JObject [("action",JString "native_unavailable")]) = P.Next summary ->
 A.compacted_result id task (CompactInput input purpose progress scope)
   (JObject [("action",JString "native_unavailable")]) false entry value =
 A.dispatch_compact id task input purpose summary scope entry value.
Proof.
 intros id task input purpose progress scope entry value summary Relevant Recovered.
 unfold A.compacted_result. rewrite Relevant,Recovered. reflexivity.
Qed.

(** Candidate validation may change representation from native to portable,
    but cannot start another summary of the same source after portable failure.
    These contracts cover both actual validation exits, not a retry counter in
    a separate Host interpreter. *)
Theorem an_oversized_portable_validation_stops :
 forall id task input purpose first rest preview scope tokens budget entry value,
 A.relevant input task value = true ->
 A.same_history preview
   (ContextSelection.adopt (captured_history input) (PortableArtifact first rest) (task_history task)) = true ->
 (tokens + reserve_tokens budget <=? window_tokens budget) = false ->
 exists reason, A.finish_validation id task input purpose (PortableArtifact first rest)
   preview scope tokens budget entry value = A.failed id task entry reason value.
Proof.
 intros id task input purpose first rest preview scope tokens budget entry value Relevant Preview Oversized.
 unfold A.finish_validation; rewrite Relevant; cbn [ContextSelection.consumes].
 rewrite Preview, Oversized; eexists; reflexivity.
Qed.

Theorem an_oversized_native_validation_keeps_portable_fallback :
 forall id task input purpose head tail first rest preview scope tokens budget entry value,
 let candidate := NativeArtifact head tail first rest in
 A.relevant input task value = true -> ContextSelection.consumes candidate scope = true ->
 A.same_history preview (ContextSelection.adopt (captured_history input) candidate (task_history task)) = true ->
 ((tokens + reserve_tokens budget <=? window_tokens budget) &&
   negb (policy_enabled (maintenance_policy (A.registry value)) &&
     (window_tokens budget * policy_blocking (maintenance_policy (A.registry value)) <=? tokens * 100))) = false ->
 A.finish_validation id task input purpose candidate preview scope tokens budget entry value =
 A.force_portable id task scope entry value.
Proof.
 intros id task input purpose head tail first rest preview scope tokens budget entry value candidate Relevant Consumes Preview Oversized.
 unfold candidate in *.
 unfold A.finish_validation; now rewrite Relevant, Consumes, Preview, Oversized.
Qed.

Theorem an_oversized_portable_validation_frame_stops :
 forall id task input scope purpose first rest preview entry value,
 let candidate := R.ValidateCandidate (Candidate purpose (PortableArtifact first rest) preview) in
 let request := R.MeasureRequest input candidate scope entry in
 (N.of_nat (String.length (TextJson.render_json (R.preview_json id (K.world_next_ticket value) request value)))
   <=? Limits.frame_bytes / 4) = false ->
 exists reason, A.measured_call id task input scope candidate entry value =
 A.failed id task entry reason value.
Proof.
 intros id task input scope purpose first rest preview entry value candidate request Oversized.
 unfold A.measured_call. fold request. rewrite Oversized; eexists; reflexivity.
Qed.

Theorem an_oversized_measurement_without_a_portable_candidate_can_rebuild :
 forall id task input scope purpose entry value,
 (forall first rest, R.purpose_candidate purpose <> Some (PortableArtifact first rest)) ->
 let request := R.MeasureRequest input purpose scope entry in
 (N.of_nat (String.length (TextJson.render_json (R.preview_json id (K.world_next_ticket value) request value)))
   <=? Limits.frame_bytes / 4) = false ->
 A.measured_call id task input scope purpose entry value =
 A.force_portable id task scope entry value.
Proof.
 intros id task input scope purpose entry value NotPortable request Oversized.
 unfold A.measured_call. fold request. rewrite Oversized.
 destruct purpose as [|purpose|[purpose candidate preview]]; [reflexivity|reflexivity|].
 destruct candidate; try reflexivity. exfalso; eapply NotPortable; reflexivity.
Qed.

Theorem a_portable_source_can_only_finish_with_a_portable_candidate :
 forall progress result candidate unread,
 Selvedge.Kernel.Compaction.compaction_source progress = Selvedge.Kernel.Compaction.PortableSource unread ->
 P.receive_source progress result = P.Compacted candidate ->
 exists first rest, candidate = PortableArtifact first rest.
Proof.
 intros progress result candidate unread Portable Finished.
 unfold P.receive_source in Finished; rewrite Portable in Finished.
 unfold P.receive_summary in Finished.
 destruct (string_field "summary_text" result) as [[|head tail]|]; try discriminate.
 destruct (skipn (N.to_nat (Selvedge.Kernel.Compaction.compaction_chunk_chars progress)) unread);
   try discriminate.
 inversion Finished; subst candidate. eexists; eexists; reflexivity.
Qed.

Lemma the_committed_compaction_entry_is_current : forall id entry value effects,
 A.current_entry id (A.registry (K.decision_world (A.commit id entry value effects))) = entry.
Proof.
 intros. unfold A.commit, A.commit_change, CommandResult.accept, A.acknowledged, A.current_entry, A.find_entry,
   A.registry, A.store, A.with_entry, R.compaction_entries, Receiver.install, Receiver.field, Receiver.inject, Receiver.keyed, K.accept, K.with_features,
   Selvedge.Features.State.with_compaction, set; cbn. now rewrite N.eqb_refl.
Qed.

Definition compaction_failure_task (current : task) (message : string) :=
 with_activity (match task_activity current with ReadyForModel => Idle | phase => phase end)
   (set task_history (fun history => (history ++ [FailureMessage message])%list) current).

Theorem compaction_failure_preserves_history_and_retires_its_receivers :
 forall id current entry reason before,
 K.find_task id before = Some current ->
 exists message,
 let stopped := compaction_failure_task current message in
 let result := A.failed id current entry reason before in
 let saved := A.current_entry id (A.registry (K.decision_world result)) in
 K.find_task id (K.decision_world result) = Some stopped /\
 task_history stopped = (task_history current ++ [FailureMessage message])%list /\
 task_activity stopped = (match task_activity current with ReadyForModel => Idle | phase => phase end) /\
 entry_job saved = NoJob /\
 entry_measurement saved = MeasurementFailed (A.capture_task stopped (K.decision_world result)) /\
 entry_attempted saved = A.useful (task_history stopped) /\
 entry_cache saved = None /\
 A.cancellations id saved = [] /\
 K.decision_effects result = [].
Proof.
 intros id current entry reason before Found.
 exists ("Context compaction: " ++ reason)%string; intros stopped result saved.
 assert (Saved : saved =
   set entry_attempted (fun _ => A.useful (task_history stopped))
     (set entry_cache (fun _ => None)
       (A.with_job NoJob (A.with_measurement (MeasurementFailed (A.capture_task stopped before)) entry)))).
 { unfold saved, result, A.failed; apply the_committed_compaction_entry_is_current. }
 split.
 - unfold result, A.failed, A.commit, A.acknowledged; cbn -[A.store K.put_task].
   rewrite storing_maintenance_preserves_tasks; eapply find_put_task; exact Found.
 - rewrite Saved. repeat split; try reflexivity.
   + unfold stopped, compaction_failure_task.
     destruct current as [contract profile settings lifecycle history queued lineage handoff consumed];
       destruct lifecycle; reflexivity.
Qed.

Lemma a_failed_capture_is_fresh_for_its_unchanged_input : forall current value,
 A.fresh (MeasurementFailed (A.capture_task current value)) current value = true.
Proof.
 intros. unfold A.fresh, A.same_input, A.same_description,
   R.same_description, A.same_history.
 cbn [A.capture_task R.capture_task captured_history].
 now rewrite !JsonObjectsProofs.equivalent_is_reflexive.
Qed.

Lemma synchronizing_a_fresh_terminal_failure_emits_no_requests :
 forall id current value entry input result,
 entry = A.synchronized_entry current (A.current_entry id (A.registry value)) ->
 entry_job entry = NoJob -> entry_measurement entry = MeasurementFailed input ->
 A.context_cancellations id current = [] ->
 entry_cache entry = None -> A.fresh (entry_measurement entry) current value = true ->
 A.synchronize id current value = Some result -> K.decision_effects result = [].
Proof.
 intros id current value entry input result Entry Job Failed NoContext Deadline Fresh Outcome.
 assert (NoCancel : A.cancellations id entry = []).
 { unfold A.cancellations; rewrite Job, Failed; reflexivity. }
 assert (NotPending : A.pending_measurement (entry_measurement entry) = false).
 { rewrite Failed; reflexivity. }
 assert (NotDue : A.idle_due current entry (A.registry value) = false).
 { unfold A.idle_due; rewrite Deadline; cbn [N.ltb]; now rewrite !andb_false_r. }
 unfold A.synchronize in Outcome; cbv beta zeta in Outcome; unfold A.current_entry in Entry; rewrite <- Entry in Outcome.
 destruct (negb (A.alive current)).
 - destruct (A.find_entry id (A.registry value)); inversion Outcome; subst result.
   cbn [A.cancel A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_effects].
   now rewrite NoCancel.
 - destruct (negb (TicketedRequest.Scoped.resources_available current value)).
   + destruct (A.find_entry id (A.registry value));
       destruct (A.enabled_target current (A.registry value)); inversion Outcome; subst result;
       unfold A.wait_for_resource;
       destruct (task_activity current) as [| | | ticket revision continuation | | | | |] eqn:Activity;
       try (destruct continuation);
       cbn [A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_effects];
       now rewrite NoCancel, NoContext.
   + destruct (A.running current); [|discriminate].
     destruct (task_activity current); try discriminate; rewrite Job in Outcome;
       (destruct (A.enabled_target current (A.registry value));
        [ rewrite NotPending, NotDue, Fresh in Outcome; inversion Outcome; reflexivity
        | destruct (A.find_entry id (A.registry value)); inversion Outcome; reflexivity ]).
Qed.

(** This applies the ordinary post-transition synchronizer to the actual failed
    decision. Unchanged input cannot acquire another scope, meter or summary
    ticket; a later user/catalog/history change remains free to start new work. *)
Theorem a_compaction_failure_is_not_immediately_resubmitted :
 forall id current entry reason before,
 K.find_task id before = Some current ->
 A.context_cancellations id current = [] ->
 K.decision_effects (DecisionComposition.run (A.synchronize_task id) (A.failed id current entry reason before)) = [].
Proof.
 intros id current entry reason before Found NoContext.
 pose proof (compaction_failure_preserves_history_and_retires_its_receivers
   id current entry reason before Found) as [message Contract].
 cbn zeta in Contract.
 destruct Contract as [Stored [_ [Activity [Job [Measured [_ [Deadline [_ Effects]]]]]]]].
 set (result := A.failed id current entry reason before) in *.
 set (stopped := compaction_failure_task current message) in *.
 set (saved := A.current_entry id (A.registry (K.decision_world result))) in *.
 set (next := A.synchronized_entry stopped saved).
 assert (NextState : entry_job next = NoJob /\
   entry_measurement next = MeasurementFailed (A.capture_task stopped (K.decision_world result)) /\
   entry_cache next = None).
 { unfold next, A.synchronized_entry.
   destruct (entry_useful saved <? A.useful (task_history stopped));
     cbn [set]; repeat split; assumption. }
 destruct NextState as [NextJob [NextMeasurement NextDeadline]].
 assert (Fresh : A.fresh (entry_measurement next) stopped (K.decision_world result) = true).
 { rewrite NextMeasurement; apply a_failed_capture_is_fresh_for_its_unchanged_input. }
 unfold DecisionComposition.run, DecisionComposition.transform, DecisionComposition.maintain, A.synchronize_task; rewrite Stored.
 destruct (A.synchronize id stopped (K.decision_world result)) as [following|] eqn:Following;
   [|exact Effects].
 cbn [DecisionComposition.run DecisionComposition.follow DecisionComposition.from_decision DecisionComposition.unchanged DecisionComposition.updated_world DecisionComposition.appended_effects K.decision_effects]; rewrite Effects; cbn.
 assert (NoStoppedContext : A.context_cancellations id stopped = []).
 { unfold A.context_cancellations in *; rewrite Activity; destruct (task_activity current); exact NoContext || reflexivity. }
 eapply synchronizing_a_fresh_terminal_failure_emits_no_requests;
   [reflexivity|exact NextJob|exact NextMeasurement|exact NoStoppedContext|exact NextDeadline|exact Fresh|exact Following].
Qed.
