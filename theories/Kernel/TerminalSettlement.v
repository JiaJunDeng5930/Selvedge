From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json OptionList.
From Selvedge.Kernel Require CommandResult RequestReceiver Tasks.
From Selvedge.Kernel Require Import Domain State TaskScope Inputs HookRules HookCallbacks.
From Selvedge.Kernel Require DeferredCommit.
Import ListNotations.

Record after_request := AfterRequest {
 owner : N;
 operation : N;
 ticket : N;
 outcome : after_outcome
}.

(* Only a matching final callback is a transaction of its own. Intermediate
   hooks still need their pending receiver and run through ordinary scheduling. *)
Definition final_action (action : HookRules.after_action) (remaining : list json) :=
 match action,remaining with HookRules.RefuseResult _ _,_ | _,[] => true | _,_ => false end.
Definition resolved_update (request : after_request) (current : task) : option Tasks.result_update :=
 match task_lifecycle current with
 | Archived _ => match RequestReceiver.pending_after (operation request) (ticket request) current with
   | Some (pending,plugin,remaining,previous,failed) =>
     let action := HookRules.after_apply previous (outcome request) in
     if final_action action remaining then
       Some (HookCallbacks.after_result_plan_for (owner request) pending plugin remaining failed (outcome request) action)
     else None
   | None => None end
 | _ => None end.
Definition eligible request current := match resolved_update request current with Some _ => true | None => false end.
Record plan (before : world) := Plan {
 target : TaskScope.task_reference before;
 request : after_request;
 owns_request : TaskScope.owner target = owner request;
 update : Tasks.result_update;
 observed_update : resolved_update request (TaskScope.selected target) = Some update
}.
Arguments target {before}.
Arguments request {before}.
Arguments owns_request {before}.
Arguments update {before}.
Arguments observed_update {before}.
Definition resolve_observed (payload : after_request) (before : world) (current : task)
 (observed : find_task (owner payload) before = Some current) : option (plan before) :=
 OptionList.observe (resolved_update payload current)
   (fun update Final => Some (Plan before (TaskScope.TaskReference before (owner payload) current observed)
      payload eq_refl update Final)) (fun _ => None).
Definition resolve_request (payload : after_request) (before : world) : option (plan before) :=
 OptionList.observe (find_task (owner payload) before)
   (fun current observed => resolve_observed payload before current observed) (fun _ => None).

Definition resolve (input : input) (before : world) := match input with
 | AfterCompleted owner operation ticket outcome =>
   resolve_request (AfterRequest owner operation ticket outcome) before
 | _ => None end.

Definition interpret_change {before : world} (accepted : plan before) :=
 CommandResult.Change (JObject [("accepted"%string,JBool true)])
   (Tasks.interpret_result (target accepted) (update accepted)) [].
(* The settled callback commits before independent runtime maintenance. The
   selected plan is an accepted settlement even when its hook result failed. *)
Definition candidate {before : world} (accepted : plan before) :=
 DeferredCommit.continue_result before (CommandResult.Accepted (interpret_change accepted)).
Definition source {before : world} (accepted : plan before) :=
 let payload := request accepted in
 AfterCompleted (owner payload) (operation payload) (ticket payload) (outcome payload).
Definition packet {before : world} (accepted : plan before) (raw : Json.json) :=
 DeferredCommit.packet (Some (source accepted)) raw before (candidate accepted).
