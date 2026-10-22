From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet Delivery Notifications Observation Queries
 WorldInvariant WorldInvariantProofs CommitAdmission CommitAdmissionProofs.
Import ListNotations.
Open Scope string_scope.
Module G := Selvedge.Generated.Commands.

Theorem accepted_query_never_runs_the_scheduler : forall source command reply value,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None value = Some reply ->
 Packet.transition source value = (false,false,Some (UserCommand command),Decision value reply []).
Proof. intros; unfold Packet.transition; rewrite H,H0; reflexivity. Qed.

(* This covers the complete exported entry, including frame admission and the
   final output admission. An oversized query result remains read-only. *)
Theorem actual_query_preserves_world_and_emits_no_effect : forall source command reply value,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None value = Some reply ->
 fst (Packet.packet source value) = value /\
 field "effects" (snd (Packet.packet source value)) = Some (JArray []) /\
 field "durable" (snd (Packet.packet source value)) = Some (JBool false).
Proof.
 intros source command reply value Decoded Query.
 unfold Packet.packet; destruct (N.leb _ _).
 - rewrite (accepted_query_never_runs_the_scheduler source command reply value Decoded Query).
   unfold Packet.admit, Notifications.decorate, CommitAdmission.retain_live_effects.
   cbn [decision_world K.decision_world K.decision_reply K.decision_effects filter].
   unfold WorldInvariant.validate; cbn [decision_world].
   destruct (world_valid value) eqn:Valid.
   + unfold CommitAdmission.validate.
     destruct (CommitAdmission.transition_authorized false (Some (UserCommand command)) source value
       (Decision value reply [])); unfold Delivery.deliver;
     destruct (Delivery.fits false _); repeat split; reflexivity.
   + unfold CommitAdmission.validate.
     destruct (CommitAdmission.transition_authorized false (Some (UserCommand command)) source value
       (reject "invariant_violation" "The candidate violates a world invariant; no state change or effect was committed" value));
     unfold Delivery.deliver; destruct (Delivery.fits false _); repeat split; reflexivity.
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
 intros durable source raw_source before candidate Before; unfold Packet.admit, Delivery.deliver.
 destruct (Delivery.fits durable _); [|exact Before].
 apply CommitAdmissionProofs.global_admission_preserves_world_validity; [exact Before|].
 apply an_admitted_world_satisfies_the_commit_requirements; exact Before.
Qed.
Theorem actual_commit_refusal_restores_the_world_and_discards_every_effect : forall durable source raw_source before candidate,
 world_valid (decision_world (Notifications.decorate durable source before
   (CommitAdmission.retain_live_effects candidate))) = false ->
 decision_world (Packet.admit durable source raw_source before candidate) = before /\
 decision_effects (Packet.admit durable source raw_source before candidate) = [].
Proof.
 intros durable source raw_source before candidate Invalid; unfold Packet.admit, Delivery.deliver.
 unfold WorldInvariant.validate; rewrite Invalid.
 unfold CommitAdmission.validate.
 destruct (CommitAdmission.transition_authorized durable source raw_source before
   (reject "invariant_violation" "The candidate violates a world invariant; no state change or effect was committed" before));
   destruct (Delivery.fits durable _); split; reflexivity.
Qed.
Theorem every_actual_packet_preserves_world_requirements : forall source before,
 world_valid before = true -> world_valid (fst (Packet.packet source before)) = true.
Proof.
 intros source before Before; unfold Packet.packet.
 destruct (N.leb _ _); [|exact Before].
 destruct (Packet.transition source before) as [[[durable schedules] input] result].
 destruct durable; cbn [fst].
 - rewrite a_journal_cursor_does_not_change_domain_validity.
   apply actual_commit_admission_preserves_world_requirements; exact Before.
 - apply actual_commit_admission_preserves_world_requirements; exact Before.
Qed.
Theorem every_actual_packet_establishes_the_named_requirements : forall source before,
 well_formed before -> well_formed (fst (Packet.packet source before)).
Proof.
 intros source before Before; apply the_world_checker_establishes_all_requirements.
 apply every_actual_packet_preserves_world_requirements.
 apply well_formed_worlds_pass_the_checker; exact Before.
Qed.


Theorem notifications_preserve_the_candidate_world : forall durable source before candidate,
 decision_world (Notifications.decorate durable source before candidate) = decision_world candidate.
Proof.
 intros durable source before candidate; unfold Notifications.decorate.
 destruct durable; [|reflexivity].
 destruct ((Notifications.input_events source before (decision_world candidate) ++
   List.concat (Numbers.indexed (fun id task => Notifications.task_events before id task (decision_world candidate))
     0 (world_tasks (decision_world candidate))) ++
   flat_map (Notifications.effect_events (decision_world candidate)) (decision_effects candidate))%list)
   as [|notice rest]; [reflexivity|].
 destruct (Delivery.fits true (Decision (decision_world candidate) (decision_reply candidate)
   ((decision_effects candidate ++ [NotifyPlugins (notice :: rest)])%list))); reflexivity.
Qed.
Lemma retaining_live_effects_preserves_the_world : forall candidate,
 decision_world (CommitAdmission.retain_live_effects candidate) = decision_world candidate.
Proof. intros []; reflexivity. Qed.

Theorem actual_commit_admission_keeps_an_unchanged_world : forall durable source raw_source before candidate,
 decision_world candidate = before ->
 decision_world (Packet.admit durable source raw_source before candidate) = before.
Proof.
 intros durable source raw_source before candidate Unchanged; unfold Packet.admit, Delivery.deliver.
 destruct (Delivery.fits durable _); [|reflexivity].
 unfold CommitAdmission.validate.
 destruct (CommitAdmission.transition_authorized durable source raw_source before
   (WorldInvariant.validate before (Notifications.decorate durable source before
     (CommitAdmission.retain_live_effects candidate))));
   [|reflexivity].
 unfold WorldInvariant.validate.
 assert (LiveWorld : decision_world (CommitAdmission.retain_live_effects candidate) = before).
 { rewrite retaining_live_effects_preserves_the_world; exact Unchanged. }
 assert (DecoratedWorld : decision_world (Notifications.decorate durable source before
   (CommitAdmission.retain_live_effects candidate)) = before).
 { rewrite notifications_preserve_the_candidate_world; exact LiveWorld. }
 destruct (world_valid (decision_world (Notifications.decorate durable source before
   (CommitAdmission.retain_live_effects candidate))));
   [exact DecoratedWorld|reflexivity].
Qed.

Theorem actual_commit_admission_is_authorized_or_rolled_back : forall durable source raw_source before candidate,
 (decision_world (Packet.admit durable source raw_source before candidate) = before /\
  decision_effects (Packet.admit durable source raw_source before candidate) = []) \/
 (CommitAdmission.transition_authorized durable source raw_source before
    (WorldInvariant.validate before (Notifications.decorate durable source before
      (CommitAdmission.retain_live_effects candidate))) = true /\
  Packet.admit durable source raw_source before candidate =
    WorldInvariant.validate before (Notifications.decorate durable source before
      (CommitAdmission.retain_live_effects candidate))).
Proof.
 intros durable source raw_source before candidate.
 unfold Packet.admit, Delivery.deliver.
 destruct (Delivery.fits durable
   (CommitAdmission.validate durable source raw_source before
     (WorldInvariant.validate before (Notifications.decorate durable source before
       (CommitAdmission.retain_live_effects candidate))))) eqn:Fits.
 - destruct (CommitAdmissionProofs.every_global_admission_preserves_or_rolls_back durable source raw_source before
     (WorldInvariant.validate before (Notifications.decorate durable source before
       (CommitAdmission.retain_live_effects candidate))))
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
   (decision_effects (Packet.admit durable source raw_source before candidate)) = true /\
  CommitAdmission.effect_notifications_valid durable source before
   (Packet.admit durable source raw_source before candidate) = true).
Proof.
 intros durable source raw_source before candidate.
 destruct (actual_commit_admission_is_authorized_or_rolled_back durable source raw_source before candidate)
   as [Rollback | [Authorized Same]].
 - left; exact Rollback.
 - right; rewrite Same.
   exact (CommitAdmissionProofs.an_authorized_transition_has_state_and_effect_authority
     durable source raw_source before
     (WorldInvariant.validate before (Notifications.decorate durable source before
       (CommitAdmission.retain_live_effects candidate))) Authorized).
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
   as [[Rollback NoEffects] | [Evolution [Fresh [Effects Notices]]]].
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
 exists durable committed,
 snd (Packet.packet source before) = Observation.envelope durable committed /\
 Forall (CommitAdmissionProofs.inference_history_bound (fst (Packet.packet source before)))
   (decision_effects committed).
Proof.
 intros source before; unfold Packet.packet.
 destruct (N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes).
 - destruct (Packet.transition source before) as [[[durable schedules] input] candidate].
   set (prepared := if schedules then Selvedge.Features.Runtime.finish
     (Scheduler.run Packet.execute_command Selvedge.Features.Runtime.can_schedule_task candidate)
     else candidate).
   set (admitted := Packet.admit durable input source before prepared).
   pose proof (actual_admission_binds_every_inference_to_its_exact_history
     durable input source before prepared) as Bound.
   fold admitted in Bound.
   destruct durable; cbn [fst snd].
   + exists true, admitted; split; [reflexivity|].
     rewrite Forall_forall in *; intros request Present.
     apply (proj2 (inference_history_binding_ignores_the_journal_cursor
       (decision_world admitted) (N.succ (world_sequence before)) request)).
     exact (Bound request Present).
   + exists false, admitted; split; [reflexivity|exact Bound].
 - exists false, (reject "invalid_input" "The complete input exceeds the native frame bound" before).
   split; [reflexivity|constructor].
Qed.
