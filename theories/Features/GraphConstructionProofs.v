From Selvedge.Programming Require CommandResult.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Schema.
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
   name (Some effort) contents
   (Some settings) false None before); reflexivity.
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
   CommandResult.accept (TaskGraph.install_change (N.of_nat (List.length (TaskGraph.registry before))) plan).
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
Theorem public_idle_missing_work_is_atomic : forall request before owner,
 G.create_idle_work_id request = Some owner ->
 Work.lookup owner before = None ->
 let refused := Worktree.handle_create_idle request None before in
 bool_default "ok" (decision_reply refused) true = false /\
 decision_world refused = before /\ decision_effects refused = [].
Proof.
 intros request before owner Owner Missing.
 unfold Worktree.handle_create_idle,Worktree.create_idle_owned.
 destruct (CommandExecution.resolve_context_start
   (G.create_idle_profile request) (G.create_idle_reasoning request) []
   (option_map (Codec.settings_request_of_values true) (G.create_idle_settings_admitted request)) true None before).
 - repeat split; reflexivity.
 - rewrite Owner,(Work.select_missing_owner owner before Missing); repeat split; reflexivity.
Qed.
