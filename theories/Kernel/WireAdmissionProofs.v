From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
From Selvedge.Kernel Require Import InputDecoder State.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Remote.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.

Theorem completion_rejects_non_root_configuration : forall execute value request admitted prepared configuration,
 G.admit (Remote.intent request) = Some admitted ->
 configuration <> JNull ->
 Remote.root_task_command (G.admitted_value admitted) = false ->
 Remote.complete_request execute true request
   (Schema.of_tuple (Remote.preparation_fields true) (prepared,(configuration,tt))) value =
 (negb (Remote.observation_command (G.admitted_value admitted)),false,
   reject "invalid_input" "Remote environment observations are limited to task creation" value).
Proof.
 intros execute value request admitted prepared configuration Admitted NonNull Root.
 unfold Remote.complete_request; rewrite Admitted; cbn beta iota zeta delta [Schema.head Schema.tail Schema.of_tuple].
 unfold Remote.execute_remote, Remote.configuration_allowed.
 destruct configuration; try (exfalso; apply NonNull; reflexivity);
   rewrite Root; reflexivity.
Qed.
