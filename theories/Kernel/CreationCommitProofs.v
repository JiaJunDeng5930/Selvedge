From Selvedge.Programming Require CommitPacket.
From Selvedge.Programming Require CommandResult.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json RegistryProofs.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Numbers Domain Codec State Inputs Tasks CommandExecution
 CreationCommit Delivery Notifications.
From Selvedge.Features Require Import Worktree.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.

Definition requested_start (request : G.create_payload) contents before :=
 CommandExecution.resolve_context_start
   (G.create_profile request) (G.create_reasoning request) contents
   (option_map (settings_request_of_values true) (G.create_settings_admitted request)) false None before.
Definition planned_decision {before : world} (plan : Worktree.planned_start before) :=
 let born := Worktree.interpret_planned_birth plan before in
 Decision (Worktree.born_world born) (success (JObject [("task_id",number (next_task before))]))
   (Worktree.born_effects born ++ [ContinueScheduling]).

Theorem every_resolved_public_create_constructs_its_planned_result :
 forall request contents before start (plan : Worktree.planned_start before),
 CommandExecution.user_content (G.create_message_admitted request) (G.create_images_admitted request) = Some contents ->
 requested_start request contents before = Tasks.StartResolved start ->
 Worktree.prepare_resolved Worktree.ImplicitCreation None None start before = CommandResult.Accepted plan ->
 CreationCommit.candidate request before = planned_decision plan.
Proof.
 intros request contents before start plan Parsed Resolved Prepared.
 unfold CreationCommit.candidate, Worktree.handle_create_result, CommandExecution.content_result.
 rewrite Parsed. cbn [CommandResult.bind]. unfold Worktree.create_selected_result,
   Worktree.create_intent_result, Worktree.resolve_start_birth.
 fold (requested_start request contents before).
 rewrite Resolved. cbn [Worktree.start_allowed CommandExecution.creation_allowed].
 unfold Worktree.prepare_selected_birth,Worktree.prepare_scoped. rewrite Prepared.
 cbn [Worktree.final_authority].
 change (Decision (Worktree.born_world (Worktree.interpret_planned_birth plan before))
   (success (JObject [("task_id",number (Worktree.born_identity (Worktree.interpret_planned_birth plan before)))]))
   (Worktree.born_effects (Worktree.interpret_planned_birth plan before) ++ [ContinueScheduling]) = planned_decision plan).
 unfold planned_decision,Worktree.born_identity.
 rewrite TaskBirth.birth_fresh. reflexivity.
Qed.

Theorem every_planned_creation_with_an_output_budget_is_delivered :
 forall request contents before start (plan : Worktree.planned_start before),
 CommandExecution.user_content (G.create_message_admitted request) (G.create_images_admitted request) = Some contents ->
 requested_start request contents before = Tasks.StartResolved start ->
 Worktree.prepare_resolved Worktree.ImplicitCreation None None start before = CommandResult.Accepted plan ->
 Delivery.fits true (planned_decision plan) = true ->
 CommitPacket.finalize before (CreationCommit.select request before) =
 (with_sequence (N.succ (world_sequence before)) (Worktree.born_world (Worktree.interpret_planned_birth plan before)),
  Notifications.envelope true true (Some (UserCommand (G.Cmd_create request))) before (planned_decision plan)).
Proof.
 intros request contents before start plan Parsed Resolved Prepared Fits.
 unfold CreationCommit.select, CommitPacket.choose.
 rewrite (every_resolved_public_create_constructs_its_planned_result request contents before start plan Parsed Resolved Prepared).
 unfold Delivery.deliver_with_status; rewrite Fits; reflexivity.
Qed.
