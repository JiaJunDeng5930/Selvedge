From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain State Reasoning.
From Selvedge.Features Require CompactionTypes.
Import ListNotations.
Module C := Selvedge.Features.CompactionTypes.

Definition request_coordinate (request : effect) := match request with
 | RequestModel request => Some (ModelRequest.owner request, ModelRequest.ticket request)
 | ObserveContext id ticket _
 | RequestReasoning id ticket _ | ExecuteTool id ticket _ _ _ _ _
 | RequestApproval id ticket _ _ _ | CheckTool id ticket _ _ _ => Some (id,ticket)
 | MaintainContext (C.Scope id ticket _)
 | MaintainContext (C.Measure id ticket _ _ _)
 | MaintainContext (C.Compact id ticket _ _ _ _) => Some (id,ticket)
 | _ => None end.
Definition cancelled (effects : list effect) (id ticket : N) :=
 existsb (fun request => match request with
 | CancelTask owner => N.eqb owner id
 | CancelTicket owner expected | MaintainContext (C.Cancel owner expected) =>
   N.eqb owner id && N.eqb expected ticket
 | _ => false end) effects.
(* DEFENSE: A later native action can archive or cancel a request emitted earlier
   in this same decision. Unfreeze maintenance can issue Scope before a pending
   native self-archive clears its receiver. Core and maintenance requests share
   this final withdrawal; their uncommitted intent must never reach physical IO. *)
Definition live_request (value : world) (effects : list effect) (request : effect) :=
 match request_coordinate request with
 | Some (id,ticket) => match find_task id value with
   | Some task => match task_lifecycle task with
     | Archived _ => false | _ => negb (cancelled effects id ticket) end
   | None => false end
 | None => match request with
   | CheckResult id ticket operation _ _ _ _ => match find_task id value with
     | Some task => existsb (fun pending => N.eqb operation (operation_id pending) &&
       match operation_stage pending with AwaitingAfterHook expected _ _ _ _ => N.eqb ticket expected | _ => false end)
       (task_operations task)
     | None => false end
   | _ => true end end.
Definition side_task (id : N) (value : world) := match find_task id value with
 | Some task => match task_side_parent task with Some _ => Some task | None => None end
 | None => None end.
(* Only requests produced by this decision are refreshed. Already dispatched
   requests retain their captured history and correlation ticket. An ordinary
   task can also receive a native operation cancellation later in this decision;
   its unstarted context read must capture that final history and source length.
   Model and reasoning selection are frozen at Scheduler's commit boundary. *)
Definition capture_request (request : effect) (value : world) : world * effect :=
 match request with
 | ObserveContext id ticket original => match find_task id value with
   | Some current => match task_activity current with
     | ObservingContext expected _ => if N.eqb expected ticket then
       (put_task id (Reasoning.capture ticket current) value,
        ObserveContext id ticket (with_history (task_history current) original)) else (value,request)
     | _ => (value,request) end
   | None => (value,request) end
 | RequestModel snapshot =>
   let id := ModelRequest.owner snapshot in
   let ticket := ModelRequest.ticket snapshot in
   match side_task id value with
   | Some current => match task_activity current with
     | AskingModel expected _ _ => if N.eqb expected ticket then
       (put_task id (with_model_cursor (List.length (task_history current)) current) value,
        RequestModel (ModelRequest.with_history (task_history current) snapshot))
       else (value,request)
     | _ => (value,request) end
   | None => (value,request) end
 | RequestReasoning id ticket original => match side_task id value with
   | Some current => match task_activity current with
     | EvaluatingReasoning expected _ => if N.eqb expected ticket then
       (put_task id (with_activity (EvaluatingReasoning ticket (List.length (task_history current))) current) value,
        RequestReasoning id ticket (with_history (task_history current) original)) else (value,request)
     | _ => (value,request) end
   | None => (value,request) end
 | _ => (value,request) end.
Fixpoint capture_requests (effects : list effect) (value : world) :=
 match effects with
 | [] => (value,[])
 | request :: rest => let '(value,request) := capture_request request value in
   let '(value,rest) := capture_requests rest value in (value,request :: rest)
 end.
Definition prepare (value : world) (effects : list effect) := capture_requests effects value.
(** The single withdrawal point runs after all scheduling and feature postprocessing. *)
Definition retain_live_effects (candidate : decision) :=
 let effects := decision_effects candidate in
 Decision (decision_world candidate) (decision_reply candidate)
   (filter (live_request (decision_world candidate) effects) effects).
