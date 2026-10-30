From Stdlib Require Import String List Bool NArith Ascii.
From Selvedge.Foundation Require OptionList.
From Selvedge.Foundation Require Import Json Numbers Schema Utf8.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

(** Internal arguments are programs in this finite language. JSON Schema is a
    projection for callers, never an unchecked internal argument definition. *)
Definition maximum_natural : N := 4294967295.
Record text_constraints := TextConstraints {
 minimum_characters : N;
 maximum_characters : N;
 maximum_bytes : N;
 text_no_nul : bool;
 text_nonblank : bool;
 text_lower_hex : bool;
 text_choices : option (list string)
}.
Inductive text_format :=
| ConstrainedText (constraints : text_constraints)
| NaturalSpelling (minimum : N) (maximum : option N)
| PrefixedSpelling (prefix : string) (suffix : text_format).
Inductive t :=
| Any | Reject | Null | Boolean
| Const (value : json)
| Textual (format : text_format)
| UnboundedNatural (minimum : N)
| Natural (minimum maximum : N)
| Integer | Decimal
| Array (element : t)
| BoundedArray (minimum maximum : N) (element : t)
| Object (properties : list (string * bool * t))
| OpenObject (properties : list (string * bool * t))
| Union (alternatives : list t).
Definition Text constraints := Textual (ConstrainedText constraints).
Definition NaturalText minimum maximum := Textual (NaturalSpelling minimum maximum).
Definition PrefixedText prefix suffix := Textual (PrefixedSpelling prefix suffix).
Definition unconstrained_text := TextConstraints 0 maximum_natural maximum_natural false false false None.
Definition text := Text unconstrained_text.
Definition bounded_format (bytes : N) := ConstrainedText (TextConstraints 0 maximum_natural bytes true true false None).
Definition bounded_text (bytes : N) := Textual (bounded_format bytes).
Definition exact_lower_hex (length : N) := Text (TextConstraints length length length false false true None).
Definition nullable declaration := Union [declaration; Null].
Definition in_bounds (minimum maximum value : N) := (minimum <=? value) && (value <=? maximum).
Definition lower_hex_byte (character : ascii) :=
 let code := Utf8.byte character in in_bounds 48 57 code || in_bounds 97 102 code.
Fixpoint lower_hex (source : string) := match source with
 | EmptyString => true | String character rest => lower_hex_byte character && lower_hex rest end.
Definition check_text (constraints : text_constraints) (source : string) :=
 match Utf8.scalar_count source with None => false | Some count =>
 in_bounds (minimum_characters constraints) (maximum_characters constraints) (N.of_nat count) &&
 (N.of_nat (Utf8.byte_length source) <=? maximum_bytes constraints) &&
 (negb (text_no_nul constraints) || Utf8.no_nul source) &&
 (negb (text_nonblank constraints) || Utf8.nonblank source) &&
 (negb (text_lower_hex constraints) || lower_hex source) &&
 match text_choices constraints with None => true | Some names => existsb (String.eqb source) names end
 end.
(** Admission retains the declared constraint. Downstream constructors receive
    its value and evidence together, rather than repeating a Boolean check. *)
Definition checked {A : Set} (admissible : A -> bool) :=
 { value : A | admissible value = true }.
Definition admit {A : Set} (admissible : A -> bool) (value : A) : option (checked admissible) :=
 match Bool.bool_dec (admissible value) true with
 | left proof => Some (exist _ value proof) | right _ => None end.
Definition natural_range minimum maximum value := (minimum <=? value) &&
 match maximum with None => true | Some maximum => value <=? maximum end.
Fixpoint text_value (format : text_format) : Set := match format with
 | ConstrainedText constraints => checked (check_text constraints)
 | NaturalSpelling minimum maximum => checked (natural_range minimum maximum)
 | PrefixedSpelling _ suffix => text_value suffix end.
Fixpoint decode_text (format : text_format) (source : string) : option (text_value format) :=
 match format as format return option (text_value format) with
 | ConstrainedText constraints => admit (check_text constraints) source
 | NaturalSpelling minimum maximum => match parse_natural source with
   | Some number => if String.eqb source (show_natural number)
       then admit (natural_range minimum maximum) number else None
   | None => None end
 | PrefixedSpelling prefix suffix => if String.prefix prefix source
   then decode_text suffix (String.substring (String.length prefix) (String.length source) source)
   else None end.
Fixpoint encode_text (format : text_format) : text_value format -> string :=
 match format as format return text_value format -> string with
 | ConstrainedText _ => fun value => proj1_sig value
 | NaturalSpelling _ _ => fun value => show_natural (proj1_sig value)
 | PrefixedSpelling prefix suffix => fun value => (prefix ++ encode_text suffix value)%string end.
(** Object fields retain presence separately from nullability. Their field
    names are unique by type; unions retain the selected alternative. *)
Fixpoint denote (declaration : t) : Set :=
 match declaration with
 | Any => json | Reject => Empty_set | Null | Const _ => unit | Boolean => bool
 | Textual format => text_value format
 | UnboundedNatural minimum => checked (fun value => minimum <=? value)
 | Natural minimum maximum => checked (in_bounds minimum maximum)
 | Integer => Z | Decimal => Schema.decimal
 | Array element => list (denote element)
 | BoundedArray minimum maximum element => checked
     (fun values : list (denote element) => in_bounds minimum maximum (N.of_nat (List.length values)))
 | Object properties | OpenObject properties => checked
   (fun _ : (fix members (properties : list (string * bool * t)) : Set :=
      match properties with [] => unit | (_,required,description) :: rest =>
        ((if required then denote description else option (denote description)) * members rest)%type end) properties =>
      unique_names (map (fun property => fst (fst property)) properties))
 | Union alternatives => (fix choices (alternatives : list t) : Set :=
     match alternatives with [] => Empty_set | first :: rest => (denote first + choices rest)%type end) alternatives
 end.
Fixpoint object_values (properties : list (string * bool * t)) : Set :=
 match properties with [] => unit | (_,required,description) :: rest =>
   ((if required then denote description else option (denote description)) * object_values rest)%type end.
Definition present {A} (value : option A) := match value with Some _ => true | None => false end.
Fixpoint decode (declaration : t) (value : json) : option (denote declaration) :=
 match declaration as description return option (denote description) with
 | Any => Some value | Reject => None
 | Null => match value with JNull => Some tt | _ => None end
 | Const expected => if Json.equal value expected then Some tt else None
 | Boolean => as_bool value
 | Textual format => match value with JString source => decode_text format source | _ => None end
 | UnboundedNatural minimum => match as_number value with Some source => match parse_natural source with
   Some number => admit (fun value => minimum <=? value) number | None => None end | None => None end
 | Natural minimum maximum => match as_number value with Some source => match parse_natural source with
   Some number => admit (in_bounds minimum maximum) number | None => None end | None => None end
 | Integer => Schema.decode_value KInteger value
 | Decimal => Schema.decode_value KDecimal value
 | Array element => match value with JArray values => OptionList.traverse (decode element) values | _ => None end
 | BoundedArray minimum maximum element => match value with JArray values =>
   match OptionList.traverse (decode element) values with
   | Some values => admit (fun values => in_bounds minimum maximum (N.of_nat (List.length values))) values
   | None => None end | _ => None end
 | Object properties | OpenObject properties => match value with JObject values =>
   if unique_names (map fst values) &&
     (match declaration with OpenObject _ => true | _ =>
       forallb (fun value => existsb (fun property => String.eqb (fst value) (fst (fst property))) properties) values end)
   then match (fix members (properties : list (string * bool * t)) : option (object_values properties) :=
     match properties as properties return option (object_values properties) with
     | [] => Some tt
     | (name,required,description) :: rest =>
       let current : option (if required then denote description else option (denote description)) :=
         match required as required return option (if required then denote description else option (denote description)) with
         | true => match lookup name values with Some source => decode description source | None => None end
         | false => match lookup name values with Some source => option_map Some (decode description source) | None => Some None end
         end in
       match current,members rest with Some current,Some tail => Some (current,tail) | _,_ => None end
     end) properties with
   | Some fields => admit (fun _ => unique_names (map (fun property => fst (fst property)) properties)) fields
   | None => None end else None
   | _ => None end
 | Union alternatives => (fix choices (alternatives : list t) : option (denote (Union alternatives)) :=
     match alternatives as alternatives return option (denote (Union alternatives)) with
     | [] => None | first :: rest => match decode first value with
       | Some decoded => Some (inl decoded) | None => option_map inr (choices rest) end
     end) alternatives
 end.
Fixpoint encode (declaration : t) : denote declaration -> json :=
 match declaration as description return denote description -> json with
 | Any => fun value => value | Reject => fun impossible => match impossible with end
 | Null => fun _ => JNull | Boolean => JBool | Const value => fun _ => value
 | Textual format => fun value => JString (encode_text format value)
 | UnboundedNatural _ | Natural _ _ => fun value => JNumber (show_natural (proj1_sig value))
 | Integer => Schema.encode_value KInteger | Decimal => Schema.encode_value KDecimal
 | Array element => fun values => JArray (map (encode element) values)
 | BoundedArray _ _ element => fun values => JArray (map (encode element) (proj1_sig values))
 | Object properties | OpenObject properties => fun values => JObject
   ((fix members (properties : list (string * bool * t)) : object_values properties -> list (string * json) :=
      match properties as properties return object_values properties -> list (string * json) with
      | [] => fun _ => []
      | (name,required,description) :: rest => fun values =>
        let encoded := match required as required return
          (if required then denote description else option (denote description)) -> option json with
          | true => fun value => Some (encode description value)
          | false => option_map (encode description) end (fst values) in
        match encoded with Some value => (name,value) :: members rest (snd values)
        | None => members rest (snd values) end
      end) properties (proj1_sig values))
 | Union alternatives =>
   (fix choices (alternatives : list t) : denote (Union alternatives) -> json :=
     match alternatives as alternatives return denote (Union alternatives) -> json with
     | [] => fun impossible => match impossible with end
     | first :: rest => fun value => match value with
       | inl value => encode first value | inr value => choices rest value end
     end) alternatives
 end.
Definition check (declaration : t) (value : json) := present (decode declaration value).
Definition bound_fields minimum maximum := [("minimum",JNumber (show_natural minimum));("maximum",JNumber (show_natural maximum))].
Definition text_fields (constraints : text_constraints) :=
 [("type",JString "string");("minLength",JNumber (show_natural (minimum_characters constraints)));
  ("maxLength",JNumber (show_natural (maximum_characters constraints)));
  ("x-maxUtf8Bytes",JNumber (show_natural (maximum_bytes constraints)))] ++
 (if text_no_nul constraints then [("x-noNul",JBool true)] else []) ++
 (if text_nonblank constraints then [("x-nonblank",JBool true)] else []) ++
 (if text_lower_hex constraints then [("pattern",JString "^[0-9a-f]*$")] else []) ++
 match text_choices constraints with None => [] | Some names => [("enum",JArray (map JString names))] end.
Fixpoint text_schema (format : text_format) : json := match format with
 | ConstrainedText constraints => JObject (text_fields constraints)
 | NaturalSpelling minimum maximum => JObject ([("type",JString "string");("x-naturalTextMinimum",JNumber (show_natural minimum))] ++
    match maximum with None => [] | Some maximum => [("x-naturalTextMaximum",JNumber (show_natural maximum))] end)
 | PrefixedSpelling prefix suffix => JObject [("type",JString "string");("x-prefix",JString prefix);("x-suffix",text_schema suffix)] end.
Fixpoint schema (declaration : t) : json :=
 match declaration with
 | Any => JObject [] | Reject => JBool false
 | Const value => JObject [("const",value)]
 | Null => JObject [("type",JString "null")]
 | Boolean => JObject [("type",JString "boolean")]
 | Textual format => text_schema format
 | UnboundedNatural minimum => JObject [("type",JString "integer");("minimum",JNumber (show_natural minimum))]
 | Natural minimum maximum => JObject ([("type",JString "integer")] ++ bound_fields minimum maximum)
 | Integer => JObject [("type",JString "integer");("x-signedInteger",JBool true)]
 | Decimal => JObject [("type",JString "number")]
 | Array element => JObject [("type",JString "array");("items",schema element)]
 | BoundedArray minimum maximum element => JObject [("type",JString "array");("items",schema element);
     ("minItems",JNumber (show_natural minimum));("maxItems",JNumber (show_natural maximum))]
 | Object properties | OpenObject properties => JObject [("type",JString "object");
   ("additionalProperties",JBool (match declaration with OpenObject _ => true | _ => false end));
   ("properties",JObject (map (fun property => (fst (fst property),schema (snd property))) properties));
   ("required",JArray (map (fun property => JString (fst (fst property)))
     (filter (fun property => snd (fst property)) properties)))]
 | Union alternatives => JObject [("anyOf",JArray (map schema alternatives))]
 end.
Fixpoint of_kind (description : kind) : t := match description with
 | KText => text | KBool => Boolean | KNatural => UnboundedNatural 0
 | KInteger => Integer | KDecimal => Decimal | KJson => Any
 | KArray element => Array (of_kind element)
 | KOptional element => nullable (of_kind element)
 | KEnum first rest => Text (TextConstraints 0 maximum_natural maximum_natural false false false (Some (first::rest)))
 end.

Definition of_schema (declaration : Schema.schema) := Object (map (fun field =>
 (field_name field,negb (field_omittable field || Schema.optional_kind (field_kind field)),
 of_kind (Schema.present_kind (field_kind field)))) declaration).

Definition refine_object (overrides : list (string * t)) (declaration : t) :=
 match declaration with Object properties => Object (map (fun property =>
   match find (fun entry => String.eqb (fst (fst property)) (fst entry)) overrides with
   | Some (_,replacement) => (fst property,replacement) | None => property end) properties)
 | _ => declaration end.

(** External extension registration shares these JSON Schema observations;
    internal declarations execute directly and never reparse their projection. *)
Definition member (name : string) (names : list string) := existsb (String.eqb name) names.
Definition object_keys (source : json) (names : list string) := match source with
 | JObject fields => unique_names (map fst fields) && forallb (fun entry => member (fst entry) names) fields
 | _ => false end.
Definition natural (value : json) := match value with
 | JNumber source => parse_natural source | _ => None end.
Definition bound_or (value : option json) (fallback : N) :=
 match value with Some value => match natural value with Some number => number | None => fallback end | None => fallback end.
Definition optional_text (value : option json) := match value with None | Some (JString _) => true | _ => false end.
Fixpoint strings (values : list json) : option (list string) := match values with
 | [] => Some [] | JString text :: rest => option_map (cons text) (strings rest) | _ => None end.
Definition enum_choices (value : option json) : option (option (list string)) := match value with
 | None => Some None
 | Some (JArray ((_ :: _) as values)) => match strings values with Some names =>
   if unique_names names && Nat.leb (List.length names) 256 then Some (Some names) else None | None => None end
 | _ => None end.
Definition traverse {A B : Type} (f : A -> option B) (values : list A) : option (list B) :=
 OptionList.traverse f values.
Definition required_names (properties : list (string * json)) (source : option json) :=
 match source with None => Some [] | Some (JArray values) => match strings values with
 | Some names => if unique_names names && forallb (fun name => member name (map fst properties)) names
   then Some names else None | None => None end | _ => None end.
