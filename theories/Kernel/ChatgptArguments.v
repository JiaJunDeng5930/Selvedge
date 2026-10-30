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
Module D := ArgumentDeclaration.
Definition properties := [
 ("command",true,D.bounded_text 32768);
 ("timeout_ms",true,D.Natural 100 1800000);
 ("max_output_length",true,D.Natural 1 8192)].
Definition declaration := D.Object properties.
Definition arguments := D.denote declaration.
Definition args_schema := D.schema declaration.
Definition admit_args := D.decode declaration.
Definition encode := D.encode declaration.
Definition valid_args source := match admit_args source with Some _ => true | None => false end.
