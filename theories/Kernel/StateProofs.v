From Stdlib Require Import NArith.
From Selvedge.Kernel Require Import State.

Theorem identity_allocation_advances_its_supply : forall space value,
 let '(identity, allocated) := allocate_identity space value in
 identity = next_identity space value /\
 (identity < next_identity space allocated)%N.
Proof.
 intros [] value; split; try reflexivity; apply N.lt_succ_diag_r.
Qed.
