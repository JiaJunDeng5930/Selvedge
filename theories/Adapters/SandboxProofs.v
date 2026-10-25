From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import JsonProofs JsonObjectsProofs.
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

Definition supported_process_transport (source : json) : Prop :=
  has (get source "options") "processMode" = false \/
  In (str (get source "options") "processMode") ["pipe";"pty"].

Lemma admitted_process_transport : forall source,
  boolean_field (plan_admission source) "ok" = true -> supported_process_transport source.
Proof.
  intros source Accepted. unfold supported_process_transport.
  unfold plan_admission in Accepted.
  destruct (has (get source "options") "processMode") eqn:Present.
  - right. destruct (existsb (String.eqb (str (get source "options") "processMode"))
      ["pipe";"pty"]) eqn:Known.
    + apply existsb_exists in Known as [mode [Member Same]].
      apply String.eqb_eq in Same. now rewrite Same.
    + discriminate Accepted.
  - now left.
Qed.

Theorem sandbox_launch_retains_process_transport : forall source result,
  sandbox_launch source = success result -> supported_process_transport source.
Proof.
  intros source result Accepted. unfold sandbox_launch in Accepted.
  apply successful_stage_runs_its_continuation in Accepted as [Plan _].
  now apply admitted_process_transport.
Qed.

Theorem unrestricted_launch_retains_process_transport : forall source result,
  unrestricted_launch source = success result -> supported_process_transport source.
Proof.
  intros source result Accepted. unfold unrestricted_launch in Accepted.
  apply successful_stage_runs_its_continuation in Accepted as [Plan _].
  now apply admitted_process_transport.
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

Theorem seccomp_instruction_cannot_supply_unknown_opcode : forall instruction,
  In (get (instruction_json instruction) "code")
    [number 6;number 21;number 32;number 53;number 69].
Proof.
  intros instruction. destruct instruction;cbn;try tauto.
  destruct comparison;cbn;tauto.
Qed.
