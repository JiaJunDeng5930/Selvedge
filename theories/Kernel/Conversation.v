From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec.
Import ListNotations.
Open Scope string_scope.

Definition provider_value (value : json) :=
 match string_field "type" value with Some "provider_receipt" => value_or_null "item" value | _ => value end.
Definition provider_assistant (value : json) :=
 match string_field "role" (provider_value value) with Some "assistant" => true | _ => false end.
Definition provider_assistant_message (value : json) :=
 String.eqb (text_default "type" (provider_value value) "") "message" && provider_assistant value.
Definition context_output_mode (value : json) (mode : output_mode) :=
 if provider_assistant_message value then mode else PlainOutput.
Definition provider_part_text (value : json) :=
 match string_field "type" value with
 | Some "output_text" | Some "summary_text" => text_default "text" value ""
 | Some "refusal" => text_default "refusal" value ""
 | _ => "" end.
Definition provider_text (value : json) :=
 fold_right (fun part text => String.append (provider_part_text part) text) ""
  (array_default "content" (provider_value value)).
Definition content_part_text (value : json) :=
 match string_field "type" value with
 | Some "text" => text_default "text" value ""
 | Some "image" => "
[Image]
"
 | _ => "" end.
Definition content_part_markdown (value : json) :=
 match string_field "type" value with
 | Some "image" => String.append "
![Image](/api/board/attachments/" (String.append
     (text_default "id" (value_or_null "image" value) "") ")
")
 | _ => content_part_text value end.
Definition public_content (render_part : json -> string) (value : json) : option string :=
 match value with
 | JString text => Some text
 | JArray parts => Some (fold_right (fun part text => String.append (render_part part) text) "" parts)
 | _ => None end.
Definition public_text := public_content content_part_text.
Definition public_markdown := public_content content_part_markdown.
Definition json_message_assistant (message : json) :=
 match string_field "role" message with
 | Some "assistant" => true
 | Some "model_context" => provider_assistant_message (value_or_null "content" message)
 | _ => false end.
Definition json_message_role (message : json) : option string :=
 match string_field "role" message with
 | Some "speech_transcript" => string_field "speaker" message
 | Some "model_context" => if provider_assistant_message (value_or_null "content" message) then Some "assistant" else None
 | Some role => Some role
 | None => None end.
Definition json_message_text (message : json) : option string :=
 match string_field "role" message with
 | Some "model_context" => Some (provider_text (value_or_null "content" message))
 | Some "user" => public_markdown (value_or_null "content" message)
 | _ => public_text (value_or_null "content" message)
 end.
Definition json_message_content (message : json) :=
 match string_field "role" message with
 | Some "model_context" => JString (provider_text (value_or_null "content" message))
 | Some "user" => match public_text (value_or_null "content" message) with Some text => JString text | None => JNull end
 | _ => value_or_null "content" message end.
