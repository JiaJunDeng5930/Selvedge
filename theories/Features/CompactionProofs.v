From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State LifecycleProofs ProtocolProofs ContextSelection ContextSelectionProofs Tasks Reasoning CompactionPlan.
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

Lemma printed_natural_is_admitted : forall value, natural (number value) = Some value.
Proof. exact natural_print_parse. Qed.
Definition completed_input (id ticket : N) (fields : list (string * json)) := JObject [
 ("kind", JString "compaction_completed"); ("task_id", number id); ("ticket", number ticket);
 ("error", JBool false); ("result", JObject fields)].
Lemma completion_wire_is_admitted : forall id ticket fields,
 CC.decode_completion "compaction_completed" (completed_input id ticket fields) = Some (Completed id ticket (JObject fields) false).
Proof.
 intros. unfold CC.decode_completion, CC.completion_decoder, CC.completion_decoders, CC.decode_outcome, completed_input.
 cbn -[natural number]. now rewrite !printed_natural_is_admitted.
Qed.
Definition owns_compactor_ticket (id ticket : N) (value : K.world) :=
 match entry_job (A.current_entry id (A.registry value)) with
 | Compacting expected _ _ _ _ => N.eqb ticket expected | _ => false end.
Lemma stale_result_does_not_change_the_component : forall id ticket result value,
 owns_compactor_ticket id ticket value = false -> A.resolve (Completed id ticket result false) value = None.
Proof.
 intros id ticket result value stale.
 unfold A.resolve, A.resolve_task_completion.
 destruct (K.find_task id value) as [task|]; [|reflexivity].
 unfold owns_compactor_ticket in stale.
 unfold A.running, A.alive, A.compact_result.
 destruct (task_lifecycle task);
 destruct (entry_job (A.current_entry id (A.registry value))); cbn in *;
 try reflexivity; now rewrite stale.
Qed.
(** A valid stale observation still participates in journal ordering and the
    outer scheduler. Its own handler acquires no state or execution authority. *)
Theorem stale_compactor_callback_has_no_effects : forall id ticket fields value,
 owns_compactor_ticket id ticket value = false ->
 A.completion (completed_input id ticket fields) value =
 Some (true,true,A.acknowledged false value []).
Proof.
 intros. unfold A.completion, completed_input at 1.
 cbn -[A.owns_kind CC.decode_completion].
 change (Some (match CC.decode_completion "compaction_completed" (completed_input id ticket fields) with
 | Some event => match A.resolve event value with
   | Some result => (true,true,result) | None => (true,true,A.acknowledged false value []) end
 | None => (false,false,K.reject "invalid_input" "Malformed compaction observation" value) end) =
 Some (true,true,A.acknowledged false value [])).
 rewrite completion_wire_is_admitted, stale_result_does_not_change_the_component by assumption. reflexivity.
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
 exists stored, K.find_task id (K.decision_world (A.supplied id task summary value)) = Some stored /\
 task_history stored = (task_history task ++ [ContextSelection.record (N.of_nat (List.length (task_history task))) (ContextSelection.portable summary)])%list.
Proof.
 intros. unfold A.supplied,A.commit,A.acknowledged.
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
 ContextSelection.settled_calls (task_history task) (task_history task)) = true ->
 A.command (G.Cmd_compact (G.Build_compact id (Some summary))) caller value = Some (A.supplied id task summary value) /\
 exists stored, K.find_task id (K.decision_world (A.supplied id task summary value)) = Some stored /\
 task_history stored = (task_history task ++ [ContextSelection.record (N.of_nat (List.length (task_history task))) (ContextSelection.portable summary)])%list.
Proof.
 intros. split.
 - unfold A.command. cbn. rewrite H,H0,H1. cbn. now rewrite H2.
 - apply supplied_history_is_an_append. assumption.
Qed.
Theorem measured_scope_and_reserve_reach_the_executed_request : forall id ticket model task scope tokens budget input value fallback_scope fallback_reserve,
 entry_measurement (A.current_entry id (A.registry value)) = Measured input scope tokens budget ->
 A.prepare_model_effects value [K.RequestModel id ticket model task fallback_scope fallback_reserve] =
 [K.RequestModel id ticket model task scope (reserve_tokens budget)].
Proof. intros. unfold A.prepare_model_effects. cbn. now rewrite H. Qed.


Theorem manual_compaction_captures_context_before_any_summary_request : forall id task value entry,
 entry = A.current_entry id (A.registry value) ->
 A.job_pending (entry_job entry) = false ->
 K.decision_effects (A.manual id task value) =
 (map K.MaintainContext (A.cancellations id entry) ++
  [K.ObserveContext id (K.world_next_ticket value) task])%list.
Proof.
 intros id task value entry Entry Ready. unfold A.manual. rewrite <- Entry, Ready.
 unfold Reasoning.observe_context, K.allocate_ticket, A.commit, A.acknowledged.
 reflexivity.
Qed.

Theorem suspended_manual_context_completion_cancels_its_job :
 forall id ticket revision input before result previous task operations,
 K.find_task id before = Some previous ->
 task_activity previous = ObservingContext ticket revision ->
 K.find_task id (K.decision_world result) = Some task ->
 entry_job (A.current_entry id (A.registry (K.decision_world result))) = Resuming input Manual ->
 (task_lifecycle task = Frozen WantsModel operations \/ task_lifecycle task = Stopped WantsModel operations) ->
 let cancelled := Tasks.promote (with_activity Idle (append_history
   [FailureMessage "Context summary was not sent because the task is frozen or stopped; original history retained"] task)) in
 A.observe_manual before id result =
 A.combine result (A.cancel id cancelled (A.current_entry id (A.registry (K.decision_world result)))
   (K.put_task id cancelled (K.decision_world result))) /\
 task_activity cancelled = Idle /\
 entry_job (A.clear_entry cancelled (A.current_entry id (A.registry (K.decision_world result)))) = NoJob.
Proof.
 intros id ticket revision input before result previous task operations Previous Phase Found Job Paused cancelled.
 unfold A.observe_manual; rewrite Previous, Found, Job, Phase.
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
