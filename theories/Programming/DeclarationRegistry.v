From Stdlib Require Import String List.
From Selvedge.Programming Require Import Schema.

(** Public names select one declaration. Composition establishes uniqueness
    before any first-match lookup can run; each owner supplies only its value. *)
Record t {A : Type} (name : A -> string) := Declared {
 values : list A;
 unique : Schema.unique_names (map name values) = true
}.
Arguments Declared {A name}.
Arguments values {A name}.
Arguments unique {A name}.
Definition declare {A : Type} (name : A -> string) (entries : list A)
 `{distinct : Schema.DistinctNames (map name entries)} : t name :=
 Declared entries (@Schema.names_distinct (map name entries) distinct).
Definition lookup {A name} (identity : string) (registry : @t A name) :=
 find (fun entry => String.eqb identity (name entry)) (values registry).
