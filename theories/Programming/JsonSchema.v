From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require ArgumentDeclaration.
From Selvedge.Foundation Require ExtensionSchema.

(** Extension schemas use ExtensionSchema.parse: closed objects and bounded
    natural integers. Internal arguments use their own richer language directly.
    Both execute ArgumentDeclaration.check; MCP schemas remain server-owned. *)
Definition maximum_natural := ArgumentDeclaration.maximum_natural.
Definition definition_fuel (fuel : nat) (source : json) :=
 match ExtensionSchema.parse_fuel fuel source with Some _ => true | None => false end.
Definition check_fuel (fuel : nat) (source value : json) :=
 match ExtensionSchema.parse_fuel fuel source with
 | Some declaration => ArgumentDeclaration.check declaration value | None => false end.
Definition definition := definition_fuel 256.
Definition valid := check_fuel 256.

(** Registration owns both the external schema and its compiled program. A
    tool invocation only interprets this program; it cannot replace the schema
    or repeat dialect compilation after registration. The original JSON remains
    the provider/persistence projection. *)
Record registered := Registered {
 registered_source : json;
 registered_program : ArgumentDeclaration.t;
 registered_binding : ExtensionSchema.parse registered_source = Some registered_program
}.
Definition register_decoded (source : json) (parsed : option ArgumentDeclaration.t)
 (Parsed : ExtensionSchema.parse source = parsed) : option registered :=
 match parsed as result return ExtensionSchema.parse source = result -> option registered with
 | Some declaration => fun Evidence => Some (Registered source declaration Evidence)
 | None => fun _ => None
 end Parsed.
Definition register (source : json) :=
 register_decoded source (ExtensionSchema.parse source) eq_refl.
Definition check_registered (schema : registered) (value : json) :=
 ArgumentDeclaration.check (registered_program schema) value.
Local Opaque ExtensionSchema.parse_fuel.
Theorem registration_retains_its_source : forall source schema,
 register source = Some schema -> registered_source schema = source.
Proof.
 intros source schema.
 assert (Retains : forall parsed (Evidence : ExtensionSchema.parse source = parsed),
   register_decoded source parsed Evidence = Some schema -> registered_source schema = source).
 { intros [declaration|] Evidence Accepted; inversion Accepted; reflexivity. }
 unfold register; apply Retains.
Qed.
Theorem registered_arguments_use_the_compiled_declaration : forall schema value,
 check_registered schema value = valid (registered_source schema) value.
Proof.
 intros [source program Binding] value.
 unfold check_registered, valid, check_fuel; cbn [registered_program registered_source].
 change (ArgumentDeclaration.check program value =
   match ExtensionSchema.parse source with
   | Some declaration => ArgumentDeclaration.check declaration value | None => false end).
 rewrite Binding; reflexivity.
Qed.
Theorem registration_accepts_exactly_the_extension_dialect : forall source,
 option_map registered_program (register source) = ExtensionSchema.parse source.
Proof.
 intro source.
 assert (Projects : forall parsed (Evidence : ExtensionSchema.parse source = parsed),
   option_map registered_program (register_decoded source parsed Evidence) = parsed).
 { intros [declaration|] Evidence; reflexivity. }
 unfold register; apply Projects.
Qed.

Theorem registered_schema_has_an_executable_declaration_fuel : forall fuel source,
 definition_fuel fuel source = true -> exists declaration,
 ExtensionSchema.parse_fuel fuel source = Some declaration /\
 forall value, check_fuel fuel source value = ArgumentDeclaration.check declaration value.
Proof.
 intros fuel source Registered. unfold definition_fuel in Registered.
 destruct (ExtensionSchema.parse_fuel fuel source) as [declaration|] eqn:Compiled;
 [|discriminate]. exists declaration; split; [reflexivity|].
 intros value. unfold check_fuel. rewrite Compiled. reflexivity.
Qed.
Theorem registered_schema_has_an_executable_declaration : forall source,
 definition source = true -> exists declaration,
 ExtensionSchema.parse source = Some declaration /\
 forall value, valid source value = ArgumentDeclaration.check declaration value.
Proof. exact (registered_schema_has_an_executable_declaration_fuel 256). Qed.

Theorem parsed_schema_executes_its_declaration : forall fuel source declaration value,
 ExtensionSchema.parse_fuel fuel source = Some declaration ->
 check_fuel fuel source value = ArgumentDeclaration.check declaration value.
Proof. intros fuel source declaration value Parsed. unfold check_fuel. rewrite Parsed. reflexivity. Qed.
