From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import NumbersProofs.
From Selvedge.Host Require Import Dispatch.
From Selvedge.Adapters Require Import Common HostDispatch.
Import ListNotations.
Open Scope string_scope.

Local Lemma running_roundtrip entry : running_of (running_json entry) = entry.
Proof.
  destruct entry as [generation key task cancellable provider reduced].
  destruct task, provider;
    cbv beta iota zeta delta -[parse_natural show_natural];
    rewrite !natural_print_parse; reflexivity.
Qed.

Local Lemma state_roundtrip current : state_of (state_json current) = current.
Proof.
  destruct current as [retired next active].
  change (State retired
    (match parse_natural (show_natural next) with Some value => value | None => 0 end)
    (map running_of (map running_json active)) = State retired next active).
  rewrite natural_print_parse, map_map.
  f_equal.
  induction active as [|entry rest IH]; cbn [map]; [reflexivity|].
  rewrite running_roundtrip, IH; reflexivity.
Qed.

Theorem dispatch_step_returns_its_next_state source current observation :
  get source "state" = state_json current ->
  observation_of (get source "observation") = Some observation ->
  let response := call "control.dispatch.step" source in
  exists reply returned_state,
    field "ok" response = Some (JBool true) /\
    field "value" response = Some reply /\
    field "state" reply = Some returned_state /\
    state_of returned_state = fst (step current observation) /\
    field "effects" reply = Some (JArray (map primitive_json (snd (step current observation)))).
Proof.
  intros Hstate Hobservation.
  unfold call.
  rewrite Hstate, state_roundtrip, Hobservation.
  destruct (step current observation) as [next effects].
  exists (JObject [("state",state_json next);("effects",JArray (map primitive_json effects))]),
    (state_json next).
  repeat split; try reflexivity.
  apply state_roundtrip.
Qed.
