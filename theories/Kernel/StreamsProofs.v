From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require Import Streams.
Import ListNotations.

Lemma key_equal_true : forall left right, key_equal left right = true <-> left = right.
Proof.
  intros [task ticket] [other_task other_ticket]. unfold key_equal;cbn.
  rewrite andb_true_iff,!N.eqb_eq. split;[intros [-> ->];reflexivity|intro H;inversion H;auto].
Qed.
Lemma updated_stream_keeps_identity : forall delta config entry index text updated,
  update_part delta config entry index text = Some updated ->
  stream_identity updated = stream_identity entry.
Proof.
  intros delta config entry index text updated H. unfold update_part in H.
  match type of H with context[if ?accepted then Some _ else None] => destruct accepted end;inversion H;reflexivity.
Qed.
Theorem stream_update_preserves_all_invocation_identities : forall delta config key index text streams,
  map stream_identity (fst (update delta config key index text streams)) = map stream_identity streams.
Proof.
  intros delta config key index text streams. induction streams as [|entry rest IH];cbn;auto.
  destruct (key_equal (stream_identity entry) key).
  - destruct (update_part delta config entry index text) eqn:updated;cbn;[|reflexivity].
    apply updated_stream_keeps_identity in updated. now rewrite updated.
  - destruct (update delta config key index text rest) eqn:tail;cbn in *.
    rewrite IH. reflexivity.
Qed.
Theorem finishing_a_stream_preserves_every_unrelated_invocation : forall config key streams entry,
  In entry (fst (step config (Finish key) streams)) <->
  In entry streams /\ stream_identity entry <> key.
Proof.
  intros config key streams entry. cbn. rewrite filter_In,negb_true_iff.
  split.
  - intros [member different]. split;[exact member|].
    intro E. assert (same : key_equal (stream_identity entry) key = true) by (apply key_equal_true;exact E).
    rewrite same in different;discriminate.
  - intros [member different]. split;[exact member|].
    destruct (key_equal (stream_identity entry) key) eqn:same;[|reflexivity].
    apply key_equal_true in same. contradiction.
Qed.
Theorem accepted_browser_restoration_obeys_text_and_part_budgets : forall restored previous,
  snd (step browser_configuration (Restore restored) previous) = true ->
  forallb (fun entry => parts_within_budget (stream_parts entry))
    (fst (step browser_configuration (Restore restored) previous)) = true.
Proof.
  intros restored previous. cbn.
  destruct (forallb (fun entry => parts_within_budget (stream_parts entry)) (normalized_state restored)) eqn:bounded;
    cbn;[exact (fun _ => bounded)|discriminate].
Qed.
