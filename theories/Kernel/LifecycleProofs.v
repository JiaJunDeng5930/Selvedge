From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Tasks History Recovery Inputs Callbacks.
Import ListNotations.

Lemma registry_replace_selected : forall (A : Type) (values : list A) index previous replacement,
 registry_at index values = Some previous -> registry_at index (replace index replacement values) = Some replacement.
Proof.
 intros A values; induction values as [|head rest IH]; intros index previous replacement H; cbn in H; try discriminate.
 cbn; destruct (N.eqb index 0) eqn:E; cbn; rewrite E; [reflexivity|].
 apply IH with previous; exact H.
Qed.
Lemma registry_replace_length : forall (A : Type) (values : list A) index replacement,
 List.length (replace index replacement values) = List.length values.
Proof. intros A values; induction values as [|head rest IH]; intros; cbn; [reflexivity|].
 destruct (N.eqb index 0); cbn; [reflexivity|rewrite IH; reflexivity]. Qed.
Lemma find_put_task : forall id before after value,
 find_task id value = Some before -> find_task id (put_task id after value) = Some after.
Proof. intros; unfold find_task, put_task, with_tasks; cbn; eapply registry_replace_selected; eauto. Qed.
Theorem task_creation_never_rewrites_existing_history : forall value created,
 world_tasks (append_task created value) = world_tasks value ++ [created].
Proof. reflexivity. Qed.
Theorem archival_removes_all_execution_authority : forall value,
 task_lifecycle (Tasks.control_task Tasks.Archive value) = Archived /\
 task_operations (Tasks.control_task Tasks.Archive value) = [].
Proof. intros [contract profile settings lifecycle history queued lineage parent cursor]; destruct lifecycle; split; reflexivity. Qed.
Theorem archived_tasks_have_no_live_operations : forall value,
 task_lifecycle value = Archived -> task_operations value = [].
Proof. intros [contract profile settings lifecycle history queued lineage parent cursor] H; cbn in *; rewrite H; reflexivity. Qed.
Theorem restart_removes_all_old_operation_rights : forall id value,
 task_operations (Recovery.recover_task id value) = [].
Proof. intros id [contract profile settings lifecycle history queued lineage parent cursor]; destruct lifecycle; reflexivity. Qed.
Theorem restart_emits_no_old_external_request : forall value,
 decision_effects (Recovery.recover value) = [].
Proof. reflexivity. Qed.
Theorem restart_retains_committed_history : forall id value,
 exists suffix, task_history (Recovery.recover_task id value) = task_history value ++ suffix.
Proof.
 intros id [contract profile settings lifecycle history queued lineage parent cursor]; destruct lifecycle; cbn [Recovery.recover_task History.close_operations with_lifecycle with_history task_history task_operations task_activity];
 eexists; rewrite app_assoc; reflexivity.
Qed.
Theorem fork_snapshot_includes_original_history : forall id value,
 exists suffix, History.snapshot_history id value = task_history value ++ suffix.
Proof. intros; unfold History.snapshot_history, History.close_operations; eexists; rewrite app_assoc; reflexivity. Qed.
Theorem inference_completion_requires_current_ticket : forall id ticket expected allowed mode outcome value task,
 find_task id value = Some task -> task_activity task = AskingModel expected allowed mode ->
 expected <> ticket -> Callbacks.model_completed id ticket outcome value = Callbacks.ignored value.
Proof.
 intros id ticket expected allowed mode outcome value task Hfind Hphase Hticket.
 unfold Callbacks.model_completed; rewrite Hfind, Hphase.
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
 unfold Callbacks.tool_completed; rewrite Hfind.
 assert (Hnone : find (Callbacks.operation_executing ticket) (task_operations task) = None).
 { apply find_none_when_rejected. intros operation Hinside.
   specialize (Howned operation Hinside). unfold Callbacks.operation_executing.
   destruct (operation_stage operation); try reflexivity; apply N.eqb_neq; exact Howned. }
 rewrite Hnone; reflexivity.
Qed.
