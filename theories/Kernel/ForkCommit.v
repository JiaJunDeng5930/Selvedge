From Selvedge.Kernel Require CommitPacket.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain Codec State CommandHandlers Delivery Notifications.
From Selvedge.Features Require Import Worktree.
Import ListNotations.

(** A manual fork commits its own births before independent scheduler work.
    The existing durable continuation drives that work after this transaction. *)
Definition workspace_error (before after : world) : option CommandResult.refusal :=
 match skipn (List.length (world_tasks before)) (world_tasks after) with
 | [] => None
 | child :: _ =>
   let selected := task_current_settings child in
   (* DEFENSE: A selected managed workspace may have been archived before this
      command. Fork siblings share this selection, so admit the observation once. *)
   if Worktree.workspace_available (settings_workspace selected) before &&
      Worktree.binding_available selected after
   then None
   else Some (CommandResult.Refusal "worktree_unavailable"%string
     "The selected workspace belongs to an unavailable managed worktree"%string)
 end.
Definition admit_workspace (before : world) (candidate : CommandResult.result CommandResult.change) :=
 CommandResult.bind candidate (fun change => match workspace_error before (CommandResult.change_world change) with
 | None => CommandResult.Accepted change | Some reason => CommandResult.Rejected reason end).
Definition propose_result (request : Commands.fork_payload) (before : world) :=
 if Worktree.execution_allowed (Commands.fork_task_id request) before
 then CommandExecution.handle_fork_result request None before
 else CommandResult.Rejected Worktree.failed_execution_reason.
Definition candidate (request : Commands.fork_payload) (before : world) :=
 CommandResult.commit before
   (fun change => CommandResult.Change (CommandResult.change_value change)
     (CommandResult.change_world change) [ContinueScheduling])
   (admit_workspace before (propose_result request before)).

Definition select (request : Commands.fork_payload) (before : world) :=
 CommitPacket.choose true (Some (Inputs.UserCommand (Commands.Cmd_fork request)))
   (Delivery.deliver_with_status true (candidate request before) before).
Definition packet (request : Commands.fork_payload) (before : world) : world * json :=
 CommitPacket.finalize before (select request before).
