From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Kernel Require Import WorkspaceBackend.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition req (name : string) (type : kind) := Field name type.
Definition opt (name : string) (type : kind) := Field name (KOptional type).
Definition task_identity := [req "task_id" KNatural].
Definition content_fields := [opt "message" KJson; opt "images" (KArray KJson)].
Definition creation_fields := [req "profile" KText; opt "reasoning" KText] ++
  content_fields ++ [opt "settings" KJson].
Definition card_metadata := [opt "title" KText; opt "description" KText;
  opt "status" KText; opt "priority" KText; opt "assignee" KText;
  opt "project" KText; opt "labels" (KArray KText); opt "attachments" (KArray KJson)].
Definition card_identity := [req "card_id" KNatural; req "revision" KNatural; opt "observed_at" KText].
Definition graph_fields := [req "name" KText; req "nodes" (KArray KJson); req "rules" (KArray KJson)].
Definition connection_project := [req "connection_id" KNatural; req "project_id" KNatural].
Definition connection_operation := connection_project ++ [req "operation_id" KNatural].

(** These declarations own public command names and fields. The schema
    interpreter and MetaRocq derivation consume this same list. *)
Definition command_specs : list command_spec := [
  Command "configure_task_execution" (task_identity ++ [opt "profile" KText; opt "reasoning" KText; opt "sandbox" KJson; opt "approval" KJson]);
  Command "create" creation_fields;
  Command "create_idle" ([req "profile" KText; opt "reasoning" KText; opt "settings" KJson; opt "work_id" KNatural; opt "create_worktree" KBool]);
  Command "send" (task_identity ++ content_fields);
  Command "steer" (task_identity ++ content_fields);
  Command "cancel_operation" (task_identity ++ [req "operation_id" KNatural]);
  Command "freeze" task_identity;
  Command "unfreeze" task_identity;
  Command "stop" task_identity;
  Command "interrupt" task_identity;
  Command "archive" task_identity;
  Command "fork" (task_identity ++ [req "child_count" KNatural; opt "messages" (KArray KJson); opt "settings" KJson]);
  Command "open_side_conversation" (task_identity ++ content_fields);
  Command "return_side_conversation" task_identity;
  Command "compact" (task_identity ++ [opt "summary" KText]);
  Command "read" (task_identity ++ [opt "after" KNatural; opt "limit" KNatural]);
  Command "search_history" [req "query" KText; opt "project_id" KNatural; opt "work_id" KNatural; opt "after" KNatural; opt "limit" KNatural];
  Command "list" [];
  Command "describe" [];
  Command "create_project" [req "name" KText; req "workspace" KJson; opt "guidance" KJson; opt "create_worktree" KBool];
  Command "update_project" [req "project_id" KNatural; opt "name" KText; opt "workspace" KJson; opt "guidance" KJson; opt "create_worktree" KBool];
  Command "delete_project" [req "project_id" KNatural];
  Command "list_projects" [];
  Command "read_project" [req "project_id" KNatural];
  Command "review_approval" (task_identity ++ [req "operation_id" KNatural; req "decision" (KEnum "allow" ["deny"]); opt "reason" KText]);
  Command "record_speech_transcript" (task_identity ++ [req "session_id" KText; req "item_id" KText; req "speaker" (KEnum "user" ["assistant"]); req "completion" (KEnum "completed" ["interrupted"]); req "text" KText]);
  Command "accept_speech_delegation" (task_identity ++ [req "session_id" KText; req "delegation_id" KText; req "message" KText; req "mode" (KEnum "send" ["steer"])]);
  Command "create_card" (opt "observed_at" KText :: card_metadata ++ [opt "assisted" KBool; opt "draft_profile" KText]);
  Command "update_card" (card_identity ++ card_metadata);
  Command "move_card" (card_identity ++ [opt "status" KText; opt "before_card" KText]);
  Command "archive_card" card_identity;
  Command "restore_card" card_identity;
  Command "delete_card" card_identity;
  Command "run_card" card_identity;
  Command "link_card" (card_identity ++ [opt "task_id" KNatural]);
  Command "regenerate_card_title" (card_identity ++ [opt "draft_profile" KText]);
  Command "pin_card" (card_identity ++ [opt "pinned" KBool]);
  Command "board_settings" [req "automatic" KBool; req "draft_profile" KText];
  Command "save_board_agent" [req "agent" KText; req "revision" KNatural; req "name" KText; req "profile" KText; req "reasoning" KText; req "instructions" KText; opt "settings" KJson; req "concurrency" KNatural];
  Command "delete_board_agent" [req "agent_id" KNatural; req "revision" KNatural];
  Command "list_cards" [];
  Command "read_card" [req "card_id" KNatural];
  Command "list_board_agents" [];
  Command "configure_chatgpt_connections" [req "connections" (KArray KJson)];
  Command "chatgpt_exec" (connection_project ++ [req "request_id" KText; req "arguments" KJson]);
  Command "chatgpt_cancel" connection_operation;
  Command "chatgpt_forget" connection_operation;
  Command "chatgpt_projects" [req "connection_id" KNatural];
  Command "chatgpt_project" connection_project;
  Command "chatgpt_operation" connection_operation;
  Command "chatgpt_operations" connection_project;
  Command "remote_enable" [];
  Command "remote_disable" [];
  Command "remote_grant" [req "controller_id" KText; req "permissions" KJson];
  Command "remote_revoke" [req "controller_id" KText];
  Command "remote_status" [];
  Command "create_task_graph" (opt "work_id" KNatural :: graph_fields);
  Command "update_task_graph" (req "graph_id" KNatural :: graph_fields);
  Command "delete_task_graph" [req "graph_id" KNatural];
  Command "list_task_graphs" [];
  Command "read_task_graph" [req "graph_id" KNatural];
  Command "read_title_settings" [];
  Command "configure_title_settings" [req "revision" KNatural; req "task_prompt" KText; req "agent_prompt" KText];
  Command "create_work" [opt "name" KText];
  Command "rename_work" [req "work_id" KNatural; req "name" KText];
  Command "create_work_task" (req "work_id" KNatural :: creation_fields ++ [opt "create_worktree" KBool]);
  Command "list_works" [];
  Command "read_work" [req "work_id" KNatural];
  Command "read_work_ui" [];
  Command "apply_work_ui_patch" [req "patch" KText; req "revision" KNatural];
  Command "create_worktree_task" creation_fields;
  Command "create_workspace_task" (req "backend" WorkspaceBackend.declaration :: creation_fields ++ [opt "work_id" KNatural]);
  Command "list_worktrees" [];
  Command "read_worktree" task_identity;
  Command "retry_worktree_archive" task_identity
].
