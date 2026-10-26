From Selvedge.Kernel Require CommandResult.
From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import RegistryProofs.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State Tasks Codec Workspace WorldInvariant FeatureFrameProofs ForkPreservation CreationPreservation CreationStartProofs.
From Selvedge.Features Require Import Domain State Worktree WorktreeProofs WorkspaceBinding.
Import ListNotations.
Module F := Selvedge.Features.Domain.

Lemma primary_workspace_keeps_validity : forall space,
 Workspace.valid_workspace space = true ->
 Workspace.valid_workspace (Worktree.primary_workspace space) = true.
Proof.
 intros [roots [root|]] Valid; [|reflexivity].
 unfold Workspace.valid_workspace in Valid; cbn in Valid.
 repeat rewrite andb_true_iff in Valid.
 destruct Valid as [[[Bound Unique] Paths] Member].
 apply existsb_exists in Member as [selected [Present Same]].
 apply String.eqb_eq in Same; subst selected.
 apply forallb_forall with (x:=root) in Paths; [|exact Present].
 unfold Worktree.primary_workspace,Workspace.valid_workspace; cbn.
 rewrite String.eqb_refl,Paths; reflexivity.
Qed.

Lemma primary_workspace_keeps_guidance : forall space guidance,
 guidance_member (Worktree.primary_workspace space) guidance = guidance_member space guidance.
Proof. intros [roots [root|]] guidance; destruct guidance; reflexivity. Qed.

Theorem resource_settings_keep_requirements : forall owner backend selected,
 WorldInvariant.settings_valid selected = true ->
 WorldInvariant.settings_valid (Worktree.resource_settings owner backend selected) = true.
Proof.
 intros owner backend selected Valid.
 destruct backend; [exact Valid|].
 unfold WorldInvariant.settings_valid in *.
 repeat rewrite andb_true_iff in *.
 destruct Valid as [[[Space Guidance] Member] Approval].
 cbn [Worktree.resource_settings WorkspaceBackend.cloud settings_workspace settings_guidance settings_approval WorldInvariant.approval_valid].
 rewrite primary_workspace_keeps_guidance; repeat split; try assumption.
 apply primary_workspace_keeps_validity; exact Space.
Qed.

Lemma resource_settings_keep_project : forall owner backend selected state,
 WorldInvariant.project_binding (Worktree.resource_settings owner backend selected) state =
 WorldInvariant.project_binding selected state.
Proof. intros; unfold WorldInvariant.project_binding,Worktree.resource_settings; reflexivity. Qed.

Lemma environment_notice_keeps_context_bindings : forall history notice,
 ContextUpdates.bindings (history ++ [EnvironmentNotice notice]) = ContextUpdates.bindings history.
Proof. intros; unfold ContextUpdates.bindings; rewrite fold_left_app; reflexivity. Qed.

Lemma resource_task_keeps_context_bindings : forall owner backend task,
 ContextUpdates.bindings (task_history (Worktree.resource_task owner backend task)) =
 ContextUpdates.bindings (task_history task).
Proof.
 intros owner [|] task; cbn [Worktree.resource_task WorkspaceBackend.cloud task_history];
 [reflexivity|apply environment_notice_keeps_context_bindings].
Qed.

Lemma resource_contract_keeps_requirements : forall owner backend contract,
 WorldInvariant.contract_valid contract = true ->
 WorldInvariant.contract_valid
   (Contract (contract_profile contract) (contract_tools contract)
     (Worktree.resource_settings owner backend (contract_settings contract))
     (contract_max_fork contract) (contract_max_descendants contract)
     (contract_plugins contract) (contract_reviewers contract)) = true.
Proof.
 intros owner backend contract Valid.
 unfold WorldInvariant.contract_valid in *; cbn.
 repeat rewrite andb_true_iff in *.
 destruct Valid as [[[[[Profile Tools] Sources] Plugins] Settings] [Fork Descendants]].
 repeat split; try assumption. apply resource_settings_keep_requirements; exact Settings.
Qed.

Theorem resource_task_keeps_fresh_start_requirements :
 forall owner backend chosen selected contents idle environment state,
 WorldInvariant.task_valid owner (Tasks.make_task chosen selected contents idle environment) state = true ->
 WorldInvariant.task_valid owner
   (Worktree.resource_task owner backend (Tasks.make_task chosen selected contents idle environment)) state = true.
Proof.
 intros owner backend chosen selected contents idle environment state Valid.
 unfold WorldInvariant.task_valid in Valid |- *.
 rewrite resource_task_keeps_context_bindings.
 cbn [Tasks.make_task task_contract task_current_profile task_current_settings task_history task_lineage
   Worktree.resource_task contract_settings contract_max_descendants] in *.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[[[[[[[[Contract Profile] Settings] Context] Project] CurrentProject] Lineage] Count] Phase] Checked] Operations].
 repeat split; try assumption.
 - apply resource_contract_keeps_requirements; exact Contract.
 - apply resource_settings_keep_requirements; exact Settings.
 - destruct backend, idle; reflexivity.
 - destruct backend, idle; reflexivity.
Qed.

Theorem environment_notice_keeps_fresh_start_requirements :
 forall owner chosen selected contents idle environment state,
 WorldInvariant.task_valid owner (Tasks.make_task chosen selected contents idle environment) state = true ->
 WorldInvariant.task_valid owner
   (append_history [EnvironmentNotice Worktree.environment_notice]
     (Tasks.make_task chosen selected contents idle environment)) state = true.
Proof.
 intros owner chosen selected contents idle environment state Valid.
 unfold WorldInvariant.task_valid in Valid |- *.
 unfold append_history,with_history; cbv [set]; cbn [task_contract task_current_profile task_current_settings task_history task_lineage].
 rewrite environment_notice_keeps_context_bindings.
 cbn [Tasks.make_task task_contract task_current_profile task_current_settings task_history task_lineage
   contract_settings contract_max_descendants] in *.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[[[[[[[[Contract Profile] Settings] Context] Project] CurrentProject] Lineage] Count] Phase] Checked] Operations].
 repeat split; try assumption; destruct idle; reflexivity.
Qed.

Lemma resource_task_keeps_lineage : forall owner backend task,
 task_lineage (Worktree.resource_task owner backend task) = task_lineage task.
Proof. intros; reflexivity. Qed.

Lemma resource_task_initial_tickets : forall owner backend chosen selected contents idle environment,
 WorldInvariant.task_tickets
   (Worktree.resource_task owner backend (Tasks.make_task chosen selected contents idle environment)) = [].
Proof. intros; destruct backend,idle; reflexivity. Qed.

(* Running connection jobs retain their resource identity while another task
   provisions an environment. Freshness makes this a registry extension. *)
Lemma storing_a_fresh_resource_keeps_old_ready_bindings : forall tree state space owner,
 Worktree.lookup (F.worktree_task tree) state = None ->
 WorkspaceBinding.resource_ready space owner state = true ->
 WorkspaceBinding.resource_ready space owner (Worktree.store tree state) = true.
Proof.
 intros tree state space [owner|] Fresh Ready; [|reflexivity].
 unfold WorkspaceBinding.resource_ready in *.
 change (match Worktree.lookup owner (Worktree.store tree state) with
 | Some entry => (if WorkspaceBackend.cloud (F.worktree_backend entry)
   then WorkspaceBinding.within_resource space entry else WorkspaceBinding.contains space entry) &&
   match F.worktree_phase entry with F.TreeReady _ _ => true | _ => false end
 | None => false end = true).
 destruct (N.eq_dec owner (F.worktree_task tree)) as [Same|Different].
 - subst owner. change (match Worktree.lookup (F.worktree_task tree) state with
   | Some entry => (if WorkspaceBackend.cloud (F.worktree_backend entry)
     then WorkspaceBinding.within_resource space entry else WorkspaceBinding.contains space entry) &&
     match F.worktree_phase entry with F.TreeReady _ _ => true | _ => false end
   | None => false end = true) in Ready.
   rewrite Fresh in Ready; discriminate.
 - rewrite store_preserves_other_resource_lookups by exact Different. exact Ready.
Qed.

Lemma storing_a_fresh_resource_keeps_sharing_requirements : forall tree state,
 Worktree.lookup (F.worktree_task tree) state = None ->
 WorldInvariant.sharing_valid state = true ->
 WorldInvariant.sharing_valid (Worktree.store tree state) = true.
Proof.
 intros tree state Fresh Valid.
 unfold WorldInvariant.sharing_valid in Valid |- *.
 cbn [Worktree.store with_features Selvedge.Features.State.with_worktrees] in *.
 unfold Worktree.store,with_features,Selvedge.Features.State.with_worktrees; cbv [set]; cbn.
 repeat rewrite andb_true_iff in Valid |- *.
 destruct Valid as [[[[[[GrantsBound GrantsUnique] Grants] JobsBound] Next] JobsUnique] Jobs].
 repeat split; try assumption.
 apply forallb_forall; intros [id job] Member.
 apply forallb_forall with (x:=(id,job)) in Jobs; [|exact Member].
 cbn in Jobs |- *; repeat rewrite andb_true_iff in Jobs |- *.
 destruct Jobs as [[[[Identity Request] Arguments] Space] Ready].
 repeat split; try assumption.
 destruct (F.job_state job); try reflexivity.
 apply storing_a_fresh_resource_keeps_old_ready_bindings; assumption.
Qed.

Lemma fresh_resource_filter_is_identity : forall entries owner,
 find (fun entry => N.eqb owner (F.worktree_task entry)) entries = None ->
 filter (fun entry => negb (N.eqb owner (F.worktree_task entry))) entries = entries.
Proof.
 induction entries as [|entry rest IH]; intros owner Fresh; [reflexivity|].
 cbn in Fresh |- *.
 destruct (N.eqb owner (F.worktree_task entry)) eqn:Same; [discriminate|].
 cbn; rewrite IH by exact Fresh; reflexivity.
Qed.

Lemma fresh_resource_owner_is_absent : forall entries owner,
 find (fun entry => N.eqb owner (F.worktree_task entry)) entries = None ->
 ~ In owner (map F.worktree_task entries).
Proof.
 intros entries owner Fresh Member.
 apply in_map_iff in Member as [entry [Same Member]].
 apply find_none with (x:=entry) in Fresh; [|exact Member].
 rewrite Same,N.eqb_refl in Fresh; discriminate.
Qed.

Lemma storing_a_fresh_resource_keeps_worktree_requirements : forall tree state,
 Worktree.lookup (F.worktree_task tree) state = None ->
 WorldInvariant.tree_owner_valid tree state = true ->
 WorldInvariant.worktrees_valid state = true ->
 WorldInvariant.worktrees_valid (Worktree.store tree state) = true.
Proof.
 intros tree state Fresh Tree Valid.
 unfold WorldInvariant.worktrees_valid in Valid |- *.
 apply andb_true_iff in Valid as [Unique Entries].
 unfold Worktree.store,with_features,Selvedge.Features.State.with_worktrees; cbv [set]; cbn.
 unfold Worktree.lookup in Fresh.
 rewrite fresh_resource_filter_is_identity by exact Fresh.
 apply andb_true_iff; split.
 - unfold WorldInvariant.unique_tickets in Unique |- *; cbn.
   destruct (in_dec N.eq_dec (F.worktree_task tree)
      (map F.worktree_task (F.feature_worktrees (world_features state)))) as [Present|Absent].
   + exfalso; eapply fresh_resource_owner_is_absent; eassumption.
   + cbn. exact Unique.
 - apply andb_true_iff; split; [exact Tree|exact Entries].
Qed.

Theorem storing_a_fresh_resource_preserves_every_world_requirement : forall tree state,
 WorldInvariant.well_formed state ->
 Worktree.lookup (F.worktree_task tree) state = None ->
 WorldInvariant.tree_owner_valid tree state = true ->
 WorldInvariant.well_formed (Worktree.store tree state).
Proof.
 intros tree state Valid Fresh Tree.
 apply unchanged_registries_preserve_other_world_requirements with state; try reflexivity; try assumption.
 - exact (WorldInvariant.tickets_requirement state Valid).
 - pose proof (well_formed_feature_requirements state Valid) as Features.
   assert (Graphs : WorldInvariant.graph_registry_valid (Worktree.store tree state) =
     WorldInvariant.graph_registry_valid state).
   { apply graph_registry_requirements_follow_entry_observations; reflexivity. }
   unfold WorldInvariant.features_valid in Features |- *; rewrite Graphs.
   repeat rewrite andb_true_iff in Features |- *.
   destruct Features as [[[[[[[Titles Remote] Trees] Board] Sharing] GraphsValid] Works] Compaction].
   repeat split; try assumption.
   + apply storing_a_fresh_resource_keeps_worktree_requirements; assumption.
   + apply storing_a_fresh_resource_keeps_sharing_requirements; assumption.
Qed.

Lemma a_well_formed_world_has_no_resource_for_its_next_task : forall state,
 WorldInvariant.well_formed state -> Worktree.lookup (next_task state) state = None.
Proof.
 intros state Valid.
 destruct (Worktree.lookup (next_task state) state) as [tree|] eqn:Found; [|reflexivity].
 exfalso.
 pose proof (lookup_has_owner _ _ _ Found) as Owner.
 unfold Worktree.lookup in Found; apply find_some in Found as [Member _].
 pose proof (WorldInvariant.features_requirement state Valid) as Features.
 unfold WorldInvariant.features_valid,WorldInvariant.worktrees_valid in Features.
 repeat rewrite andb_true_iff in Features.
 assert (WorldInvariant.tree_owner_valid tree (WorldInvariant.world_structure state) = true) as Tree.
 { assert (Entries : forallb (fun entry => WorldInvariant.tree_owner_valid entry (WorldInvariant.world_structure state))
     (F.feature_worktrees (world_features state)) = true) by tauto.
   apply forallb_forall with (x:=tree) in Entries; assumption. }
 unfold WorldInvariant.tree_owner_valid in Tree; rewrite Owner in Tree.
 destruct (find_task (next_task state) (WorldInvariant.world_structure state)) as [task|] eqn:Selected.
 - apply Selvedge.Foundation.RegistryProofs.registry_lookup_implies_position_bound in Selected.
   change (next_task state < N.of_nat (List.length (world_tasks state)))%N in Selected.
   unfold next_task in Selected; lia.
 - rewrite andb_false_r in Tree; discriminate.
Qed.

Lemma root_birth_task_requirements_ignore_the_new_root : forall first second before owner task,
 task_lineage first = [] -> task_lineage second = [] -> task_lineage task = [] ->
 WorldInvariant.task_valid owner task (append_task first before) =
 WorldInvariant.task_valid owner task (append_task second before).
Proof.
 intros first second before owner task First Second Root.
 unfold WorldInvariant.task_valid.
 rewrite !root_creation_keeps_existing_descendant_counts by assumption.
 unfold WorldInvariant.lineage_valid; rewrite Root; reflexivity.
Qed.

Lemma a_resource_start_is_valid_in_its_own_birth : forall before backend start,
 WorldInvariant.task_valid (next_task before) (Tasks.start_task start)
   (append_task (Tasks.start_task start) before) = true ->
 WorldInvariant.task_valid (next_task before)
   (Worktree.resource_task (next_task before) backend (Tasks.start_task start))
   (append_task (Worktree.resource_task (next_task before) backend (Tasks.start_task start)) before) = true.
Proof.
 intros before backend [chosen selected contents idle environment] Valid.
 apply resource_task_keeps_fresh_start_requirements.
 rewrite root_birth_task_requirements_ignore_the_new_root with
   (second:=Tasks.make_task chosen selected contents idle environment); [exact Valid|reflexivity|reflexivity|reflexivity].
Qed.

Lemma an_environment_notice_start_is_valid_in_its_own_birth : forall before start,
 WorldInvariant.task_valid (next_task before) (Tasks.start_task start)
   (append_task (Tasks.start_task start) before) = true ->
 WorldInvariant.task_valid (next_task before)
   (append_history [EnvironmentNotice Worktree.environment_notice] (Tasks.start_task start))
   (append_task (append_history [EnvironmentNotice Worktree.environment_notice] (Tasks.start_task start)) before) = true.
Proof.
 intros before [chosen selected contents idle environment] Valid.
 apply environment_notice_keeps_fresh_start_requirements.
 rewrite root_birth_task_requirements_ignore_the_new_root with
   (second:=Tasks.make_task chosen selected contents idle environment); [exact Valid|reflexivity|reflexivity|reflexivity].
Qed.

Lemma admitted_provision_has_a_valid_primary : forall before intent start backend,
 Worktree.resource_error intent before (Tasks.start_settings start)
   (match backend with WorkspaceBackend.Local => Worktree.ProvisionLocal
    | WorkspaceBackend.TencentCvm => Worktree.ProvisionCloud end) = None ->
 Workspace.valid_path (Worktree.primary (settings_workspace
   (task_current_settings (Worktree.resource_task (next_task before) backend (Tasks.start_task start))))) = true.
Proof.
 intros before intent start backend Admitted.
 unfold Worktree.resource_error in Admitted.
 destruct backend; cbn [WorkspaceBackend.cloud] in Admitted |- *.
 - destruct (workspace_primary (settings_workspace (Tasks.start_settings start))) as [root|] eqn:Primary; [|discriminate].
   destruct (Workspace.valid_workspace (settings_workspace (Tasks.start_settings start)) &&
      Workspace.valid_path (Worktree.primary (settings_workspace (Tasks.start_settings start))) &&
      Worktree.workspace_available (settings_workspace (Tasks.start_settings start)) before) eqn:Available; [|discriminate].
   repeat rewrite andb_true_iff in Available; tauto.
 - destruct (negb (Worktree.project_primary_matches (Tasks.start_settings start) before)); [discriminate|].
   destruct (workspace_primary (settings_workspace (Tasks.start_settings start))) as [root|] eqn:Primary; [|discriminate].
   destruct (Workspace.valid_workspace (settings_workspace (Tasks.start_settings start)) &&
      Workspace.valid_path (Worktree.primary (settings_workspace (Tasks.start_settings start))) &&
      Worktree.workspace_available (settings_workspace (Tasks.start_settings start)) before) eqn:Available; [|discriminate].
   repeat rewrite andb_true_iff in Available.
   change (Workspace.valid_path (Worktree.primary (Worktree.primary_workspace (settings_workspace (Tasks.start_settings start)))) = true).
   unfold Worktree.primary_workspace,Worktree.primary; rewrite Primary.
   unfold Worktree.primary in Available; rewrite Primary in Available; tauto.
Qed.

Theorem provisioning_a_start_preserves_every_world_requirement : forall before intent start backend,
 WorldInvariant.well_formed before ->
 Worktree.resource_error intent before (Tasks.start_settings start)
   (match backend with WorkspaceBackend.Local => Worktree.ProvisionLocal
    | WorkspaceBackend.TencentCvm => Worktree.ProvisionCloud end) = None ->
 WorldInvariant.task_valid (next_task before) (Tasks.start_task start)
   (append_task (Tasks.start_task start) before) = true ->
 let prepared := Worktree.resource_task (next_task before) backend (Tasks.start_task start) in
 let tree := F.Worktree (next_task before)
   (Worktree.primary (settings_workspace (task_current_settings prepared))) (F.TreeCreating false) backend in
 WorldInvariant.well_formed (Worktree.store tree (append_task prepared before)).
Proof.
 intros before intent start backend Valid Admitted Start prepared tree.
 apply storing_a_fresh_resource_preserves_every_world_requirement.
 - apply root_birth_preserves_every_world_requirement; [exact Valid|reflexivity| |].
   + destruct start; apply resource_task_initial_tickets.
   + apply a_resource_start_is_valid_in_its_own_birth; exact Start.
 - exact (a_well_formed_world_has_no_resource_for_its_next_task before Valid).
 - pose proof (admitted_provision_has_a_valid_primary before intent start backend Admitted) as Primary.
   change (Workspace.valid_path (Worktree.primary (settings_workspace (task_current_settings prepared))) = true) in Primary.
   unfold tree, WorldInvariant.tree_owner_valid; cbn [F.worktree_task F.worktree_source F.worktree_root F.worktree_phase].
   rewrite Primary; cbn.
   unfold find_task; change (match registry_at (next_task before) (world_tasks before ++ [prepared]) with
     | Some task => match task_lifecycle task with Frozen _ [] => true | _ => false end
     | None => false end = true).
   unfold next_task; rewrite Selvedge.Foundation.RegistryProofs.registry_lookup_at_appended_index.
   unfold prepared; destruct start as [chosen selected contents idle environment]; destruct backend,idle; reflexivity.
Qed.

Theorem planned_resources_preserve_every_world_requirement : forall before (plan : Worktree.planned_start before),
 WorldInvariant.well_formed before ->
 WorldInvariant.task_valid (next_task before) (Tasks.start_task (Worktree.planned_task plan))
   (append_task (Tasks.start_task (Worktree.planned_task plan)) before) = true ->
 WorldInvariant.well_formed (decision_world (Worktree.consume_planned_start plan before)).
Proof.
 intros before [intent start resource admitted] Valid Start.
 destruct resource as [|owner tree observed| |].
 - apply root_birth_preserves_every_world_requirement; [exact Valid|reflexivity| |exact Start].
   destruct start as [chosen selected contents idle environment]; destruct idle; reflexivity.
 - unfold Worktree.consume_planned_start, Worktree.interpret_planned_birth, Worktree.born_decision, Worktree.born_world, Worktree.born_effects, Worktree.born_identity; cbn [Worktree.planned_task Worktree.planned_resource].
   destruct (WorkspaceBackend.cloud (F.worktree_backend tree)).
   + apply root_birth_preserves_every_world_requirement; [exact Valid|reflexivity| |].
     * destruct start as [chosen selected contents idle environment]; destruct idle; reflexivity.
     * apply an_environment_notice_start_is_valid_in_its_own_birth; exact Start.
   + apply root_birth_preserves_every_world_requirement; [exact Valid|reflexivity| |exact Start].
     destruct start as [chosen selected contents idle environment]; destruct idle; reflexivity.
 - apply provisioning_a_start_preserves_every_world_requirement with (intent:=intent);
   assumption.
 - apply provisioning_a_start_preserves_every_world_requirement with (intent:=intent);
   assumption.
Qed.

Lemma preparing_a_start_keeps_its_resolved_task : forall intent managed backend start before plan,
 Worktree.prepare_resolved intent managed backend start before = CommandResult.Accepted plan ->
 Worktree.planned_task plan = start.
Proof.
 intros intent managed backend start before plan Planned.
 unfold Worktree.prepare_resolved in Planned.
 destruct (Worktree.select_creation_plan before (Tasks.start_settings start) managed backend) as [resource|]; [|discriminate].
 assert (Erases : forall result
   (observed : Worktree.resource_error intent before (Tasks.start_settings start) resource = result),
   (match result as selected return
       Worktree.resource_error intent before (Tasks.start_settings start) resource = selected ->
       Worktree.start_plan_result before with
    | Some cause => fun _ => CommandResult.Rejected
        (CommandResult.Refusal (Tasks.failure_code (Worktree.creation_entry intent None) cause) (Tasks.failure_message cause))
    | None => fun admitted => CommandResult.Accepted (Worktree.PlannedStart intent start resource admitted)
    end observed) = CommandResult.Accepted plan -> Worktree.planned_task plan = start).
 { intros [cause|] observed Equal; [discriminate|]. inversion Equal; reflexivity. }
 eapply Erases; exact Planned.
Qed.


Theorem a_resolved_public_resource_creation_preserves_every_world_requirement :
 forall name effort contents settings before start (plan : Worktree.planned_start before),
 WorldInvariant.well_formed before ->
 CommandExecution.resolve_context_start (Worktree.creation_entry Worktree.ImplicitCreation None)
   name effort contents settings false None before = Tasks.StartResolved start ->
 Worktree.prepare_resolved Worktree.ImplicitCreation None None start before = CommandResult.Accepted plan ->
 WorldInvariant.well_formed (decision_world (Worktree.consume_planned_start plan before)).
Proof.
 intros name effort contents settings before start plan Valid Resolved Planned.
 apply planned_resources_preserve_every_world_requirement; [exact Valid|].
 rewrite (preparing_a_start_keeps_its_resolved_task _ _ _ _ _ _ Planned).
 eapply a_resolved_public_start_constructs_a_valid_root; eauto.
Qed.
