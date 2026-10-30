From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State WorkspaceBackend Workspace.
From Selvedge.Features Require Import Domain.
Import ListNotations.
Open Scope string_scope.

Definition owned (id : N) (value : world) :=
  find (fun tree => N.eqb id (Selvedge.Features.Domain.worktree_task tree))
    (Selvedge.Features.Domain.feature_worktrees (world_features value)).

Definition environment_reference (reference : option N) (value : world) : option (option N) :=
  match reference with
  | None => Some None
  | Some owner => match owned owner value with
    | None => None
    | Some tree => Some (if WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree)
      then Some owner else None)
    end
  end.

Definition same_environment (first second : option N) (value : world) :=
  match environment_reference first value, environment_reference second value with
  | Some first, Some second => Workspace.same_resource first second
  | _, _ => false
  end.

Definition inside (root path : string) :=
  String.eqb root path || String.prefix (String.append root "/") path.

Definition contains (space : workspace) (tree : Selvedge.Features.Domain.worktree) :=
  match workspace_primary space, Selvedge.Features.Domain.worktree_root tree with
  | Some selected, Some root => inside root selected
  | _, _ => false
  end.

Definition local (space : workspace) (value : world) :=
  find (fun tree => negb (WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree)) && contains space tree)
    (Selvedge.Features.Domain.feature_worktrees (world_features value)).

(* The reference is part of settings so independent task creation and forks
   inherit the same environment without inferring ownership from path text. *)
Definition resolve (settings : task_settings) (value : world) :=
  match settings_resource settings with
  | Some owner => owned owner value
  | None => local (settings_workspace settings) value
  end.

Definition for_task (id : N) (value : world) :=
  match find_task id value with
  | Some task => resolve (task_current_settings task) value
  | None => None
  end.

Definition settings_execution_ready (settings : task_settings) (value : world) :=
 match resolve settings value with
 | Some tree => match Selvedge.Features.Domain.worktree_phase tree with
   | Selvedge.Features.Domain.TreeReady _ _ => true | _ => false end
 | None => true end.
Definition execution_ready (id : N) (value : world) :=
 match find_task id value with
 | Some task => settings_execution_ready (task_current_settings task) value
 | None => true end.

Definition cloud_settings (settings : task_settings) :=
  Settings (settings_workspace settings) (settings_project settings) (Sandbox WorkspaceWrite true)
    FullAccess (settings_guidance settings) (settings_worktree settings) (settings_resource settings).

Definition normalize_settings (settings : task_settings) (value : world) :=
  match resolve settings value with
  | Some tree => if WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree)
    then cloud_settings settings else settings
  | None => settings
  end.

Definition cloud_task (id : N) (value : world) :=
  match for_task id value with
  | Some tree => WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree)
  | None => false
  end.

Definition resource_json := Selvedge.Features.Domain.resource_json.

Definition execution (settings : task_settings) (value : world) :=
  match resolve settings value with Some tree => resource_json tree | None => JNull end.

Definition reference_execution (owner : option N) (value : world) :=
 Selvedge.Features.Domain.reference_execution owner (world_features value).
Definition within_resource (space : workspace) (tree : Selvedge.Features.Domain.worktree) :=
  match Selvedge.Features.Domain.worktree_root tree with
  | Some root => forallb (inside root) (workspace_roots space)
  | None => false end.
Definition resource_ready (space : workspace) (owner : option N) (value : world) :=
  match owner with
  | None => true
  | Some id => match owned id value with
    | Some tree =>
      (* Cloud roots share one remote filesystem. A local managed checkout owns
         the primary root while the task can retain independent secondary roots. *)
      (if WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree)
       then within_resource space tree else contains space tree) &&
      match Selvedge.Features.Domain.worktree_phase tree with
        | Selvedge.Features.Domain.TreeReady _ _ => true | _ => false end
    | None => false end end.
Definition cloud_intersects (space : workspace) (tree : Selvedge.Features.Domain.worktree) :=
  WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree) &&
  match Selvedge.Features.Domain.worktree_root tree with
  | Some root => existsb (inside root) (workspace_roots space)
  | None => false end.
(* This is a workspace selection, not an execution-time lookup. The observed
   choice is retained by the project, task settings and the connection job. *)
Definition select_resource (space : workspace) (value : world) : option (option N) :=
  match filter (cloud_intersects space)
    (Selvedge.Features.Domain.feature_worktrees (world_features value)) with
  | [] => Some None
  | [tree] => let owner := Some (Selvedge.Features.Domain.worktree_task tree) in
    if resource_ready space owner value then Some owner else None
  (* DEFENSE: Two cloud instances can expose the same path. A path selection
     cannot choose between them, or combine roots from different environments. *)
  | _ => None end.

(* An explicit directory can still belong to the already selected environment.
   Keep that identity instead of interpreting its path on the local host. *)
Definition select_bound_workspace (base selected : task_settings) (value : world)
 : option task_settings :=
 match settings_resource base with
 | None => Some selected
 | Some owner => match owned owner value with
   | None => Some selected
   | Some tree =>
     if cloud_intersects (settings_workspace selected) tree then
       (* DEFENSE: A native request can combine an observed cloud root and a
          local project root; one execution cannot span both environments. *)
       if within_resource (settings_workspace selected) tree then
         Some (Settings (settings_workspace selected) (settings_project selected)
           (settings_sandbox selected) (settings_approval selected) (settings_guidance selected)
           (settings_worktree selected) (Some owner))
       else None
     else Some selected
   end
 end.

Lemma resolve_owned : forall settings value owner tree,
  settings_resource settings = Some owner ->
  owned owner value = Some tree -> resolve settings value = Some tree.
Proof.
  intros settings value owner tree reference found.
  unfold resolve. rewrite reference, found. reflexivity.
Qed.

Definition workspace_available (space:workspace) (value:world) := forallb
 (fun tree=>WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree) ||
 match Selvedge.Features.Domain.worktree_phase tree with Selvedge.Features.Domain.TreeReady _ _=>true | _=>
 match Selvedge.Features.Domain.worktree_root tree with Some root=>negb (existsb (fun path => String.eqb root path || String.prefix (String.append root "/") path) (workspace_roots space)) | None=>true end end)
 (Selvedge.Features.Domain.feature_worktrees (world_features value)).
