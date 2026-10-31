From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8 Schema OptionList.
From Selvedge.Kernel Require Import Images.
From Selvedge.Features Require BoardParameters.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.

Definition filename_character (code : N) := (31 <? code) &&
  negb (N.eqb code 127 || N.eqb code 47 || N.eqb code 92).
Definition filename (value : json) :=
  let name := text value in
  let valid := match Utf8.decode name with Some scalars => forallb filename_character scalars | None => false end in
  if is_text value && negb (String.eqb name "") && (N.of_nat (String.length name) <=? 256) && valid &&
    negb (String.eqb name "." || String.eqb name "..")
  then success value else type_error "An attachment needs a plain filename of at most 256 UTF-8 bytes".
Definition identifier (value : json) :=
  match D.decode ContentDeclarations.identifier_declaration value with
  | Some id => success (D.encode ContentDeclarations.identifier_declaration id)
  | None => type_error "Invalid attachment identifier" end.
Definition attachment (source : json) :=
  let record := get source "record" in
  if is_object record && equal (get record "version") (number 1) && equal (get record "id") (get source "id") &&
    equal (get record "bytes") (get source "bytes") && equal (get record "mime") (get source "mime") &&
    equal (get source "hash") (get source "id") then
    let name := filename (get record "name") in
    if boolean_field name "ok" then success (JObject [("id",get source "id");("name",get name "value");
      ("mime",get record "mime");("path",get source "path");("bytes",JString (decimal (num source "bytes")))])
    else name
  else err "Attachment content or metadata failed its integrity check".
Definition byte_eqb (bytes : list json) (index : nat) (expected : N) :=
  match nth_error bytes index with
  | Some value => match natural value with Some value => N.eqb value expected | None => false end
  | None => false
  end.
Definition signature_matches (bytes : list json) (offset : nat) (expected : list N) :=
  forallb (fun indexed => byte_eqb bytes (offset + fst indexed) (snd indexed))
    (combine (seq 0 (List.length expected)) expected).
Definition attachment_media_type (source : json) :=
  let bytes := items (get source "prefix") in
  if signature_matches bytes 0 [137;80;78;71;13;10;26;10] then success (JString "image/png")
  else if signature_matches bytes 0 [255;216;255] then success (JString "image/jpeg")
  else if signature_matches bytes 0 [71;73;70;56;55;97] || signature_matches bytes 0 [71;73;70;56;57;97]
  then success (JString "image/gif")
  else if signature_matches bytes 0 [82;73;70;70] && signature_matches bytes 8 [87;69;66;80]
  then success (JString "image/webp")
  (* DEFENSE: Uploaded SVG/HTML and caller-supplied MIME types must not authorize active inline content. *)
  else success (JString "application/octet-stream").
Definition board_command (source : json) :=
  let command := get source "command" in
  let observe := is_object command && existsb (String.eqb (str command "op"))
    ["create_card";"update_card";"move_card";"archive_card";"restore_card";"delete_card";"run_card";"link_card";"regenerate_card_title";"pin_card"] in
  (* DEFENSE: Explicit malformed attachment input must not bypass reference admission. *)
  success (JObject [("observe",JBool observe);("attachments",JBool
    (observe && has command "attachments" && existsb (String.eqb (str command "op")) ["create_card";"update_card"]))]).
Definition board_references (source : json) :=
  let references := get (get source "command") "attachments" in
  match ArgumentDeclaration.decode (BoardParameters.attachments_declaration false) references with
  | Some admitted =>
    let identities := map (fun value => proj1_sig (fst (proj1_sig value))) (proj1_sig admitted) in
    if Schema.unique_names identities
    then success (ArgumentDeclaration.encode (BoardParameters.attachments_declaration false) admitted)
    (* DEFENSE: A raw board command can repeat one uploaded file identity. *)
    else type_error "Attachments must be distinct uploaded file references"
  (* DEFENSE: Raw attachment references can exceed the four-file limit or contain malformed metadata. *)
  | None => type_error "A card accepts at most four well-formed uploaded file references" end.
Fixpoint reference_match (keys : list string) (value attachment : json) :=
  match keys with [] => success attachment | key::rest =>
    if negb (has value key) || equal (get value key) (get attachment key)
    then reference_match rest value attachment
    else type_error ("Attachment " ++ key ++ " does not match its stored observation") end.
Definition decode_optional declaration source : option (option (D.denote declaration)) :=
  match source with JNull => Some None | _ => option_map (@Some _) (D.decode declaration source) end.
Definition content_images (parts : Domain.content) := flat_map (fun part => match part with
  | Domain.ImagePart image => [Images.image_json image] | _ => [] end) parts.
Definition message_images_only source := option_map content_images (Images.parse_content source).
Definition message_images (source : json) :=
  let command := get source "command" in
  match decode_optional ContentDeclarations.content_declaration (get command "message"),
    decode_optional ContentDeclarations.images_declaration (get command "images"),
    OptionList.traverse message_images_only (items (get command "messages")) with
  | Some message,Some references,Some batches =>
    match Images.admit_user_content message references with
    | Some admitted =>
      let '(message,references) := proj1_sig admitted in
      let content := match message with Some value => content_images (Images.content_of_values value) | None => [] end in
      let attachments := match references with
        | Some values => map (D.encode ContentDeclarations.reference_declaration) values | None => [] end in
      success (JArray (content ++ attachments ++ List.concat batches))
    (* DEFENSE: Inline images and uploaded references share the public per-message image limit. *)
    | None => type_error "A user message supports at most four images" end
  (* DEFENSE: A raw command can contain malformed image references or oversized message image batches. *)
  | _,_,_ => type_error "Each message requires well-formed content and at most four images" end.
Definition message_image_match (source : json) :=
  let stored := get source "attachment" in
  let invalid := type_error "Image reference does not match the stored attachment" in
  match D.decode ContentDeclarations.reference_declaration (get source "value") with
  | Some admitted => let '(id,(mime,(bytes,(name,(path,_))))) := proj1_sig admitted in
    let matches key value := match value with
      | Some value => equal (JString (proj1_sig value)) (get stored key) | None => true end in
    if equal (JString (proj1_sig id)) (get stored "id") &&
      equal (JString (proj1_sig mime)) (get stored "mime") &&
      String.eqb (decimal (Images.reference_byte_count bytes)) (diagnostic (get stored "bytes")) &&
      matches "name" name && matches "path" path
    then success (D.encode ContentDeclarations.reference_declaration admitted) else invalid
  | None => invalid end.
Definition attachment_budget (source : json) :=
  if bound (get source "size") 0 Images.image_byte_limit then success JNull else range_error "Each board attachment is limited to 10 MiB".
Definition artifact_limit (source : json) :=
  if bound (get (get source "limits") "artifact_bytes") 1 9007199254740991 then success JNull else type_error "Invalid artifact byte limit".
Definition board_clock (source : json) :=
  if bound (get source "seconds") 0 4294967295 then success (JString (diagnostic (get source "seconds")))
  else range_error "The clock is outside the native board timestamp range".
