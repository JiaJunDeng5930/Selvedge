From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema SchemaJson Utf8.
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
Definition bounded_property (field : field_spec) :=
  let properties := kind_schema field.(field_kind) in
  JObject (match bounds field.(field_name) with Some (minimum,maximum) =>
    set_field "maximum" (JNumber (show_natural maximum))
      (set_field "minimum" (JNumber (show_natural minimum)) properties)
    | None => properties end).
Definition args_schema := object_schema (map (fun f => (f.(field_name),bounded_property f)) argument_declaration)
  (map field_name argument_declaration).
Definition bounded_number (source : json) key := match number_field key source,bounds key with
  | Some value,Some (minimum,maximum) => match parse_natural value with
    | Some value => (minimum <=? value) && (value <=? maximum) | None => false end
  | _,_ => false end.
Definition admit_args source : option (fields argument_declaration) := match Schema.decode argument_declaration source with
  | None => None
  | Some values => if bounded_number source "timeout_ms" && bounded_number source "max_output_length" &&
    match string_field "command" source with Some command =>
      negb (String.eqb command "") && Utf8.well_formed command && (N.of_nat (String.length command) <=? 32768)
    | None => false end then Some values else None end.
Definition valid_args source := match admit_args source with Some _=>true | None=>false end.
