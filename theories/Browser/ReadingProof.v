From Stdlib Require Import List NArith.
From Selvedge.Browser Require Import Reading.
Import ListNotations.

Theorem resize_keeps_user_reading_state : forall current height viewport reduced,
  fst (step (LayoutChanged height viewport) reduced current) = current.
Proof. reflexivity. Qed.
Theorem observed_anchor_does_not_select_latest : forall current point reduced,
  reading_intent (fst (step (AnchorObserved point) reduced current)) = reading_intent current.
Proof. reflexivity. Qed.
Theorem explicit_latest_cancels_anchor_and_respects_motion : forall current reduced,
  step Follow reduced current =
    (State FollowLatest None, [CancelAnchorObservation; AlignLatest (negb reduced)]).
Proof. reflexivity. Qed.
Theorem user_scroll_takes_over_viewport : forall current reduced,
  step BeginUserScroll reduced current = (State ReadHistory None, [LeaveViewport]).
Proof. reflexivity. Qed.

Theorem a_new_reader_occurrence_discards_old_anchor : forall previous observed current,
 previous <> observed -> bind_generation previous observed current = State FollowLatest None.
Proof. intros. unfold bind_generation. apply N.eqb_neq in H. rewrite H. reflexivity. Qed.
