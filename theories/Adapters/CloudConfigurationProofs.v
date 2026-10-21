From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import SchemaProofs.
From Selvedge.Adapters Require Import Common CloudConfiguration.
From Selvedge.Kernel Require Import WorkspaceBackend.
Open Scope string_scope.

Theorem enabled_configuration_passed_admission : forall source value,
  CloudConfiguration.call source = success value ->
  value <> JBool false ->
  CloudConfiguration.valid (get source "cloud") = true /\ value = get source "cloud".
Proof.
  intros source value accepted enabled. unfold CloudConfiguration.call in accepted.
  destruct (CloudConfiguration.disabled (get source "cloud")) eqn:disabled.
  - inversion accepted; subst. contradiction.
  - destruct (CloudConfiguration.valid (get source "cloud")) eqn:valid.
    + inversion accepted; subst. auto.
    + discriminate.
Qed.

Theorem configured_backend_is_tencent : forall value,
  CloudConfiguration.valid value = true ->
  str value "backend" = WorkspaceBackend.name WorkspaceBackend.TencentCvm.
Proof.
  intros value accepted. unfold CloudConfiguration.valid in accepted.
  destruct (Schema.decode cloud_schema value); [|discriminate].
  apply andb_true_iff in accepted as [backend settings].
  now apply String.eqb_eq in backend.
Qed.

Theorem enabled_configuration_has_declared_fields : forall source,
  CloudConfiguration.valid (JObject source) = true ->
  Schema.keys_declared cloud_schema source = true.
Proof.
  intros source accepted. unfold CloudConfiguration.valid in accepted.
  destruct (Schema.keys_declared cloud_schema source) eqn:declared; [reflexivity|].
  assert (Schema.decode cloud_schema (JObject source) = None) as refused.
  { now apply SchemaProofs.rejects_unknown_field. }
  rewrite refused in accepted. discriminate.
Qed.
