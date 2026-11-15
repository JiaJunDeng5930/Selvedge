From Stdlib Require Import List Bool.
Import ListNotations.

Fixpoint list {A} (same : A -> A -> bool) (left right : Datatypes.list A) : bool :=
 match left, right with
 | [], [] => true
 | x :: xs, y :: ys => same x y && list same xs ys
 | _, _ => false end.

Definition option {A} (same : A -> A -> bool) (left right : Datatypes.option A) : bool :=
 match left, right with
 | None, None => true
 | Some x, Some y => same x y
 | _, _ => false end.
