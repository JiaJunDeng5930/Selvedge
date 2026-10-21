From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common Observation EffectCallbacks.
Import ListNotations.
Open Scope string_scope.

Theorem callback_results_cannot_forge_task_identity : forall kind effect result,
  get (extend (base kind effect) result) "task_id" = get effect "task_id".
Proof. reflexivity. Qed.

Theorem callback_results_cannot_forge_invocation_ticket : forall kind effect result,
  get (extend (base kind effect) result) "ticket" = get effect "ticket".
Proof. reflexivity. Qed.

Theorem model_completion_preserves_committed_coordinates : forall effect result reply,
  str effect "kind" = "model" ->
  completed effect result = Some reply ->
  get reply "task_id" = get effect "task_id" /\ get reply "ticket" = get effect "ticket".
Proof.
  intros effect result reply kind H. unfold completed in H.
  rewrite kind in H. cbn in H. inversion H. auto.
Qed.

Theorem plugin_completion_preserves_committed_operation : forall effect result reply,
  str effect "kind" = "chatgpt_exec" ->
  completed effect result = Some reply ->
  get reply "operation_id" = get effect "operation_id".
Proof.
  intros effect result reply kind H. unfold completed in H.
  rewrite kind in H. cbn in H. inversion H. reflexivity.
Qed.
