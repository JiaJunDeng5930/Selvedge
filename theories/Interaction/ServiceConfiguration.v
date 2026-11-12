From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json TextJson Numbers.
From Selvedge.Foundation Require BoundedInteger.
From Selvedge.Interaction Require Import Codec.
Import ListNotations.
Open Scope string_scope.

Inductive input_kind := Text | Boolean | Number | Choice (options : list json) | Structured.

Record setting := Setting {
  setting_path : list string;
  setting_value : json;
  setting_explicit : bool;
  setting_resettable : bool;
  setting_reset_changes_value : bool;
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
    ("reset_changes_value", JBool (setting_reset_changes_value entry));
    ("kind", JString kind)] ++ extra)%list.

Definition decode_setting j :=
  path <- list_field as_string "path" j ;;
  value <- field "value" j ;;
  explicit <- bool_field "explicit" j ;;
  resettable <- bool_field "resettable" j ;;
  changes_value <- bool_field "reset_changes_value" j ;;
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
  | _ => Some (Setting path value explicit resettable changes_value input)
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

Definition idle_lead_in_seconds entry :=
  match setting_path entry, setting_input entry with
  | ["compaction"; "idle_lead_ms"], Number => true
  | _, _ => false
  end.

Definition seconds_precision := 3%nat.
Definition milliseconds_per_second := N.pow 10 (N.of_nat seconds_precision).
Definition format_milliseconds_as_seconds (milliseconds : N) :=
  let whole := show_natural (N.div milliseconds milliseconds_per_second) in
  let remainder := N.modulo milliseconds milliseconds_per_second in
  if N.eqb remainder 0 then whole else
    whole ++ "." ++ substring 1 seconds_precision (show_natural (milliseconds_per_second + remainder)).

Definition milliseconds_digits :=
  decimal_width (N.to_uint (Z.to_N BoundedInteger.safe_integer_limit)).

Definition parse_seconds_as_milliseconds raw :=
  seconds <- parse_decimal raw ;;
  let '(negative, coefficient, fraction, exponent) := BoundedInteger.decimal_components seconds in
  let scaled := Decimal.app coefficient (Nat.iter seconds_precision Decimal.D0 Decimal.Nil) in
  value <- BoundedInteger.coefficient_integer milliseconds_digits negative scaled fraction exponent ;;
  if (0 <=? value)%Z && BoundedInteger.within_safe_integer value then
    Some (JNumber (show_natural (Z.to_N value))) else None.

Definition initial_input entry :=
  match setting_input entry with
  | Text => value_or "" (as_string (setting_value entry))
  | Number => match setting_value entry with
      | JNumber number => if idle_lead_in_seconds entry then
          value_or "" (option_map format_milliseconds_as_seconds
            (BoundedInteger.decode_natural milliseconds_digits number))
        else number
      | _ => ""
      end
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

Definition interpret_setting_input entry raw :=
  let value := interpret_input (setting_input entry) raw in
  if idle_lead_in_seconds entry then
    number <- bind value as_number ;;
    parse_seconds_as_milliseconds number
  else value.

Definition can_reset entry :=
  setting_resettable entry && setting_explicit entry &&
  match setting_path entry, setting_input entry with
  | ["compaction"; _], (Boolean | Number) => setting_reset_changes_value entry
  | _, _ => true
  end.

Inductive change := Assign (value : json) | Reset.

Definition request (current : snapshot) entry change :=
  let fields := [("revision", JString (revision current)); ("path", encode_path (setting_path entry))] in
  JObject (match change with
  | Assign value => ("operation", JString "set") :: ("value", value) :: fields
  | Reset => ("operation", JString "reset") :: fields
  end).
