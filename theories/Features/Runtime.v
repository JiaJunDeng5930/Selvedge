From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Scheduler.
From Selvedge.Generated Require Import Commands.
From Selvedge.Features Require Import Work Board Worktree TaskGraph Remote Chatgpt Compaction TitleRuntime.
Definition or_else {A:Type} (first:option A) (next:unit->option A) := match first with Some value=>Some value | None=>next tt end.
Definition query (command:Selvedge.Generated.Commands.command) (caller:option N) (value:world) :option json :=
 or_else (Work.query command caller value) (fun _=>
 or_else (Board.query command caller value) (fun _=>
 or_else (TaskGraph.query command caller value) (fun _=>
 or_else (Worktree.query command caller value) (fun _=>
 or_else (Remote.query command caller value) (fun _=>
 or_else (Chatgpt.query command caller value) (fun _=>TitleRuntime.query command caller value)))))).
Definition command (command:Selvedge.Generated.Commands.command) (caller:option N) (value:world) :option decision :=
 or_else (Work.command command caller value) (fun _=>
 or_else (Board.command command caller value) (fun _=>
 or_else (TaskGraph.command command caller value) (fun _=>
 or_else (Worktree.command command caller value) (fun _=>
 or_else (Remote.command command caller value) (fun _=>
 or_else (Chatgpt.command command caller value) (fun _=>
 or_else (Compaction.command command caller value) (fun _=>TitleRuntime.command command caller value))))))).
Definition completion (execute:Scheduler.executor) (source:json) (value:world) :option (bool*bool*decision) :=
 or_else (Remote.completion execute source value) (fun _=>
 or_else (Worktree.completion source value) (fun _=>
 or_else (Board.completion source value) (fun _=>
 or_else (Chatgpt.completion source value) (fun _=>
 or_else (Compaction.completion source value) (fun _=>TitleRuntime.completion source value))))).
Definition after_transition (before:world) (result:decision) :decision :=
 Compaction.after_transition before (TitleRuntime.after_transition before
 (Board.after_transition before (TaskGraph.after_transition before (Worktree.after_transition before result)))).
Definition recover (value:world) :world :=
 TitleRuntime.recover (Compaction.recover (Chatgpt.recover (Board.recover (Worktree.recover value)))).
Definition schedules (command:Selvedge.Generated.Commands.command) :bool := match command with
 | Selvedge.Generated.Commands.Cmd_configure_title_settings _ | Selvedge.Generated.Commands.Cmd_read_title_settings _
 | Selvedge.Generated.Commands.Cmd_remote_enable _ | Selvedge.Generated.Commands.Cmd_remote_disable _ | Selvedge.Generated.Commands.Cmd_remote_grant _
 | Selvedge.Generated.Commands.Cmd_remote_revoke _ | Selvedge.Generated.Commands.Cmd_remote_status _ => false | _=>true end.
Definition can_schedule_task := Compaction.can_schedule_task.
Definition finish (result:decision) := Selvedge.Features.Compaction.attach (Board.finish result).
Definition model_context_limit (id ticket:N) (value:world) :decision := Compaction.model_context_limit id ticket value.

Definition guard_command (command:Selvedge.Generated.Commands.command) (caller:option N) (value:world) :=
 or_else (Worktree.guard_command command caller value) (fun _=>match command with
 | Selvedge.Generated.Commands.Cmd_delete_project p=>if Board.project_used (Selvedge.Generated.Commands.delete_project_project_id p) value || Chatgpt.project_used (Selvedge.Generated.Commands.delete_project_project_id p) value
 then Some (reject "project_in_use"%string "A project referenced by a board card or ChatGPT grant cannot be deleted"%string value) else None
 | _=>None end).
Definition guard_result := Worktree.guard_result.
