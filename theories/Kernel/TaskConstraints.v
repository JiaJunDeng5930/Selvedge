From Stdlib Require Import List Bool NArith.

Definition fork_capacities_valid (count:N)(capacities:list(option(N*N))) :=
 forallb(fun capacity=>match capacity with
 |Some(descendants,limit)=>N.leb(count+descendants)limit|None=>false end)capacities.

Definition fork_count_valid (count limit : N) :=
 ((0 <? count) && (count <=? limit))%N.

Definition fork_messages_valid (count : N) (messages : nat) :=
 Nat.eqb messages 0 || N.eqb (N.of_nat messages) count.
