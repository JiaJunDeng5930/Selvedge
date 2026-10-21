From Stdlib Require Import List Relations Relation_Operators PeanoNat.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Inputs InputDecoder Packet PacketProofs.
Import ListNotations.

(* A trace records the complete envelopes returned by the actual exported
   packet entry. The physical journal replays this entry one input at a time;
   effect descriptions are retained as data, never performed by replay. *)
Record trace := Trace { trace_world : world; trace_receipts : list json }.
Definition advance (source : json) (state : trace) :=
 let '(next,receipt) := Packet.packet source (trace_world state) in
 Trace next (receipt :: trace_receipts state).
Definition run (events : list json) (state : trace) := fold_left (fun state source => advance source state) events state.
Definition replay (events : list json) (state : world) :=
 fold_left (fun state source => fst (Packet.packet source state)) events state.
Definition edge (before after : trace) := exists source, after = advance source before.
Definition reachable := clos_refl_trans trace edge.

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
 List.length events + List.length (trace_receipts state).
Proof.
 induction events as [|source rest IH]; intros state; [reflexivity|].
 change (List.length (trace_receipts (run rest (advance source state))) =
  S (List.length rest + List.length (trace_receipts state))).
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
