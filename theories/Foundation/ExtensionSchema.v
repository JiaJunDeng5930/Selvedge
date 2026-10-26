From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Foundation Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Module D := ArgumentDeclaration.

(** The extension protocol is a deliberately smaller dialect than internal
    declarations or server-owned MCP schemas. Registration compiles that
    dialect into the shared argument language; execution has one checker. *)
Definition optional_text (value : option json) := match value with
 | None | Some JNull | Some (JString _) => true | _ => false end.
Definition optional_natural (value : option json) := match value with
 | None | Some JNull => true
 | Some source => match D.natural source with
   | Some number => number <=? D.maximum_natural | None => false end end.
Definition closed (value : option json) := match value with
 | None | Some JNull | Some (JBool false) => true | _ => false end.
Definition required_names (properties : list (string * json)) (value : option json) :=
 D.required_names properties (match value with Some JNull => None | other => other end).
Fixpoint parse_fuel (fuel : nat) (source : json) : option D.t :=
 match fuel with O => None | S fuel =>
 if optional_text (field "description" source) && optional_text (field "title" source)
 then match source with
 | JObject fields => match lookup "anyOf" fields with
   | Some (JArray ((_ :: _) as alternatives)) =>
     if D.object_keys source ["anyOf";"description"] &&
        D.optional_text (field "description" source)
     then option_map D.Union (D.traverse (parse_fuel fuel) alternatives) else None
   | Some _ => None
   | None => match string_field "type" source with
     | Some "string" =>
       if D.object_keys source ["type";"description";"title";"enum"] then
       match D.enum_choices (field "enum" source) with
       | Some choices => Some (D.Text (D.TextConstraints 0 D.maximum_natural
           D.maximum_natural false false false choices))
       | None => None end else None
     | Some "integer" =>
       let lower := D.bound_or (field "minimum" source) 0 in
       let upper := D.bound_or (field "maximum" source) D.maximum_natural in
       if D.object_keys source ["type";"description";"title";"minimum";"maximum"] &&
          optional_natural (field "minimum" source) &&
          optional_natural (field "maximum" source) && (lower <=? upper)
       then Some (D.Natural lower upper) else None
     | Some "null" =>
       if D.object_keys source ["type";"description";"title"] then Some D.Null else None
     | Some "boolean" =>
       if D.object_keys source ["type";"description";"title"] then Some D.Boolean else None
     | Some "array" =>
       if D.object_keys source ["type";"description";"title";"items"] then
       match field "items" source with
       | Some item => option_map D.Array (parse_fuel fuel item)
       | None => None end else None
     | Some "object" =>
       if D.object_keys source ["type";"description";"title";"properties";"required";"additionalProperties"] &&
          closed (field "additionalProperties" source) then
       match field "properties" source with
       | Some (JObject properties) =>
         if unique_names (map fst properties) then
         match required_names properties (field "required" source) with
         | Some required => option_map D.Object
           (D.traverse (fun property => option_map (fun declaration =>
             (fst property,D.member (fst property) required,declaration))
             (parse_fuel fuel (snd property))) properties)
         | None => None end else None
       | _ => None end else None
     | _ => None end
   end
 | _ => None end else None end.
Definition parse := parse_fuel 256.

Theorem omitted_integer_bounds_are_natural_u32 :
 parse (JObject [("type",JString "integer")]) = Some (D.Natural 0 D.maximum_natural).
Proof. reflexivity. Qed.
Theorem maximum_only_integer_bound_is_supported : forall source maximum,
 D.natural source = Some maximum -> (maximum <=? D.maximum_natural) = true ->
 parse (JObject [("type",JString "integer");("maximum",source)]) =
 Some (D.Natural 0 maximum).
Proof.
 intros source maximum Parsed Bounded.
 unfold D.maximum_natural in Bounded.
 destruct source; try discriminate Parsed.
 cbv beta iota zeta delta -[D.natural Numbers.parse_natural N.leb].
 rewrite Parsed, Bounded.
 assert (Zero : (0 <=? maximum) = true) by (apply N.leb_le; apply N.le_0_l).
 rewrite Zero; reflexivity.
Qed.
