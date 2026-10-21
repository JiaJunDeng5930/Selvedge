From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import JsonProofs.
From Selvedge.Adapters Require Import Common CloudWorkspaces.
Open Scope string_scope.

Theorem admitted_receipt_preserves_expected_fields : forall source value,
  CloudWorkspaces.receipt source = success value ->
  forall name, In name receipt_keys ->
  get value name = get (get source "expected") name.
Proof.
  intros source value accepted name member.
  unfold CloudWorkspaces.receipt in accepted.
  destruct (receipt_matches source) eqn:admitted; [|discriminate].
  inversion accepted; subst value.
  unfold receipt_matches in admitted.
  repeat rewrite andb_true_iff in admitted.
  assert (forallb (fun name => equal (get (get source "value") name)
    (get (get source "expected") name)) receipt_keys = true) as fields by tauto.
  apply forallb_forall with (x:=name) in fields; [|exact member].
  now apply JsonProofs.equal_reflects_equality in fields.
Qed.
