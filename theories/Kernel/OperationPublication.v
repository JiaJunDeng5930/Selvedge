From Stdlib Require Import String List.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain.
Import ListNotations.
Open Scope string_scope.

Definition notice (value : operation) := JObject [
 ("status",JString (match operation_stage value with AwaitingApproval _ _ => "awaiting_approval"
  | Granted _ => "approved_waiting_to_run" | _ => "running" end));
 ("operation_id",number (operation_id value));("tool",JString (call_name (operation_call value)));
 ("message",JString (match operation_stage value with
 | AwaitingApproval _ HumanReviewer => "Bash has not started. This exact command is waiting for the user's one-operation approval in the UI. Continue independent work or end the turn; do not poll or try to approve it yourself."
 | AwaitingApproval _ (ModelReviewer _) => "Bash has not started. An independent, tool-free reviewer is assessing this exact command. The result arrives automatically; do not poll or create another task to review it."
 | Granted _ => "A one-operation grant is committed, but Bash has not started. It will run only when the task is active."
 | _ => "This operation is still running, not completed. Its result will arrive as an asynchronous operation result. Continue independent work, or end your turn to wait; do not poll or sleep just to wait." end))].

(** A notice closes the original provider call. From that point on the
    completion addresses the published operation instead. *)
Definition advance (value : operation) : operation * option message :=
 match operation_result_route value with
 | ProviderCall =>
   (Operation (operation_id value) (operation_call value) PublishedOperation (operation_stage value),
    Some (FunctionOutput (call_id (operation_call value)) (notice value) false))
 | PublishedOperation => (value,None)
 end.
Definition collect (values : list operation) : list operation * list message :=
 fold_right (fun value rest =>
   let '(next,receipt) := advance value in
   (next :: fst rest, match receipt with Some item => item :: snd rest | None => snd rest end))
   ([],[]) values.
