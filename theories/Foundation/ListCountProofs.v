From Stdlib Require Import List Lia.
From Selvedge.Foundation Require Import ListCount.

Theorem count_selected {A : Type} (test : A -> bool) (values : list A) :
 count test values = List.length (filter test values).
Proof.
 unfold count.
 assert (Total : forall seed,
   fold_left (fun total value => if test value then S total else total) values seed =
   seed + List.length (filter test values)).
 { induction values as [|value rest IH]; intro seed; cbn; [lia|].
   destruct (test value); cbn; rewrite IH; lia. }
 apply Total.
Qed.
