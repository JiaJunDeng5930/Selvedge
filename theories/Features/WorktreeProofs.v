From Selvedge.Foundation Require Import RegistryProofs.
From Stdlib Require Import String List Bool NArith Lia.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import Numbers Domain State Codec WorkspaceBackend LifecycleProofs Tasks.
From Selvedge.Features Require Import Domain Worktree WorkspaceBinding Runtime.
Import ListNotations.
Module F:=Selvedge.Features.Domain.

(** The public Interrupt and composed feature controls share this resource gate.
    Preparing an owner's workspace is a business refusal, with no tentative
    task or feature update for a later invariant gate to undo. *)
Theorem interrupt_pending_resource_is_rejected : forall id value tree,
 Worktree.execution_allowed id value = true ->
 Worktree.lookup id value = Some tree ->
 Worktree.pending tree = true ->
 Worktree.control_guard Tasks.Interrupt id value = Some
   (reject "worktree_pending"%string
     "Wait for worktree creation or archive the task before changing its execution"%string value).
Proof.
 intros id value tree executable found pending.
 unfold Worktree.control_guard, Worktree.execution_guard, Worktree.control_allowed.
 rewrite executable, found, pending. reflexivity.
Qed.

Theorem interrupt_admitted_resource_passes_shared_guard : forall id value,
 Worktree.control_allowed Tasks.Interrupt id value = true ->
 Worktree.control_guard Tasks.Interrupt id value = None.
Proof.
 intros id value admitted.
 pose proof admitted as executable.
 unfold Worktree.control_allowed in executable.
 apply Bool.andb_true_iff in executable as [executable _].
 unfold Worktree.control_guard, Worktree.execution_guard.
 rewrite executable, admitted. reflexivity.
Qed.

Theorem public_interrupt_uses_shared_resource_guard : forall payload caller value,
 Worktree.guard_command (Selvedge.Generated.Commands.Cmd_interrupt payload) caller value =
 Worktree.control_guard Tasks.Interrupt
   (Selvedge.Generated.Commands.interrupt_task_id payload) value.
Proof. reflexivity. Qed.

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
Lemma completing_bindings_preserves_the_owner : forall owner space guidance value task,
 find_task owner value = Some task ->
 find_task owner (Worktree.complete_bindings owner space guidance value) = Some task.
Proof.
 intros owner space guidance value task Found.
 unfold Worktree.complete_bindings, with_tasks, find_task; cbv [set]; cbn [world_tasks].
 rewrite (Selvedge.Foundation.RegistryProofs.registry_lookup_at_numbered_map _ _ _ _ 0 owner task Found).
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
 rewrite (Selvedge.Foundation.RegistryProofs.registry_lookup_at_numbered_map _ _ _ _ 0 id task Found).
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

Theorem an_unavailable_resource_cannot_be_selected_by_a_new_task : forall before result id task,
 In (id,task) (indexed (fun id task=>(id,task)) 0 (world_tasks (decision_world result))) ->
 Selvedge.Kernel.State.find_task id before=None ->
 Worktree.binding_available (task_current_settings task) (decision_world result)=false ->
 decision_world (Worktree.guard_result before result)=before /\
 decision_effects (Worktree.guard_result before result)=nil.
Proof.
 intros before result id task Member Missing Unavailable.
 unfold Worktree.guard_result.
 destruct (List.forallb _ _) eqn:Available; [|split;reflexivity].
 apply forallb_forall with (x:=(id,task)) in Available; [|exact Member].
 cbn beta iota zeta delta [fst snd] in Available.
 rewrite Missing, Unavailable, andb_false_r in Available. discriminate.
Qed.

(** Host jobs hold local roots. A frozen cloud selection is a different resource
    even when its path text is identical. *)
Theorem running_connection_job_blocks_local_archive : forall owner root value tree id job,
 Worktree.lookup owner value=Some tree -> F.worktree_backend tree=WorkspaceBackend.Local ->
 In (id,job) (F.sharing_jobs (F.feature_sharing (world_features value))) ->
 F.job_state job=F.JobRunning -> F.job_resource job=None ->
 Worktree.any_inside root (workspace_roots (F.job_workspace job))=true ->
 Worktree.root_unused owner root value=false.
Proof.
 intros owner root value tree id job found backend member running resource uses.
 apply Bool.not_true_is_false. intro available.
 unfold Worktree.root_unused in available. rewrite found,backend in available.
 apply Bool.andb_true_iff in available as [_ jobs].
 apply forallb_forall with (x:=(id,job)) in jobs; [|exact member].
 cbn in jobs. unfold Worktree.job_uses_root in jobs. rewrite running,resource,uses in jobs. discriminate.
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
 Worktree.handle_read_worktree payload caller value=
 success (Selvedge.Features.Observation.worktree_json tree).
Proof.
 intros payload caller value task owner tree found reference resource.
 unfold Worktree.handle_read_worktree. rewrite found. unfold Worktree.effective, WorkspaceBinding.for_task.
 rewrite found. rewrite (WorkspaceBinding.resolve_owned _ _ _ _ reference resource). reflexivity.
Qed.
Theorem unknown_task_has_no_binding : forall payload caller value,
 find_task (Selvedge.Generated.Commands.read_worktree_task_id payload) value=None ->
 Worktree.handle_read_worktree payload caller value=
 failure "task_not_found" "Task does not exist.".
Proof. intros; unfold Worktree.handle_read_worktree; now rewrite H. Qed.

(** Cloud fork admission runs before the ordinary settings selection. Both
    workspace and project overrides are rejected by the actual feature guard. *)
Theorem cloud_fork_selection_retains_its_environment : forall parent value selected,
 WorkspaceBinding.resolve (task_current_settings parent) value = Some selected ->
 WorkspaceBackend.cloud (F.worktree_backend selected) = true ->
 forall admission : Tasks.admitted_fork_selection parent value,
 Workspace.same_resource (settings_resource (Tasks.fork_selected parent value admission)) (Some (F.worktree_task selected)) = true /\
 Json.equal (workspace_json (settings_workspace (Tasks.fork_selected parent value admission)))
   (workspace_json (settings_workspace (task_current_settings parent))) = true /\
 Workspace.same_resource (settings_project (Tasks.fork_selected parent value admission))
   (settings_project (task_current_settings parent)) = true.
Proof.
 intros parent value selected Found Cloud admission.
 pose proof (Tasks.fork_environment_fixed parent value admission) as Fixed.
 unfold Tasks.fork_selection_fixed in Fixed. rewrite Found, Cloud in Fixed.
 repeat rewrite andb_true_iff in Fixed. tauto.
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
 unfold F.worktree_root in available. unfold Worktree.any_inside,Worktree.inside in uses.
 rewrite phase,uses in available. discriminate.
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
Theorem mismatched_cloud_project_is_rejected : forall before intent settings,
 Worktree.project_primary_matches settings before=false ->
 Worktree.resource_error intent before settings Worktree.ProvisionCloud=Some Tasks.ProjectPrimaryMismatch.
Proof. intros; unfold Worktree.resource_error; cbn [WorkspaceBackend.cloud]; now rewrite H. Qed.

(** The scheduler predicate used by Kernel.Packet excludes all non-ready
    managed environments, including a borrower's inherited resource. *)
Theorem admitted_scheduler_requires_ready_binding : forall id value tree,
 Runtime.can_schedule_task id value=true ->
 WorkspaceBinding.for_task id value=Some tree ->
 exists root target,F.worktree_phase tree=F.TreeReady root target.
Proof.
 intros id value tree admitted bound.
 unfold Runtime.can_schedule_task,Worktree.execution_ready,WorkspaceBinding.execution_ready in admitted.
 apply Bool.andb_true_iff in admitted as [ready _].
 unfold WorkspaceBinding.for_task in bound.
 destruct (find_task id value) as [task|] eqn:Found; [|discriminate].
 unfold WorkspaceBinding.settings_execution_ready in ready. rewrite bound in ready.
 destruct (F.worktree_phase tree);try discriminate; eauto.
Qed.

(** Starting an environment binds the owner before any physical preparation
    completes. The real scheduler therefore cannot execute in the source
    workspace while the managed resource is still being created. *)
Local Lemma provisioned_birth_binds_pending_owner : forall backend before task,
 let owner:=next_task before in
 let prepared:=Worktree.resource_task owner backend task in
 let tree:=F.Worktree owner (Worktree.primary (settings_workspace (task_current_settings prepared)))
   (F.TreeCreating false) backend in
 let staged:=Worktree.store tree (append_task prepared before) in
 Worktree.lookup owner staged=Some tree /\
 WorkspaceBinding.for_task owner staged=Some tree /\
 Runtime.can_schedule_task owner staged=false.
Proof.
 intros backend before task owner prepared tree staged.
 assert (owned:Worktree.lookup owner staged=Some tree).
 { unfold staged. change (Worktree.lookup (F.worktree_task tree)
     (Worktree.store tree (append_task prepared before))=Some tree).
   apply stored_resource_is_the_lookup. }
 assert (selected:find_task owner staged=Some prepared).
 { unfold staged,find_task. rewrite store_preserves_tasks,task_creation_never_rewrites_existing_history.
   apply Selvedge.Foundation.RegistryProofs.registry_lookup_at_appended_index. }
 assert (bound:WorkspaceBinding.for_task owner staged=Some tree).
 { unfold WorkspaceBinding.for_task. rewrite selected. unfold WorkspaceBinding.resolve.
   assert (reference:settings_resource (task_current_settings prepared)=Some owner).
   { unfold prepared,Worktree.resource_task,Worktree.resource_settings; destruct task; reflexivity. }
   rewrite reference. exact owned. }
 split; [exact owned|]. split; [exact bound|].
 unfold Runtime.can_schedule_task,Worktree.execution_ready,WorkspaceBinding.execution_ready,
   WorkspaceBinding.settings_execution_ready. rewrite selected.
 unfold WorkspaceBinding.for_task in bound. rewrite selected in bound. rewrite bound. reflexivity.
Qed.
Theorem successful_initialization_binds_pending_owner : forall backend before intent start
 (admitted:Worktree.resource_error intent before (Tasks.start_settings start)
   (match backend with WorkspaceBackend.Local=>Worktree.ProvisionLocal
    | WorkspaceBackend.TencentCvm=>Worktree.ProvisionCloud end)=None),
 let plan:=Worktree.PlannedStart intent start
   (match backend with WorkspaceBackend.Local=>Worktree.ProvisionLocal
    | WorkspaceBackend.TencentCvm=>Worktree.ProvisionCloud end) admitted in
 let initialized:=Worktree.consume_planned_start plan before in
 exists tree,
 Worktree.lookup (next_task before) (decision_world initialized)=Some tree /\
 WorkspaceBinding.for_task (next_task before) (decision_world initialized)=Some tree /\
 F.worktree_backend tree=backend /\ F.worktree_phase tree=F.TreeCreating false /\
 Runtime.can_schedule_task (next_task before) (decision_world initialized)=false.
Proof.
 intros backend before intent start admitted.
 pose proof (provisioned_birth_binds_pending_owner backend before (Tasks.start_task start)) as Birth.
 cbv zeta in Birth |- *.
 destruct backend; cbn [Worktree.consume_planned_start Worktree.interpret_planned_birth Worktree.born_decision Worktree.born_world Worktree.born_effects Worktree.born_identity Worktree.planned_task Worktree.planned_resource
   Tasks.birth_prepared Tasks.birth_world Selvedge.Kernel.State.accept decision_world] in *.
 all: destruct Birth as [Owned [Bound Ready]]; eexists; repeat split; eauto.
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
 In (id,task) (Selvedge.Foundation.Registry.indexed (fun id task => (id,task)) 0 (world_tasks value)) ->
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

Theorem running_connection_job_blocks_its_cloud_archive : forall owner root value tree id job,
 Worktree.lookup owner value=Some tree -> F.worktree_backend tree=WorkspaceBackend.TencentCvm ->
 In (id,job) (F.sharing_jobs (F.feature_sharing (world_features value))) ->
 F.job_state job=F.JobRunning -> F.job_resource job=Some owner ->
 Worktree.root_unused owner root value=false.
Proof.
 intros owner root value tree id job Found Backend Member Running Resource.
 apply Bool.not_true_is_false. intro Available.
 unfold Worktree.root_unused in Available. rewrite Found,Backend in Available.
 apply Bool.andb_true_iff in Available as [_ Jobs].
 apply forallb_forall with (x:=(id,job)) in Jobs; [|exact Member].
 cbn in Jobs. unfold Worktree.job_uses_resource in Jobs.
 rewrite Running,Resource in Jobs. unfold Workspace.same_resource in Jobs.
 rewrite N.eqb_refl in Jobs. discriminate.
Qed.

Theorem reusing_a_binding_never_provisions_another_resource :
 forall before intent start owner tree observed admitted,
 decision_effects (Worktree.consume_planned_start
   (@Worktree.PlannedStart before intent start
     (@Worktree.ReuseBinding before (Tasks.start_settings start) owner tree observed) admitted) before) = [].
Proof. intros; reflexivity. Qed.
Theorem planned_birth_changes_only_tasks_and_worktrees : forall before (plan:Worktree.planned_start before) current,
 let result:=decision_world (Worktree.consume_planned_start plan current) in
 with_tasks (world_tasks current)
   (with_features (Selvedge.Features.State.with_worktrees
     (F.feature_worktrees (world_features current)) (world_features result)) result) = current.
Proof.
 intros before [intent start resource admitted] current.
 destruct resource; destruct current as [sequence tasks ticket environment projects features];
 destruct features; reflexivity.
Qed.
Theorem an_observed_binding_takes_priority_over_automatic_worktree_preference :
 forall before settings owner,
 settings_resource settings = Some owner ->
 Worktree.select_creation_plan before settings None None = Worktree.reuse_plan before settings owner.
Proof. intros before settings owner Bound. unfold Worktree.select_creation_plan; rewrite Bound; reflexivity. Qed.
Theorem explicit_provision_rejects_an_observed_cloud_source : forall before backend settings tree,
 WorkspaceBinding.resolve settings before = Some tree ->
 WorkspaceBackend.cloud (F.worktree_backend tree) = true ->
 Worktree.provision_plan before backend settings = None.
Proof. intros before backend settings tree Observed Cloud. unfold Worktree.provision_plan; rewrite Observed, Cloud; reflexivity. Qed.

Theorem planned_birth_appends_exactly_one_task : forall before (plan:Worktree.planned_start before) current,
 exists created, world_tasks (decision_world (Worktree.consume_planned_start plan current)) = (world_tasks current ++ [created])%list.
Proof.
 intros before [intent start resource admitted] current.
 destruct resource; unfold Worktree.consume_planned_start, Worktree.interpret_planned_birth, Worktree.born_decision, Worktree.born_world, Worktree.born_effects, Worktree.born_identity;
 cbn [Worktree.planned_task Worktree.planned_resource Tasks.birth_prepared Tasks.birth_world
   Selvedge.Kernel.State.accept decision_world]; eexists; reflexivity.
Qed.
Theorem planned_birth_preserves_existing_tasks : forall before (plan:Worktree.planned_start before) current id task,
 find_task id current=Some task ->
 find_task id (decision_world (Worktree.consume_planned_start plan current))=Some task.
Proof.
 intros before plan current id task Found.
 destruct (planned_birth_appends_exactly_one_task before plan current) as [created Appended].
 unfold find_task. rewrite Appended.
 apply Selvedge.Foundation.RegistryProofs.registry_lookup_preserved_by_append. exact Found.
Qed.


Theorem scoped_birth_preserves_existing_tasks : forall origin before
 (created : Worktree.start_transition origin before) id task,
 find_task id before=Some task ->
 find_task id (Worktree.transition_world created)=Some task.
Proof.
 intros origin before created id task Found.
 unfold find_task; rewrite Worktree.transition_tasks_are_the_witnessed_birth.
 apply Selvedge.Foundation.RegistryProofs.registry_lookup_preserved_by_append; exact Found.
Qed.
Theorem attach_planned_birth_preserves_existing_tasks : forall before
 (owner : Work.owner_scope before) (plan : Worktree.scoped_start before) id task,
 find_task id before=Some task ->
 find_task id (decision_world (Worktree.attach_planned_birth owner plan))=Some task.
Proof.
 intros; apply scoped_birth_preserves_existing_tasks; exact H.
Qed.
Theorem consume_start_resolution_preserves_existing_tasks : forall intent settings caller managed backend cached value id task,
 find_task id value=Some task ->
 find_task id (decision_world (Worktree.consume_start_resolution intent settings caller managed backend cached value))=Some task.
Proof.
 intros intent settings caller managed backend cached value id task Found.
 unfold Worktree.consume_start_resolution, Worktree.resolve_start_birth.
 destruct cached as [cause|start]; [exact Found|].
 destruct (Worktree.start_allowed settings caller value (Tasks.StartResolved start)); [|exact Found].
 destruct (Worktree.prepare_scoped intent caller managed backend start value) as [plan|reply];
 [apply scoped_birth_preserves_existing_tasks; exact Found|exact Found].
Qed.
Theorem create_selected_preserves_existing_tasks : forall name effort contents settings idle caller managed value id task,
 find_task id value=Some task ->
 find_task id (decision_world (Worktree.create_selected name effort contents settings idle caller managed value))=Some task.
Proof.
 intros. unfold Worktree.create_selected,Worktree.create_selected_result,Worktree.create_intent_result.
 apply consume_start_resolution_preserves_existing_tasks. exact H.
Qed.
Theorem a_batch_preserves_original_task_observations : forall original current
 (frame : Worktree.birth_frame original current) id task,
 find_task id original = Some task -> find_task id current = Some task.
Proof.
 intros original current frame; induction frame as [|current frame IH plan owner works]; intros id task Found.
 - exact Found.
 - specialize (IH id task Found).
   destruct owner;
   change (find_task id (Worktree.born_world
     (Worktree.interpret_planned_birth (Worktree.scoped_plan plan) current)) = Some task);
   apply planned_birth_preserves_existing_tasks; exact IH.
Qed.

(** Failure rendering remains attached to the actual typed resolvers.  A
    caller can branch on Created without inferring creation from reply JSON. *)
Lemma resolved_start_replies_are_failures : forall intent managed backend start before,
 match Worktree.prepare_resolved intent managed backend start before with
 | Worktree.Planned _ => True
 | Worktree.PlanningFailed reply => bool_default "ok" reply false = false end.
Proof.
 intros. unfold Worktree.prepare_resolved.
 destruct (Worktree.select_creation_plan before (Tasks.start_settings start) managed backend) as [plan|];
 [|reflexivity].
 generalize (eq_refl (Worktree.resource_error intent before (Tasks.start_settings start) plan)).
 generalize (Worktree.resource_error intent before (Tasks.start_settings start) plan) at 2 3.
 intros [cause|] Admitted; [reflexivity|exact I].
Qed.
Lemma scoped_start_replies_are_failures : forall intent caller managed backend start before,
 match Worktree.prepare_scoped intent caller managed backend start before with
 | Worktree.ScopedPlanned _ => True
 | Worktree.ScopedPlanningFailed reply => bool_default "ok" reply false = false end.
Proof.
 intros. pose proof (resolved_start_replies_are_failures intent managed backend start before) as Refused.
 unfold Worktree.prepare_scoped.
 destruct (Worktree.prepare_resolved intent managed backend start before) as [plan|reply]; [|exact Refused].
 destruct (Bool.bool_dec (Worktree.final_authority caller plan) true); [exact I|reflexivity].
Qed.
Theorem rejected_selected_creation_has_a_failure_reply : forall name effort contents settings idle caller managed before reply,
 Worktree.create_selected_result name effort contents settings idle caller managed before = Worktree.CreationRejected reply ->
 bool_default "ok" reply false = false.
Proof.
 intros name effort contents settings idle caller managed before reply Rejected.
 unfold Worktree.create_selected_result,Worktree.create_intent_result,Worktree.resolve_start_birth in Rejected.
 destruct (CommandExecution.resolve_context_start
  (Worktree.creation_entry (if idle then Worktree.IdleTaskCreation else Worktree.ImplicitCreation) caller)
  name effort contents settings idle caller before) as [cause|start];
 [inversion Rejected; reflexivity|].
 destruct (Worktree.start_allowed settings caller before (Tasks.StartResolved start));
 [|inversion Rejected; reflexivity].
 pose proof (scoped_start_replies_are_failures
  (if idle then Worktree.IdleTaskCreation else Worktree.ImplicitCreation) caller managed None start before) as Refused.
 destruct (Worktree.prepare_scoped
  (if idle then Worktree.IdleTaskCreation else Worktree.ImplicitCreation) caller managed None start before)
  as [plan|failure]; [discriminate|].
 inversion Rejected; subst failure; exact Refused.
Qed.
