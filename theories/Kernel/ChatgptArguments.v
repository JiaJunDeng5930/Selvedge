From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Numbers Schema SchemaJson Utf8.
From Selvedge.Foundation Require ArgumentDeclaration.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.
Open Scope list_scope.

Module D := ArgumentDeclaration.
Definition identity_maximum : N := 4294967295.
Definition identity_declaration := D.Natural 0 identity_maximum.
Definition request_declaration := D.Text
 (D.TextConstraints 1 D.maximum_natural 128 false false false None).
Definition request_identifier := D.denote request_declaration.
Definition request_text (value : request_identifier) := proj1_sig value.
Definition default_timeout_ms : N := 120000.
Definition default_max_output_length : N := 4096.
Definition properties := [
 ("command",true,D.bounded_text 32768);
 ("timeout_ms",true,D.Natural 100 1800000);
 ("max_output_length",true,D.Natural 1 8192)].
Definition declaration := D.Object properties.
Definition arguments := D.denote declaration.
Definition args_schema := D.schema declaration.
Definition encode := D.encode declaration.
