From Stdlib Require Import String List.
From Selvedge.Programming Require Import Schema.
From Selvedge.Programming Require ArgumentDeclaration.
Import ListNotations.

(** An admitted name selects its domain value from the same declaration.
    Extension authors provide values and spellings; name uniqueness is solved
    by the common declaration constructor. *)
Record t (A : Set) := Choices {
 spelling : A -> string;
 first : A;
 rest : list A;
 distinct : unique_names (map spelling (first :: rest)) = true
}.
Arguments spelling {A}.
Arguments first {A}.
Arguments rest {A}.
Definition declare {A : Set} (name : A -> string) (initial : A) (others : list A)
 `{DistinctNames (map name (initial :: others))} :=
 Choices A name initial others names_distinct.
Definition declaration {A} (choices : t A) := ArgumentDeclaration.Value
 (KEnum (spelling choices (first choices)) (map (spelling choices) (rest choices))).

Fixpoint select {A : Set} (name : A -> string) (choices : list A) (text : string)
 (present : In text (map name choices)) : { selected : A | name selected = text }.
Proof.
 destruct choices as [|selected remaining]; [contradiction|].
 destruct (string_dec (name selected) text) as [Same|Different].
 - exact (exist _ selected Same).
 - apply (select A name remaining text).
   destruct present as [Same|Present]; [contradiction|exact Present].
Defined.
Definition value {A} (choices : t A)
 (admitted : ArgumentDeclaration.denote (declaration choices)) : A :=
 proj1_sig (select (spelling choices) (first choices :: rest choices)
   (proj1_sig admitted) (proj2_sig admitted)).
