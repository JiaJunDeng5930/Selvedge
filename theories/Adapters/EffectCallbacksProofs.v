From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation EffectCallbacks.
Import ListNotations.
Open Scope string_scope.

(** External result fields cannot choose the pending operation they complete.
    Each callback family retains the coordinates from the issued effect. *)
Definition committed_coordinates (effect reply : json) : Prop :=
  match callback_kind_of (str effect "kind") with
  | ChatgptExec => get reply "operation_id" = get effect "operation_id"
  | BoardText => get reply "card_id" = get effect "card_id" /\
      get reply "ticket" = get effect "ticket"
  | Worktree _ => get reply "task_id" = get effect "task_id"
  | AfterHook => get reply "task_id" = get effect "task_id" /\
      get reply "ticket" = get effect "ticket" /\
      get reply "operation_id" = get effect "operation_id"
  | _ => get reply "task_id" = get effect "task_id" /\
      get reply "ticket" = get effect "ticket"
  end.

Theorem completed_callback_preserves_committed_coordinates effect result reply :
  completed effect result = Some reply -> committed_coordinates effect reply.
Proof.
  unfold completed, committed_coordinates.
  destruct (callback_kind_of (str effect "kind"));
    try solve [intro H; inversion H; subst; cbn [base extend]; repeat split; reflexivity].
  destruct (Utf8.take 1024 (str result "message")); intro H; try discriminate.
  inversion H; subst. unfold worktree_reply. cbn. reflexivity.
Qed.

Theorem failed_callback_preserves_committed_coordinates effect message short_message limit :
  committed_coordinates effect (failed effect message short_message limit).
Proof.
  unfold committed_coordinates, failed.
  destruct (callback_kind_of (str effect "kind"));
    try solve [cbn [base failed_outcome worktree_reply]; repeat split; reflexivity].
  destruct limit; cbn [base optional]; auto.
Qed.
