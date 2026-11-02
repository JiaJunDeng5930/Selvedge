From Stdlib Require Import String List Bool.
From Selvedge.Host Require Import Process.
From Selvedge.Adapters Require Import Common HostProcess.
Import ListNotations.
Open Scope string_scope.

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
