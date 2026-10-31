From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require Import Schema Arguments.
From Selvedge.Programming Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module D := ArgumentDeclaration.

Definition from_fields := D.of_schema.
Definition natural := D.of_kind KNatural.
Definition enum (first : string) (rest : list string) := D.of_kind (KEnum first rest).

(** A field declares its internal representation and its external admission in
    one place. The observed interpretation differs only for host-owned evidence.
    Generated internal messages retain ordinary naturals; admitted messages
    retain the values admitted by the external declaration. Internal identifiers
    and counters need not belong to the public U32 wire protocol. *)
Record field_declaration := DeclareField {
 field_shape : field_spec;
 field_wire_type : bool -> option D.t;
 field_force_required : bool;
 field_host_observed : bool
}.
Definition plain (field : field_spec) := DeclareField field (fun _ => None) false false.
Definition req (name : string) (kind : kind) := plain (Field name kind).
Definition opt (name : string) (kind : kind) := plain (OmittableField name kind).
Definition nullable (name : string) (kind : kind) := plain (Field name (KOptional kind)).
Definition typed (description : D.t) (field : field_declaration) := DeclareField
 (field_shape field) (fun _ => Some description) (field_force_required field) (field_host_observed field).
Definition staged (description : bool -> D.t) (field : field_declaration) := DeclareField
 (field_shape field) (fun observed => Some (description observed)) (field_force_required field) (field_host_observed field).
Definition required (field : field_declaration) := DeclareField
 (field_shape field) (field_wire_type field) true (field_host_observed field).
Definition host_observed (field : field_declaration) := DeclareField
 (field_shape field) (field_wire_type field) (field_force_required field) true.
Definition bounded (minimum maximum : N) (field : field_declaration) := typed (D.Natural minimum maximum) field.
Record wire_command := WireCommand {
 wire_name : string;
 wire_fields : list field_declaration
}.
Definition command_shape (declaration : wire_command) :=
 Command (wire_name declaration) (map field_shape (wire_fields declaration)).
Definition field_argument (observed : bool) (declaration : field_declaration)
 (base : argument_spec) :=
 let argument := Argument (argument_name base) (argument_type_of base)
   (field_force_required declaration || argument_required base) (argument_description base) in
 match field_wire_type declaration observed with
 | Some description => Arguments.with_declaration description argument
 | None => argument end.
