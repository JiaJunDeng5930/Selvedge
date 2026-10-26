From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.Kernel Require Import Domain State TaskScope TaskChange TaskChangeProofs
 Tasks TaskChangesProofs Callbacks CallbackChangesProofs SideContext Dispatch Scheduler RuntimeCompositionProofs.
From Selvedge.Features Require Import Runtime Board Compaction Worktree TaskGraph TaskGraphProofs.
Import ListNotations.
Open Scope list_scope.

Lemma writing_tasks_installs_the_registry : forall tasks value,
 world_tasks (with_tasks tasks value) = tasks.
Proof. intros tasks []; reflexivity. Qed.
Lemma writing_features_keeps_the_task_registry : forall features value,
 world_tasks (with_features features value) = world_tasks value.
Proof. intros features []; reflexivity. Qed.

Theorem reconciliation_keeps_an_archived_owner : forall owner task operations value,
 find_task owner value = Some task -> task_lifecycle task = Archived operations ->
 find_task owner (SideContext.reconcile value) = Some task.
Proof.
 intros owner task operations value Found ArchivedTask.
 unfold SideContext.reconcile, find_task; rewrite writing_tasks_installs_the_registry.
 rewrite registry_lookup_commutes_with_mapping.
 change (Registry.registry_at owner (world_tasks value) = Some task) in Found.
 rewrite Found; cbn. unfold SideContext.reconcile_task; rewrite ArchivedTask; reflexivity.
Qed.

Lemma replacing_another_owner_keeps_the_archived_reference : forall owner other task replacement value,
 owner <> other -> find_task owner value = Some task ->
 find_task owner (put_task other replacement value) = Some task.
Proof.
 intros; unfold find_task, put_task; rewrite writing_tasks_installs_the_registry.
 rewrite registry_replace_other; [assumption|congruence].
Qed.

Lemma capture_keeps_an_archived_owner : forall owner task operations value request,
 find_task owner value = Some task -> task_lifecycle task = Archived operations ->
 find_task owner (fst (Dispatch.capture_request request value)) = Some task.
Proof.
 intros owner task operations value request Found ArchivedTask.
 destruct request; cbn [Dispatch.capture_request]; try exact Found.
 all: repeat match goal with
 | |- context [match ?term with _ => _ end] => destruct term eqn:?
 end; cbn; try exact Found.
 all: apply replacing_another_owner_keeps_the_archived_reference; [|exact Found].
 all: intro Same; subst owner.
 all: match goal with
 | Selected : find_task ?id ?stored = Some ?active,
   Phase : task_activity ?active = ?phase |- _ =>
     assert (active = task) by congruence; subst active;
     unfold task_activity in Phase; rewrite ArchivedTask in Phase; discriminate
 | Side : Dispatch.side_task ?id ?stored = Some ?active,
   Phase : task_activity ?active = ?phase |- _ =>
     unfold Dispatch.side_task in Side; rewrite Found in Side;
     destruct (task_side_parent task); inversion Side; subst active;
     unfold task_activity in Phase; rewrite ArchivedTask in Phase; discriminate
 end.
Qed.

Theorem dispatch_preparation_keeps_an_archived_owner : forall requests owner task operations value,
 find_task owner value = Some task -> task_lifecycle task = Archived operations ->
 find_task owner (fst (Dispatch.prepare value requests)) = Some task.
Proof.
 intros requests; induction requests as [|request rest IH]; intros owner task operations value Found ArchivedTask;
 [exact Found|].
 unfold Dispatch.prepare in *; cbn [Dispatch.capture_requests].
 pose proof (capture_keeps_an_archived_owner owner task operations value request Found ArchivedTask) as Kept.
 destruct (Dispatch.capture_request request value) as [next emitted]; cbn in Kept |- *.
 specialize (IH owner task operations next Kept ArchivedTask).
 destruct (Dispatch.capture_requests rest next); exact IH.
Qed.

Theorem finishing_keeps_every_task_reference : forall current owner,
 find_task owner (decision_world (Runtime.finish current)) = find_task owner (decision_world current).
Proof.
 intros; unfold Runtime.finish, TitleCommit.enqueue.
 destruct (TitleCommit.resolve _); cbn [decision_world];
 unfold Compaction.attach, Board.finish; cbn [decision_world];
 unfold Board.synchronize, Board.store, find_task;
 rewrite writing_features_keeps_the_task_registry; reflexivity.
Qed.

Theorem a_foreign_field_change_keeps_the_archived_reference : forall before
 (plan : TaskChange.plan before) owner task,
 find_task owner before = Some task -> TaskScope.owner (TaskChange.target plan) <> owner ->
 find_task owner (TaskChange.interpret plan) = Some task.
Proof. intros; rewrite a_field_plan_preserves_every_other_task by assumption; assumption. Qed.

Lemma settling_an_archived_operation_keeps_the_result : forall task operations original result error,
 task_lifecycle task = Archived operations ->
 let settled := Callbacks.settle_operation original result error task in
 task_lifecycle settled = Archived (Callbacks.remove_operation (operation_id original) operations) /\
 task_history settled = task_history task ++ [History.operation_result original result error].
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor consumed]
   operations original result error ArchivedTask; cbn in ArchivedTask; subst lifecycle.
 rewrite CallbackChangesProofs.settle_operation_expression.
 repeat split; reflexivity.
Qed.

Theorem an_archived_result_is_installed_before_runtime_maintenance :
 forall owner ticket result error value task original operations,
 find_task owner value = Some task -> task_lifecycle task = Archived operations ->
 find (Callbacks.operation_executing ticket) operations = Some original ->
 Callbacks.after_plugins task = [] ->
 let completed := Callbacks.tool_completed owner ticket result error value in
 decision_reply completed = State.success (JObject [("accepted"%string,JBool true)]) /\
 exists settled,
 find_task owner (decision_world completed) = Some settled /\
 task_lifecycle settled = Archived (Callbacks.remove_operation (operation_id original) operations) /\
 task_history settled = task_history task ++ [History.operation_result original result error].
Proof.
 intros owner ticket result error value task original operations Found ArchivedTask Owned Hooks.
 rewrite CallbackChangesProofs.tool_completed_expression, Found.
 unfold task_operations; rewrite ArchivedTask, Owned.
 unfold Callbacks.begin_result_plan; rewrite Hooks.
 cbn [Callbacks.acknowledged State.accept decision_reply decision_world].
 split; [reflexivity|]. exists (Callbacks.settle_operation original result error task).
 split.
 - unfold Tasks.apply_result, Callbacks.settle_operation_plan.
   rewrite TaskWakeProofs.context_wake_preserves_every_task_lookup.
   unfold find_task, put_task; rewrite writing_tasks_installs_the_registry.
   eapply registry_replace_selected; exact Found.
 - apply settling_an_archived_operation_keeps_the_result; exact ArchivedTask.
Qed.

Theorem withdrawal_never_dispatches_execution_for_an_archived_owner :
 forall owner task operations current request ticket,
 find_task owner (decision_world current) = Some task ->
 task_lifecycle task = Archived operations ->
 Dispatch.request_coordinate request = Some (owner,ticket) ->
 ~ In request (decision_effects (Dispatch.retain_live_effects current)).
Proof.
 intros owner task operations current request ticket Found ArchivedTask Coordinate Emitted.
 unfold Dispatch.retain_live_effects in Emitted; cbn in Emitted.
 apply filter_In in Emitted as [_ Live].
 unfold Dispatch.live_request in Live; rewrite Coordinate, Found, ArchivedTask in Live; discriminate.
Qed.

Lemma composing_exact_task_frames : forall A (step : decision -> A -> decision),
 (forall current item owner, find_task owner (decision_world (step current item)) =
   find_task owner (decision_world current)) ->
 forall items current owner,
 find_task owner (decision_world (fold_left step items current)) = find_task owner (decision_world current).
Proof.
 intros A step Frame items; induction items as [|first rest IH]; intros current owner;
 cbn; [reflexivity|rewrite IH, Frame; reflexivity].
Qed.

Lemma composing_an_archived_reference_frame : forall A (step : decision -> A -> decision)
 owner task operations,
 task_lifecycle task = Archived operations ->
 (forall current item, find_task owner (decision_world current) = Some task ->
   find_task owner (decision_world (step current item)) = Some task) ->
 forall items current, find_task owner (decision_world current) = Some task ->
 find_task owner (decision_world (fold_left step items current)) = Some task.
Proof.
 intros A step owner task operations ArchivedTask Frame items;
 induction items as [|first rest IH]; intros current Found; cbn; [exact Found|].
 apply IH, Frame; exact Found.
Qed.

Lemma archiving_worktree_resources_preserves_tasks : forall tree current,
 world_tasks (decision_world (Worktree.archive_after tree current)) = world_tasks (decision_world current).
Proof.
 intros; unfold Worktree.archive_after, Worktree.archive_tree.
 repeat match goal with
 | |- context [match ?term with _ => _ end] => destruct term eqn:?
 end; unfold Worktree.store; cbn [decision_world];
 rewrite ?writing_features_keeps_the_task_registry; reflexivity.
Qed.

Theorem worktree_maintenance_keeps_every_task_reference : forall before current owner,
 find_task owner (decision_world (Worktree.after_transition before current)) =
 find_task owner (decision_world current).
Proof.
 intros; unfold Worktree.after_transition; apply composing_exact_task_frames.
 intros; unfold find_task; rewrite archiving_worktree_resources_preserves_tasks; reflexivity.
Qed.

Lemma sending_input_keeps_an_archived_owner : forall destination contents owner task operations value,
 find_task owner value = Some task -> task_lifecycle task = Archived operations ->
 find_task owner (decision_world (Tasks.send destination contents value)) = Some task.
Proof.
 intros destination contents owner task operations value Found ArchivedTask.
 destruct (N.eq_dec owner destination) as [Same|Different].
 - subst destination; rewrite TaskChangesProofs.send_expression, Found, ArchivedTask; exact Found.
 - rewrite TaskChangesProofs.send_expression.
   destruct (find_task destination value) as [target|]; [|exact Found].
   destruct (task_lifecycle target); try exact Found;
   destruct (content_nonempty contents); try exact Found;
   apply replacing_another_owner_keeps_the_archived_reference; assumption.
Qed.

Lemma graph_delivery_keeps_an_archived_owner : forall source item current owner task operations,
 find_task owner (decision_world current) = Some task -> task_lifecycle task = Archived operations ->
 find_task owner (decision_world (TaskGraph.send_delivery source item current)) = Some task.
Proof.
 intros source item current owner task operations Found ArchivedTask.
 unfold TaskGraph.send_delivery, Worktree.execution_guard.
 destruct (Worktree.execution_allowed (TaskGraph.delivery_target item) (decision_world current));
   cbn [decision_world Worktree.failed_execution reject];
   unfold find_task at 1; rewrite TaskGraphProofs.recording_receipt_preserves_tasks.
 - change (find_task owner (decision_world (Tasks.send (TaskGraph.delivery_target item)
     [TextPart (TaskGraph.delivery_text item)] (decision_world current))) = Some task).
   eapply sending_input_keeps_an_archived_owner; eauto.
 - exact Found.
Qed.

Theorem graph_maintenance_keeps_an_archived_owner : forall before current owner task operations,
 find_task owner (decision_world current) = Some task -> task_lifecycle task = Archived operations ->
 find_task owner (decision_world (TaskGraph.after_transition before current)) = Some task.
Proof.
 intros before current owner task operations Found ArchivedTask; unfold TaskGraph.after_transition.
 eapply composing_an_archived_reference_frame; [exact ArchivedTask| |exact Found].
 intros current1 pair Found1.
 eapply composing_an_archived_reference_frame; [exact ArchivedTask| |exact Found1].
 intros current2 output Found2; unfold TaskGraph.react_output.
 eapply composing_an_archived_reference_frame; [exact ArchivedTask| |exact Found2].
 intros current3 item Found3. eapply graph_delivery_keeps_an_archived_owner; eauto.
Qed.
