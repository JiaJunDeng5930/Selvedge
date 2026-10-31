From Selvedge.Programming Require CommandResult.
From Selvedge.Programming Require CommitPacket.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain Codec State Inputs Delivery Notifications.
From Selvedge.Features Require Import Worktree.
Import ListNotations.

(* Creation commits its birth and resource request before independent scheduling.
   The continuation is durable, just as it is for a public manual fork. *)
Definition input (decoded : option Inputs.input) : option Commands.create_payload :=
 match decoded with
 | Some (UserCommand (Commands.Cmd_create request)) => Some request
 | _ => None
 end.
Definition candidate (request : Commands.create_payload) (before : world) :=
 CommandResult.commit before
   (fun birth => CommandResult.append_effects [ContinueScheduling] (Worktree.transition_change birth))
   (Worktree.handle_create_result request None before).
Definition select (request : Commands.create_payload) (before : world) :=
 CommitPacket.choose true (Some (Inputs.UserCommand (Commands.Cmd_create request)))
   (Delivery.deliver_with_status true (candidate request before) before).
Definition packet (request : Commands.create_payload) (before : world) : world * json :=
 CommitPacket.finalize before (select request before).
