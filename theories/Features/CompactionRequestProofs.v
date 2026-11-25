From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Programming Require TaskScope.
From Selvedge.Foundation Require Import Json Registry RegistryProofs.
From Selvedge.Foundation Require Import ComparisonProofs JsonObjectsProofs.
From Selvedge.Programming Require ArgumentDeclarationProofs Arguments.
From Selvedge.Programming Require Import OptionObservationProofs ReceiverProofs.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Programming Require Import FeatureRequest TaskScopeProofs.
From Selvedge.Features Require Import CompactionRequest.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Module S := CompactionRequest.
Module F := Selvedge.Features.Domain.
Module C := Selvedge.Features.CompactionTypes.

Local Lemma same_guidance_refl : forall value, Guidance.same value value = true.
Proof.
 intros [[[absent|[present|impossible]] Accepted]|]; cbn [Guidance.same]; try reflexivity.
 - apply String.eqb_refl.
 - destruct present as [[workspace [path [revision [instructions done]]]] Valid].
   cbn. now rewrite !String.eqb_refl.
 - destruct impossible.
Qed.

Local Lemma same_settings_refl : forall settings, S.same_settings settings settings = true.
Proof.
 intros settings; unfold S.same_settings.
 rewrite (ComparisonProofs.list_refl String.eqb String.eqb_refl).
 rewrite (ComparisonProofs.option_refl String.eqb String.eqb_refl).
 rewrite !(ComparisonProofs.option_refl N.eqb N.eqb_refl).
 rewrite !Bool.eqb_reflx, same_guidance_refl.
 destruct (sandbox_access (settings_sandbox settings)), (settings_approval settings);
   cbn; try reflexivity; now rewrite String.eqb_refl.
Qed.

Local Lemma same_measurement_profile_refl : forall model, S.same_measurement_profile model model = true.
Proof.
 intros model; unfold S.same_measurement_profile.
 rewrite JsonObjectsProofs.equivalent_is_reflexive, !String.eqb_refl.
 destruct (profile_policy model) as [|policy]; cbn [S.same_reasoning_policy]; [reflexivity|].
 rewrite !String.eqb_refl, (ComparisonProofs.list_refl String.eqb String.eqb_refl), N.eqb_refl.
 destruct (reasoning_transport_mode policy); reflexivity.
Qed.

Local Lemma same_argument_refl : forall argument,
 Arguments.same_spec JsonObjects.equivalent argument argument = true.
Proof.
 intros argument; unfold Arguments.same_spec.
 rewrite !String.eqb_refl, Bool.eqb_reflx.
 destruct (Arguments.argument_type_of argument) as [kind|declaration]; cbn.
 - destruct (Schema.kind_eq_dec kind kind); congruence.
 - apply ArgumentDeclarationProofs.same_refl, JsonObjectsProofs.equivalent_is_reflexive.
Qed.

Local Lemma same_tool_refl : forall tool, same_tool JsonObjects.equivalent tool tool = true.
Proof.
 intros tool; unfold same_tool.
 rewrite !String.eqb_refl.
 destruct (tool_origin tool);
   try rewrite (ComparisonProofs.list_refl _ same_argument_refl);
   now rewrite !JsonObjectsProofs.equivalent_is_reflexive, ?String.eqb_refl.
Qed.

Lemma unchanged_description_is_compatible : forall current before,
 S.same_description (S.capture_task current before) current before = true.
Proof.
 intros current before.
 change (S.same_measurement_profile (task_current_profile current) (task_current_profile current) &&
   S.same_settings (task_current_settings current) (task_current_settings current) &&
   Comparison.list (same_tool JsonObjects.equivalent) (Capabilities.task_tools current) (Capabilities.task_tools current) &&
   Comparison.list String.eqb (Capabilities.callable current (world_environment before))
     (Capabilities.callable current (world_environment before)) = true).
 now rewrite same_measurement_profile_refl, same_settings_refl,
   (ComparisonProofs.list_refl _ same_tool_refl),
   (ComparisonProofs.list_refl String.eqb String.eqb_refl).
Qed.

Lemma different_native_parameter_bounds_invalidate_the_description :
 forall name description program parameter documentation required minimum old_max new_max,
 old_max <> new_max ->
 let definition maximum := Tool name description
   (NativeToolSource [Arguments.Argument parameter
     (Arguments.Structured (ArgumentDeclaration.Natural minimum maximum)) required documentation] program) in
 same_tool JsonObjects.equivalent (definition old_max) (definition new_max) = false.
Proof.
 intros; unfold same_tool, Arguments.same_spec; cbn.
 rewrite !String.eqb_refl, Bool.eqb_reflx, N.eqb_refl.
 destruct (N.eqb old_max new_max) eqn:Equal; [apply N.eqb_eq in Equal; contradiction|reflexivity].
Qed.

Definition maintenance_admission owner request before :=
 match find_task owner before, S.compaction_entry owner before with
 | Some current, Some entry =>
   S.maintenance_ready_from (S.maintenance_input request) current entry before &&
     S.maintenance_replacement_ready request
 | _, _ => false end.

Lemma admitted_maintenance_has_a_selected_plan : forall before owner request current
 (Found : find_task owner before = Some current),
 maintenance_admission owner request before = true ->
 exists reference, S.maintenance_selected owner request before current Found = Some reference.
Proof.
 intros before owner request current Found Ready.
 unfold maintenance_admission in Ready; rewrite Found in Ready.
 unfold S.maintenance_selected.
 eapply observe_cases; [intros entry Stored|intro Missing].
 - rewrite Stored in Ready; unfold S.maintenance_observed,S.boolean_admission.
   destruct (Bool.bool_dec _ true) as [Eligible|Refused]; [eexists; reflexivity|contradiction].
 - rewrite Missing in Ready; discriminate.
Qed.

Theorem maintenance_context_installs_its_exact_continuation :
 forall before (request : S.maintenance_context_plan before),
 let target := S.maintenance_context_target request in
 let current := TaskScope.selected target in
 let owner := TaskScope.owner target in
 let ticket := world_next_ticket before in
 let continuation := ForMaintenance (S.maintenance_context_purpose request)
   (match task_activity current with ReadyForModel => true | _ => false end) in
 let issued := S.maintenance_observe request in
 find_task owner (decision_world issued) =
   Some (with_activity (ObservingContext ticket (List.length (task_history current)) continuation) current) /\
 decision_effects issued = [ObserveContext owner ticket current].
Proof.
 intros before request; cbn zeta.
 unfold S.maintenance_observe. cbn [allocate_identity next_identity decision_world decision_effects accept].
 split; [|reflexivity].
 let body := match goal with |- _ = Some ?current => current end in
   change (find_task (TaskScope.owner (S.maintenance_context_target request))
     (put_task (TaskScope.owner (S.maintenance_context_target request)) body
       (with_ticket (N.succ (world_next_ticket before)) before)) = Some body).
 rewrite find_task_as_list, world_tasks_updated.
 eapply registry_replace_selected. rewrite <- find_task_as_list. exact (TaskScope.observed (S.maintenance_context_target request)).
Qed.

Theorem maintenance_observation_uses_the_current_task : forall before
 (reference : TaskScope.task_reference before) purpose entry,
 S.can_observe_maintenance (TaskScope.selected reference) before = true ->
 S.maintenance_prefix_ready purpose (task_history (TaskScope.selected reference)) = true ->
 exists request, S.maintenance_context_selected reference purpose entry = Some request /\
   decision_effects (S.maintenance_observe request) =
     [ObserveContext (TaskScope.owner reference) (world_next_ticket before) (TaskScope.selected reference)].
Proof.
 intros before reference purpose entry Allowed Closed.
 unfold S.maintenance_context_selected,S.boolean_admission.
 destruct (Bool.bool_dec (S.maintenance_context_ready purpose (TaskScope.selected reference) before) true)
   as [Admitted|Refused].
 - eexists; split; reflexivity.
 - unfold S.maintenance_context_ready in Refused; rewrite Allowed,Closed in Refused; contradiction.
Qed.

Theorem unavailable_maintenance_observation_has_no_plan : forall before
 (reference : TaskScope.task_reference before) purpose entry,
 S.can_observe_maintenance (TaskScope.selected reference) before = false ->
 S.maintenance_context_selected reference purpose entry = None.
Proof.
 intros before reference purpose entry Unavailable.
 unfold S.maintenance_context_selected,S.boolean_admission.
 destruct (Bool.bool_dec (S.maintenance_context_ready purpose (TaskScope.selected reference) before) true)
   as [Admitted|Refused]; [|reflexivity].
 exfalso; unfold S.maintenance_context_ready in Admitted; rewrite Unavailable in Admitted; discriminate.
Qed.

Theorem an_open_summary_prefix_has_no_context_plan : forall before
 (reference : TaskScope.task_reference before) purpose entry,
 ContextSelection.closed_prefix (task_history (TaskScope.selected reference)) = false ->
 S.maintenance_context_selected reference (Some purpose) entry = None.
Proof.
 intros before reference purpose entry Open.
 unfold S.maintenance_context_selected,S.boolean_admission.
 destruct (Bool.bool_dec (S.maintenance_context_ready (Some purpose) (TaskScope.selected reference) before) true)
   as [Admitted|Refused]; [|reflexivity].
 exfalso; unfold S.maintenance_context_ready,S.maintenance_prefix_ready in Admitted.
 rewrite Open,andb_false_r in Admitted; discriminate.
Qed.
