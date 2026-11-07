From Stdlib Require Import NArith.
From Selvedge.Kernel Require Import State.

Theorem identity_allocation_advances_its_supply : forall space value,
 let '(identity, allocated) := allocate_identity space value in
 (next_identity space value <= identity)%N /\
 (identity < next_identity space allocated)%N.
Proof.
 intros [] value; split; auto using N.le_refl, N.lt_succ_diag_r.
Qed.
