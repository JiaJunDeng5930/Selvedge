From Selvedge.Foundation Require Import RegistryProofs.
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
 assert (N.eqb id (N.of_nat (List.length
   (Selvedge.Features.Domain.board_cards (Board.registry value)))) = false) as not_append.
 { apply N.eqb_neq. lia. }
 unfold Board.registry in not_append.
 unfold Board.lookup, Board.put, Board.store, Board.registry,
   Selvedge.Kernel.State.with_features, Selvedge.Features.State.with_board.
 rewrite not_append. cbv [set]. cbn.
 assert (selected : registry_at id
   (replace id (Some replacement)
     (Selvedge.Features.Domain.board_cards
       (Selvedge.Features.Domain.feature_board (Selvedge.Kernel.State.world_features value)))) =
   Some (Some replacement)).
 { eapply Selvedge.Foundation.RegistryProofs.registry_replace_selected; exact slot. }
 rewrite selected. reflexivity.
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

Lemma board_lookup_after_append_task : forall card_id task value,
 Board.lookup card_id (Selvedge.Kernel.State.append_task task value)=Board.lookup card_id value.
Proof.
 intros. unfold Board.lookup, Board.registry, Selvedge.Kernel.State.append_task,
   Selvedge.Kernel.State.with_tasks.
 cbv [set]. reflexivity.
Qed.

Lemma board_lookup_after_interpret_start : forall card_id plan value,
 Board.lookup card_id (decision_world (Tasks.interpret_start plan value)) = Board.lookup card_id value.
Proof.
 intros. cbn [Tasks.interpret_start Tasks.birth_start Tasks.birth_world Selvedge.Kernel.State.accept decision_world].
 apply board_lookup_after_append_task.
Qed.
Lemma board_lookup_after_create_with_defaults : forall card_id name reasoning contents settings idle fallback value,
 Board.lookup card_id
   (decision_world (Tasks.create_with_defaults name reasoning contents settings idle fallback value))=
 Board.lookup card_id value.
Proof.
 intros. unfold Tasks.create_with_defaults.
 destruct (Tasks.resolve_start (if idle then Tasks.IdleCreation else Tasks.OrdinaryCreation)
   name reasoning contents settings idle fallback value);
 [reflexivity|apply board_lookup_after_interpret_start].
Qed.
Lemma board_lookup_after_create_context : forall card_id name effort contents settings idle caller value,
 Board.lookup card_id (decision_world
   (CommandExecution.create_in_context name effort contents settings idle caller value))=
 Board.lookup card_id value.
Proof.
 intros. unfold CommandExecution.create_in_context.
 destruct (CommandExecution.resolve_context_start
   (match caller with Some _=>Tasks.NativeCreation | None=>if idle then Tasks.IdleCreation else Tasks.OrdinaryCreation end)
   name effort contents settings idle caller value) as [cause|plan]; [reflexivity|].
 destruct (CommandExecution.creation_allowed settings (Tasks.start_settings plan) caller value);
 [apply board_lookup_after_interpret_start|reflexivity].
Qed.

Lemma board_lookup_after_worktree_store : forall card_id tree value,
 Board.lookup card_id (Selvedge.Features.Worktree.store tree value)=Board.lookup card_id value.
Proof.
 intros. unfold Board.lookup, Board.registry, Selvedge.Features.Worktree.store,
   Selvedge.Kernel.State.with_features, Selvedge.Features.State.with_worktrees.
 cbv [set]. reflexivity.
Qed.

Lemma board_lookup_after_consume_planned_start : forall before card_id (plan:Worktree.planned_start before) current,
 Board.lookup card_id (decision_world (Worktree.consume_planned_start plan current)) = Board.lookup card_id current.
Proof.
 intros before card_id [intent start resource admitted] current.
 unfold Worktree.consume_planned_start, Worktree.interpret_planned_birth, Worktree.born_decision, Worktree.born_world, Worktree.born_effects, Worktree.born_identity; cbn [Worktree.planned_task Worktree.planned_resource].
 destruct resource as [|owner tree observed| |];
   cbn [Selvedge.Kernel.State.accept decision_world];
   try rewrite board_lookup_after_worktree_store;
   try apply board_lookup_after_append_task.
Qed.
Lemma board_lookup_after_create_selected : forall card_id name effort contents settings idle caller managed value,
 Board.lookup card_id (decision_world
   (Worktree.create_selected name effort contents settings idle caller managed value))=Board.lookup card_id value.
Proof.
 intros. unfold Worktree.create_selected, Worktree.create_selected_result,
   Worktree.create_intent_result, Worktree.resolve_start_birth.
 destruct (CommandExecution.resolve_context_start
   (Worktree.creation_entry (if idle then Worktree.IdleTaskCreation else Worktree.ImplicitCreation) caller)
   name effort contents settings idle caller value) as [cause|start]; [reflexivity|].
 destruct (Worktree.start_allowed settings caller value (Tasks.StartResolved start)); [|reflexivity].
 destruct (Worktree.prepare_scoped (if idle then Worktree.IdleTaskCreation else Worktree.ImplicitCreation)
   caller managed None start value) as [plan|reply]; [|reflexivity].
 unfold Worktree.creation_decision,Worktree.transition_decision,Board.lookup,Board.registry.
 cbn [accept decision_world]. rewrite Worktree.transition_preserves_board; reflexivity.
Qed.
