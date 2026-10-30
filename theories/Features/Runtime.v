From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Scheduler TitleCommit DecisionComposition.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Work Board Worktree TaskGraph Remote Chatgpt Compaction TitleRuntime.
Definition or_else {A:Type} (first:option A) (next:unit->option A) := match first with Some value=>Some value | None=>next tt end.
Definition completion (execute:Scheduler.executor) (source:json) (value:world) :option (bool*bool*decision) :=
 or_else (Remote.completion execute source value) (fun _=>
 or_else (Worktree.completion source value) (fun _=>
 or_else (Board.completion source value) (fun _=>
 or_else (Chatgpt.completion source value) (fun _=>
 or_else (Compaction.completion source value) (fun _=>TitleRuntime.completion source value))))).
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

Definition guard_command (command:Selvedge.Generated.Commands.command) (_caller:option N) (value:world) :=
 match command with
 | Selvedge.Generated.Commands.Cmd_delete_project p=>if Board.project_used (Selvedge.Generated.Commands.delete_project_project_id p) value || Chatgpt.project_used (Selvedge.Generated.Commands.delete_project_project_id p) value
 then Some (reject "project_not_empty"%string "A project referenced by a board card or ChatGPT grant cannot be deleted"%string value) else None
 | _=>None end.
