From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Utf8.
From Selvedge.Kernel Require Import Images.
From Selvedge.Adapters Require Import Common Observation.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Definition filename_character (code : N) := (31 <? code) &&
  negb (N.eqb code 127 || N.eqb code 47 || N.eqb code 92).
Definition filename (value : json) :=
  let name := text value in
  let valid := match Utf8.decode name with Some scalars => forallb filename_character scalars | None => false end in
  if is_text value && negb (String.eqb name "") && (N.of_nat (String.length name) <=? 256) && valid &&
    negb (String.eqb name "." || String.eqb name "..")
  then success value else type_error "An attachment needs a plain filename of at most 256 UTF-8 bytes".
Definition identifier (value : json) :=
  if is_text value && Images.valid_identifier (text value) then success value else type_error "Invalid attachment identifier".
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
  success (JObject [("observe",JBool observe);("attachments",JBool
    (observe && negb (is_null (get command "attachments")) && existsb (String.eqb (str command "op")) ["create_card";"update_card"]))]).
Fixpoint reference_shapes (seen : list string) (references : list json) :=
  match references with [] => true | reference::rest =>
    plain_fields_only ["id";"name";"mime";"path";"bytes"] reference && is_text (get reference "id") &&
    negb (existsb (String.eqb (str reference "id")) seen) && reference_shapes (str reference "id"::seen) rest end.
Definition board_references (source : json) :=
  let references := get (get source "command") "attachments" in
  if is_array references && (N.of_nat (List.length (items references)) <=? 4) then
    if reference_shapes [] (items references) then success references else type_error "Attachments must be distinct uploaded file references"
  else range_error "A card accepts at most four attachments".
Fixpoint reference_match (keys : list string) (value attachment : json) :=
  match keys with [] => success attachment | key::rest =>
    if negb (has value key) || equal (get value key) (get attachment key)
    then reference_match rest value attachment
    else type_error ("Attachment " ++ key ++ " does not match its stored observation") end.
Inductive image_collection := Collected (values : list json) | InvalidImages (reason : string).
Definition join (left right : image_collection) := match left,right with
  | InvalidImages reason,_ | _,InvalidImages reason => InvalidImages reason
  | Collected xs,Collected ys => Collected (List.app xs ys) end.
Definition checked (accepted : bool) (values : list json) (error : string) :=
  if accepted then Collected values else InvalidImages error.
Definition image_part (part : json) :=
  if String.eqb (str part "type") "image" then checked (Images.valid_image_part part) [get part "image"] "Invalid image content part"
  else checked (match Images.parse_content_part part with Some _ => true | None => false end) [] "Invalid message content part".
Fixpoint image_parts (values : list json) := match values with [] => Collected [] | value::rest => join (image_part value) (image_parts rest) end.
Definition message_parts (value : json) := match value with
  | JArray values => image_parts values
  | JString _ | JNull => Collected []
  | _ => InvalidImages "Invalid message content" end.
Fixpoint reference_images (values : list json) :=
  match values with [] => Collected [] | value::rest =>
    join (checked (Images.valid_reference value) [value] "Invalid image attachment reference") (reference_images rest) end.
Definition image_references (value : json) := match value with
  | JNull => Collected [] | JArray values => reference_images values | _ => InvalidImages "Images must be an array" end.
Definition limited (collection : image_collection) := match collection with
  | InvalidImages reason => InvalidImages reason
  | Collected values => checked (Nat.leb (List.length values) Images.message_image_limit) values "A user message supports at most four images" end.
Fixpoint messages_images (messages : list json) := match messages with
  | [] => Collected [] | message::rest => join (limited (message_parts message)) (messages_images rest) end.
Definition message_images (source : json) :=
  let command := get source "command" in
  match join (limited (join (message_parts (get command "message")) (image_references (get command "images"))))
    (messages_images (items (get command "messages"))) with
  | Collected images => success (JArray images)
  | InvalidImages reason => type_error reason end.
Definition message_image_match (source : json) :=
  let value := get source "value" in let stored := get source "attachment" in
  let bytes := fun value => match get value "bytes" with JString value | JNumber value => value | _ => "" end in
  if Images.valid_reference value && equal (get value "id") (get stored "id") &&
    equal (get value "mime") (get stored "mime") && String.eqb (bytes value) (bytes stored) &&
    forallb (fun key => negb (has value key) || equal (get value key) (get stored key)) ["name";"path"]
  then success value else type_error "Image reference does not match the stored attachment".
Definition attachment_budget (source : json) :=
  if bound (get source "size") 0 Images.image_byte_limit then success JNull else range_error "Each board attachment is limited to 10 MiB".
Definition artifact_limit (source : json) :=
  if bound (get (get source "limits") "artifact_bytes") 1 9007199254740991 then success JNull else type_error "Invalid artifact byte limit".
Definition board_clock (source : json) :=
  if bound (get source "seconds") 0 4294967295 then success (JString (diagnostic (get source "seconds")))
  else range_error "The clock is outside the native board timestamp range".
