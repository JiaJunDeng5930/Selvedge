From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Interaction Require Import Codec Identity.
From Selvedge.Programming Require Import Resource.
From Selvedge.Browser.Session Require Import Services ObjectActions.
From Selvedge.Interaction Require CommandAssessment.
From Selvedge.Browser.Session Require State.
Open Scope string_scope.

Theorem available_native_has_a_connected_idle_command state value accepted :
 command value = Some accepted -> availability state value = Available ->
 Services.connected(State.service_state state)=true /\ State.pending_command accepted state=false.
Proof.
 intros Command AvailableNow. unfold availability in AvailableNow. rewrite Command in AvailableNow.
 destruct (State.pending_command accepted state); [discriminate|].
 destruct (Services.connected(State.service_state state)); [auto|discriminate].
Qed.
