From Stdlib Require Import List Bool.
Import ListNotations.

(** An observational comparison chooses its projection explicitly. In
    particular, these combinators do not equate hidden state or proof fields. *)
Definition on {A B} (same : B -> B -> bool) (view : A -> B) (left right : A) :=
 same (view left) (view right).
Definition option_equal {A} (same : A -> A -> bool) (left right : Datatypes.option A) :=
 match left,right with None,None => true | Some first,Some second => same first second | _,_ => false end.
Fixpoint list_equal {A} (same : A -> A -> bool) (left right : Datatypes.list A) :=
 match left,right with
 | [],[] => true | first::ls,second::rs => same first second && list_equal same ls rs | _,_ => false end.
Definition all {A} (observations : Datatypes.list (A -> A -> bool)) (left right : A) :=
 fold_left (fun accepted same => accepted && same left right) observations true.
Theorem list_reflexive : forall A (same : A -> A -> bool),
 (forall value, same value value = true) -> forall values, list_equal same values values = true.
Proof. intros A same Reflexive values; induction values; cbn; [reflexivity|now rewrite Reflexive, IHvalues]. Qed.
