From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Codec WorkspaceBackend.
From Selvedge.Features Require Import Domain Worktree WorkspaceBinding Runtime.
Import ListNotations.
Module F:=Selvedge.Features.Domain.
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
