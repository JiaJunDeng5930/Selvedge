From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import JsonProofs JsonObjectsProofs.
From Selvedge.Adapters Require Import Common Observation Workspaces SandboxPolicy Seatbelt Sandbox.
From Selvedge.Programming Require Import AdapterResult AdapterResultProofs.
Import ListNotations.
Open Scope string_scope.

Theorem linux_sandbox_launch_preserves_binding_meaning : forall source result,
  str (get source "options") "platform" = "linux" ->
  sandbox_launch source = success result ->
  same_json_meaning (get source "bindings") (expected_bindings source).
Proof.
  intros source result platform Accepted. unfold sandbox_launch in Accepted.
  do 4 (apply successful_stage_runs_its_continuation in Accepted as [_ Accepted]).
  rewrite platform in Accepted. change (linux_launch source = success result) in Accepted.
  unfold linux_launch in Accepted.
  apply successful_stage_runs_its_continuation in Accepted as [Bindings _].
  apply successful_admission_means_its_condition in Bindings.
  now apply equivalent_preserves_json_meaning.
Qed.

Theorem unrestricted_execution_cannot_be_project_scoped : forall source result,
  unrestricted_launch source = success result ->
  str (get source "plan") "scope" <> "project".
Proof.
  intros source result H.
  unfold unrestricted_launch in H.
  apply successful_stage_runs_its_continuation in H as [_ H].
  apply successful_stage_runs_its_continuation in H as [_ H].
  apply successful_stage_runs_its_continuation in H as [access _].
  apply successful_admission_means_its_condition in access.
  apply andb_true_iff in access as [_ scope].
  apply negb_true_iff in scope. apply String.eqb_neq in scope. exact scope.
Qed.

Theorem sandbox_execution_requires_committed_sandbox_access : forall source result,
  sandbox_launch source = success result ->
  str (get source "plan") "access" = "sandboxed".
Proof.
  intros source result H.
  unfold sandbox_launch in H.
  apply successful_stage_runs_its_continuation in H as [_ H].
  apply successful_stage_runs_its_continuation in H as [_ H].
  apply successful_stage_runs_its_continuation in H as [security _].
  unfold security_admission,next in security.
  destruct (boolean_field (admit (String.eqb (str (get source "plan") "access") "sandboxed")
    "Malformed committed sandbox execution plan") "ok") eqn:access.
  - apply successful_admission_means_its_condition in access. apply String.eqb_eq in access;exact access.
  - unfold admit in access. destruct (String.eqb (str (get source "plan") "access") "sandboxed"); discriminate.
Qed.
