From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import FreshNames FreshNamesProofs.
From Selvedge.Kernel Require Import Domain History ContextSelection Tasks.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem manual_fork_identity_fresh : forall ticket task identity,
 In identity (Tasks.fork_call_ids task) ->
 Tasks.manual_fork_identity ticket task <> identity.
Proof.
 intros ticket task identity Present.
 unfold Tasks.manual_fork_identity.
 apply FreshNamesProofs.fresh_name_is_fresh; [discriminate|exact Present].
Qed.

Theorem manual_fork_identity_fresh_history : forall ticket task message identity,
 In message (task_history task) ->
 In identity (Tasks.fork_message_call_ids message) ->
 Tasks.manual_fork_identity ticket task <> identity.
Proof.
 intros ticket task message identity Message Identity.
 apply manual_fork_identity_fresh.
 unfold Tasks.fork_call_ids; apply in_or_app; left.
 apply in_flat_map; exists message; auto.
Qed.

Theorem manual_fork_identity_fresh_pending : forall ticket task invocation,
 In invocation (History.pending_invocations (task_activity task)) ->
 Tasks.manual_fork_identity ticket task <> call_id invocation.
Proof.
 intros ticket task invocation Present; apply manual_fork_identity_fresh.
 unfold Tasks.fork_call_ids; apply in_or_app; right.
 apply in_or_app; left; apply in_map; exact Present.
Qed.

Theorem manual_fork_identity_fresh_operation : forall ticket task operation,
 In operation (task_operations task) ->
 Tasks.manual_fork_identity ticket task <> call_id (operation_call operation).
Proof.
 intros ticket task operation Present; apply manual_fork_identity_fresh.
 unfold Tasks.fork_call_ids; apply in_or_app; right.
 apply in_or_app; right; apply in_map_iff.
 exists operation; split; [reflexivity|exact Present].
Qed.

Lemma fork_receipt_preserves_other_output : forall history invocation owner branch identity,
 call_id invocation <> identity ->
 ContextSelection.has_output
   (history ++ [FunctionCall invocation; ForkReceipt owner invocation branch]) identity =
 ContextSelection.has_output history identity.
Proof.
 intros history invocation owner branch identity Different.
 unfold ContextSelection.has_output; rewrite existsb_app.
 destruct invocation as [call_identity name arguments attempt]; cbn in *.
 apply String.eqb_neq in Different; rewrite Different; cbn.
 apply orb_false_r.
Qed.

Theorem manual_fork_receipt_preserves_operation_output :
 forall ticket task operation owner branch arguments,
 In operation (task_operations task) ->
 let invocation := Call (Tasks.manual_fork_identity ticket task) "fork_task" arguments InitialAttempt in
 ContextSelection.has_output
   (task_history task ++ [FunctionCall invocation; ForkReceipt owner invocation branch])
   (call_id (operation_call operation)) =
 ContextSelection.has_output (task_history task) (call_id (operation_call operation)).
Proof.
 intros ticket task operation owner branch arguments Present; cbn zeta.
 apply fork_receipt_preserves_other_output.
 now apply manual_fork_identity_fresh_operation.
Qed.
