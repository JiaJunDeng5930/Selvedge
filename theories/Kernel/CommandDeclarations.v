From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Arguments.
From Selvedge.Kernel Require Import Commands.
From Selvedge.Kernel Require Export CommandArguments.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition declaration_for (name : string) := find (fun declaration =>
 String.eqb name (wire_name (declared_wire declaration))) Commands.command_declarations.
Definition refine_argument (observed : bool) (name : string) (argument : argument_spec) :=
 match declaration_for name with
 | Some declaration => match find (fun field =>
   String.eqb (argument_name argument) (field_name (field_shape field)))
   (wire_fields (declared_wire declaration)) with
   | Some field => field_argument observed field argument
   | None => argument end
 | None => argument end.
Definition command_arguments_with (observed : bool) (specification : command_spec) :=
 map (refine_argument observed (command_name specification))
 (map (Commands.command_argument (command_name specification))
  (Field "op" (KEnum (command_name specification) []) ::
   filter (fun field => observed || negb (String.eqb (field_name field) "workspace_binding"))
     (command_fields specification))).
Definition command_arguments := command_arguments_with false.
Definition command_schema (specification : command_spec) := Arguments.json_schema (command_arguments specification).
Definition valid (observed : bool) (source : json) :=
 match string_field "op" source with
 | Some name => match find (fun specification => String.eqb name (command_name specification)) Commands.command_specs with
   | Some specification => Arguments.valid (command_arguments_with observed specification) source
   | None => false end
 | None => false end.
Record public_raw_command := PublicRawCommand {
 public_raw_source : json;
 public_raw_admitted : valid false public_raw_source = true
}.
Record observed_command := ObservedCommand {
 observed_source : json;
 observed_admitted : valid true observed_source = true
}.
Definition admit_public (source : json) : option public_raw_command :=
 match Bool.bool_dec (valid false source) true with
 | left proof => Some (PublicRawCommand source proof) | right _ => None end.
Definition admit_observed (source : json) : option observed_command :=
 match Bool.bool_dec (valid true source) true with
 | left proof => Some (ObservedCommand source proof) | right _ => None end.
