From Selvedge.Kernel Require Import CommitPacket CommitPacketProofs ForkCommitAuthorization.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet Delivery Notifications NotificationsProofs Observation Queries
 WorldInvariant WorldInvariantProofs CommitAdmission CommitAdmissionProofs.
From Selvedge.Kernel Require Import ForkCommit ForkCommitProofs ForkCommitPreservation.
From Selvedge.Kernel Require DeferredCommitProofs CreationCommitPreservation CreationCommitAuthorization.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.

Theorem live_configuration_preserves_maintenance_cancellations : forall environment value,
 Packet.core_transition (Configure environment) value =
 Decision (Selvedge.Features.Compaction.recover (with_environment environment value))
   (success (JObject [("configured",JBool true)]))
   (map MaintainContext (Selvedge.Features.Compaction.pending_cancellations
     (Selvedge.Features.Compaction.registry value))).
Proof. reflexivity. Qed.

Definition admit_is_validation_pipeline := DeferredCommitProofs.admit_is_validation_pipeline.
Definition admit_result_is_the_selected_outcome := DeferredCommitProofs.admit_result_is_the_selected_outcome.

Theorem accepted_query_never_runs_the_scheduler : forall source command reply value,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None value = Some reply ->
 Packet.transition source value = (false,false,Some (UserCommand command),Decision value reply []).
Proof. intros; unfold Packet.transition, Packet.transition_decoded; rewrite H,H0; reflexivity. Qed.

Lemma a_nondurable_transition_has_no_typed_input : forall source value result,
 Packet.transition source value = (false,false,None,result) ->
 InputDecoder.decode source = None.
Proof.
 intros source value result Transition.
 unfold Packet.transition, Packet.transition_decoded in Transition.
 destruct (InputDecoder.decode source) as [input|]; [|reflexivity].
 destruct input; try discriminate.
 destruct (Packet.query command None value); discriminate.
Qed.

Lemma actual_query_selects_its_ordinary_commit : forall source command reply value admission,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None value = Some reply ->
 Packet.select_admitted source admission value =
 DeferredCommit.select false (Some (UserCommand command)) source value (Decision value reply []).
Proof.
 intros source command reply value admission Decoded Query.
 unfold Packet.select_admitted; rewrite InputDecoder.admitted_input_is_its_decoder_result, Decoded.
 destruct command;
 cbn [Packet.manual_fork_input CreationCommit.input Packet.deferred_candidate BoardCommit.input ConnectionCommit.input
   Packet.native_fork_input NativeForkCommit.resolve TitleCommit.input
   Packet.terminal_settlement_input TerminalSettlement.resolve Packet.transition_decoded Packet.prepare];
 try solve [rewrite Query; reflexivity].
 all: unfold Packet.query,CommandHandlers.query,Selvedge.Generated.Commands.dispatch in Query;
   cbn [CommandHandlers.handlers] in Query; discriminate.
Qed.
Lemma a_nondurable_transition_selects_its_ordinary_commit : forall source value result admission,
 Packet.transition source value = (false,false,None,result) ->
 Packet.select_admitted source admission value = DeferredCommit.select false None source value result.
Proof.
 intros source value result admission Transition.
 pose proof (a_nondurable_transition_has_no_typed_input _ _ _ Transition) as Decoded.
 unfold Packet.select_admitted; rewrite InputDecoder.admitted_input_is_its_decoder_result, Decoded.
 change ((let '(durable,schedules,input,observed) := Packet.transition_decoded None source value in
 DeferredCommit.select durable input source value (Packet.prepare schedules input observed)) =
 DeferredCommit.select false None source value result).
 unfold Packet.transition in Transition; rewrite Decoded in Transition.
 rewrite Transition; reflexivity.
Qed.


Theorem actual_query_preserves_world_and_emits_no_effect : forall source command reply value,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None value = Some reply ->
 fst (Packet.packet source value) = value /\
 field "effects" (snd (Packet.packet source value)) = Some (JArray []) /\
 field "durable" (snd (Packet.packet source value)) = Some (JBool false).
Proof.
 intros source command reply value Decoded Query.
 unfold Packet.packet,Packet.packet_admitted; destruct (N.leb _ _).
 - rewrite (actual_query_selects_its_ordinary_commit source command reply value _ Decoded Query).
   apply DeferredCommitProofs.a_noncommitting_unchanged_candidate_has_no_effect; reflexivity.
 - repeat split; reflexivity.
Qed.
Definition describe_input := JObject [("kind",JString "command");("command",JObject [("op",JString "describe")])].
Theorem describe_input_is_actually_accepted :
 InputDecoder.decode describe_input = Some (UserCommand (G.Cmd_describe tt)).
Proof. vm_compute; reflexivity. Qed.
Theorem describe_is_read_only_at_the_actual_entry : forall value,
 fst (Packet.packet describe_input value) = value /\
 field "effects" (snd (Packet.packet describe_input value)) = Some (JArray []) /\
 field "durable" (snd (Packet.packet describe_input value)) = Some (JBool false).
Proof.
 intros; eapply actual_query_preserves_world_and_emits_no_effect.
 - apply describe_input_is_actually_accepted.
 - reflexivity.
Qed.


Definition actual_commit_admission_preserves_world_requirements := DeferredCommitProofs.actual_commit_admission_preserves_world_requirements.
Definition actual_commit_refusal_restores_the_world_and_discards_every_effect := DeferredCommitProofs.actual_commit_refusal_restores_the_world_and_discards_every_effect.
Lemma a_selected_fork_satisfies_the_shared_requirements : forall raw request before,
 CommitPacketProofs.requirements raw before (ForkCommit.select request before).
Proof.
 intros; apply CommitPacketProofs.output_admission_preserves_requirements; constructor.
 - intros Valid; apply well_formed_worlds_pass_the_checker,
     a_manual_fork_transaction_preserves_world_requirements,
     the_world_checker_establishes_all_requirements; exact Valid.
 - apply a_manual_fork_transaction_retains_or_constructs_its_cross_state_authority.
 - pose proof (the_fork_transaction_emits_only_its_durable_continuation request before) as Only.
   rewrite Forall_forall in *; intros effect Present; specialize (Only effect Present); subst; exact I.
Qed.
Lemma a_selected_creation_satisfies_the_shared_requirements : forall raw request before,
 CommitPacketProofs.requirements raw before (CreationCommit.select request before).
Proof.
 intros; apply CommitPacketProofs.output_admission_preserves_requirements; constructor.
 - intros Valid; apply well_formed_worlds_pass_the_checker,
     CreationCommitPreservation.public_creation_candidates_preserve_every_world_requirement,
     the_world_checker_establishes_all_requirements; exact Valid.
 - intros Valid; right; apply CreationCommitAuthorization.every_creation_candidate_preserves_retained_execution_authority; exact Valid.
 - apply CreationCommitAuthorization.every_creation_candidate_effect_has_its_inference_history_bound.
Qed.
(** This is the single proof over the production route selection. All packet
    and journal consumers use the selected outcome's shared contract. *)
Theorem every_selected_packet_satisfies_the_shared_requirements : forall raw admission before,
 CommitPacketProofs.requirements raw before (Packet.select_admitted raw admission before).
Proof.
 intros; unfold Packet.select_admitted.
 rewrite InputDecoder.admitted_input_is_its_decoder_result; cbv beta zeta.
 destruct (Packet.manual_fork_input (InputDecoder.decode raw)) as [request|].
 - apply a_selected_fork_satisfies_the_shared_requirements.
 - destruct (CreationCommit.input (InputDecoder.decode raw)) as [request|].
   + apply a_selected_creation_satisfies_the_shared_requirements.
   + destruct (Packet.deferred_candidate (InputDecoder.decode raw) before) as [[input candidate]|].
     * apply DeferredCommitProofs.selected_commit_satisfies_the_shared_requirements.
     * destruct (Packet.transition_decoded (InputDecoder.decode raw) raw before)
         as [[[durable schedules] input] candidate].
       apply DeferredCommitProofs.selected_commit_satisfies_the_shared_requirements.
Qed.
Theorem every_actual_packet_preserves_world_requirements : forall source before,
 world_valid before = true -> world_valid (fst (Packet.packet source before)) = true.
Proof.
 intros source before Before; unfold Packet.packet.
 destruct (N.leb _ _); [|exact Before].
 eapply CommitPacketProofs.finalized_world_is_valid;
 [apply every_selected_packet_satisfies_the_shared_requirements|exact Before].
Qed.
Theorem every_actual_packet_establishes_the_named_requirements : forall source before,
 well_formed before -> well_formed (fst (Packet.packet source before)).
Proof.
 intros source before Before; apply the_world_checker_establishes_all_requirements.
 apply every_actual_packet_preserves_world_requirements.
 apply well_formed_worlds_pass_the_checker; exact Before.
Qed.


Definition retaining_live_effects_preserves_the_world := DeferredCommitProofs.retaining_live_effects_preserves_the_world.

Definition actual_commit_admission_keeps_an_unchanged_world := DeferredCommitProofs.actual_commit_admission_keeps_an_unchanged_world.

Definition actual_commit_admission_is_authorized_or_rolled_back := DeferredCommitProofs.actual_commit_admission_is_authorized_or_rolled_back.

Definition actual_commit_admission_satisfies_global_transition_or_rollback := DeferredCommitProofs.actual_commit_admission_satisfies_global_transition_or_rollback.

Definition actual_admission_binds_every_inference_to_its_exact_history := DeferredCommitProofs.actual_admission_binds_every_inference_to_its_exact_history.

(* The witness is the selected decision whose effects form the actual receipt,
   including rollback. Finalization never changes an inference's history. *)
Theorem every_actual_packet_binds_its_emitted_inference_history : forall source before,
 exists durable admitted input committed,
 snd (Packet.packet source before) = Notifications.envelope durable admitted input before committed /\
 Forall (CommitAdmissionProofs.inference_history_bound (fst (Packet.packet source before)))
   (decision_effects committed).
Proof.
 intros source before; unfold Packet.packet.
 destruct (N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes).
 - set (chosen := Packet.select_admitted source (InputDecoder.admit source) before).
   exists (selected_durable chosen),(selected_admitted chosen),
     (selected_source chosen),(selected_decision chosen).
   split; [apply finalize_has_its_selected_receipt|].
   eapply CommitPacketProofs.finalized_receipt_binds_its_history.
   apply every_selected_packet_satisfies_the_shared_requirements.
 - exists false,false,None,(reject "invalid_input" "The complete input exceeds the native frame bound" before).
   split; [reflexivity|constructor].
Qed.

Theorem a_world_invariant_refusal_cannot_publish_notifications :
 forall durable source raw_source before candidate,
 world_valid (decision_world (Dispatch.retain_live_effects candidate)) = false ->
 let '(accepted,result) := Packet.admit_with_status durable source raw_source before candidate in
 Notifications.envelope durable accepted source before result = Observation.envelope durable result.
Proof.
 intros durable source raw_source before candidate Invalid.
 unfold Packet.admit_with_status, DeferredCommit.admit_with_status, WorldInvariant.validate_with_status.
 rewrite Invalid. cbn [andb].
 destruct (CommitAdmission.validate_with_status durable source raw_source before
   (reject "invariant_violation" "The candidate violates a world invariant; no state change or effect was committed" before))
   as [authorized guarded].
 destruct (Delivery.deliver_with_status durable guarded before) as [fits delivered].
 apply NotificationsProofs.a_noncommitting_observation_has_no_notification_batch.
Qed.
