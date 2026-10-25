From Stdlib Require Import List Bool NArith.
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
Definition eligible (request : after_request) (current : task) :=
 match task_lifecycle current with
 | Archived operations =>
   match find (fun pending => N.eqb (operation request) (operation_id pending)) operations with
   | Some pending => match operation_stage pending with
     | AwaitingAfterHook expected _ remaining result _ => N.eqb expected (ticket request) &&
       match HookRules.after_apply result (outcome request), remaining with
       | HookRules.RefuseResult _ _, _ | _, [] => true
       | _, _ => false end
     | _ => false end
   | None => false end
 | _ => false end.

Record plan (before : world) := Plan {
 target : TaskScope.task_reference before;
 request : after_request;
 owns_request : TaskScope.owner target = owner request;
 finishes_operation : eligible request (TaskScope.selected target) = true
}.
Arguments target {before}.
Arguments request {before}.
Arguments owns_request {before}.
Arguments finishes_operation {before}.

Definition resolve_observed (request : after_request) (before : world) (current : task)
 (observed : find_task (owner request) before = Some current) : option (plan before).
Proof.
 destruct (eligible request current) eqn:Final; [|exact None].
 exact (Some (Plan before (TaskScope.TaskReference before (owner request) current observed)
   request eq_refl Final)).
Defined.
Definition resolve_request (request : after_request) (before : world) : option (plan before) :=
 match find_task (owner request) before as found return
   find_task (owner request) before = found -> option (plan before) with
 | Some current => fun observed => resolve_observed request before current observed
 | None => fun _ => None
 end eq_refl.

Definition resolve (input : input) (before : world) := match input with
 | AfterCompleted owner operation ticket outcome =>
   resolve_request (AfterRequest owner operation ticket outcome) before
 | _ => None end.

Definition interpret {before : world} (accepted : plan before) :=
 let payload := request accepted in
 HookCallbacks.after_completed (owner payload) (operation payload) (ticket payload) (outcome payload) before.

(* The settled result and its callback receipt commit together. Runtime feature
   maintenance follows through the existing durable continuation; it has no
   authority to roll this unrelated owned result back. *)
Definition candidate {before : world} (accepted : plan before) :=
 DeferredCommit.continue (interpret accepted).
Definition source {before : world} (accepted : plan before) :=
 let payload := request accepted in
 AfterCompleted (owner payload) (operation payload) (ticket payload) (outcome payload).
Definition packet {before : world} (accepted : plan before) (raw : Json.json) :=
 DeferredCommit.packet (Some (source accepted)) raw before (candidate accepted).
