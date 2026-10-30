From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Foundation Require ArgumentDeclaration.
Import ListNotations.
Module D := ArgumentDeclaration.

Definition property := (string * bool * D.t)%type.
Definition required (name : string) (description : D.t) : property := (name,true,description).
Definition optional (name : string) (description : D.t) : property := (name,false,description).
Definition values := D.object_values.
Definition names (properties : list property) := map (fun property => fst (fst property)) properties.
Definition pack properties (unique : Schema.unique_names (names properties) = true)
 (values : values properties) : D.denote (D.Object properties) := exist _ values unique.
Definition decode properties source := option_map (@proj1_sig _ _) (D.decode (D.Object properties) source).
Definition observe properties source := option_map (@proj1_sig _ _) (D.decode (D.OpenObject properties) source).
Definition encode properties unique fields := D.encode (D.Object properties) (pack properties unique fields).
Definition schema_properties (description : Schema.schema) :=
 map (fun field => required (field_name field) (D.Value (field_representation field))) description.
Fixpoint from_schema {description} (fields : Schema.fields description) : values (schema_properties description) :=
 match fields with
 | FNil => tt
 | FCons value rest => (value,from_schema rest) end.
Fixpoint to_schema description : values (schema_properties description) -> Schema.fields description :=
 match description as description return values (schema_properties description) -> Schema.fields description with
 | [] => fun _ => FNil
 | field :: rest => fun fields => FCons (fst fields) (to_schema rest (snd fields)) end.
Fixpoint append first second : values first -> values second -> values (first ++ second) :=
 match first as first return values first -> values second -> values (first ++ second) with
 | [] => fun _ suffix => suffix
 | (_,_,_) :: rest => fun prefix suffix => (fst prefix,append rest second (snd prefix) suffix)
 end.
Fixpoint split first second : values (first ++ second) -> values first * values second :=
 match first as first return values (first ++ second) -> values first * values second with
 | [] => fun fields => (tt,fields)
 | (_,_,_) :: rest => fun fields => let '(prefix,suffix) := split rest second (snd fields) in
   ((fst fields,prefix),suffix)
 end.
