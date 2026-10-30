From Stdlib Require Import List NArith.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Domain State TaskScope TaskChange.
Import ListNotations.

Lemma apply_app : forall first rest current,
 TaskChange.apply (first ++ rest) current = TaskChange.apply rest (TaskChange.apply first current).
Proof. intros; unfold TaskChange.apply; apply fold_left_app. Qed.

Lemma appending_history_keeps_operations : forall messages current,
 task_operations (append_history messages current) = task_operations current.
Proof. reflexivity. Qed.

Definition preserves_observation {A : Type} (observe : task -> A) (change : TaskChange.edit) :=
 forall current, observe (TaskChange.apply_edit change current) = observe current.

Theorem field_changes_preserve_an_observation : forall A (observe : task -> A) changes current,
 Forall (preserves_observation observe) changes ->
 observe (TaskChange.apply changes current) = observe current.
Proof.
 intros A observe changes current Preserved; revert current.
 induction Preserved; intro current; [reflexivity|].
 change (observe (TaskChange.apply l (TaskChange.apply_edit x current)) = observe current).
 rewrite IHPreserved; apply H.
Qed.

Lemma one_append_only_edit_retains_history : forall change current,
 exists suffix, task_history (TaskChange.apply_edit change current) = task_history current ++ suffix.
Proof.
 intros [update [messages|]] current.
 - exists messages; reflexivity.
 - exists []; rewrite app_nil_r; reflexivity.
Qed.

Theorem append_only_changes_retain_history : forall changes current,
 exists suffix, task_history (TaskChange.apply changes current) = task_history current ++ suffix.
Proof.
 induction changes as [|change rest IH]; intro current.
 - exists []; rewrite app_nil_r; reflexivity.
 - destruct (one_append_only_edit_retains_history change current) as [first First].
   destruct (IH (TaskChange.apply_edit change current)) as [remaining Rest].
   exists (first ++ remaining).
   change (task_history (TaskChange.apply rest (TaskChange.apply_edit change current)) =
     task_history current ++ (first ++ remaining)).
   rewrite Rest, First, <- app_assoc; reflexivity.
Qed.

Theorem field_changes_keep_the_immutable_task_identity : forall changes current,
 task_contract (TaskChange.apply changes current) = task_contract current /\
 task_lineage (TaskChange.apply changes current) = task_lineage current /\
 task_side_parent (TaskChange.apply changes current) = task_side_parent current.
Proof.
 intros changes current.
 pose proof (Focus.modifications_keep_the_frame _ _ _ TaskChange.task_focus
   TaskChange.edit_parts changes current) as Frame.
 change ((task_contract (TaskChange.apply changes current),
   task_current_profile (TaskChange.apply changes current), task_current_settings (TaskChange.apply changes current),
   task_lineage (TaskChange.apply changes current), task_side_parent (TaskChange.apply changes current),
    task_side_cursor (TaskChange.apply changes current)) =
   (task_contract current, task_current_profile current, task_current_settings current,
    task_lineage current, task_side_parent current, task_side_cursor current)) in Frame.
 injection Frame; auto.
Qed.

Theorem field_changes_keep_execution_configuration : forall changes current,
 task_current_profile (TaskChange.apply changes current) = task_current_profile current /\
 task_current_settings (TaskChange.apply changes current) = task_current_settings current.
Proof.
 intros changes current.
 pose proof (Focus.modifications_keep_the_frame _ _ _ TaskChange.task_focus
   TaskChange.edit_parts changes current) as Frame.
 change ((task_contract (TaskChange.apply changes current),
   task_current_profile (TaskChange.apply changes current), task_current_settings (TaskChange.apply changes current),
   task_lineage (TaskChange.apply changes current), task_side_parent (TaskChange.apply changes current),
    task_side_cursor (TaskChange.apply changes current)) =
   (task_contract current, task_current_profile current, task_current_settings current,
    task_lineage current, task_side_parent current, task_side_cursor current)) in Frame.
 injection Frame; auto.
Qed.

Theorem a_field_plan_installs_its_exact_interpretation : forall before (plan : TaskChange.plan before),
 find_task (TaskScope.owner (TaskChange.target plan)) (TaskChange.interpret plan) =
 Some (TaskChange.apply (TaskChange.changes plan) (TaskScope.selected (TaskChange.target plan))).
Proof.
 intros before plan; unfold TaskChange.interpret, find_task, put_task, with_tasks; cbn.
 eapply registry_replace_selected; exact (TaskScope.observed (TaskChange.target plan)).
Qed.

Theorem a_field_plan_preserves_every_other_task : forall before (plan : TaskChange.plan before) other,
 TaskScope.owner (TaskChange.target plan) <> other ->
 find_task other (TaskChange.interpret plan) = find_task other before.
Proof.
 intros before plan other Different; unfold TaskChange.interpret, find_task, put_task, with_tasks; cbn.
 now apply registry_replace_other.
Qed.

Theorem a_field_plan_preserves_the_world_frame : forall before (plan : TaskChange.plan before),
 let after := TaskChange.interpret plan in
 world_sequence after = world_sequence before /\
 world_next_ticket after = world_next_ticket before /\
 world_environment after = world_environment before /\
 world_projects after = world_projects before /\
 world_features after = world_features before /\
 List.length (world_tasks after) = List.length (world_tasks before).
Proof.
 intros; unfold TaskChange.interpret, put_task, with_tasks; cbn.
 repeat split; try reflexivity. apply registry_replace_length.
Qed.

Theorem changing_stage_retains_the_selected_operation : forall current pending stage,
 In pending (task_operations current) ->
 In (Operation (operation_id pending) (operation_call pending) (operation_announced pending) stage)
   (task_operations (TaskChange.apply [TaskChange.ChangeOperationStage (operation_id pending) stage] current)).
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor consumed] pending stage Member.
 destruct lifecycle; cbn in *; apply in_map_iff; exists pending.
 all: split; [cbn; now rewrite N.eqb_refl|exact Member].
Qed.
