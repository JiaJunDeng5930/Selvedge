From Stdlib Require Import String Bool.
From Selvedge.Adapters Require Import Common Api CloudConfigurationProofs CloudWorkspacesProofs.
From Selvedge.Kernel Require Import WorkspaceBackend.
Open Scope string_scope.

Theorem executed_cloud_configuration_is_admitted : forall source value,
  Api.call "config.cloud" source = success value ->
  value <> JBool false ->
  CloudConfiguration.valid value = true /\
  str value "backend" = WorkspaceBackend.name WorkspaceBackend.TencentCvm.
Proof.
  intros source value accepted enabled.
  change (CloudConfiguration.call source = success value) in accepted.
  apply enabled_configuration_passed_admission in accepted as [valid value_source]; [|exact enabled].
  subst value. split; [exact valid|].
  now apply configured_backend_is_tencent.
Qed.

Theorem executed_cloud_receipt_preserves_expected_fields : forall source value,
  Api.call "effect.cloud_receipt" source = success value ->
  forall name, List.In name CloudWorkspaces.receipt_keys ->
  get value name = get (get source "expected") name.
Proof.
  intros source value accepted.
  change (CloudWorkspaces.receipt source = success value) in accepted.
  now apply admitted_receipt_preserves_expected_fields.
Qed.
