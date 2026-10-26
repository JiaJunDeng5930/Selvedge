From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json Schema SchemaProofs.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Workspace
 ModelCapabilities WorldInvariant ContextUpdates.
From Selvedge.Features Require Import WorkspaceBinding.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Lemma parsed_workspaces_are_valid : forall raw selected,
 parse_workspace raw = Some selected -> Workspace.valid_workspace selected = true.
Proof.
 intros raw selected Parsed; unfold parse_workspace in Parsed.
 destruct (Schema.decode Workspace.workspace_schema raw) as [values|]; [|discriminate].
 destruct (Workspace.valid_workspace _) eqn:Valid; [|discriminate].
 inversion Parsed; subst; exact Valid.
Qed.

Lemma catalog_members_have_valid_profiles : forall catalog selected,
 profiles_valid catalog = true -> In selected catalog -> profile_valid selected = true.
Proof.
 intros catalog selected Valid Member; unfold profiles_valid in Valid.
 apply andb_true_iff in Valid as [Profiles _].
 rewrite forallb_forall in Profiles; apply Profiles; exact Member.
Qed.

Lemma default_reviewers_have_valid_profiles : forall model catalog,
 profile_valid model = true -> profiles_valid catalog = true ->
 profile_valid (ModelCapabilities.default_reviewer model catalog) = true.
Proof.
 intros model catalog Model Catalog; unfold ModelCapabilities.default_reviewer.
 repeat first [
   match goal with |- context[find ?predicate catalog] =>
     let Found := fresh "Found" in destruct (find predicate catalog) eqn:Found end
 | match goal with |- context[if ?condition then _ else _] => destruct condition end ].
 all: try exact Model.
 all: match goal with Found : find _ ?values = Some ?reviewer |- profile_valid ?reviewer = true =>
   apply find_some in Found as [Member _];
   eapply catalog_members_have_valid_profiles; eauto end.
Qed.

Lemma parsed_approvals_are_valid : forall model catalog raw selected,
 profile_valid model = true -> profiles_valid catalog = true ->
 parse_approval model catalog raw = Some selected -> approval_valid selected = true.
Proof.
 intros model catalog raw selected Model Catalog Parsed; unfold parse_approval in Parsed.
 destruct (Schema.decode approval_schema raw) as [values|]; [|discriminate].
 destruct (String.eqb _ "full-access"); [inversion Parsed; reflexivity|].
 destruct (String.eqb _ "ask-for-approval"); [inversion Parsed; reflexivity|].
 destruct (head (tail values)) as [name|].
 - destruct (find _ catalog) as [reviewer|] eqn:Found; [|discriminate].
   destruct (ModelCapabilities.valid_reviewer_profile reviewer); [|discriminate].
   inversion Parsed; subst; apply find_some in Found as [Member _].
   eapply catalog_members_have_valid_profiles; eauto.
 - destruct (ModelCapabilities.valid_reviewer_profile _); [|discriminate].
   inversion Parsed; subst; apply default_reviewers_have_valid_profiles; assumption.
Qed.

Lemma selected_overrides_preserve_validity : forall (A : Type) (valid : A -> bool)
 (parse : json -> option A) source fallback selected,
 valid fallback = true ->
 (forall input value, parse input = Some value -> valid value = true) ->
 override_value parse source fallback = Some selected -> valid selected = true.
Proof.
 intros A valid parse [input|] fallback selected Fallback Parsed Selected.
 - eapply Parsed; exact Selected.
 - inversion Selected; subst; exact Fallback.
Qed.

Lemma inherited_guidance_is_valid : forall workspace guidance,
 valid_guidance guidance = true -> valid_guidance (inherited_guidance workspace guidance) = true.
Proof.
 intros workspace guidance Valid; unfold inherited_guidance.
 destruct (guidance_member workspace guidance); [exact Valid|reflexivity].
Qed.

Lemma settings_fields_are_valid : forall model catalog values fallback selected,
 profile_valid model = true -> profiles_valid catalog = true -> settings_valid fallback = true ->
 settings_of_fields model catalog values fallback = Some selected -> settings_valid selected = true.
Proof.
 intros model catalog values fallback selected Model Catalog Fallback Parsed.
 unfold settings_valid in Fallback; repeat rewrite andb_true_iff in Fallback.
 destruct Fallback as [[[Space Guidance] Member] Approval].
 unfold settings_of_fields in Parsed; cbn zeta in Parsed.
 set (workspace_source := head values) in *.
 set (guidance_source := head (tail (tail (tail (tail values))))) in *.
 destruct (valid_guidance (match guidance_source with Some value => value | None => JNull end)) eqn:RawGuidance; [|discriminate].
 destruct (override_value parse_workspace workspace_source (settings_workspace fallback)) as [workspace|] eqn:Workspace; [|discriminate].
 destruct (override_value (parse_sandbox_patch _) _ _) as [sandbox|] eqn:Sandbox; [|discriminate].
 destruct (override_value (parse_approval _ _) _ _) as [approval|] eqn:ApprovalSelected; [|discriminate].
 assert (WorkspaceValid : Workspace.valid_workspace workspace = true).
 { eapply selected_overrides_preserve_validity; eauto using parsed_workspaces_are_valid. }
 assert (ApprovalValid : approval_valid approval = true).
 { eapply selected_overrides_preserve_validity; eauto using parsed_approvals_are_valid. }
 assert (GuidanceValid : valid_guidance (match guidance_source with
   | None | Some JNull => inherited_guidance workspace (settings_guidance fallback) | Some guidance => guidance end) = true).
 { destruct guidance_source as [guidance|]; [destruct guidance|];
     try exact RawGuidance; apply inherited_guidance_is_valid; exact Guidance. }
 destruct (match head (tail (tail (tail (tail (tail values))))) with
   | Some observation => parse_workspace_binding observation
   | None => Some (match workspace_source with Some (JObject _) => None | _ => settings_resource fallback end) end)
   as [resource|]; [|discriminate].
 destruct (guidance_member workspace _) eqn:GuidanceMember; [|discriminate].
 inversion Parsed; subst selected; unfold settings_valid; cbn [settings_workspace settings_guidance settings_approval].
 apply andb_true_iff; split; [|exact ApprovalValid].
 apply andb_true_iff; split; [|exact GuidanceMember].
 apply andb_true_iff; split; assumption.
Qed.
Lemma parsed_settings_are_valid : forall model catalog raw fallback selected,
 profile_valid model = true -> profiles_valid catalog = true -> settings_valid fallback = true ->
 parse_settings model catalog raw fallback = Some selected -> settings_valid selected = true.
Proof.
 intros model catalog raw fallback selected Model Catalog Fallback Parsed.
 destruct raw; cbn [parse_settings] in Parsed; try discriminate.
 - inversion Parsed; subst; exact Fallback.
 - destruct (Schema.decode task_settings_schema (JObject fields)) as [values|]; [|discriminate].
   eapply settings_fields_are_valid; eauto.
Qed.

Lemma settings_fields_retain_the_project_selection : forall model catalog values fallback selected,
 settings_of_fields model catalog values fallback = Some selected ->
 settings_project selected = match head (tail (tail (tail values))) with Some id => Some id | None => settings_project fallback end.
Proof.
 intros model catalog values fallback selected Parsed; unfold settings_of_fields in Parsed; cbn zeta in Parsed.
 repeat match type of Parsed with
 | (if ?condition then _ else _) = _ => destruct condition eqn:?; try discriminate
 | (match ?input with _ => _ end) = _ => destruct input eqn:?; try discriminate
 end.
 inversion Parsed; reflexivity.
Qed.
Lemma parsed_settings_retain_the_project_selection : forall model catalog raw fallback selected,
 parse_settings model catalog raw fallback = Some selected ->
 (match field "project_id" raw with
  | None => Some (settings_project fallback)
  | Some value => option_map (@Some N) (natural value) end) = Some (settings_project selected).
Proof.
 intros model catalog raw fallback selected Parsed.
 destruct raw as [|boolean|decimal|text|items|members]; cbn [parse_settings] in Parsed; try discriminate.
 - inversion Parsed; reflexivity.
 - destruct (Schema.decode task_settings_schema (JObject members)) as [values|] eqn:Decoded; [|discriminate].
   rewrite (settings_fields_retain_the_project_selection _ _ _ _ _ Parsed).
   apply decoded_object_fields in Decoded as [source [Source Decoded]].
   inversion Source; subst source.
   do 3 apply decoded_field_tail in Decoded.
   apply decoded_field_head in Decoded.
   cbn [decode_field OmittableField field_name] in Decoded.
   cbn [field]. destruct (Json.lookup "project_id" members) as [value|].
   + destruct value as [|flag|lexeme|text|items|fields]; cbn [decode_value as_number natural option_map] in *; try discriminate.
     destruct (parse_natural lexeme) as [id|]; [|discriminate].
     injection Decoded as Project; rewrite <- Project; reflexivity.
   + injection Decoded as Project; rewrite <- Project; reflexivity.
Qed.

Lemma selecting_a_bound_workspace_preserves_settings : forall base selected before result,
 WorkspaceBinding.select_bound_workspace base selected before = Some result ->
 settings_valid selected = true -> project_binding selected before = true ->
 settings_valid result = true /\ project_binding result before = true.
Proof.
 intros base selected before result Selected Valid Binding.
 unfold WorkspaceBinding.select_bound_workspace in Selected.
 destruct (settings_resource base) as [owner|]; [|inversion Selected; subst; auto].
 destruct (WorkspaceBinding.owned owner before) as [tree|]; [|inversion Selected; subst; auto].
 destruct (WorkspaceBinding.cloud_intersects (settings_workspace selected) tree); [|inversion Selected; subst; auto].
 destruct (WorkspaceBinding.within_resource (settings_workspace selected) tree); [|discriminate].
 inversion Selected; subst; exact (conj Valid Binding).
Qed.

Lemma normalizing_settings_preserves_validity : forall selected before,
 settings_valid selected = true -> project_binding selected before = true ->
 settings_valid (WorkspaceBinding.normalize_settings selected before) = true /\
 project_binding (WorkspaceBinding.normalize_settings selected before) before = true.
Proof.
 intros selected before Valid Binding; unfold WorkspaceBinding.normalize_settings.
 destruct (WorkspaceBinding.resolve selected before) as [tree|]; [|auto].
 destruct (WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree)); [|auto].
 split; [|exact Binding].
 unfold WorkspaceBinding.cloud_settings, settings_valid in *; cbn in *.
 repeat rewrite andb_true_iff in *; tauto.
Qed.

Definition a_registry_lookup_is_a_member := @RegistryProofs.registry_lookup_is_member.

Lemma retained_tasks_have_valid_settings : forall values start state selected,
 tasks_valid start values state = true -> In selected values ->
 profile_valid (task_current_profile selected) = true /\
 settings_valid (task_current_settings selected) = true /\
 project_binding (task_current_settings selected) state = true.
Proof.
 induction values as [|first rest IH]; intros start state selected Valid Member; [contradiction|].
 cbn in Valid; apply andb_true_iff in Valid as [First Rest].
 destruct Member as [Same|Member]; [subst first|eapply IH; eauto].
 unfold task_valid in First; repeat rewrite andb_true_iff in First.
 tauto.
Qed.

Lemma valid_guidance_has_an_observed_workspace : forall source,
 valid_guidance source = true -> source = JNull \/
 exists root, string_field "workspace" source = Some root /\ Workspace.valid_path root = true.
Proof.
 intros source Valid; destruct source as [|boolean|decimal|text|items|members]; try (left; reflexivity).
 all: right; unfold valid_guidance in Valid.
 all: try discriminate.
 destruct (Schema.decode guidance_schema (JObject members)) as [decoded|] eqn:Decoded; [|discriminate].
 exists (head decoded); split.
 - apply decoded_object_fields in Decoded as [fields [Source Decoded]].
   inversion Source; subst fields. apply decoded_field_head in Decoded; exact Decoded.
 - repeat rewrite andb_true_iff in Valid; tauto.
Qed.

Lemma observed_workspace_field : forall source root,
 string_field "workspace" source = Some root -> value_or_null "workspace" source = JString root.
Proof.
 intros source root Observed; unfold string_field in Observed; unfold value_or_null.
 destruct (field "workspace" source) as [value|]; [|discriminate].
 destruct value; try discriminate; inversion Observed; reflexivity.
Qed.

Lemma environment_creation_defaults_are_valid : forall environment,
 environment_valid environment = true ->
 settings_valid (Tasks.creation_defaults environment) = true.
Proof.
 intros environment Valid.
 assert (Guidance : valid_guidance (environment_project environment) = true).
 { unfold environment_valid in Valid; repeat rewrite andb_true_iff in Valid; tauto. }
 destruct (valid_guidance_has_an_observed_workspace _ Guidance) as [Absent|[root [Observed Path]]].
 - unfold Tasks.creation_defaults; rewrite Absent; reflexivity.
 - unfold Tasks.creation_defaults; rewrite (observed_workspace_field _ _ Observed).
   unfold settings_valid; cbn [settings_workspace settings_guidance settings_approval approval_valid].
   unfold Workspace.valid_workspace; cbn; rewrite Path; cbn.
   unfold guidance_member; rewrite Observed, Guidance.
   destruct (environment_project environment); cbn; rewrite ?String.eqb_refl; reflexivity.
Qed.

Theorem fork_settings_bases_are_valid : forall origin owner before parent,
 well_formed before -> find_task owner before = Some parent ->
 profile_valid (task_current_profile parent) = true /\
 settings_valid (Tasks.fork_settings_base origin parent before) = true /\
 project_binding (Tasks.fork_settings_base origin parent before) before = true.
Proof.
 intros origin owner before parent Formed Found.
 destruct Formed as [Environment Projects Tasks Tickets Features].
 change (environment_valid (world_environment before) = true) in Environment.
 assert (Retained : profile_valid (task_current_profile parent) = true /\
   settings_valid (task_current_settings parent) = true /\
   project_binding (task_current_settings parent) before = true).
 { pose proof (retained_tasks_have_valid_settings _ _ _ parent Tasks
      (a_registry_lookup_is_a_member _ _ _ _ Found)) as Retained.
   exact Retained. }
 destruct Retained as [Profile [Settings Binding]].
 split; [exact Profile|].
 destruct origin; [exact (conj Settings Binding)|].
 unfold Tasks.fork_settings_base.
 destruct (match WorkspaceBinding.resolve (task_current_settings parent) before with
   | Some tree => WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree) | None => false end).
 - split; [|exact Binding].
   unfold settings_valid in *; cbn in *.
   repeat rewrite andb_true_iff in *; tauto.
 - split; [apply environment_creation_defaults_are_valid; exact Environment|].
   unfold Tasks.creation_defaults, project_binding.
   destruct (value_or_null "workspace" (environment_project (world_environment before))); cbn;
     try destruct (parse_workspace _); reflexivity.
Qed.

Lemma parsed_settings_keep_a_live_project_binding : forall model catalog raw fallback before selected,
 project_binding fallback before = true ->
 (forall source id, field "project_id" raw = Some source -> natural source = Some id ->
   match registry_at id (world_projects before) with
   | Some project => negb (project_deleted project) | None => false end = true) ->
 parse_settings model catalog raw fallback = Some selected -> project_binding selected before = true.
Proof.
 intros model catalog raw fallback before selected Binding Observed Parsed.
 pose proof (parsed_settings_retain_the_project_selection _ _ _ _ _ Parsed) as Project.
 unfold project_binding.
 destruct (field "project_id" raw) as [source|] eqn:Source.
 - destruct (natural source) as [id|] eqn:Id; [|discriminate].
   cbn in Project; inversion Project; subst; eapply Observed; eauto.
 - inversion Project; subst; exact Binding.
Qed.

Lemma settings_from_a_live_base_are_valid : forall model catalog raw fallback before selected,
 profile_valid model = true -> profiles_valid catalog = true ->
 settings_valid fallback = true -> project_binding fallback before = true ->
 (forall source id, field "project_id" raw = Some source -> natural source = Some id ->
   match registry_at id (world_projects before) with
   | Some project => negb (project_deleted project) | None => false end = true) ->
 (match parse_settings model catalog raw fallback with
  | Some parsed =>
    let selection := match field "workspace_binding" raw, field "workspace" raw with
     | None, Some (JObject _) => WorkspaceBinding.select_bound_workspace fallback parsed before
     | _, _ => Some parsed end in
    option_map (fun settings => WorkspaceBinding.normalize_settings settings before) selection
  | None => None end) = Some selected ->
 settings_valid selected = true /\ project_binding selected before = true.
Proof.
 intros model catalog raw fallback before selected Model Catalog Valid Binding Observed Resolved.
 destruct (parse_settings model catalog raw fallback) as [parsed|] eqn:Parsed; [|discriminate].
 assert (ParsedValid : settings_valid parsed = true) by (eapply parsed_settings_are_valid; eauto).
 assert (ParsedBinding : project_binding parsed before = true)
   by (eapply parsed_settings_keep_a_live_project_binding; eauto).
 destruct (field "workspace_binding" raw) as [observation|] eqn:Observation;
 destruct (field "workspace" raw) as [workspace|] eqn:Space;
 try (inversion Resolved; subst; apply normalizing_settings_preserves_validity; assumption).
 destruct workspace; try (inversion Resolved; subst; apply normalizing_settings_preserves_validity; assumption).
 destruct (WorkspaceBinding.select_bound_workspace fallback parsed before) as [bound|] eqn:Bound;
   [|discriminate].
 inversion Resolved; subst.
 apply normalizing_settings_preserves_validity.
 all: destruct (selecting_a_bound_workspace_preserves_settings _ _ _ _ Bound ParsedValid ParsedBinding); assumption.
Qed.

Lemma resolving_settings_preserves_validity : forall model source fallback before selected,
 profile_valid model = true -> profiles_valid (environment_profiles (world_environment before)) = true ->
 projects_valid before = true -> settings_valid fallback = true -> project_binding fallback before = true ->
 Tasks.resolve_settings model source fallback before = Some selected ->
 settings_valid selected = true /\ project_binding selected before = true.
Proof.
 intros model source fallback before selected Model Catalog Projects Fallback Binding Resolved.
 unfold Tasks.resolve_settings in Resolved.
 remember (match source with Some raw => raw | None => JNull end) as raw.
 clear Heqraw source.
 destruct (field "project_id" raw) as [project_source|] eqn:ProjectSource.
 - destruct project_source as [|boolean|decimal|text|values|fields]; try discriminate.
   all: destruct (natural _) as [id|] eqn:Id; [|discriminate].
   all: destruct (registry_at id (world_projects before)) as [project|] eqn:Project; [|discriminate].
   all: destruct (project_deleted project) eqn:Deleted; [discriminate|].
   all: eapply settings_from_a_live_base_are_valid; [exact Model|exact Catalog| | | |exact Resolved].
   + unfold projects_valid in Projects; repeat rewrite andb_true_iff in Projects.
     assert (ProjectValid : project_valid project = true).
     { destruct Projects as [[_ _] Valid]; rewrite forallb_forall in Valid.
       apply Valid; eapply a_registry_lookup_is_a_member; exact Project. }
     unfold project_valid in ProjectValid; rewrite Deleted in ProjectValid.
     unfold settings_valid in *; cbn.
     repeat rewrite andb_true_iff in *; tauto.
   + unfold project_binding; cbn; rewrite Project, Deleted; reflexivity.
   + intros encoded selected_id Encoded SelectedId.
     rewrite ProjectSource in Encoded; inversion Encoded; subst encoded.
     rewrite Id in SelectedId; inversion SelectedId; subst selected_id.
     rewrite Project, Deleted; reflexivity.
 - eapply settings_from_a_live_base_are_valid; [exact Model|exact Catalog|exact Fallback|exact Binding| |exact Resolved].
   intros encoded id Encoded; rewrite ProjectSource in Encoded; discriminate.
Qed.

Theorem resolved_fork_settings_are_valid : forall origin owner source before parent selected,
 well_formed before -> find_task owner before = Some parent ->
 Tasks.resolve_settings (task_current_profile parent) source (Tasks.fork_settings_base origin parent before) before = Some selected ->
 settings_valid selected = true /\ project_binding selected before = true.
Proof.
 intros origin owner source before parent selected Formed Found Resolved.
 destruct (fork_settings_bases_are_valid origin owner before parent Formed Found) as [Model [Base Binding]].
 destruct Formed as [Environment Projects Tasks Tickets Features].
 change (environment_valid (world_environment before) = true) in Environment.
 change (projects_valid before = true) in Projects.
 assert (Catalog : profiles_valid (environment_profiles (world_environment before)) = true).
 { unfold environment_valid in Environment; repeat rewrite andb_true_iff in Environment; tauto. }
 eapply resolving_settings_preserves_validity; eauto.
Qed.

Theorem initial_project_guidance_is_admitted : forall settings snapshot,
 Tasks.initial_project_guidance settings = Some snapshot ->
 ContextUpdates.valid_snapshot snapshot = true.
Proof.
 intros settings snapshot Initial; unfold Tasks.initial_project_guidance in Initial.
 destruct (string_field "workspace" (settings_guidance settings)); [|discriminate].
 destruct (string_field "path" (settings_guidance settings)); [|discriminate].
 destruct (string_field "revision" (settings_guidance settings)); [|discriminate].
 destruct (string_field "instructions" (settings_guidance settings)); [|discriminate].
 unfold ContextUpdates.construct_snapshot in Initial.
 destruct (ContextUpdates.valid_snapshot _) eqn:Valid; [|discriminate].
 inversion Initial; subst; exact Valid.
Qed.
