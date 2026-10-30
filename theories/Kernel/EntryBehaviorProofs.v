From Selvedge.Kernel Require CommandResult.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Packet Inputs InputDecoder CommandExecution
 CreationCommit CreationCommitProofs CreationBirthProofs Delivery Notifications NotificationsProofs.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Worktree.
Import ListNotations.
Open Scope string_scope.

Definition first_task_configuration := JObject [
 ("kind",JString "configure");
 ("profiles",JArray [JObject [("key",JString "fixture");("provider",JString "responses");
   ("name",JString "fixture");("reasoning_options",JNull)]]);
 ("tools",JArray []);("max_fork",JNumber "4");("max_descendants",JNumber "8");
 ("instructions",JObject [("configured",JString "")])].
Definition first_task_command := JObject [("kind",JString "command");
 ("command",JObject [("op",JString "create");("profile",JString "fixture");
   ("message",JString "First user input")])].

(* A positive requirement at the exported entry also excludes an implementation
   that silently removes all scheduling while preserving its safety properties. *)
Theorem the_initial_public_create_commits_input_and_a_durable_continuation :
 let configured := fst (Packet.packet first_task_configuration State.initial) in
 let '(committed,envelope) := Packet.packet first_task_command configured in
 List.length (world_tasks committed) = 1%nat /\
 (match find_task 0 committed with
 | Some created => In (UserMessage [TextPart "First user input"]) (task_history created)
 | None => False end) /\
 existsb (fun request => String.eqb (text_default "kind" request "") "continue")
   (array_default "effects" envelope) = true.
Proof. vm_compute; repeat split; auto. Qed.


(* Unrelated tasks, queued operations, feature requests and unavailable resources
   do not enter these premises. Resolution supplies the actual birth capability;
   delivery supplies only the real encoded frame and decision budgets. *)
Theorem every_resolved_exported_creation_commits_its_planned_result :
 forall source request contents before start (plan : Worktree.planned_start before),
 Packet.decode source = Some (inl (UserCommand (Commands.Cmd_create request))) ->
 Delivery.fits_json source = true ->
 CommandExecution.user_content (Commands.create_message_admitted request) (Commands.create_images_admitted request) = Some contents ->
 requested_start request contents before = Tasks.StartResolved start ->
 Worktree.prepare_resolved Worktree.ImplicitCreation None None start before = CommandResult.Accepted plan ->
 Delivery.fits true (planned_decision plan) = true ->
 Packet.packet source before =
 (with_sequence (N.succ (world_sequence before)) (decision_world (Worktree.consume_planned_start plan before)),
  Notifications.envelope true true (Some (UserCommand (Commands.Cmd_create request))) before (planned_decision plan)).
Proof.
 intros source request contents before start plan Decoded InputFits Parsed Resolved Prepared OutputFits.
 unfold Packet.packet, Packet.select.
 fold (Delivery.fits_json source).
 rewrite InputFits,Decoded; cbn [Packet.core_input Packet.manual_fork_input CreationCommit.input].
 apply every_planned_creation_with_an_output_budget_is_delivered with contents start; assumption.
Qed.

Corollary every_resolved_exported_creation_returns_and_installs_its_fresh_reference :
 forall source request contents before start (plan : Worktree.planned_start before),
 Packet.decode source = Some (inl (UserCommand (Commands.Cmd_create request))) ->
 Delivery.fits_json source = true ->
 CommandExecution.user_content (Commands.create_message_admitted request) (Commands.create_images_admitted request) = Some contents ->
 requested_start request contents before = Tasks.StartResolved start ->
 Worktree.prepare_resolved Worktree.ImplicitCreation None None start before = CommandResult.Accepted plan ->
 Delivery.fits true (planned_decision plan) = true ->
 let '(committed,envelope) := Packet.packet source before in
 bool_default "ok" (value_or_null "reply" envelope) false = true /\
 field "task_id" (value_or_null "result" (value_or_null "reply" envelope)) = Some (number (next_task before)) /\
 (exists created,find_task (next_task before) committed = Some created) /\
 (forall owner existing,find_task owner before = Some existing -> find_task owner committed = Some existing) /\
 List.length (world_tasks committed) = S (List.length (world_tasks before)).
Proof.
 intros source request contents before start plan Decoded InputFits Parsed Resolved Prepared OutputFits.
 rewrite (every_resolved_exported_creation_commits_its_planned_result source request contents before start plan
   Decoded InputFits Parsed Resolved Prepared OutputFits).
 cbn zeta.
 unfold value_or_null at 1 2 3.
 rewrite !notification_envelopes_preserve_the_committed_reply.
 cbn [planned_decision decision_reply].
 destruct (each_planned_start_installs_its_reported_fresh_reference before plan) as [created [Installed Count]].
 repeat split; try reflexivity.
 - exists created; exact Installed.
 - intros; eapply each_planned_start_keeps_every_existing_task; eassumption.
 - exact Count.
Qed.
