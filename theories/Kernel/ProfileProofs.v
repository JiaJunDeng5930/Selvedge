From Selvedge.Kernel Require Import Domain Codec.

Theorem parsed_profile_retains_configuration : forall source parsed,
 Domain.parse_profile source = Some parsed ->
 Domain.parse_profile_configuration source = Some (configured_value (profile_configuration_source parsed)) /\
 profile_reasoning parsed = profile_default parsed.
Proof.
 intros source parsed.
 assert (Retains : forall decoded Binding,
   parse_profile_decoded source decoded Binding = Some parsed ->
   Domain.parse_profile_configuration source = Some (configured_value (profile_configuration_source parsed)) /\
   profile_reasoning parsed = profile_default parsed).
 { intros [configuration|] Binding Accepted; [|discriminate].
   inversion Accepted; subst; split; [exact Binding|reflexivity]. }
 unfold Domain.parse_profile; apply Retains.
Qed.
Theorem configured_effort_is_profile_default : forall current configured,
 Codec.parse_profile (profile_metadata current) = Some configured ->
 profile_reasoning configured = profile_default current.
Proof.
 intros current configured Parsed.
 apply parsed_profile_retains_configuration in Parsed as [Parsed Effort].
 pose proof (configured_binding (profile_configuration_source current)) as Bound.
 change (Domain.parse_profile_configuration (profile_metadata current) =
   Some (configured_value (profile_configuration_source current))) in Bound.
 rewrite Bound in Parsed; injection Parsed as Configuration.
 rewrite Effort; unfold profile_default; now rewrite Configuration.
Qed.
