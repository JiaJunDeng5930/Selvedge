From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require DeferredCommit.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require CommitPacket.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet Delivery Notifications NotificationsProofs Observation Queries.
From Selvedge.Kernel Require Import DeferredCommitProofs.
Import ListNotations.
Open Scope string_scope.
Local Opaque Packet.decode CommandHandlers.interpret DeferredCommit.select.

Theorem live_configuration_preserves_maintenance_cancellations : forall environment value,
 decision_effects (Packet.core_transition (Configure environment) value) =
 map MaintainContext (Selvedge.Features.Compaction.pending_cancellations value).
Proof. reflexivity. Qed.

Lemma a_nondurable_transition_has_no_core_input : forall source value result,
 Packet.transition_decoded (Packet.decode source) source value = (false,false,None,result) ->
 Packet.core_input (Packet.decode source) = None.
Proof.
 intros source value result Transition.
 unfold Packet.transition_decoded in Transition.
 destruct (Packet.decode source) as [[input|complete]|]; cbn [Packet.core_input]; try reflexivity.
 destruct input; try discriminate.
 destruct (CommandHandlers.interpret command false); discriminate.
Qed.

Lemma a_nondurable_transition_selects_its_ordinary_commit : forall source value result,
 Packet.transition_decoded (Packet.decode source) source value = (false,false,None,result) ->
 Packet.select source value = DeferredCommit.select false None value result.
Proof.
 intros source value result Transition.
 destruct result as [next reply effects].
 pose proof (a_nondurable_transition_has_no_core_input _ _ _ Transition) as Decoded.
 unfold Packet.select; cbv beta zeta.
 destruct (Packet.decode source) as [[input|complete]|] eqn:Received;
   [cbn [Packet.core_input] in Decoded; discriminate| |].
 all: exact (f_equal (fun outcome : bool * bool * option Inputs.input * decision =>
   let '(durable,schedules,input,observed) := outcome in
   DeferredCommit.select durable input value (Packet.prepare schedules input observed)) Transition).
Qed.


Theorem actual_query_preserves_world_and_emits_no_effect : forall source command reply value,
 Packet.decode source = Some (inl (UserCommand command)) ->
 Packet.query command None value = Some reply ->
 fst (Packet.packet source value) = value /\
 field "effects" (snd (Packet.packet source value)) = Some (JArray []) /\
 field "durable" (snd (Packet.packet source value)) = Some (JBool false).
Proof.
 intros source command reply value Decoded Query.
 unfold Packet.packet; destruct (Delivery.fits_json source).
 - unfold Packet.select; rewrite Decoded.
   unfold Packet.query,CommandHandlers.query in Query.
   cbn [CommandHandlers.task_origin] in Query.
   destruct (CommandHandlers.interpret command false) as [observe|mutate]; [|discriminate].
   apply DeferredCommitProofs.a_noncommitting_unchanged_candidate_has_no_effect; reflexivity.
 - repeat split; reflexivity.
Qed.
Local Transparent DeferredCommit.select.
Theorem actual_admitted_query_delivers_its_observation source command reply value :
 Delivery.fits_json source = true ->
 Packet.decode source = Some (inl (UserCommand command)) ->
 Packet.query command None value = Some reply ->
 Delivery.fits false (Decision value reply []) = true ->
 field "reply" (snd (Packet.packet source value)) = Some reply.
Proof.
 intros FitsInput Decoded Query FitsReply.
 unfold Packet.packet, Packet.select. rewrite FitsInput, Decoded.
 unfold Packet.query, CommandHandlers.query in Query.
 cbn [CommandHandlers.task_origin] in Query.
 destruct (CommandHandlers.interpret command false) as [observe|mutate]; [|discriminate].
 injection Query as Reply. rewrite Reply.
 unfold CommitPacket.finalize, DeferredCommit.select, DeferredCommit.admit_with_status.
 unfold Delivery.deliver_with_status, Dispatch.retain_live_effects.
 cbn [decision_world decision_reply decision_effects filter].
 rewrite FitsReply. reflexivity.
Qed.

Local Opaque DeferredCommit.select.

(** Every ignored, nondurable callback uses this same finalization path. *)
Theorem packet_keeps_an_ignored_nondurable_result : forall source value result,
 Packet.transition_decoded (Packet.decode source) source value=(false,false,None,result) ->
 decision_world result=value -> decision_effects result=[] ->
 fst (Packet.packet source value)=value /\
 field "effects" (snd (Packet.packet source value))=Some (JArray []) /\
 field "durable" (snd (Packet.packet source value))=Some (JBool false).
Proof.
 intros source value result Transition Unchanged Empty.
 unfold Packet.packet; destruct (Delivery.fits_json source).
 - rewrite (a_nondurable_transition_selects_its_ordinary_commit source value result Transition).
   apply DeferredCommitProofs.a_noncommitting_unchanged_candidate_has_no_effect; assumption.
 - repeat split; reflexivity.
Qed.

Theorem replay_recovers_the_packet_world_and_durability source value :
 fst (Packet.replay source value) = fst (Packet.packet source value) /\
 field "durable" (snd (Packet.packet source value)) =
 Some (JBool (snd (Packet.replay source value))).
Proof.
 unfold Packet.replay, Packet.packet.
 destruct (Delivery.fits_json source); [|split; reflexivity].
 destruct (Packet.select source value) as [durable admitted input result].
 split; [reflexivity|].
 cbn [CommitPacket.finalize CommitPacket.selected_durable CommitPacket.selected_admitted
   CommitPacket.selected_source CommitPacket.selected_decision fst snd].
 unfold Notifications.envelope.
 destruct (durable && admitted); [|reflexivity].
 destruct (Notifications.batch input value result) as [|notice rest]; [reflexivity|].
 destruct (Delivery.fits_json _); reflexivity.
Qed.

(** Replay of the current journal commits the same world and cursor decision
    as its actual live entry. An uncommitted reply is not a replay record. *)
Theorem journal_replay_agrees_with_live_commit same_image source value :
 Packet.journal_replay same_image source value =
 (fst (Packet.journal_packet same_image source value),
  match field "durable" (snd (Packet.journal_packet same_image source value)) with
  | Some (JBool durable) => durable | _ => false end).
Proof.
 unfold Packet.journal_replay, Packet.journal_packet.
 destruct (Delivery.fits_json source); [|reflexivity].
 unfold CommitPacket.journal_finalize, CommitPacket.finalize.
 cbn [fst snd]. rewrite NotificationsProofs.notification_envelopes_preserve_the_durability_flag.
 reflexivity.
Qed.

Theorem journal_never_commits_an_unchanged_refusal same_image source before code reason :
 same_image before before = true ->
 Delivery.fits_json source = true ->
 CommitPacket.selected_decision (Packet.select source before) = State.reject code reason before ->
 Packet.journal_replay same_image source before = (before,false).
Proof.
 intros Same Fits Refused. unfold Packet.journal_replay. rewrite Fits.
 unfold CommitPacket.select_journal, CommitPacket.needs_commit. rewrite Refused.
 cbn [State.reject State.decision_effects State.decision_world existsb orb].
 rewrite Same. cbn [negb].
 destruct (CommitPacket.selected_durable (Packet.select source before)); [|reflexivity].
 unfold Delivery.deliver_with_status. destruct (Delivery.fits false _); reflexivity.
Qed.

Local Transparent DeferredCommit.select.
Theorem journal_query_preserves_world_and_emits_no_effect same_image source command reply value :
 same_image value value = true ->
 Packet.decode source = Some (inl (UserCommand command)) ->
 Packet.query command None value = Some reply ->
 fst (Packet.journal_packet same_image source value) = value /\
 field "effects" (snd (Packet.journal_packet same_image source value)) = Some (JArray []) /\
 field "durable" (snd (Packet.journal_packet same_image source value)) = Some (JBool false).
Proof.
 intros Same Decoded Query.
 unfold Packet.journal_packet. destruct (Delivery.fits_json source); [|repeat split; reflexivity].
 unfold Packet.select. rewrite Decoded.
 unfold Packet.query, CommandHandlers.query in Query.
 cbn [CommandHandlers.task_origin] in Query.
 destruct (CommandHandlers.interpret command false) as [observe|mutate]; [|discriminate].
 unfold CommitPacket.journal_finalize.
 assert (Unchanged : CommitPacket.select_journal same_image value
     (DeferredCommit.select false (Some (UserCommand command)) value (Decision value (observe None value) [])) =
     DeferredCommit.select false (Some (UserCommand command)) value (Decision value (observe None value) [])).
 { unfold CommitPacket.select_journal, CommitPacket.needs_commit, DeferredCommit.select,
     CommitPacket.choose, DeferredCommit.admit_with_status, Delivery.deliver_with_status.
   destruct (Delivery.fits false (Dispatch.retain_live_effects (Decision value (observe None value) [])));
   cbn [Dispatch.retain_live_effects State.reject CommitPacket.selected_decision CommitPacket.selected_durable
     CommitPacket.selected_admitted CommitPacket.selected_source snd fst decision_world decision_effects existsb orb];
   rewrite Same; reflexivity. }
 rewrite Unchanged.
 apply DeferredCommitProofs.a_noncommitting_unchanged_candidate_has_no_effect; reflexivity.
Qed.
Local Opaque DeferredCommit.select.

Theorem historical_send_uses_the_written_admission_rule before task contents :
 let historical := with_legacy_send_admission true before in
 Tasks.send_result task contents historical = Tasks.input_result Tasks.AppendInput task contents historical.
Proof. reflexivity. Qed.

Theorem historical_replay_does_not_retain_its_execution_mode source before :
 world_legacy_send_admission (fst (Packet.replay_format_28 source before)) =
 world_legacy_send_admission before.
Proof.
 unfold Packet.replay_format_28.
 destruct (Packet.replay source (with_legacy_send_admission true before)); reflexivity.
Qed.
