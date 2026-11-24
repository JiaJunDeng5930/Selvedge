From Stdlib Require Import String List Bool NArith.
From Selvedge.Kernel Require DeferredCommit.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require CommitPacket.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet Delivery Notifications NotificationsProofs Observation Queries.
From Selvedge.Kernel Require Import DeferredCommitProofs.
Import ListNotations.
Open Scope string_scope.
Local Opaque Packet.decode CommandHandlers.interpret DeferredCommit.select.

Theorem historical_configuration_preserves_maintenance_cancellations : forall environment value,
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
 - destruct (CommandHandlers.interpret command false); discriminate.
 - destruct (Packet.configure_catalog environment policy value); discriminate.
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

From Selvedge.Kernel Require CreationFacts.

Theorem observed_root_planning_retains_the_committed_environment facts command before :
 world_environment (decision_world (Packet.observed_creation facts command before)) =
 world_environment before.
Proof. apply CreationFacts.select_preserves_committed_environment. Qed.

Theorem refused_observed_root_planning_retains_no_observations facts command before code reason :
 Packet.execute_domain command None (CreationFacts.observation_world facts before) =
   State.reject code reason (CreationFacts.observation_world facts before) ->
 Packet.observed_creation facts command before = State.reject code reason before.
Proof. apply CreationFacts.a_refused_plan_retains_no_observations. Qed.

Theorem selected_create_retains_the_committed_environment source request facts before :
 Packet.decode source = Some (inl (RootCommand (Selvedge.Generated.Commands.Cmd_create request) facts)) ->
 world_environment (decision_world (CommitPacket.selected_decision (Packet.select source before))) =
   world_environment before.
Proof.
 intro Decoded. unfold Packet.select. rewrite Decoded.
 unfold CommitPacket.choose, Delivery.deliver_with_status.
 destruct (Delivery.fits true _).
 - exact (CreationFacts.select_preserves_committed_environment facts
     (CreationCommit.candidate request) before).
 - reflexivity.
Qed.

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

Theorem journal_never_commits_an_unchanged_refusal same_image source before code reason :
 same_image before before = true ->
 Delivery.fits_json source = true ->
 CommitPacket.selected_decision (Packet.select source before) = State.reject code reason before ->
 fst (Packet.journal_packet same_image source before) = before /\
 field "durable" (snd (Packet.journal_packet same_image source before)) = Some (JBool false).
Proof.
 intros Same Fits Refused. unfold Packet.journal_packet. rewrite Fits.
 unfold CommitPacket.journal_finalize, CommitPacket.select_journal, CommitPacket.needs_commit.
 rewrite Refused.
 cbn [State.reject State.decision_effects State.decision_world existsb orb].
 rewrite Same. cbn [negb].
 destruct (CommitPacket.selected_durable (Packet.select source before)).
 - unfold Delivery.deliver_with_status. destruct (Delivery.fits false _); split; reflexivity.
 - split; reflexivity.
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
