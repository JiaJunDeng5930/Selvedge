From Selvedge.Programming Require CommandResult.
From Selvedge.Programming Require CommitPacket.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain Codec State CommandHandlers Delivery Notifications.
From Selvedge.Features Require Import Worktree.
Import ListNotations.

(** A manual fork commits its own births before independent scheduler work.
    The existing durable continuation drives that work after this transaction. *)
Definition candidate (request : Commands.fork_payload) (before : world) :=
 CommandResult.commit before
   (fun change => CommandResult.Change (CommandResult.change_value change)
     (CommandResult.change_world change) [ContinueScheduling])
   (CommandExecution.handle_fork_result request None before).

Definition select (request : Commands.fork_payload) (before : world) :=
 CommitPacket.choose true (Some (Inputs.UserCommand (Commands.Cmd_fork request)))
   (Delivery.deliver_with_status true (candidate request before) before).
Definition packet (request : Commands.fork_payload) (before : world) : world * json :=
 CommitPacket.finalize before (select request before).
