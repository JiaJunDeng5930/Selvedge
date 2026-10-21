From Selvedge.Features Require Import WorkspaceBinding.
From Selvedge.Kernel Require Import WorkspaceBackend.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonProofs.
From Selvedge.Kernel Require Import Numbers ContextTypes Context Domain Codec ContextUpdates Tasks.
Import ListNotations.

Theorem constructed_snapshots_obey_the_declared_source : forall definition identity revision fields snapshot,
 ContextUpdates.construct_snapshot definition identity revision fields = Some snapshot ->
 snapshot_key snapshot = ContextKey definition identity /\ snapshot_revision snapshot = revision /\
 snapshot_fields snapshot = fields /\ ContextUpdates.valid_identity definition identity = true /\
 ContextUpdates.valid_value (ContextKey definition identity) fields = true /\ nonempty revision = true.
Proof.
 intros definition identity revision fields snapshot Constructed.
 unfold ContextUpdates.construct_snapshot in Constructed.
 destruct (nonempty revision && ContextUpdates.valid_identity definition identity &&
  ContextUpdates.valid_value (ContextKey definition identity) fields) eqn:Admitted; try discriminate.
 inversion Constructed; subst snapshot.
 apply andb_true_iff in Admitted as [Identity Value].
 apply andb_true_iff in Identity as [Revision Identity].
 repeat split; assumption || reflexivity.
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
 ContextUpdates.remove_snapshot key bindings ++ [Snapshot key revision after].
Proof.
 intros bindings key base revision before after patches Found Applied.
 cbn [ContextUpdates.apply_change]; rewrite Found; cbn.
 rewrite String.eqb_refl, Applied; reflexivity.
Qed.
Theorem unchanged_context_fields_do_not_append_a_revision_only_change : forall current patch previous bindings,
 ContextUpdates.find_snapshot (snapshot_key current) bindings = Some previous ->
 snapshot_fields current = snapshot_fields previous ->
 ContextUpdates.observation_changes (Present current patch) bindings = Some [].
Proof.
 intros current patch previous bindings Found Same.
 unfold ContextUpdates.observation_changes; rewrite Found, Same, equal_is_reflexive; reflexivity.
Qed.
Theorem actual_context_amendments_obey_the_shared_patch_contract : forall current patch bindings key base revision changes,
 ContextUpdates.observation_changes (Present current patch) bindings = Some [Amend key base revision changes] ->
 ContextUpdates.valid_patch key changes = true /\ base <> revision.
Proof.
 intros current patch bindings key base revision changes Accepted.
 unfold ContextUpdates.observation_changes in Accepted.
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
