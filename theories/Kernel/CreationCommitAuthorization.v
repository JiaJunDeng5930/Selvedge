From Selvedge.Kernel Require Import FeatureAuthorityProofs TaskAuthorityProofs.
From Selvedge.Kernel Require CommandResult.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonProofs KeyedListProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Domain Codec State Inputs Tasks ContextSelection
 WorldInvariant WorldInvariantProofs CommitAdmission CommitAdmissionProofs AfterHookAuthorizationProofs
 ForkAuthorizationProofs CreationResourcesProofs CreationCommit.
From Selvedge.Features Require Import Worktree.
Import ListNotations.
Module F := Selvedge.Features.Domain.

Definition an_unchanged_task_retains_authority_across_feature_updates :=
 FeatureAuthorityProofs.a_task_keeps_authority_across_other_features.

Lemma appending_a_birth_retains_all_old_task_authorities :
 forall source raw before owner old_features new_features entries suffix,
 CommitAdmission.retained_tasks_from source raw before owner old_features new_features
   entries (entries ++ suffix) = true.
Proof.
 intros; apply appending_tasks_keeps_retained_registry_authority,
   unchanged_tasks_keep_authority_across_other_features.
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
 apply keyed_retention_follows_each_lookup; intros entry Member.
 rewrite Lookup by exact Member.
 unfold CommitAdmission.retained_worktree; now rewrite !String.eqb_refl.
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

Definition an_unchanged_world_preserves_cross_state_authority :=
 FeatureAuthorityProofs.an_unchanged_world_preserves_cross_state_authority.

Theorem every_creation_candidate_preserves_retained_execution_authority :
 forall source raw request before,
 WorldInvariant.well_formed before ->
 CommitAdmission.world_evolution source raw before
   (decision_world (CreationCommit.candidate request before)) = true.
Proof.
 intros source raw request before Valid; unfold CreationCommit.candidate.
 rewrite CommandResult.appending_effects_keeps_the_committed_world.
 unfold Worktree.handle_create_result, CommandExecution.content_result.
 destruct (CommandExecution.user_content _ _) as [contents|];
   [|apply an_unchanged_world_preserves_cross_state_authority; exact Valid].
 cbn [CommandResult.bind].
 unfold Worktree.create_selected_result, Worktree.create_intent_result, Worktree.resolve_start_birth.
 destruct (CommandExecution.resolve_context_start
   (Worktree.creation_entry Worktree.ImplicitCreation None)
   (Commands.create_profile request) (Commands.create_reasoning request) contents
   (Commands.create_settings request) false None before) as [cause|start];
   [apply an_unchanged_world_preserves_cross_state_authority; exact Valid|].
 cbn [Worktree.start_allowed CommandExecution.creation_allowed].
 unfold Worktree.prepare_scoped.
 destruct (Worktree.prepare_resolved Worktree.ImplicitCreation None None start before) as [plan|reason];
   [|apply an_unchanged_world_preserves_cross_state_authority; exact Valid].
 cbn [Worktree.final_authority].
 change (CommitAdmission.world_evolution source raw before
   (decision_world (Worktree.consume_planned_start plan before)) = true).
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

Lemma every_scoped_birth_effect_has_its_inference_history_bound : forall origin before
 (birth : Worktree.start_transition origin before) after,
 Forall (CommitAdmissionProofs.inference_history_bound after) (Worktree.transition_effects birth).
Proof.
 intros origin before [[task resource] owner works frame] after.
 destruct resource; repeat constructor.
Qed.
Theorem every_creation_candidate_effect_has_its_inference_history_bound : forall request before after,
 Forall (CommitAdmissionProofs.inference_history_bound after)
   (decision_effects (CreationCommit.candidate request before)).
Proof.
 intros request before after; unfold CreationCommit.candidate.
 destruct (Worktree.handle_create_result request None before) as [birth|reason]; [|constructor].
 change (Forall (CommitAdmissionProofs.inference_history_bound after)
   (Worktree.transition_effects birth ++ [ContinueScheduling])).
 apply Forall_app; split; [apply every_scoped_birth_effect_has_its_inference_history_bound|repeat constructor].
Qed.
