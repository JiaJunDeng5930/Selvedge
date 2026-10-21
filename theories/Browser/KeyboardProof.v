From Stdlib Require Import String Bool.
From Selvedge.Browser Require Import Keyboard.

Theorem ime_confirmation_preserves_native_input : forall key ime shift alt modified multiline enabled pending,
  normalize (Observe key true ime shift alt modified) multiline enabled pending = Decide false false.
Proof. intros; unfold normalize, confirmation; simpl; destruct (String.eqb key "Enter"); reflexivity. Qed.
Theorem ime_key_preserves_native_input : forall key shift alt modified multiline enabled pending,
  normalize (Observe key false true shift alt modified) multiline enabled pending = Decide false false.
Proof. intros; unfold normalize, confirmation; simpl; destruct (String.eqb key "Enter"); reflexivity. Qed.
Theorem pending_operation_is_not_submitted : forall observed multiline enabled,
  submit (normalize observed multiline enabled true) = false.
Proof. intros; unfold normalize; simpl; apply andb_false_r. Qed.
