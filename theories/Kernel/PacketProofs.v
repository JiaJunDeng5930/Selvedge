From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet Delivery Notifications
 NotificationsProofs Observation Queries DeferredCommitProofs.
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

Lemma actual_query_selects_its_ordinary_commit : forall source command reply value,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None value = Some reply ->
 Packet.select source value =
 DeferredCommit.select false (Some (UserCommand command)) value (Decision value reply []).
Proof.
 intros source command reply value Decoded Query.
 unfold Packet.select; rewrite Decoded.
 destruct command;
 cbn [Packet.manual_fork_input CreationCommit.input Packet.deferred_candidate BoardCommit.input ConnectionCommit.input
   Packet.native_fork_input NativeForkCommit.resolve TitleCommit.input
   Packet.terminal_settlement_input TerminalSettlement.resolve Packet.transition_decoded Packet.prepare];
 try solve [rewrite Query; reflexivity].
 all: unfold Packet.query,CommandHandlers.query,Selvedge.Generated.Commands.dispatch in Query;
   cbn [CommandHandlers.handlers] in Query; discriminate.
Qed.
Lemma a_nondurable_transition_selects_its_ordinary_commit : forall source value result,
 Packet.transition source value = (false,false,None,result) ->
 Packet.select source value = DeferredCommit.select false None value result.
Proof.
 intros source value result Transition.
 pose proof (a_nondurable_transition_has_no_typed_input _ _ _ Transition) as Decoded.
 unfold Packet.select; rewrite Decoded.
 change ((let '(durable,schedules,input,observed) := Packet.transition_decoded None source value in
 DeferredCommit.select durable input value (Packet.prepare schedules input observed)) =
 DeferredCommit.select false None value result).
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
 unfold Packet.packet; destruct (N.leb _ _).
 - rewrite (actual_query_selects_its_ordinary_commit source command reply value Decoded Query).
   apply DeferredCommitProofs.a_noncommitting_unchanged_candidate_has_no_effect; reflexivity.
 - repeat split; reflexivity.
Qed.
Definition describe_input := JObject [("kind",JString "command");("command",JObject [("op",JString "describe")])].
Definition describe_payload : G.describe_payload := G.Admit_describe
 (exist _ (exist _ "describe" (or_introl eq_refl), tt) eq_refl).
Theorem describe_input_is_actually_accepted :
 InputDecoder.decode describe_input = Some (UserCommand (G.Cmd_describe describe_payload)).
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
