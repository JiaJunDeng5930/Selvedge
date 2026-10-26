From Selvedge.Kernel Require CommandResult.
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
 CommandExecution.resolve_context_start (Worktree.creation_entry Worktree.ImplicitCreation None)
   (G.create_profile request) (G.create_reasoning request) contents
   (G.create_settings request) false None before.
Definition planned_decision {before : world} (plan : Worktree.planned_start before) :=
 let born := Worktree.consume_planned_start plan before in
 Decision (decision_world born) (success (JObject [("task_id",number (next_task before))]))
   (decision_effects born ++ [ContinueScheduling]).

Lemma every_planned_start_has_its_exact_positive_reply : forall before (plan : Worktree.planned_start before),
 decision_reply (Worktree.consume_planned_start plan before) =
   success (JObject [("task_id",number (next_task before))]).
Proof.
 intros before [intent start resource admitted].
 unfold Worktree.consume_planned_start, Worktree.interpret_planned_birth, Worktree.born_decision, Worktree.born_world, Worktree.born_effects, Worktree.born_identity; cbn [Worktree.planned_task Worktree.planned_resource].
 destruct resource; reflexivity.
Qed.

Theorem every_resolved_public_create_constructs_its_planned_result :
 forall request contents before start (plan : Worktree.planned_start before),
 CommandExecution.user_content (G.create_message request) (G.create_images request) = Some contents ->
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
 unfold Worktree.prepare_scoped. rewrite Prepared.
 cbn [Worktree.final_authority].
 change ((let born := Worktree.consume_planned_start plan before in
   Decision (decision_world born) (decision_reply born)
     (decision_effects born ++ [ContinueScheduling])) = planned_decision plan).
 cbv zeta.
 rewrite every_planned_start_has_its_exact_positive_reply.
 reflexivity.
Qed.

Theorem every_planned_creation_with_an_output_budget_is_delivered :
 forall request contents before start (plan : Worktree.planned_start before),
 CommandExecution.user_content (G.create_message request) (G.create_images request) = Some contents ->
 requested_start request contents before = Tasks.StartResolved start ->
 Worktree.prepare_resolved Worktree.ImplicitCreation None None start before = CommandResult.Accepted plan ->
 Delivery.fits true (planned_decision plan) = true ->
 CreationCommit.packet request before =
 (with_sequence (N.succ (world_sequence before)) (decision_world (Worktree.consume_planned_start plan before)),
  Notifications.envelope true true (Some (UserCommand (G.Cmd_create request))) before (planned_decision plan)).
Proof.
 intros request contents before start plan Parsed Resolved Prepared Fits.
 unfold CreationCommit.packet, CreationCommit.select, CommitPacket.choose.
 rewrite (every_resolved_public_create_constructs_its_planned_result request contents before start plan Parsed Resolved Prepared).
 unfold Delivery.deliver_with_status; rewrite Fits; reflexivity.
Qed.
