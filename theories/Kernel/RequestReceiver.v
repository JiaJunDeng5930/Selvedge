From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State.
From Selvedge.Programming Require Import TaskScope.

(* The pending phase owns both correlation and the frozen continuation data.
   Callbacks and outgoing-effect admission consume this same description. *)
Inductive phase_kind := ContextReceiver | ModelReceiver | ReasoningReceiver | HookReceiver.
Definition phase_payload (kind : phase_kind) : Type := match kind with
 | ContextReceiver | ReasoningReceiver => nat
 | ModelReceiver => list string * output_mode
 | HookReceiver => json * call * list json * list call end.
Definition phase_receiver (kind : phase_kind) (phase : activity)
 : option (N * phase_payload kind) := match kind return option (N * phase_payload kind) with
 | ContextReceiver => match phase with ObservingContext ticket revision => Some (ticket,revision) | _ => None end
 | ModelReceiver => match phase with AskingModel ticket allowed mode => Some (ticket,(allowed,mode)) | _ => None end
 | ReasoningReceiver => match phase with EvaluatingReasoning ticket revision => Some (ticket,revision) | _ => None end
 | HookReceiver => match phase with CheckingHook ticket plugin invocation pending remaining =>
     Some (ticket,(plugin,invocation,pending,remaining)) | _ => None end end.
Definition pending_phase (kind : phase_kind) (ticket : N) (current : task) : option (phase_payload kind) :=
 match phase_receiver kind (task_activity current) with
 | Some (expected,payload) => if N.eqb expected ticket then Some payload else None
 | None => None end.
Definition operation_at (identity : N) (current : task) :=
 find (fun pending => N.eqb identity (operation_id pending)) (task_operations current).
Inductive operation_kind := ExecutionReceiver | ApprovalReceiver | AfterReceiver.
Definition operation_payload (kind : operation_kind) : Type := match kind with
 | ExecutionReceiver => option reviewer | ApprovalReceiver => reviewer
 | AfterReceiver => json * list json * json * bool end.
Definition operation_receiver (kind : operation_kind) (pending : operation)
 : option (N * operation_payload kind) := match kind return option (N * operation_payload kind) with
 | ExecutionReceiver => match operation_stage pending with
   | Executing ticket => Some (ticket,None) | Elevated ticket actor => Some (ticket,Some actor) | _ => None end
 | ApprovalReceiver => match operation_stage pending with
   | AwaitingApproval ticket actor => Some (ticket,actor) | _ => None end
 | AfterReceiver => match operation_stage pending with
   | AwaitingAfterHook ticket plugin remaining result error => Some (ticket,(plugin,remaining,result,error))
   | _ => None end end.
Definition operation_executing (ticket : N) (pending : operation) :=
 match operation_receiver ExecutionReceiver pending with
 | Some (expected,_) => N.eqb expected ticket | None => false end.
Definition operation_tickets (pending : operation) :=
 operation_id pending :: match operation_stage pending with
 | Executing ticket | AwaitingApproval ticket _ | Elevated ticket _
 | AwaitingAfterHook ticket _ _ _ _ =>
   if N.eqb ticket (operation_id pending) then nil else ticket :: nil
 | Granted _ | AfterHooksReady _ _ _ => nil end.
Definition pending_tool (ticket : N) (current : task) := find (operation_executing ticket) (task_operations current).
Definition find_approval (selected : N -> N -> reviewer -> bool) (operations : list operation)
 : option (operation * reviewer) :=
 fold_right (fun pending rest => match operation_receiver ApprovalReceiver pending with
 | Some (ticket,actor) =>
   if selected (operation_id pending) ticket actor then Some (pending,actor) else rest
 | _ => rest end) None operations.
Definition pending_approval (ticket : N) (current : task) :=
 find_approval (fun _ expected actor => match actor with
   | ModelReviewer _ => N.eqb ticket expected | HumanReviewer => false end) (task_operations current).
Definition pending_human_approval (identity : N) (current : task) :=
 find_approval (fun candidate _ actor => N.eqb identity candidate &&
   match actor with HumanReviewer => true | ModelReviewer _ => false end) (task_operations current).
Definition pending_after (identity ticket : N) (current : task) :=
 match operation_at identity current with
 | Some pending => match operation_receiver AfterReceiver pending with
   | Some (expected,(plugin,remaining,result,error)) =>
     if N.eqb expected ticket then Some (pending,plugin,remaining,result,error) else None
   | _ => None end
 | None => None end.
Definition deliver_or {A : Type} (id : N) (before : world) (lookup : task -> option A)
 (refused : decision) (handle : task_reference before -> A -> decision) :=
 (* DEFENSE: An asynchronous delivery may be stale, duplicated, or arrive after
    cancellation. Only the retained receiver authorizes its continuation. *)
 match TaskScope.select id before with
 | Some target => match lookup (selected target) with
   | Some payload => handle target payload | None => refused end
 | None => refused end.
Definition deliver {A : Type} (id : N) (before : world) (lookup : task -> option A)
 (handle : task_reference before -> A -> decision) :=
 deliver_or id before lookup (State.ignored before) handle.
