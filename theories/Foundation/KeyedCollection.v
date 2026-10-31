From Stdlib Require Import List Bool RelationClasses.
From Stdlib Require MSetWeakList.
Import ListNotations.

Module Type Entry.
 Parameter t key : Type.
 Parameter key_of : t -> key.
 Parameter key_eq_dec : forall left right : key, {left = right} + {left <> right}.
End Entry.

(** The standard library owns uniqueness. Entries are compared by their domain
    key; its list implementation preserves the first inserted value and order. *)
Module Make (Value : Entry).
 Module Equality.
  Definition t := Value.t.
  Definition eq left right := Value.key_of left = Value.key_of right.
  #[global] Instance eq_equiv : Equivalence eq.
  Proof. split; unfold eq; congruence. Qed.
  Definition eq_dec left right := Value.key_eq_dec (Value.key_of left) (Value.key_of right).
 End Equality.
 Module Collection := MSetWeakList.Make Equality.
 Definition t := Collection.t.
 Definition values := Collection.elements.
 Definition select := Collection.filter.
 Definition size := Collection.cardinal.
 Definition empty := Collection.empty.
 Fixpoint append (values : list Value.t) (current : t) : option t := match values with
  | [] => Some current
  | value::rest => if Collection.mem value current then None else append rest (Collection.add value current)
  end.
 Definition admit values := append values empty.
 Definition distinct values := fold_left (fun current value => Collection.add value current) values empty.
End Make.
