From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation EffectCallbacks.
From Selvedge.Kernel Require Import ModelDeclarations.
From Selvedge.Foundation Require Import BoundedDiagnostic BoundedDiagnosticProofs.
Import ListNotations.
Open Scope string_scope.

(** External result fields cannot choose the pending operation they complete.
    Each callback family retains the coordinates from the issued effect. *)
Definition committed_coordinates (effect reply : json) : Prop :=
  match callback_kind_of (str effect "kind") with
  | Some ChatgptExec => get reply "operation_id" = get effect "operation_id"
  | Some BoardText => get reply "card_id" = get effect "card_id" /\
      get reply "ticket" = get effect "ticket"
  | Some (Worktree _) => get reply "task_id" = get effect "task_id"
  | Some AfterHook => get reply "task_id" = get effect "task_id" /\
      get reply "ticket" = get effect "ticket" /\
      get reply "operation_id" = get effect "operation_id"
  | Some _ => get reply "task_id" = get effect "task_id" /\
      get reply "ticket" = get effect "ticket"
  | None => True
  end.

Theorem completed_callback_preserves_committed_coordinates effect result reply :
  completed effect result = Some reply -> committed_coordinates effect reply.
Proof.
  unfold completed, committed_coordinates.
  destruct (callback_kind_of (str effect "kind")) as [kind|]; [destruct kind|];
    try solve [intro H; inversion H; subst; cbn [base extend worktree_reply]; repeat split; reflexivity].
Qed.

Theorem failed_callback_preserves_committed_coordinates effect message limit :
  committed_coordinates effect (failed effect message limit).
Proof.
  unfold committed_coordinates, failed.
  destruct (callback_kind_of (str effect "kind")) as [kind|]; [destruct kind|exact I];
    try solve [cbn [base failed_outcome worktree_reply]; repeat split; reflexivity].
  destruct limit; cbn [base optional]; auto.
Qed.

Theorem every_callback_diagnostic_is_admitted kind message :
 BoundedDiagnostic.accepts (diagnostic_contract kind) (diagnostic kind message) = true.
Proof.
 unfold diagnostic. apply constructed_diagnostic_is_admitted.
 destruct kind; reflexivity.
Qed.

Theorem failure_construction_is_total source kind :
 callback_kind_of (str (get source "effect") "kind") = Some kind ->
 exists reply, failure source = success reply /\
   committed_coordinates (get source "effect") reply.
Proof.
 intro callback. unfold failure. rewrite callback.
 eexists. split; [reflexivity|apply failed_callback_preserves_committed_coordinates].
Qed.
