From Stdlib Require Import List.
Import ListNotations.

(** One all-or-nothing list interpretation for optional parsers. Domain modules
    may expose named aliases, but do not maintain independent recursive copies. *)
Fixpoint traverse {A B : Type} (parse : A -> option B) (values : list A) : option (list B) :=
 match values with
 | [] => Some []
 | value :: rest => match parse value with
   | Some value => option_map (cons value) (traverse parse rest)
   | None => None end
 end.
