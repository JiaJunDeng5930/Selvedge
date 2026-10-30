From Selvedge.Kernel Require Import TaskConstraints.
From Selvedge.Kernel Require Import TaskChangesProofs.
From Selvedge.Foundation Require Import RegistryProofs.
From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks LifecycleProofs.
Import ListNotations.
Open Scope string_scope.

Theorem constructed_children_have_the_requested_count :
 forall count owner parent messages settings entry start next invocation,
 List.length (Tasks.constructed_children count owner parent messages settings entry start next invocation) = count.
Proof.
 induction count; intros; cbn [Tasks.constructed_children List.length]; auto.
Qed.

Theorem constructed_children_have_the_parent_lineage :
 forall count owner parent messages settings entry start next invocation,
 Forall (fun child => task_lineage child = owner :: task_lineage parent)
   (Tasks.constructed_children count owner parent messages settings entry start next invocation).
Proof.
 induction count; intros; cbn [Tasks.constructed_children]; constructor; [reflexivity|apply IHcount].
Qed.

Definition registry_lookup_preserved_by_append := @Selvedge.Foundation.RegistryProofs.registry_lookup_preserved_by_append.
Lemma append_task_preserves_existing : forall owner existing child value,
 find_task owner value = Some existing -> find_task owner (append_task child value) = Some existing.
Proof.
 intros. unfold find_task, append_task, with_tasks; cbn.
 eapply registry_lookup_preserved_by_append; exact H.
Qed.
Theorem fork_children_preserve_every_existing_task : forall count parent_id parent messages settings entry start invocation before owner existing,
 find_task owner before = Some existing ->
 find_task owner (Tasks.fork_children count parent_id parent messages settings entry start invocation before) = Some existing.
Proof.
 intros; unfold Tasks.fork_children, find_task, with_tasks; cbn.
 eapply registry_lookup_preserved_by_append; exact H.
Qed.
Theorem fork_does_not_write_unrelated_existing_tasks : forall entry origin id count messages settings before other existing,
 other <> id -> find_task other before = Some existing ->
 find_task other (decision_world (Tasks.fork_with_caller entry origin id count messages settings before)) = Some existing.
Proof.
 intros entry origin id count messages settings before other existing Different Found.
 rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta.
 destruct (find_task id before) as [parent|]; [|exact Found].
 destruct (Tasks.fork_parent_ready entry parent &&
   TaskConstraints.fork_count_fits count (contract_max_fork (task_contract parent)) &&
   TaskConstraints.fork_messages_valid count (List.length messages) &&
   Tasks.ancestors_fit (id :: task_lineage parent) count before).
 2: { unfold Tasks.fork_refusal; destruct entry;
      try destruct (Tasks.fork_parent_ready Tasks.ManualFork parent); exact Found. }
 destruct (Tasks.resolve_settings (task_current_profile parent) settings (Tasks.fork_settings_base origin parent before) before)
   as [selected|]; [|exact Found].
 destruct (Tasks.admit_fork_selection parent before selected) as [selection|]; [|exact Found].
 destruct (match entry with Tasks.ManualFork => false | Tasks.AcceptedNativeFork _ _ =>
   negb (Workspace.may_delegate (Tasks.fork_selected parent before selection) (task_current_settings parent) &&
     Tasks.no_resource_observation settings) end); [exact Found|].
 destruct (allocate_ticket before) as [ticket allocated] eqn:Allocated.
 cbn [decision_world accept]. apply fork_children_preserve_every_existing_task.
 destruct entry; [|exact Found].
 unfold find_task, put_task, with_tasks; cbv [set]; cbn.
 rewrite registry_replace_other by congruence.
 unfold allocate_ticket in Allocated; inversion Allocated; subst allocated.
 unfold with_ticket; cbn. exact Found.
Qed.
Theorem accepted_native_fork_never_reconfigures_its_parent : forall invocation remaining origin id count messages settings before parent,
 find_task id before = Some parent ->
 find_task id (decision_world
   (Tasks.fork_with_caller (Tasks.AcceptedNativeFork invocation remaining) origin id count messages settings before)) = Some parent.
Proof.
 intros invocation remaining origin id count messages settings before parent Found.
 rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta; rewrite Found.
 destruct (Tasks.fork_parent_ready (Tasks.AcceptedNativeFork invocation remaining) parent &&
   TaskConstraints.fork_count_fits count (contract_max_fork (task_contract parent)) &&
   TaskConstraints.fork_messages_valid count (List.length messages) &&
   Tasks.ancestors_fit (id :: task_lineage parent) count before); [|exact Found].
 destruct (Tasks.resolve_settings (task_current_profile parent) settings (Tasks.fork_settings_base origin parent before) before)
   as [selected|]; [|exact Found].
 destruct (Tasks.admit_fork_selection parent before selected) as [selection|]; [|exact Found].
 cbn. destruct (negb (Workspace.may_delegate (Tasks.fork_selected parent before selection) (task_current_settings parent) &&
   Tasks.no_resource_observation settings)); [exact Found|].
 destruct (allocate_ticket before). cbn [decision_world accept].
 apply fork_children_preserve_every_existing_task; exact Found.
Qed.
