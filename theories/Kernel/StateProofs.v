From Stdlib Require Import NArith List.
From Selvedge.Kernel Require Import State.

Theorem ticket_allocation_advances_only_the_supply : forall value,
 let '(ticket, allocated) := allocate_ticket value in
 ticket = world_next_ticket value /\
 world_next_ticket allocated = N.succ ticket /\
 with_ticket (world_next_ticket value) allocated = value.
Proof. intros []; repeat split; reflexivity. Qed.
