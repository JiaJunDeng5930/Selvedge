From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Programming Require DecisionComposition.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Inputs InputDecoder
 Scheduler SideContext Dispatch Limits Observation Notifications Delivery Packet.
From Selvedge.Kernel Require Import TicketedRequest.
From Selvedge.Kernel Require Import Capabilities PacketBusinessProofs.
From Selvedge.Kernel Require Import ScopedRequestProofs.
From Selvedge.Kernel Require Import TerminalSettlement TerminalSettlementPlanProofs DeferredCommitProofs.
From Selvedge.Kernel Require CreationCommit NativeForkCommit BoardCommit ConnectionCommit TitleCommit.
From Selvedge.Features Require Import Runtime.
Import ListNotations.
Open Scope string_scope.

(* Final archived callbacks commit their owned result before unrelated runtime
   work. The finite request constructor proves its exact local writes; the
   continuation retains normal task and feature progress after that commit. *)
Theorem an_archived_result_is_committed_by_the_exported_packet :
 forall raw before (accepted : TerminalSettlement.plan before),
 Packet.decode raw = Some (inl (TerminalSettlement.source accepted)) ->
 TerminalSettlement.resolve (TerminalSettlement.source accepted) before = Some accepted ->
 N.leb (N.of_nat (String.length (TextJson.render_json raw))) Limits.frame_bytes = true ->
 Delivery.fits true (TerminalSettlement.candidate accepted) = true ->
 Packet.packet raw before =
 (with_sequence (N.succ (world_sequence before)) (decision_world (TerminalSettlement.candidate accepted)),
  Notifications.envelope true true (Some (TerminalSettlement.source accepted)) before
    (TerminalSettlement.candidate accepted)).
Proof.
 intros raw before accepted Decoded Resolved InputBudget OutputBudget.
 unfold Packet.packet, Packet.select.
 rewrite InputBudget; cbv beta zeta; rewrite Decoded.
 cbn [Packet.select_change Packet.core_input Packet.manual_fork_input CreationCommit.input Packet.deferred_candidate BoardCommit.input
  ConnectionCommit.input TitleCommit.input Packet.native_fork_input
  NativeForkCommit.resolve Packet.terminal_settlement_input TerminalSettlement.source].
 rewrite Resolved.
 apply a_constructed_candidate_with_its_actual_budget_is_committed; [|exact OutputBudget].
 reflexivity.
Qed.

(* The public result follows from callback ownership, decoded input and the
   frame budgets. Other tasks and feature registries are arbitrary. *)
Theorem every_owned_terminal_callback_commits_at_the_public_packet :
 forall raw before payload current,
 let input := AfterCompleted (TerminalSettlement.owner payload) (TerminalSettlement.operation payload)
   (TerminalSettlement.ticket payload) (TerminalSettlement.outcome payload) in
 Packet.decode raw = Some (inl input) ->
 find_task (TerminalSettlement.owner payload) before = Some current ->
 (match TerminalSettlement.resolved_update payload current with Some _ => true | None => false end) = true ->
 N.leb (N.of_nat (String.length (TextJson.render_json raw))) Limits.frame_bytes = true ->
 exists accepted, TerminalSettlement.resolve_request payload before = Some accepted /\
 (Delivery.fits true (TerminalSettlement.candidate accepted) = true ->
  let result := TerminalSettlement.candidate accepted in
  Packet.packet raw before =
  (with_sequence (N.succ (world_sequence before)) (decision_world result),
   Notifications.envelope true true (Some input) before result) /\
  bool_default "ok" (decision_reply result) false = true /\
  decision_effects result = [ContinueScheduling]).
Proof.
 intros raw before payload current input Decoded Found Eligible InputBudget.
 destruct (every_owned_terminal_callback_resolves_its_finite_transaction payload before current Found Eligible)
  as [accepted Resolved].
 pose proof (resolution_retains_the_callback_payload payload before accepted Resolved) as Payload.
 assert (Source : TerminalSettlement.source accepted = input).
 { unfold TerminalSettlement.source; rewrite Payload; reflexivity. }
 exists accepted; split; [exact Resolved|]; intro OutputBudget; cbn beta zeta; split.
 - rewrite <- Source.
   apply an_archived_result_is_committed_by_the_exported_packet; try assumption.
   + rewrite Source; exact Decoded.
   + rewrite Source; unfold input, TerminalSettlement.resolve.
     destruct payload; exact Resolved.
 - split; reflexivity.
Qed.
