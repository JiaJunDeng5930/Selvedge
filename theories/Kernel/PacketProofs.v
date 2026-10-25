From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet Delivery Notifications NotificationsProofs Observation Queries
 WorldInvariant WorldInvariantProofs CommitAdmission CommitAdmissionProofs.
From Selvedge.Kernel Require Import ForkCommit ForkCommitProofs ForkCommitPreservation.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.

Lemma admit_is_validation_pipeline : forall durable source raw_source before candidate,
 Packet.admit durable source raw_source before candidate =
 Delivery.deliver durable
   (CommitAdmission.validate durable source raw_source before
     (WorldInvariant.validate before (Dispatch.retain_live_effects candidate))) before.
Proof.
 intros. unfold Packet.admit, Packet.admit_with_status, Delivery.deliver,
   CommitAdmission.validate, WorldInvariant.validate.
 destruct (WorldInvariant.validate_with_status before (Dispatch.retain_live_effects candidate)) as [valid checked]; cbn [snd].
 destruct (CommitAdmission.validate_with_status durable source raw_source before checked) as [authorized granted]; cbn [snd].
 destruct (Delivery.deliver_with_status durable granted before); reflexivity.
Qed.
Lemma admit_result_is_the_selected_outcome : forall durable source raw_source before candidate admitted result,
 Packet.admit_with_status durable source raw_source before candidate = (admitted,result) ->
 Packet.admit durable source raw_source before candidate = result.
Proof. intros; unfold Packet.admit; rewrite H; reflexivity. Qed.

Theorem accepted_query_never_runs_the_scheduler : forall source command reply value,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None value = Some reply ->
 Packet.transition source value = (false,false,Some (UserCommand command),Decision value reply []).
Proof. intros; unfold Packet.transition, Packet.transition_decoded; rewrite H,H0; reflexivity. Qed.

(* This covers the complete exported entry, including frame admission and the
   final output admission. An oversized query result remains read-only. *)
Lemma a_query_is_not_a_manual_fork : forall source command reply value,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None value = Some reply -> Packet.manual_fork source = None.
Proof.
 intros source command reply value Decoded Query.
 unfold Packet.manual_fork; rewrite Decoded; destruct command; try reflexivity.
 unfold Packet.query, CommandHandlers.query, Selvedge.Generated.Commands.dispatch in Query.
 cbn [CommandHandlers.handlers Selvedge.Generated.Commands.handle_fork] in Query; discriminate.
Qed.
Lemma a_nondurable_transition_is_not_a_manual_fork : forall source value result,
 Packet.transition source value = (false,false,None,result) -> Packet.manual_fork source = None.
Proof.
 intros source value result Transition.
 unfold Packet.manual_fork, Packet.manual_fork_input.
 destruct (InputDecoder.decode source) as [input|] eqn:Decoded; [|reflexivity].
 destruct input; try reflexivity; destruct command; try reflexivity.
 unfold Packet.transition, Packet.transition_decoded in Transition; rewrite Decoded in Transition.
 unfold Packet.query, CommandHandlers.query, Selvedge.Generated.Commands.dispatch in Transition.
 cbn [CommandHandlers.handlers Selvedge.Generated.Commands.handle_fork] in Transition; discriminate.
Qed.
Theorem actual_query_preserves_world_and_emits_no_effect : forall source command reply value,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None value = Some reply ->
 fst (Packet.packet source value) = value /\
 field "effects" (snd (Packet.packet source value)) = Some (JArray []) /\
 field "durable" (snd (Packet.packet source value)) = Some (JBool false).
Proof.
 intros source command reply value Decoded Query.
 unfold Packet.packet; cbv beta zeta; fold (Packet.manual_fork source); destruct (N.leb _ _).
 - cbv beta zeta; fold (Packet.manual_fork source).
   rewrite (a_query_is_not_a_manual_fork source command reply value Decoded Query).
   fold (Packet.transition source value).
   rewrite (accepted_query_never_runs_the_scheduler source command reply value Decoded Query).
   unfold Packet.admit_with_status, Dispatch.retain_live_effects.
   cbn [decision_world K.decision_world K.decision_reply K.decision_effects filter].
   unfold WorldInvariant.validate_with_status; cbn [decision_world].
   destruct (world_valid value) eqn:Valid; cbn [snd];
     unfold CommitAdmission.validate_with_status.
   + destruct (CommitAdmission.transition_authorized false (Some (UserCommand command)) source value
       (Decision value reply [])); cbn [snd]; unfold Delivery.deliver_with_status;
       destruct (Delivery.fits false _); repeat split; reflexivity.
   + destruct (CommitAdmission.transition_authorized false (Some (UserCommand command)) source value
       (reject "invariant_violation" "The candidate violates a world invariant; no state change or effect was committed" value)); cbn [snd];
       unfold Delivery.deliver_with_status; destruct (Delivery.fits false _); repeat split; reflexivity.
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


Theorem actual_commit_admission_preserves_world_requirements : forall durable source raw_source before candidate,
 world_valid before = true ->
 world_valid (decision_world (Packet.admit durable source raw_source before candidate)) = true.
Proof.
 intros durable source raw_source before candidate Before; rewrite admit_is_validation_pipeline; unfold Delivery.deliver, Delivery.deliver_with_status.
 destruct (Delivery.fits durable _); [|exact Before].
 apply CommitAdmissionProofs.global_admission_preserves_world_validity; [exact Before|].
 apply an_admitted_world_satisfies_the_commit_requirements; exact Before.
Qed.
Theorem actual_commit_refusal_restores_the_world_and_discards_every_effect : forall durable source raw_source before candidate,
 world_valid (decision_world (Dispatch.retain_live_effects candidate)) = false ->
 decision_world (Packet.admit durable source raw_source before candidate) = before /\
 decision_effects (Packet.admit durable source raw_source before candidate) = [].
Proof.
 intros durable source raw_source before candidate Invalid; rewrite admit_is_validation_pipeline; unfold Delivery.deliver, Delivery.deliver_with_status.
 unfold WorldInvariant.validate, WorldInvariant.validate_with_status; rewrite Invalid; cbn [snd].
 unfold CommitAdmission.validate, CommitAdmission.validate_with_status.
 destruct (CommitAdmission.transition_authorized durable source raw_source before
   (reject "invariant_violation" "The candidate violates a world invariant; no state change or effect was committed" before)); cbn [snd];
   destruct (Delivery.fits durable _); split; reflexivity.
Qed.
Theorem every_actual_packet_preserves_world_requirements : forall source before,
 world_valid before = true -> world_valid (fst (Packet.packet source before)) = true.
Proof.
 intros source before Before; unfold Packet.packet; cbv beta zeta; fold (Packet.manual_fork source).
 destruct (N.leb _ _); [|exact Before].
 destruct (Packet.manual_fork source) as [request|].
 { apply manual_fork_packets_preserve_world_requirements; exact Before. }
 fold (Packet.transition source before).
   destruct (Packet.transition source before) as [[[durable schedules] input] result].
 set (prepared := if schedules then Selvedge.Features.Runtime.finish
   (Scheduler.run Packet.execute_command Selvedge.Features.Runtime.can_schedule_task result) else result).
 destruct (Packet.admit_with_status durable input source before prepared) as [accepted committed] eqn:Outcome.
 pose proof (actual_commit_admission_preserves_world_requirements durable input source before prepared Before) as Valid.
 rewrite (admit_result_is_the_selected_outcome durable input source before prepared accepted committed Outcome) in Valid.
 destruct durable; cbn [fst]; [rewrite a_journal_cursor_does_not_change_domain_validity|]; exact Valid.
Qed.
Theorem every_actual_packet_establishes_the_named_requirements : forall source before,
 well_formed before -> well_formed (fst (Packet.packet source before)).
Proof.
 intros source before Before; apply the_world_checker_establishes_all_requirements.
 apply every_actual_packet_preserves_world_requirements.
 apply well_formed_worlds_pass_the_checker; exact Before.
Qed.


Lemma retaining_live_effects_preserves_the_world : forall candidate,
 decision_world (Dispatch.retain_live_effects candidate) = decision_world candidate.
Proof. intros []; reflexivity. Qed.

Theorem actual_commit_admission_keeps_an_unchanged_world : forall durable source raw_source before candidate,
 decision_world candidate = before ->
 decision_world (Packet.admit durable source raw_source before candidate) = before.
Proof.
 intros durable source raw_source before candidate Unchanged; rewrite admit_is_validation_pipeline; unfold Delivery.deliver, Delivery.deliver_with_status.
 destruct (Delivery.fits durable _); [|reflexivity].
 unfold CommitAdmission.validate, CommitAdmission.validate_with_status.
 destruct (CommitAdmission.transition_authorized durable source raw_source before
   (WorldInvariant.validate before (Dispatch.retain_live_effects candidate)));
   [|reflexivity].
 unfold WorldInvariant.validate, WorldInvariant.validate_with_status.
 assert (LiveWorld : decision_world (Dispatch.retain_live_effects candidate) = before).
 { rewrite retaining_live_effects_preserves_the_world; exact Unchanged. }
 assert (DecoratedWorld : decision_world (Dispatch.retain_live_effects candidate) = before).
 { exact LiveWorld. }
 destruct (world_valid (decision_world (Dispatch.retain_live_effects candidate)));
   [exact DecoratedWorld|reflexivity].
Qed.

Theorem actual_commit_admission_is_authorized_or_rolled_back : forall durable source raw_source before candidate,
 (decision_world (Packet.admit durable source raw_source before candidate) = before /\
  decision_effects (Packet.admit durable source raw_source before candidate) = []) \/
 (CommitAdmission.transition_authorized durable source raw_source before
    (WorldInvariant.validate before (Dispatch.retain_live_effects candidate)) = true /\
  Packet.admit durable source raw_source before candidate =
    WorldInvariant.validate before (Dispatch.retain_live_effects candidate)).
Proof.
 intros durable source raw_source before candidate.
 rewrite admit_is_validation_pipeline; unfold Delivery.deliver, Delivery.deliver_with_status.
 destruct (Delivery.fits durable
   (CommitAdmission.validate durable source raw_source before
     (WorldInvariant.validate before (Dispatch.retain_live_effects candidate)))) eqn:Fits.
 - destruct (CommitAdmissionProofs.every_global_admission_preserves_or_rolls_back durable source raw_source before
     (WorldInvariant.validate before (Dispatch.retain_live_effects candidate)))
     as [[RolledBackWorld RolledBackEffects] | [Authorized Kept]].
   + left; split; assumption.
   + right; split; [exact Authorized|exact Kept].
 - left; split; reflexivity.
Qed.

Theorem actual_commit_admission_satisfies_global_transition_or_rollback : forall durable source raw_source before candidate,
 (decision_world (Packet.admit durable source raw_source before candidate) = before /\
  decision_effects (Packet.admit durable source raw_source before candidate) = []) \/
 (CommitAdmission.world_evolution source raw_source before
   (decision_world (Packet.admit durable source raw_source before candidate)) = true /\
  CommitAdmission.effect_tickets_fresh (world_next_ticket before)
   (world_next_ticket (decision_world (Packet.admit durable source raw_source before candidate)))
   (decision_effects (Packet.admit durable source raw_source before candidate)) = true /\
  CommitAdmission.effects_authorized source raw_source before
   (decision_world (Packet.admit durable source raw_source before candidate))
   (decision_effects (Packet.admit durable source raw_source before candidate)) = true).
Proof.
 intros durable source raw_source before candidate.
 destruct (actual_commit_admission_is_authorized_or_rolled_back durable source raw_source before candidate)
   as [Rollback | [Authorized Same]].
 - left; exact Rollback.
 - right; rewrite Same.
   exact (CommitAdmissionProofs.an_authorized_transition_has_state_and_effect_authority
     durable source raw_source before
     (WorldInvariant.validate before (Dispatch.retain_live_effects candidate)) Authorized).
Qed.

Theorem actual_admission_binds_every_inference_to_its_exact_history :
 forall durable source raw_source before candidate,
 Forall (CommitAdmissionProofs.inference_history_bound
   (decision_world (Packet.admit durable source raw_source before candidate)))
   (decision_effects (Packet.admit durable source raw_source before candidate)).
Proof.
 intros durable source raw_source before candidate.
 destruct (actual_commit_admission_satisfies_global_transition_or_rollback
   durable source raw_source before candidate)
   as [[Rollback NoEffects] | [Evolution [Fresh Effects]]].
 - rewrite NoEffects; constructor.
 - eapply CommitAdmissionProofs.every_authorized_effect_has_its_inference_history_bound.
   exact Effects.
Qed.

Lemma inference_history_binding_ignores_the_journal_cursor : forall after sequence request,
 CommitAdmissionProofs.inference_history_bound (with_sequence sequence after) request <->
 CommitAdmissionProofs.inference_history_bound after request.
Proof.
 intros after sequence request; unfold CommitAdmissionProofs.inference_history_bound.
 destruct (CommitAdmissionProofs.inference_snapshot request) as [[owner snapshot]|];
   destruct after; reflexivity.
Qed.

(* The witness is the actual decision whose encoded effects form the returned
   public receipt; the property is about Packet.packet, including rollback. *)
Theorem every_actual_packet_binds_its_emitted_inference_history : forall source before,
 exists durable admitted input committed,
 snd (Packet.packet source before) = Notifications.envelope durable admitted input before committed /\
 Forall (CommitAdmissionProofs.inference_history_bound (fst (Packet.packet source before)))
   (decision_effects committed).
Proof.
 intros source before; unfold Packet.packet; cbv beta zeta; fold (Packet.manual_fork source).
 destruct (N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes).
 - destruct (Packet.manual_fork source) as [request|] eqn:Manual.
   { unfold ForkCommit.packet.
     destruct (Delivery.deliver_with_status true (ForkCommit.candidate request before) before)
       as [fits delivered] eqn:Outcome.
     exists true,fits,(Some (UserCommand (G.Cmd_fork request))),delivered.
     split; [reflexivity|].
     pose proof (delivered_fork_effects_are_only_continuations request before) as Only.
     rewrite Outcome in Only; cbn [snd] in Only.
     rewrite Forall_forall in *; intros effect Present.
     specialize (Only effect Present); subst effect; exact I. }
   fold (Packet.transition source before).
   destruct (Packet.transition source before) as [[[durable schedules] input] candidate].
   set (prepared := if schedules then Selvedge.Features.Runtime.finish
     (Scheduler.run Packet.execute_command Selvedge.Features.Runtime.can_schedule_task candidate)
     else candidate).
   destruct (Packet.admit_with_status durable input source before prepared) as [accepted committed] eqn:Outcome.
   pose proof (actual_admission_binds_every_inference_to_its_exact_history
     durable input source before prepared) as Bound.
   rewrite (admit_result_is_the_selected_outcome durable input source before prepared accepted committed Outcome) in Bound.
   destruct durable; cbn [fst snd].
   + exists true,accepted,input,committed; split; [reflexivity|].
     rewrite Forall_forall in *; intros request Present.
     apply (proj2 (inference_history_binding_ignores_the_journal_cursor
       (decision_world committed) (N.succ (world_sequence before)) request)).
     exact (Bound request Present).
   + exists false,accepted,input,committed; split; [reflexivity|exact Bound].
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
 unfold Packet.admit_with_status, WorldInvariant.validate_with_status.
 rewrite Invalid. cbn [andb].
 destruct (CommitAdmission.validate_with_status durable source raw_source before
   (reject "invariant_violation" "The candidate violates a world invariant; no state change or effect was committed" before))
   as [authorized guarded].
 destruct (Delivery.deliver_with_status durable guarded before) as [fits delivered].
 apply NotificationsProofs.a_noncommitting_observation_has_no_notification_batch.
Qed.
