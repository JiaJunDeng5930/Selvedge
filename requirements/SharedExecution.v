(** * Shared execution environments

    A Workspace's directory settings select the machine that interprets its
    paths. A Project can provide this Workspace as a default for a task. A draft
    that changes machines needs a fresh selection of directory paths.
    The receiver runs the access mode and sandbox selected by the task. Its
    connection authentication identifies the calling installation. A caller
    retrying a start after delivery loss observes the original operation.
    A conflicting operation cannot start under the same durable identity.
    Cancellation that reaches the receiver before a delayed start prevents
    that start from launching.

    An installation can share a local MCP server with its paired task service.
    The local MCP connection remains the authority for tools and process
    permissions. An import is an installation-wide tool selection, independent
    of the task Workspace. It identifies the receiver and the exported server.
    MCP invocations use the same durable operation identity as other shared
    execution, with admission to a server controlled by the export list. *)
From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Adapters Require Import SharedExecution.
From Selvedge.Adapters Require Common.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Kernel Require Import Workspace.
From Selvedge.Features Require WorkspaceBinding.
Open Scope string_scope.

Lemma shared_mcp_authority_is_explicit : forall exports server,
  exported_mcp exports server = true -> In server (map Common.text exports).
Proof.
 intros exports server Allowed. unfold exported_mcp, has_name in Allowed.
 apply existsb_exists in Allowed. destruct Allowed as [name [Member Equal]].
 apply String.eqb_eq in Equal. now subst name.
Qed.

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

(** A shared directory may select a Git worktree on the same receiver.
    That checkout retains the task's sandbox and approval policy. *)
Lemma shared_workspace_keeps_task_permissions : forall settings value,
  Workspace.on_shared_environment (settings_workspace settings) = true ->
  settings_resource settings = None ->
  WorkspaceBinding.normalize_settings settings value = settings.
Proof.
 intros settings value shared unowned.
 unfold WorkspaceBinding.normalize_settings, WorkspaceBinding.resolve.
 rewrite unowned. unfold WorkspaceBinding.local.
 destruct (find _ _) as [tree|] eqn:found; [|reflexivity].
 apply find_some in found as [_ available].
 apply Bool.andb_true_iff in available as [backend _].
 apply Bool.negb_true_iff in backend. now rewrite backend.
Qed.

Lemma selecting_another_workspace_machine_clears_directory_paths : forall workspace environment,
  same_environment workspace (ExecutionWorkspace nil None environment) = false ->
  workspace_roots (select_environment environment workspace) = nil /\
  workspace_primary (select_environment environment workspace) = None.
Proof.
 intros workspace environment changed.
 unfold select_environment. now rewrite changed.
Qed.
