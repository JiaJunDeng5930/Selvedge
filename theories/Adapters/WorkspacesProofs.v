From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import JsonProofs JsonObjectsProofs.
From Selvedge.Adapters Require Import Common Observation Workspaces.
Import ListNotations.
Open Scope string_scope.

Theorem supplied_workspace_prevents_project_resolution : forall source,
  has (get source "value") "workspace" = true ->
  JsonObjects.equivalent (workspace_selection_plan source) (success (JObject [
    ("project_id", JNull); ("observe_workspace", JBool true)])) = true.
Proof.
  intros source supplied; unfold workspace_selection_plan.
  rewrite supplied; cbn [negb]; rewrite andb_false_r; apply equivalent_is_reflexive.
Qed.

Theorem workspace_binding_matches_committed_paths : forall source,
  workspace_bound source = success (execution_context (get source "workspace") (get source "plan")) <->
  get (get source "workspace") "roots" = get (get (get source "plan") "workspace") "roots" /\
  get (get source "workspace") "primary_root" = get (get (get source "plan") "workspace") "primary_root".
Proof.
  intro source; split.
  - unfold workspace_bound. destruct (_ && _) eqn:Matches; [|discriminate].
    intros _. apply andb_true_iff in Matches. destruct Matches as [Roots Primary].
    split; now apply equal_reflects_equality.
  - intros [Roots Primary]. unfold workspace_bound.
    rewrite Roots, Primary, !equal_is_reflexive. reflexivity.
Qed.

Theorem archive_path_is_owned_storage : forall source,
  str source "operation" = "archive" -> worktree_path source = success JNull ->
  get source "root" = get (get source "files") "active" \/
  get source "root" = get (get source "files") "archived".
Proof.
  intros source operation H. unfold worktree_path in H.
  rewrite operation in H. cbn in H.
  destruct (equal (get source "root") (get (get source "files") "active") ||
    equal (get source "root") (get (get source "files") "archived")) eqn:owned;
    [|discriminate].
  apply orb_true_iff in owned. destruct owned as [active|archived].
  - left. apply equal_reflects_equality;exact active.
  - right. apply equal_reflects_equality;exact archived.
Qed.
