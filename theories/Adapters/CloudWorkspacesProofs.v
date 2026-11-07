From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import JsonProofs.
From Selvedge.Adapters Require Import Common CloudWorkspaces.
Open Scope string_scope.

Theorem admitted_receipt_preserves_expected_fields : forall source value,
  CloudWorkspaces.receipt source = success value ->
  forall name, In name receipt_keys ->
  get (get source "value") name = get (get source "expected") name.
Proof.
  intros source value accepted name member.
  unfold CloudWorkspaces.receipt in accepted.
  destruct (ArgumentDeclaration.decode CloudConfiguration.recovery_settings_declaration
    (get (get source "value") "settings")); [|discriminate].
  destruct (receipt_matches source) eqn:admitted; [|discriminate].
  unfold receipt_matches in admitted.
  repeat rewrite andb_true_iff in admitted.
  assert (forallb (fun name => equal (get (get source "value") name)
    (get (get source "expected") name)) receipt_keys = true) as fields by tauto.
  apply forallb_forall with (x:=name) in fields; [|exact member].
  now apply JsonProofs.equal_reflects_equality in fields.
Qed.

Theorem a_matching_receipt_restores_the_admitted_connection : forall source settings,
  receipt_matches source = true ->
  ArgumentDeclaration.decode CloudConfiguration.recovery_settings_declaration
    (get (get source "value") "settings") = Some settings ->
  CloudWorkspaces.receipt source =
    success (ArgumentDeclaration.encode CloudConfiguration.recovery_settings_declaration settings).
Proof.
  intros source settings Matches Admitted.
  unfold CloudWorkspaces.receipt; rewrite Admitted, Matches; reflexivity.
Qed.
