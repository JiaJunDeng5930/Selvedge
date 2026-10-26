From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json JsonProofs.
From Selvedge.Kernel Require Import Domain Codec.
Import ListNotations.

Theorem metadata_determines_admitted_profile_configuration : forall left right,
 profile_metadata left = profile_metadata right ->
 configured_value (profile_configuration_source left) = configured_value (profile_configuration_source right).
Proof.
 intros [[left_source left_value Left] left_reason] [[right_source right_value Right] right_reason] Same.
 cbn [profile_metadata profile_configuration_source configured_source] in Same; subst right_source.
 cbn [profile_configuration_source configured_value]. rewrite Left in Right; congruence.
Qed.

(** These were the independent observations compared before admission bound the
    immutable configuration to its source. Their conjunction has exactly the
    same meaning as comparing the retained source and the mutable effort. *)
Theorem admitted_profile_comparison_preserves_every_original_observation : forall left right,
 (Json.equal (Codec.model_json left) (Codec.model_json right) &&
  Json.equal (Codec.profile_json left) (Codec.profile_json right) &&
  Json.equal (JArray (map JString (profile_reasoning_options left)))
    (JArray (map JString (profile_reasoning_options right))) &&
  String.eqb (profile_reasoning left) (profile_reasoning right)) = Domain.same_profile left right.
Proof.
 intros left right.
 destruct (Domain.same_profile left right) eqn:Same.
 - unfold Domain.same_profile in Same; apply andb_true_iff in Same as [Metadata Effort].
   apply JsonProofs.equal_reflects_equality in Metadata; apply String.eqb_eq in Effort.
   pose proof (metadata_determines_admitted_profile_configuration _ _ Metadata) as Configuration.
   unfold Codec.profile_json, Codec.model_json, profile_key, profile_provider, profile_model,
     profile_reasoning_options, profile_policy.
   rewrite Configuration, Metadata, Effort, !JsonProofs.equal_is_reflexive, String.eqb_refl; reflexivity.
 - apply Bool.not_true_is_false; intro Different.
   repeat rewrite andb_true_iff in Different.
   unfold Domain.same_profile in Same.
   destruct Different as [[[_ Metadata] _] Effort].
   unfold Codec.profile_json in Metadata. rewrite Metadata, Effort in Same; discriminate.
Qed.

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
