From Stdlib Require Import String List Bool.
From Selvedge.Adapters Require Import Common.
From Selvedge.Programming Require Import AdapterResult.
Open Scope string_scope.

Lemma successful_stage_runs_its_continuation : forall previous continuation result,
  next previous continuation = success result ->
  boolean_field previous "ok" = true /\ continuation = success result.
Proof.
  intros previous continuation result H. unfold next in H.
  destruct (boolean_field previous "ok") eqn:accepted.
  - auto.
  - rewrite H in accepted. discriminate.
Qed.

Lemma successful_admission_means_its_condition : forall condition message,
  boolean_field (admit condition message) "ok" = true -> condition = true.
Proof. intros [];cbn;intros;auto;discriminate. Qed.
