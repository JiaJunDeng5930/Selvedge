From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain State.
Import ListNotations.

Definition request_coordinate (request : effect) := match request with
 | ObserveContext id ticket _ | RequestModel id ticket _ _ _ _
 | RequestReasoning id ticket _ _ | ExecuteTool id ticket _ _ _ _ _
 | RequestApproval id ticket _ _ _ | CheckTool id ticket _ _ _ => Some (id,ticket)
 | _ => None end.
Definition cancelled (effects : list effect) (id ticket : N) :=
 existsb (fun request => match request with
 | CancelTask owner => N.eqb owner id
 | CancelTicket owner expected => N.eqb owner id && N.eqb expected ticket
 | _ => false end) effects.
(* DEFENSE: A later native action can archive or cancel a request emitted earlier
   in this same decision. Its uncommitted intent must never reach physical IO. *)
Definition live_request (value : world) (effects : list effect) (request : effect) :=
 match request_coordinate request with
 | Some (id,ticket) => match find_task id value with
   | Some task => match task_lifecycle task with
     | Archived => false | _ => negb (cancelled effects id ticket) end
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
   requests retain their captured history and correlation ticket. *)
Definition capture_request (request : effect) (value : world) : world * effect :=
 match request with
 | ObserveContext id ticket original => match side_task id value with
   | Some current => match task_activity current with
     | ObservingContext expected => if N.eqb expected ticket then
       (value,ObserveContext id ticket (with_history (task_history current) original)) else (value,request)
     | _ => (value,request) end
   | None => (value,request) end
 | RequestModel id ticket model original scope reserve => match side_task id value with
   | Some current => match task_activity current with
     | AskingModel expected _ _ => if N.eqb expected ticket then
       (put_task id (with_model_cursor (List.length (task_history current)) current) value,
        RequestModel id ticket model (with_history (task_history current) original) scope reserve)
       else (value,request)
     | _ => (value,request) end
   | None => (value,request) end
 | RequestReasoning id ticket model original => match side_task id value with
   | Some current => match task_activity current with
     | EvaluatingReasoning expected _ => if N.eqb expected ticket then
       (put_task id (with_activity (EvaluatingReasoning ticket (List.length (task_history current))) current) value,
        RequestReasoning id ticket model (with_history (task_history current) original)) else (value,request)
     | _ => (value,request) end
   | None => (value,request) end
 | _ => (value,request) end.
Fixpoint capture_requests (effects : list effect) (value : world) :=
 match effects with
 | [] => (value,[])
 | request :: rest => let '(value,request) := capture_request request value in
   let '(value,rest) := capture_requests rest value in (value,request :: rest)
 end.
Definition prepare (value : world) (effects : list effect) :=
 let '(value,effects) := capture_requests effects value in
 (value,filter (live_request value effects) effects).
