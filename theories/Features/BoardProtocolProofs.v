From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import Numbers State InputDecoder Packet PacketProofs WorldInvariant Notifications Delivery CommitAdmission.
From Selvedge.Features Require Import Board BoardProofs Remote Worktree Runtime.
Import ListNotations.
Open Scope string_scope.

Lemma board_text_is_not_a_typed_input : forall source,
 string_field "kind" source=Some "board_text" ->
 InputDecoder.decode source=None /\ InputDecoder.owns_kind source=false.
Proof.
 intros source kind. split.
 - unfold InputDecoder.decode.
   destruct source as [|boolean|decimal|text|items|fields].
   + reflexivity.
   + reflexivity.
   + reflexivity.
   + reflexivity.
   + reflexivity.
   + change ((match Selvedge.Foundation.Json.lookup "kind" fields with
       | Some value => Selvedge.Foundation.Json.as_string value
       | None => None end)=Some "board_text") in kind.
     destruct (Schema.unique_names (map fst fields)); [|reflexivity].
     destruct (Selvedge.Foundation.Json.lookup "kind" fields) as [kind_value|].
     * destruct kind_value; cbn in kind; try discriminate.
       inversion kind; subst. vm_compute. reflexivity.
     * reflexivity.
 - unfold InputDecoder.owns_kind. rewrite kind. vm_compute. reflexivity.
Qed.

Lemma remote_completion_ignores_board_text : forall execute source value,
 string_field "kind" source=Some "board_text" ->
 Remote.completion execute source value=None.
Proof.
 intros execute source value kind. unfold Remote.completion. rewrite kind. cbn. reflexivity.
Qed.

Lemma worktree_completion_ignores_board_text : forall source value,
 string_field "kind" source=Some "board_text" ->
 Worktree.completion source value=None.
Proof.
 intros source value kind. unfold Worktree.completion. rewrite kind.
 destruct (natural_field "task_id" source); destruct (bool_field "ok" source); cbn; reflexivity.
Qed.

Lemma runtime_completion_uses_board_text : forall execute source value durable schedules result,
 string_field "kind" source=Some "board_text" ->
 Board.completion source value=Some (durable,schedules,result) ->
 Runtime.completion execute source value=Some (durable,schedules,result).
Proof.
 intros execute source value durable schedules result kind board.
 unfold Runtime.completion, Runtime.or_else.
 rewrite (remote_completion_ignores_board_text execute source value kind).
 rewrite (worktree_completion_ignores_board_text source value kind).
 rewrite board. reflexivity.
Qed.

Theorem stale_board_text_transition_is_ignored : forall source value id ticket ok,
 string_field "kind" source=Some "board_text" ->
 natural_field "card_id" source=Some id ->
 natural_field "ticket" source=Some ticket ->
 bool_field "ok" source=Some ok ->
 Board.valid_completion_payload source ok=true ->
 (forall card, Board.lookup id value=Some card -> ~ BoardProofs.current_board_lease ticket card) ->
 exists result,
   Board.completion source value=Some (false,false,result) /\
   Packet.transition source value=(false,false,None,result) /\
   decision_reply result=success (JObject [("accepted",JBool false)]) /\
   decision_world result=value /\ decision_effects result=[].
Proof.
 intros source value id ticket ok kind identity issued outcome valid no_lease.
 pose proof (BoardProofs.board_text_without_current_lease_is_ignored
   source value id ticket ok kind identity issued outcome valid no_lease)
   as [result [board [reply [unchanged [effects _]]]]].
 assert (wire : InputDecoder.decode source=None /\ InputDecoder.owns_kind source=false).
 { apply board_text_is_not_a_typed_input; exact kind. }
 assert (completed : Runtime.completion Packet.execute_domain source value=
   Some (false,false,result)).
 { eapply runtime_completion_uses_board_text; eauto. }
 assert (transition : Packet.transition source value=(false,false,None,result)).
 { unfold Packet.transition. rewrite (proj1 wire), (proj2 wire), completed. cbn. reflexivity. }
 exists result. repeat split; assumption.
Qed.

Lemma world_invariant_keeps_an_unchanged_empty_decision : forall value result,
 decision_world result=value -> decision_effects result=[] ->
 decision_world (WorldInvariant.validate value result)=value /\
 decision_effects (WorldInvariant.validate value result)=[].
Proof.
 intros value result unchanged no_effects.
 unfold WorldInvariant.validate.
 destruct (WorldInvariant.world_valid (decision_world result)); cbn [decision_world decision_effects State.reject];
   split; try assumption; reflexivity.
Qed.

Lemma packet_keeps_an_ignored_nondurable_result : forall source value result,
 Packet.transition source value=(false,false,None,result) ->
 decision_world result=value -> decision_effects result=[] ->
 fst (Packet.packet source value)=value /\
 field "effects" (snd (Packet.packet source value))=Some (JArray []) /\
 field "durable" (snd (Packet.packet source value))=Some (JBool false).
Proof.
 intros source value result transition unchanged no_effects.
 unfold Packet.packet. destruct (N.leb _ _) eqn:frame.
 - rewrite transition. cbn beta iota zeta.
   assert (retained : CommitAdmission.retain_live_effects result=result).
   { destruct result as [world reply effects]. cbn in no_effects.
     subst effects. reflexivity. }
   assert (admitted : decision_world (Packet.admit false None source value result)=value /\
     decision_effects (Packet.admit false None source value result)=[]).
   { pose proof (PacketProofs.actual_commit_admission_is_authorized_or_rolled_back
       false None source value result) as [rollback|[_ kept]].
     - exact rollback.
     - rewrite kept, retained. cbn [Notifications.decorate].
       apply world_invariant_keeps_an_unchanged_empty_decision; assumption. }
   destruct admitted as [admitted_world admitted_effects].
   unfold Selvedge.Kernel.Observation.envelope.
   rewrite admitted_world, admitted_effects.
   cbn [Selvedge.Foundation.Json.field Selvedge.Foundation.Json.lookup].
   repeat split; reflexivity.
 - cbn. repeat split; reflexivity.
Qed.

(** This is the public JSON packet entry: an expired, superseded or archived
    card ticket cannot mutate Board/Task state, dispatch work, or advance the
    durable sequence. The callback's false scheduling flag makes this packet
    path skip both after_transition and Scheduler.run. *)
Theorem stale_board_text_packet_has_no_effect : forall source value id ticket ok,
 string_field "kind" source=Some "board_text" ->
 natural_field "card_id" source=Some id ->
 natural_field "ticket" source=Some ticket ->
 bool_field "ok" source=Some ok ->
 Board.valid_completion_payload source ok=true ->
 (forall card, Board.lookup id value=Some card -> ~ BoardProofs.current_board_lease ticket card) ->
 exists result,
   Board.completion source value=Some (false,false,result) /\
   decision_reply result=success (JObject [("accepted",JBool false)]) /\
   decision_world result=value /\ decision_effects result=[] /\
   fst (Packet.packet source value)=value /\
   field "effects" (snd (Packet.packet source value))=Some (JArray []) /\
   field "durable" (snd (Packet.packet source value))=Some (JBool false).
Proof.
 intros source value id ticket ok kind identity issued outcome valid no_lease.
 pose proof (stale_board_text_transition_is_ignored source value id ticket ok
   kind identity issued outcome valid no_lease)
   as [result [completed [transition [reply [unchanged effects]]]]].
 pose proof (packet_keeps_an_ignored_nondurable_result source value result
   transition unchanged effects) as [world [packet_effects packet_durable]].
 exists result. repeat split; assumption.
Qed.
