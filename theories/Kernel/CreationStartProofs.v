From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json JsonProofs.
From Selvedge.Kernel Require Import Numbers Domain Codec State Context ContextUpdates Tasks CommandExecution
 WorldInvariant GlobalGuidanceProofs ForkSettingsProofs ForkLineageProofs CreationPreservation.
From Selvedge.Features Require Import Worktree.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(* Gallina compiles the literal default pattern into character matches; this
   equation exposes the same public selection rule to subsequent proofs. *)
Lemma selected_reasoning_as_test : forall effort model,
 Tasks.selected_reasoning (Some effort) model =
 if String.eqb effort "default" then Some model else
 if match profile_policy model with
 | AdaptivePolicy _ => String.eqb effort "auto"
 | FixedReasoning => nonempty effort && negb (String.eqb effort "auto") &&
   match profile_reasoning_options model with [] => true | options => existsb (String.eqb effort) options end
 end then Some (with_reasoning effort model) else None.
Proof.
 intros effort model.
 unfold Tasks.selected_reasoning.
 destruct effort as [|a effort]; [reflexivity|].
 destruct a as [a b c d e f g h];
 destruct a,b,c,d,e,f,g,h; try reflexivity.
 do 6 (destruct effort as [|a effort]; [reflexivity|];
   destruct a as [a b c d e f g h];
   destruct a,b,c,d,e,f,g,h; try reflexivity).
 destruct effort; reflexivity.
Qed.

Lemma selected_reasoning_preserves_profile_validity : forall effort model chosen,
 profile_valid model = true -> Tasks.selected_reasoning effort model = Some chosen ->
 profile_valid chosen = true.
Proof.
 intros [effort|] model chosen Valid Selected; [|inversion Selected; subst; exact Valid].
 rewrite selected_reasoning_as_test in Selected.
 destruct (String.eqb effort "default") eqn:Default; [inversion Selected; subst; exact Valid|].
 unfold profile_valid in Valid.
 destruct (parse_profile (profile_metadata model)) as [original|] eqn:Original; [|discriminate].
 repeat rewrite andb_true_iff in Valid.
 destruct Valid as [[[[[Key Provider] Model] Options] Policy] Reasoning].
 unfold same_values in Options; apply JsonProofs.equal_reflects_equality in Options.
 injection Options as Options.
 assert (SameOptions : profile_reasoning_options model = profile_reasoning_options original).
 { clear Selected; revert Options; generalize (profile_reasoning_options original);
   induction (profile_reasoning_options model) as [|x xs IH]; intros [|y ys] Equal;
     cbn in Equal; try discriminate; [reflexivity|].
   injection Equal as Head Tail; subst y; f_equal; apply IH; exact Tail. }
 destruct (profile_policy model) eqn:ModelPolicy;
 destruct (profile_policy original) eqn:OriginalPolicy;
 try (cbn [reasoning_policy_json Json.equal] in Policy; discriminate).
 all: match type of Selected with (if ?allowed then _ else _) = _ =>
   destruct allowed eqn:Allowed; [|discriminate] end.
 all: inversion Selected; subst chosen; unfold profile_valid;
   cbn [with_reasoning profile_metadata profile_key profile_provider profile_model profile_reasoning_options profile_policy profile_reasoning];
   rewrite Original, Key, Provider, Model;
   cbn [profile_key profile_provider profile_model profile_reasoning_options profile_policy profile_reasoning] in *;
   rewrite SameOptions; try rewrite SameOptions in Allowed.
 all: rewrite selected_reasoning_as_test, Default, OriginalPolicy;
   try rewrite SameOptions; try rewrite Allowed.
 all: rewrite ModelPolicy; cbn [with_reasoning profile_reasoning];
   rewrite String.eqb_refl; unfold same_values;
   rewrite JsonProofs.equal_is_reflexive; rewrite Policy; reflexivity.
Qed.

Lemma initial_introductions_retain_admitted_context : forall history bindings,
 Forall (fun entry => match entry with
   | ContextObservation (Introduce snapshot) => ContextUpdates.valid_snapshot snapshot = true
   | ContextObservation _ => False | _ => True end) history ->
 forallb ContextUpdates.valid_snapshot bindings = true ->
 forallb ContextUpdates.valid_snapshot
   (fold_left (fun values message => match message with
     | ContextObservation change => ContextUpdates.apply_change change values | _ => values end)
     history bindings) = true.
Proof.
 intros history; induction history as [|entry rest IH]; intros bindings Entries Valid; [exact Valid|].
 inversion Entries as [|? ? First Tail]; subst.
 cbn [fold_left]; apply IH; [exact Tail|].
 destruct entry; try exact Valid.
 match type of First with match ?change with _ => _ end => destruct change end; try contradiction.
 cbn [ContextUpdates.apply_change forallb]; rewrite First.
 apply forallb_forall; intros snapshot Member.
 apply filter_In in Member as [Member _].
 rewrite forallb_forall in Valid; apply Valid; exact Member.
Qed.

Lemma fresh_root_has_no_descendants : forall child before,
 well_formed before -> task_lineage child = [] ->
 Tasks.descendant_count (next_task before) (world_tasks (append_task child before)) = 0%N.
Proof.
 intros child before Valid Root.
 rewrite root_creation_keeps_existing_descendant_counts by exact Root.
 apply descendant_count_is_zero_above_all_lineages with (lower:=next_task before); [|lia].
 apply legal_registry_lineages_precede_the_append_position; exact Valid.
Qed.

Lemma constructed_root_task_is_valid : forall owner chosen selected contents idle environment after,
 environment_valid environment = true -> profile_valid chosen = true ->
 settings_valid selected = true -> project_binding selected after = true ->
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (Tasks.initial_history environment chosen selected)) = true ->
 Tasks.descendant_count owner (world_tasks after) = 0%N ->
 task_valid owner (Tasks.make_task chosen selected contents idle environment) after = true.
Proof.
 intros owner chosen selected contents idle environment after Environment Profile Settings Project Context Capacity.
 unfold environment_valid in Environment; repeat rewrite andb_true_iff in Environment.
 assert (Tools : tools_valid (environment_tools environment) = true) by tauto.
 assert (Sources : forallb (fun tool => match tool_origin tool with
   | ExtensionToolSource _ reference _ => Capabilities.plugin_present reference (environment_plugins environment)
   | _ => true end) (environment_tools environment) = true) by tauto.
 assert (Plugins : plugins_valid (environment_plugins environment) = true) by tauto.
 assert (Limits : ((0 <? environment_max_fork environment) && (0 <? environment_max_descendants environment))%N = true) by (apply andb_true_iff; tauto).
 unfold task_valid, contract_valid, Tasks.make_task.
 cbn [task_contract task_current_profile task_current_settings task_history contract_profile contract_tools
   contract_plugins contract_settings contract_max_fork contract_max_descendants task_lineage lineage_valid].
 rewrite Profile, Tools, Sources, Plugins, Settings, Project, Capacity, Limits.
 assert (History : forallb ContextUpdates.valid_snapshot
   (ContextUpdates.bindings (Tasks.initial_history environment chosen selected ++ if idle then [] else [UserMessage contents])) = true).
 { unfold ContextUpdates.bindings in *; rewrite fold_left_app.
   destruct idle; exact Context. }
 rewrite History.
 destruct idle; destruct (environment_max_descendants environment); reflexivity.
Qed.

Theorem a_resolved_public_start_has_valid_settings_and_profile : forall name effort contents settings before start,
 well_formed before ->
 CommandExecution.resolve_context_start (Worktree.creation_entry Worktree.ImplicitCreation None)
   name effort contents settings false None before = Tasks.StartResolved start ->
 start_environment start = world_environment before /\
 profile_valid (start_profile start) = true /\
 settings_valid (start_settings start) = true /\ project_binding (start_settings start) before = true.
Proof.
 intros name effort contents settings before start Formed Resolved.
 pose proof (environment_requirement before Formed) as Environment.
 change (environment_valid (world_environment before) = true) in Environment.
 pose proof (projects_requirement before Formed) as Projects.
 change (projects_valid before = true) in Projects.
 assert (Catalog : profiles_valid (environment_profiles (world_environment before)) = true).
 { unfold environment_valid in Environment; repeat rewrite andb_true_iff in Environment; tauto. }
 unfold CommandExecution.resolve_context_start, Tasks.resolve_start in Resolved; cbn in Resolved.
 destruct (Tasks.find_profile name (environment_profiles (world_environment before))) as [model|] eqn:Found; [|discriminate].
 assert (Model : profile_valid model = true).
 { unfold Tasks.find_profile in Found; apply find_some in Found as [Member _].
   eapply catalog_members_have_valid_profiles; eauto. }
 destruct (Tasks.resolve_settings model settings (Tasks.creation_defaults (world_environment before)) before)
   as [selected|] eqn:Settings; [|discriminate].
 destruct (Tasks.selected_reasoning effort model) as [chosen|] eqn:Reasoning; [|discriminate].
 destruct (Tasks.content_nonempty contents); [|discriminate].
 inversion Resolved; subst start; cbn; split; [reflexivity|]; split.
 - eapply selected_reasoning_preserves_profile_validity; eauto.
 - eapply resolving_settings_preserves_validity; [exact Model|exact Catalog|exact Projects| | |exact Settings].
   + apply environment_creation_defaults_are_valid; exact Environment.
   + unfold Tasks.creation_defaults, project_binding.
     destruct (value_or_null "workspace" (environment_project (world_environment before))); cbn;
       try destruct (parse_workspace _); reflexivity.
Qed.


Theorem initial_history_admits_only_valid_context : forall environment chosen selected,
 forallb ContextUpdates.valid_snapshot
   (ContextUpdates.bindings (Tasks.initial_history environment chosen selected)) = true.
Proof.
 intros environment chosen selected.
 unfold ContextUpdates.bindings; apply initial_introductions_retain_admitted_context; [|reflexivity].
 unfold Tasks.initial_history.
 apply Forall_app; split; [constructor; [reflexivity|constructor]|].
 apply Forall_app; split.
 - destruct (environment_global_instructions environment) as [source|]; [|constructor].
   destruct (ContextUpdates.global_guidance_snapshot source) as [snapshot|] eqn:Created; [|constructor].
   constructor; [eapply global_snapshot_is_valid; exact Created|constructor].
 - apply Forall_app; split.
   + destruct (Tasks.initial_project_guidance selected) as [snapshot|] eqn:Created; [|constructor].
     constructor; [eapply initial_project_guidance_is_admitted; exact Created|constructor].
   + constructor; [exact I|constructor].
Qed.

Theorem a_resolved_public_start_constructs_a_valid_root : forall name effort contents settings before start,
 well_formed before ->
 CommandExecution.resolve_context_start (Worktree.creation_entry Worktree.ImplicitCreation None)
   name effort contents settings false None before = Tasks.StartResolved start ->
 task_valid (next_task before) (Tasks.start_task start) (append_task (Tasks.start_task start) before) = true.
Proof.
 intros name effort contents settings before start Valid Resolved.
 destruct (a_resolved_public_start_has_valid_settings_and_profile name effort contents settings before start Valid Resolved)
   as [Environment [Profile [Settings Project]]].
 unfold Tasks.start_task; apply constructed_root_task_is_valid.
 - rewrite Environment; exact (environment_requirement before Valid).
 - exact Profile.
 - exact Settings.
 - exact Project.
 - apply initial_history_admits_only_valid_context.
 - apply fresh_root_has_no_descendants; [exact Valid|reflexivity].
Qed.

Theorem a_resolved_public_start_preserves_every_world_requirement : forall name effort contents settings before start,
 well_formed before ->
 CommandExecution.resolve_context_start (Worktree.creation_entry Worktree.ImplicitCreation None)
   name effort contents settings false None before = Tasks.StartResolved start ->
 well_formed (append_task (Tasks.start_task start) before).
Proof.
 intros name effort contents settings before start Valid Resolved.
 apply root_birth_preserves_every_world_requirement.
 - exact Valid.
 - reflexivity.
 - unfold task_tickets, Tasks.start_task, Tasks.make_task; cbn.
   destruct (Tasks.start_idle start); reflexivity.
 - eapply a_resolved_public_start_constructs_a_valid_root; eauto.
Qed.


Theorem a_resolved_workspace_creation_preserves_every_world_requirement :
 forall name effort contents settings before start (plan : Worktree.planned_start before),
 well_formed before ->
 CommandExecution.resolve_context_start (Worktree.creation_entry Worktree.ImplicitCreation None)
   name effort contents settings false None before = Tasks.StartResolved start ->
 Worktree.planned_task plan = start -> Worktree.planned_resource plan = Worktree.UseWorkspace ->
 well_formed (decision_world (Worktree.consume_planned_start plan before)).
Proof.
 intros name effort contents settings before start plan Valid Resolved Task Resource.
 unfold Worktree.consume_planned_start; rewrite Resource, Task.
 change (well_formed (append_task (Tasks.start_task start) before)).
 eapply a_resolved_public_start_preserves_every_world_requirement; eauto.
Qed.
