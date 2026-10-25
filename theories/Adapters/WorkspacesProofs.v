From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import JsonProofs.
From Selvedge.Adapters Require Import Common Observation Workspaces.
Import ListNotations.
Open Scope string_scope.

Theorem clients_cannot_supply_committed_guidance : forall source,
  is_null (get (get source "value") "guidance") = false ->
  workspace_settings source = type_error "Root guidance and workspace resources are observed by the service, not supplied by a client".
Proof. intros source H;unfold workspace_settings,type_admit;rewrite H;reflexivity. Qed.

Theorem supplied_workspace_prevents_project_resolution : forall source,
  has (get source "value") "workspace" = true ->
  is_null (get (get source "value") "guidance") = true ->
  is_null (get (get source "value") "workspace_binding") = true ->
  workspace_settings source = success (JObject [
    ("project_id", JNull); ("observe_workspace", JBool true)]).
Proof.
  intros source supplied guidance resource. unfold workspace_settings,type_admit.
  rewrite supplied,guidance,resource. cbn [negb]. rewrite andb_false_r. reflexivity.
Qed.

Theorem changed_committed_roots_prevent_execution : forall source,
  equal (get (get source "workspace") "roots")
    (get (get (get source "plan") "workspace") "roots") = false ->
  workspace_bound source = err "A workspace root changed after it was committed; reselect the workspace before executing".
Proof. intros source H;unfold workspace_bound;rewrite H;rewrite andb_false_r;reflexivity. Qed.

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

Theorem clients_cannot_supply_workspace_resource_observations : forall source,
  is_null (get (get source "value") "workspace_binding") = false ->
  workspace_settings source = type_error "Root guidance and workspace resources are observed by the service, not supplied by a client".
Proof.
 intros source H. unfold workspace_settings,type_admit. rewrite H.
 rewrite andb_false_r. reflexivity.
Qed.
