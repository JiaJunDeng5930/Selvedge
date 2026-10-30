From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema ArgumentDeclaration.
From Selvedge.Kernel Require Import Domain ContentDeclarations.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.

Definition image_byte_limit := ContentDeclarations.image_byte_limit.
Definition message_image_limit := ContentDeclarations.message_image_limit.
Definition detail_kind := ContentDeclarations.detail_kind.
Definition mime_kind := ContentDeclarations.mime_kind.
Definition mime_types := match mime_kind with KEnum first rest => first::rest | _ => [] end.
Definition valid_identifier (value : string) :=
 D.present (D.decode identifier_declaration (JString value)).
Definition detail_name (value : image_detail) := match value with
 | ImageAuto => "auto" | ImageLow => "low" | ImageHigh => "high" end.
Definition image_json (value : image_asset) := JObject [("id",JString value.(image_id));
 ("mime",JString value.(image_mime));("bytes",JNumber (show_natural value.(image_bytes)))].
Definition content_part_json (part : content_part) := match part with
 | TextPart text => JObject [("type",JString "text");("text",JString text)]
 | ImagePart image => JObject [("type",JString "image");("image",image_json image);
     ("detail",JString (detail_name image.(image_detail_level)))] end.

(** These interpreters consume declaration values directly. Shape, identity,
    MIME membership and byte bounds have already been admitted together. *)
Definition asset_of_values (values : D.denote asset_declaration) : image_asset :=
 let '(id,(mime,(bytes,_))) := proj1_sig values in
 ImageAsset (proj1_sig id) (proj1_sig mime) (proj1_sig bytes) ImageAuto.
Definition reference_byte_count (value : D.denote reference_bytes) : N :=
 match value with inl number | inr (inl number) => proj1_sig number
 | inr (inr impossible) => match impossible with end end.
Definition reference_of_values (values : D.denote reference_declaration) : image_asset :=
 let '(id,(mime,(bytes,_))) := proj1_sig values in
 ImageAsset (proj1_sig id) (proj1_sig mime) (reference_byte_count bytes) ImageAuto.
Definition detail_of_values (value : option (Schema.denote detail_kind)) :=
 match value with
 | Some selected => if String.eqb (proj1_sig selected) "low" then ImageLow else
     if String.eqb (proj1_sig selected) "high" then ImageHigh else ImageAuto
 | None => ImageAuto end.
Definition part_of_values (value : D.denote part_declaration) : content_part :=
 match value with
 | inl fields => let '(_,(text,_)) := proj1_sig fields in TextPart (proj1_sig text)
 | inr (inl fields) => let '(_,(asset,(detail,_))) := proj1_sig fields in
   let image := asset_of_values asset in
   ImagePart (ImageAsset image.(image_id) image.(image_mime) image.(image_bytes) (detail_of_values detail))
 | inr (inr impossible) => match impossible with end end.
Definition content_of_values (value : D.denote content_declaration) : content :=
 match value with inl text => [TextPart (proj1_sig text)]
 | inr (inl parts) => map part_of_values parts
 | inr (inr impossible) => match impossible with end end.
Definition image_count (parts : content) :=
 List.length (filter (fun part => match part with ImagePart _ => true | _ => false end) parts).
Definition bounded_content := D.checked (fun parts => Nat.leb (image_count parts) message_image_limit).
(* DEFENSE: Message parts and separately uploaded attachments share the public
   per-message limit; their combined image count can exceed four. *)
Definition admit_content : content -> option bounded_content :=
 D.admit (fun parts => Nat.leb (image_count parts) message_image_limit).
Definition message_content (value : D.denote content_declaration) :=
 option_map (@proj1_sig _ _) (admit_content (content_of_values value)).
Definition user_content (message : option (D.denote content_declaration))
 (images : option (D.denote images_declaration)) :=
 option_map (@proj1_sig _ _) (admit_content
   (List.app (match message with Some value => content_of_values value | None => [] end)
    (match images with Some values => map (fun value => ImagePart (reference_of_values value)) values
     | None => [] end))).

(** Raw entry points are for external attachment receipts, tool results and
    serialized content. Commands use the admitted interpreters above. *)
Definition parse_asset_fields value :=
 option_map reference_of_values (D.decode reference_declaration value).
Definition parse_content_part value := option_map part_of_values (D.decode part_declaration value).
Definition parse_content (source : json) : option content := match source with
 | JNull => Some [] | _ => match D.decode content_declaration source with
   | Some value => message_content value | None => None end end.
Definition valid_image_asset source := D.present (D.decode asset_declaration source).
Definition valid_image_part source := D.present (D.decode image_part_declaration source).
Definition valid_reference source := D.present (D.decode reference_declaration source).
Definition only_images (parts : content) :=
 filter (fun part => match part with ImagePart _ => true | _ => false end) parts.
Definition result_images (source : json) :=
 match field "content" source with
 | Some (JArray parts) => flat_map (fun part => match parse_content_part part with
   | Some (ImagePart image) => [ImagePart image] | _ => [] end) parts
 | _ => [] end.
