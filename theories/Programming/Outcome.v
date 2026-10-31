From Stdlib Require Import String List.
Import ListNotations.

Inductive outcome (A:Type) := Good (value:A) | Error (reason:string).
Arguments Good {A} _.
Arguments Error {A} _.
Definition bind {A B} (v:outcome A) (f:A->outcome B) := match v with Good x=>f x | Error e=>Error e end.
Notation "x <-? a ;; b" := (bind a (fun x=>b)) (at level 100, a at next level, right associativity).
Definition from_option {A} message (v:option A) := match v with Some x=>Good x | None=>Error message end.

Fixpoint traverse{A B}(f:A->outcome B)(xs:list A):outcome(list B):=
 match xs with []=>Good[]|x::xs=>y <-? f x;;ys <-? traverse f xs;;Good(y::ys)end.
