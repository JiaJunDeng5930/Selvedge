From Stdlib Require Import List.
Import ListNotations.

(* Large admitted histories exceed the JavaScript stack when a recursive take
   retains one frame per scalar. Accumulation preserves the standard firstn. *)
Fixpoint take_acc {A : Type} (count : nat) (values reversed : list A) : list A :=
 match count, values with
 | O, _ | _, [] => List.rev_append reversed []
 | S count, value :: rest => take_acc count rest (value :: reversed)
 end.
Definition take {A : Type} (count : nat) (values : list A) := take_acc count values [].
