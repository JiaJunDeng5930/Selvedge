From Stdlib Require Import String List Bool NArith Ascii.
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
Inductive t :=
| Any | Reject | Null | Boolean
| Text (constraints : text_constraints)
| NaturalText (minimum : N) (maximum : option N)
| PrefixedText (prefix : string) (suffix : t)
| UnboundedNatural (minimum : N)
| Natural (minimum maximum : N)
| Integer | Decimal
| Array (element : t)
| BoundedArray (minimum maximum : N) (element : t)
| Object (properties : list (string * bool * t))
| OpenObject (properties : list (string * bool * t))
| Union (alternatives : list t).
Definition unconstrained_text := TextConstraints 0 maximum_natural maximum_natural false false false None.
Definition text := Text unconstrained_text.
Definition bounded_text (bytes : N) := Text (TextConstraints 0 maximum_natural bytes true true false None).
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
Fixpoint check (declaration : t) (value : json) : bool :=
 match declaration with
 | Any => true | Reject => false
 | Null => match value with JNull => true | _ => false end
 | Boolean => match value with JBool _ => true | _ => false end
 | Text constraints => match value with JString source => check_text constraints source | _ => false end
 | UnboundedNatural minimum => match as_number value with Some source => match parse_natural source with
   Some number => minimum <=? number | None => false end | None => false end
 | NaturalText minimum maximum => match value with JString source => match parse_natural source with
   | Some number => String.eqb source (show_natural number) && (minimum <=? number) &&
       match maximum with None => true | Some maximum => number <=? maximum end
   | None => false end | _ => false end
 | PrefixedText prefix suffix => match value with JString source => String.prefix prefix source &&
   check suffix (JString (String.substring (String.length prefix) (String.length source) source)) | _ => false end
 | Natural minimum maximum => match as_number value with Some source => match parse_natural source with
   Some number => in_bounds minimum maximum number | None => false end | None => false end
 | Integer => match as_number value with Some source => match parse_integer source with Some _ => true | None => false end | None => false end
 | Decimal => match as_number value with Some source => number_lexeme source | None => false end
 | Array element => match value with JArray values => forallb (check element) values | _ => false end
 | BoundedArray minimum maximum element => match value with JArray values =>
   in_bounds minimum maximum (N.of_nat (List.length values)) && forallb (check element) values | _ => false end
 | Object properties | OpenObject properties => match value with JObject values =>
   unique_names (map fst values) && unique_names (map (fun property => fst (fst property)) properties) &&
   forallb (fun property => match lookup (fst (fst property)) values with
      None => negb (snd (fst property)) | Some value => check (snd property) value end) properties &&
   (match declaration with OpenObject _ => true | _ =>
     forallb (fun value => existsb (fun property => String.eqb (fst value) (fst (fst property))) properties) values end)
   | _ => false end
 | Union alternatives => existsb (fun alternative => check alternative value) alternatives
 end.
Definition bound_fields minimum maximum := [("minimum",JNumber (show_natural minimum));("maximum",JNumber (show_natural maximum))].
Definition text_fields (constraints : text_constraints) :=
 [("type",JString "string");("minLength",JNumber (show_natural (minimum_characters constraints)));
  ("maxLength",JNumber (show_natural (maximum_characters constraints)));
  ("x-maxUtf8Bytes",JNumber (show_natural (maximum_bytes constraints)))] ++
 (if text_no_nul constraints then [("x-noNul",JBool true)] else []) ++
 (if text_nonblank constraints then [("x-nonblank",JBool true)] else []) ++
 (if text_lower_hex constraints then [("pattern",JString "^[0-9a-f]*$")] else []) ++
 match text_choices constraints with None => [] | Some names => [("enum",JArray (map JString names))] end.
Fixpoint schema (declaration : t) : json :=
 match declaration with
 | Any => JObject [] | Reject => JBool false
 | Null => JObject [("type",JString "null")]
 | Boolean => JObject [("type",JString "boolean")]
 | Text constraints => JObject (text_fields constraints)
 | UnboundedNatural minimum => JObject [("type",JString "integer");("minimum",JNumber (show_natural minimum))]
 | NaturalText minimum maximum => JObject ([("type",JString "string");("x-naturalTextMinimum",JNumber (show_natural minimum))] ++
    match maximum with None => [] | Some maximum => [("x-naturalTextMaximum",JNumber (show_natural maximum))] end)
 | PrefixedText prefix suffix => JObject [("type",JString "string");("x-prefix",JString prefix);("x-suffix",schema suffix)]
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
Fixpoint of_kind (description : kind) := match description with
 | KText => text | KBool => Boolean | KNatural => UnboundedNatural 0
 | KInteger => Integer | KDecimal => Decimal | KJson => Any
 | KArray element => Array (of_kind element)
 | KOptional element => nullable (of_kind element)
 | KEnum first rest => Text (TextConstraints 0 maximum_natural maximum_natural false false false (Some (first::rest)))
 end.

(** Extension registration uses a closed parser. Unrecognized assertions fail
    registration, rather than silently acquiring a weaker interpretation. *)
Definition member (name : string) (names : list string) := existsb (String.eqb name) names.
Definition object_keys (source : json) (names : list string) := match source with
 | JObject fields => unique_names (map fst fields) && forallb (fun entry => member (fst entry) names) fields
 | _ => false end.
Definition natural (value : json) := match value with
 | JNumber source => parse_natural source | _ => None end.
Definition optional_bound (value : option json) := match value with
 | None => true | Some value => match natural value with Some _ => true | None => false end end.
Definition bound_or (value : option json) (fallback : N) :=
 match value with Some value => match natural value with Some number => number | None => fallback end | None => fallback end.
Definition optional_text (value : option json) := match value with None | Some (JString _) => true | _ => false end.
Definition optional_flag (value : option json) := match value with None | Some (JBool _) => true | _ => false end.
Definition flag (value : option json) := match value with Some (JBool true) => true | _ => false end.
Fixpoint strings (values : list json) : option (list string) := match values with
 | [] => Some [] | JString text :: rest => option_map (cons text) (strings rest) | _ => None end.
Definition enum_choices (value : option json) : option (option (list string)) := match value with
 | None => Some None
 | Some (JArray ((_ :: _) as values)) => match strings values with Some names =>
   if unique_names names && Nat.leb (List.length names) 256 then Some (Some names) else None | None => None end
 | _ => None end.
Fixpoint traverse {A B} (f : A -> option B) (values : list A) : option (list B) :=
 match values with [] => Some [] | value::rest => match f value, traverse f rest with
 | Some value,Some rest => Some (value::rest) | _,_ => None end end.
Definition parse_text (source : json) :=
 let lower := bound_or (field "minLength" source) 0 in
 let upper := bound_or (field "maxLength" source) maximum_natural in
 let bytes := bound_or (field "x-maxUtf8Bytes" source) maximum_natural in
 if object_keys source ["type";"description";"title";"minLength";"maxLength";"x-maxUtf8Bytes";"x-noNul";"x-nonblank";"pattern";"enum"] &&
    optional_bound (field "minLength" source) && optional_bound (field "maxLength" source) &&
    optional_bound (field "x-maxUtf8Bytes" source) && (lower <=? upper) &&
    optional_flag (field "x-noNul" source) && optional_flag (field "x-nonblank" source)
 then match field "pattern" source, enum_choices (field "enum" source) with
 | None,Some choices => Some (Text (TextConstraints lower upper bytes
    (flag (field "x-noNul" source)) (flag (field "x-nonblank" source)) false choices))
 | Some (JString "^[0-9a-f]*$"),Some choices => Some (Text (TextConstraints lower upper bytes
    (flag (field "x-noNul" source)) (flag (field "x-nonblank" source)) true choices))
 | _,_ => None end else None.
Definition required_names (properties : list (string * json)) (source : option json) :=
 match source with None => Some [] | Some (JArray values) => match strings values with
 | Some names => if unique_names names && forallb (fun name => member name (map fst properties)) names
   then Some names else None | None => None end | _ => None end.
Fixpoint parse_fuel (fuel : nat) (source : json) : option t :=
 match fuel with O => None | S fuel =>
 if optional_text (field "description" source) && optional_text (field "title" source) then
 match source with
 | JBool false => Some Reject
 | JObject [] => Some Any
 | JObject fields => match lookup "anyOf" fields with
   | Some (JArray ((_ :: _) as alternatives)) =>
     if object_keys source ["anyOf";"description";"title"] then option_map Union (traverse (parse_fuel fuel) alternatives) else None
   | Some _ => None
   | None => if object_keys source ["description";"title"] then Some Any else match string_field "type" source with
     | Some "string" => match field "x-prefix" source, field "x-naturalTextMinimum" source with
       | Some (JString prefix),None =>
         if object_keys source ["type";"description";"title";"x-prefix";"x-suffix"] then
           match field "x-suffix" source with Some suffix => option_map (PrefixedText prefix) (parse_fuel fuel suffix) | None => None end
         else None
       | None,Some minimum =>
         if object_keys source ["type";"description";"title";"x-naturalTextMinimum";"x-naturalTextMaximum"] &&
            optional_bound (field "x-naturalTextMaximum" source) then
           match natural minimum with Some minimum =>
             match field "x-naturalTextMaximum" source with None => Some (NaturalText minimum None)
             | Some value => match natural value with Some maximum =>
                 if minimum <=? maximum then Some (NaturalText minimum (Some maximum)) else None
               | None => None end end | None => None end
         else None
       | None,None => parse_text source
       | _,_ => None end
     | Some "null" => if object_keys source ["type";"description";"title"] then Some Null else None
     | Some "boolean" => if object_keys source ["type";"description";"title"] then Some Boolean else None
     | Some "number" => if object_keys source ["type";"description";"title"] then Some Decimal else None
     | Some "integer" =>
       if object_keys source ["type";"description";"title";"minimum";"maximum";"x-signedInteger"] &&
          optional_bound (field "minimum" source) && optional_bound (field "maximum" source) &&
          optional_flag (field "x-signedInteger" source)
       then if flag (field "x-signedInteger" source) then
         match field "minimum" source, field "maximum" source with None,None => Some Integer | _,_ => None end
       else match field "minimum" source, field "maximum" source with
       | None,None => Some Integer
       | None,Some _ => None
       | Some _,maximum => let lower := bound_or (field "minimum" source) 0 in
           let upper := bound_or maximum maximum_natural in
           match maximum with None => Some (UnboundedNatural lower)
           | Some _ => if lower <=? upper then Some (Natural lower upper) else None end
       end
       else None
     | Some "array" =>
       if object_keys source ["type";"description";"title";"items";"minItems";"maxItems"] &&
          optional_bound (field "minItems" source) && optional_bound (field "maxItems" source)
       then match field "items" source with Some item =>
         match parse_fuel fuel item with Some declaration =>
           match field "minItems" source, field "maxItems" source with
           | None,None => Some (Array declaration)
           | _,_ => let lower := bound_or (field "minItems" source) 0 in
               let upper := bound_or (field "maxItems" source) maximum_natural in
               if lower <=? upper then Some (BoundedArray lower upper declaration) else None
           end | None => None end | None => None end else None
     | Some "object" =>
       if object_keys source ["type";"description";"title";"properties";"required";"additionalProperties"] &&
          optional_flag (field "additionalProperties" source)
       then match field "properties" source with Some (JObject properties) =>
         if unique_names (map fst properties) then match required_names properties (field "required" source) with
         | Some required => option_map
           (match field "additionalProperties" source with Some (JBool false) => Object | _ => OpenObject end)
           (traverse (fun property =>
             option_map (fun declaration => (fst property, member (fst property) required, declaration))
                (parse_fuel fuel (snd property))) properties)
         | None => None end else None | _ => None end else None
     | _ => None end
   end
 | _ => None end else None end.
Definition parse := parse_fuel 256.


(** Internal declarations execute directly. Their schema is a projection of
    that program; compiling cannot reject or alter an internal declaration. *)
Record executable := Executable { program : t }.
Definition emitted_schema (declaration : executable) := schema (program declaration).
Definition compile (declaration : t) := Executable declaration.
Theorem compile_preserves_language : forall declaration value,
 check (program (compile declaration)) value = check declaration value.
Proof. reflexivity. Qed.
Theorem compile_preserves_schema : forall declaration,
 emitted_schema (compile declaration) = schema declaration.
Proof. reflexivity. Qed.
