From Stdlib Require Import String List Bool.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema Arguments CommandFields.
From Selvedge.Programming Require CommandDeclarations.
From Selvedge.Kernel Require Import Commands.
Open Scope string_scope.

(** These instances select the product's current command catalogue. The shared
    declaration interpreter accepts the selected declarations explicitly. *)
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
Definition admit (observed : bool) (source : json) :=
 match string_field "op" source with
 | Some name => Selvedge.Programming.CommandDeclarations.decode_invocation
     observed Commands.command_declarations name source
 | None => None end.
Definition public_command :=
 Selvedge.Programming.CommandDeclarations.invocation false Commands.command_declarations.
Definition observed_command :=
 Selvedge.Programming.CommandDeclarations.invocation true Commands.command_declarations.
Definition admit_public := admit false.
Definition admit_observed := admit true.
Definition public_json :=
 Selvedge.Programming.CommandDeclarations.encode_invocation false Commands.command_declarations.
Definition observed_json :=
 Selvedge.Programming.CommandDeclarations.encode_invocation true Commands.command_declarations.
