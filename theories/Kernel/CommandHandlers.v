From Stdlib Require Import String List NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Generated Require Import Commands.
From Selvedge.Kernel Require Import Domain State Queries CommandExecution Tasks.
From Selvedge.Features Require Import Work Board Worktree TaskGraph Remote Chatgpt Compaction TitleRuntime WorkspaceBinding.
Module G := Selvedge.Generated.Commands.
Module Declarations := Selvedge.Kernel.Commands.
Open Scope string_scope.
Inductive interpretation :=
 | Observation (run : option N -> world -> json)
 | Mutation (run : option Tasks.native_call -> world -> decision).
Definition handlers : G.handler_table interpretation := {|
 G.handle_configure_task_execution := fun payload => Mutation (fun context value => Selvedge.Features.Worktree.configure_task_execution payload value);
 G.handle_create := fun payload => Mutation (fun context value => Selvedge.Features.Worktree.handle_create payload (option_map Tasks.native_owner context) value);
 G.handle_create_idle := fun payload => Mutation (fun context value => Selvedge.Features.Worktree.handle_create_idle payload (option_map Tasks.native_owner context) value);
 G.handle_send := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_send payload context value);
 G.handle_steer := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_steer payload context value);
 G.handle_cancel_operation := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_cancel_operation payload context value);
 G.handle_freeze := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_freeze payload context value);
 G.handle_unfreeze := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_unfreeze payload context value);
 G.handle_stop := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_stop payload context value);
 G.handle_interrupt := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_interrupt payload context value);
 G.handle_archive := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_archive payload context value);
 G.handle_fork := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_fork payload context value);
 G.handle_open_side_conversation := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_open_side_conversation payload context value);
 G.handle_return_side_conversation := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_return_side_conversation payload context value);
 G.handle_compact := fun payload => Mutation (fun context value => Selvedge.Features.Compaction.handle_compact payload (option_map Tasks.native_owner context) value);
 G.handle_read := fun payload => Observation (fun caller value => Selvedge.Kernel.Queries.handle_read payload caller value);
 G.handle_search_history := fun payload => Observation (fun caller value => Selvedge.Kernel.Queries.handle_search_history payload caller value);
 G.handle_list := fun payload => Observation (fun caller value => Selvedge.Kernel.Queries.handle_list payload caller value);
 G.handle_describe := fun payload => Observation (fun caller value => Selvedge.Kernel.Queries.handle_describe payload caller value);
 G.handle_create_project := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_create_project payload context value);
 G.handle_update_project := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_update_project payload context value);
 G.handle_delete_project := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_delete_project payload context value);
 G.handle_list_projects := fun payload => Observation (fun caller value => Selvedge.Kernel.Queries.handle_list_projects payload caller value);
 G.handle_read_project := fun payload => Observation (fun caller value => Selvedge.Kernel.Queries.handle_read_project payload caller value);
 G.handle_review_approval := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_review_approval payload context value);
 G.handle_record_speech_transcript := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_record_speech_transcript payload context value);
 G.handle_accept_speech_delegation := fun payload => Mutation (fun context value => Selvedge.Kernel.CommandExecution.handle_accept_speech_delegation payload context value);
 G.handle_create_card := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_create_card payload (option_map Tasks.native_owner context) value);
 G.handle_update_card := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_update_card payload (option_map Tasks.native_owner context) value);
 G.handle_move_card := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_move_card payload (option_map Tasks.native_owner context) value);
 G.handle_archive_card := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_archive_card payload (option_map Tasks.native_owner context) value);
 G.handle_restore_card := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_restore_card payload (option_map Tasks.native_owner context) value);
 G.handle_delete_card := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_delete_card payload (option_map Tasks.native_owner context) value);
 G.handle_run_card := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_run_card payload (option_map Tasks.native_owner context) value);
 G.handle_link_card := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_link_card payload (option_map Tasks.native_owner context) value);
 G.handle_regenerate_card_title := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_regenerate_card_title payload (option_map Tasks.native_owner context) value);
 G.handle_pin_card := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_pin_card payload (option_map Tasks.native_owner context) value);
 G.handle_board_settings := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_board_settings payload (option_map Tasks.native_owner context) value);
 G.handle_save_board_agent := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_save_board_agent payload (option_map Tasks.native_owner context) value);
 G.handle_delete_board_agent := fun payload => Mutation (fun context value => Selvedge.Features.Board.handle_delete_board_agent payload (option_map Tasks.native_owner context) value);
 G.handle_list_cards := fun payload => Observation (fun caller value => Selvedge.Features.Board.handle_list_cards payload caller value);
 G.handle_read_card := fun payload => Observation (fun caller value => Selvedge.Features.Board.handle_read_card payload caller value);
 G.handle_list_board_agents := fun payload => Observation (fun caller value => Selvedge.Features.Board.handle_list_board_agents payload caller value);
 G.handle_configure_chatgpt_connections := fun payload => Mutation (fun context value => Selvedge.Features.Chatgpt.handle_configure_chatgpt_connections payload (option_map Tasks.native_owner context) value);
 G.handle_chatgpt_exec := fun payload => Mutation (fun context value => Selvedge.Features.Chatgpt.handle_chatgpt_exec payload (option_map Tasks.native_owner context) value);
 G.handle_chatgpt_cancel := fun payload => Mutation (fun context value => Selvedge.Features.Chatgpt.handle_chatgpt_cancel payload (option_map Tasks.native_owner context) value);
 G.handle_chatgpt_forget := fun payload => Mutation (fun context value => Selvedge.Features.Chatgpt.handle_chatgpt_forget payload (option_map Tasks.native_owner context) value);
 G.handle_chatgpt_projects := fun payload => Observation (fun caller value => Selvedge.Features.Chatgpt.handle_chatgpt_projects payload caller value);
 G.handle_chatgpt_project := fun payload => Observation (fun caller value => Selvedge.Features.Chatgpt.handle_chatgpt_project payload caller value);
 G.handle_chatgpt_operation := fun payload => Observation (fun caller value => Selvedge.Features.Chatgpt.handle_chatgpt_operation payload caller value);
 G.handle_chatgpt_operations := fun payload => Observation (fun caller value => Selvedge.Features.Chatgpt.handle_chatgpt_operations payload caller value);
 G.handle_remote_enable := fun payload => Mutation (fun context value => Selvedge.Features.Remote.handle_remote_enable payload (option_map Tasks.native_owner context) value);
 G.handle_remote_disable := fun payload => Mutation (fun context value => Selvedge.Features.Remote.handle_remote_disable payload (option_map Tasks.native_owner context) value);
 G.handle_remote_grant := fun payload => Mutation (fun context value => Selvedge.Features.Remote.handle_remote_grant payload (option_map Tasks.native_owner context) value);
 G.handle_remote_revoke := fun payload => Mutation (fun context value => Selvedge.Features.Remote.handle_remote_revoke payload (option_map Tasks.native_owner context) value);
 G.handle_remote_status := fun payload => Observation (fun caller value => Selvedge.Features.Remote.handle_remote_status payload caller value);
 G.handle_create_task_graph := fun payload => Mutation (fun context value => Selvedge.Features.TaskGraph.handle_create_task_graph payload (option_map Tasks.native_owner context) value);
 G.handle_update_task_graph := fun payload => Mutation (fun context value => Selvedge.Features.TaskGraph.handle_update_task_graph payload (option_map Tasks.native_owner context) value);
 G.handle_delete_task_graph := fun payload => Mutation (fun context value => Selvedge.Features.TaskGraph.handle_delete_task_graph payload (option_map Tasks.native_owner context) value);
 G.handle_list_task_graphs := fun payload => Observation (fun caller value => Selvedge.Features.TaskGraph.handle_list_task_graphs payload caller value);
 G.handle_read_task_graph := fun payload => Observation (fun caller value => Selvedge.Features.TaskGraph.handle_read_task_graph payload caller value);
 G.handle_read_title_settings := fun payload => Observation (fun caller value => Selvedge.Features.TitleRuntime.handle_read_title_settings payload caller value);
 G.handle_configure_title_settings := fun payload => Mutation (fun context value => Selvedge.Features.TitleRuntime.handle_configure_title_settings payload (option_map Tasks.native_owner context) value);
 G.handle_create_work := fun payload => Mutation (fun context value => Selvedge.Features.Work.handle_create_work payload (option_map Tasks.native_owner context) value);
 G.handle_rename_work := fun payload => Mutation (fun context value => Selvedge.Features.Work.handle_rename_work payload (option_map Tasks.native_owner context) value);
 G.handle_create_work_task := fun payload => Mutation (fun context value => Selvedge.Features.Worktree.handle_create_work_task payload (option_map Tasks.native_owner context) value);
 G.handle_list_works := fun payload => Observation (fun caller value => Selvedge.Features.Work.handle_list_works payload caller value);
 G.handle_read_work := fun payload => Observation (fun caller value => Selvedge.Features.Work.handle_read_work payload caller value);
 G.handle_read_work_ui := fun payload => Observation (fun caller value => Selvedge.Features.Work.handle_read_work_ui payload caller value);
 G.handle_apply_work_ui_patch := fun payload => Mutation (fun context value => Selvedge.Features.Work.handle_apply_work_ui_patch payload (option_map Tasks.native_owner context) value);
 G.handle_create_worktree_task := fun payload => Mutation (fun context value => Selvedge.Features.Worktree.handle_create_worktree_task payload (option_map Tasks.native_owner context) value);
 G.handle_create_workspace_task := fun payload => Mutation (fun context value => Selvedge.Features.Worktree.handle_create_workspace_task payload (option_map Tasks.native_owner context) value);
 G.handle_list_worktrees := fun payload => Observation (fun caller value => Selvedge.Features.Worktree.handle_list_worktrees payload caller value);
 G.handle_read_worktree := fun payload => Observation (fun caller value => Selvedge.Features.Worktree.handle_read_worktree payload caller value);
 G.handle_retry_worktree_archive := fun payload => Mutation (fun context value => Selvedge.Features.Worktree.handle_retry_worktree_archive payload (option_map Tasks.native_owner context) value);
 G.handle_resolve_workspace := fun payload => Observation (fun caller value => Selvedge.Features.Worktree.handle_resolve_workspace payload caller value)
|}.
Definition task_origin {A : Type} (context : option A) := match context with Some _ => true | None => false end.
Definition origin_failure := State.failure "access_denied" "This command is not available to task-originated calls".
(* Every real interpretation is selected through the same origin policy that
   NativeTools uses to construct the advertised task capability surface. *)
Definition interpret (command : G.command) (from_task : bool) :=
 if Declarations.origin_allowed from_task (Selvedge.Foundation.Schema.command_name (G.declared_command command))
 then G.dispatch handlers command
 else Observation (fun _ _ => origin_failure).
Definition query (command : G.command) (caller : option N) (value : world) :=
 match interpret command (task_origin caller) with
 | Observation run => Some (run caller value)
 | Mutation _ => None end.
Definition execute (command : G.command) (context : option Tasks.native_call) (value : world) :=
 match interpret command (task_origin context) with
 | Observation run => Decision value (run (option_map Tasks.native_owner context) value) nil
 | Mutation run => run context value end.
