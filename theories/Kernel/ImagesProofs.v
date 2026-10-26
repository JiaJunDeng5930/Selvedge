From Stdlib Require Import String List Bool NArith Arith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Domain Images.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Lemma admitted_content_has_bounded_images : forall parts accepted,
  admit_content parts = Some accepted ->
  (image_count accepted <= message_image_limit)%nat.
Proof.
 intros parts accepted admitted. unfold admit_content in admitted.
 destruct (Nat.leb (image_count parts) message_image_limit) eqn:bounded; [|discriminate].
 inversion admitted; subst. now apply Nat.leb_le.
Qed.

Theorem parsed_content_has_bounded_images : forall source content,
  parse_content source = Some content ->
  (image_count content <= message_image_limit)%nat.
Proof.
 intros source content accepted. unfold parse_content in accepted.
 destruct source; try discriminate;
   try (eapply admitted_content_has_bounded_images; exact accepted).
 destruct (traverse parse_content_part values); [|discriminate].
 eapply admitted_content_has_bounded_images; exact accepted.
Qed.

Theorem valid_content_array_is_preserved : forall values content,
  traverse parse_content_part values = Some content ->
  (image_count content <= message_image_limit)%nat ->
  parse_content (JArray values) = Some content.
Proof.
 intros values content parsed bounded. unfold parse_content. rewrite parsed.
 unfold admit_content. apply Nat.leb_le in bounded. now rewrite bounded.
Qed.

Theorem parsed_user_content_has_bounded_images : forall source content,
  parse_user_content source = Some content ->
  (image_count content <= message_image_limit)%nat.
Proof.
 intros source content accepted. unfold parse_user_content in accepted.
 repeat match type of accepted with
 | context [match ?parsed with Some _ => _ | None => _ end] =>
     destruct parsed; try discriminate
 end.
 eapply admitted_content_has_bounded_images; exact accepted.
Qed.

Definition valid_asset (image : image_asset) : Prop :=
  valid_identifier image.(image_id) = true /\ In image.(image_mime) mime_types /\
  0 < image.(image_bytes) <= image_byte_limit.
Lemma admitted_asset_values_are_valid : forall id mime bytes image,
 asset_of_values id mime bytes = Some image -> valid_asset image.
Proof.
 intros id mime bytes image Accepted; unfold asset_of_values in Accepted.
 destruct (valid_identifier id && existsb (String.eqb mime) mime_types && (0 <? bytes) && (bytes <=? image_byte_limit)) eqn:Valid; [|discriminate].
 inversion Accepted; subst image; unfold valid_asset; cbn.
 repeat rewrite andb_true_iff in Valid.
 destruct Valid as [[[Identity Mime] Lower] Upper].
 apply N.ltb_lt in Lower; apply N.leb_le in Upper.
 apply existsb_exists in Mime as [value [Member Same]].
 apply String.eqb_eq in Same; subst; auto.
Qed.
Lemma admitted_asset_fields_are_valid : forall source image,
 parse_asset_fields source = Some image -> valid_asset image.
Proof.
 intros source image Parsed; unfold parse_asset_fields in Parsed.
 destruct (string_field "id" source), (string_field "mime" source), (field "bytes" source); try discriminate.
 destruct (raw_bytes j); [|discriminate]. eapply admitted_asset_values_are_valid; exact Parsed.
Qed.
Theorem decoded_image_asset_is_valid : forall source image,
 parse_asset source = Some image -> valid_asset image.
Proof.
 intros source image Parsed; unfold parse_asset in Parsed.
 destruct (Schema.decode asset_schema source); [|discriminate].
 eapply admitted_asset_values_are_valid; exact Parsed.
Qed.
Theorem decoded_image_reference_is_valid : forall source image,
 parse_image source = Some image -> valid_asset image.
Proof.
 intros source image Parsed; unfold parse_image in Parsed.
 destruct (Schema.decode reference_schema source) as [values|]; [|discriminate].
 destruct (raw_bytes (head (tail (tail values)))); [|discriminate].
 eapply admitted_asset_values_are_valid; exact Parsed.
Qed.
Theorem image_reference_does_not_hide_detail : forall source image,
 parse_image source = Some image -> image_detail_level image = ImageAuto.
Proof.
 intros source image Parsed; unfold parse_image in Parsed.
 destruct (Schema.decode reference_schema source) as [values|]; [|discriminate].
 destruct (raw_bytes (head (tail (tail values)))); [|discriminate].
 unfold asset_of_values in Parsed.
 match type of Parsed with context[if ?valid then _ else _] => destruct valid end;
   inversion Parsed; reflexivity.
Qed.
