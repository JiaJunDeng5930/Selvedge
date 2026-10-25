From Stdlib Require Import List NArith.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.Kernel Require Import Domain State TaskScope TaskChange.
Import ListNotations.

Lemma apply_app : forall first rest current,
 TaskChange.apply (first ++ rest) current = TaskChange.apply rest (TaskChange.apply first current).
Proof. intros; unfold TaskChange.apply; apply fold_left_app. Qed.

Lemma one_edit_keeps_the_immutable_task_identity : forall change current,
 task_contract (TaskChange.apply_edit change current) = task_contract current /\
 task_lineage (TaskChange.apply_edit change current) = task_lineage current /\
 task_side_parent (TaskChange.apply_edit change current) = task_side_parent current.
Proof.
 intros change [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct change; destruct lifecycle; repeat split; reflexivity.
Qed.

Theorem field_changes_keep_the_immutable_task_identity : forall changes current,
 task_contract (TaskChange.apply changes current) = task_contract current /\
 task_lineage (TaskChange.apply changes current) = task_lineage current /\
 task_side_parent (TaskChange.apply changes current) = task_side_parent current.
Proof.
 intros changes; induction changes as [|change rest IH]; intro current; [repeat split; reflexivity|].
 change (let after := TaskChange.apply_edit change current in
  task_contract (TaskChange.apply rest after) = task_contract current /\
  task_lineage (TaskChange.apply rest after) = task_lineage current /\
  task_side_parent (TaskChange.apply rest after) = task_side_parent current).
 destruct (IH (TaskChange.apply_edit change current)) as [Contract [Lineage Parent]].
 destruct (one_edit_keeps_the_immutable_task_identity change current) as [OwnContract [OwnLineage OwnParent]].
 cbv zeta. now rewrite Contract, Lineage, Parent, OwnContract, OwnLineage, OwnParent.
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

Theorem a_stage_change_preserves_other_operation_keys : forall selected queried stage current,
 selected <> queried ->
 find (fun operation => N.eqb queried (operation_id operation))
   (task_operations (TaskChange.apply [TaskChange.ChangeOperationStage selected stage] current)) =
 find (fun operation => N.eqb queried (operation_id operation)) (task_operations current).
Proof.
 intros selected queried stage current Different.
 assert (Map : forall operations : list operation,
  find (fun pending => N.eqb queried (operation_id pending))
   (map (fun pending => if N.eqb selected (operation_id pending) then
      Operation (operation_id pending) (operation_call pending) (operation_announced pending) stage
      else pending) operations) =
  find (fun pending => N.eqb queried (operation_id pending)) operations).
 { intro operations; induction operations as [|pending rest IH]; [reflexivity|].
   cbn [map find]; destruct (N.eqb selected (operation_id pending)) eqn:Write;
   destruct (N.eqb queried (operation_id pending)) eqn:Read;
   cbn [operation_id]; rewrite ?Read; try reflexivity; try exact IH;
   apply N.eqb_eq in Write, Read; exfalso; apply Different; congruence. }
 destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle; cbn [TaskChange.apply TaskChange.apply_edit fold_left task_operations with_operations with_lifecycle];
 apply Map.
Qed.

Theorem a_stage_change_keeps_operation_identity_and_call : forall selected stage current,
 map (fun operation => (operation_id operation,operation_call operation))
   (task_operations (TaskChange.apply [TaskChange.ChangeOperationStage selected stage] current)) =
 map (fun operation => (operation_id operation,operation_call operation)) (task_operations current).
Proof.
 intros selected stage current.
 assert (Map : forall operations : list operation,
  map (fun pending => (operation_id pending,operation_call pending))
   (map (fun pending => if N.eqb selected (operation_id pending) then
      Operation (operation_id pending) (operation_call pending) (operation_announced pending) stage
      else pending) operations) =
  map (fun pending => (operation_id pending,operation_call pending)) operations).
 { intro operations; rewrite map_map; apply map_ext; intro pending;
   destruct (N.eqb selected (operation_id pending)); reflexivity. }
 destruct current as [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle; apply Map.
Qed.
