From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import InputDecoder State.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Remote.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.

Theorem decode_requires_variant_field_admission : forall fields kind output,
 lookup "kind" fields = Some (JString kind) ->
 InputDecoder.decode (JObject fields) = Some output ->
 InputDecoder.variant_fields_valid kind (JObject fields) = true.
Proof.
 intros fields kind output Kind Decoded.
 unfold InputDecoder.decode in Decoded.
 destruct (Schema.unique_names (map fst fields)) eqn:Unique; try discriminate.
 rewrite Kind in Decoded.
 destruct (InputDecoder.variant_fields_valid kind (JObject fields)) eqn:Valid; try discriminate.
 reflexivity.
Qed.

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

Theorem completion_rejects_non_root_configuration : forall execute source value request command configuration,
 string_field "kind" source = Some "remote_command" ->
 Remote.parse_request true source = Some request ->
 G.decode (Remote.intent request) = Some command ->
 field "configuration" source = Some configuration ->
 configuration <> JNull ->
 Remote.root_task_command command = false ->
 Remote.completion execute source value =
 Some (negb (Remote.observation_command command),false,
   reject "invalid_input" "Remote environment observations are limited to task creation" value).
Proof.
 intros execute source value request command configuration Kind Parsed Decoded Config NonNull Root.
 rewrite <- G.admit_projects_decode in Decoded.
 destruct (G.admit (Remote.intent request)) as [admitted|] eqn:Admitted; [|discriminate].
 cbn in Decoded; inversion Decoded; subst command.
 unfold Remote.completion.
 rewrite Kind.
 cbn.
 rewrite Parsed, Admitted.
 unfold Remote.execute_remote, Remote.configuration_allowed.
 rewrite Config.
 destruct configuration; try (exfalso; apply NonNull; reflexivity);
   rewrite Root; reflexivity.
Qed.
