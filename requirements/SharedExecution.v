(** * Shared execution environments

    A Workspace's directory settings select the machine that interprets its
    paths. A Project can provide this Workspace as a default for a task. A draft
    that changes machines needs a fresh selection of directory paths.
    The receiver runs the access mode and sandbox selected by the task. Its
    connection authentication identifies the calling installation. A caller
    retrying a start after delivery loss observes the original operation.
    A conflicting operation cannot start under the same durable identity.
    Cancellation that reaches the receiver before a delayed start prevents
    that start from launching. *)
From Stdlib Require Import String.
From Selvedge.Foundation Require Import Json.
From Selvedge.Adapters Require Import SharedExecution.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Kernel Require Import Workspace.
From Selvedge.Features Require WorkspaceBinding.
Open Scope string_scope.

Lemma reserved_start_cannot_launch_again : forall request incoming,
  start_action true request incoming <> "reserve".
Proof.
 intros request incoming. destruct request; cbn [start_action negb]; try discriminate;
 match goal with |- (if ?same then _ else _) <> _ => destruct same; discriminate end.
Qed.

Lemma conflicts_cannot_launch : forall previous incoming,
  previous <> JNull -> Json.equal previous incoming = false ->
  start_action true previous incoming = "conflict".
Proof.
 intros previous incoming present Different. destruct previous; try contradiction;
   cbn [start_action negb];
   match goal with |- (if ?same then _ else _) = _ => change (same = false) in Different end;
   now rewrite Different.
Qed.

Lemma early_cancellation_prevents_launch : forall request,
  start_action true JNull request = "cancelled".
Proof. reflexivity. Qed.

(** The receiver selection excludes local and cloud Worktree path inference.
    The task's execution settings therefore retain their original sandbox
    and approval policy when their workspace is shared. *)
Lemma shared_workspace_keeps_task_permissions : forall settings value,
  Workspace.on_shared_environment (settings_workspace settings) = true ->
  settings_resource settings = None ->
  WorkspaceBinding.normalize_settings settings value = settings.
Proof.
 intros settings value shared unowned.
 unfold WorkspaceBinding.normalize_settings, WorkspaceBinding.resolve.
 now rewrite unowned, shared.
Qed.

Lemma selecting_another_workspace_machine_clears_directory_paths : forall workspace environment,
  same_environment workspace (ExecutionWorkspace nil None environment) = false ->
  workspace_roots (select_environment environment workspace) = nil /\
  workspace_primary (select_environment environment workspace) = None.
Proof.
 intros workspace environment changed.
 unfold select_environment. now rewrite changed.
Qed.
