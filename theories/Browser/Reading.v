From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Numbers.
Import ListNotations.
Open Scope string_scope.

(** Physical measurements preserve their decimal spelling. Native CSS evaluates
    the requested clamp; the host does not implement another reading policy. *)
Definition extent := { spelling : string | number_lexeme spelling = true }.
Definition admit_extent (spelling : string) : option extent.
Proof.
  destruct (number_lexeme spelling) eqn:accepted.
  - exact (Some (exist _ spelling accepted)).
  - exact None.
Defined.
Definition pixels (value : extent) := proj1_sig value ++ "px".
Definition clearance_css (height viewport : extent) :=
  "min(max(" ++ pixels height ++ ", 0px), max(" ++ pixels viewport ++ ", 0px))".
Record anchor := Anchor { anchor_key : string; offset : extent }.
Inductive intent := FollowLatest | ReadHistory.
Record state := State { reading_intent : intent; bookmark : option anchor }.
Inductive event := BeginUserScroll | ReadHistoryAt (point : anchor) | Follow
  | LayoutChanged (dock viewport : extent) | AnchorObserved (point : anchor)
  | JumpToMessage (index : N) | NavigationKey (key : string) (editable : bool).
Inductive effect := LeaveViewport | CancelAnchorObservation
  | AlignLatest (animate : bool) | PreserveAnchor (point : anchor) | MeasureAnchor
  | LocateMessage (index : N) | ReserveComposer (height viewport : extent).
Definition layout current := match reading_intent current with
  | FollowLatest => [CancelAnchorObservation; AlignLatest false]
  | ReadHistory => match bookmark current with
      Some point => [PreserveAnchor point] | None => [MeasureAnchor] end
  end.
Definition navigation_key key :=
  existsb (String.eqb key) ["PageUp"; "PageDown"; "ArrowUp"; "ArrowDown"; "Home"; "End"].
Definition step input reduced_motion current : state * list effect :=
  match input with
  | BeginUserScroll => (State ReadHistory None, [LeaveViewport])
  | ReadHistoryAt point => (State ReadHistory (Some point), [LeaveViewport])
  | Follow => (State FollowLatest None,
      [CancelAnchorObservation; AlignLatest (negb reduced_motion)])
  | LayoutChanged height viewport =>
      (current, ReserveComposer height viewport :: layout current)
  | AnchorObserved point => (State (reading_intent current) (Some point), [])
  | JumpToMessage index => (State ReadHistory None, [LeaveViewport; LocateMessage index])
  | NavigationKey key editable =>
      if negb editable && navigation_key key
      then (State ReadHistory None, [LeaveViewport]) else (current, [])
  end.

(** The host stores this state under the task-view key. A new visit changes
    observation authority, but does not discard that task's reading position. *)
Definition bind_generation (_previous _observed : N) (current : state) := current.
