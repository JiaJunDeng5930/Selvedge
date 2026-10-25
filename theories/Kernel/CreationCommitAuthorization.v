From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Domain Codec State Inputs Tasks ContextSelection
 WorldInvariant WorldInvariantProofs CommitAdmission CommitAdmissionProofs AfterHookAuthorizationProofs
 ForkAuthorizationProofs CreationResourcesProofs CreationCommit.
From Selvedge.Features Require Import Worktree.
Import ListNotations.
Module F := Selvedge.Features.Domain.

Lemma an_unchanged_task_retains_authority_across_feature_updates :
 forall source raw before owner old_features new_features task,
 CommitAdmission.retained_task source raw before owner old_features new_features task task = true.
Proof.
 intros; unfold CommitAdmission.retained_task.
 rewrite the_same_lineage_has_the_same_ancestors,
   the_same_creation_contract_has_the_same_configuration,
   the_same_profile_has_the_same_configuration,
   the_same_settings_have_the_same_configuration,
   the_same_history_retains_its_captured_prefix.
 cbn -[CommitAdmission.same_content_lists].
 destruct (task_lifecycle task) eqn:Phase; unfold CommitAdmission.same_archived_task;
   rewrite Phase; try reflexivity.
 rewrite the_same_history_retains_its_captured_prefix.
 unfold CommitAdmission.archived_suffix_valid; rewrite skipn_all; cbn -[CommitAdmission.same_content_lists].
 rewrite the_same_queued_content_is_retained; reflexivity.
Qed.

Lemma appending_a_birth_retains_all_old_task_authorities :
 forall source raw before owner old_features new_features entries suffix,
 CommitAdmission.retained_tasks_from source raw before owner old_features new_features
   entries (entries ++ suffix) = true.
Proof.
 intros source raw before owner old_features new_features entries; revert owner.
 induction entries; intros; cbn [CommitAdmission.retained_tasks_from app]; [reflexivity|].
 rewrite an_unchanged_task_retains_authority_across_feature_updates, IHentries; reflexivity.
Qed.

Lemma a_fresh_resource_retains_all_existing_resources : forall entries tree,
 NoDup (map F.worktree_task entries) ->
 ~ In (F.worktree_task tree) (map F.worktree_task entries) ->
 CommitAdmission.retained_worktrees entries (tree :: entries) = true.
Proof.
 intros entries tree Unique Fresh.
 assert (Lookup : forall entry, In entry entries ->
   CommitAdmission.worktree_list_entry (F.worktree_task entry) (tree :: entries) = Some entry).
 { intros entry Member; unfold CommitAdmission.worktree_list_entry; cbn.
   assert (Different : N.eqb (F.worktree_task entry) (F.worktree_task tree) = false).
   { apply N.eqb_neq; intro Same; apply Fresh; rewrite <- Same; apply in_map; exact Member. }
   rewrite Different.
   apply a_unique_registry_key_finds_its_own_entry; assumption. }
 assert (Retained : forall todo, (forall entry, In entry todo -> In entry entries) ->
   CommitAdmission.retained_worktrees todo (tree :: entries) = true).
 { induction todo as [|entry rest IH]; intros Member; [reflexivity|].
   cbn [CommitAdmission.retained_worktrees]; rewrite Lookup by (apply Member; left; reflexivity).
   unfold CommitAdmission.retained_worktree; rewrite !String.eqb_refl; cbn.
   apply IH; intros; apply Member; right; assumption. }
 apply Retained; auto.
Qed.

Lemma a_fresh_resource_store_preserves_feature_authority : forall before tree,
 WorldInvariant.well_formed before ->
 Worktree.lookup (F.worktree_task tree) before = None ->
 CommitAdmission.features_evolution (world_features before)
   (world_features (Worktree.store tree before)) = true.
Proof.
 intros before tree Valid Fresh.
 pose proof (WorldInvariant.features_requirement before Valid) as Features.
 pose proof (well_formed_features_admit_their_unchanged_configuration _ Features) as Same.
 assert (Unique : NoDup (map F.worktree_task (F.feature_worktrees (world_features before)))).
 { unfold WorldInvariant.features_valid, WorldInvariant.worktrees_valid in Features.
   repeat rewrite andb_true_iff in Features.
   apply unique_tickets_denotes_distinct_correlation_owners; tauto. }
 unfold Worktree.lookup in Fresh.
 pose proof (fresh_resource_filter_is_identity _ _ Fresh) as Filter.
 unfold Worktree.store, with_features, Selvedge.Features.State.with_worktrees; cbv [set]; cbn.
 unfold CommitAdmission.features_evolution in *; cbn in *.
 rewrite Filter.
 assert (Trees := a_fresh_resource_retains_all_existing_resources _ tree Unique
   (fresh_resource_owner_is_absent _ _ Fresh)).
 repeat rewrite andb_true_iff in *; tauto.
Qed.

Lemma a_birth_preserves_cross_state_authority : forall source raw before task,
 WorldInvariant.well_formed before ->
 CommitAdmission.world_evolution source raw before (append_task task before) = true.
Proof.
 intros source raw before task Valid.
 unfold CommitAdmission.world_evolution, CommitAdmission.retained_tasks.
 unfold append_task, with_tasks; cbv [set]; cbn.
 rewrite appending_a_birth_retains_all_old_task_authorities, !N.leb_refl; cbn.
 exact (well_formed_features_admit_their_unchanged_configuration _
   (WorldInvariant.features_requirement before Valid)).
Qed.

Lemma a_provisioned_birth_preserves_cross_state_authority : forall source raw before task root backend,
 WorldInvariant.well_formed before ->
 CommitAdmission.world_evolution source raw before
   (Worktree.store (F.Worktree (next_task before) root (F.TreeCreating false) backend)
     (append_task task before)) = true.
Proof.
 intros source raw before task root backend Valid.
 pose proof (a_fresh_resource_store_preserves_feature_authority before
   (F.Worktree (next_task before) root (F.TreeCreating false) backend) Valid
   (a_well_formed_world_has_no_resource_for_its_next_task before Valid)) as Features.
 unfold CommitAdmission.world_evolution, CommitAdmission.retained_tasks.
 unfold Worktree.store, with_features, Selvedge.Features.State.with_worktrees, append_task, with_tasks in *;
   cbv [set] in *; cbn in *.
 rewrite appending_a_birth_retains_all_old_task_authorities, !N.leb_refl; exact Features.
Qed.

Lemma every_planned_birth_preserves_cross_state_authority : forall source raw before (plan : Worktree.planned_start before),
 WorldInvariant.well_formed before ->
 CommitAdmission.world_evolution source raw before
   (decision_world (Worktree.consume_planned_start plan before)) = true.
Proof.
 intros source raw before [intent start resource admitted] Valid.
 unfold Worktree.consume_planned_start; cbn [Worktree.planned_task Worktree.planned_resource].
 destruct resource; cbn [accept decision_world Tasks.birth_prepared Tasks.birth_world];
   first [apply a_birth_preserves_cross_state_authority | apply a_provisioned_birth_preserves_cross_state_authority];
   exact Valid.
Qed.

Lemma an_unchanged_world_preserves_cross_state_authority : forall source raw before,
 WorldInvariant.well_formed before -> CommitAdmission.world_evolution source raw before before = true.
Proof.
 intros source raw before Valid.
 unfold CommitAdmission.world_evolution, CommitAdmission.retained_tasks.
 rewrite identical_registries_retain_every_configuration, !N.leb_refl; cbn.
 exact (well_formed_features_admit_their_unchanged_configuration _
   (WorldInvariant.features_requirement before Valid)).
Qed.

Theorem every_creation_candidate_preserves_retained_execution_authority :
 forall source raw request before,
 WorldInvariant.well_formed before ->
 CommitAdmission.world_evolution source raw before
   (decision_world (CreationCommit.candidate request before)) = true.
Proof.
 intros source raw request before Valid.
 unfold CreationCommit.candidate, Worktree.handle_create, CommandExecution.with_content.
 destruct (CommandExecution.user_content _ _) as [contents|];
   [|apply an_unchanged_world_preserves_cross_state_authority; exact Valid].
 unfold Worktree.create_selected, Worktree.create_planned, Worktree.create_intent,
   Worktree.consume_start_resolution.
 destruct (CommandExecution.resolve_context_start _ _ _ _ _ _ _ _) as [cause|start];
   [apply an_unchanged_world_preserves_cross_state_authority; exact Valid|].
 destruct (Worktree.start_allowed _ _ _ _);
   [|apply an_unchanged_world_preserves_cross_state_authority; exact Valid].
 destruct (Worktree.prepare_resolved _ _ _ _ _) as [plan|reply];
   [|cbn [decision_reply]; destruct (bool_default "ok" reply false); apply an_unchanged_world_preserves_cross_state_authority; exact Valid].
 destruct (bool_default "ok" (decision_reply (Worktree.consume_planned_start plan before)) false);
   apply every_planned_birth_preserves_cross_state_authority; exact Valid.
Qed.

Lemma every_planned_birth_effect_has_its_inference_history_bound : forall before (plan : Worktree.planned_start before) after,
 Forall (CommitAdmissionProofs.inference_history_bound after)
   (decision_effects (Worktree.consume_planned_start plan before)).
Proof.
 intros before [intent start resource admitted] after.
 unfold Worktree.consume_planned_start; cbn [Worktree.planned_task Worktree.planned_resource].
 destruct resource; repeat constructor.
Qed.

Theorem every_creation_candidate_effect_has_its_inference_history_bound : forall request before after,
 Forall (CommitAdmissionProofs.inference_history_bound after)
   (decision_effects (CreationCommit.candidate request before)).
Proof.
 intros request before after.
 unfold CreationCommit.candidate, Worktree.handle_create, CommandExecution.with_content.
 destruct (CommandExecution.user_content _ _) as [contents|]; [|repeat constructor].
 unfold Worktree.create_selected, Worktree.create_planned, Worktree.create_intent,
   Worktree.consume_start_resolution.
 destruct (CommandExecution.resolve_context_start _ _ _ _ _ _ _ _) as [cause|start]; [repeat constructor|].
 destruct (Worktree.start_allowed _ _ _ _); [|repeat constructor].
 destruct (Worktree.prepare_resolved _ _ _ _ _) as [plan|reply].
 - destruct (bool_default "ok" (decision_reply (Worktree.consume_planned_start plan before)) false); cbn.
   + apply Forall_app; split; [apply every_planned_birth_effect_has_its_inference_history_bound|repeat constructor].
   + apply every_planned_birth_effect_has_its_inference_history_bound.
 - cbn [decision_reply]; destruct (bool_default "ok" reply false); repeat constructor.
Qed.
