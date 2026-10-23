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

Theorem history_layout_preserves_the_saved_anchor : forall point,
  layout (State ReadHistory (Some point)) = [PreserveAnchor point].
Proof. reflexivity. Qed.
Theorem history_without_a_bookmark_requests_an_observation :
  layout (State ReadHistory None) = [MeasureAnchor].
Proof. reflexivity. Qed.
Theorem latest_layout_cancels_history_observation : forall point,
  layout (State FollowLatest point) = [CancelAnchorObservation; AlignLatest false].
Proof. reflexivity. Qed.
Theorem resizing_reserves_the_composer_before_restoring_reading :
  forall current height viewport reduced,
  step (LayoutChanged height viewport) reduced current =
    (current, ReserveComposer height viewport :: layout current).
Proof. reflexivity. Qed.
Theorem explicit_history_owns_its_selected_anchor : forall current point reduced,
  step (ReadHistoryAt point) reduced current =
    (State ReadHistory (Some point), [LeaveViewport]).
Proof. reflexivity. Qed.
Theorem anchor_observation_is_not_a_scroll_request : forall current point reduced,
  step (AnchorObserved point) reduced current =
    (State (reading_intent current) (Some point), []).
Proof. reflexivity. Qed.

Theorem reader_occurrences_preserve_the_task_reading_position : forall previous observed current,
 bind_generation previous observed current = current.
Proof. reflexivity. Qed.
