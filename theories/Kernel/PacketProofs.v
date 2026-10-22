From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet Delivery Notifications Observation Queries WorldInvariant WorldInvariantProofs.
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
   unfold Packet.admit, Notifications.decorate; cbn [decision_world].
   unfold WorldInvariant.validate; cbn [decision_world].
   destruct (world_valid value); unfold Delivery.deliver;
   destruct (Delivery.fits false _); repeat split; reflexivity.
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


Theorem actual_commit_admission_preserves_world_requirements : forall durable source before candidate,
 world_valid before = true ->
 world_valid (decision_world (Packet.admit durable source before candidate)) = true.
Proof.
 intros durable source before candidate Before; unfold Packet.admit, Delivery.deliver.
 destruct (Delivery.fits durable _).
 - apply an_admitted_world_satisfies_the_commit_requirements; exact Before.
 - exact Before.
Qed.
Theorem actual_commit_refusal_restores_the_world_and_discards_every_effect : forall durable source before candidate,
 world_valid (decision_world (Notifications.decorate durable source before candidate)) = false ->
 decision_world (Packet.admit durable source before candidate) = before /\
 decision_effects (Packet.admit durable source before candidate) = [].
Proof.
 intros durable source before candidate Invalid; unfold Packet.admit, WorldInvariant.validate.
 rewrite Invalid; unfold Delivery.deliver.
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
Theorem actual_commit_admission_keeps_an_unchanged_world : forall durable source before candidate,
 decision_world candidate = before ->
 decision_world (Packet.admit durable source before candidate) = before.
Proof.
 intros durable source before candidate Unchanged; unfold Packet.admit, Delivery.deliver.
 destruct (Delivery.fits durable _); [|reflexivity].
 unfold WorldInvariant.validate; destruct (world_valid _); [|reflexivity].
 rewrite notifications_preserve_the_candidate_world; exact Unchanged.
Qed.
