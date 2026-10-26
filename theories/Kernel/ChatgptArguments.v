From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema SchemaJson Utf8.
From Selvedge.Foundation Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

Definition identity_maximum : N := 4294967295.
Definition identity_schema := kind_schema KNatural ++ [("maximum",JNumber (show_natural identity_maximum))].
Definition grant_declaration : schema := [Field "connection_id" KNatural;
  Field "project_ids" (KArray KNatural);Field "sandbox" KJson].
Definition default_timeout_ms : N := 120000.
Definition default_max_output_length : N := 4096.
Definition argument_declaration : schema := [Field "command" KText;Field "timeout_ms" KNatural;Field "max_output_length" KNatural].
Definition bounds key := if String.eqb key "timeout_ms" then Some (100,1800000)
  else if String.eqb key "max_output_length" then Some (1,8192) else None.
Definition field_declaration (field : field_spec) := match bounds (field_name field) with
 | Some (minimum,maximum) => ArgumentDeclaration.Natural minimum maximum
 | None => ArgumentDeclaration.of_kind (field_kind field) end.
Definition bounded_property field := ArgumentDeclaration.schema (field_declaration field).
Definition declaration := ArgumentDeclaration.Object (map (fun field =>
 (field_name field,true,field_declaration field)) argument_declaration).
Definition args_schema := ArgumentDeclaration.schema declaration.
Definition bounded_value key value := match bounds key with
 | Some (minimum,maximum) => (minimum <=? value) && (value <=? maximum) | None => false end.
Definition arguments_valid (values : fields argument_declaration) :=
 let command := head values in let values := tail values in
 bounded_value "timeout_ms" (head values) && bounded_value "max_output_length" (head (tail values)) &&
 negb (String.eqb command "") && Utf8.well_formed command && (N.of_nat (String.length command) <=? 32768).
Definition checked_arguments := { values : fields argument_declaration | arguments_valid values = true }.
Definition admit_args source := match Schema.decode argument_declaration source with
 | Some values => if arguments_valid values then Some values else None | None => None end.
Definition valid_args source := match admit_args source with Some _ => true | None => false end.
Theorem admitted_arguments_are_valid : forall source values,
 admit_args source = Some values -> arguments_valid values = true.
Proof.
 intros source values Accepted; unfold admit_args in Accepted.
 destruct (Schema.decode argument_declaration source) as [decoded|]; [|discriminate].
 destruct (arguments_valid decoded) eqn:Valid; [|discriminate].
 inversion Accepted; subst; exact Valid.
Qed.
Definition certify_arguments source (admitted : option (fields argument_declaration))
 (Accepted : admit_args source = admitted) : option checked_arguments :=
 match admitted as admitted return admit_args source = admitted -> option checked_arguments with
 | Some values => fun Accepted => Some (exist _ values (admitted_arguments_are_valid source values Accepted))
 | None => fun _ => None end Accepted.
Definition admit_arguments source := certify_arguments source (admit_args source) eq_refl.
Theorem admit_arguments_erases : forall source,
 option_map (@proj1_sig _ _) (admit_arguments source) = admit_args source.
Proof.
 intro source.
 assert (Erases : forall admitted Accepted,
   option_map (@proj1_sig _ _) (certify_arguments source admitted Accepted) = admitted).
 { intros [values|] Accepted; reflexivity. }
 unfold admit_arguments; apply Erases.
Qed.
