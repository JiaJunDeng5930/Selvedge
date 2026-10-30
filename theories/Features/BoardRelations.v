From Selvedge.Foundation Require Import RegistryProofs ReceiverProofs.
From Stdlib Require Import String List NArith Lia.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks CommandExecution.
From Selvedge.Features Require Import Domain State Board Worktree.
Open Scope bool_scope.
Open Scope string_scope.

Lemma board_lookup_after_put_selected : forall id before replacement value,
 Board.lookup id value = Some before ->
 Board.lookup id (Board.put id replacement value) = Some replacement.
Proof.
 intros id before replacement value found.
 unfold Board.lookup in found.
 destruct (registry_at id (Selvedge.Features.Domain.board_cards (Board.registry value)))
   as [stored|] eqn:slot; cbn in found; try discriminate.
 inversion found; subst stored.
 assert ((id < N.of_nat (List.length
   (Selvedge.Features.Domain.board_cards (Board.registry value))))%N) as bounded.
 { eapply Selvedge.Foundation.RegistryProofs.registry_lookup_implies_position_bound; exact slot. }
 unfold Board.registry in bounded.
 pose proof (ReceiverProofs.installed (TicketedRequest.Scoped.card_slot id) replacement
   (world_features value) ltac:(cbn; apply N.leb_le; lia)) as Installed.
 change (match registry_at id (board_cards (feature_board (world_features (Board.put id replacement value)))) with
   | Some stored => Constructor.project (@Some card) stored | None => None end = Some replacement) in Installed.
 unfold Board.lookup,Board.registry.
 destruct (registry_at id (board_cards (feature_board (world_features (Board.put id replacement value)))))
   as [[stored|]|]; exact Installed.
Qed.

Lemma board_lookup_after_task_put : forall card_id task_id task value,
 Board.lookup card_id (Selvedge.Kernel.State.put_task task_id task value) = Board.lookup card_id value.
Proof.
 intros. unfold Board.lookup, Board.registry, Selvedge.Kernel.State.put_task,
   Selvedge.Kernel.State.with_tasks.
 cbv [set]. reflexivity.
Qed.

Lemma task_lookup_after_board_put : forall card_id card task_id value,
 Selvedge.Kernel.State.find_task task_id (Board.put card_id card value) =
 Selvedge.Kernel.State.find_task task_id value.
Proof.
 intros. unfold Selvedge.Kernel.State.find_task, Board.put, Board.store,
   Selvedge.Kernel.State.with_features, Selvedge.Features.State.with_board.
 cbv [set]. reflexivity.
Qed.

Lemma task_lookup_after_put_task : forall task_id previous replacement value,
 Selvedge.Kernel.State.find_task task_id value = Some previous ->
 Selvedge.Kernel.State.find_task task_id
   (Selvedge.Kernel.State.put_task task_id replacement value) = Some replacement.
Proof.
 intros task_id previous replacement value found.
 unfold Selvedge.Kernel.State.find_task, Selvedge.Kernel.State.put_task,
   Selvedge.Kernel.State.with_tasks in *.
 cbv [set]. eapply Selvedge.Foundation.RegistryProofs.registry_replace_selected; exact found.
Qed.
