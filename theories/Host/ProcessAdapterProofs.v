From Stdlib Require Import String List Bool.
From Selvedge.Host Require Import Process.
From Selvedge.Adapters Require Import Common HostProcess.
Import ListNotations.
Open Scope string_scope.

Theorem process_state_roundtrip current : state_of (state_json current) = current.
Proof.
  destruct current as [phase input busy drained reason].
  destruct phase, reason as [[code message]|]; reflexivity.
Qed.
