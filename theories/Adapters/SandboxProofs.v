From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import JsonProofs.
From Selvedge.Adapters Require Import Common Observation Workspaces SandboxPolicy Seatbelt Sandbox.
Import ListNotations.
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

Theorem seccomp_instruction_cannot_supply_unknown_opcode : forall instruction,
  In (get (instruction_json instruction) "code")
    [number 6;number 21;number 32;number 53;number 69].
Proof.
  intros instruction. destruct instruction;cbn;try tauto.
  destruct comparison;cbn;tauto.
Qed.
