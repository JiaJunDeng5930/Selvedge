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

Theorem constructed_snapshots_obey_the_declared_source : forall definition identity revision fields snapshot,
 ContextUpdates.construct_snapshot definition identity revision fields = Some snapshot ->
 snapshot_key snapshot = ContextKey definition identity /\ snapshot_revision snapshot = revision /\
 snapshot_fields snapshot = fields /\ ContextUpdates.valid_identity definition identity = true /\
 ContextUpdates.valid_value (ContextKey definition identity) fields = true /\
 ContextUpdates.valid_definition definition = true /\ ContextUpdates.nonempty_text revision = true.
Proof.
 intros definition identity revision fields snapshot Constructed.
 unfold ContextUpdates.construct_snapshot in Constructed.
 destruct (ContextUpdates.valid_snapshot (Snapshot (ContextKey definition identity) revision fields)) eqn:Admitted; try discriminate.
 inversion Constructed; subst snapshot.
 change (ContextUpdates.nonempty_text revision && ContextUpdates.valid_definition definition &&
  ContextUpdates.valid_identity definition identity && ContextUpdates.valid_value (ContextKey definition identity) fields = true) in Admitted.
 repeat rewrite andb_true_iff in Admitted.
 destruct Admitted as [[[Revision Declared] Identity] Value].
 repeat split; assumption || reflexivity.
Qed.

Theorem registered_context_definitions_are_valid :
 forallb ContextUpdates.valid_definition Context.definitions = true.
Proof. vm_compute. reflexivity. Qed.

Theorem context_fields_roundtrip : forall fields,
 forallb (fun field => Utf8.well_formed (snd field)) fields = true ->
 ContextUpdates.parse_fields (fields_json fields) = Some fields.
Proof.
 induction fields as [|[name text] rest IH]; intro Valid; [reflexivity|].
 apply andb_true_iff in Valid as [Text Rest].
 change (Utf8.well_formed text = true) in Text.
 change ((if Utf8.well_formed text then
   option_map (cons (name,text)) (ContextUpdates.parse_fields (fields_json rest)) else None) = Some ((name,text)::rest)).
 rewrite Text.
 rewrite IH by exact Rest; reflexivity.
Qed.

Theorem constructed_context_snapshots_are_admitted : forall definition identity revision fields current,
 ContextUpdates.construct_snapshot definition identity revision fields = Some current ->
 ContextUpdates.valid_snapshot current = true.
Proof.
 intros definition identity revision fields current Constructed.
 unfold ContextUpdates.construct_snapshot in Constructed.
 destruct (ContextUpdates.valid_snapshot (Snapshot (ContextKey definition identity) revision fields)) eqn:Valid; try discriminate.
 inversion Constructed; subst current; exact Valid.
Qed.

Theorem parsed_context_definitions_obey_the_shared_definition_contract : forall source definition,
 ContextProtocol.parse_definition source = Some definition -> ContextUpdates.valid_definition definition = true.
Proof.
 intros source definition Parsed; unfold ContextProtocol.parse_definition in Parsed.
 destruct (string_field "kind" source) as [kind|]; try discriminate.
 destruct (string_field "semantics" source) as [semantics|]; try discriminate.
 destruct (ContextProtocol.parse_scope (value_or_null "scope" source)) as [scope|]; try discriminate.
 destruct (ContextProtocol.parse_observer (value_or_null "observer" source)) as [observer|]; try discriminate.
 destruct (array_field "identity" source) as [encoded_identity|]; try discriminate.
 destruct (array_field "fields" source) as [encoded_fields|]; try discriminate.
 destruct (Codec.traverse ContextProtocol.parse_identity_field encoded_identity) as [identity|]; try discriminate.
 destruct (Codec.traverse ContextProtocol.parse_value_field encoded_fields) as [fields|]; try discriminate.
 destruct (ContextUpdates.valid_definition (ContextDefinition kind semantics scope observer identity fields)) eqn:Valid; try discriminate.
 inversion Parsed; subst definition; exact Valid.
Qed.

Theorem parsed_context_snapshots_obey_the_shared_source_contract : forall source current,
 ContextProtocol.self_snapshot source = Some current -> ContextUpdates.valid_snapshot current = true.
Proof.
 intros source current Parsed; unfold ContextProtocol.self_snapshot in Parsed.
 destruct (ContextProtocol.self_key (value_or_null "key" source)); try discriminate.
 destruct (string_field "revision" source); try discriminate.
 destruct (ContextUpdates.parse_fields (value_or_null "fields" (value_or_null "value" source))); try discriminate.
 destruct (String.eqb _ _); try discriminate.
 eapply constructed_context_snapshots_are_admitted; exact Parsed.
Qed.

Theorem invalid_context_snapshots_are_rejected : forall current patches values,
 ContextUpdates.valid_snapshot current = false ->
 ContextUpdates.observation_changes (Present current patches) values = None.
Proof. intros; unfold ContextUpdates.observation_changes; rewrite H; reflexivity. Qed.

Theorem accepted_context_observations_use_admitted_snapshots : forall current patches values changes,
 ContextUpdates.observation_changes (Present current patches) values = Some changes ->
 ContextUpdates.valid_snapshot current = true.
Proof.
 intros current patches values changes Accepted.
 unfold ContextUpdates.observation_changes in Accepted.
 destruct (ContextUpdates.valid_snapshot current) eqn:Valid; [reflexivity|discriminate].
Qed.

Theorem context_history_reconstructs_each_accepted_change : forall history change,
 ContextUpdates.bindings (history ++ [ContextObservation change]) =
 ContextUpdates.apply_change change (ContextUpdates.bindings history).
Proof. intros; unfold ContextUpdates.bindings; rewrite fold_left_app; reflexivity. Qed.

Theorem context_replacement_preserves_the_reconstructed_sources : forall history replacement,
 ContextUpdates.bindings (history ++ [ContextReplacement replacement]) = ContextUpdates.bindings history.
Proof. intros; unfold ContextUpdates.bindings; rewrite fold_left_app; reflexivity. Qed.

Theorem rejecting_one_source_does_not_discard_the_other_context_changes :
 forall before after current patch values,
 ContextUpdates.valid_snapshot current = false ->
 fst (ContextUpdates.observe_all (before ++ Present current patch :: after) values) =
 fst (ContextUpdates.observe_all (before ++ after) values).
Proof.
 induction before as [|first rest IH]; intros after current patch values Invalid.
 - cbn [List.app ContextUpdates.observe_all].
   rewrite (invalid_context_snapshots_are_rejected current patch values Invalid).
   destruct (ContextUpdates.observe_all after values); reflexivity.
 - cbn [List.app ContextUpdates.observe_all].
   destruct (ContextUpdates.observation_changes first values) as [changes|].
   + pose proof (IH after current patch
       (fold_left (fun values change => ContextUpdates.apply_change change values) changes values) Invalid) as Other.
     destruct (ContextUpdates.observe_all (rest ++ Present current patch :: after)
       (fold_left (fun values change => ContextUpdates.apply_change change values) changes values)).
     destruct (ContextUpdates.observe_all (rest ++ after)
       (fold_left (fun values change => ContextUpdates.apply_change change values) changes values)).
     cbn in Other |- *; rewrite Other; reflexivity.
   + pose proof (IH after current patch values Invalid) as Other.
     destruct (ContextUpdates.observe_all (rest ++ Present current patch :: after) values).
     destruct (ContextUpdates.observe_all (rest ++ after) values).
     cbn in Other |- *; exact Other.
Qed.

Lemma replacing_text_preserves_field_names : forall fields name text,
 map fst (ContextUpdates.replace_text name text fields) = map fst fields.
Proof.
 induction fields as [|[key previous] rest IH]; intros name text; [reflexivity|].
 cbn [ContextUpdates.replace_text List.map]. destruct (String.eqb name key); cbn;
 [reflexivity|rewrite IH; reflexivity].
Qed.

Theorem accepted_field_edits_preserve_the_complete_field_schema : forall patches fields updated,
 ContextUpdates.apply_fields patches fields = Some updated -> map fst updated = map fst fields.
Proof.
 induction patches as [|patch rest IH]; intros fields updated Applied; cbn in Applied.
 - inversion Applied; reflexivity.
 - destruct (ContextUpdates.find_text (patch_field patch) fields); try discriminate.
   destruct (ContextUpdates.apply_text s (patch_edits patch)); try discriminate.
   specialize (IH _ _ Applied). rewrite IH. apply replacing_text_preserves_field_names.
Qed.

Lemma context_fields_encoding_is_injective : forall left right,
 fields_json left = fields_json right -> left = right.
Proof.
 induction left as [|[name text] rest IH]; intros right H; destruct right as [|[name' text'] rest']; cbn in H;
  try discriminate; try reflexivity.
 injection H as Hname Htext Htail. subst name' text'.
 f_equal. apply IH. unfold fields_json. now rewrite Htail.

Qed.
Theorem accepted_amendment_matches_the_observed_fields : forall current patches bindings key base revision changes,
 ContextUpdates.observation_changes (Present current patches) bindings = Some [Amend key base revision changes] ->
 exists previous,
 ContextUpdates.find_snapshot (snapshot_key current) bindings = Some previous /\
 key = snapshot_key current /\ base = snapshot_revision previous /\ revision = snapshot_revision current /\
 changes = patches /\
 ContextUpdates.apply_fields patches (snapshot_fields previous) = Some (snapshot_fields current).
Proof.
 intros current patches bindings key base revision changes H.
 unfold ContextUpdates.observation_changes in H.
 destruct (ContextUpdates.valid_snapshot current); try discriminate.
 destruct (ContextUpdates.find_snapshot (snapshot_key current) bindings) as [previous|] eqn:Found; try discriminate.
 destruct (Json.equal (fields_json (snapshot_fields current)) (fields_json (snapshot_fields previous))); try discriminate.
 destruct (negb (String.eqb (snapshot_revision current) (snapshot_revision previous)) && ContextUpdates.valid_patch (snapshot_key current) patches); try discriminate.
 destruct (ContextUpdates.apply_fields patches (snapshot_fields previous)) as [fields|] eqn:Applied; try discriminate.
 destruct (Json.equal (fields_json fields) (fields_json (snapshot_fields current))) eqn:Equal; try discriminate.
 inversion H; subst. apply equal_reflects_equality in Equal.
 apply context_fields_encoding_is_injective in Equal; subst fields.
 exists previous; repeat split; assumption || reflexivity.
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

Theorem a_stale_returned_amendment_preserves_the_current_binding : forall key base revision patches bindings current,
 ContextUpdates.find_snapshot key bindings = Some current -> snapshot_revision current <> base ->
 ContextUpdates.apply_change (Amend key base revision patches) bindings = bindings.
Proof.
 intros key base revision patches bindings current Found Stale.
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

Theorem an_accepted_patch_updates_its_captured_binding : forall bindings key base revision before after patches,
 ContextUpdates.find_snapshot key bindings = Some (Snapshot key base before) ->
 ContextUpdates.apply_fields patches before = Some after ->
 ContextUpdates.apply_change (Amend key base revision patches) bindings =
 Snapshot key revision after :: ContextUpdates.remove_snapshot key bindings.
Proof.
 intros bindings key base revision before after patches Found Applied.
 cbn [ContextUpdates.apply_change]; rewrite Found; cbn.
 rewrite String.eqb_refl, Applied; reflexivity.
Qed.
Theorem unchanged_context_fields_do_not_append_a_revision_only_change : forall current patch previous bindings,
 ContextUpdates.valid_snapshot current = true ->
 ContextUpdates.find_snapshot (snapshot_key current) bindings = Some previous ->
 snapshot_fields current = snapshot_fields previous ->
 ContextUpdates.observation_changes (Present current patch) bindings = Some [].
Proof.
 intros current patch previous bindings Valid Found Same.
 unfold ContextUpdates.observation_changes; rewrite Valid, Found, Same, equal_is_reflexive; reflexivity.
Qed.
Theorem actual_context_amendments_obey_the_shared_patch_contract : forall current patch bindings key base revision changes,
 ContextUpdates.observation_changes (Present current patch) bindings = Some [Amend key base revision changes] ->
 ContextUpdates.valid_patch key changes = true /\ base <> revision.
Proof.
 intros current patch bindings key base revision changes Accepted.
 unfold ContextUpdates.observation_changes in Accepted.
 destruct (ContextUpdates.valid_snapshot current); try discriminate.
 destruct (ContextUpdates.find_snapshot (snapshot_key current) bindings) as [previous|]; try discriminate.
 destruct (Json.equal (fields_json (snapshot_fields current)) (fields_json (snapshot_fields previous))); try discriminate.
 destruct (negb (String.eqb (snapshot_revision current) (snapshot_revision previous)) &&
   ContextUpdates.valid_patch (snapshot_key current) patch) eqn:Guard; try discriminate.
 destruct (ContextUpdates.apply_fields patch (snapshot_fields previous)); try discriminate.
 destruct (Json.equal _ _); try discriminate.
 inversion Accepted; subst. apply andb_true_iff in Guard as [Different Valid].
 split; [exact Valid|]. intros Equal; rewrite Equal, String.eqb_refl in Different; discriminate.
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
 destruct Checked as [[[Declaration Identity] Revision] Fields].
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
 field "project_id" source = None ->
 field "workspace_binding" source = None ->
 field "workspace" source = Some (JObject fields) ->
 Codec.parse_settings model (environment_profiles (world_environment value)) source base = Some selected ->
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
 field "project_id" source = None ->
 field "workspace_binding" source = None ->
 field "workspace" source = Some (JObject fields) ->
 Codec.parse_settings model (environment_profiles (world_environment value)) source base = Some selected ->
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
