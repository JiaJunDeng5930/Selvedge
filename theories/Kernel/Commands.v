From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Arguments JsonSchema.
From Selvedge.Kernel Require Import WorkspaceBackend Pagination.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition req (name : string) (type : kind) := Field name type.
Definition opt (name : string) (type : kind) := Field name (KOptional type).
Definition task_identity := [req "task_id" KNatural].
Definition content_fields := [opt "message" KJson; opt "images" (KArray KJson)].
Definition creation_fields := [req "profile" KText; opt "reasoning" KText] ++
  content_fields ++ [opt "settings" KJson].
Definition card_metadata := [OmittableField "title" KText; OmittableField "description" KText;
  OmittableField "status" KText; OmittableField "priority" KText; OmittableField "assignee" KText;
  OmittableField "project" KText; OmittableField "labels" (KArray KText); OmittableField "attachments" (KArray KJson)].
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
  Command "fork" (task_identity ++ [req "child_count" KNatural; opt "messages" (KArray KJson); opt "settings" KJson; opt "settings_origin" (KEnum "parent" ["environment"])]);
  Command "open_side_conversation" (task_identity ++ content_fields);
  Command "return_side_conversation" task_identity;
  Command "compact" (task_identity ++ [opt "summary" KText]);
  Command "read" (task_identity ++ [opt "after" KNatural; opt "limit" KNatural]);
  Command "search_history" [req "query" KText; opt "project_id" KNatural; opt "work_id" KNatural; opt "after" KNatural; opt "limit" KNatural];
  Command "list" [];
  Command "describe" [];
  Command "create_project" [req "name" KText; req "workspace" KJson; opt "guidance" KJson; opt "create_worktree" KBool; opt "workspace_binding" KJson];
  Command "update_project" [req "project_id" KNatural; opt "name" KText; opt "workspace" KJson; opt "guidance" KJson; opt "create_worktree" KBool; opt "workspace_binding" KJson];
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
  Command "retry_worktree_archive" task_identity;
  Command "resolve_workspace" [opt "workspace" KJson; opt "project_id" KNatural]
].

Definition command_field_description (command field : string) :=
  if String.eqb field "profile" then "Key of a configured model profile." else
  if String.eqb field "reasoning" then "Reasoning effort override; omitted uses the selected profile's default." else
  if String.eqb field "task_id" && String.eqb command "cancel_operation" then
    "Task identifier; omitted to target the calling task." else
  if String.eqb field "task_id" then "Task identifier returned by a task command." else
  if String.eqb field "child_count" then "Number of child tasks to create, at least one and bounded by the configured fork limit." else
  if String.eqb command "fork" && String.eqb field "settings_origin" then
    "Base child execution settings on parent (default) or environment before applying settings overrides." else
  if String.eqb command "fork" && String.eqb field "messages" then
    "Omit initial input or supply exactly one content value per child." else
  if String.eqb field "workspace" then
    "Canonical absolute workspace roots, at most 32; primary_root must belong to roots and defaults to the first root." else
  if String.eqb field "guidance" then
    "Primary-workspace guidance snapshot containing workspace, path, revision and instructions." else
  if String.eqb field "create_worktree" then
    if String.eqb command "create_project" then
      "Create a Git worktree for new tasks by default; defaults to false." else
    if String.eqb command "update_project" then
      "Create a Git worktree for new tasks by default; omitted retains the current project default." else
      "Create a Git worktree for this task; omitted uses the selected project's default."
  else
  if String.eqb field "session_id" then "Stable upstream speech session identity." else
  if String.eqb field "item_id" then "Stable upstream speech item identity within the session; reuse it when replaying the same transcript." else
  if String.eqb field "delegation_id" then "Stable upstream delegation identity within the session; repeating it does not deliver the input again." else
  if String.eqb command "search_history" && String.eqb field "query" then
    "Literal keyword or phrase to search committed user and assistant messages; 1..240 Unicode scalar values after trimming." else
  if String.eqb command "search_history" && String.eqb field "project_id" then
    "Restrict results to this project." else
  if String.eqb command "search_history" && String.eqb field "work_id" then
    "Restrict results to this Work." else
  if String.eqb command "read" && String.eqb field "after" then
    "Zero-based offset into the task's retained message history; defaults to 0." else
  if String.eqb command "search_history" && String.eqb field "after" then
    "Zero-based offset into matching search results; defaults to 0." else
  if String.eqb command "read" && String.eqb field "limit" then
    "Maximum messages to return, from 1 to 100; defaults to 100." else
  if String.eqb command "search_history" && String.eqb field "limit" then
    "Maximum results to return, from 1 to 50; defaults to 20." else "".

Definition command_argument (command : string) (field : field_spec) :=
  let argument := Arguments.with_description
    (command_field_description command (field_name field)) (Arguments.from_field field) in
  if String.eqb command "fork" && String.eqb (field_name field) "child_count" then
    Arguments.with_bounds (1%N, JsonSchema.maximum_natural) argument else
  if String.eqb command "read" && String.eqb (field_name field) "limit" then
    Arguments.with_bounds (1%N, Pagination.history_limit) argument else
  if String.eqb command "search_history" && String.eqb (field_name field) "limit" then
    Arguments.with_bounds (1%N, Pagination.search_limit) argument else argument.

Definition command_arguments (specification : command_spec) :=
  map (command_argument (command_name specification))
    (Field "op" KText :: filter (fun field => negb (String.eqb (field_name field) "workspace_binding")) (command_fields specification)).

(* Host workspace observation and native remote admission share this schema-level judgment. *)
Definition graph_node_creates_root_task (node : json) :=
 match node with
 | JObject fields => match lookup "task_id" fields with None => true | Some _ => false end
 | _ => false end.
Definition root_task_creation (command : json) := match field "op" command with
 | Some (JString operation) =>
   existsb (fun spec => String.eqb operation (command_name spec)) command_specs &&
   (existsb (String.eqb operation) ["create";"create_idle";"create_work_task";"create_worktree_task";"create_workspace_task"] ||
    ((String.eqb operation "create_task_graph" || String.eqb operation "update_task_graph") &&
     match field "nodes" command with Some (JArray nodes) => existsb graph_node_creates_root_task nodes | _ => false end))
 | _ => false end.

(** Descriptions accompany the shared command declarations without repeating
    their argument schemas. *)
Definition command_descriptions : list (string * string) := [
  ("configure_task_execution", "Change a quiescent task's current execution settings while preserving its creation snapshot.");
  ("create", "Start an agent with a frozen model and tool contract.");
  ("create_idle", "Create a task with frozen execution settings without submitting an initial input.");
  ("send", "Commit or queue a user message; reactivate a stopped task.");
  ("steer", "Replace current model work with immediate user input without cancelling independent operations or discarding queued follow-ups. Frozen tasks remain frozen.");
  ("cancel_operation", "Cancel one live operation. Other work continues; previous side effects cannot be undone.");
  ("freeze", "Suspend dispatch without discarding accepted results.");
  ("unfreeze", "Resume a frozen task.");
  ("stop", "Settle accepted tools without requesting another model reply.");
  ("interrupt", "Cancel current work without archiving. Retain queued messages; record unknown outcomes for already-dispatched tools. A new message resumes the task.");
  ("archive", "Permanently archive a task and cancel external work.");
  ("fork", "Fork an idle task, subject to every ancestor's descendant limit.");
  ("open_side_conversation", "Open a side conversation from the task's committed history while its work continues. An omitted message creates an idle side task.");
  ("return_side_conversation", "Append only this side conversation's new content to its parent, excluding side instructions and parent lifecycle updates. Current work continues.");
  ("compact", "Checkpoint an idle task without deleting original history. Without summary, request a model summary (active tasks only). A supplied bounded summary also works on stopped or frozen tasks, without calling a model.");
  ("read", "Read a bounded history page without advancing the task.");
  ("search_history", "Search committed conversation text across tasks, optionally restricted to a project or Work. Read an original message with read after=message_index (0-based).");
  ("list", "Read task summaries and the currently available model profiles and tools.");
  ("describe", "Read this executable command vocabulary and the effect-boundary limits.");
  ("create_project", "Create an organizational project with default workspace roots; existing tasks never follow later default changes.");
  ("update_project", "Change the project's name or workspace defaults without rewriting task contracts.");
  ("delete_project", "Delete an empty project. A project referenced by any task cannot be deleted.");
  ("list_projects", "Read project summaries without advancing tasks.");
  ("read_project", "Read a project's workspace defaults and frozen root guidance.");
  ("review_approval", "Approve exactly one pending human-reviewed command, or deny it. A grant cannot change the command, task settings, or any later operation.");
  ("record_speech_transcript", "Record a final speech transcript without invoking or scheduling the task model.");
  ("accept_speech_delegation", "Accept a voice work delegation through ordinary task input, retaining its receipt in the same decision.");
  ("create_card", "Capture planned work without starting a task; assisted creation requests a separate bounded title/description suggestion.");
  ("update_card", "Update only named card fields, guarded by the observed card revision. Execution inputs remain frozen after linking a task.");
  ("move_card", "Move a revision-bound card before another card, or to the end when before_card is empty. Preserve the relative order of other cards.");
  ("archive_card", "Archive a card and interrupt its active execution. Its stage and linked task history are retained.");
  ("restore_card", "Restore an archived card to its retained stage without replaying its execution.");
  ("delete_card", "Delete an idle card, not its linked task or conversation.");
  ("run_card", "Start the assigned agent exactly once, freezing the current project and agent execution settings.");
  ("link_card", "Attach an existing unlinked conversation to a card without creating or replaying a task.");
  ("regenerate_card_title", "Request a revision-correlated title suggestion; retain the description, assignments and task link.");
  ("pin_card", "Pin or unpin an idle card. Pinned cards precede other cards in both the board and automatic dispatch queue.");
  ("board_settings", "Configure automatic dispatch and the independent ordinary profile used for drafting.");
  ("save_board_agent", "Create or edit a reusable board role; blank agent means create. Existing task contracts are never rewritten.");
  ("delete_board_agent", "Delete an unused board role without deleting its endpoint configuration.");
  ("list_cards", "Observe the card registry, automatic-dispatch setting and independent drafting profile.");
  ("read_card", "Observe one card and its current execution capabilities.");
  ("list_board_agents", "Observe reusable board roles and their current configured endpoints.");
  ("configure_chatgpt_connections", "Replace local ChatGPT connection grants; administrative access only.");
  ("chatgpt_exec", "Commit one project-scoped Bash operation. Retained request IDs deduplicate retries.");
  ("chatgpt_cancel", "Interrupt one connection-owned operation; physical changes are not undone.");
  ("chatgpt_forget", "Delete a settled receipt and end its request-ID deduplication retention.");
  ("chatgpt_projects", "List only projects granted to this connection.");
  ("chatgpt_project", "Read an authorized project and its root guidance.");
  ("chatgpt_operation", "Read one operation owned by this connection and project.");
  ("chatgpt_operations", "List bounded operation summaries, without their output bodies.");
  ("remote_enable", "Enable locally granted remote controllers; administrative access only.");
  ("remote_disable", "Disable remote control immediately without cancelling local tasks; administrative access only.");
  ("remote_grant", "Grant or replace one remote controller's permissions and issue a fresh grant generation; administrative access only.");
  ("remote_revoke", "Revoke one remote controller and remove its retained command receipts; administrative access only.");
  ("remote_status", "Read local remote-control status and granted controllers; administrative access only.");
  ("create_task_graph", "Create Tasks and install their output handlers atomically before scheduling them. Optional work_id scopes the graph: existing Tasks must already belong to that Work and new Tasks join it.");
  ("update_task_graph", "Replace a graph declaration atomically; retained Task references keep their existing settings and history.");
  ("delete_task_graph", "Remove a graph and its future output handlers without archiving its Tasks.");
  ("list_task_graphs", "Observe installed Task graphs, resolved Task references and latest delivery receipts.");
  ("read_task_graph", "Observe one installed Task graph, its rules and latest delivery receipts.");
  ("read_title_settings", "Read independent Task board and Agent conversation title instructions.");
  ("configure_title_settings", "Save independent title instructions at their current revision; existing names and pending requests are preserved.");
  ("create_work", "Create a Work independent of Projects; an omitted name becomes Work #id.");
  ("rename_work", "Rename a Work while preserving its Tasks and Task graphs.");
  ("create_work_task", "Create a root Task and record its immutable Work ownership atomically; optionally create a managed worktree.");
  ("list_works", "Observe Works with their derived Task IDs and associated Task graph IDs.");
  ("read_work", "Observe one Work with its derived Task IDs and associated Task graph IDs.");
  ("read_work_ui", "Read the persistent shared UI source and revision of this calling Task's Work. The source uses the same selvedge-ui DSL as conversation interfaces, without a Markdown fence. No Work or Task identifier is accepted.");
  ("apply_work_ui_patch", "Edit this Task's Work UI atomically using the revision from read_work_ui. Patch exactly one virtual file work-ui.dsl using *** Begin Patch, *** Add File: work-ui.dsl (for empty source), *** Update File: work-ui.dsl with @@ and exact context/-/+ lines, or *** Delete File: work-ui.dsl (clear), then *** End Patch. Example initial patch:
*** Begin Patch
*** Add File: work-ui.dsl
+<ui id=""work""><metric id=""progress"" label=""Progress"" value={0} /></ui>
*** End Patch. Source is raw selvedge-ui DSL without fences. Concurrent edits reject stale revisions; read again before revising the patch.");
  ("create_workspace_task", "Create a task after preparing a local worktree or a cloud environment.");
  ("create_worktree_task", "Create a task in a managed Git worktree before starting its execution.");
  ("resolve_workspace", "Resolve the selected workspace environment before observing its directories.");
  ("list_worktrees", "List managed task worktrees and their current operation state.");
  ("read_worktree", "Read the managed worktree associated with one task.");
  ("retry_worktree_archive", "Retry archiving a task worktree after an external archive failure.")
].

Definition command_description (name : string) : option string :=
  option_map snd (find (fun entry => String.eqb name (fst entry)) command_descriptions).
