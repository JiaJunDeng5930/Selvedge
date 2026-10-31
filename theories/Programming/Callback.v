From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json BoundedDiagnostic.
From Selvedge.Programming Require Import Schema DeclarationFields.
From Selvedge.Programming Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module D := ArgumentDeclaration.
Module F := DeclarationFields.

Definition text_constraints bytes no_nul nonblank :=
 D.TextConstraints 0 D.maximum_natural bytes no_nul nonblank false None.
Definition text bytes no_nul := D.Text (text_constraints bytes no_nul false).

Record diagnostic_spec := Diagnostic {
 diagnostic_constraint : D.text_constraints;
 diagnostic_default : D.text_value (D.ConstrainedText diagnostic_constraint)
}.
Definition diagnostic_type spec := D.Textual (D.ConstrainedText (diagnostic_constraint spec)).
Definition diagnostic_admitted spec := D.denote (diagnostic_type spec).
Definition normalize_diagnostic spec := BoundedDiagnostic.make
 (diagnostic_constraint spec) (diagnostic_default spec).

Definition marked_fields marker (body : list F.property) := match marker with
 | Some (name,success) => F.required name (D.Const (JBool success)) :: body
 | None => body end.
Definition wire_fields marker (body : bool -> list F.property) ok :=
 marked_fields (option_map (fun '(name,success) => (name,Bool.eqb ok success)) marker) (body ok).
Inductive layout := Unmarked (fields : list F.property)
 | Marked (name : string) (success : bool) (fields : bool -> list F.property).
Definition result_fields shape ok := match shape with
 | Unmarked fields => fields | Marked _ _ fields => fields ok end.
Definition result_marker shape := match shape with
 | Unmarked _ => None | Marked name success _ => Some (name,success) end.
Definition property_names address shape ok :=
 "kind" :: F.names (F.schema_properties address ++ wire_fields (result_marker shape) (result_fields shape) ok).
Definition replies (body : bool -> list F.property) := { ok : bool & F.values (body ok) }.

(** Each callback owns its vocabulary, branches and physical result observation.
    The common constructor owns framing, coordinate fields and field uniqueness;
    extending the vocabulary never extends an enumeration or a case analysis. *)
Record callback_kind := Callback {
 callback_text : string;
 coordinates : schema;
 result_layout : layout;
 diagnostic_definition : diagnostic_spec;
 observe_result : json -> option (replies (result_fields result_layout));
 reject_result : diagnostic_admitted diagnostic_definition -> bool -> F.values (result_fields result_layout false);
 distinct_success : unique_names (property_names coordinates result_layout true) = true;
 distinct_failure : unique_names (property_names coordinates result_layout false) = true
}.
Definition declare name address shape diagnostic observe reject
 `{DistinctNames (property_names address shape true)}
 `{DistinctNames (property_names address shape false)} :=
 Callback name address shape diagnostic observe reject
  (@names_distinct _ H) (@names_distinct _ H0).
Definition payload kind := result_fields (result_layout kind).
Definition status kind := result_marker (result_layout kind).
Definition diagnostic_text kind := diagnostic_type (diagnostic_definition kind).
Definition diagnostic kind := normalize_diagnostic (diagnostic_definition kind).
Definition reply_fields kind := replies (payload kind).
Definition observed_result kind := observe_result kind.
Definition failure_payload kind := reject_result kind.
Definition wire_payload kind := wire_fields (status kind) (payload kind).
Definition full_properties kind ok := F.required "kind" (D.Const (JString (callback_text kind))) ::
 F.schema_properties (coordinates kind) ++ wire_payload kind ok.
Definition full_schema kind ok := D.Object (full_properties kind ok).
Definition mark kind ok : F.values (payload kind ok) -> F.values (wire_payload kind ok) :=
 match status kind as marker return F.values (payload kind ok) ->
   F.values (wire_fields marker (payload kind) ok) with
 | Some (name,success) => fun values => (tt,values) | None => fun values => values end.
Definition unmark kind ok : F.values (wire_payload kind ok) -> F.values (payload kind ok) :=
 match status kind as marker return F.values (wire_fields marker (payload kind) ok) ->
   F.values (payload kind ok) with
 | Some (name,success) => fun values => snd values | None => fun values => values end.
Definition full_fields kind ok (address : Schema.fields (coordinates kind)) (values : F.values (payload kind ok))
 : D.denote (full_schema kind ok).
Proof.
 refine (exist _ (tt,F.append _ _ (F.from_schema address) (mark kind ok values)) _).
 destruct ok; [exact (distinct_success kind)|exact (distinct_failure kind)].
Defined.
Definition encode kind ok address values := D.encode (full_schema kind ok) (full_fields kind ok address values).
Definition read_status kind source := match status kind with
 | Some (name,success) => option_map (fun marked => Bool.eqb marked success) (bool_field name source)
 | None => Some true end.
Definition decoded kind := { ok : bool & (Schema.fields (coordinates kind) * F.values (payload kind ok))%type }.
Definition decode_branch kind ok source :=
 option_map (fun values =>
   let '(address,fields) := F.split (F.schema_properties (coordinates kind)) (wire_payload kind ok) (snd (proj1_sig values)) in
   (F.to_schema (coordinates kind) address,unmark kind ok fields))
   (D.decode (full_schema kind ok) source).
Definition decode kind source : option (decoded kind) :=
 match read_status kind source with
 | Some ok => option_map (fun values => existT _ ok values) (decode_branch kind ok source)
 | None => None end.

Definition observe_fields body ok source : option (replies body) :=
 option_map (fun values => existT _ ok values) (F.observe (body ok) source).
Definition wrapped property description := fun _ : bool => [F.required property description].
Definition observe_wrapped property description source : option (replies (wrapped property description)) :=
 option_map (fun value => existT _ true (value,tt)) (D.decode description source).
