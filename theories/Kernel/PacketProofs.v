From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require DeferredCommit.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet Delivery Notifications NotificationsProofs Observation Queries.
From Selvedge.Programming Require Import DeferredCommitProofs.
Import ListNotations.
Open Scope string_scope.
Local Opaque Packet.decode CommandHandlers.interpret DeferredCommit.select.

Theorem live_configuration_preserves_maintenance_cancellations : forall environment value,
 Packet.core_transition (Configure environment) value =
 Decision (Selvedge.Features.Compaction.recover (with_environment environment value))
   (success (JObject [("configured",JBool true)]))
   (map MaintainContext (Selvedge.Features.Compaction.pending_cancellations
     (Selvedge.Features.Compaction.registry value))).
Proof. reflexivity. Qed.

Lemma a_nondurable_transition_has_no_core_input : forall source value result,
 Packet.transition source value = (false,false,None,result) ->
 Packet.core_input (Packet.decode source) = None.
Proof.
 intros source value result Transition.
 unfold Packet.transition, Packet.transition_decoded in Transition.
 destruct (Packet.decode source) as [[input|complete]|]; cbn [Packet.core_input]; try reflexivity.
 destruct input; try discriminate.
 destruct (CommandHandlers.interpret command false); discriminate.
Qed.

Lemma a_nondurable_transition_selects_its_ordinary_commit : forall source value result,
 Packet.transition source value = (false,false,None,result) ->
 Packet.select source value = DeferredCommit.select false None value result.
Proof.
 intros source value result Transition.
 destruct result as [next reply effects].
 pose proof (a_nondurable_transition_has_no_core_input _ _ _ Transition) as Decoded.
 unfold Packet.transition in Transition.
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
 unfold Packet.packet; destruct (N.leb _ _).
 - unfold Packet.select; rewrite Decoded.
   unfold Packet.query,CommandHandlers.query in Query.
   cbn [CommandHandlers.task_origin] in Query.
   destruct (CommandHandlers.interpret command false) as [observe|mutate]; [|discriminate].
   apply DeferredCommitProofs.a_noncommitting_unchanged_candidate_has_no_effect; reflexivity.
 - repeat split; reflexivity.
Qed.
(** Every ignored, nondurable callback uses this same finalization path. *)
Theorem packet_keeps_an_ignored_nondurable_result : forall source value result,
 Packet.transition source value=(false,false,None,result) ->
 decision_world result=value -> decision_effects result=[] ->
 fst (Packet.packet source value)=value /\
 field "effects" (snd (Packet.packet source value))=Some (JArray []) /\
 field "durable" (snd (Packet.packet source value))=Some (JBool false).
Proof.
 intros source value result Transition Unchanged Empty.
 unfold Packet.packet; destruct (N.leb _ _).
 - rewrite (a_nondurable_transition_selects_its_ordinary_commit source value result Transition).
   apply DeferredCommitProofs.a_noncommitting_unchanged_candidate_has_no_effect; assumption.
 - repeat split; reflexivity.
Qed.
