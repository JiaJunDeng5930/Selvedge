From Stdlib Require Import String List Bool Arith PeanoNat NArith.
Import ListNotations.
Open Scope string_scope.

Record key_observation := KeyObservation {
  keyboard : string; composing : bool; ime_key : bool;
  shift : bool; alt : bool; modified : bool
}.
Record key_decision := KeyDecision { submit : bool; prevent_default : bool }.
Definition normalize_key (input : key_observation) (multiline enabled pending : bool) : key_decision :=
  let enter := String.eqb (keyboard input) "Enter" &&
    negb (composing input) && negb (ime_key input) in
  let confirm := enter && negb (shift input) && negb (alt input) in
  KeyDecision (confirm && (multiline || modified input) && enabled && negb pending) confirm.

Inductive reading_intent := FollowLatest | ReadHistory.
Record anchor := Anchor { anchor_key : string; offset : string }.
Inductive reading_event := BeginScroll | AtAnchor (value : anchor) | Follow
  | LayoutChanged | JumpToMessage (index : nat) | ReadingKey (key : string) (editable : bool).
Inductive reading_effect := AlignLatest | PreserveAnchor (value : anchor)
  | MeasureAnchor | LocateMessage (index : nat).
Record reading_state := ReadingState {
  intent : reading_intent; bookmark : option anchor
}.
Definition reading_navigation_key key :=
  existsb (String.eqb key) ["PageUp"; "PageDown"; "ArrowUp"; "ArrowDown"; "Home"; "End"].
Definition reading_layout (state : reading_state) : list reading_effect :=
  match intent state with
  | FollowLatest => [AlignLatest]
  | ReadHistory => match bookmark state with
      Some value => [PreserveAnchor value] | None => [MeasureAnchor] end
  end.
Definition read_step (event : reading_event) (state : reading_state) :=
  match event with
  | BeginScroll => (ReadingState ReadHistory None, [])
  | AtAnchor value => (ReadingState ReadHistory (Some value), [])
  | Follow => (ReadingState FollowLatest None, [AlignLatest])
  | LayoutChanged => (state, reading_layout state)
  | JumpToMessage index => (ReadingState ReadHistory None, [LocateMessage index])
  | ReadingKey key editable => if reading_navigation_key key && negb editable
      then (ReadingState ReadHistory None, []) else (state, [])
  end.

Record allocation := Allocation {
  navigation_minimum : nat; content_minimum : nat; rail_width : nat; gap_width : nat
}.
Inductive presentation := Simultaneous | Sequential.
Definition simultaneous_minimum (requirements : allocation) :=
  navigation_minimum requirements + content_minimum requirements +
  rail_width requirements + gap_width requirements.
Definition allocate (viewport : nat) (requirements : allocation) : presentation :=
  if Nat.leb (simultaneous_minimum requirements) viewport then Simultaneous else Sequential.

Record publication := Publication {
  semantic_generation : N; document_generation : N; published_generation : N;
  namespace : string; sequence : N
}.
Definition fresh (state : publication) :=
  N.eqb (semantic_generation state) (published_generation state).
Definition admit_generation (generation : N) (state : publication) :=
  N.eqb (document_generation state) (semantic_generation state) && N.eqb generation (semantic_generation state).
Definition advance_semantics (state : publication) :=
  Publication (N.succ (semantic_generation state)) (document_generation state) (published_generation state)
    (namespace state) (sequence state).
Definition accept_document (generation : N) (state : publication) :=
  if N.eqb generation (semantic_generation state) then
    Publication (semantic_generation state) generation (published_generation state) (namespace state) (sequence state)
  else state.
Definition accept_publication (generation : N) (state : publication) :=
  if N.eqb generation (semantic_generation state) && N.eqb (document_generation state) (semantic_generation state) then
    Publication (semantic_generation state) (document_generation state) generation (namespace state) (sequence state)
  else state.
Definition refresh_needed (source_namespace : string) (source_sequence : N)
    (sources_fresh : bool) (state : publication) :=
  negb (String.eqb source_namespace (namespace state) &&
    (N.leb source_sequence (sequence state)) && sources_fresh).

(** A logical document may be presented simultaneously in independent physical
    views. IO observes candidates; this rule selects a target without changing
    the logical editor, task or source authority. *)
Record target_observation := TargetObservation {
  target_key : string; target_aliases : list string; target_view : string
}.
Definition resolve_target (requested preferred_view : string)
    (candidates : list target_observation) : option string :=
  match find (fun candidate => String.eqb requested (target_key candidate)) candidates with
  | Some candidate => Some (target_key candidate)
  | None =>
    let aliases := filter (fun candidate => existsb (String.eqb requested) (target_aliases candidate)) candidates in
    match find (fun candidate => String.eqb preferred_view (target_view candidate)) aliases with
    | Some candidate => Some (target_key candidate)
    | None => option_map target_key (hd_error aliases)
    end
  end.

(* DEFENSE: resizing can remove an activity's original trigger before it closes.
   Its return effect explicitly supplies another real target; ordinary focus has no fallback. *)
Definition resolve_focus_target requested fallback preferred_view candidates :=
  match resolve_target requested preferred_view candidates with
  | Some key => Some key
  | None => resolve_target fallback preferred_view candidates
  end.

Definition cycle (backward : bool) (current : string) (targets : list string) : option string :=
  let ordered := if backward then rev targets else targets in
  let fix after (xs : list string) :=
    match xs with
    | [] => None
    | key :: rest => if String.eqb current key then hd_error rest else after rest
    end in
  match after ordered with Some key => Some key | None => hd_error ordered end.

Inductive snapshot_origin := Authentication | ExistingSession.
Definition admit_snapshot (origin : snapshot_origin) (expected incoming : string)
    (incoming_sequence : N) (state : publication) :=
  String.eqb expected (namespace state) &&
  if String.eqb incoming (namespace state) then N.leb (sequence state) incoming_sequence
  else match origin with Authentication => true | ExistingSession => false end.
