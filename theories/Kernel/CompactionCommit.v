From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import State Inputs.
From Selvedge.Programming Require Import DeferredCommit.
From Selvedge.Features Require Import Compaction.

(* Checkpoint admission owns this transaction. Scheduling may begin new work
   only after its replacement record or observation request is durable. *)
Definition candidate (request : Commands.compact_payload) (before : world) :=
 DeferredCommit.continue_result before (Compaction.handle_compact_result request None before).

Definition packet (raw : json) (request : Commands.compact_payload) (before : world) :=
 DeferredCommit.packet (Some (UserCommand (Commands.Cmd_compact request))) before
   (candidate request before).
