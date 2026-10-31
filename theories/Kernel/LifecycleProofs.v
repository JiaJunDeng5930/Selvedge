From Selvedge.Kernel Require Import CallbackChangesProofs.
From Selvedge.Kernel Require Import TaskChangesProofs.
From Selvedge.Foundation Require Import RegistryProofs.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Tasks History Recovery RecoveryProofs Inputs Callbacks.
Import ListNotations.

Definition registry_replace_selected := @Selvedge.Foundation.RegistryProofs.registry_replace_selected.
Definition registry_replace_length := @Selvedge.Foundation.RegistryProofs.registry_replace_length.
Lemma find_put_task : forall id before after value,
 find_task id value = Some before -> find_task id (put_task id after value) = Some after.
Proof. intros; unfold find_task, put_task, with_tasks; cbn; eapply registry_replace_selected; eauto. Qed.
Theorem task_creation_never_rewrites_existing_history : forall value created,
 world_tasks (append_task created value) = world_tasks value ++ [created].
Proof. reflexivity. Qed.
Theorem archival_removes_all_execution_authority : forall value,
 task_archived value = false ->
 task_lifecycle (Tasks.control_task Tasks.Archive value) = Archived [] /\
 task_operations (Tasks.control_task Tasks.Archive value) = [].
Proof.
 intros [contract profile settings lifecycle history queued lineage parent cursor] Live.
 destruct lifecycle; cbn [task_archived task_lifecycle] in Live; try discriminate;
 split; reflexivity.
Qed.
Theorem restart_removes_all_old_operation_rights : forall id value,
 task_operations (Recovery.recover_task id value) = [].
Proof. apply recovery_retires_every_operation. Qed.
Theorem restart_emits_no_old_external_request : forall value,
 decision_effects (Recovery.recover value) = [].
Proof. reflexivity. Qed.
Theorem restart_retains_committed_history : forall id value,
 exists suffix, task_history (Recovery.recover_task id value) = task_history value ++ suffix.
Proof. apply recovery_retains_committed_history. Qed.
Theorem fork_snapshot_includes_original_history : forall id value,
 exists suffix, History.snapshot_history id value = task_history value ++ suffix.
Proof. intros; unfold History.snapshot_history, History.close_operations; eexists; rewrite app_assoc; reflexivity. Qed.
Theorem inference_completion_requires_current_ticket : forall id ticket expected allowed mode outcome value task,
 find_task id value = Some task -> task_activity task = AskingModel expected allowed mode ->
 expected <> ticket -> Callbacks.model_completed id ticket outcome value = Callbacks.ignored value.
Proof.
 intros id ticket expected allowed mode outcome value task Hfind Hphase Hticket.
 rewrite CallbackChangesProofs.model_completed_expression; rewrite Hfind, Hphase.
 apply N.eqb_neq in Hticket; rewrite Hticket; reflexivity.
Qed.
Lemma find_none_when_rejected : forall (A : Type) (predicate : A -> bool) values,
 (forall item, In item values -> predicate item = false) -> find predicate values = None.
Proof.
 intros A predicate values; induction values as [|item rest IH]; intros H; cbn; [reflexivity|].
 rewrite H by (left; reflexivity). apply IH; intros; apply H; right; assumption.
Qed.
Theorem tool_completion_requires_owned_execution : forall id ticket result error value task,
 find_task id value = Some task ->
 (forall operation, In operation (task_operations task) ->
  match operation_stage operation with Executing actual | Elevated actual _ => actual <> ticket | _ => True end) ->
 Callbacks.tool_completed id ticket result error value = Callbacks.ignored value.
Proof.
 intros id ticket result error value task Hfind Howned.
 rewrite CallbackChangesProofs.tool_completed_expression; rewrite Hfind.
 assert (Hnone : find (Callbacks.operation_executing ticket) (task_operations task) = None).
 { apply find_none_when_rejected. intros operation Hinside.
   specialize (Howned operation Hinside). unfold Callbacks.operation_executing, RequestReceiver.operation_executing, RequestReceiver.operation_receiver.
   destruct (operation_stage operation); try reflexivity; apply N.eqb_neq; exact Howned. }
 rewrite Hnone; reflexivity.
Qed.
