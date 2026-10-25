From Selvedge.Kernel Require Import TaskChangesProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json JsonProofs.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs
 ContextSelection WorldInvariant ForkPreservation ForkLineageProofs
 CommitAdmission AfterHookAuthorizationProofs.
Import ListNotations.
Open Scope list_scope.

Lemma a_task_is_its_own_retained_configuration : forall source raw before owner features value,
 CommitAdmission.retained_task source raw before owner features features value value = true.
Proof.
 intros; apply AfterHookAuthorizationProofs.retained_task_allows_operation_progress; reflexivity.
Qed.

Lemma a_manual_fork_retains_its_parents_execution_authority :
 forall source raw before owner receipt_owner features parent ticket arguments,
 Tasks.fork_parent_ready Tasks.ManualFork parent = true ->
 let invocation := Call (Tasks.manual_fork_identity ticket parent) "fork_task"%string arguments InitialAttempt in
 CommitAdmission.retained_task source raw before owner features features parent
   (with_activity WantsModel (append_history [FunctionCall invocation; ForkReceipt receipt_owner invocation 0] parent)) = true.
Proof.
 intros source raw before owner receipt_owner features parent ticket arguments Ready invocation.
 unfold Tasks.fork_parent_ready in Ready.
 destruct parent as [contract profile settings lifecycle history queued lineage side cursor consumed].
 destruct lifecycle as [phase operations|phase operations|phase operations|operations]; try discriminate.
 destruct phase; try discriminate.
 unfold CommitAdmission.retained_task.
 rewrite the_same_lineage_has_the_same_ancestors,
   the_same_creation_contract_has_the_same_configuration,
   the_same_profile_has_the_same_configuration,
   the_same_settings_have_the_same_configuration.
 assert (Prefix : ContextSelection.history_extends history
   (history ++ [FunctionCall invocation; ForkReceipt receipt_owner invocation 0]) = true).
 { apply appended_history_preserves_captured_prefix; apply the_same_history_retains_its_captured_prefix. }
 change (ContextSelection.history_extends history
   (history ++ [FunctionCall invocation; ForkReceipt receipt_owner invocation 0]) && true = true).
 rewrite Prefix; reflexivity.
Qed.

Lemma retained_task_prefix_ignores_new_births : forall source raw before owner features old next suffix,
 CommitAdmission.retained_tasks_from source raw before owner features features old next = true ->
 CommitAdmission.retained_tasks_from source raw before owner features features old (next ++ suffix) = true.
Proof.
 intros source raw before owner features old; revert owner.
 induction old as [|first rest IH]; intros owner next suffix Valid; [reflexivity|].
 destruct next as [|next remaining]; [discriminate|].
 cbn [CommitAdmission.retained_tasks_from app] in *.
 apply andb_true_iff in Valid as [Head Tail]; rewrite Head; cbn; apply IH; exact Tail.
Qed.

Lemma identical_registries_retain_every_configuration : forall source raw before owner features values,
 CommitAdmission.retained_tasks_from source raw before owner features features values values = true.
Proof.
 intros source raw before owner features values; revert owner; induction values as [|value rest IH]; intro owner; [reflexivity|].
 cbn [CommitAdmission.retained_tasks_from]; rewrite a_task_is_its_own_retained_configuration, IH; reflexivity.
Qed.

Lemma replacing_one_configuration_lifts_its_authority :
 forall source raw before owner features values selected old next,
 registry_at selected values = Some old ->
 (forall owner, CommitAdmission.retained_task source raw before owner features features old next = true) ->
 CommitAdmission.retained_tasks_from source raw before owner features features values (replace selected next values) = true.
Proof.
 intros source raw before owner features values; revert owner.
 induction values as [|first rest IH]; intros owner selected old next Found Authority; [discriminate|].
 cbn [registry_at] in Found; cbn [replace]; destruct (N.eqb selected 0).
 - inversion Found; subst first; cbn [CommitAdmission.retained_tasks_from].
   rewrite Authority, identical_registries_retain_every_configuration; reflexivity.
 - cbn [CommitAdmission.retained_tasks_from].
   rewrite a_task_is_its_own_retained_configuration; cbn. eapply IH; eassumption.
Qed.

Theorem a_constructed_fork_preserves_every_retained_execution_authority :
 forall source raw before entry owner count messages parent selected,
 find_task owner before = Some parent -> Tasks.fork_parent_ready entry parent = true ->
 CommitAdmission.retained_tasks source raw before
   (fork_candidate entry owner count messages parent selected before) = true.
Proof.
 intros source raw before entry owner count messages parent selected Parent Ready.
 unfold CommitAdmission.retained_tasks.
 pose proof (fork_candidate_keeps_the_non_task_world_frame entry owner count messages parent selected before)
   as [_ [_ [_ Features]]].
 rewrite Features, fork_candidate_registry.
 apply retained_task_prefix_ignores_new_births.
 destruct entry as [|invocation remaining].
 - cbn [fork_retained].
   eapply replacing_one_configuration_lifts_its_authority; [exact Parent|].
   intros queried; apply a_manual_fork_retains_its_parents_execution_authority; exact Ready.
 - apply identical_registries_retain_every_configuration.
Qed.

Theorem a_constructed_fork_has_its_cross_state_authority :
 forall source raw before entry owner count messages parent selected,
 WorldInvariant.well_formed before -> find_task owner before = Some parent ->
 Tasks.fork_parent_ready entry parent = true ->
 CommitAdmission.world_evolution source raw before
   (fork_candidate entry owner count messages parent selected before) = true.
Proof.
 intros source raw before entry owner count messages parent selected Valid Parent Ready.
 unfold CommitAdmission.world_evolution.
 rewrite a_constructed_fork_preserves_every_retained_execution_authority by assumption.
 pose proof (fork_candidate_keeps_the_non_task_world_frame entry owner count messages parent selected before)
   as [_ [_ [Projects Features]]].
 rewrite Projects, Features, N.leb_refl.
 rewrite (proj2 (N.leb_le _ _) (forks_never_revoke_the_existing_ticket_supply entry owner count messages parent selected before)).
 cbn.
 exact (AfterHookAuthorizationProofs.well_formed_features_admit_their_unchanged_configuration
   (WorldInvariant.world_structure before) (WorldInvariant.features_requirement before Valid)).
Qed.

Lemma actual_fork_state_is_retained_or_constructed :
 forall entry origin owner count messages requested before,
 decision_world (Tasks.fork_with_caller entry origin owner count messages requested before) = before \/
 exists parent selected,
   find_task owner before = Some parent /\ Tasks.fork_parent_ready entry parent = true /\
   decision_world (Tasks.fork_with_caller entry origin owner count messages requested before) =
     fork_candidate entry owner count messages parent selected before.
Proof.
 intros entry origin owner count messages requested before.
 rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta.
 destruct (find_task owner before) as [parent|] eqn:Parent; [|left; reflexivity].
 destruct (Tasks.fork_parent_ready entry parent &&
   TaskConstraints.fork_count_valid count (contract_max_fork (task_contract parent)) &&
   TaskConstraints.fork_messages_valid count (List.length messages) &&
   Tasks.ancestors_fit (owner :: task_lineage parent) count before) eqn:Business; [|left; reflexivity].
 destruct (Tasks.resolve_settings (task_current_profile parent) requested (Tasks.fork_settings_base origin parent before) before)
   as [selected|] eqn:Resolved; [|left; reflexivity].
 destruct (Tasks.admit_fork_selection parent before selected) as [selection|] eqn:Selection; [|left; reflexivity].
 pose proof (admitted_fork_selection_keeps_the_resolved_value _ _ _ _ Selection) as Selected; rewrite Selected.
 destruct (match entry with Tasks.ManualFork => false | Tasks.AcceptedNativeFork _ _ =>
   negb (Workspace.may_delegate selected (task_current_settings parent) && Tasks.no_resource_observation requested) end);
   [left; reflexivity|].
 right; exists parent, selected; split; [reflexivity|]; split.
 - repeat rewrite andb_true_iff in Business; tauto.
 - destruct entry; reflexivity.
Qed.

Theorem every_actual_fork_retains_or_constructs_its_cross_state_authority :
 forall source raw before entry origin owner count messages requested,
 WorldInvariant.well_formed before ->
 WorldInvariant.world_structure (decision_world (Tasks.fork_with_caller entry origin owner count messages requested before)) =
   WorldInvariant.world_structure before \/
 CommitAdmission.world_evolution source raw before
   (decision_world (Tasks.fork_with_caller entry origin owner count messages requested before)) = true.
Proof.
 intros source raw before entry origin owner count messages requested Valid.
 destruct (actual_fork_state_is_retained_or_constructed entry origin owner count messages requested before)
   as [Retained|[parent [selected [Parent [Ready Constructed]]]]].
 - left; rewrite Retained; reflexivity.
 - right; rewrite Constructed; apply a_constructed_fork_has_its_cross_state_authority; assumption.
Qed.
