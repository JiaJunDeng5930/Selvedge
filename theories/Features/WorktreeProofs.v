From Stdlib Require Import String List NArith.
From Selvedge.Kernel Require Import Numbers Domain State.
From Selvedge.Features Require Import Domain Worktree.
Import ListNotations.
Module F:=Selvedge.Features.Domain.
(** Resource phases carry their roots, so a ready tree cannot have no root. *)
Theorem ready_tree_has_root : forall tree,
 F.worktree_state tree = F.Ready -> exists root, F.worktree_root tree = Some root.
Proof.
 intros [id source phase] ready. destruct phase; simpl in *; try discriminate.
 - destruct archived; discriminate.
 - eexists;reflexivity.
Qed.
Theorem creating_has_no_root : forall id source archived,
 F.worktree_root (F.Worktree id source (F.TreeCreating archived)) = None.
Proof. reflexivity. Qed.
(** Result validation rolls back the complete decision when a workspace is held. *)
Theorem unavailable_result_has_no_effects : forall before result,
 Worktree.guard_result before result <> result ->
 decision_world (Worktree.guard_result before result) = before /\
 decision_effects (Worktree.guard_result before result) = nil.
Proof.
 intros before result changed. unfold Worktree.guard_result in *.
 destruct (List.forallb _ _); [contradiction|split;reflexivity].
Qed.

(** An admitted background job is a live user of its frozen workspace even
    though it is not a conversation Task. *)
Theorem running_connection_job_blocks_archive : forall owner root value id job,
 In (id,job) (Selvedge.Features.Domain.sharing_jobs
   (Selvedge.Features.Domain.feature_sharing (world_features value))) ->
 Selvedge.Features.Domain.job_state job=Selvedge.Features.Domain.JobRunning ->
 Worktree.any_inside root (workspace_roots (Selvedge.Features.Domain.job_workspace job))=true ->
 Worktree.root_unused owner root value=false.
Proof.
 intros owner root value id job member running uses.
 apply Bool.not_true_is_false. intro available.
 unfold Worktree.root_unused in available. apply Bool.andb_true_iff in available as [_ jobs].
 apply forallb_forall with (x:=(id,job)) in jobs; [|exact member].
 cbn in jobs. unfold Worktree.job_uses_root in jobs. rewrite running,uses in jobs. discriminate.
Qed.
Theorem borrowed_task_blocks_archive : forall owner root value id task,
 In (id,task) (indexed (fun id task=>(id,task)) 0 (world_tasks value)) ->
 id<>owner -> Worktree.archived task=false -> Worktree.task_uses_root root task=true ->
 Worktree.root_unused owner root value=false.
Proof.
 intros owner root value id task member other live uses.
 apply Bool.not_true_is_false. intro available.
 unfold Worktree.root_unused in available. apply Bool.andb_true_iff in available as [tasks _].
 apply forallb_forall with (x:=(id,task)) in tasks; [|exact member].
 cbn in tasks. assert (different:N.eqb owner id=false) by (apply N.eqb_neq;congruence).
 rewrite different,live,uses in tasks. discriminate.
Qed.
Theorem shared_archive_emits_no_io : forall tree value root,
 Selvedge.Features.Domain.worktree_root tree=Some root ->
 Worktree.root_unused (Selvedge.Features.Domain.worktree_task tree) root value=false ->
 decision_effects (Worktree.archive_tree tree value)=[].
Proof. intros. unfold Worktree.archive_tree. rewrite H,H0. reflexivity. Qed.

Theorem owned_tree_has_priority : forall id value tree,
 Worktree.lookup id value=Some tree -> Worktree.effective id value=Some tree.
Proof. intros. unfold Worktree.effective. now rewrite H. Qed.
Theorem inherited_tree_contains_frozen_primary : forall id value task tree,
 Worktree.lookup id value=None -> Selvedge.Kernel.State.find_task id value=Some task ->
 Worktree.effective id value=Some tree ->
 exists root,F.worktree_root tree=Some root /\
 Worktree.inside root (Worktree.primary (settings_workspace (contract_settings (task_contract task))))=true.
Proof.
 intros id value task tree unowned found selected.
 unfold Worktree.effective in selected. rewrite unowned,found in selected.
 apply find_some in selected as [_ inside].
 destruct (F.worktree_root tree) as [root|] eqn:observed; [exists root;auto|discriminate].
Qed.
Theorem archiving_workspace_is_unavailable : forall space value tree root target,
 In tree (F.feature_worktrees (world_features value)) ->
 F.worktree_phase tree=F.TreeArchiving root target ->
 Worktree.any_inside root (workspace_roots space)=true ->
 Worktree.workspace_available space value=false.
Proof.
 intros space value tree root target member phase uses.
 apply Bool.not_true_is_false. intro available.
 unfold Worktree.workspace_available in available.
 apply forallb_forall with (x:=tree) in available; [|exact member].
 rewrite phase in available. unfold F.worktree_root in available. rewrite phase,uses in available. discriminate.
Qed.
