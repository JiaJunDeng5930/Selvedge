From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require ArgumentDeclaration.

(** External schemas are registered only after compilation into the same finite
    argument language that executes internal declarations. Unknown assertions
    are registration errors. MCP schemas remain owned by the MCP server. *)
Definition maximum_natural := ArgumentDeclaration.maximum_natural.
Definition definition_fuel (fuel : nat) (source : json) :=
 match ArgumentDeclaration.parse_fuel fuel source with Some _ => true | None => false end.
Definition check_fuel (fuel : nat) (source value : json) :=
 match ArgumentDeclaration.parse_fuel fuel source with
 | Some declaration => ArgumentDeclaration.check declaration value | None => false end.
Definition definition := definition_fuel 256.
Definition valid := check_fuel 256.

Theorem registered_schema_has_an_executable_declaration_fuel : forall fuel source,
 definition_fuel fuel source = true -> exists declaration,
 ArgumentDeclaration.parse_fuel fuel source = Some declaration /\
 forall value, check_fuel fuel source value = ArgumentDeclaration.check declaration value.
Proof.
 intros fuel source Registered. unfold definition_fuel in Registered.
 destruct (ArgumentDeclaration.parse_fuel fuel source) as [declaration|] eqn:Compiled;
 [|discriminate]. exists declaration; split; [reflexivity|].
 intros value. unfold check_fuel. rewrite Compiled. reflexivity.
Qed.
Theorem registered_schema_has_an_executable_declaration : forall source,
 definition source = true -> exists declaration,
 ArgumentDeclaration.parse source = Some declaration /\
 forall value, valid source value = ArgumentDeclaration.check declaration value.
Proof. exact (registered_schema_has_an_executable_declaration_fuel 256). Qed.

Theorem parsed_schema_executes_its_declaration : forall fuel source declaration value,
 ArgumentDeclaration.parse_fuel fuel source = Some declaration ->
 check_fuel fuel source value = ArgumentDeclaration.check declaration value.
Proof. intros fuel source declaration value Parsed. unfold check_fuel. rewrite Parsed. reflexivity. Qed.
