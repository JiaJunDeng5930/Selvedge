From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require CommandResult TaskChange.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State Inputs Scheduler.
From Selvedge.Programming Require Import TaskScope.
From Selvedge.Kernel Require Import CommandExecution ForkCommit.
From Selvedge.Programming Require Import DeferredCommit.
From Selvedge.Features Require Import Runtime.
Import ListNotations.

Record plan (before : world) := Plan {
 planned_step : Scheduler.native_fork_step;
 planned_target : TaskScope.task_reference before;
 planned_owner : TaskScope.owner planned_target = Scheduler.native_fork_owner planned_step;
 planned_selection : Scheduler.first_native_fork Runtime.can_schedule_task 0
   (world_tasks before) before = Some planned_step
}.
Arguments planned_step {before}.
Arguments planned_target {before}.
Definition resolve (source : Inputs.input) (before : world) : option (plan before) :=
 match source with
 | Continue =>
   match Scheduler.first_native_fork Runtime.can_schedule_task 0
     (world_tasks before) before as selected
     return Scheduler.first_native_fork Runtime.can_schedule_task 0
       (world_tasks before) before = selected -> option (plan before) with
   | Some step => fun evidence =>
     match find_task (Scheduler.native_fork_owner step) before as found
       return find_task (Scheduler.native_fork_owner step) before = found -> option (plan before) with
     | Some task => fun observed => Some (Plan before step
       (TaskScope.TaskReference before (Scheduler.native_fork_owner step) task observed) eq_refl evidence)
     | None => fun _ => None end eq_refl
   | None => fun _ => None end eq_refl
 | _ => None end.
Definition started_world {before : world} (accepted : plan before) :=
 let step := planned_step accepted in
 TaskChange.interpret (TaskChange.Plan before (planned_target accepted)
   [TaskChange.ChangePhase (PendingCalls (Scheduler.native_fork_remaining step))]).
Definition business_result {before : world} (accepted : plan before) :=
 let step := planned_step accepted in
 let started := started_world accepted in
 CommandExecution.handle_fork_result (Scheduler.native_fork_request step)
     (Some (Tasks.NativeCall (Scheduler.native_fork_owner step)
       (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step))) started.
Definition settle_result owner invocation remaining before (outcome : CommandResult.result CommandResult.change) :=
 let result := CommandResult.decide before outcome in
 let '(value,failed) := match outcome with
   | CommandResult.Accepted _ => (number 0,false)
   | CommandResult.Rejected reason => (failure (CommandResult.refusal_code reason) (CommandResult.refusal_message reason),true) end in
 Scheduler.finish_call owner invocation remaining value failed result.
Definition interpret {before : world} (accepted : plan before) :=
 let step := planned_step accepted in
 settle_result (Scheduler.native_fork_owner step) (Scheduler.native_fork_invocation step)
   (Scheduler.native_fork_remaining step) (started_world accepted) (business_result accepted).
Definition candidate {before : world} (accepted : plan before) :=
 let result := interpret accepted in
 (* The native invocation already receives its exact business result through
    internal_result. This independent Continue packet acknowledges dispatch,
    including a refused fork; it is not a second public fork command. *)
 accept JNull (decision_world result)
   (decision_effects result ++ [ContinueScheduling]).
Definition packet {before : world} (accepted : plan before) (raw : json) : world * json :=
 DeferredCommit.packet (Some Continue) before (candidate accepted).
