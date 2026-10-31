From Stdlib Require Import NArith.
From Selvedge.Foundation Require ArgumentDeclaration.
Module D := ArgumentDeclaration.

Definition declaration := D.NaturalText 0 (Some D.maximum_natural).
Definition t := D.denote declaration.
Definition value (clock : t) := proj1_sig clock.
Definition zero : t := exist _ 0%N eq_refl.
Definition observed (clock : option t) := match clock with Some value => value | None => zero end.
