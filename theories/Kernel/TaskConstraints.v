From Stdlib Require Import Bool NArith.

Definition fork_count_valid (count limit : N) :=
 ((0 <? count) && (count <=? limit))%N.

Definition fork_messages_valid (count : N) (messages : nat) :=
 Nat.eqb messages 0 || N.eqb (N.of_nat messages) count.
