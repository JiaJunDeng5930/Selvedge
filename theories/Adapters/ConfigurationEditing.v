From Stdlib Require Import String List Bool NArith.
From Selvedge.Adapters Require Import Common.
From Selvedge.Programming Require ArgumentDeclaration Schema DeclarationFields.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Record setting := Setting {
  name : string;
  declaration : D.t;
  fallback : option json
}.

Record location := Location {
  address : list string;
  shape : D.t;
  supplied : option json;
  inherited : option json;
  write : json -> json;
  reset : option (unit -> json)
}.

Definition chosen (value : location) :=
  match supplied value with Some value => value
  | None => match inherited value with Some value => value | None => JNull end
  end.

Definition describe (value : location) :=
  let schema := D.schema (shape value) in
  let '(kind, extra) :=
    match field "enum" schema with
    | Some choices => ("enum", [("options", choices)])
    | None =>
        (match str schema "type" with
         | "string" => "text" | "boolean" => "boolean"
         | "integer" | "number" => "number" | _ => "json"
         end, [])
    end in
  JObject ([("path", JArray (map JString (address value))); ("value", chosen value);
    ("explicit", JBool (D.present (supplied value)));
    ("resettable", JBool (D.present (reset value))); ("kind", JString kind)] ++ extra).

Definition member_location parent (property : F.property) :=
  let '(key, required, child) := property in
  let source := supplied parent in
  let read source := match source with Some value => field key value | None => None end in
  let current := read source in
  let members := match source with Some value => value | None => JObject [] end in
  Location (address parent ++ [key]) child current (read (inherited parent))
    (fun value => write parent (set members key value))
    (if required then None else Some (fun _ => write parent (without members key))).

Definition element_location parent description position before value after :=
  Location (address parent ++ [decimal position]) description (Some value) None
    (fun value => write parent (JArray (rev_append before (value :: after)))) None.

(** The same structural traversal supplies the editors and the writable locations.
    The executable admission for the resulting document stays with configuration. *)
Fixpoint locations (description : D.t) (value : location) : list location :=
  match description with
  | D.Const _ => []
  | D.Object properties | D.OpenObject properties =>
      value :: if is_object (chosen value) then
        (fix members properties :=
          match properties with
          | [] => []
          | property :: rest =>
              locations (snd property) (member_location value property) ++ members rest
          end) properties
        else []
  | D.Array element | D.BoundedArray _ _ element =>
      value :: (fix elements position before remaining :=
        match remaining with
        | [] => []
        | first :: rest => locations element
            (element_location value element position before first rest) ++
            elements (N.succ position) (first :: before) rest
        end) 0 [] (match supplied value with Some array => items array | None => [] end)
  | _ => [value]
  end.

Definition settings_locations (settings : list setting) (source : json) :=
  flat_map (fun setting =>
    let key := name setting in
    let description := declaration setting in
    locations description (Location [key] description (field key source) (fallback setting)
      (set source key) (Some (fun _ => without source key)))) settings.

Definition editable settings source :=
  if is_object source then success
    (JObject [("entries", JArray (map describe (settings_locations settings source)))])
  else type_error "Configuration must be an object".

Definition change_fields := [
  F.required "path" (D.BoundedArray 1 D.maximum_natural (D.Value Schema.KText));
  F.required "operation" (D.Value (Schema.KEnum "set" ["reset"]));
  F.optional "value" D.Any].

Fixpoint same_address lhs rhs :=
  match lhs, rhs with
  | [], [] => true
  | first :: remaining, second :: rest => String.eqb first second && same_address remaining rest
  | _, _ => false
  end.

Definition edit settings source change :=
  if negb (is_object source) then type_error "Configuration must be an object" else
  match D.decode (D.Object change_fields) change with
  | None => type_error "Invalid configuration edit"
  | Some admitted =>
      let '(path, (operation, (replacement, _))) := proj1_sig admitted in
      match find (fun target => same_address (proj1_sig path) (address target))
              (settings_locations settings source) with
      | None => type_error "Configuration location is not editable"
      | Some target =>
          if String.eqb (proj1_sig operation) "set" then
            match replacement with Some value => success (write target value)
            | None => type_error "Setting a configuration value requires a value" end
          else match replacement, reset target with
            | None, Some revert => if D.present (supplied target) then success (revert tt) else success source
            | _, _ => type_error "Configuration location cannot be reset" end
      end
  end.
