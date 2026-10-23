From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State Codec WorkspaceBackend LifecycleProofs.
From Selvedge.Features Require Import Domain Worktree WorkspaceBinding Runtime.
Import ListNotations.
Module F:=Selvedge.Features.Domain.
(** A completion looked up by owner can only update that registry identity. *)
Lemma lookup_has_owner : forall id value tree,
 Worktree.lookup id value = Some tree -> F.worktree_task tree = id.
Proof.
 intros id value tree found. unfold Worktree.lookup in found.
 apply find_some in found as [_ matches]. apply N.eqb_eq in matches. symmetry; exact matches.
Qed.
(** The registry is replaced through the operation used by setup, archive and
    callback admission. A write cannot retain another entry for that owner or
    change an unrelated resource. *)
Theorem stored_resource_is_the_lookup : forall tree value,
 Worktree.lookup (F.worktree_task tree) (Worktree.store tree value) = Some tree.
Proof.
 intros; unfold Worktree.lookup, Worktree.store, Selvedge.Kernel.State.with_features,
   Selvedge.Features.State.with_worktrees; cbv [set]; cbn.
 rewrite N.eqb_refl; reflexivity.
Qed.
Theorem stored_resource_removes_previous_entries : forall tree value previous,
 In previous (tl (F.feature_worktrees (world_features (Worktree.store tree value)))) ->
 F.worktree_task previous <> F.worktree_task tree.
Proof.
 intros tree value previous member.
 unfold Worktree.store, Selvedge.Kernel.State.with_features,
   Selvedge.Features.State.with_worktrees in member; cbv [set] in member; cbn in member.
 apply filter_In in member as [_ different].
 apply Bool.negb_true_iff in different; apply N.eqb_neq in different; congruence.
Qed.
Lemma find_other_resource_after_filter : forall entries id owner,
 id <> owner ->
 find (fun tree => N.eqb id (F.worktree_task tree))
   (filter (fun tree => negb (N.eqb owner (F.worktree_task tree))) entries) =
 find (fun tree => N.eqb id (F.worktree_task tree)) entries.
Proof.
 induction entries as [|tree rest IH]; intros id owner different; [reflexivity|].
 cbn. destruct (N.eqb owner (F.worktree_task tree)) eqn:owned; cbn.
 - apply N.eqb_eq in owned.
   assert (N.eqb id (F.worktree_task tree) = false) as other.
   { apply N.eqb_neq; congruence. }
   rewrite other; apply IH; exact different.
 - destruct (N.eqb id (F.worktree_task tree)); [reflexivity|apply IH; exact different].
Qed.
Theorem store_preserves_other_resource_lookups : forall tree value id,
 id <> F.worktree_task tree ->
 Worktree.lookup id (Worktree.store tree value) = Worktree.lookup id value.
Proof.
 intros tree value id different.
 unfold Worktree.lookup, Worktree.store, Selvedge.Kernel.State.with_features,
   Selvedge.Features.State.with_worktrees; cbv [set]; cbn.
 assert (N.eqb id (F.worktree_task tree) = false) as other by (apply N.eqb_neq; exact different).
 rewrite other; apply find_other_resource_after_filter; exact different.
Qed.
(** Restoring just the registry restores the entire world, including all other
    feature components and the kernel. This subsumes the old per-field frames. *)
Theorem store_changes_only_worktree_registry : forall tree value,
 Selvedge.Kernel.State.with_features
   (Selvedge.Features.State.with_worktrees (F.feature_worktrees (world_features value))
      (world_features (Worktree.store tree value))) (Worktree.store tree value) = value.
Proof.
 intros tree [sequence tasks ticket environment projects features].
 destruct features; reflexivity.
Qed.
Lemma store_preserves_tasks : forall tree value,
 world_tasks (Worktree.store tree value) = world_tasks value.
Proof. intros tree [sequence tasks ticket environment projects features]; destruct features; reflexivity. Qed.
Lemma registry_at_numbered_map : forall (A B : Type) (f : N -> A -> B) values offset index previous,
 registry_at index values = Some previous ->
 registry_at index (Numbers.indexed f offset values) = Some (f (offset+index)%N previous).
Proof.
 intros A B f values; induction values as [|first rest IH]; intros offset index previous Found;
 cbn [registry_at Numbers.indexed] in Found |- *; [discriminate|].
 destruct (N.eqb index 0) eqn:Zero.
 - apply N.eqb_eq in Zero; subst index; inversion Found; subst previous.
   now rewrite N.add_0_r.
 - rewrite (IH (N.succ offset) (N.pred index) previous Found).
   f_equal; f_equal; apply N.eqb_neq in Zero; lia.
Qed.
Lemma completing_bindings_preserves_the_owner : forall owner space guidance value task,
 find_task owner value = Some task ->
 find_task owner (Worktree.complete_bindings owner space guidance value) = Some task.
Proof.
 intros owner space guidance value task Found.
 unfold Worktree.complete_bindings, with_tasks, find_task; cbv [set]; cbn [world_tasks].
 rewrite (registry_at_numbered_map _ _ _ _ 0 owner task Found).
 rewrite N.add_0_l. unfold Worktree.complete_binding. rewrite N.eqb_refl; reflexivity.
Qed.
Theorem setup_initializes_every_live_binding : forall owner id space guidance value task,
 find_task id value = Some task -> id <> owner -> Worktree.archived task = false ->
 settings_resource (contract_settings (task_contract task)) = Some owner ->
 find_task id (Worktree.complete_bindings owner space guidance value) =
 Some (Worktree.install_workspace (task_lifecycle task) space guidance task).
Proof.
 intros owner id space guidance value task Found Other Live Bound.
 unfold Worktree.complete_bindings, with_tasks, find_task; cbv [set]; cbn [world_tasks].
 rewrite (registry_at_numbered_map _ _ _ _ 0 id task Found).
 rewrite N.add_0_l. unfold Worktree.complete_binding.
 assert (Different : N.eqb owner id = false) by (apply N.eqb_neq; congruence).
 rewrite Different, Live, Bound. unfold Workspace.same_resource. rewrite N.eqb_refl; reflexivity.
Qed.
(** A host success must name its primary directory and carry guidance from that
    directory. Malformed observations never turn a pending setup into failure. *)
Theorem created_completion_requires_explicit_primary : forall source value id observed,
 string_field "kind" source = Some "worktree_created" ->
 natural_field "task_id" source = Some id -> bool_field "ok" source = Some true ->
 field "workspace" source = Some observed -> string_field "primary_root" observed = None ->
 Worktree.completion source value = None.
Proof.
 intros source value id observed kind identity succeeded workspace missing.
 unfold Worktree.completion; rewrite kind, identity, succeeded; cbn zeta.
 rewrite workspace, missing.
 destruct (string_field "root" source), (parse_workspace observed); cbn;
   repeat rewrite Bool.andb_false_r; reflexivity.
Qed.
Theorem created_completion_rejects_other_directory_guidance : forall source value id observed space,
 string_field "kind" source = Some "worktree_created" ->
 natural_field "task_id" source = Some id -> bool_field "ok" source = Some true ->
 field "workspace" source = Some observed -> parse_workspace observed = Some space ->
 Codec.guidance_member space (value_or_null "guidance" source) = false ->
 Worktree.completion source value = None.
Proof.
 intros source value id observed space kind identity succeeded workspace parsed mismatch.
 unfold Worktree.completion; rewrite kind, identity, succeeded; cbn zeta.
 rewrite workspace, parsed.
 destruct (string_field "root" source); cbn; [rewrite mismatch|];
   repeat rewrite Bool.andb_false_r; reflexivity.
Qed.
(** Resource phases carry their roots, so a ready tree cannot have no root. *)
Theorem ready_tree_has_root : forall tree,
 F.worktree_state tree = F.Ready -> exists root, F.worktree_root tree = Some root.
Proof.
 intros [id source phase backend] ready. destruct phase; simpl in *; try discriminate.
 - destruct archived; discriminate.
 - eexists;reflexivity.
Qed.
Theorem creating_has_no_root : forall id source archived backend,
 F.worktree_root (F.Worktree id source (F.TreeCreating archived) backend) = None.
Proof. reflexivity. Qed.
Theorem phase_transition_preserves_backend : forall phase tree,
 F.worktree_backend (F.with_worktree_phase phase tree) = F.worktree_backend tree.
Proof. reflexivity. Qed.

(** A valid successful setup does install a ready resource, rather than merely
    avoiding an invalid transition. The callback's physical observations remain
    assumptions; the checked conclusion concerns their admitted domain update. *)
Theorem successful_creation_installs_ready_resource : forall tree value task root space guidance message,
 find_task (F.worktree_task tree) value = Some task ->
 Worktree.created_valid root space guidance task = true ->
 Worktree.archived task = false ->
 let result := Worktree.created tree true (Some root) (Some space) guidance message value in
 decision_reply result = success (JObject [("accepted"%string, JBool true)]) /\
 exists ready,
   Worktree.lookup (F.worktree_task tree) (decision_world result) = Some ready /\
   F.worktree_phase ready = F.TreeReady root (Worktree.primary space) /\
   F.worktree_backend ready = F.worktree_backend tree.
Proof.
 intros tree value task root space guidance message found valid live.
 unfold Worktree.created. rewrite found. cbn. rewrite valid, live. cbn.
 split; [reflexivity|].
 exists (F.with_worktree_phase (F.TreeReady root (Worktree.primary space)) tree).
 split.
 - unfold Worktree.lookup, Worktree.store, Selvedge.Kernel.State.with_features,
     Selvedge.Features.State.with_worktrees.
   cbv [set F.with_worktree_phase]. cbn.
   rewrite N.eqb_refl. reflexivity.
 - split; reflexivity.
Qed.
(** Promotion can record queued input, but it preserves the frozen execution
    contract and current settings. *)
Lemma promote_preserves_frozen_fields : forall task,
 Selvedge.Kernel.Domain.task_contract (Selvedge.Kernel.Tasks.promote task) =
   Selvedge.Kernel.Domain.task_contract task /\
 Selvedge.Kernel.Domain.task_current_settings (Selvedge.Kernel.Tasks.promote task) =
   Selvedge.Kernel.Domain.task_current_settings task.
Proof.
 intros [contract profile settings lifecycle history queued lineage parent side_cursor model_cursor].
 destruct lifecycle as [phase operations|phase operations|phase operations|];
   try destruct phase; try destruct calls; destruct queued;
   cbn [Selvedge.Kernel.Tasks.promote];
   unfold Selvedge.Kernel.Domain.with_lifecycle, Selvedge.Kernel.Domain.with_queued,
     Selvedge.Kernel.Domain.append_history, Selvedge.Kernel.Domain.with_history;
   cbv [set]; simpl; split; reflexivity.
Qed.
(** The contract and execution settings are frame fields of promotion. *)
Lemma promote_preserves_contract_settings : forall task,
 Selvedge.Kernel.Domain.contract_settings
   (Selvedge.Kernel.Domain.task_contract (Selvedge.Kernel.Tasks.promote task)) =
 Selvedge.Kernel.Domain.contract_settings (Selvedge.Kernel.Domain.task_contract task).
Proof.
 intros task. destruct (promote_preserves_frozen_fields task) as [contract_field _].
 now rewrite contract_field.
Qed.
Lemma promote_preserves_current_settings : forall task,
 Selvedge.Kernel.Domain.task_current_settings (Selvedge.Kernel.Tasks.promote task) =
 Selvedge.Kernel.Domain.task_current_settings task.
Proof.
 intros task. destruct (promote_preserves_frozen_fields task) as [_ settings_field].
 exact settings_field.
Qed.
(** Completion selects the host-observed settings independently for the frozen
    contract and the task's current execution settings. *)
Lemma completed_task_contract_settings : forall space guidance task,
 Selvedge.Kernel.Domain.contract_settings
   (Selvedge.Kernel.Domain.task_contract (Worktree.completed_task space guidance task)) =
 Worktree.selected_settings
   (Worktree.selected_workspace (Worktree.primary space)
      (Selvedge.Kernel.Domain.settings_workspace
        (Selvedge.Kernel.Domain.contract_settings
          (Selvedge.Kernel.Domain.task_contract task)))) guidance
   (Selvedge.Kernel.Domain.contract_settings (Selvedge.Kernel.Domain.task_contract task)).
Proof.
 intros space guidance task. unfold Worktree.completed_task, Worktree.install_workspace.
 rewrite promote_preserves_contract_settings. reflexivity.
Qed.
Lemma completed_task_current_settings : forall space guidance task,
 Selvedge.Kernel.Domain.task_current_settings (Worktree.completed_task space guidance task) =
 Worktree.selected_settings space guidance (Selvedge.Kernel.Domain.task_current_settings task).
Proof.
 intros space guidance task. unfold Worktree.completed_task, Worktree.install_workspace.
 rewrite promote_preserves_current_settings. reflexivity.
Qed.
(** Result validation rolls back the complete decision when a workspace is held. *)
Theorem unavailable_result_has_no_effects : forall before result,
 Worktree.guard_result before result <> result ->
 decision_world (Worktree.guard_result before result) = before /\
 decision_effects (Worktree.guard_result before result) = nil.
Proof.
 intros before result changed. unfold Worktree.guard_result in *.
 destruct (List.forallb _ _); [contradiction|split;reflexivity].
Qed.

(** Project background jobs use the host environment. They hold local roots,
    whereas an identical path in a cloud environment is a different resource. *)
Theorem running_connection_job_blocks_local_archive : forall owner root value tree id job,
 Worktree.lookup owner value=Some tree -> F.worktree_backend tree=WorkspaceBackend.Local ->
 In (id,job) (F.sharing_jobs (F.feature_sharing (world_features value))) ->
 F.job_state job=F.JobRunning ->
 Worktree.any_inside root (workspace_roots (F.job_workspace job))=true ->
 Worktree.root_unused owner root value=false.
Proof.
 intros owner root value tree id job found backend member running uses.
 apply Bool.not_true_is_false. intro available.
 unfold Worktree.root_unused in available. rewrite found,backend in available.
 apply Bool.andb_true_iff in available as [_ jobs].
 apply forallb_forall with (x:=(id,job)) in jobs; [|exact member].
 cbn in jobs. unfold Worktree.job_uses_root in jobs. rewrite running,uses in jobs. discriminate.
Qed.
(** A frozen borrower holds the owner's cloud resource regardless of path text
    or whether the owner later changes its current task settings. *)
Theorem frozen_cloud_borrower_blocks_archive : forall owner root value tree id task,
 Worktree.lookup owner value=Some tree -> F.worktree_backend tree=WorkspaceBackend.TencentCvm ->
 In (id,task) (indexed (fun id task=>(id,task)) 0 (world_tasks value)) ->
 id<>owner -> Worktree.archived task=false ->
 settings_resource (contract_settings (task_contract task))=Some owner ->
 Worktree.root_unused owner root value=false.
Proof.
 intros owner root value tree id task found backend member other live reference.
 apply Bool.not_true_is_false. intro available.
 unfold Worktree.root_unused in available. rewrite found,backend in available.
 apply Bool.andb_true_iff in available as [tasks _].
 apply forallb_forall with (x:=(id,task)) in tasks; [|exact member].
 cbn in tasks. assert (different:N.eqb owner id=false) by (apply N.eqb_neq;congruence).
 rewrite different,live,reference in tasks. unfold Workspace.same_resource in tasks.
 rewrite N.eqb_refl in tasks. discriminate.
Qed.
Theorem shared_archive_emits_no_io : forall tree value root,
 F.worktree_root tree=Some root ->
 Worktree.root_unused (F.worktree_task tree) root value=false ->
 decision_effects (Worktree.archive_tree tree value)=[].
Proof. intros. unfold Worktree.archive_tree. rewrite H,H0. reflexivity. Qed.

(** The public query follows the controlled binding, including inherited
    bindings. It does not select a resource merely because paths coincide. *)
Theorem bound_resource_is_observed : forall payload caller value task owner tree,
 find_task (Selvedge.Generated.Commands.read_worktree_task_id payload) value=Some task ->
 settings_resource (task_current_settings task)=Some owner ->
 WorkspaceBinding.owned owner value=Some tree ->
 Worktree.query (Selvedge.Generated.Commands.Cmd_read_worktree payload) caller value=
 Some (success (Selvedge.Features.Observation.worktree_json tree)).
Proof.
 intros payload caller value task owner tree found reference resource.
 unfold Worktree.query. rewrite found. unfold Worktree.effective, WorkspaceBinding.for_task.
 rewrite found. rewrite (WorkspaceBinding.resolve_owned _ _ _ _ reference resource). reflexivity.
Qed.
Theorem unknown_task_has_no_binding : forall payload caller value,
 find_task (Selvedge.Generated.Commands.read_worktree_task_id payload) value=None ->
 Worktree.query (Selvedge.Generated.Commands.Cmd_read_worktree payload) caller value=
 Some (failure "task_not_found" "Task does not exist.").
Proof. intros; unfold Worktree.query; now rewrite H. Qed.

(** Cloud fork admission runs before the ordinary settings selection. Both
    workspace and project overrides are rejected by the actual feature guard. *)
Theorem cloud_fork_cannot_override_environment : forall payload caller value selected,
 WorkspaceBinding.cloud_task (Selvedge.Generated.Commands.fork_task_id payload) value=true ->
 Selvedge.Generated.Commands.fork_settings payload=Some selected ->
 (Json.equal (value_or_null "workspace" selected) JNull=false \/
  Json.equal (value_or_null "project_id" selected) JNull=false) ->
 Runtime.guard_command (Selvedge.Generated.Commands.Cmd_fork payload) caller value=
 Some (reject "cloud_workspace_fixed" "A cloud task keeps its bound workspace; forks inherit that environment" value).
Proof.
 intros payload caller value selected cloud settings override.
 unfold Runtime.guard_command, Runtime.or_else, Worktree.guard_command, Worktree.cloud_options_allowed.
 rewrite cloud,settings. cbn [negb orb].
 destruct override as [workspace|project]; rewrite ?workspace,?project,?Bool.andb_false_r; reflexivity.
Qed.
Theorem archiving_local_workspace_is_unavailable : forall space value tree root target,
 In tree (F.feature_worktrees (world_features value)) ->
 F.worktree_backend tree=WorkspaceBackend.Local ->
 F.worktree_phase tree=F.TreeArchiving root target ->
 Worktree.any_inside root (workspace_roots space)=true ->
 Worktree.workspace_available space value=false.
Proof.
 intros space value tree root target member backend phase uses.
 apply Bool.not_true_is_false. intro available.
 unfold Worktree.workspace_available in available.
 apply forallb_forall with (x:=tree) in available; [|exact member].
 rewrite backend,phase in available. cbn [WorkspaceBackend.cloud] in available.
 unfold F.worktree_root in available. rewrite phase,uses in available. discriminate.
Qed.

Theorem inherited_cloud_policy_is_full_access : forall settings value tree,
 WorkspaceBinding.resolve settings value=Some tree ->
 F.worktree_backend tree=WorkspaceBackend.TencentCvm ->
 settings_sandbox (WorkspaceBinding.normalize_settings settings value)=Sandbox WorkspaceWrite true /\
 settings_approval (WorkspaceBinding.normalize_settings settings value)=FullAccess.
Proof.
 intros settings value tree bound backend.
 unfold WorkspaceBinding.normalize_settings. rewrite bound,backend. split;reflexivity.
Qed.
Theorem mismatched_cloud_project_is_rejected : forall before result task,
 bool_default "ok" (decision_reply result) false=true ->
 find_task (next_task before) (decision_world result)=Some task ->
 Worktree.project_primary_matches (task_current_settings task) before=false ->
 Worktree.initialize_backend WorkspaceBackend.TencentCvm before result=
 reject "invalid_settings" "A cloud task must use its Project primary workspace" before.
Proof.
 intros before result task accepted found mismatch.
 unfold Worktree.initialize_backend. rewrite accepted,found,mismatch. reflexivity.
Qed.

(** The scheduler predicate used by Kernel.Packet excludes all non-ready
    managed environments, including a borrower's inherited resource. *)
Theorem admitted_scheduler_requires_ready_binding : forall id value tree,
 Runtime.can_schedule_task id value=true ->
 WorkspaceBinding.for_task id value=Some tree ->
 exists root target,F.worktree_phase tree=F.TreeReady root target.
Proof.
 intros id value tree admitted bound.
 unfold Runtime.can_schedule_task,Worktree.execution_ready in admitted.
 rewrite bound in admitted. apply Bool.andb_true_iff in admitted as [ready _].
 destruct (F.worktree_phase tree);try discriminate; eauto.
Qed.

(** Starting an environment binds the owner before any physical preparation
    completes. The real scheduler therefore cannot execute in the source
    workspace while the managed resource is still being created. *)
Theorem successful_initialization_binds_pending_owner : forall backend before result task,
 bool_default "ok" (decision_reply result) false = true ->
 find_task (next_task before) (decision_world result) = Some task ->
 bool_default "ok" (decision_reply (Worktree.initialize_backend backend before result)) false = true ->
 let initialized := Worktree.initialize_backend backend before result in
 exists tree,
   Worktree.lookup (next_task before) (decision_world initialized) = Some tree /\
   WorkspaceBinding.for_task (next_task before) (decision_world initialized) = Some tree /\
   F.worktree_backend tree = backend /\
   F.worktree_phase tree = F.TreeCreating false /\
   Runtime.can_schedule_task (next_task before) (decision_world initialized) = false.
Proof.
 intros backend before result task accepted found initialized.
 unfold Worktree.initialize_backend in initialized |- *.
 rewrite accepted, found in initialized |- *.
 destruct (WorkspaceBackend.cloud backend &&
   negb (Worktree.project_primary_matches (task_current_settings task) before));
   [discriminate|].
 destruct (negb (Workspace.valid_workspace
   (settings_workspace (task_current_settings (Worktree.resource_task (next_task before) backend task))) &&
   Workspace.valid_path (Worktree.primary
     (settings_workspace (task_current_settings (Worktree.resource_task (next_task before) backend task)))) &&
   Worktree.workspace_available
     (settings_workspace (task_current_settings (Worktree.resource_task (next_task before) backend task))) before));
   [discriminate|].
 cbn zeta.
 set (owner := next_task before).
 set (prepared := Worktree.resource_task owner backend task).
 set (tree := F.Worktree owner
   (Worktree.primary (settings_workspace (task_current_settings prepared)))
   (F.TreeCreating false) backend).
 set (staged := Worktree.store tree (put_task owner prepared (decision_world result))).
 assert (owned : Worktree.lookup owner staged = Some tree).
 { unfold staged. change (Worktree.lookup (F.worktree_task tree)
     (Worktree.store tree (put_task owner prepared (decision_world result))) = Some tree).
   apply stored_resource_is_the_lookup. }
 assert (selected : find_task owner staged = Some prepared).
 { unfold staged, find_task. rewrite store_preserves_tasks.
   eapply find_put_task. exact found. }
 assert (bound : WorkspaceBinding.for_task owner staged = Some tree).
 { unfold WorkspaceBinding.for_task. rewrite selected.
   unfold WorkspaceBinding.resolve.
   assert (reference : settings_resource (task_current_settings prepared) = Some owner).
   { unfold prepared, Worktree.resource_task, Worktree.resource_settings.
     destruct task; reflexivity. }
   rewrite reference. exact owned. }
 exists tree. split; [exact owned|]. split; [exact bound|].
 split; [reflexivity|]. split; [reflexivity|].
 change (Runtime.can_schedule_task owner staged = false).
 unfold Runtime.can_schedule_task, Worktree.execution_ready.
 rewrite bound. reflexivity.
Qed.

Theorem a_frozen_borrower_stays_frozen_during_setup :
 forall phase operations space guidance task,
 task_lifecycle task = Frozen phase operations ->
 task_lifecycle (Worktree.install_workspace (task_lifecycle task) space guidance task) = Frozen phase operations /\
 task_queued (Worktree.install_workspace (task_lifecycle task) space guidance task) = task_queued task.
Proof.
 intros phase operations space guidance [contract profile settings lifecycle history queued lineage parent cursor consumed] Frozen;
 cbn in Frozen; subst lifecycle; split; reflexivity.
Qed.

Theorem a_live_pending_binding_holds_its_owner : forall owner id value task tree archived,
 Worktree.lookup owner value = Some tree ->
 F.worktree_phase tree = F.TreeCreating archived ->
 In (id,task) (Numbers.indexed (fun id task => (id,task)) 0 (world_tasks value)) ->
 id <> owner -> Worktree.archived task = false ->
 settings_resource (contract_settings (task_contract task)) = Some owner ->
 Worktree.archive_allowed owner value = false.
Proof.
 intros owner id value task tree archived Found Pending Member Other Live Bound.
 unfold Worktree.archive_allowed; rewrite Found.
 unfold F.worktree_root; rewrite Pending.
 apply Bool.not_true_is_false; intro Available.
 unfold Worktree.bound_tasks_unused in Available.
 apply forallb_forall with (x:=(id,task)) in Available; [|exact Member].
 cbn in Available.
 assert (Different : N.eqb owner id = false) by (apply N.eqb_neq; congruence).
 rewrite Different, Live, Bound in Available; unfold Workspace.same_resource in Available.
 rewrite N.eqb_refl in Available; discriminate.
Qed.
