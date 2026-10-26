From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import InputDecoder State.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Remote.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.

Theorem completion_rejects_unadmitted_remote_request : forall execute source value (prepared : bool),
 string_field "kind" source = Some (if prepared then "remote_command" else "remote_probe") ->
 Remote.parse_request prepared source = None ->
 Remote.completion execute source value =
 Some (false,false,reject "invalid_input" "Malformed remote request" value).
Proof.
 intros execute source value prepared Kind Parsed.
 unfold Remote.completion.
 rewrite Kind.
 destruct prepared; simpl in *; rewrite Parsed; reflexivity.
Qed.

Theorem completion_rejects_non_root_configuration : forall execute source value request command prepared configuration,
 string_field "kind" source = Some "remote_command" ->
 Remote.parse_request true source = Some (request,Schema.of_tuple (Remote.preparation_fields true) (prepared,(configuration,tt))) ->
 G.decode (Remote.intent request) = Some command ->
 configuration <> JNull ->
 Remote.root_task_command command = false ->
 Remote.completion execute source value =
 Some (negb (Remote.observation_command command),false,
   reject "invalid_input" "Remote environment observations are limited to task creation" value).
Proof.
 intros execute source value request command prepared configuration Kind Parsed Decoded NonNull Root.
 rewrite <- G.admit_projects_decode in Decoded.
 destruct (G.admit (Remote.intent request)) as [admitted|] eqn:Admitted; [|discriminate].
 cbn in Decoded; inversion Decoded; subst command.
 unfold Remote.completion.
 rewrite Kind.
 cbn.
 rewrite Parsed, Admitted.
 unfold Remote.execute_remote, Remote.configuration_allowed.
 destruct configuration; try (exfalso; apply NonNull; reflexivity);
   rewrite Root; reflexivity.
Qed.
