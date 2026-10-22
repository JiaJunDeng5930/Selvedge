From Stdlib Require Import List Relations Relation_Operators.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import State Packet.
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

