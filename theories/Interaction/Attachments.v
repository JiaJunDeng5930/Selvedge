From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers.
From Selvedge.Kernel Require Import Images.
From Selvedge.Features Require Domain Observation.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.

(** Uploaded and stored assets share the board/domain attachment identity. *)
Definition attachment := Selvedge.Features.Domain.attachment.
Definition Attachment := Selvedge.Features.Domain.Attachment.
Definition asset_id := Selvedge.Features.Domain.attachment_id.
Definition asset_name := Selvedge.Features.Domain.attachment_name.
Definition asset_mime := Selvedge.Features.Domain.attachment_mime.
Definition asset_path := Selvedge.Features.Domain.attachment_path.
Definition asset_bytes := Selvedge.Features.Domain.attachment_bytes.
Definition encode_attachment := Selvedge.Features.Observation.attachment_json.
Definition decode_attachment j :=
  id <- string_field "id" j ;; name <- string_field "name" j ;; mime <- string_field "mime" j ;;
  path <- string_field "path" j ;;
  bytes <- (match field "bytes" j with Some(JString s) | Some(JNumber s) => parse_natural s | _ => None end) ;;
  if String.eqb id "" then None else Some(Attachment id name mime path bytes).
Definition passive_mime mime := existsb (String.eqb mime) Images.mime_types.
Definition passive_image a := passive_mime(asset_mime a).
Record selected_file := SelectedFile { file_handle:string; file_name:string; file_mime:string; file_bytes:N }.
Definition encode_file f := JObject [("handle",JString(file_handle f));("name",JString(file_name f));("mime",JString(file_mime f));("bytes",number(file_bytes f))].
Definition decode_file j := h <- string_field "handle" j ;; n <- string_field "name" j ;; m <- string_field "mime" j ;; b <- natural_field "bytes" j ;; Some(SelectedFile h n m b).
