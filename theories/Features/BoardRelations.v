From Stdlib Require Import String List NArith Lia.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks CommandExecution.
From Selvedge.Features Require Import Domain State Board Worktree.
Open Scope bool_scope.
Open Scope string_scope.

Lemma registry_at_lt_length : forall (A : Type) index (values : list A) value,
 registry_at index values = Some value -> (index < N.of_nat (List.length values))%N.
Proof.
 intros A index. induction index using N.peano_ind; intros values value found.
 - destruct values; cbn in found; try discriminate; cbn; lia.
 - destruct values; cbn in found; try discriminate.
   destruct (N.eqb (N.succ index) 0) eqn:zero.
   + apply N.eqb_eq in zero; lia.
   + rewrite N.pred_succ in found. apply IHindex in found. cbn. lia.
Qed.

Lemma registry_replace_selected : forall (A : Type) (values : list A) index (previous replacement : A),
 registry_at index values = Some previous ->
 registry_at index (replace index replacement values) = Some replacement.
Proof.
 intros A values. induction values as [|head rest IH]; intros index previous replacement found.
 - cbn in found; discriminate.
 - cbn in found |- *. destruct (N.eqb index 0) eqn:zero.
   + apply N.eqb_eq in zero. subst index. cbn. reflexivity.
   + cbn in found. cbn. rewrite zero. eapply IH; exact found.
Qed.

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
 { eapply registry_at_lt_length; exact slot. }
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
 { eapply registry_replace_selected; exact slot. }
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
 cbv [set]. eapply registry_replace_selected; exact found.
Qed.

Lemma board_lookup_after_append_task : forall card_id task value,
 Board.lookup card_id (Selvedge.Kernel.State.append_task task value)=Board.lookup card_id value.
Proof.
 intros. unfold Board.lookup, Board.registry, Selvedge.Kernel.State.append_task,
   Selvedge.Kernel.State.with_tasks.
 cbv [set]. reflexivity.
Qed.

Lemma board_lookup_after_create_with_defaults : forall card_id name reasoning contents settings idle fallback value,
 Board.lookup card_id
   (Selvedge.Kernel.State.decision_world
     (Selvedge.Kernel.Tasks.create_with_defaults name reasoning contents settings idle fallback value))=
 Board.lookup card_id value.
Proof.
 intros card_id name reasoning contents settings idle fallback value.
 unfold Selvedge.Kernel.Tasks.create_with_defaults.
 destruct (find_profile name (environment_profiles (world_environment value))) as [profile|];
   cbn [Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.reject]; try reflexivity.
 destruct (selected_reasoning reasoning profile) as [chosen|];
   destruct (resolve_for_profile name settings fallback value) as [resolved|];
   cbn [Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.reject]; try reflexivity.
 destruct (idle || content_nonempty contents); cbn [Selvedge.Kernel.State.decision_world
   Selvedge.Kernel.State.accept Selvedge.Kernel.State.append_task];
   [apply board_lookup_after_append_task|reflexivity].
Qed.

Lemma board_lookup_after_create_context : forall card_id name effort contents settings idle caller value,
 Board.lookup card_id
   (Selvedge.Kernel.State.decision_world
     (Selvedge.Kernel.CommandExecution.create_in_context name effort contents settings idle caller value))=
 Board.lookup card_id value.
Proof.
 intros card_id name effort contents settings idle caller value.
 unfold Selvedge.Kernel.CommandExecution.create_in_context.
 destruct caller as [caller|].
 - destruct (Selvedge.Kernel.State.find_task caller value) as [parent|];
     cbn [Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.reject]; try reflexivity.
   destruct (Selvedge.Kernel.Tasks.resolve_for_profile name settings
     (Selvedge.Kernel.Domain.task_current_settings parent) value) as [selected|];
     cbn [Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.reject]; try reflexivity.
   destruct (Selvedge.Kernel.Tasks.native_creation_allowed settings selected
     (Selvedge.Kernel.Domain.task_current_settings parent) value);
     cbn [Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.reject];
     [apply board_lookup_after_create_with_defaults|reflexivity].
 - apply board_lookup_after_create_with_defaults.
Qed.

Lemma board_lookup_after_worktree_store : forall card_id tree value,
 Board.lookup card_id (Selvedge.Features.Worktree.store tree value)=Board.lookup card_id value.
Proof.
 intros. unfold Board.lookup, Board.registry, Selvedge.Features.Worktree.store,
   Selvedge.Kernel.State.with_features, Selvedge.Features.State.with_worktrees.
 cbv [set]. reflexivity.
Qed.

Lemma board_lookup_after_worktree_initialize : forall card_id before result,
 Board.lookup card_id (Selvedge.Kernel.State.decision_world result)=Board.lookup card_id before ->
 Board.lookup card_id
   (Selvedge.Kernel.State.decision_world (Selvedge.Features.Worktree.initialize before result))=
 Board.lookup card_id before.
Proof.
 intros card_id before result unchanged.
 unfold Selvedge.Features.Worktree.initialize, Selvedge.Features.Worktree.initialize_backend.
 destruct (bool_default "ok" (Selvedge.Kernel.State.decision_reply result) false) eqn:created;
   cbn [Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.reject]; [|exact unchanged].
 cbn zeta.
 destruct (Selvedge.Kernel.State.find_task (Selvedge.Kernel.State.next_task before)
   (Selvedge.Kernel.State.decision_world result)) as [task|] eqn:found;
   cbn [Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.reject]; [|exact unchanged].
 cbn [WorkspaceBackend.cloud andb].
 destruct (negb (Workspace.valid_workspace (settings_workspace (task_current_settings (resource_task
   (Selvedge.Kernel.State.next_task before) WorkspaceBackend.Local task))) &&
   Workspace.valid_path (primary (settings_workspace (task_current_settings (resource_task
     (Selvedge.Kernel.State.next_task before) WorkspaceBackend.Local task)))) &&
   workspace_available (settings_workspace (task_current_settings (resource_task
     (Selvedge.Kernel.State.next_task before) WorkspaceBackend.Local task))) before)) eqn:space_ok;
   cbn [Selvedge.Kernel.State.decision_world Selvedge.Kernel.State.reject]; [reflexivity|].
 rewrite board_lookup_after_worktree_store, board_lookup_after_task_put.
 exact unchanged.
Qed.

Lemma board_lookup_after_create_selected : forall card_id name effort contents settings idle caller managed value,
 Board.lookup card_id
   (Selvedge.Kernel.State.decision_world
     (Selvedge.Features.Worktree.create_selected name effort contents settings idle caller managed value))=
 Board.lookup card_id value.
Proof.
 intros card_id name effort contents settings idle caller managed value.
 unfold Selvedge.Features.Worktree.create_selected.
 remember (Selvedge.Kernel.CommandExecution.create_in_context name effort contents settings idle caller value)
   as created_result eqn:created_equation.
 assert (unchanged : Board.lookup card_id (Selvedge.Kernel.State.decision_world created_result)=Board.lookup card_id value).
 { subst created_result. apply board_lookup_after_create_context. }
 destruct managed as [choice|].
 - destruct choice; cbn; [apply board_lookup_after_worktree_initialize; exact unchanged|exact unchanged].
 - destruct (Selvedge.Kernel.State.find_task (Selvedge.Kernel.State.next_task value)
     (Selvedge.Kernel.State.decision_world created_result)) as [task|] eqn:found; cbn.
   + destruct (settings_worktree (Selvedge.Kernel.Domain.task_current_settings task)); cbn;
       [apply board_lookup_after_worktree_initialize; exact unchanged|exact unchanged].
   + exact unchanged.
Qed.
