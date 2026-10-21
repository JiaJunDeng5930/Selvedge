From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Domain Images.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition valid_asset (image : image_asset) : Prop :=
  valid_identifier image.(image_id) = true /\ In image.(image_mime) mime_types /\
  0 < image.(image_bytes) <= image_byte_limit.
Lemma admitted_asset_fields_are_valid : forall source image,
  parse_asset_fields source = Some image -> valid_asset image.
Proof.
  intros source image H. unfold parse_asset_fields in H.
  destruct (string_field "id" source) as [id|];[|discriminate].
  destruct (string_field "mime" source) as [mime|];[|discriminate].
  destruct (field "bytes" source) as [raw|];[|discriminate].
  destruct (raw_bytes raw) as [bytes|];[|discriminate].
  destruct (valid_identifier id && existsb (String.eqb mime) mime_types && (0 <? bytes) && (bytes <=? image_byte_limit)) eqn:accepted;[|discriminate].
  inversion H;subst image. unfold valid_asset;cbn.
  repeat rewrite andb_true_iff in accepted.
  destruct accepted as [[[identity mime_member] lower] upper].
  apply N.ltb_lt in lower. apply N.leb_le in upper.
  apply existsb_exists in mime_member as [value [member same]].
  apply String.eqb_eq in same;subst value. auto.
Qed.
Theorem decoded_image_asset_is_valid : forall source image,
  parse_asset source = Some image -> valid_asset image.
Proof.
  intros source image H. unfold parse_asset in H.
  destruct (Schema.decode asset_schema source);[|discriminate].
  apply admitted_asset_fields_are_valid in H;exact H.
Qed.
Theorem decoded_image_reference_is_valid : forall source image,
  parse_image source = Some image -> valid_asset image.
Proof.
  intros source image H. unfold parse_image in H.
  destruct (Schema.decode reference_schema source);[|discriminate].
  match type of H with context[if ?accepted then _ else _] => destruct accepted end;[|discriminate].
  apply admitted_asset_fields_are_valid in H;exact H.
Qed.
Theorem image_reference_does_not_hide_detail : forall source image,
  parse_image source = Some image -> image_detail_level image = ImageAuto.
Proof.
  intros source image H. unfold parse_image in H.
  destruct (Schema.decode reference_schema source);[|discriminate].
  match type of H with context[if ?accepted then _ else _] => destruct accepted end;[|discriminate].
  unfold parse_asset_fields in H.
  destruct (string_field "id" source), (string_field "mime" source), (field "bytes" source);try discriminate.
  destruct (raw_bytes j);try discriminate.
  match type of H with context[if ?accepted then _ else _] => destruct accepted end;inversion H;reflexivity.
Qed.
