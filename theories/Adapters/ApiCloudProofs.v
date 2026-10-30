From Stdlib Require Import String Bool.
From Selvedge.Adapters Require Import Common Api CloudWorkspacesProofs.
From Selvedge.Kernel Require Import WorkspaceBackend.
Open Scope string_scope.

Theorem executed_cloud_receipt_preserves_expected_fields : forall source value,
  Api.call "effect.cloud_receipt" source = success value ->
  forall name, List.In name CloudWorkspaces.receipt_keys ->
  get value name = get (get source "expected") name.
Proof.
  intros source value accepted.
  change (CloudWorkspaces.receipt source = success value) in accepted.
  now apply admitted_receipt_preserves_expected_fields.
Qed.
