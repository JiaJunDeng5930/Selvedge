From Stdlib Require Import String List Bool.
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
Definition construct properties `{Schema.DistinctNames (names properties)} (values : values properties) :=
 pack properties names_distinct values.
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

(** A tagged branch owns its marker and field names. Its payload constructor
    cannot replace the marker or create a collision with it. *)
Record branch := Branch {
 tag_field : string; tag_value : json; payload_fields : list property;
 branch_distinct : Schema.unique_names (tag_field :: names payload_fields) = true
}.
Definition declare tag value properties
 `{Schema.DistinctNames (tag :: names properties)} := Branch tag value properties names_distinct.
Definition branch_fields description := required (tag_field description) (D.Const (tag_value description)) :: payload_fields description.
Definition branch_declaration description := D.Object (branch_fields description).
Definition branch_values description := values (payload_fields description).
Definition branch_arguments description (payload : branch_values description) : D.denote (branch_declaration description) :=
 exist _ (tt,payload) (branch_distinct description).
Definition branch_decode description source :=
 option_map (fun value => snd (proj1_sig value)) (D.decode (branch_declaration description) source).
Definition branch_encode description payload := D.encode (branch_declaration description) (branch_arguments description payload).
Record packet := Packet { packet_branch : branch; packet_values : branch_values packet_branch }.
Definition encode_packet value := branch_encode (packet_branch value) (packet_values value).
Record decoder (A : Type) := Decoder {
 decoder_branch : branch; decoder_construct : branch_values decoder_branch -> option A
}.
Arguments Decoder {A} _ _.
Arguments decoder_branch {A} _.
Arguments decoder_construct {A} _ _.
Fixpoint decode_cases {A} (cases : list (decoder A)) source := match cases with
 | [] => None
 | entry :: rest => match branch_decode (decoder_branch entry) source with
   | Some fields => match decoder_construct entry fields with
     | Some value => Some value | None => decode_cases rest source end
   | None => decode_cases rest source end end.

(** ABI shape is a projection of the admitted language. Opaque values remain
    opaque; runtime peers never own a second field-shape specification. *)
Fixpoint shape_kind (description : D.t) : Schema.kind := match description with
 | D.Value kind => kind | D.Textual _ => Schema.KText
 | D.Natural _ _ | D.UnboundedNatural _ => Schema.KNatural
 | D.SafeInteger _ _ => Schema.KInteger
 | D.Array item | D.BoundedArray _ _ item => Schema.KArray (shape_kind item)
 | D.Const (JString text) => Schema.KEnum text []
 | D.Const (JBool _) => Schema.KBool
 | _ => Schema.KJson end.
Definition shape properties := map (fun property => let '(name,required,description) := property in
 Schema.FieldSpec name (shape_kind description) (negb required)) properties.
