From Stdlib Require Import List.

Definition count {A : Type} (test : A -> bool) (values : list A) :=
 fold_left (fun total value => if test value then S total else total) values 0.
