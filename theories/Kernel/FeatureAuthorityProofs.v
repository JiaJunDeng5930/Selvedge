From Stdlib Require Import List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State CommitAdmission AfterHookAuthorizationProofs TaskAuthorityProofs.
Module A := CommitAdmission.

Lemma a_task_keeps_authority_across_other_features : forall source raw before owner old_features next_features current,
 A.retained_task source raw before owner old_features next_features current current=true.
Proof.
 intros. unfold A.retained_task,A.same_archived_task,A.archived_suffix_valid.
 rewrite the_same_lineage_has_the_same_ancestors,
 the_same_creation_contract_has_the_same_configuration,
 the_same_profile_has_the_same_configuration,
 the_same_settings_have_the_same_configuration,
 the_same_history_retains_its_captured_prefix.
 cbn -[A.same_content_lists]. destruct (task_lifecycle current); cbn -[A.same_content_lists];
 rewrite ?the_same_history_retains_its_captured_prefix,?skipn_all,?the_same_queued_content_is_retained; reflexivity.
Qed.

Lemma unchanged_tasks_keep_authority_across_other_features : forall source raw before owner old_features next_features entries,
 A.retained_tasks_from source raw before owner old_features next_features entries entries=true.
Proof.
 intros; apply retained_task_registries_follow_lookups; intros offset current Found.
 exists current; split; [exact Found|apply a_task_keeps_authority_across_other_features].
Qed.


Lemma replacing_one_task_keeps_authority_across_other_features :
 forall source raw before first old_features next_features values owner current replacement,
 registry_at owner values = Some current ->
 (forall actual, A.retained_task source raw before actual old_features next_features current replacement = true) ->
 A.retained_tasks_from source raw before first old_features next_features values (replace owner replacement values) = true.
Proof.
 intros; eapply replacing_one_task_lifts_indexed_authority;
   [intros; apply a_task_keeps_authority_across_other_features|eassumption|auto].
Qed.

Lemma an_unchanged_world_preserves_cross_state_authority : forall source raw before,
 WorldInvariant.well_formed before -> A.world_evolution source raw before before = true.
Proof.
 intros source raw before Valid; unfold A.world_evolution,A.retained_tasks.
 rewrite unchanged_tasks_keep_authority_across_other_features,!N.leb_refl; cbn.
 exact (well_formed_features_admit_their_unchanged_configuration _
   (WorldInvariant.features_requirement before Valid)).
Qed.
