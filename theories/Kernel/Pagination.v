From Stdlib Require Import NArith.
From Selvedge.Programming Require ArgumentDeclaration.

(* Page limits constrain both the public queries and their model-facing tools. *)
Definition history_limit : N := 100.
Definition search_limit : N := 50.
Definition search_default : N := 20.

Definition size (maximum : N) := ArgumentDeclaration.denote (ArgumentDeclaration.Natural 1 maximum).
Definition history_default : size history_limit := exist _ history_limit eq_refl.
Definition default_search_size : size search_limit := exist _ search_default eq_refl.
Definition selected {maximum} (requested : option (size maximum)) (fallback : size maximum) :=
 match requested with Some requested => requested | None => fallback end.
