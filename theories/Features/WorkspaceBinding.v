From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State WorkspaceBackend.
From Selvedge.Features Require Import Domain.
Import ListNotations.
Open Scope string_scope.

Definition owned (id : N) (value : world) :=
  find (fun tree => N.eqb id (Selvedge.Features.Domain.worktree_task tree))
    (Selvedge.Features.Domain.feature_worktrees (world_features value)).

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

Definition resource_json (tree : Selvedge.Features.Domain.worktree) := JObject [
  ("task_id", number (Selvedge.Features.Domain.worktree_task tree));
  ("backend", JString (WorkspaceBackend.name (Selvedge.Features.Domain.worktree_backend tree)))].

Definition execution (settings : task_settings) (value : world) :=
  match resolve settings value with Some tree => resource_json tree | None => JNull end.

Lemma resolve_owned : forall settings value owner tree,
  settings_resource settings = Some owner ->
  owned owner value = Some tree -> resolve settings value = Some tree.
Proof.
  intros settings value owner tree reference found.
  unfold resolve. rewrite reference, found. reflexivity.
Qed.
