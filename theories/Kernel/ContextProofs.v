From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import ContextTypes Context Domain ContextUpdates JsonProofs Tasks.
Import ListNotations.

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
 inversion H; subst. apply json_comparison_is_exact in Equal.
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
Theorem unchanged_context_fields_do_not_append_a_revision_only_change : forall current patch previous bindings,
 ContextUpdates.find_snapshot (snapshot_key current) bindings = Some previous ->
 snapshot_fields current = snapshot_fields previous ->
 ContextUpdates.observation_changes (Present current patch) bindings = Some [].
Proof.
 intros current patch previous bindings Found Same.
 unfold ContextUpdates.observation_changes; rewrite Found, Same, json_comparison_reflexive; reflexivity.
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
 apply json_comparison_is_exact in Fields.
 apply context_fields_encoding_is_injective in Fields.
 exists value; repeat split; assumption.
Qed.

Theorem omitted_project_selection_preserves_the_frozen_settings : forall model settings value,
 Tasks.resolve_settings model None settings value = Some settings.
Proof. reflexivity. Qed.
