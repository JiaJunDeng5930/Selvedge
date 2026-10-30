From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json JsonObjectsProofs Registry RegistryProofs OptionListProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State LifecycleProofs ProtocolProofs ContextSelection ContextSelectionProofs Tasks Reasoning Recovery CompactionPlan ScopedRequestProofs FeatureRequestProofs TaskScopeProofs.
From Selvedge.Features Require Import CompactionTypes CompactionCodec Compaction.
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
 TicketedRequest.Scoped.maintenance_admission id request before = true ->
 exists reference : TicketedRequest.Scoped.maintenance_reference before id request,
   A.run_request id request before = TicketedRequest.Scoped.maintenance_issue reference.
Proof.
 intros id request before Ready; pose proof Ready as HasOwner.
 unfold TicketedRequest.Scoped.maintenance_admission,TicketedRequest.Scoped.maintenance_ready in HasOwner.
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
 C.entry_measurement (A.current_entry id (A.registry value)) = C.Measuring ticket input stage ->
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
 entry = A.synchronized_entry current (A.current_entry id (A.registry value)) (A.registry value) ->
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

Theorem an_admitted_current_scope_has_its_exact_pending_receiver :
 forall id input entry value,
 TicketedRequest.Scoped.maintenance_ready id input value = true ->
 let result := A.begin_scope id input None entry value in
 K.decision_effects result = [K.MaintainContext (Scope id (K.world_next_ticket value) input)] /\
 entry_measurement (A.current_entry id (A.registry (K.decision_world result))) =
   Measuring (K.world_next_ticket value) input InspectScope.
Proof.
 intros id input entry value Ready; cbn zeta; unfold A.begin_scope.
 assert (Admitted : TicketedRequest.Scoped.maintenance_admission id
   (TicketedRequest.Scoped.ScopeRequest input None entry) value = true).
 { change (TicketedRequest.Scoped.maintenance_ready id input value && true = true).
   now rewrite Ready. }
 destruct (admitted_maintenance_runs_its_resolved_plan id _ value Admitted) as [reference Issued].
 rewrite Issued.
 destruct (resolved_maintenance_installs_its_exact_receiver value id _ reference) as [Installed Effects].
 split; [exact Effects|].
 unfold A.current_entry,A.find_entry,A.registry; rewrite Installed; reflexivity.
Qed.

Lemma printed_natural_is_admitted : forall value, natural (number value) = Some value.
Proof. exact natural_print_parse. Qed.
Definition owns_compactor_ticket (id ticket : N) (value : K.world) :=
 match entry_job (A.current_entry id (A.registry value)) with
 | Compacting expected _ _ _ _ => N.eqb ticket expected | _ => false end.
Lemma stale_result_does_not_change_the_component : forall id ticket result error value,
 owns_compactor_ticket id ticket value = false -> A.resolve (Completed id ticket result error) value = None.
Proof.
 intros id ticket result error value stale; unfold A.resolve,A.resolve_task_completion.
 destruct (K.find_task id value) as [current|]; [|reflexivity].
 unfold owns_compactor_ticket in stale; cbv beta zeta.
 unfold A.running,A.alive,A.compact_result.
 destruct (task_lifecycle current);
 destruct (entry_job (A.current_entry id (A.registry value))); cbn in *;
 try reflexivity; now rewrite stale.
Qed.
(** A valid stale observation still participates in journal ordering and the
    outer scheduler. Its own handler acquires no state or execution authority. *)
Theorem stale_compactor_callback_has_no_effects : forall source id ticket result error value,
 string_field "kind" source = Some "compaction_completed" ->
 CC.decode_completion "compaction_completed" source = Some (Completed id ticket result error) ->
 owns_compactor_ticket id ticket value = false ->
 A.completion source value = Some (true,true,A.acknowledged false value []).
Proof.
 intros source id ticket result error value Kind Decoded Stale.
 unfold A.completion; rewrite Kind.
 change (Some (match CC.decode_completion "compaction_completed" source with
 | Some event => match A.resolve event value with
   | Some result => (true,true,result) | None => (true,true,A.acknowledged false value []) end
 | None => (false,false,K.reject "invalid_input" "Malformed compaction observation" value) end) =
 Some (true,true,A.acknowledged false value [])).
 rewrite Decoded, stale_result_does_not_change_the_component by assumption. reflexivity.
Qed.
Definition clock_input (now : N) := JObject [("kind",JString "compaction_clock");("now",number now)].
Theorem clock_observation_uses_monotone_time : forall now value,
 A.completion (clock_input now) value = Some (true,true,
 A.acknowledged true (A.store (set maintenance_timer (fun _ => 0) (A.with_now now (A.registry value))) value) []).
Proof.
 intros. unfold A.completion, clock_input, A.owns_kind, CC.decode_completion,
   CC.completion_decoder, CC.completion_decoders.
 cbn -[natural number A.resolve]. rewrite printed_natural_is_admitted. reflexivity.
Qed.
Lemma storing_maintenance_preserves_tasks : forall id state value,
 K.find_task id (A.store state value) = K.find_task id value.
Proof. reflexivity. Qed.
Lemma supplied_history_is_an_append : forall id task summary value,
 K.find_task id value = Some task ->
 exists stored, K.find_task id (CommandResult.change_world (A.supplied_change id task summary value)) = Some stored /\
 task_history stored = (task_history task ++ [ContextSelection.record (N.of_nat (List.length (task_history task))) (ContextSelection.portable summary)])%list.
Proof.
 intros. unfold A.supplied_change,A.commit_change.
 cbn -[A.store K.put_task ContextSelection.adopt]. rewrite storing_maintenance_preserves_tasks.
 eexists. split; [eapply find_put_task;exact H|].
 change (ContextSelection.adopt (task_history task) (ContextSelection.portable summary) (task_history task) =
 (task_history task ++ [ContextSelection.record (N.of_nat (List.length (task_history task))) (ContextSelection.portable summary)])%list).
 apply a_current_snapshot_can_be_adopted.
Qed.
(** This positive contract constrains the actual typed command entry, excluding
    implementations that reject every checkpoint or discard its source history. *)
Theorem a_valid_checkpoint_preserves_its_original_records : forall id summary caller task value,
 K.find_task id value = Some task -> A.alive task = true -> A.idle task = true ->
 (negb (String.eqb summary "") && (N.of_nat (String.length summary) <=? Selvedge.Kernel.Compaction.summary_limit_bytes) &&
 ContextSelection.closed_prefix (task_history task)) = true ->
 A.handle_compact_result (G.Build_compact id (Some summary)) caller value = CommandResult.Accepted (A.supplied_change id task summary value) /\
 exists stored, K.find_task id (CommandResult.change_world (A.supplied_change id task summary value)) = Some stored /\
 task_history stored = (task_history task ++ [ContextSelection.record (N.of_nat (List.length (task_history task))) (ContextSelection.portable summary)])%list.
Proof.
 intros. split.
 - destruct (selecting_an_existing_task_retains_its_key id value task H)
     as [[owner current Observed] [Selected [Owner Current]]].
   cbn in Owner,Current; subst owner current.
   unfold A.handle_compact_result; cbn [G.compact_task_id G.compact_summary].
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
 TicketedRequest.Scoped.can_observe_maintenance current value = true ->
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
Definition manual_waiting_decision (id : N) (current : task) (before : K.world) :=
 K.Decision (manual_waiting_world id current before)
   (K.success (JObject [("task_id", number id)]))
   (map K.MaintainContext (A.cancellations id (A.current_entry id (A.registry before)))).

(** This is the public command with a live operation, not an assumed accepted
    helper result. The wait keeps the task, operation and queued demand intact;
    only obsolete maintenance requests are cancelled. *)
Theorem manual_compaction_accepts_an_open_prefix_and_waits :
 forall id current operations caller before,
 K.find_task id before = Some current ->
 task_lifecycle current = Running Idle operations ->
 TicketedRequest.Scoped.resources_available current before = true ->
 A.job_pending (entry_job (A.current_entry id (A.registry before))) = false ->
 ContextSelection.closed_prefix (task_history current) = false ->
 A.handle_compact (G.Build_compact id None) caller before =
 manual_waiting_decision id current before.
Proof.
 intros id current operations caller before Found Lifecycle Available NoJob Open.
 destruct (selecting_an_existing_task_retains_its_key id before current Found)
   as [[owner task Observed] [Selected [Owner Current]]].
 cbn in Owner,Current; subst owner task.
 pose proof (an_open_summary_prefix_has_no_context_plan before
   (TaskScope.TaskReference before id current Observed) Manual
   (A.current_entry id (A.registry before)) Open) as NoPlan.
 assert (Alive : A.alive current = true) by (unfold A.alive; now rewrite Lifecycle).
 assert (RunningTask : A.running current = true) by (unfold A.running; now rewrite Lifecycle).
 assert (Phase : task_activity current = Idle) by (unfold task_activity; now rewrite Lifecycle).
 unfold A.handle_compact,A.handle_compact_result; cbn [G.compact_task_id G.compact_summary].
 rewrite Selected; cbn [TaskScope.selected]; rewrite Alive,Phase,RunningTask; cbn.
 unfold A.manual_change,CommandResult.accept; cbn [TaskScope.owner]; rewrite NoJob.
 unfold A.wait_for_context_selected; rewrite NoPlan.
 cbn [TaskScope.owner TaskScope.selected].
 unfold A.retain_context_wait; rewrite Available.
 unfold manual_waiting_decision, manual_waiting_world, manual_waiting_entry.
 cbn [A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_world K.decision_effects].
 now rewrite app_nil_r.
Qed.

Theorem an_open_manual_wait_preserves_all_task_state : forall id current before,
 K.world_tasks (K.decision_world (manual_waiting_decision id current before)) = K.world_tasks before /\
 entry_job (A.current_entry id (A.registry
   (K.decision_world (manual_waiting_decision id current before)))) =
 Resuming (A.capture_task current before) Manual.
Proof.
 intros; split; [reflexivity|].
 unfold manual_waiting_decision, manual_waiting_world, manual_waiting_entry,
   A.current_entry, A.find_entry, A.registry, A.store, A.with_entry, TicketedRequest.Scoped.compaction_entries, Receiver.install, Receiver.field, Receiver.inject, Receiver.keyed, A.with_observation,
   A.with_measurement, A.with_job, K.with_features, Selvedge.Features.State.with_compaction, set;
 cbn. now rewrite N.eqb_refl.
Qed.

(** Results, cancellations and running announcements may close the source.
    Synchronization then captures the whole current prefix, including those
    records; it never reuses the open prefix saved when the request arrived. *)
Theorem a_closed_manual_wait_recaptures_its_current_prefix :
 forall id current before input entry operations phase,
 task_lifecycle current = Running phase operations ->
 phase <> WantsModel -> (forall ticket revision, phase <> ObservingContext ticket revision) ->
 TicketedRequest.Scoped.resources_available current before = true ->
 entry = A.synchronized_entry current (A.current_entry id (A.registry before)) (A.registry before) ->
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
 entry = A.synchronized_entry current (A.current_entry id (A.registry before)) (A.registry before) ->
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
 entry = A.synchronized_entry current (A.current_entry id (A.registry before)) (A.registry before) ->
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
 assert (CanObserve : TicketedRequest.Scoped.can_observe_maintenance current before = true).
 { unfold TicketedRequest.Scoped.can_observe_maintenance; rewrite Available,Lifecycle;
   destruct Phase as [Phase|Phase]; subst phase; reflexivity. }
 destruct (maintenance_observation_uses_the_current_task before
   (TaskScope.TaskReference before id current Observed) (Some Manual) (A.with_job NoJob entry) CanObserve Closed)
   as [request [Planned Effects]].
 exists (A.begin_scope id (A.capture_task current before) (Some Manual) (A.with_job NoJob entry) before).
 split.
 - eapply a_closed_manual_wait_recaptures_its_current_prefix; eauto;
     destruct Phase as [Phase|Phase]; subst phase; discriminate.
 - unfold A.begin_scope,A.run_request; rewrite Selected.
   unfold A.run_request_selected,TicketedRequest.Scoped.maintenance_selected;
     cbn [TaskScope.owner TaskScope.selected TaskScope.observed].
   apply observe_cases.
   + intros stored Stored.
     assert (Missing : entry_observation stored = None).
     { unfold A.current_entry in Unobserved.
       change (A.find_entry id (A.registry before) = Some stored) in Stored.
       now rewrite Stored in Unobserved. }
     unfold TicketedRequest.Scoped.maintenance_observed,TicketedRequest.Scoped.boolean_admission.
     destruct (Bool.bool_dec _ true) as [Eligible|Unavailable].
     { exfalso; unfold TicketedRequest.Scoped.maintenance_ready_from in Eligible.
       rewrite Missing,!andb_false_r in Eligible; discriminate. }
     cbn [option_map TicketedRequest.Scoped.maintenance_waiting_entry].
     unfold A.wait_for_context_selected; rewrite Planned; exact Effects.
   + intros Absent; cbn [TicketedRequest.Scoped.maintenance_waiting_entry].
     unfold A.wait_for_context_selected; rewrite Planned; exact Effects.
Qed.

Theorem suspended_manual_context_completion_cancels_its_job :
 forall id ticket revision before result previous task operations,
 K.find_task id before = Some previous ->
 task_activity previous = ObservingContext ticket revision ->
 K.find_task id (K.decision_world result) = Some task ->
 entry_job (A.current_entry id (A.registry before)) = AwaitingContext ticket (Some Manual) false ->
 entry_job (A.current_entry id (A.registry (K.decision_world result))) = AwaitingContext ticket (Some Manual) false ->
 A.cancelled_task id (K.decision_effects result) = false ->
 A.cancelled_ticket id ticket (K.decision_effects result) = false ->
 (task_lifecycle task = Frozen WantsModel operations \/ task_lifecycle task = Stopped WantsModel operations) ->
 let cancelled := Tasks.promote (with_activity Idle (append_history
   [FailureMessage "Context summary was not sent because the task is frozen or stopped; original history retained"] task)) in
 DecisionComposition.run (A.observe_manual before id) result =
 DecisionComposition.follow result (A.cancel id cancelled (A.current_entry id (A.registry (K.decision_world result)))
   (K.put_task id cancelled (K.decision_world result))) /\
 task_activity cancelled = Idle /\
 entry_job (A.clear_entry cancelled (A.current_entry id (A.registry (K.decision_world result)))) = NoJob.
Proof.
 intros id ticket revision before result previous task operations Previous Phase Found Job CurrentJob NotCancelled NotSteered Paused cancelled.
 unfold DecisionComposition.run, A.observe_manual; rewrite Previous, Found, NotCancelled, Phase, Job, N.eqb_refl, NotSteered.
 unfold A.awaiting_context_demand; rewrite CurrentJob, N.eqb_refl; cbn [A.same_context_purpose].
 destruct Paused as [FrozenTask|StoppedTask].
 - assert (Activity : task_activity task = WantsModel) by (unfold task_activity; rewrite FrozenTask; reflexivity).
   rewrite Activity, FrozenTask. split; [reflexivity|]. split; [|reflexivity].
   unfold cancelled. destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
   cbn in FrozenTask; subst lifecycle; reflexivity.
 - assert (Activity : task_activity task = WantsModel) by (unfold task_activity; rewrite StoppedTask; reflexivity).
   rewrite Activity, StoppedTask. split; [reflexivity|]. split; [|reflexivity].
   unfold cancelled. destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
   cbn in StoppedTask; subst lifecycle; destruct queued; reflexivity.
Qed.

Theorem a_suspended_observation_preserves_exactly_its_model_demand :
 forall purpose demand current operations,
 (task_lifecycle current = Frozen WantsModel operations \/ task_lifecycle current = Stopped WantsModel operations) ->
 task_activity (A.suspended_context_task purpose demand current) = if demand then WantsModel else Idle.
Proof.
 intros purpose demand [contract profile settings lifecycle history queued lineage parent cursor consumed] operations Status.
 cbn in Status. destruct Status as [Status|Status]; subst lifecycle;
   unfold A.suspended_context_task; destruct purpose as [purpose|]; try destruct purpose;
   destruct demand; destruct queued; reflexivity.
Qed.

Theorem a_replaced_context_never_consumes_the_new_task_demand :
 forall id ticket revision purpose resume_model before result previous current,
 K.find_task id before = Some previous ->
 task_activity previous = ObservingContext ticket revision ->
 K.find_task id (K.decision_world result) = Some current ->
 entry_job (A.current_entry id (A.registry before)) = AwaitingContext ticket purpose resume_model ->
 A.cancelled_ticket id ticket (K.decision_effects result) = true ->
 K.world_tasks (K.decision_world (DecisionComposition.run (A.observe_manual before id) result)) = K.world_tasks (K.decision_world result) /\
 K.decision_effects (DecisionComposition.run (A.observe_manual before id) result) = K.decision_effects result.
Proof.
 intros id ticket revision purpose resume_model before result previous current Previous Phase Current Job Cancelled.
 unfold DecisionComposition.run, A.observe_manual; rewrite Previous, Current.
 destruct (A.cancelled_task id (K.decision_effects result)).
 2: { rewrite Phase, Job, N.eqb_refl.
      destruct (A.awaiting_context_demand ticket purpose
        (A.current_entry id (A.registry (K.decision_world result)))); [rewrite Cancelled|];
      split; try reflexivity;
      cbn [DecisionComposition.run DecisionComposition.follow DecisionComposition.from_decision DecisionComposition.unchanged DecisionComposition.updated_world DecisionComposition.appended_effects A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_effects]; apply app_nil_r. }
 split; [reflexivity|cbn [DecisionComposition.run DecisionComposition.follow DecisionComposition.from_decision DecisionComposition.unchanged DecisionComposition.updated_world DecisionComposition.appended_effects A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_effects]; apply app_nil_r].
Qed.

Lemma matching_context_purposes_are_equal : forall first second,
 A.same_context_purpose first second = true -> first = second.
Proof.
 intros [first|] [second|]; try destruct first; try destruct second;
   cbn [A.same_context_purpose]; intros Equal; try discriminate; reflexivity.
Qed.

Theorem a_current_context_demand_names_its_exact_receiver : forall ticket purpose entry demand,
 A.awaiting_context_demand ticket purpose entry = Some demand ->
 entry_job entry = AwaitingContext ticket purpose demand.
Proof.
 intros ticket purpose entry demand Present; unfold A.awaiting_context_demand in Present.
 destruct (entry_job entry) as [|waiting|actual current demanded|input resumed|
   actual input resumed stage|actual input resumed progress scope|actual input resumed candidate preview stage]
   eqn:Job; try discriminate.
 destruct (N.eqb actual ticket && A.same_context_purpose current purpose) eqn:Matches; [|discriminate].
 inversion Present; subst demand. apply andb_true_iff in Matches as [Ticket Purpose].
 apply N.eqb_eq in Ticket; apply matching_context_purposes_are_equal in Purpose.
 now subst actual current.
Qed.

Theorem a_retired_context_receiver_preserves_the_entire_decision :
 forall id ticket revision purpose resume_model before result previous current,
 K.find_task id before = Some previous ->
 task_activity previous = ObservingContext ticket revision ->
 entry_job (A.current_entry id (A.registry before)) = AwaitingContext ticket purpose resume_model ->
 K.find_task id (K.decision_world result) = Some current ->
 A.cancelled_task id (K.decision_effects result) = false ->
 A.awaiting_context_demand ticket purpose (A.current_entry id (A.registry (K.decision_world result))) = None ->
 DecisionComposition.run (A.observe_manual before id) result = result.
Proof.
 intros id ticket revision purpose resume_model before result previous current Previous Phase Job Current NotCancelled Retired.
 unfold DecisionComposition.run, A.observe_manual; now rewrite Previous, Current, NotCancelled, Phase, Job, N.eqb_refl, Retired; destruct result; cbn; now rewrite app_nil_r.
Qed.

Theorem recovering_a_context_retires_its_receiver : forall entry ticket purpose demand,
 entry_job entry = AwaitingContext ticket purpose demand ->
 entry_job (A.recover_entry entry) = NoJob.
Proof.
 intros; unfold A.recover_entry, A.with_observation, A.with_measurement, A.with_job, set; cbn.
 unfold A.resume; now rewrite H.
Qed.

Theorem recovery_of_pending_operations_creates_the_retained_frozen_demand :
 forall state id current ticket revision purpose operations,
 entry_job (A.current_entry id state) = AwaitingContext ticket purpose false ->
 task_lifecycle current = Frozen (ObservingContext ticket revision) operations ->
 operations <> [] ->
 task_activity (Recovery.recover_task id (A.recover_context_task state id current)) = WantsModel.
Proof.
 intros state id current ticket revision purpose operations Job Lifecycle Pending.
 assert (Phase : task_activity current = ObservingContext ticket revision)
   by (unfold task_activity; now rewrite Lifecycle).
 unfold A.recover_context_task; rewrite Job, Phase, N.eqb_refl.
 destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed].
 cbn in Lifecycle; subst lifecycle; destruct operations; [contradiction|reflexivity].
Qed.

Theorem manual_context_recovery_does_not_invent_model_demand :
 forall state id task ticket revision,
 entry_job (A.current_entry id state) = AwaitingContext ticket (Some Manual) false ->
 task_activity task = ObservingContext ticket revision ->
 A.recover_context_task state id task = with_activity Idle task.
Proof.
 intros. unfold A.recover_context_task. now rewrite H, H0, N.eqb_refl.
Qed.

Lemma cancellations_name_exact_pending_tickets : forall owner id ticket entry,
 In (Cancel owner ticket) (A.cancellations id entry) <->
 owner = id /\ (A.measurement_ticket (entry_measurement entry) = Some ticket \/
   A.job_ticket (entry_job entry) = Some ticket).
Proof.
 intros; unfold A.cancellations.
 destruct (A.measurement_ticket (entry_measurement entry));
 destruct (A.job_ticket (entry_job entry)); cbn; intuition congruence.
Qed.

Lemma registry_cancellations_name_exact_pending_tickets : forall state id ticket,
 In (Cancel id ticket) (A.pending_cancellations state) <->
 exists entry, In (id, entry) (maintenance_entries state) /\
   (A.measurement_ticket (entry_measurement entry) = Some ticket \/
    A.job_ticket (entry_job entry) = Some ticket).
Proof.
 intros; unfold A.pending_cancellations; rewrite in_flat_map; split.
 - intros [[owner entry] [Present Pending]]; cbn in Pending.
   apply cancellations_name_exact_pending_tickets in Pending as [Same Pending].
   subst owner; exists entry; now split.
 - intros [entry [Present Pending]]; exists (id,entry); split; [exact Present|].
   apply cancellations_name_exact_pending_tickets; now split.
Qed.

Theorem live_reconfiguration_cancels_exactly_the_retired_requests : forall value id ticket,
 In (K.MaintainContext (Cancel id ticket)) (K.decision_effects (A.reconfigure value)) <->
 exists entry, In (id,entry) (maintenance_entries (A.registry value)) /\
   (A.measurement_ticket (entry_measurement entry) = Some ticket \/
    A.job_ticket (entry_job entry) = Some ticket).
Proof.
 intros; cbn [A.reconfigure A.acknowledged K.accept K.decision_effects].
 rewrite <- registry_cancellations_name_exact_pending_tickets.
 split.
 - intros Present; apply in_map_iff in Present as [request [Same Present]].
   inversion Same; subst request; exact Present.
 - apply in_map.
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
 destruct (entry_job entry); reflexivity.
Qed.

Lemma live_reconfiguration_recovers_the_selected_task : forall value id task,
 K.find_task id value = Some task ->
 K.find_task id (K.decision_world (A.reconfigure value)) =
 Some (A.recover_context_task (A.registry value) id task).
Proof.
 intros value id task Found; rewrite live_reconfiguration_uses_the_existing_recovery_state.
 unfold A.recover; rewrite storing_maintenance_preserves_tasks.
 unfold A.recover_context_tasks, K.find_task, K.with_tasks, set; cbn.
 replace id with (0 + id) at 2 by reflexivity.
 apply registry_lookup_at_numbered_map; exact Found.
Qed.

Theorem live_reconfiguration_retains_the_saved_inference_demand :
 forall value id task ticket revision purpose resume_model,
 K.find_task id value = Some task ->
 entry_job (A.current_entry id (A.registry value)) = AwaitingContext ticket purpose resume_model ->
 task_activity task = ObservingContext ticket revision ->
 K.find_task id (K.decision_world (A.reconfigure value)) =
 Some (with_activity (if resume_model then WantsModel else Idle) task).
Proof.
 intros; rewrite (live_reconfiguration_recovers_the_selected_task value id task H).
 unfold A.recover_context_task; now rewrite H0, H1, N.eqb_refl.
Qed.

Theorem live_reconfiguration_preserves_an_unrelated_context_receiver :
 forall value id task ticket revision,
 K.find_task id value = Some task ->
 task_activity task = ObservingContext ticket revision ->
 (forall purpose demand,
   entry_job (A.current_entry id (A.registry value)) <> AwaitingContext ticket purpose demand) ->
 K.find_task id (K.decision_world (A.reconfigure value)) = Some task.
Proof.
 intros value id task ticket revision Found Phase Unrelated.
 rewrite (live_reconfiguration_recovers_the_selected_task value id task Found).
 unfold A.recover_context_task; rewrite Phase.
 destruct (entry_job (A.current_entry id (A.registry value))) as
   [|waiting|expected purpose demand|input resumed|expected input resumed stage|
    expected input resumed progress scope|expected input resumed candidate preview stage] eqn:Job;
   try reflexivity.
 destruct (N.eqb expected ticket) eqn:Same; [|reflexivity].
 apply N.eqb_eq in Same; subst expected; exfalso; apply (Unrelated purpose demand); reflexivity.
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
 assert (NoObservation : TicketedRequest.Scoped.can_observe_maintenance (TaskScope.selected target) value = false).
 { unfold TicketedRequest.Scoped.can_observe_maintenance; now rewrite Unavailable. }
 pose proof (unavailable_maintenance_observation_has_no_plan value target (Some Manual) entry NoObservation) as NoPlan.
 unfold A.manual_change; rewrite <- Entry,Ready.
 unfold A.wait_for_context_selected; rewrite NoPlan.
 unfold A.retain_context_wait; rewrite Unavailable.
 split.
 - cbn [A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_effects]. apply app_nil_r.
 - cbn [A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_world].
   unfold A.current_entry,A.find_entry,A.registry,A.store,A.with_entry, TicketedRequest.Scoped.compaction_entries, Receiver.install, Receiver.field, Receiver.inject, Receiver.keyed,A.with_observation,
     A.with_measurement,A.with_job,K.with_features,Selvedge.Features.State.with_compaction,set;
   cbn; now rewrite N.eqb_refl.
Qed.

(** The feature callback forwards recovered progress with its captured input,
    purpose and scope to the currently configured target. The kernel planner
    separately proves that recovered progress retains native raw history. *)
Theorem native_unavailable_callback_dispatches_portable_rebuild :
 forall id ticket task input purpose progress scope entry value target portable,
 C.entry_job entry = C.Compacting ticket input purpose progress scope ->
 A.relevant input task value = true ->
 P.receive progress (JObject [("action",JString "native_unavailable")]) = P.Next portable ->
 A.configured_target task (A.registry value) = Some target ->
 A.compact_result id ticket task (JObject [("action",JString "native_unavailable")]) false entry value =
 Some (A.dispatch_compact id task input purpose target portable scope entry value).
Proof.
 intros id ticket task input purpose progress scope entry value target portable Job Relevant Recovered Target.
 unfold A.compact_result. rewrite Job, N.eqb_refl, Relevant.
 rewrite Recovered, Target. reflexivity.
Qed.

(** Candidate validation may change representation from native to portable,
    but cannot start another summary of the same source after portable failure.
    These contracts cover both actual validation exits, not a retry counter in
    a separate Host interpreter. *)
Theorem an_oversized_portable_validation_stops :
 forall id task input purpose first rest usage preview scope tokens budget entry value,
 A.relevant input task value = true ->
 A.same_history preview
   (ContextSelection.adopt (captured_history input) (PortableArtifact first rest usage) (task_history task)) = true ->
 (tokens + reserve_tokens budget <=? window_tokens budget) = false ->
 A.finish_validation id task input purpose (PortableArtifact first rest usage)
   preview scope tokens budget entry value =
 A.failed id task entry
   "The portable summary and retained context exceed the configured model window; original history retained" value.
Proof.
 intros id task input purpose first rest usage preview scope tokens budget entry value Relevant Preview Oversized.
 unfold A.finish_validation; rewrite Relevant; cbn [ContextSelection.consumes].
 now rewrite Preview, Oversized.
Qed.

Theorem an_oversized_native_validation_keeps_portable_fallback :
 forall id task input purpose head tail first rest usage preview scope tokens budget entry value,
 let candidate := NativeArtifact head tail first rest usage in
 A.relevant input task value = true -> ContextSelection.consumes candidate scope = true ->
 A.same_history preview (ContextSelection.adopt (captured_history input) candidate (task_history task)) = true ->
 ((tokens + reserve_tokens budget <=? window_tokens budget) &&
   negb (policy_enabled (maintenance_policy (A.registry value)) &&
     (window_tokens budget * policy_blocking (maintenance_policy (A.registry value)) <=? tokens * 100))) = false ->
 A.finish_validation id task input purpose candidate preview scope tokens budget entry value =
 A.force_portable id task scope entry value.
Proof.
 intros id task input purpose head tail first rest usage preview scope tokens budget entry value candidate Relevant Consumes Preview Oversized.
 unfold candidate in *.
 unfold A.finish_validation; now rewrite Relevant, Consumes, Preview, Oversized.
Qed.

Theorem an_oversized_portable_validation_frame_stops :
 forall id task input scope purpose first rest usage preview entry value,
 let candidate := Some (PortableArtifact first rest usage, preview) in
 let request := TicketedRequest.Scoped.MeasureRequest input purpose candidate scope entry in
 (N.of_nat (String.length (TextJson.render_json (CC.effect_json
   (snd (TicketedRequest.Scoped.maintenance_build id (K.world_next_ticket value) request)))))
   <=? Limits.frame_bytes / 4) = false ->
 A.measured_call id task input scope purpose candidate entry value =
 A.failed id task entry
   "The portable summary and retained context exceed the validation transport budget; original history retained" value.
Proof.
 intros id task input scope purpose first rest usage preview entry value candidate request Oversized.
 unfold A.measured_call. fold request. now rewrite Oversized.
Qed.

Theorem an_oversized_measurement_without_a_portable_candidate_can_rebuild :
 forall id task input scope purpose candidate entry value,
 (forall first rest usage preview, candidate <> Some (PortableArtifact first rest usage, preview)) ->
 let request := TicketedRequest.Scoped.MeasureRequest input purpose candidate scope entry in
 (N.of_nat (String.length (TextJson.render_json (CC.effect_json
   (snd (TicketedRequest.Scoped.maintenance_build id (K.world_next_ticket value) request)))))
   <=? Limits.frame_bytes / 4) = false ->
 A.measured_call id task input scope purpose candidate entry value =
 A.force_portable id task scope entry value.
Proof.
 intros id task input scope purpose candidate entry value NotPortable request Oversized.
 unfold A.measured_call. fold request. rewrite Oversized.
 destruct candidate as [[candidate preview]|]; [destruct candidate|]; try reflexivity.
 exfalso; eapply NotPortable; reflexivity.
Qed.

Theorem a_portable_source_can_only_finish_with_a_portable_candidate :
 forall progress result candidate unread,
 Selvedge.Kernel.Compaction.compaction_source progress = Selvedge.Kernel.Compaction.PortableSource unread ->
 P.receive_source progress result = P.Compacted candidate ->
 exists first rest usage, candidate = PortableArtifact first rest usage.
Proof.
 intros progress result candidate unread Portable Finished.
 unfold P.receive_source in Finished; rewrite Portable in Finished.
 destruct (string_field "summary_text" result) as [[|head tail]|]; try discriminate.
 destruct (skipn (N.to_nat (Selvedge.Kernel.Compaction.compaction_chunk_chars progress)) unread);
   try discriminate.
 inversion Finished; subst candidate. eexists; eexists; eexists; reflexivity.
Qed.

Lemma the_committed_compaction_entry_is_current : forall id entry value effects,
 A.current_entry id (A.registry (K.decision_world (A.commit id entry value effects))) = entry.
Proof.
 intros. unfold A.commit, A.commit_change, CommandResult.accept, A.acknowledged, A.current_entry, A.find_entry,
   A.registry, A.store, A.with_entry, TicketedRequest.Scoped.compaction_entries, Receiver.install, Receiver.field, Receiver.inject, Receiver.keyed, K.accept, K.with_features,
   Selvedge.Features.State.with_compaction, set; cbn. now rewrite N.eqb_refl.
Qed.

Definition compaction_failure_task (current : task) (reason : string) :=
 with_activity (match task_activity current with ReadyForModel => Idle | phase => phase end)
   (set task_history (fun history => (history ++ [FailureMessage ("Context compaction: " ++ reason)])%list) current).

Theorem compaction_failure_preserves_history_and_retires_its_receivers :
 forall id current entry reason before,
 K.find_task id before = Some current ->
 let stopped := compaction_failure_task current reason in
 let result := A.failed id current entry reason before in
 let saved := A.current_entry id (A.registry (K.decision_world result)) in
 K.find_task id (K.decision_world result) = Some stopped /\
 task_history stopped = (task_history current ++ [FailureMessage ("Context compaction: " ++ reason)])%list /\
 task_activity stopped = (match task_activity current with ReadyForModel => Idle | phase => phase end) /\
 entry_job saved = NoJob /\
 entry_measurement saved = MeasurementFailed (A.capture_task stopped (K.decision_world result)) /\
 entry_attempted saved = A.useful (task_history stopped) /\
 entry_cache_deadline saved = 0 /\
 A.cancellations id saved = [] /\
 K.decision_effects result = [].
Proof.
 intros id current entry reason before Found stopped result saved.
 assert (Saved : saved =
   set entry_attempted (fun _ => A.useful (task_history stopped))
     (set entry_cache_deadline (fun _ => 0)
       (A.with_job NoJob (A.with_measurement (MeasurementFailed (A.capture_task stopped before)) entry)))).
 { unfold saved, result, A.failed; apply the_committed_compaction_entry_is_current. }
 split.
 - unfold result, A.failed, A.commit, A.acknowledged; cbn -[A.store K.put_task].
   rewrite storing_maintenance_preserves_tasks; eapply find_put_task; exact Found.
 - rewrite Saved. repeat split; try reflexivity.
   + unfold stopped, compaction_failure_task.
     destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed];
       destruct lifecycle; reflexivity.
Qed.

Lemma a_failed_capture_is_fresh_for_its_unchanged_input : forall current value,
 A.fresh (MeasurementFailed (A.capture_task current value)) current value = true.
Proof.
 intros. unfold A.fresh, A.same_input, A.same_description,
   TicketedRequest.Scoped.same_description, A.same_history.
 cbn [A.capture_task TicketedRequest.Scoped.capture_task captured_history].
 now rewrite !JsonObjectsProofs.equivalent_is_reflexive.
Qed.

Lemma synchronizing_a_fresh_terminal_failure_emits_no_requests :
 forall id current value entry input result,
 entry = A.synchronized_entry current (A.current_entry id (A.registry value)) (A.registry value) ->
 entry_job entry = NoJob -> entry_measurement entry = MeasurementFailed input ->
 entry_cache_deadline entry = 0 -> A.fresh (entry_measurement entry) current value = true ->
 A.synchronize id current value = Some result -> K.decision_effects result = [].
Proof.
 intros id current value entry input result Entry Job Failed Deadline Fresh Outcome.
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
       cbn [A.wait_for_resource A.commit A.commit_change CommandResult.accept CommandResult.change_value CommandResult.change_world CommandResult.change_effects A.acknowledged K.accept K.decision_effects];
       now rewrite NoCancel.
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
 K.decision_effects (DecisionComposition.run (A.synchronize_task id) (A.failed id current entry reason before)) = [].
Proof.
 intros id current entry reason before Found.
 pose proof (compaction_failure_preserves_history_and_retires_its_receivers
   id current entry reason before Found) as Contract.
 cbn zeta in Contract.
 destruct Contract as [Stored [_ [_ [Job [Measured [_ [Deadline [_ Effects]]]]]]]].
 set (result := A.failed id current entry reason before) in *.
 set (stopped := compaction_failure_task current reason) in *.
 set (saved := A.current_entry id (A.registry (K.decision_world result))) in *.
 set (next := A.synchronized_entry stopped saved (A.registry (K.decision_world result))).
 assert (NextState : entry_job next = NoJob /\
   entry_measurement next = MeasurementFailed (A.capture_task stopped (K.decision_world result)) /\
   entry_cache_deadline next = 0).
 { unfold next, A.synchronized_entry.
   destruct (entry_useful saved <? A.useful (task_history stopped));
     cbn [set]; repeat split; assumption. }
 destruct NextState as [NextJob [NextMeasurement NextDeadline]].
 assert (Fresh : A.fresh (entry_measurement next) stopped (K.decision_world result) = true).
 { rewrite NextMeasurement; apply a_failed_capture_is_fresh_for_its_unchanged_input. }
 unfold DecisionComposition.run, A.synchronize_task; rewrite Stored.
 destruct (A.synchronize id stopped (K.decision_world result)) as [following|] eqn:Following;
   [|exact Effects].
 cbn [DecisionComposition.run DecisionComposition.follow DecisionComposition.from_decision DecisionComposition.unchanged DecisionComposition.updated_world DecisionComposition.appended_effects K.decision_effects]; rewrite Effects; cbn.
 eapply synchronizing_a_fresh_terminal_failure_emits_no_requests;
   [reflexivity|exact NextJob|exact NextMeasurement|exact NextDeadline|exact Fresh|exact Following].
Qed.
