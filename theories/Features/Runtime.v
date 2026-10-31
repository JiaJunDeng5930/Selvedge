From Selvedge.Programming Require InputRoute.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Scheduler TitleCommit.
From Selvedge.Programming Require Import DecisionComposition.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Work Board Worktree TaskGraph Remote Chatgpt Compaction TitleRuntime.
Definition completion_inputs (execute : Scheduler.executor) :=
 (Remote.completion_inputs execute ++ Worktree.completion_inputs ++ Board.completion_inputs ++
  Chatgpt.completion_inputs ++ Compaction.completion_inputs ++ TitleRuntime.completion_inputs)%list.
Definition after_transition (before:world) (result:decision) :decision :=
 DecisionComposition.run
 (DecisionComposition.and_then (Worktree.after_transition before)
 (DecisionComposition.and_then (TaskGraph.after_transition before)
 (DecisionComposition.and_then (Board.after_transition before) (Compaction.after_transition before)))) result.
Definition recover (value:world) :world :=
 TitleRuntime.recover (Compaction.recover (Chatgpt.recover (Board.recover (Worktree.recover value)))).
Definition reconfigure := Compaction.reconfigure.
Definition schedules (command:Selvedge.Generated.Commands.command) :bool := match command with
 | Selvedge.Generated.Commands.Cmd_configure_title_settings _ | Selvedge.Generated.Commands.Cmd_read_title_settings _
 | Selvedge.Generated.Commands.Cmd_remote_enable _ | Selvedge.Generated.Commands.Cmd_remote_disable _ | Selvedge.Generated.Commands.Cmd_remote_grant _
 | Selvedge.Generated.Commands.Cmd_remote_revoke _ | Selvedge.Generated.Commands.Cmd_remote_status _ => false | _=>true end.
Definition can_schedule_task (id:N) (value:world) :=
 Worktree.execution_ready id value && Compaction.can_schedule_task id value.
Definition finalization := DecisionComposition.compose (DecisionComposition.maintain Board.finish)
 (DecisionComposition.compose Selvedge.Features.Compaction.attach_context TitleCommit.enqueue_title).
Definition finish := DecisionComposition.transform finalization.
