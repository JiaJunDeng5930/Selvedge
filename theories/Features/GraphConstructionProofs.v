From Selvedge.Kernel Require CommandResult.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import Domain State Codec Tasks CommandExecution.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Domain Work Worktree TaskGraph TaskGraphProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Module F := Selvedge.Features.Domain.
Module G := Selvedge.Generated.Commands.

(** These are universal properties of the production construction entry. The
    provider/native round-trip remains an integration obligation of its own. *)
Lemma public_cached_nodes_have_no_task_caller_gate : forall before nodes,
 forallb (TaskGraph.cached_allowed None before)
   (map (TaskGraph.cache_node None before) nodes) = true.
Proof.
 intros before nodes; induction nodes as [|node rest IH]; [reflexivity|].
 cbn [map forallb]. rewrite IH, andb_true_r.
 destruct node as [key id|key name effort contents settings]; [reflexivity|].
 unfold TaskGraph.cached_allowed,TaskGraph.cache_node.
 unfold Worktree.start_allowed.
 destruct (CommandExecution.resolve_context_start
   (Worktree.creation_entry Worktree.GraphTaskCreation None) name (Some effort) contents
   (Some settings) false None before); reflexivity.
Qed.

Theorem public_missing_work_precedes_graph_capacity_and_semantics : forall request before owner,
 G.create_task_graph_work_id request = Some owner ->
 Work.lookup owner before = None ->
 TaskGraph.handle_create_task_graph request None before =
 reject "work_not_found" "The Work does not exist." before.
Proof.
 intros request before owner Owner Missing.
 unfold TaskGraph.handle_create_task_graph,TaskGraph.declare,TaskGraph.declare_result.
 rewrite Owner.
 cbn [TaskGraph.cache_declaration TaskGraph.cached_nodes].
 destruct (Bool.bool_dec _ true) as [Authorized|Denied].
 2: { exfalso; apply Denied; apply public_cached_nodes_have_no_task_caller_gate. }
 unfold TaskGraph.select_owner; rewrite Work.select_missing_owner by exact Missing.
 reflexivity.
Qed.
Theorem public_graph_capacity_precedes_declaration_semantics : forall request before owner,
 TaskGraph.select_owner (G.create_task_graph_work_id request) before = Some owner ->
 TaskGraph.graph_capacity before = false ->
 TaskGraph.handle_create_task_graph request None before =
 reject "invalid_task_graph" "At most 32 live Task graphs may be installed" before.
Proof.
 intros request before owner Owner Full.
 unfold TaskGraph.handle_create_task_graph,TaskGraph.declare,TaskGraph.declare_result.
 cbn [TaskGraph.cache_declaration TaskGraph.cached_nodes].
 destruct (Bool.bool_dec _ true) as [Authorized|Denied].
 2: { exfalso; apply Denied; apply public_cached_nodes_have_no_task_caller_gate. }
 rewrite Owner,Full; reflexivity.
Qed.

Theorem public_resolved_graph_installs_its_exact_typed_plan : forall request before owner plans,
 let source := TaskGraph.create_declaration request in
 TaskGraph.select_owner (G.create_task_graph_work_id request) before = Some owner ->
 TaskGraph.graph_capacity before = true ->
 TaskGraph.valid_declaration source = true ->
 TaskGraph.prepare_nodes (TaskGraph.scope_identity owner) None before
   (map (TaskGraph.cache_node None before) (TaskGraph.declaration_nodes source)) = CommandResult.Accepted plans ->
 exists plan : TaskGraph.graph_plan before None owner,
 TaskGraph.cached_source (TaskGraph.checked_cache (TaskGraph.graph_checked plan)) = source /\
 TaskGraph.graph_plans plan = plans /\
 TaskGraph.handle_create_task_graph request None before =
   TaskGraph.install_plan (N.of_nat (List.length (TaskGraph.registry before))) plan.
Proof.
 intros request before owner plans source Owner Capacity Valid Prepared.
 unfold TaskGraph.handle_create_task_graph,TaskGraph.declare,TaskGraph.declare_result.
 fold source.
 cbn [TaskGraph.cache_declaration TaskGraph.cached_nodes].
 destruct (Bool.bool_dec _ true) as [Authorized|Denied].
 2: { exfalso; apply Denied; apply public_cached_nodes_have_no_task_caller_gate. }
 rewrite Owner,Capacity.
 cbn [negb orb].
 unfold TaskGraph.construct_cached.
 cbn [TaskGraph.cache_declaration TaskGraph.cached_source].
 destruct (Bool.bool_dec (TaskGraph.valid_declaration source) true) as [Admitted|Denied].
 2: { contradiction. }
 exists (TaskGraph.GraphPlan
   (TaskGraph.CheckedCached (TaskGraph.cache_declaration None before source) Authorized Admitted)
   plans Prepared).
 split; [reflexivity|split; [reflexivity|]].
 apply TaskGraphProofs.resolved_installation_follows_the_typed_plan.
Qed.

Lemma failed_installation_is_atomic : forall original caller
 (owner : option (Work.owner_scope original)) id (checked : TaskGraph.checked_cached caller original),
 bool_default "ok" (decision_reply (TaskGraph.install_cached id owner checked)) false = false ->
 decision_world (TaskGraph.install_cached id owner checked) = original /\
 decision_effects (TaskGraph.install_cached id owner checked) = [].
Proof. intros; now apply CommandResult.a_failed_command_is_atomic. Qed.
Theorem every_failed_graph_declaration_is_atomic : forall creating id owner source caller before,
 let result := TaskGraph.declare creating id owner source caller before in
 bool_default "ok" (decision_reply result) false = false ->
 decision_world result = before /\ decision_effects result = [].
Proof. intros; now apply CommandResult.a_failed_command_is_atomic. Qed.
Theorem failed_create_graph_keeps_the_complete_world : forall request caller before,
 bool_default "ok" (decision_reply (TaskGraph.handle_create_task_graph request caller before)) false = false ->
 decision_world (TaskGraph.handle_create_task_graph request caller before) = before /\
 decision_effects (TaskGraph.handle_create_task_graph request caller before) = [].
Proof. intros; apply every_failed_graph_declaration_is_atomic; exact H. Qed.
Theorem failed_update_graph_keeps_the_complete_world : forall request caller before,
 bool_default "ok" (decision_reply (TaskGraph.handle_update_task_graph request caller before)) false = false ->
 decision_world (TaskGraph.handle_update_task_graph request caller before) = before /\
 decision_effects (TaskGraph.handle_update_task_graph request caller before) = [].
Proof.
 intros request caller before.
 unfold TaskGraph.handle_update_task_graph.
 destruct (TaskGraph.lookup (G.update_task_graph_graph_id request) before);
 [apply every_failed_graph_declaration_is_atomic|intros; split; reflexivity].
Qed.

(** An existing-node constructor retains the exact original-world observation.
    Other nodes may be appended first, but cannot supply a provisional identity
    for this branch. Reusing the same original Task under distinct keys is valid. *)
Theorem existing_birth_keeps_its_original_identity : forall original
 (owner : option (Work.owner_scope original)) key id task observed membership progress,
 TaskGraph.born_nodes (TaskGraph.birth owner
   (@TaskGraph.ExistingPlan original (TaskGraph.scope_identity owner) key id task observed membership) progress) =
   TaskGraph.born_nodes progress ++ [F.ResolvedNode key id] /\
 find_task id original = Some task /\
 TaskGraph.born_world (TaskGraph.birth owner
   (@TaskGraph.ExistingPlan original (TaskGraph.scope_identity owner) key id task observed membership) progress) =
   TaskGraph.born_world progress.
Proof. intros; split; [reflexivity|split; [exact observed|reflexivity]]. Qed.
Theorem spawned_birth_uses_the_actual_fresh_identity : forall original
 (owner : option (Work.owner_scope original)) key plan progress,
 TaskGraph.born_nodes (TaskGraph.birth owner (TaskGraph.SpawnPlan key plan) progress) =
 TaskGraph.born_nodes progress ++ [F.ResolvedNode key (next_task (TaskGraph.born_world progress))].
Proof.
 intros. cbn [TaskGraph.birth TaskGraph.born_nodes].
 rewrite Worktree.transition_identity_is_fresh; reflexivity.
Qed.
Theorem an_ordinary_start_failure_retains_its_declared_error : forall owner caller original key settings cause,
 TaskGraph.prepare_node owner caller original (TaskGraph.CachedSpawn key settings (Tasks.StartRefused cause)) =
 CommandResult.Rejected (CommandResult.Refusal (Tasks.failure_code (Worktree.creation_entry Worktree.GraphTaskCreation caller) cause)
   (Tasks.failure_message cause)).
Proof. reflexivity. Qed.
Theorem the_first_refused_node_prevents_every_birth : forall owner caller original node rest reason,
 TaskGraph.prepare_node owner caller original node = CommandResult.Rejected reason ->
 TaskGraph.prepare_nodes owner caller original (node::rest) = CommandResult.Rejected reason.
Proof. intros; now apply CommandResult.traverse_refuses_first. Qed.
Theorem later_refusal_prevents_every_birth : forall owner caller original node rest plan reason,
 TaskGraph.prepare_node owner caller original node = CommandResult.Accepted plan ->
 TaskGraph.prepare_nodes owner caller original rest = CommandResult.Rejected reason ->
 TaskGraph.prepare_nodes owner caller original (node::rest) = CommandResult.Rejected reason.
Proof. intros; eapply CommandResult.traverse_refuses_tail; eassumption. Qed.

Theorem public_idle_profile_failure_precedes_work_lookup : forall request before cause,
 CommandExecution.resolve_context_start (Worktree.creation_entry Worktree.IdleTaskCreation None)
   (G.create_idle_profile request) (G.create_idle_reasoning request) []
   (option_map (Codec.settings_request_of_values true) (G.create_idle_settings_admitted request)) true None before = Tasks.StartRefused cause ->
 Worktree.handle_create_idle request None before =
 Tasks.refuse_start (Worktree.creation_entry Worktree.IdleTaskCreation None) cause before.
Proof. intros; unfold Worktree.handle_create_idle,Worktree.create_idle_owned; now rewrite H. Qed.
Theorem public_idle_missing_work_follows_successful_profile_resolution : forall request before start owner,
 G.create_idle_work_id request = Some owner ->
 CommandExecution.resolve_context_start (Worktree.creation_entry Worktree.IdleTaskCreation None)
   (G.create_idle_profile request) (G.create_idle_reasoning request) []
   (option_map (Codec.settings_request_of_values true) (G.create_idle_settings_admitted request)) true None before = Tasks.StartResolved start ->
 Work.lookup owner before = None ->
 Worktree.handle_create_idle request None before =
 reject "invalid_arguments" "The Work does not exist." before.
Proof.
 intros request before start owner Owner Started Missing.
 unfold Worktree.handle_create_idle,Worktree.create_idle_owned.
 rewrite Started,Owner,(Work.select_missing_owner owner before Missing); reflexivity.
Qed.
