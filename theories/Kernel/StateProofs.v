From Stdlib Require Import NArith List.
From Selvedge.Kernel Require Import State.

Lemma reply_preserving_fold : forall A (step : decision -> A -> decision),
 (forall current item, decision_reply (step current item) = decision_reply current) ->
 forall items current, decision_reply (fold_left step items current) = decision_reply current.
Proof.
 intros A step Preserves items; induction items as [|item rest IH]; intros current; cbn.
 - reflexivity.
 - rewrite IH, Preserves; reflexivity.
Qed.

Theorem ticket_allocation_advances_only_the_supply : forall value,
 let '(ticket, allocated) := allocate_ticket value in
 ticket = world_next_ticket value /\
 world_next_ticket allocated = N.succ ticket /\
 with_ticket (world_next_ticket value) allocated = value.
Proof. intros []; repeat split; reflexivity. Qed.
