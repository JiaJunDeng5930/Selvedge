From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain State Inputs InputDecoder Limits Packet Notifications
 BoardCommit BoardCommitProofs ConnectionCommit ConnectionCommitProofs CompactionCommit CompactionCommitProofs CompactionEntryPreservation CheckpointWorldProofs
 TitleCommit TitleCommitAuthorization Delivery WorldInvariant Numbers Workspace ChatgptArguments.
From Selvedge.Features Require Import Chatgpt WorkspaceBinding Compaction.
From Selvedge.Foundation Require Import Utf8.
Import ListNotations.

Definition input_fits source :=
 N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes = true.

Theorem a_public_board_birth_uses_its_independent_transaction : forall source before request,
 input_fits source -> InputDecoder.decode source = Some (UserCommand (Commands.Cmd_create_card request)) ->
 Packet.packet source before = BoardCommit.packet request source before.
Proof.
 intros source before request Fits Decoded. unfold input_fits in Fits.
 unfold Packet.packet, Packet.packet_admitted.
 rewrite InputDecoder.admitted_input_is_its_decoder_result, Fits, Decoded. reflexivity.
Qed.

Theorem a_public_connection_request_uses_its_independent_transaction : forall source before request,
 input_fits source -> InputDecoder.decode source = Some (UserCommand (Commands.Cmd_chatgpt_exec request)) ->
 Packet.packet source before = ConnectionCommit.packet request source before.
Proof.
 intros source before request Fits Decoded. unfold input_fits in Fits.
 unfold Packet.packet, Packet.packet_admitted.
 rewrite InputDecoder.admitted_input_is_its_decoder_result, Fits, Decoded. reflexivity.
Qed.

Theorem a_public_checkpoint_uses_its_independent_transaction : forall source before request,
 input_fits source -> InputDecoder.decode source = Some (UserCommand (Commands.Cmd_compact request)) ->
 Packet.packet source before = CompactionCommit.packet source request before.
Proof.
 intros source before request Fits Decoded. unfold input_fits in Fits.
 unfold Packet.packet, Packet.packet_admitted.
 rewrite InputDecoder.admitted_input_is_its_decoder_result, Fits, Decoded. reflexivity.
Qed.

Theorem an_automatic_title_uses_its_independent_transaction : forall source before (request : TitleCommit.plan before),
 input_fits source -> InputDecoder.decode source = Some Continue ->
 Packet.native_fork_input (Some Continue) before = None -> TitleCommit.resolve before = Some request ->
 Packet.packet source before = TitleCommit.packet request source.
Proof.
 intros source before request Fits Decoded Native Selected. unfold input_fits in Fits.
 unfold Packet.packet, Packet.packet_admitted.
 rewrite InputDecoder.admitted_input_is_its_decoder_result, Fits, Decoded.
 cbn [Packet.manual_fork_input CreationCommit.input Packet.deferred_candidate BoardCommit.input ConnectionCommit.input TitleCommit.input].
 rewrite Native, Selected. reflexivity.
Qed.

Theorem every_public_board_birth_with_its_actual_budget_commits : forall source before request now draft,
 input_fits source -> InputDecoder.decode source = Some (UserCommand (Commands.Cmd_create_card request)) ->
 card_birth_requirements request before now draft ->
 Delivery.fits true (constructed_card_decision draft now before) = true ->
 Packet.packet source before =
 (with_sequence (N.succ (world_sequence before)) (append_card draft now before),
  Notifications.envelope true true (Some (UserCommand (Commands.Cmd_create_card request))) before
    (constructed_card_decision draft now before)).
Proof.
 intros source before request now draft Fits Decoded Requirements Budget.
 rewrite a_public_board_birth_uses_its_independent_transaction with (request:=request) by assumption.
 now apply every_unassisted_card_command_with_a_real_output_budget_commits.
Qed.

Theorem every_automatic_title_plan_with_its_actual_budget_commits : forall source before (request : TitleCommit.plan before),
 input_fits source -> InputDecoder.decode source = Some Continue ->
 Packet.native_fork_input (Some Continue) before = None -> TitleCommit.resolve before = Some request ->
 WorldInvariant.world_valid before = true -> Delivery.fits true (TitleCommit.candidate request) = true ->
 Packet.packet source before =
 (with_sequence (N.succ (world_sequence before)) (decision_world (TitleCommit.candidate request)),
  Notifications.envelope true true (Some Continue) before (TitleCommit.candidate request)).
Proof.
 intros source before request Fits Decoded Native Selected World Budget.
 rewrite an_automatic_title_uses_its_independent_transaction with (request:=request) by assumption.
 now apply every_title_plan_with_its_actual_budget_commits.
Qed.

Module F := Selvedge.Features.Domain.
Theorem every_admissible_public_connection_packet_commits :
 forall connection project request arguments command timeout maximum granted target before raw,
 input_fits raw -> InputDecoder.decode raw = Some (UserCommand (Commands.Cmd_chatgpt_exec
 (Commands.Build_chatgpt_exec connection project request arguments))) ->
 WorldInvariant.world_valid before=true ->
 Chatgpt.ids_valid [connection;project]=true -> Chatgpt.bounded_text 128 request=true ->
 ChatgptArguments.admit_args arguments=Some (bash_arguments command timeout maximum) ->
 negb (String.eqb command ""%string)=true -> Utf8.well_formed command=true ->
 (N.of_nat (String.length command) <= 32768)%N ->
 (100 <= timeout <= 1800000)%N -> (1 <= maximum <= 8192)%N ->
 Chatgpt.authority connection project (Chatgpt.registry before)=Some granted ->
 Chatgpt.project project before=Some target -> workspace_primary (project_workspace target)<>None ->
 Chatgpt.retry connection request (Chatgpt.registry before)=None ->
 Selvedge.Features.Worktree.workspace_available (project_workspace target) before=true ->
 WorkspaceBinding.resource_ready (project_workspace target) (project_resource target) before=true ->
 ((N.of_nat (List.length (F.sharing_jobs (Chatgpt.registry before))) <? 128) &&
 (F.sharing_next (Chatgpt.registry before) <? ChatgptArguments.identity_maximum))%N=true ->
 let job:=admitted_job connection project request (bash_arguments command timeout maximum) granted target in
 Delivery.fits true (accepted_decision before job)=true ->
 Packet.packet raw before =
 (with_sequence (N.succ (world_sequence before)) (Chatgpt.store (fresh_state before job) before),
 Notifications.envelope true true
  (Some (UserCommand (Selvedge.Generated.Commands.Cmd_chatgpt_exec
   (Selvedge.Generated.Commands.Build_chatgpt_exec connection project request arguments))))
  before (accepted_decision before job)).
Proof.
 intros. rewrite a_public_connection_request_uses_its_independent_transaction
   with (request:=Commands.Build_chatgpt_exec connection project request arguments) by assumption.
 eapply every_admissible_public_connection_has_its_durable_result; eauto.
Qed.

Theorem every_public_checkpoint_with_its_actual_budget_commits : forall source before request current summary,
 input_fits source -> InputDecoder.decode source = Some (UserCommand (Commands.Cmd_compact request)) ->
 WorldInvariant.world_valid before = true -> find_task (Commands.compact_task_id request) before = Some current ->
 Compaction.alive current = true -> Compaction.idle current = true ->
 Commands.compact_summary request = Some summary -> summary_admitted current summary = true ->
 Delivery.fits true (checkpoint_decision (Commands.compact_task_id request) current summary before) = true ->
 Packet.packet source before =
 (with_sequence (N.succ (world_sequence before)) (checkpoint_world (Commands.compact_task_id request) current summary before),
  Notifications.envelope true true (Some (UserCommand (Commands.Cmd_compact request))) before
    (checkpoint_decision (Commands.compact_task_id request) current summary before)).
Proof.
 intros source before request current summary Fits Decoded World Owned Alive Idle Summary Admitted Budget.
 rewrite a_public_checkpoint_uses_its_independent_transaction with (request:=request) by assumption.
 eapply every_admitted_checkpoint_with_its_actual_budget_commits; eauto.
Qed.
