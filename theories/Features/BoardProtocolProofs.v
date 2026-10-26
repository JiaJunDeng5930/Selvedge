From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import Numbers State InputDecoder CallbackProtocolProofs Packet PacketProofs WorldInvariant Notifications Delivery CommitAdmission.
From Selvedge.Features Require Import Board BoardProofs Remote Worktree Runtime.
Import ListNotations.
Open Scope string_scope.

Lemma board_text_is_not_a_typed_input : forall source,
 string_field "kind" source=Some "board_text" ->
 InputDecoder.decode source=None /\ InputDecoder.owns_kind source=false.
Proof.
 intros source Kind; split.
 - unfold InputDecoder.decode.
   destruct source as [|boolean|decimal|text|items|members]; try reflexivity.
   unfold Json.string_field,Json.field in Kind.
   destruct (Schema.unique_names (map fst members)); [|reflexivity].
   destruct (Json.lookup "kind" members) as [value|] eqn:Tag; [|reflexivity].
   destruct value; cbn [as_string] in Kind; try discriminate.
   inversion Kind; subst.
   unfold ModelDeclarations.decode_cases.
   rewrite input_find_is_named with (name:="board_text") by exact Tag; reflexivity.
 - unfold InputDecoder.owns_kind; rewrite Kind; reflexivity.
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

Theorem stale_board_text_transition_is_ignored : forall source value ok payload,
 string_field "kind" source=Some "board_text" ->
 bool_field "ok" source=Some ok ->
 Board.decode_completion_payload source ok=Some payload ->
 (forall card, Board.lookup (Board.completion_card payload) value=Some card ->
   ~ BoardProofs.current_board_lease (Board.completion_ticket payload) card) ->
 exists result,
   Board.completion source value=Some (false,false,result) /\
   Packet.transition source value=(false,false,None,result) /\
   decision_reply result=success (JObject [("accepted",JBool false)]) /\
   decision_world result=value /\ decision_effects result=[].
Proof.
 intros source value ok payload kind outcome parsed no_lease.
 pose proof (BoardProofs.board_text_without_current_lease_is_ignored
   source value ok payload kind outcome parsed no_lease)
   as [result [board [reply [unchanged [effects _]]]]].
 assert (wire : InputDecoder.decode source=None /\ InputDecoder.owns_kind source=false).
 { apply board_text_is_not_a_typed_input; exact kind. }
 assert (completed : Runtime.completion Packet.execute_domain source value=
   Some (false,false,result)).
 { eapply runtime_completion_uses_board_text; eauto. }
 assert (transition : Packet.transition source value=(false,false,None,result)).
 { unfold Packet.transition, Packet.transition_decoded. rewrite (proj1 wire), (proj2 wire), completed. cbn. reflexivity. }
 exists result. repeat split; assumption.
Qed.

Lemma packet_keeps_an_ignored_nondurable_result : forall source value result,
 Packet.transition source value=(false,false,None,result) ->
 decision_world result=value -> decision_effects result=[] ->
 fst (Packet.packet source value)=value /\
 field "effects" (snd (Packet.packet source value))=Some (JArray []) /\
 field "durable" (snd (Packet.packet source value))=Some (JBool false).
Proof.
 intros source value result Transition Unchanged Empty.
 unfold Packet.packet,Packet.packet_admitted; destruct (N.leb _ _).
 - rewrite (PacketProofs.a_nondurable_transition_selects_its_ordinary_commit source value result _ Transition).
   apply DeferredCommitProofs.a_noncommitting_unchanged_candidate_has_no_effect; assumption.
 - repeat split; reflexivity.
Qed.

(** This is the public JSON packet entry: an expired, superseded or archived
    card ticket cannot mutate Board/Task state, dispatch work, or advance the
    durable sequence. The callback's false scheduling flag makes this packet
    path skip both after_transition and Scheduler.run. *)
Theorem stale_board_text_packet_has_no_effect : forall source value ok payload,
 string_field "kind" source=Some "board_text" ->
 bool_field "ok" source=Some ok ->
 Board.decode_completion_payload source ok=Some payload ->
 (forall card, Board.lookup (Board.completion_card payload) value=Some card ->
   ~ BoardProofs.current_board_lease (Board.completion_ticket payload) card) ->
 exists result,
   Board.completion source value=Some (false,false,result) /\
   decision_reply result=success (JObject [("accepted",JBool false)]) /\
   decision_world result=value /\ decision_effects result=[] /\
   fst (Packet.packet source value)=value /\
   field "effects" (snd (Packet.packet source value))=Some (JArray []) /\
   field "durable" (snd (Packet.packet source value))=Some (JBool false).
Proof.
 intros source value ok payload kind outcome parsed no_lease.
 pose proof (stale_board_text_transition_is_ignored source value ok payload
   kind outcome parsed no_lease)
   as [result [completed [transition [reply [unchanged effects]]]]].
 pose proof (packet_keeps_an_ignored_nondurable_result source value result
   transition unchanged effects) as [world [packet_effects packet_durable]].
 exists result. repeat split; assumption.
Qed.
