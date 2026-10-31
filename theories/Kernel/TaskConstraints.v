From Stdlib Require Import List Bool NArith.
From Selvedge.Foundation Require ArgumentDeclaration.

Definition fork_count_declaration := ArgumentDeclaration.Natural 1 ArgumentDeclaration.maximum_natural.
Definition fork_count := ArgumentDeclaration.denote fork_count_declaration.
Definition fork_count_value (value : fork_count) : N := proj1_sig value.
Coercion fork_count_value : fork_count >-> N.
Definition fork_count_fits (count : fork_count) (limit : N) := N.leb count limit.

Definition fork_capacities_valid (count:N)(capacities:list(option(N*N))) :=
 forallb(fun capacity=>match capacity with
 |Some(descendants,limit)=>N.leb(count+descendants)limit|None=>false end)capacities.

Definition fork_count_valid (count limit : N) :=
 ((0 <? count) && (count <=? limit))%N.

Definition fork_messages_valid (count : N) (messages : nat) :=
 Nat.eqb messages 0 || N.eqb (N.of_nat messages) count.
