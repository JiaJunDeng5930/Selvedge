From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json Registry RegistryProofs.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs TaskScope
 NativeTools Scheduler SchedulerChangesProofs NativeForkCommit NativeForkSchedulingProofs
 NativeForkExecutionProofs ForkCommit ForkCommitProofs ForkPreservation ForkConstructionProofs.
From Selvedge.Features Require Import Worktree Runtime.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module G := Selvedge.Generated.Commands.

Lemma every_native_fork_plan_has_its_actual_final_dispatch_gate :
 forall before (accepted : NativeForkCommit.plan before),
 Scheduler.native_fork_ready (Scheduler.native_fork_owner (NativeForkCommit.planned_step accepted))
   (TaskScope.selected (NativeForkCommit.planned_target accepted)) before =
 Some (NativeForkCommit.planned_step accepted).
Proof.
 intros before accepted.
 destruct (the_selected_native_fork_has_an_observed_ready_owner
   Runtime.can_schedule_task (world_tasks before) before 0 (NativeForkCommit.planned_step accepted)
   (NativeForkCommit.planned_selection before accepted)) as [offset [current [Found [Owner Ready]]]].
 rewrite N.add_0_l in Owner.
 pose proof (TaskScope.observed (NativeForkCommit.planned_target accepted)) as Selected.
 rewrite (NativeForkCommit.planned_owner before accepted) in Selected.
 assert (Observed : find_task (Scheduler.native_fork_owner (NativeForkCommit.planned_step accepted)) before = Some current).
 { unfold find_task; rewrite Owner; exact Found. }
 rewrite Observed in Selected; inversion Selected; subst current; exact Ready.
Qed.

Definition started_world := @NativeForkCommit.started_world.
Arguments started_world {before}.
Definition continued_parent {before : world} (accepted : NativeForkCommit.plan before) :=
 with_activity (PendingCalls (Scheduler.native_fork_remaining (NativeForkCommit.planned_step accepted)))
   (TaskScope.selected (NativeForkCommit.planned_target accepted)).

Lemma a_native_fork_request_names_its_selected_owner : forall before (accepted : NativeForkCommit.plan before),
 G.fork_task_id (Scheduler.native_fork_request (NativeForkCommit.planned_step accepted)) =
 Scheduler.native_fork_owner (NativeForkCommit.planned_step accepted).
Proof.
 intros; pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_carries_its_final_dispatch_gate _ _ _ _ Ready) as [_ [_ [_ [_ Owner]]]]; exact Owner.
Qed.

Definition requested_world {before : world} (accepted : NativeForkCommit.plan before) messages parent selected :=
 let step := NativeForkCommit.planned_step accepted in
 fork_candidate (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (Scheduler.native_fork_owner step) (G.fork_child_count (Scheduler.native_fork_request step))
   messages parent selected (started_world accepted).
Definition requested_settlement {before : world} (accepted : NativeForkCommit.plan before) messages parent selected :=
 let step := NativeForkCommit.planned_step accepted in
 Scheduler.internal_result (Scheduler.native_fork_owner step) (Scheduler.native_fork_invocation step)
   (Scheduler.native_fork_remaining step) (number 0) false parent
   (requested_world accepted messages parent selected).
Definition requested_decision {before : world} (accepted : NativeForkCommit.plan before) messages parent selected :=
 let step := NativeForkCommit.planned_step accepted in
 let settled := requested_settlement accepted messages parent selected in
 Decision (decision_world settled)
   (success JNull)
   (decision_effects settled ++ [ContinueScheduling]).

Theorem every_admissible_native_fork_plan_constructs_its_actual_settlement :
 forall before (accepted : NativeForkCommit.plan before) messages parent selected,
 let step := NativeForkCommit.planned_step accepted in
 let request := Scheduler.native_fork_request step in
 Codec.traverse Images.parse_content (message_sources request) = Some messages ->
 fork_admissible (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (settings_origin request) (Scheduler.native_fork_owner step) (G.fork_child_count request)
   messages (G.fork_settings request) (started_world accepted) parent selected ->
 Worktree.workspace_available (settings_workspace selected) (started_world accepted) &&
   Worktree.binding_available selected (requested_world accepted messages parent selected) = true ->
 NativeForkCommit.candidate accepted = requested_decision accepted messages parent selected.
Proof.
 intros before accepted messages parent selected step request Parsed Admissible Workspace.
 pose proof (a_native_fork_request_names_its_selected_owner before accepted) as Owner.
 fold step in Owner; fold request in Owner.
 assert (Constructed : CommandExecution.handle_fork_result request
   (Some (Tasks.NativeCall (Scheduler.native_fork_owner step) (Scheduler.native_fork_invocation step)
     (Scheduler.native_fork_remaining step))) (started_world accepted) =
   CommandResult.Accepted (CommandResult.Change (fork_reply (G.fork_child_count request) (started_world accepted))
     (requested_world accepted messages parent selected) [])).
 { unfold requested_world; fold step; fold request; rewrite <- Owner.
   apply every_admissible_native_fork_handler_constructs_its_business_result; [exact Parsed|].
   rewrite Owner; exact Admissible. }
 assert (Business : NativeForkCommit.business_result accepted =
   CommandResult.Accepted (CommandResult.Change (fork_reply (G.fork_child_count request) (started_world accepted))
     (requested_world accepted messages parent selected) [])).
 { unfold NativeForkCommit.business_result; fold step; fold request; fold (started_world accepted).
   rewrite Constructed.
   apply a_positive_native_fork_admits_its_observed_workspace with (raw:=G.fork_settings request) (origin:=settings_origin request); assumption. }
 assert (Parent : find_task (Scheduler.native_fork_owner step)
   (requested_world accepted messages parent selected) = Some parent).
 { destruct Admissible as [Found _].
   unfold requested_world,fork_candidate; fold step; fold request.
   cbn [fork_retained fork_snapshot_parent fork_invocation].
   apply fork_children_preserve_every_existing_task; exact Found. }
 unfold NativeForkCommit.candidate,NativeForkCommit.interpret,NativeForkCommit.settle_result,requested_decision.
 fold step; fold (started_world accepted); rewrite Business.
 cbn [CommandResult.decide CommandResult.resolve CommandResult.accept CommandResult.change_value
   CommandResult.change_world CommandResult.change_effects accept decision_world decision_effects].
 unfold Scheduler.finish_call,CommandResult.accept.
 cbn [accept decision_world CommandResult.change_world]; rewrite Parent; reflexivity.
Qed.

From Selvedge.Kernel Require Import NativeForkStartProofs NativeForkPreservation NativeResultTicketProofs WorldInvariant WorldInvariantProofs.

Lemma every_native_fork_plan_has_its_observed_source : forall before (accepted : NativeForkCommit.plan before),
 find_task (Scheduler.native_fork_owner (NativeForkCommit.planned_step accepted)) before =
 Some (TaskScope.selected (NativeForkCommit.planned_target accepted)).
Proof.
 intros before accepted; rewrite <- (NativeForkCommit.planned_owner before accepted).
 apply TaskScope.observed.
Qed.

Lemma a_native_fork_start_is_the_exact_pending_phase_change : forall before (accepted : NativeForkCommit.plan before),
 started_world accepted = put_task (Scheduler.native_fork_owner (NativeForkCommit.planned_step accepted))
   (with_activity (PendingCalls (Scheduler.native_fork_remaining (NativeForkCommit.planned_step accepted)))
     (TaskScope.selected (NativeForkCommit.planned_target accepted))) before.
Proof.
 intros before accepted; rewrite <- (NativeForkCommit.planned_owner before accepted); reflexivity.
Qed.

Theorem every_selected_native_fork_starts_in_a_well_formed_world :
 forall before (accepted : NativeForkCommit.plan before),
 WorldInvariant.well_formed before -> WorldInvariant.well_formed (started_world accepted).
Proof.
 intros before accepted Valid.
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 rewrite a_native_fork_start_is_the_exact_pending_phase_change.
 eapply starting_an_accepted_native_call_preserves_every_world_requirement;
   [exact Valid|apply every_native_fork_plan_has_its_observed_source|exact Call].
Qed.

Lemma each_native_fork_keeps_the_exact_started_parent :
 forall before (accepted : NativeForkCommit.plan before) messages parent selected,
 let step := NativeForkCommit.planned_step accepted in
 fork_admissible (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (settings_origin (Scheduler.native_fork_request step)) (Scheduler.native_fork_owner step)
   (G.fork_child_count (Scheduler.native_fork_request step)) messages (G.fork_settings (Scheduler.native_fork_request step))
   (started_world accepted) parent selected ->
 parent = with_activity (PendingCalls (Scheduler.native_fork_remaining step))
   (TaskScope.selected (NativeForkCommit.planned_target accepted)).
Proof.
 intros before accepted messages parent selected step [Found _].
 rewrite a_native_fork_start_is_the_exact_pending_phase_change in Found.
 pose proof (LifecycleProofs.find_put_task (Scheduler.native_fork_owner step)
   (TaskScope.selected (NativeForkCommit.planned_target accepted))
   (with_activity (PendingCalls (Scheduler.native_fork_remaining step)) (TaskScope.selected (NativeForkCommit.planned_target accepted)))
   before (every_native_fork_plan_has_its_observed_source before accepted)) as Installed.
 fold step in Found. rewrite Installed in Found; now inversion Found.
Qed.

Lemma a_native_fork_keeps_its_parent_and_exact_ticket_supply :
 forall before (accepted : NativeForkCommit.plan before) messages parent selected,
 let step := NativeForkCommit.planned_step accepted in
 find_task (Scheduler.native_fork_owner step) (started_world accepted) = Some parent ->
 find_task (Scheduler.native_fork_owner step) (requested_world accepted messages parent selected) = Some parent /\
 world_next_ticket (requested_world accepted messages parent selected) = world_next_ticket before.
Proof.
 intros before accepted messages parent selected step Found; split.
 - unfold requested_world,fork_candidate; fold step.
   cbn [fork_retained fork_snapshot_parent fork_invocation].
   apply fork_children_preserve_every_existing_task; exact Found.
 - unfold requested_world,fork_candidate; fold step.
   cbn [fork_retained fork_snapshot_parent fork_invocation].
   rewrite (proj1 (proj2 (fork_children_preserve_the_world_frame _ _ _ _ _ _ _ _ _))).
   rewrite a_native_fork_start_is_the_exact_pending_phase_change; reflexivity.
Qed.

Theorem every_admissible_native_fork_constructs_a_well_formed_birth_world :
 forall before (accepted : NativeForkCommit.plan before) messages parent selected,
 let step := NativeForkCommit.planned_step accepted in
 WorldInvariant.well_formed before ->
 fork_admissible (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (settings_origin (Scheduler.native_fork_request step)) (Scheduler.native_fork_owner step)
   (G.fork_child_count (Scheduler.native_fork_request step)) messages (G.fork_settings (Scheduler.native_fork_request step))
   (started_world accepted) parent selected ->
 WorldInvariant.well_formed (requested_world accepted messages parent selected).
Proof.
 intros before accepted messages parent selected step Valid Admissible.
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 destruct (a_final_native_call_has_its_stored_dispatch_phase _ _ _ _ Call) as [Calls _].
 unfold requested_world; fold step.
 eapply admissible_forks_preserve_every_world_requirement;
   [apply every_selected_native_fork_starts_in_a_well_formed_world; exact Valid|exact Admissible|].
 destruct Admissible as [Found _].
 rewrite a_native_fork_start_is_the_exact_pending_phase_change in Found.
 apply actual_native_fork_start_carries_its_accepted_call_certificate with
   (value:=before) (owner:=Scheduler.native_fork_owner step) (source:=TaskScope.selected (NativeForkCommit.planned_target accepted));
   [exact Valid|apply every_native_fork_plan_has_its_observed_source|exact Calls|exact Found].
Qed.

Lemma a_started_native_fork_keeps_its_continued_parent :
 forall before (accepted : NativeForkCommit.plan before),
 find_task (Scheduler.native_fork_owner (NativeForkCommit.planned_step accepted)) (started_world accepted) =
 Some (continued_parent accepted).
Proof.
 intros before accepted; rewrite a_native_fork_start_is_the_exact_pending_phase_change.
 apply LifecycleProofs.find_put_task with (before:=TaskScope.selected (NativeForkCommit.planned_target accepted)).
 apply every_native_fork_plan_has_its_observed_source.
Qed.

(** Birth and business refusal differ in their intermediate world. Both
    settle the same accepted invocation against the unchanged continued parent. *)
Theorem a_selected_native_fork_settles_in_its_retained_parent :
 forall before (accepted : NativeForkCommit.plan before) after parent result failed,
 let step := NativeForkCommit.planned_step accepted in
 let source := TaskScope.selected (NativeForkCommit.planned_target accepted) in
 WorldInvariant.well_formed before -> WorldInvariant.well_formed after ->
 find_task (Scheduler.native_fork_owner step) after = Some parent ->
 parent = continued_parent accepted -> world_next_ticket after = world_next_ticket before ->
 WorldInvariant.hooks_correspond (Scheduler.native_fork_owner step) source
   (Scheduler.native_fork_invocation step) [] = true ->
 historical_result_tickets_below (world_next_ticket before) (task_history source) ->
 WorldInvariant.well_formed (decision_world (Scheduler.internal_result
   (Scheduler.native_fork_owner step) (Scheduler.native_fork_invocation step)
   (Scheduler.native_fork_remaining step) result failed parent after)).
Proof.
 intros before accepted after parent result failed step source Valid AfterValid Found Parent Supply Hooks Historical.
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 fold step in Ready; fold source in Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 destruct (a_final_native_call_has_its_stored_dispatch_phase _ _ _ _ Call)
   as [Calls [Tickets [phase [operations [running [Lifecycle NonIdle]]]]]].
 fold step in Parent; fold source in Parent.
 assert (Life : task_lifecycle parent = result_lifecycle running (PendingCalls (Scheduler.native_fork_remaining step)) operations).
 { rewrite Parent; unfold continued_parent; fold step; fold source; unfold with_activity; rewrite Lifecycle; destruct running; reflexivity. }
 assert (Static : task_contract parent = task_contract source /\
   task_history parent = task_history source /\ task_operations parent = task_operations source).
 { rewrite Parent; unfold continued_parent; fold step; fold source; unfold with_activity; rewrite Lifecycle.
   destruct running; repeat split; try reflexivity;
   unfold task_operations; rewrite Lifecycle; reflexivity. }
 destruct Static as [Contract [History Operations]].
 pose proof (ForkLineageProofs.lookup_task_requirements before (Scheduler.native_fork_owner step) source Valid
   (every_native_fork_plan_has_its_observed_source before accepted)) as SourceValid.
 rewrite task_requirements_ignore_the_journal_cursor in SourceValid.
 pose proof (a_valid_task_has_its_progress_requirements _ _ _ SourceValid) as [_ [Phase [_ UniqueOperations]]].
 unfold WorldInvariant.phase_valid in Phase; rewrite Calls in Phase; apply andb_true_iff in Phase as [ValidCalls _].
 unfold WorldInvariant.operations_valid in UniqueOperations; rewrite Calls in UniqueOperations.
 repeat rewrite andb_true_iff in UniqueOperations; destruct UniqueOperations as [[_ Unique] _].
 destruct (a_ready_native_fork_carries_its_final_dispatch_gate _ _ _ _ Ready) as [_ [_ [Room _]]].
 pose proof (a_ready_native_fork_keeps_its_frozen_tool _ _ _ _ Ready) as Known.

 eapply actual_internal_native_results_preserve_every_world_requirement with (operations:=operations) (running:=running).
 - exact AfterValid.
 - exact Found.
 - exact Life.
 - rewrite History; exact ValidCalls.
 - rewrite Operations; exact Unique.
 - unfold WorldInvariant.hooks_correspond,Scheduler.before_plugins in *; rewrite Contract,History; exact Hooks.
 - exists (Scheduler.native_fork_tool step); rewrite Contract; exact Known.
 - rewrite Supply,History; exact Historical.
 - unfold Scheduler.internal_result_available,Callbacks.after_plugins in *; rewrite Contract,Operations; exact Room.
Qed.

Theorem every_authorized_native_fork_settlement_preserves_every_world_requirement :
 forall before (accepted : NativeForkCommit.plan before) messages parent selected,
 let step := NativeForkCommit.planned_step accepted in
 let source := TaskScope.selected (NativeForkCommit.planned_target accepted) in
 WorldInvariant.well_formed before ->
 fork_admissible (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (settings_origin (Scheduler.native_fork_request step)) (Scheduler.native_fork_owner step)
   (G.fork_child_count (Scheduler.native_fork_request step)) messages (G.fork_settings (Scheduler.native_fork_request step))
   (started_world accepted) parent selected ->
 WorldInvariant.hooks_correspond (Scheduler.native_fork_owner step) source (Scheduler.native_fork_invocation step) [] = true ->
 historical_result_tickets_below (world_next_ticket before) (task_history source) ->
 WorldInvariant.well_formed (decision_world (requested_settlement accepted messages parent selected)).
Proof.
 intros before accepted messages parent selected step source Valid Admissible Hooks Historical.
 destruct (a_native_fork_keeps_its_parent_and_exact_ticket_supply before accepted messages parent selected (proj1 Admissible))
   as [Found Supply].
 unfold requested_settlement; fold step.
 eapply a_selected_native_fork_settles_in_its_retained_parent; try eassumption.
 - eapply every_admissible_native_fork_constructs_a_well_formed_birth_world; eassumption.
 - eapply each_native_fork_keeps_the_exact_started_parent; exact Admissible.
Qed.

Lemma a_selected_native_fork_settlement_uses_its_exact_result_task :
 forall before (accepted : NativeForkCommit.plan before) after parent result failed,
 let step := NativeForkCommit.planned_step accepted in
 WorldInvariant.well_formed after ->
 find_task (Scheduler.native_fork_owner step) after = Some parent ->
 parent = continued_parent accepted -> world_next_ticket after = world_next_ticket before ->
 decision_world (Scheduler.internal_result (Scheduler.native_fork_owner step)
   (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step) result failed parent after) =
 put_task (Scheduler.native_fork_owner step)
   (result_task (Scheduler.native_fork_owner step) (world_next_ticket before)
     (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step) result failed parent)
   (match Callbacks.after_plugins parent with
    | [] => after | _ => with_ticket (N.succ (world_next_ticket before)) after end).
Proof.
 intros before accepted after parent result failed step Valid Found Parent Supply.
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 destruct (a_final_native_call_has_its_stored_dispatch_phase _ _ _ _ Call)
   as [_ [_ [phase [operations [running [Lifecycle NonIdle]]]]]].
 assert (Active : exists phase operations running,task_lifecycle parent = result_lifecycle running phase operations).
 { exists (PendingCalls (Scheduler.native_fork_remaining step)),operations,running.
   rewrite Parent; unfold continued_parent,with_activity; rewrite Lifecycle; destruct running; reflexivity. }
 rewrite (internal_native_results_use_the_exact_result_task _ _ _ _ _ _ _ Found Active
   (owned_operation_tickets_precede_the_next_ticket _ _ _ Valid Found)).
 rewrite Supply; reflexivity.
Qed.

Theorem each_native_fork_settlement_uses_its_exact_result_task :
 forall before (accepted : NativeForkCommit.plan before) messages parent selected,
 let step := NativeForkCommit.planned_step accepted in
 WorldInvariant.well_formed before ->
 fork_admissible (Tasks.AcceptedNativeFork (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))
   (settings_origin (Scheduler.native_fork_request step)) (Scheduler.native_fork_owner step)
   (G.fork_child_count (Scheduler.native_fork_request step)) messages (G.fork_settings (Scheduler.native_fork_request step))
   (started_world accepted) parent selected ->
 decision_world (requested_settlement accepted messages parent selected) =
 put_task (Scheduler.native_fork_owner step)
   (result_task (Scheduler.native_fork_owner step) (world_next_ticket before) (Scheduler.native_fork_invocation step)
     (Scheduler.native_fork_remaining step) (number 0) false parent)
   (match Callbacks.after_plugins parent with
    | [] => requested_world accepted messages parent selected
    | _ => with_ticket (N.succ (world_next_ticket before)) (requested_world accepted messages parent selected) end).
Proof.
 intros before accepted messages parent selected step Valid Admissible.
 destruct (a_native_fork_keeps_its_parent_and_exact_ticket_supply before accepted messages parent selected (proj1 Admissible)) as [Found Supply].
 unfold requested_settlement; fold step.
 eapply a_selected_native_fork_settlement_uses_its_exact_result_task; try eassumption.
 - eapply every_admissible_native_fork_constructs_a_well_formed_birth_world; eassumption.
 - eapply each_native_fork_keeps_the_exact_started_parent; exact Admissible.
Qed.

Lemma internal_native_results_emit_no_external_effects : forall owner invocation remaining result failed parent value,
 decision_effects (Scheduler.internal_result owner invocation remaining result failed parent value) = [].
Proof.
 intros; unfold Scheduler.internal_result.
 destruct (Callbacks.after_plugins parent); [reflexivity|].
 cbn [allocate_ticket]; rewrite CallbackChangesProofs.tool_completed_expression.
 repeat match goal with
 | |- context [find_task ?owner ?after] => destruct (find_task owner after)
 | |- context [find ?test ?entries] => destruct (find test entries)
 end; reflexivity.
Qed.

Lemma each_native_fork_result_has_only_its_durable_continuation :
 forall before (accepted : NativeForkCommit.plan before) messages parent selected,
 decision_effects (requested_decision accepted messages parent selected) = [ContinueScheduling].
Proof.
 intros; unfold requested_decision,requested_settlement; cbn [decision_effects].
 rewrite internal_native_results_emit_no_external_effects; reflexivity.
Qed.

Definition refused_settlement {before : world} (accepted : NativeForkCommit.plan before) code reason :=
 let step := NativeForkCommit.planned_step accepted in
 Scheduler.internal_result (Scheduler.native_fork_owner step) (Scheduler.native_fork_invocation step)
   (Scheduler.native_fork_remaining step) (failure code reason) true
   (continued_parent accepted) (started_world accepted).
Definition refused_decision {before : world} (accepted : NativeForkCommit.plan before) code reason :=
 let settled := refused_settlement accepted code reason in
 accept JNull (decision_world settled) (decision_effects settled ++ [ContinueScheduling]).

Lemma exhausted_descendant_capacity_refuses_the_actual_native_fork_handler :
 forall request invocation remaining messages before parent,
 Codec.traverse Images.parse_content (message_sources request) = Some messages ->
 find_task (G.fork_task_id request) before = Some parent ->
 Tasks.ancestors_fit (G.fork_task_id request :: task_lineage parent)
   (G.fork_child_count request) before = false ->
 CommandExecution.handle_fork_result request
   (Some (Tasks.NativeCall (G.fork_task_id request) invocation remaining)) before =
 CommandResult.Rejected (Tasks.start_refusal Tasks.NativeForkEntry Tasks.DescendantCapacity).
Proof.
 intros request invocation remaining messages before parent Parsed Found Capacity.
 change (Tasks.ancestors_fit (@cons N (G.fork_task_id request) (task_lineage parent))
   (G.fork_child_count request) before = false) in Capacity.
 unfold CommandExecution.handle_fork_result.
 match goal with |- match ?parsed with Some _ => _ | None => _ end = _ =>
   change (parsed = Some messages) in Parsed end; rewrite Parsed.
 cbn [Tasks.native_owner Tasks.native_invocation Tasks.native_remaining].
 rewrite N.eqb_refl; unfold Tasks.fork_result.
 destruct (TaskScopeProofs.selecting_an_existing_task_retains_its_key _ _ _ Found)
   as [target [Selected [_ Current]]].
 rewrite Selected; cbn beta iota zeta; rewrite Current,Capacity,andb_false_r.
 unfold Tasks.fork_refusal_reason; rewrite Capacity; reflexivity.
Qed.

Theorem every_refused_native_fork_plan_constructs_its_error_settlement :
 forall before (accepted : NativeForkCommit.plan before) code reason,
 let step := NativeForkCommit.planned_step accepted in
 NativeForkCommit.business_result accepted =
 CommandResult.Rejected (CommandResult.Refusal code reason) ->
 NativeForkCommit.candidate accepted = refused_decision accepted code reason.
Proof.
 intros before accepted code reason step Refused.
 unfold NativeForkCommit.candidate,NativeForkCommit.interpret,NativeForkCommit.settle_result,refused_decision.
 fold step; fold (started_world accepted); rewrite Refused.
 cbn [CommandResult.decide CommandResult.resolve CommandResult.reject CommandResult.refusal_code
   CommandResult.refusal_message reject decision_world decision_effects].
 unfold Scheduler.finish_call,CommandResult.reject.
 cbn [reject decision_world CommandResult.refusal_code CommandResult.refusal_message].
 unfold step; rewrite a_started_native_fork_keeps_its_continued_parent; reflexivity.
Qed.

Theorem a_refused_native_fork_settlement_preserves_every_world_requirement :
 forall before (accepted : NativeForkCommit.plan before) code reason,
 let step := NativeForkCommit.planned_step accepted in
 let source := TaskScope.selected (NativeForkCommit.planned_target accepted) in
 WorldInvariant.well_formed before ->
 WorldInvariant.hooks_correspond (Scheduler.native_fork_owner step) source
   (Scheduler.native_fork_invocation step) [] = true ->
 historical_result_tickets_below (world_next_ticket before) (task_history source) ->
 WorldInvariant.well_formed (decision_world (refused_settlement accepted code reason)).
Proof.
 intros before accepted code reason step source Valid Hooks Historical.
 unfold refused_settlement; fold step.
 eapply a_selected_native_fork_settles_in_its_retained_parent; try eassumption.
 - apply every_selected_native_fork_starts_in_a_well_formed_world; exact Valid.
 - apply a_started_native_fork_keeps_its_continued_parent.
 - reflexivity.
 - rewrite a_native_fork_start_is_the_exact_pending_phase_change; reflexivity.
Qed.

Theorem a_refused_native_fork_keeps_the_exact_error_and_continuation :
 forall before (accepted : NativeForkCommit.plan before) code reason,
 let step := NativeForkCommit.planned_step accepted in
 WorldInvariant.well_formed before ->
 decision_world (refused_settlement accepted code reason) =
 put_task (Scheduler.native_fork_owner step)
   (result_task (Scheduler.native_fork_owner step) (world_next_ticket before)
     (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step)
     (failure code reason) true (continued_parent accepted))
   (match Callbacks.after_plugins (continued_parent accepted) with
    | [] => started_world accepted
    | _ => with_ticket (N.succ (world_next_ticket before)) (started_world accepted) end) /\
 decision_reply (refused_decision accepted code reason) = success JNull /\
 decision_effects (refused_decision accepted code reason) = [ContinueScheduling].
Proof.
 intros before accepted code reason step Valid; split.
 - unfold refused_settlement; fold step.
   eapply a_selected_native_fork_settlement_uses_its_exact_result_task.
   + apply every_selected_native_fork_starts_in_a_well_formed_world; exact Valid.
   + apply a_started_native_fork_keeps_its_continued_parent.
   + reflexivity.
   + rewrite a_native_fork_start_is_the_exact_pending_phase_change; reflexivity.
 - split; [reflexivity|].
   unfold refused_decision,refused_settlement; cbn [accept decision_effects].
   rewrite internal_native_results_emit_no_external_effects; reflexivity.
Qed.
