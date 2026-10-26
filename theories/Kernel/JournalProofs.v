From Stdlib Require Import List Relations Relation_Operators PeanoNat NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet PacketProofs Journal
 WorldInvariant WorldInvariantProofs CommitAdmission ForkCommit ForkCommitAuthorization.
From Selvedge.Kernel Require Scheduler CreationCommit CreationCommitAuthorization DeferredCommitProofs.
From Selvedge.Features Require Import Runtime.
Import ListNotations.

Theorem every_actual_packet_preserves_global_state_relation_or_rolls_back : forall source before,
 well_formed before ->
 let '(after, receipt) := Packet.packet source before in
 WorldInvariant.world_structure after = WorldInvariant.world_structure before \/
 exists input, CommitAdmission.world_evolution input source before after = true.
Proof.
 intros source before Valid; unfold Packet.packet.
 destruct (N.leb (N.of_nat (String.length (TextJson.render_json source))) Limits.frame_bytes).
 - pose proof (CommitPacketProofs.finalized_world_is_authorized source before
     (Packet.select_admitted source (InputDecoder.admit source) before)
     (every_selected_packet_satisfies_the_shared_requirements source (InputDecoder.admit source) before)
     Valid) as Authority.
   unfold Packet.packet_admitted.
   destruct (CommitPacket.finalize before (Packet.select_admitted source (InputDecoder.admit source) before))
     as [after receipt]; cbn [fst] in Authority.
   destruct Authority as [Retained|Evolved]; [left; exact Retained|right; eauto].
 - left; reflexivity.
Qed.

Theorem batches_preserve_input_and_receipt_order : forall first second state,
 run (first ++ second) state = run second (run first state).
Proof. intros; unfold run; apply fold_left_app. Qed.

Theorem every_trace_is_reachable_by_actual_inputs : forall events state,
 reachable state (run events state).
Proof.
 induction events as [|source rest IH]; intros state; cbn [run].
 - apply rt_refl.
 - eapply rt_trans; [apply rt_step; exists source; reflexivity|apply IH].
Qed.

Theorem replay_projects_the_actual_trace : forall events state,
 trace_world (run events state) = replay events (trace_world state).
Proof.
 induction events as [|source rest IH]; intros state; [reflexivity|].
 change (trace_world (run rest (advance source state)) =
  replay rest (fst (Packet.packet source (trace_world state)))).
 rewrite IH. unfold advance.
 destruct (Packet.packet source (trace_world state)); reflexivity.
Qed.

Theorem every_input_retains_one_complete_receipt : forall events state,
 List.length (trace_receipts (run events state)) =
 (List.length events + List.length (trace_receipts state))%nat.
Proof.
 induction events as [|source rest IH]; intros state; [reflexivity|].
 change (List.length (trace_receipts (run rest (advance source state))) =
  S (List.length rest + List.length (trace_receipts state))%nat).
 rewrite IH. unfold advance.
 destruct (Packet.packet source (trace_world state)); cbn; apply Nat.add_succ_r.
Qed.

Theorem extending_a_trace_never_rewrites_prior_receipts : forall events state,
 exists generated, trace_receipts (run events state) = generated ++ trace_receipts state.
Proof.
 induction events as [|source rest IH]; intros state.
 - exists []; reflexivity.
 - change (exists generated, trace_receipts (run rest (advance source state)) = generated ++ trace_receipts state).
   destruct (IH (advance source state)) as [generated Kept].
   rewrite Kept. unfold advance.
   destruct (Packet.packet source (trace_world state)) as [next receipt].
   exists (generated ++ [receipt]); cbn. rewrite <- app_assoc; reflexivity.
Qed.

(* This premise identifies a decoded public read-only command. It does not
   assume the unchanged-world conclusion or any fact about later inputs. *)
Theorem an_actual_query_does_not_change_later_replay : forall first second state source command reply,
 InputDecoder.decode source = Some (UserCommand command) ->
 Packet.query command None (replay first state) = Some reply ->
 replay (first ++ source :: second) state = replay (first ++ second) state.
Proof.
 intros first second state source command reply Decoded Query.
 unfold replay; rewrite !fold_left_app; cbn.
 destruct (actual_query_preserves_world_and_emits_no_effect
  source command reply (replay first state) Decoded Query) as [Unchanged _].
 unfold replay in Unchanged; rewrite Unchanged; reflexivity.
Qed.


Theorem every_actual_history_step_preserves_world_requirements : forall source state,
 world_valid (trace_world state) = true -> world_valid (trace_world (advance source state)) = true.
Proof.
 intros source state Before; unfold advance.
 pose proof (every_actual_packet_preserves_world_requirements source (trace_world state) Before) as Safe.
 destruct (Packet.packet source (trace_world state)); exact Safe.
Qed.
Theorem every_actual_history_preserves_world_requirements : forall events state,
 world_valid (trace_world state) = true -> world_valid (trace_world (run events state)) = true.
Proof.
 induction events as [|source rest IH]; intros state Before; [exact Before|].
 change (world_valid (trace_world (run rest (advance source state))) = true).
 apply IH, every_actual_history_step_preserves_world_requirements; exact Before.
Qed.
Theorem actual_reachability_preserves_world_requirements : forall before after,
 reachable before after -> world_valid (trace_world before) = true -> world_valid (trace_world after) = true.
Proof.
 intros before after Path; induction Path; intros Valid.
 - destruct H as [source Step]; subst y.
   apply every_actual_history_step_preserves_world_requirements; exact Valid.
 - exact Valid.
 - apply IHPath2, IHPath1; exact Valid.
Qed.
Theorem every_actual_replay_preserves_world_requirements : forall events before,
 world_valid before = true -> world_valid (replay events before) = true.
Proof.
 induction events as [|source rest IH]; intros before Valid; [exact Valid|].
 change (world_valid (replay rest (fst (Packet.packet source before))) = true).
 apply IH, every_actual_packet_preserves_world_requirements; exact Valid.
Qed.
Theorem replay_from_initial_establishes_every_named_world_requirement : forall events,
 well_formed (replay events State.initial).
Proof.
 intros events; apply the_world_checker_establishes_all_requirements.
 apply every_actual_replay_preserves_world_requirements, the_initial_world_is_well_formed.
Qed.
