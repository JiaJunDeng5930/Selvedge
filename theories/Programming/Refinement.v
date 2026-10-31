From Stdlib Require Import Bool.

Polymorphic Definition checked {A : Type} (admissible : A -> bool) :=
 { value : A | admissible value = true }.
Polymorphic Definition admit {A : Type} (admissible : A -> bool) (value : A) : option (checked admissible) :=
 match Bool.bool_dec (admissible value) true with
 | left proof => Some (exist _ value proof) | right _ => None end.
Polymorphic Definition strengthen {A : Type} (previous extra : A -> bool) (value : checked previous)
    : option (checked (fun value => previous value && extra value)) :=
 match Bool.bool_dec (extra (proj1_sig value)) true with
 | left proof => Some (exist _ (proj1_sig value) (proj2 (Bool.andb_true_iff _ _) (conj (proj2_sig value) proof)))
 | right _ => None end.
