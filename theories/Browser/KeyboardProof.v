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

Theorem retained_composition_preserves_native_editing : forall observed,
  editing_key observed true = false /\
  unmodified_editing_key observed true = false /\
  text_confirmation observed true = false /\
  control_activation observed true = false /\
  begins_input observed true = false.
Proof.
  intros [k c i s a m]; unfold editing_key, unmodified_editing_key,
    text_confirmation, control_activation, begins_input; simpl.
  destruct c; simpl; repeat split; reflexivity.
Qed.

Theorem mention_gestures_require_unmodified_input : forall k c i s a m,
  s || a || m = true ->
  unmodified_editing_key (Observe k c i s a m) false = false.
Proof.
  intros k c i s a m H; unfold unmodified_editing_key; simpl; rewrite H.
  apply andb_false_r.
Qed.

Theorem directory_confirmation_requires_plain_enter : forall observed composing,
  text_confirmation observed composing = true ->
  key observed = "Enter" /\ unmodified_editing_key observed composing = true.
Proof.
  intros observed composing H; unfold text_confirmation in H.
  apply andb_true_iff in H as [plain enter].
  apply String.eqb_eq in enter. auto.
Qed.
