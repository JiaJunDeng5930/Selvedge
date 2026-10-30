From Selvedge.Kernel Require Import CallbackChangesProofs.
From Selvedge.Features Require Import WorkspaceBinding.
From Selvedge.Kernel Require Import WorkspaceBackend.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonProofs Utf8.
From Selvedge.Kernel Require Import Numbers ContextTypes Context Domain Codec ContextUpdates ContextProtocol State Tasks Callbacks LifecycleProofs.
From Selvedge.Kernel Require Import ScopedRequestProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem context_history_reconstructs_each_accepted_change : forall history change,
 ContextUpdates.bindings (history ++ [ContextObservation change]) =
 ContextUpdates.apply_change change (ContextUpdates.bindings history).
Proof. intros; unfold ContextUpdates.bindings; rewrite fold_left_app; reflexivity. Qed.

Theorem context_replacement_preserves_the_reconstructed_sources : forall history replacement,
 ContextUpdates.bindings (history ++ [ContextReplacement replacement]) = ContextUpdates.bindings history.
Proof. intros; unfold ContextUpdates.bindings; rewrite fold_left_app; reflexivity. Qed.

Theorem rejecting_one_source_does_not_discard_the_other_context_changes :
 forall before after values,
 fst (ContextUpdates.observe_all (before ++ RejectedObservation :: after) values) =
 fst (ContextUpdates.observe_all (before ++ after) values).
Proof.
 induction before as [|first rest IH]; intros after values.
 - cbn [List.app ContextUpdates.observe_all ContextUpdates.observation_changes].
   destruct (ContextUpdates.observe_all after values); reflexivity.
 - cbn [List.app ContextUpdates.observe_all].
   destruct (ContextUpdates.observation_changes first values) as [changes|].
   + pose proof (IH after (fold_left (fun values change => ContextUpdates.apply_change change values) changes values)) as Other.
     destruct (ContextUpdates.observe_all (rest ++ RejectedObservation :: after)
       (fold_left (fun values change => ContextUpdates.apply_change change values) changes values)).
     destruct (ContextUpdates.observe_all (rest ++ after)
       (fold_left (fun values change => ContextUpdates.apply_change change values) changes values)).
     cbn in Other |- *; rewrite Other; reflexivity.
   + pose proof (IH after values) as Other.
     destruct (ContextUpdates.observe_all (rest ++ RejectedObservation :: after) values).
     destruct (ContextUpdates.observe_all (rest ++ after) values).
     cbn in Other |- *; exact Other.
Qed.

Lemma context_fields_encoding_is_injective : forall left right,
 fields_json left = fields_json right -> left = right.
Proof.
 induction left as [|[name text] rest IH]; intros right H; destruct right as [|[name' text'] rest']; cbn in H;
  try discriminate; try reflexivity.
 injection H as Hname Htext Htail. subst name' text'.
 f_equal. apply IH. unfold fields_json. now rewrite Htail.

Qed.
Theorem an_observed_amendment_matches_its_baseline_and_patch : forall current patches bindings target base changes,
 ContextUpdates.observation_changes (Present current patches) bindings = Some [Amend target base changes] ->
 exists previous,
 ContextUpdates.find_snapshot (snapshot_key target) bindings = Some previous /\
 base = snapshot_revision previous /\ base <> snapshot_revision target /\
 ContextUpdates.valid_patch (snapshot_key target) changes = true /\
 ContextUpdates.apply_fields changes (snapshot_fields previous) = Some (snapshot_fields target).
Proof.
 intros current patches bindings target base changes Accepted.
 unfold ContextUpdates.observation_changes in Accepted.
 destruct (ContextUpdates.find_snapshot (snapshot_key current) bindings) as [previous|] eqn:Found; try discriminate.
 destruct (Json.equal (fields_json (snapshot_fields current)) (fields_json (snapshot_fields previous))); try discriminate.
 destruct (negb (String.eqb (snapshot_revision current) (snapshot_revision previous)) &&
   ContextUpdates.valid_patch (snapshot_key current) patches) eqn:Guard; try discriminate.
 destruct (ContextUpdates.apply_fields patches (snapshot_fields previous)) as [fields|] eqn:Applied; try discriminate.
 destruct (Json.equal (fields_json fields) (fields_json (snapshot_fields current))) eqn:Equal; try discriminate.
 inversion Accepted; subst. apply andb_true_iff in Guard as [Different Valid].
 apply equal_reflects_equality in Equal; apply context_fields_encoding_is_injective in Equal; subst fields.
 exists previous; repeat split; try assumption; try reflexivity.
 intro Same; rewrite Same,String.eqb_refl in Different; discriminate.
Qed.
Theorem absent_context_does_not_synthesize_content : forall key bindings changes,
 ContextUpdates.observation_changes (Absent key) bindings = Some changes ->
 changes = [] \/ exists revision, changes = [Remove key revision].
Proof.
 intros; cbn in H. destruct (ContextUpdates.find_snapshot key bindings); inversion H; subst;
 [right; eexists; reflexivity|left; reflexivity].
Qed.
Theorem failed_context_observation_retains_the_last_admitted_binding : forall key reason bindings,
 ContextUpdates.observation_changes (ObservationFailure key reason) bindings = Some [].
Proof. reflexivity. Qed.

Theorem a_stale_returned_amendment_preserves_the_current_binding : forall target base patches bindings current,
 ContextUpdates.find_snapshot (snapshot_key target) bindings = Some current -> snapshot_revision current <> base ->
 ContextUpdates.apply_change (Amend target base patches) bindings = bindings.
Proof.
 intros target base patches bindings current Found Stale.
 cbn [ContextUpdates.apply_change]; rewrite Found.
 apply String.eqb_neq in Stale; rewrite Stale; reflexivity.
Qed.

Theorem a_stale_returned_removal_preserves_the_current_binding : forall key base bindings current,
 ContextUpdates.find_snapshot key bindings = Some current -> snapshot_revision current <> base ->
 ContextUpdates.apply_change (Remove key base) bindings = bindings.
Proof.
 intros key base bindings current Found Stale.
 cbn [ContextUpdates.apply_change]; rewrite Found.
 apply String.eqb_neq in Stale; rewrite Stale; reflexivity.
Qed.

Theorem an_accepted_patch_installs_its_captured_target : forall bindings target previous patches,
 ContextUpdates.find_snapshot (snapshot_key target) bindings = Some previous ->
 ContextUpdates.apply_change (Amend target (snapshot_revision previous) patches) bindings =
 target :: ContextUpdates.remove_snapshot (snapshot_key target) bindings.
Proof. intros; cbn [ContextUpdates.apply_change]; rewrite H,String.eqb_refl; reflexivity. Qed.

Theorem unchanged_context_fields_do_not_append_a_revision_only_change : forall current patch previous bindings,
 ContextUpdates.find_snapshot (snapshot_key current) bindings = Some previous ->
 snapshot_fields current = snapshot_fields previous ->
 ContextUpdates.observation_changes (Present current patch) bindings = Some [].
Proof.
 intros current patch previous bindings Found Same.
 unfold ContextUpdates.observation_changes; rewrite Found,Same,equal_is_reflexive; reflexivity.
Qed.

Theorem interactive_capability_requires_the_native_revision_and_body :
 forall values revision content,
 definition_observer Context.interactive_markdown = NativeText revision content ->
 ContextUpdates.interactive_available values = true ->
 exists value, In value values /\ snapshot_revision value = revision /\
 snapshot_fields value = [("content"%string,content)].
Proof.
 intros values revision content Observer Available.
 unfold ContextUpdates.interactive_available in Available. rewrite Observer in Available.
 apply existsb_exists in Available as [value [Member Checked]].
 repeat rewrite andb_true_iff in Checked.
 destruct Checked as [[Declaration Revision] Fields].
 apply String.eqb_eq in Revision.
 apply equal_reflects_equality in Fields.
 apply context_fields_encoding_is_injective in Fields.
 exists value; repeat split; assumption.
Qed.

Theorem omitted_project_selection_preserves_environment_binding : forall model settings value,
 exists selected, Tasks.resolve_settings model None settings value = Some selected /\
 settings_workspace selected = settings_workspace settings /\
 settings_project selected = settings_project settings /\
 settings_resource selected = settings_resource settings.
Proof.
 intros model settings value.
 exists (WorkspaceBinding.normalize_settings settings value). split; [reflexivity|].
 unfold WorkspaceBinding.normalize_settings.
 destruct (WorkspaceBinding.resolve settings value) as [tree|]; [|repeat split;reflexivity].
 destruct (WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree));repeat split;reflexivity.
Qed.

Theorem an_explicit_directory_keeps_its_selected_cloud_environment :
 forall model source fields base selected value owner tree,
 project_override source = None ->
 binding_observation source = None ->
 workspace_override source = Some fields ->
 Codec.settings_of_request model (environment_profiles (world_environment value)) source base = Some selected ->
 settings_resource base = Some owner -> WorkspaceBinding.owned owner value = Some tree ->
 WorkspaceBinding.cloud_intersects (settings_workspace selected) tree = true ->
 WorkspaceBinding.within_resource (settings_workspace selected) tree = true ->
 exists resolved, Tasks.resolve_settings model (Some source) base value = Some resolved /\
 settings_workspace resolved = settings_workspace selected /\
 settings_resource resolved = Some owner /\
 settings_sandbox resolved = Sandbox WorkspaceWrite true /\
 settings_approval resolved = FullAccess.
Proof.
 intros model source fields base selected value owner tree NoProject NoObservation Explicit
   Parsed Reference Owned Intersects Inside.
 assert (Cloud : WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree) = true).
 { unfold WorkspaceBinding.cloud_intersects in Intersects.
   apply andb_true_iff in Intersects; exact (proj1 Intersects). }
 unfold Tasks.resolve_settings; cbn zeta.
 rewrite NoProject, Parsed, NoObservation, Explicit.
 unfold WorkspaceBinding.select_bound_workspace; rewrite Reference, Owned, Intersects, Inside.
 unfold WorkspaceBinding.normalize_settings, WorkspaceBinding.resolve; cbn.
 rewrite Owned, Cloud; eexists; repeat split; reflexivity.
Qed.

Theorem an_explicit_directory_cannot_mix_the_selected_cloud_with_another_environment :
 forall model source fields base selected value owner tree,
 project_override source = None ->
 binding_observation source = None ->
 workspace_override source = Some fields ->
 Codec.settings_of_request model (environment_profiles (world_environment value)) source base = Some selected ->
 settings_resource base = Some owner -> WorkspaceBinding.owned owner value = Some tree ->
 WorkspaceBinding.cloud_intersects (settings_workspace selected) tree = true ->
 WorkspaceBinding.within_resource (settings_workspace selected) tree = false ->
 Tasks.resolve_settings model (Some source) base value = None.
Proof.
 intros model source fields base selected value owner tree NoProject NoObservation Explicit
   Parsed Reference Owned Intersects Outside.
 unfold Tasks.resolve_settings; cbn zeta.
 rewrite NoProject, Parsed, NoObservation, Explicit.
 unfold WorkspaceBinding.select_bound_workspace; rewrite Reference, Owned, Intersects, Outside.
 reflexivity.
Qed.
