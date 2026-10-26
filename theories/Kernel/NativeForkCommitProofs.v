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

Definition started_world {before : world} (accepted : NativeForkCommit.plan before) :=
 let step := NativeForkCommit.planned_step accepted in
 Scheduler.commit_changes (Scheduler.native_fork_owner step)
   (fun _ => [TaskChange.ChangePhase (PendingCalls (Scheduler.native_fork_remaining step))]) before.
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
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_carries_its_final_dispatch_gate
   (Scheduler.native_fork_owner step) (TaskScope.selected (NativeForkCommit.planned_target accepted))
   before step Ready) as [Admitted [Decoded [Room [Name Owner]]]].
 unfold NativeTools.command in Decoded.
 destruct (NativeTools.admit_command (Scheduler.native_fork_owner step)
   (Scheduler.native_fork_invocation step)) as [native|] eqn:Native; [|discriminate].
 cbn [option_map] in Decoded; injection Decoded as Decoded.
 unfold NativeForkCommit.candidate,NativeForkCommit.interpret,requested_decision.
 fold step; fold request.
 unfold Scheduler.execute_checked_call; rewrite Admitted,Native,Decoded,Room.
 fold (started_world accepted).
 unfold NativeForkCommit.execute.
 change (Scheduler.commit_changes (Scheduler.native_fork_owner step)
   (fun _ => [TaskChange.ChangePhase (PendingCalls (Scheduler.native_fork_remaining step))]) before)
   with (started_world accepted).
 fold request.
 assert (Constructed : CommandHandlers.execute (G.Cmd_fork request)
   (Some (Tasks.NativeCall (Scheduler.native_fork_owner step) (Scheduler.native_fork_invocation step)
     (Scheduler.native_fork_remaining step))) (started_world accepted) =
   accept (fork_reply (G.fork_child_count request) (started_world accepted))
     (requested_world accepted messages parent selected) []).
 { unfold requested_world; fold step; fold request.
   change (G.fork_task_id request = Scheduler.native_fork_owner step) in Owner.
   rewrite <- Owner.
   apply every_admissible_native_fork_handler_constructs_its_business_result; [exact Parsed|].
   rewrite Owner; exact Admissible. }
 rewrite Constructed.
 unfold requested_world in Workspace; fold step in Workspace; fold request in Workspace.
 pose proof (a_positive_native_fork_admits_its_observed_workspace _ _ _ _ _ _ _ _ _ _ Admissible Workspace) as Resources.
 change (ForkCommit.admit_workspace (started_world accepted)
   (accept (fork_reply (G.fork_child_count request) (started_world accepted))
     (requested_world accepted messages parent selected) []) =
   accept (fork_reply (G.fork_child_count request) (started_world accepted))
     (requested_world accepted messages parent selected) []) in Resources.
 rewrite Resources.
 assert (Parent : find_task (Scheduler.native_fork_owner step)
   (requested_world accepted messages parent selected) = Some parent).
 { destruct Admissible as [Found _].
   unfold requested_world,fork_candidate; fold step; fold request.
   cbn [fork_retained fork_snapshot_parent fork_invocation].
   apply fork_children_preserve_every_existing_task; exact Found. }
 cbn [decision_reply decision_world decision_effects accept].
 rewrite Name,String.eqb_refl; cbn.
 rewrite Parent; reflexivity.
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
 intros before accepted; unfold started_world.
 rewrite commit_changes_use_the_observed_owner with
   (task:=TaskScope.selected (NativeForkCommit.planned_target accepted)) by apply every_native_fork_plan_has_its_observed_source.
 reflexivity.
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
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 fold step in Ready; fold source in Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 destruct (a_final_native_call_has_its_stored_dispatch_phase _ _ _ _ Call)
   as [Calls [Tickets [phase [operations [running [Lifecycle NonIdle]]]]]].
 pose proof (each_native_fork_keeps_the_exact_started_parent before accepted messages parent selected Admissible) as Parent.
 fold step in Parent; fold source in Parent.
 assert (Life : task_lifecycle parent = result_lifecycle running (PendingCalls (Scheduler.native_fork_remaining step)) operations).
 { rewrite Parent; unfold with_activity; rewrite Lifecycle; destruct running; reflexivity. }
 assert (Static : task_contract parent = task_contract source /\
   task_history parent = task_history source /\ task_operations parent = task_operations source).
 { rewrite Parent; unfold with_activity; rewrite Lifecycle.
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
 pose proof (every_admissible_native_fork_constructs_a_well_formed_birth_world before accepted messages parent selected Valid Admissible) as BirthValid.
 destruct (a_native_fork_keeps_its_parent_and_exact_ticket_supply before accepted messages parent selected (proj1 Admissible))
   as [Found Supply].
 destruct (a_ready_native_fork_carries_its_final_dispatch_gate _ _ _ _ Ready) as [_ [_ [Room _]]].
 pose proof (a_ready_native_fork_keeps_its_frozen_tool _ _ _ _ Ready) as Known.
 unfold requested_settlement; fold step.
 eapply actual_internal_native_results_preserve_every_world_requirement with (operations:=operations) (running:=running).
 - exact BirthValid.
 - exact Found.
 - exact Life.
 - rewrite History; exact ValidCalls.
 - rewrite Operations; exact Unique.
 - unfold WorldInvariant.hooks_correspond,Scheduler.before_plugins in *; rewrite Contract,History; exact Hooks.
 - exists (Scheduler.native_fork_tool step); rewrite Contract; exact Known.
 - rewrite Supply,History; exact Historical.
 - unfold Scheduler.internal_result_available,Callbacks.after_plugins in *; rewrite Contract,Operations; exact Room.
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
 pose proof (every_admissible_native_fork_constructs_a_well_formed_birth_world before accepted messages parent selected Valid Admissible) as BirthValid.
 destruct (a_native_fork_keeps_its_parent_and_exact_ticket_supply before accepted messages parent selected (proj1 Admissible)) as [Found Supply].
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 destruct (a_final_native_call_has_its_stored_dispatch_phase _ _ _ _ Call) as [_ [_ [phase [operations [running [Lifecycle NonIdle]]]]]].
 pose proof (each_native_fork_keeps_the_exact_started_parent before accepted messages parent selected Admissible) as Parent.
 assert (Active : exists phase operations running,task_lifecycle parent = result_lifecycle running phase operations).
 { exists (PendingCalls (Scheduler.native_fork_remaining step)),operations,running.
   rewrite Parent; unfold with_activity; rewrite Lifecycle; destruct running; reflexivity. }
 unfold requested_settlement; fold step.
 rewrite (internal_native_results_use_the_exact_result_task _ _ _ _ _ _ _ Found Active
   (owned_operation_tickets_precede_the_next_ticket _ _ _ BirthValid Found)).
 rewrite Supply; reflexivity.
Qed.

Lemma internal_native_results_emit_no_external_effects : forall owner invocation remaining result failed parent value,
 decision_effects (Scheduler.internal_result owner invocation remaining result failed parent value) = [].
Proof.
 intros; unfold Scheduler.internal_result.
 destruct (Callbacks.after_plugins parent); [reflexivity|].
 cbn [allocate_ticket]. unfold Callbacks.tool_completed.
 destruct (TaskScope.select _ _) as [target|]; [|reflexivity].
 destruct (find _ _); reflexivity.
Qed.

Lemma each_native_fork_result_has_only_its_durable_continuation :
 forall before (accepted : NativeForkCommit.plan before) messages parent selected,
 decision_effects (requested_decision accepted messages parent selected) = [ContinueScheduling].
Proof.
 intros; unfold requested_decision,requested_settlement; cbn [decision_effects].
 rewrite internal_native_results_emit_no_external_effects; reflexivity.
Qed.

Definition continued_parent {before : world} (accepted : NativeForkCommit.plan before) :=
 with_activity (PendingCalls (Scheduler.native_fork_remaining (NativeForkCommit.planned_step accepted)))
   (TaskScope.selected (NativeForkCommit.planned_target accepted)).
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
 CommandHandlers.execute (G.Cmd_fork request)
   (Some (Tasks.NativeCall (G.fork_task_id request) invocation remaining)) before =
 Tasks.refuse_start Tasks.NativeForkEntry Tasks.DescendantCapacity before.
Proof.
 intros request invocation remaining messages before parent Parsed Found Capacity.
 change (Tasks.ancestors_fit (@cons N (G.fork_task_id request) (task_lineage parent))
   (G.fork_child_count request) before = false) in Capacity.
 change ((match Codec.traverse Images.parse_content (message_sources request) with
 | Some parsed => Tasks.fork_with_caller
   (if N.eqb (G.fork_task_id request) (G.fork_task_id request)
    then Tasks.AcceptedNativeFork invocation remaining else Tasks.ManualFork)
   (settings_origin request) (G.fork_task_id request) (G.fork_child_count request)
   parsed (G.fork_settings request) before
 | None => reject "invalid_message" "Child messages contain invalid content parts" before end) =
 Tasks.refuse_start Tasks.NativeForkEntry Tasks.DescendantCapacity before).
 rewrite Parsed,N.eqb_refl,TaskChangesProofs.fork_with_caller_expression.
 rewrite Found,Capacity,andb_false_r.
 unfold Tasks.fork_refusal; rewrite ?Capacity; reflexivity.
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

Theorem every_refused_native_fork_plan_constructs_its_error_settlement :
 forall before (accepted : NativeForkCommit.plan before) code reason,
 let step := NativeForkCommit.planned_step accepted in
 CommandHandlers.execute (G.Cmd_fork (Scheduler.native_fork_request step))
   (Some (Tasks.NativeCall (Scheduler.native_fork_owner step) (Scheduler.native_fork_invocation step)
     (Scheduler.native_fork_remaining step))) (started_world accepted) =
 reject code reason (started_world accepted) ->
 NativeForkCommit.candidate accepted = refused_decision accepted code reason.
Proof.
 intros before accepted code reason step Refused.
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_carries_its_final_dispatch_gate
   (Scheduler.native_fork_owner step) (TaskScope.selected (NativeForkCommit.planned_target accepted))
   before step Ready) as [Admitted [Decoded [Room [Name Owner]]]].
 unfold NativeTools.command in Decoded.
 destruct (NativeTools.admit_command (Scheduler.native_fork_owner step)
   (Scheduler.native_fork_invocation step)) as [native|] eqn:Native; [|discriminate].
 cbn [option_map] in Decoded; injection Decoded as Decoded.
 unfold NativeForkCommit.candidate,NativeForkCommit.interpret,refused_decision.
 fold step.
 unfold Scheduler.execute_checked_call; rewrite Admitted,Native,Decoded,Room.
 fold (started_world accepted).
 unfold NativeForkCommit.execute.
 change (Scheduler.commit_changes (Scheduler.native_fork_owner step)
   (fun _ => [TaskChange.ChangePhase (PendingCalls (Scheduler.native_fork_remaining step))]) before)
   with (started_world accepted).
 rewrite Refused.
 unfold ForkCommit.admit_workspace; cbn [reject decision_world]; rewrite skipn_all.
 cbn [reject decision_world decision_reply decision_effects].
 assert (NotOk : bool_default "ok" (failure code reason) false = false) by reflexivity.
 rewrite NotOk,andb_false_r.
 pose proof (a_started_native_fork_keeps_its_continued_parent before accepted) as Parent.
 fold step in Parent; rewrite Parent.
 reflexivity.
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
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 fold step in Ready; fold source in Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 destruct (a_final_native_call_has_its_stored_dispatch_phase _ _ _ _ Call)
   as [Calls [Tickets [phase [operations [running [Lifecycle NonIdle]]]]]].
 assert (Life : task_lifecycle (continued_parent accepted) =
   result_lifecycle running (PendingCalls (Scheduler.native_fork_remaining step)) operations).
 { unfold continued_parent; fold step; fold source; unfold with_activity; rewrite Lifecycle;
   destruct running; reflexivity. }
 assert (Static : task_contract (continued_parent accepted) = task_contract source /\
   task_history (continued_parent accepted) = task_history source /\
   task_operations (continued_parent accepted) = task_operations source).
 { unfold continued_parent; fold step; fold source; unfold with_activity; rewrite Lifecycle.
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
 assert (Supply : world_next_ticket (started_world accepted) = world_next_ticket before).
 { rewrite a_native_fork_start_is_the_exact_pending_phase_change; reflexivity. }
 unfold refused_settlement; fold step.
 eapply actual_internal_native_results_preserve_every_world_requirement with (operations:=operations) (running:=running).
 - apply every_selected_native_fork_starts_in_a_well_formed_world; exact Valid.
 - apply a_started_native_fork_keeps_its_continued_parent.
 - exact Life.
 - rewrite History; exact ValidCalls.
 - rewrite Operations; exact Unique.
 - unfold WorldInvariant.hooks_correspond,Scheduler.before_plugins in *; rewrite Contract,History; exact Hooks.
 - exists (Scheduler.native_fork_tool step); rewrite Contract; exact Known.
 - rewrite Supply,History; exact Historical.
 - unfold Scheduler.internal_result_available,Callbacks.after_plugins in *; rewrite Contract,Operations; exact Room.
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
 intros before accepted code reason step Valid.
 pose proof (every_selected_native_fork_starts_in_a_well_formed_world before accepted Valid) as StartedValid.
 pose proof (a_started_native_fork_keeps_its_continued_parent before accepted) as Found.
 pose proof (every_native_fork_plan_has_its_actual_final_dispatch_gate before accepted) as Ready.
 destruct (a_ready_native_fork_keeps_its_dispatch_call _ _ _ _ Ready) as [retry Call].
 destruct (a_final_native_call_has_its_stored_dispatch_phase _ _ _ _ Call)
   as [_ [_ [phase [operations [running [Lifecycle NonIdle]]]]]].
 assert (Active : exists phase operations running,
   task_lifecycle (continued_parent accepted) = result_lifecycle running phase operations).
 { exists (PendingCalls (Scheduler.native_fork_remaining step)),operations,running.
   unfold continued_parent; unfold with_activity; rewrite Lifecycle; destruct running; reflexivity. }
 assert (Supply : world_next_ticket (started_world accepted) = world_next_ticket before).
 { rewrite a_native_fork_start_is_the_exact_pending_phase_change; reflexivity. }
 split.
 - unfold refused_settlement; fold step.
   rewrite (internal_native_results_use_the_exact_result_task _ _ _ _ _ _ _ Found Active
     (owned_operation_tickets_precede_the_next_ticket _ _ _ StartedValid Found)).
   rewrite Supply; reflexivity.
 - split; [reflexivity|].
   unfold refused_decision,refused_settlement; cbn [accept decision_effects].
   rewrite internal_native_results_emit_no_external_effects; reflexivity.
Qed.
