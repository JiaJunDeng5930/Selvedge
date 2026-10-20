From Stdlib Require Import String List Bool Arith NArith Lia.
From Selvedge.Browser Require Import Native.

Theorem composing_never_submits : forall key ime shift alt modified multiline enabled pending,
  submit (normalize_key (KeyObservation key true ime shift alt modified) multiline enabled pending) = false.
Proof. intros; unfold normalize_key; simpl; destruct (String.eqb key "Enter"); reflexivity. Qed.

Theorem ime_never_submits : forall key composing shift alt modified multiline enabled pending,
  submit (normalize_key (KeyObservation key composing true shift alt modified) multiline enabled pending) = false.
Proof. intros; unfold normalize_key; simpl; destruct (String.eqb key "Enter"), composing; reflexivity. Qed.

Theorem pending_never_resubmits : forall key multiline,
  submit (normalize_key key multiline true true) = false.
Proof. intros; unfold normalize_key; simpl; rewrite Bool.andb_false_r; reflexivity. Qed.

Theorem simultaneous_fits : forall viewport requirements,
  allocate viewport requirements = Simultaneous ->
  navigation_minimum requirements + content_minimum requirements +
    rail_width requirements + gap_width requirements <= viewport.
Proof.
  intros viewport requirements; unfold allocate, simultaneous_minimum.
  destruct (Nat.leb _ _) eqn:fits; [apply Nat.leb_le in fits; auto | discriminate].
Qed.

Theorem stale_publication_does_not_clear_lag : forall generation state,
  generation <> semantic_generation state -> accept_publication generation state = state.
Proof.
  intros generation state different; unfold accept_publication.
  assert (N.eqb generation (semantic_generation state) = false) by (apply N.eqb_neq; assumption).
  rewrite H; reflexivity.
Qed.

Theorem accepted_publication_is_current : forall state,
  document_generation state = semantic_generation state ->
  fresh (accept_publication (semantic_generation state) state) = true.
Proof.
  intros state current; unfold fresh, accept_publication; rewrite current, N.eqb_refl; simpl; apply N.eqb_refl.
Qed.

Theorem semantic_change_requires_publication : forall state,
  fresh state = true -> fresh (advance_semantics state) = false.
Proof.
  intros state ready; unfold fresh in *; apply N.eqb_eq in ready.
  unfold advance_semantics; cbn -[N.eqb]; apply N.eqb_neq; lia.
Qed.

Theorem user_scroll_never_aligns_latest : forall state,
  snd (read_step BeginScroll state) = nil.
Proof. reflexivity. Qed.

Theorem layout_preserves_reading_intent : forall state,
  fst (read_step LayoutChanged state) = state.
Proof. reflexivity. Qed.

Theorem editing_does_not_change_reading_intent : forall key state,
  fst (read_step (ReadingKey key true) state) = state.
Proof. intros; cbn [read_step]; rewrite Bool.andb_false_r; reflexivity. Qed.

Theorem admitted_event_is_from_current_document : forall generation state,
  admit_generation generation state = true ->
  generation = semantic_generation state /\
    document_generation state = semantic_generation state.
Proof.
  intros generation state admitted; unfold admit_generation, fresh in admitted.
  apply Bool.andb_true_iff in admitted as [published current].
  apply N.eqb_eq in published; apply N.eqb_eq in current; auto.
Qed.

Theorem admitted_same_namespace_snapshot_does_not_roll_back : forall origin expected incoming cursor state,
  incoming = namespace state -> admit_snapshot origin expected incoming cursor state = true ->
  (sequence state <= cursor)%N.
Proof.
  intros origin expected incoming cursor state same admitted.
  unfold admit_snapshot in admitted; rewrite same, String.eqb_refl in admitted.
  apply Bool.andb_true_iff in admitted as [_ ordered]; apply N.leb_le; exact ordered.
Qed.
