From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.

Inductive input_kind := Text | Boolean | Number | Choice (options : list json) | Structured.

Record setting := Setting {
  setting_path : list string;
  setting_value : json;
  setting_explicit : bool;
  setting_resettable : bool;
  setting_input : input_kind
}.

Record snapshot := Snapshot {
  revision : string;
  entries : list setting
}.

Definition encode_path path := JArray (map JString path).
Definition encode_setting entry :=
  let '(kind, extra) := match setting_input entry with
    | Text => ("text", [])
    | Boolean => ("boolean", [])
    | Number => ("number", [])
    | Choice options => ("enum", [("options", JArray options)])
    | Structured => ("json", [])
    end in
  JObject ([("path", encode_path (setting_path entry)); ("value", setting_value entry);
    ("explicit", JBool (setting_explicit entry)); ("resettable", JBool (setting_resettable entry));
    ("kind", JString kind)] ++ extra)%list.

Definition decode_setting j :=
  path <- list_field as_string "path" j ;;
  value <- field "value" j ;;
  explicit <- bool_field "explicit" j ;;
  resettable <- bool_field "resettable" j ;;
  kind <- string_field "kind" j ;;
  input <- match kind with
    | "text" => Some Text
    | "boolean" => Some Boolean
    | "number" => Some Number
    | "enum" => option_map Choice (array_field "options" j)
    | "json" => Some Structured
    | _ => None
    end ;;
  match path with
  | [] => None
  | _ => Some (Setting path value explicit resettable input)
  end.

Definition encode_snapshot value := JObject
  [("revision", JString (revision value)); ("entries", JArray (map encode_setting (entries value)))].
Definition decode_snapshot j :=
  version <- string_field "revision" j ;;
  fields <- list_field decode_setting "entries" j ;;
  Some (Snapshot version fields).

Definition setting_key path := TextJson.render_json (encode_path path).
Definition find_setting path current :=
  find (fun entry => String.eqb (setting_key (setting_path entry)) (setting_key path)) (entries current).

Definition display_value value :=
  match value with JString text => text | _ => TextJson.render_json value end.

Definition initial_input entry :=
  match setting_input entry with
  | Text => value_or "" (as_string (setting_value entry))
  | Number => match setting_value entry with JNumber number => number | _ => "" end
  | _ => TextJson.render_json (setting_value entry)
  end.

Definition interpret_input kind raw :=
  match kind with
  | Text => Some (JString raw)
  | Number => match TextJson.parse_json raw with Some (JNumber value) => Some (JNumber value) | _ => None end
  | Boolean => match raw with "true" => Some (JBool true) | "false" => Some (JBool false) | _ => None end
  | Choice options => find (fun value => String.eqb (TextJson.render_json value) raw) options
  | Structured => TextJson.parse_json raw
  end.

Inductive change := Assign (value : json) | Reset.

Definition request (current : snapshot) entry change :=
  let fields := [("revision", JString (revision current)); ("path", encode_path (setting_path entry))] in
  JObject (match change with
  | Assign value => ("operation", JString "set") :: ("value", value) :: fields
  | Reset => ("operation", JString "reset") :: fields
  end).
