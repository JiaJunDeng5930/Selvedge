From Stdlib Require Import String List NArith Numbers.DecimalString.
From Selvedge.Foundation Require Import Json.
From Selvedge.Foundation Require Export Numbers.
Open Scope N_scope.

Definition number_text := Selvedge.Foundation.Numbers.show_natural.
Definition number (value : N) : json := JNumber (number_text value).
Definition natural (value : json) : option N :=
 match value with JNumber source => Selvedge.Foundation.Numbers.parse_natural source | _ => None end.
Definition natural_field (key : string) (value : json) : option N :=
  match field key value with Some n => natural n | None => None end.

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
