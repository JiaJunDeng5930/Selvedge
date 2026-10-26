From Stdlib Require Import NArith.
From Selvedge.Kernel Require Import Domain State TaskScope TaskScopeProofs RequestReceiver.

(* Eliminate the shared selection once. A continuation receives the exact task
   stored at this owner; it cannot redirect a late result to a proposed task. *)
Theorem deliver_selected : forall A id before lookup refused handle
 (target : task_reference before) (payload : A),
 TaskScope.select id before = Some target ->
 lookup (selected target) = Some payload ->
 deliver_or id before lookup refused handle = handle target payload.
Proof. intros; unfold deliver_or; now rewrite H,H0. Qed.

Theorem deliver_missing : forall A id before (lookup : task -> option A) refused handle,
 TaskScope.select id before = None ->
 deliver_or id before lookup refused handle = refused.
Proof. intros; unfold deliver_or; now rewrite H. Qed.

Theorem deliver_unmatched : forall A id before (lookup : task -> option A) refused handle target,
 TaskScope.select id before = Some target -> lookup (selected target) = None ->
 deliver_or id before lookup refused handle = refused.
Proof. intros; unfold deliver_or; now rewrite H,H0. Qed.

Theorem deliver_eliminate : forall A id before (lookup : task -> option A) refused handle (P : decision -> Prop),
 P refused ->
 (forall target payload, TaskScope.select id before = Some target ->
   lookup (selected target) = Some payload -> P (handle target payload)) ->
 P (deliver_or id before lookup refused handle).
Proof.
 intros A id before lookup refused handle P Missing Accepted.
 unfold deliver_or; destruct (TaskScope.select id before) as [target|] eqn:Selected; [|exact Missing].
 destruct (lookup (selected target)) as [payload|] eqn:Found; [eapply Accepted; eauto|exact Missing].
Qed.
