From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import NumbersProofs.
From Selvedge.Host Require Import Process ProcessProofs.
From Selvedge.Adapters Require Import Common HostProcess.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Local Lemma tail_roundtrip current : tail_of (tail_json current) = current.
Proof.
  destruct current as [retained total].
  cbv beta iota zeta delta -[parse_natural show_natural N.to_nat N.of_nat].
  rewrite !natural_print_parse, Nat2N.id; reflexivity.
Qed.

Definition tail_plan_keeps_latest_output {A} (plan : json) capacity current
  (previous added : list A) : Prop :=
  let suffix := skipn (List.length (previous ++ added) - capacity) (previous ++ added) in
  skipn (N.to_nat (num plan "old_drop")) previous ++
    skipn (N.to_nat (num plan "new_drop")) added = suffix /\
  tail_of (get plan "tail") = Tail (List.length suffix)
    (total current + N.of_nat (List.length added)).

Local Lemma append_plan_keeps_latest_output {A} capacity current (previous added : list A) :
  retained current = List.length previous ->
  tail_plan_keeps_latest_output (append_plan capacity current (List.length added))
    capacity current previous added.
Proof.
  intros Length. unfold tail_plan_keeps_latest_output.
  change (skipn (N.to_nat (nat_value (number (N.of_nat (drop_old capacity current (List.length added)))))) previous ++
      skipn (N.to_nat (nat_value (number (N.of_nat (drop_new capacity (List.length added)))))) added =
      skipn (List.length (previous ++ added) - capacity) (previous ++ added) /\
    tail_of (tail_json (append_tail capacity current (List.length added))) =
      Tail (List.length (skipn (List.length (previous ++ added) - capacity) (previous ++ added)))
        (total current + N.of_nat (List.length added))).
  unfold nat_value, natural, number, decimal.
  rewrite !natural_print_parse, !Nat2N.id, tail_roundtrip.
  split; [now apply append_tail_keeps_latest_output|].
  rewrite <- (append_tail_keeps_latest_output capacity current previous added Length).
  rewrite length_app, !length_skipn.
  rewrite <- Length, append_tail_matches_slice_lengths.
  reflexivity.
Qed.

Theorem output_append_keeps_latest_output {A} source capacity current combined
  (previous combined_previous added : list A) :
  get source "tail" = tail_json current ->
  get source "combined" = tail_json combined ->
  num source "capacity" = N.of_nat capacity ->
  num source "count" = N.of_nat (List.length added) ->
  retained current = List.length previous ->
  retained combined = List.length combined_previous ->
  let response := call "control.process.output_append" source in
  field "ok" response = Some (JBool true) /\
  tail_plan_keeps_latest_output (get (get response "value") "tail")
    capacity current previous added /\
  tail_plan_keeps_latest_output (get (get response "value") "combined")
    capacity combined combined_previous added.
Proof.
  intros Current Combined Capacity Count Previous CombinedPrevious.
  unfold call. rewrite Current, Combined, Capacity, Count, !tail_roundtrip, !Nat2N.id.
  split; [reflexivity|].
  split; apply append_plan_keeps_latest_output; assumption.
Qed.

Theorem process_state_roundtrip current : state_of (state_json current) = current.
Proof.
  destruct current as [phase input busy reason].
  destruct phase, reason as [[code message]|]; reflexivity.
Qed.

Local Lemma registry_entry_roundtrip entry : entry_of (entry_json entry) = entry.
Proof.
  destruct entry as [key mode reason].
  destruct mode, reason as [[code message]|]; reflexivity.
Qed.

Local Lemma registry_roundtrip current : registry_of (registry_json current) = current.
Proof.
  destruct current as [entries completed].
  change (Registry (map entry_of (map entry_json entries))
    (map text (map JString completed)) = Registry entries completed).
  rewrite !map_map.
  f_equal.
  - induction entries as [|entry rest IH]; cbn [map]; [reflexivity|].
    rewrite registry_entry_roundtrip, IH; reflexivity.
  - induction completed as [|key rest IH]; cbn [map]; [reflexivity|].
    rewrite IH; reflexivity.
Qed.

Theorem registry_completion_returns_its_retained_processes source current key :
  get source "registry" = registry_json current ->
  str source "key" = key ->
  let response := call "control.process.registry_complete" source in
  exists reply returned_registry,
    field "ok" response = Some (JBool true) /\
    field "value" response = Some reply /\
    field "registry" reply = Some returned_registry /\
    registry_of returned_registry = complete current key /\
    field "retired" reply = Some (JArray (map JString (retired current key))).
Proof.
  intros Hregistry Hkey.
  unfold call.
  rewrite Hregistry, registry_roundtrip, Hkey.
  exists (JObject [("registry",registry_json (complete current key));
      ("retired",JArray (map JString (retired current key)))]),
    (registry_json (complete current key)).
  repeat split; try reflexivity.
  apply registry_roundtrip.
Qed.
