From Stdlib Require Import String List Bool Ascii NArith.
From Selvedge.Foundation Require OptionList.
From Selvedge.Foundation Require Import Json Numbers Schema.
From Selvedge.Kernel Require Import Domain.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition image_byte_limit : N := 10485760.
Definition message_image_limit : nat := 4.
Definition detail_name (value : image_detail) := match value with
  | ImageAuto => "auto" | ImageLow => "low" | ImageHigh => "high" end.
Definition detail_kind := KEnum "auto" ["low";"high"].
Definition mime_kind := KEnum "image/png" ["image/jpeg";"image/gif";"image/webp"].
Definition mime_types := match mime_kind with KEnum first rest => first::rest | _ => [] end.
Fixpoint hex_digits (value : string) := match value with
  | EmptyString => true
  | String c rest => let n := N.of_nat (nat_of_ascii c) in
    (((48 <=? n) && (n <=? 57)) || ((97 <=? n) && (n <=? 102))) && hex_digits rest end.
Definition valid_identifier (value : string) := Nat.eqb (String.length value) 64 && hex_digits value.
Definition asset_schema := [Field "id" KText;Field "mime" mime_kind;Field "bytes" KNatural].
Definition reference_schema := [Field "id" KText;Field "mime" mime_kind;Field "bytes" KJson;
  OmittableField "name" KText;OmittableField "path" KText].
Definition text_part_schema := [Field "type" (KEnum "text" []);Field "text" KText].
Definition image_part_schema := [Field "type" (KEnum "image" []);Field "image" KJson;OmittableField "detail" detail_kind].
Definition image_json (value : image_asset) := JObject [("id",JString value.(image_id));
  ("mime",JString value.(image_mime));("bytes",JNumber (show_natural value.(image_bytes)))].
Definition content_part_json (part : content_part) := match part with
  | TextPart text => JObject [("type",JString "text");("text",JString text)]
  | ImagePart image => JObject [("type",JString "image");("image",image_json image);
      ("detail",JString (detail_name image.(image_detail_level)))] end.
Definition raw_bytes (value : json) := match value with
  | JString text | JNumber text => parse_natural text | _ => None end.
Definition asset_of_values id mime bytes :=
 if valid_identifier id && existsb (String.eqb mime) mime_types &&
   (0 <? bytes) && (bytes <=? image_byte_limit) then Some (ImageAsset id mime bytes ImageAuto) else None.
Definition parse_asset_fields (value : json) : option image_asset :=
 match string_field "id" value,string_field "mime" value,field "bytes" value with
 | Some id,Some mime,Some raw => match raw_bytes raw with
   | Some bytes => asset_of_values id mime bytes | None => None end
 | _,_,_ => None end.
Definition parse_asset value := match Schema.decode asset_schema value with
 | Some values => asset_of_values (head values) (proj1_sig (head (tail values))) (head (tail (tail values)))
 | None => None end.
Definition parse_image value := match Schema.decode reference_schema value with
 | Some values => match raw_bytes (head (tail (tail values))) with
   | Some bytes => asset_of_values (head values) (proj1_sig (head (tail values))) bytes | None => None end
 | None => None end.
Definition parse_content_part value :=
 match string_field "type" value with
 | Some "text" => option_map (fun values : Schema.fields text_part_schema => TextPart (head (tail values))) (Schema.decode text_part_schema value)
 | Some "image" => match Schema.decode image_part_schema value with
   | Some values => option_map (fun image =>
     let detail := match head (tail (tail values)) with
       | None => ImageAuto | Some selected =>
         if String.eqb (proj1_sig selected) "low" then ImageLow else
         if String.eqb (proj1_sig selected) "high" then ImageHigh else ImageAuto end in
     ImagePart (ImageAsset image.(image_id) image.(image_mime) image.(image_bytes) detail))
       (parse_asset (head (tail values)))
   | None => None end
 | _ => None end.
Definition traverse {A B : Type} (parse : A -> option B) (values : list A) : option (list B) :=
 OptionList.traverse parse values.
Definition image_count (parts : content) := List.length (filter (fun part => match part with ImagePart _ => true | _ => false end) parts).
(* DEFENSE: Both fork message arrays and message-plus-attachment requests can
   exceed the per-message image limit at their public JSON input boundaries. *)
Definition admit_content (parts : content) : option content :=
  if Nat.leb (image_count parts) message_image_limit then Some parts else None.
Definition parse_content (source : json) : option content :=
  match match source with
    | JNull => Some [] | JString text => Some [TextPart text]
    | JArray values => traverse parse_content_part values | _ => None end with
  | Some parts => admit_content parts | None => None end.
Definition parse_user_content (source : json) : option content :=
  let message := match field "message" source with Some value => value | None => JNull end in
  let images := match field "images" source with None | Some JNull => Some []
    | Some (JArray values) => traverse parse_image values | _ => None end in
  match parse_content message,images with
  | Some parts,Some images => admit_content (List.app parts (map ImagePart images))
  | _,_ => None end.
Definition valid_image_asset (source : json) := match parse_asset source with Some _ => true | None => false end.
Definition valid_image_part (source : json) := match parse_content_part source with Some (ImagePart _) => true | _ => false end.
Definition valid_reference (source : json) := match parse_image source with Some _ => true | None => false end.

Definition only_images (parts : content) :=
 filter (fun part => match part with ImagePart _ => true | _ => false end) parts.
Definition result_images (source : json) :=
 match field "content" source with
 | Some (JArray parts) => flat_map (fun part => match parse_content_part part with
   | Some (ImagePart image) => [ImagePart image] | _ => [] end) parts
 | _ => [] end.
