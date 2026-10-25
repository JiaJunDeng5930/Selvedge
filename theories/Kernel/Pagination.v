From Stdlib Require Import NArith.

(* Page limits constrain both the public queries and their model-facing tools. *)
Definition history_limit : N := 100.
Definition search_limit : N := 50.
Definition search_default : N := 20.
