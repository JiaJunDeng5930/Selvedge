From Stdlib Require Import List.
From Selvedge.Kernel Require Import State.
Import ListNotations.

(** Maintenance adopts the next world and appends its effects, while the
    acknowledgement still belongs to the operation that started the turn. *)
Definition follow (first second : decision) :=
 Decision (decision_world second) (decision_reply first)
   (decision_effects first ++ decision_effects second).
