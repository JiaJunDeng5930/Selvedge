From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain Codec State CommandHandlers Delivery Notifications.
From Selvedge.Features Require Import Worktree.
Import ListNotations.

(** A manual fork commits its own births before independent scheduler work.
    The existing durable continuation drives that work after this transaction. *)
Definition admit_workspace (before : world) (candidate : decision) :=
 match skipn (List.length (world_tasks before)) (world_tasks (decision_world candidate)) with
 | [] => candidate
 | child :: _ =>
   let selected := task_current_settings child in
   (* DEFENSE: A selected managed workspace may have been archived before this
      command. Fork siblings share this selection, so admit the observation once. *)
   if Worktree.workspace_available (settings_workspace selected) before &&
      Worktree.binding_available selected (decision_world candidate)
   then candidate
   else reject "worktree_unavailable"%string
     "The selected workspace belongs to an unavailable managed worktree"%string before
 end.

Definition propose (request : Commands.fork_payload) (before : world) :=
 match Worktree.execution_guard (Commands.fork_task_id request) before with
 | Some refused => refused
 | None => CommandHandlers.execute (Commands.Cmd_fork request) None before
 end.

Definition candidate (request : Commands.fork_payload) (before : world) :=
 let result := admit_workspace before (propose request before) in
 if bool_default "ok"%string (decision_reply result) false
 then Decision (decision_world result) (decision_reply result) [ContinueScheduling]
 else result.

Definition packet (request : Commands.fork_payload) (before : world) : world * json :=
 let '(fits,result) := Delivery.deliver_with_status true (candidate request before) before in
 (with_sequence (N.succ (world_sequence before)) (decision_world result),
  Notifications.envelope true fits (Some (Inputs.UserCommand (Commands.Cmd_fork request))) before result).
