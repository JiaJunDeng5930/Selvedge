From Stdlib Require Import List NArith.
Import ListNotations.
(** Task identities are positions in the append-only registry. There is no
    separately stored identity that can disagree with its registry key. *)
Fixpoint registry_at {A : Type} (index : N) (values : list A) : option A :=
  match values with
  | nil => None
  | value :: rest => if N.eqb index 0 then Some value else registry_at (N.pred index) rest
  end.
Fixpoint replace {A : Type} (index : N) (value : A) (values : list A) : list A :=
  match values with
  | nil => nil
  | previous :: rest =>
      if N.eqb index 0 then value :: rest
      else previous :: replace (N.pred index) value rest
  end.

Fixpoint indexed {A B : Type} (f : N -> A -> B) (index : N) (values : list A) :=
 match values with nil => nil | value :: rest => f index value :: indexed f (N.succ index) rest end.

