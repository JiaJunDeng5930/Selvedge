From Stdlib Require Import String List Bool NArith ZArith.
From Selvedge.Foundation Require Import Json Numbers.
Import ListNotations.
Open Scope string_scope.

Record decimal : Type := Decimal { spelling : string; spelling_valid : number_lexeme spelling = true }.

(** Enum choices are nonempty, so both default construction and selection are total. *)
Inductive kind : Type :=
| KText | KBool | KNatural | KInteger | KDecimal | KJson
| KArray (element : kind)
| KOptional (element : kind)
| KEnum (first : string) (rest : list string).

Fixpoint denote (description : kind) : Type :=
  match description with
  | KText => string | KBool => bool | KNatural => N | KInteger => Z
  | KDecimal => decimal | KJson => json
  | KArray element => list (denote element)
  | KOptional element => option (denote element)
  | KEnum first rest => { value : string | In value (first :: rest) }
  end.

Record field_spec := Field { field_name : string; field_kind : kind }.
Definition schema := list field_spec.
Inductive fields : schema -> Type :=
| FNil : fields []
| FCons : forall field rest, denote (field_kind field) -> fields rest -> fields (field :: rest).
Arguments FCons {field rest} _ _.

Fixpoint decode_list {A} (decode : json -> option A) (values : list json) : option (list A) :=
  match values with
  | [] => Some []
  | value :: rest => match decode value, decode_list decode rest with
    | Some value, Some rest => Some (value :: rest)
    | _, _ => None end
  end.
Fixpoint decode_value (description : kind) : json -> option (denote description) :=
  match description as description return json -> option (denote description) with
  | KText => as_string
  | KBool => as_bool
  | KNatural => fun value => match as_number value with Some s => parse_natural s | None => None end
  | KInteger => fun value => match as_number value with Some s => parse_integer s | None => None end
  | KDecimal => fun value => match value with
    | JNumber text => match number_lexeme text as valid return
        number_lexeme text = valid -> option decimal with
      | true => fun proof => Some (Decimal text proof)
      | false => fun _ => None end eq_refl
    | _ => None end
  | KJson => fun value => Some value
  | KArray element => fun value => match value with
      JArray values => decode_list (decode_value element) values | _ => None end
  | KOptional element => fun value => match value with
      JNull => Some None | _ => option_map Some (decode_value element value) end
  | KEnum first rest => fun value => match value with
    | JString text => match in_dec string_dec text (first :: rest) with
        left proof => Some (exist _ text proof) | right _ => None end
    | _ => None end
  end.
Fixpoint encode_value (description : kind) : denote description -> json :=
  match description as description return denote description -> json with
  | KText => JString | KBool => JBool
  | KNatural => fun value => JNumber (show_natural value)
  | KInteger => fun value => JNumber (show_integer value)
  | KDecimal => fun value => JNumber (spelling value)
  | KJson => fun value => value
  | KArray element => fun values => JArray (map (encode_value element) values)
  | KOptional element => fun value => match value with
      None => JNull | Some value => encode_value element value end
  | KEnum _ _ => fun value => JString (proj1_sig value)
  end.
Definition default_value (description : kind) : denote description :=
  match description as description return denote description with
  | KText => "" | KBool => false | KNatural => 0%N | KInteger => 0%Z
  | KDecimal => Decimal "0" eq_refl | KJson => JNull
  | KArray _ => [] | KOptional _ => None
  | KEnum first rest => exist _ first (or_introl eq_refl)
  end.
Fixpoint defaults (description : schema) : fields description :=
  match description with
  | [] => FNil
  | field :: rest => FCons (default_value (field_kind field)) (defaults rest)
  end.
Fixpoint encode_fields {description} (values : fields description) : list (string * json) :=
  match values with
  | FNil => []
  | @FCons field rest value values =>
      (field_name field, encode_value (field_kind field) value) :: encode_fields values
  end.
Definition encode (description : schema) (values : fields description) : json := JObject (encode_fields values).
Fixpoint unique_names (names : list string) : bool :=
  match names with
  | [] => true
  | name :: rest => negb (existsb (String.eqb name) rest) && unique_names rest
  end.
Definition declared_names (description : schema) := map field_name description.
Definition schema_valid (description : schema) := unique_names (declared_names description).
Definition source_keys (source : list (string * json)) := map fst source.
Definition keys_declared (description : schema) (source : list (string * json)) :=
  forallb (fun key => existsb (String.eqb key) (declared_names description)) (source_keys source).
Definition missing_value (description : kind) : option (denote description) :=
  match description as description return option (denote description) with
  | KOptional _ => Some None
  | _ => None
  end.
Fixpoint decode_fields (description : schema) (source : list (string * json)) : option (fields description) :=
  match description as description return option (fields description) with
  | [] => Some FNil
  | field :: rest =>
      let value := match lookup (field_name field) source with
        Some value => decode_value (field_kind field) value
      | None => missing_value (field_kind field) end in
      match value, decode_fields rest source with
      | Some value, Some values => Some (FCons value values)
      | _, _ => None end
  end.
Definition decode (description : schema) (source : json) : option (fields description) :=
  match source with
  | JObject source =>
      if schema_valid description && unique_names (source_keys source) && keys_declared description source
      then decode_fields description source else None
  | _ => None
  end.
Fixpoint lookup_field {description} (name : string) (values : fields description) : option json :=
  match values with
  | FNil => None
  | @FCons field rest value values =>
      if String.eqb name (field_name field) then Some (encode_value (field_kind field) value)
      else lookup_field name values
  end.
Fixpoint update_field {description} (name : string) (source : json) (values : fields description) : option (fields description) :=
  match values in fields description return option (fields description) with
  | FNil => None
  | @FCons field rest value values =>
      if String.eqb name (field_name field) then
        option_map (fun value => FCons value values) (decode_value (field_kind field) source)
      else option_map (fun values => FCons value values) (update_field name source values)
  end.

Record command_spec := Command { command_name : string; command_fields : schema }.
Inductive command_value : list command_spec -> Type :=
| CFirst : forall command rest, fields (command_fields command) -> command_value (command :: rest)
| CNext : forall command rest, command_value rest -> command_value (command :: rest).
Arguments CFirst {command rest} _.
Arguments CNext {command rest} _.
Fixpoint decode_named_command (commands : list command_spec) (name : string) (source : json) : option (command_value commands) :=
  match commands as commands return option (command_value commands) with
  | [] => None
  | command :: rest =>
      if String.eqb name (command_name command)
      then option_map CFirst (decode (command_fields command) source)
      else option_map CNext (decode_named_command rest name source)
  end.
Definition decode_command (commands : list command_spec) (source : json) : option (command_value commands) :=
  match source with
  | JObject source => match lookup "op" source with
    | Some (JString name) =>
        if unique_names (source_keys source)
        then decode_named_command commands name (JObject (remove_field "op" source)) else None
    | _ => None end
  | _ => None
  end.
Definition encode_declared (command : command_spec) (values : fields (command_fields command)) : json :=
  JObject (("op", JString (command_name command)) :: encode_fields values).
Fixpoint encode_command {commands} (value : command_value commands) : json :=
  match value with
  | @CFirst command rest values => encode_declared command values
  | @CNext _ _ value => encode_command value
  end.

Definition head {field rest} (values : fields (field :: rest)) : denote (field_kind field) :=
  match values in fields description return
    match description with [] => unit | field :: _ => denote (field_kind field) end with
  | FNil => tt
  | FCons value _ => value
  end.
Definition tail {field rest} (values : fields (field :: rest)) : fields rest :=
  match values in fields description return
    match description with [] => unit | _ :: rest => fields rest end with
  | FNil => tt
  | FCons _ values => values
  end.
Definition projection (description : schema) :=
  { description_kind : kind & (string * (fields description -> denote description_kind))%type }.
Fixpoint projections (description : schema) : list (projection description) :=
  match description as description return list (projection description) with
  | [] => []
  | field :: rest =>
      existT _ (field_kind field) (field_name field, @head field rest) ::
      map (fun entry => match entry with
        existT _ kind entry =>
          existT _ kind (fst entry, fun values => snd entry (tail values))
      end) (projections rest)
  end.
