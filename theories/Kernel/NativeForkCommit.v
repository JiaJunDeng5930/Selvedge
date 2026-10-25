From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec State Inputs Scheduler TaskScope
 CommandHandlers ForkCommit DeferredCommit.
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
Definition execute command context before :=
 ForkCommit.admit_workspace before (CommandHandlers.execute command context before).
Definition interpret {before : world} (accepted : plan before) :=
 let step := planned_step accepted in
 Scheduler.execute_checked_call execute
   (Scheduler.native_fork_owner step) (Scheduler.native_fork_tool step)
   (Scheduler.native_fork_invocation step) (Scheduler.native_fork_remaining step)
   (TaskScope.selected (planned_target accepted)) before.
Definition candidate {before : world} (accepted : plan before) :=
 let result := interpret accepted in
 Decision (decision_world result) (decision_reply result)
   (decision_effects result ++ [ContinueScheduling]).
Definition packet {before : world} (accepted : plan before) (raw : json) : world * json :=
 DeferredCommit.packet (Some Continue) raw before (candidate accepted).
