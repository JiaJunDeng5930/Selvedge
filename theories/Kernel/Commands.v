From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Arguments JsonSchema.
From Selvedge.Kernel Require Import WorkspaceBackend Pagination TaskConstraints.
From Selvedge.Kernel Require Compaction.
From Selvedge.Kernel Require Export CommandArguments.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition task_identity := [u32 (req "task_id" KNatural)].
Definition content_fields := [typed (content_declaration) (opt "message" KJson); typed (images_declaration) (opt "images" (KArray KJson))].
Definition creation_fields := [req "profile" KText; opt "reasoning" KText] ++
  content_fields ++ [staged settings_declaration (opt "settings" KJson)].
Definition card_metadata := [opt "title" KText; opt "description" KText;
  typed board_status (opt "status" KText); typed board_priority (opt "priority" KText); typed board_assignee (opt "assignee" KText);
  typed board_project (opt "project" KText); opt "labels" (KArray KText); staged attachments_declaration (opt "attachments" (KArray KJson))].
Definition card_identity := [u32 (req "card_id" KNatural); u32 (req "revision" KNatural); typed board_clock (opt "observed_at" KText)].
Definition graph_fields := [typed TaskGraphDeclarations.identifier (req "name" KText); staged graph_nodes_declaration (req "nodes" (KArray KJson)); typed graph_rules_declaration (req "rules" (KArray KJson))].
Definition connection_project := [u32 (req "connection_id" KNatural); u32 (req "project_id" KNatural)].
Definition connection_operation := connection_project ++ [u32 (req "operation_id" KNatural)].

(** These declarations own public command names and fields. The schema
    interpreter and MetaRocq derivation consume this same list. *)
Inductive command_owner :=
 KernelQuery | WorkQuery | BoardQuery | TaskGraphQuery | WorktreeQuery | RemoteQuery | ChatgptQuery | TitleQuery | WorkChange | BoardChange | TaskGraphChange | WorktreeChange | RemoteChange | ChatgptChange | CompactionChange | TitleChange | KernelChange.
Definition owner_name (owner : command_owner) := match owner with
 | KernelQuery => "KernelQuery"
 | WorkQuery => "WorkQuery"
 | BoardQuery => "BoardQuery"
 | TaskGraphQuery => "TaskGraphQuery"
 | WorktreeQuery => "WorktreeQuery"
 | RemoteQuery => "RemoteQuery"
 | ChatgptQuery => "ChatgptQuery"
 | TitleQuery => "TitleQuery"
 | WorkChange => "WorkChange"
 | BoardChange => "BoardChange"
 | TaskGraphChange => "TaskGraphChange"
 | WorktreeChange => "WorktreeChange"
 | RemoteChange => "RemoteChange"
 | ChatgptChange => "ChatgptChange"
 | CompactionChange => "CompactionChange"
 | TitleChange => "TitleChange"
 | KernelChange => "KernelChange"
 end.
(** Task exposure belongs to the command declaration. It controls both the
    resident native catalog and the final dispatcher. External commands retain
    their existing owner/remote/connection authentication and grant checks. *)
Inductive task_exposure := TaskAllowed | TaskExcluded.
Record command_declaration := DeclareCommand {
 declared_owner : command_owner;
 declared_task_exposure : task_exposure;
 declared_wire : wire_command
}.
Definition declared_schema (declaration : command_declaration) := command_shape (declared_wire declaration).
Definition command_declarations : list command_declaration := [
  DeclareCommand WorktreeChange TaskExcluded (WireCommand "configure_task_execution" (task_identity ++ [opt "profile" KText; opt "reasoning" KText; typed (sandbox_patch_declaration) (opt "sandbox" KJson); typed (approval_declaration) (opt "approval" KJson)]));
  DeclareCommand WorktreeChange TaskAllowed (WireCommand "create" creation_fields);
  DeclareCommand WorktreeChange TaskExcluded (WireCommand "create_idle" ([req "profile" KText; opt "reasoning" KText; staged settings_declaration (opt "settings" KJson); u32 (opt "work_id" KNatural); opt "create_worktree" KBool]));
  DeclareCommand KernelChange TaskAllowed (WireCommand "send" (task_identity ++ content_fields));
  DeclareCommand KernelChange TaskExcluded (WireCommand "steer" (task_identity ++ content_fields));
  DeclareCommand KernelChange TaskAllowed (WireCommand "cancel_operation" (task_identity ++ [u32 (req "operation_id" KNatural)]));
  DeclareCommand KernelChange TaskExcluded (WireCommand "freeze" task_identity);
  DeclareCommand KernelChange TaskExcluded (WireCommand "unfreeze" task_identity);
  DeclareCommand KernelChange TaskExcluded (WireCommand "stop" task_identity);
  DeclareCommand KernelChange TaskExcluded (WireCommand "interrupt" task_identity);
  DeclareCommand KernelChange TaskAllowed (WireCommand "archive" task_identity);
  DeclareCommand KernelChange TaskAllowed (WireCommand "fork" (task_identity ++ [typed TaskConstraints.fork_count_declaration (req "child_count" KNatural); typed (D.Array content_declaration) (opt "messages" (KArray KJson)); staged settings_declaration (opt "settings" KJson); nullable "settings_origin" (KEnum "parent" ["environment"])]));
  DeclareCommand KernelChange TaskExcluded (WireCommand "open_side_conversation" (task_identity ++ content_fields));
  DeclareCommand KernelChange TaskExcluded (WireCommand "return_side_conversation" task_identity);
  DeclareCommand CompactionChange TaskExcluded (WireCommand "compact" (task_identity ++ [typed Compaction.summary_declaration (opt "summary" KText)]));
  DeclareCommand KernelQuery TaskAllowed (WireCommand "read" (task_identity ++ [u32 (opt "after" KNatural); bounded 1 Pagination.history_limit (opt "limit" KNatural)]));
  DeclareCommand KernelQuery TaskAllowed (WireCommand "search_history" [req "query" KText; u32 (opt "project_id" KNatural); u32 (opt "work_id" KNatural); u32 (opt "after" KNatural); bounded 1 Pagination.search_limit (opt "limit" KNatural)]);
  DeclareCommand KernelQuery TaskExcluded (WireCommand "list" []);
  DeclareCommand KernelQuery TaskExcluded (WireCommand "describe" []);
  DeclareCommand KernelChange TaskExcluded (WireCommand "create_project" [typed Workspace.project_name_declaration (req "name" KText); typed workspace_declaration (req "workspace" KJson); host_observed (typed guidance_declaration (opt "guidance" KJson)); opt "create_worktree" KBool; host_observed (typed binding_declaration (opt "workspace_binding" KJson))]);
  DeclareCommand KernelChange TaskExcluded (WireCommand "update_project" [u32 (req "project_id" KNatural); typed Workspace.project_name_declaration (opt "name" KText); typed workspace_declaration (opt "workspace" KJson); host_observed (typed guidance_declaration (opt "guidance" KJson)); opt "create_worktree" KBool; host_observed (typed binding_declaration (opt "workspace_binding" KJson))]);
  DeclareCommand KernelChange TaskExcluded (WireCommand "delete_project" [u32 (req "project_id" KNatural)]);
  DeclareCommand KernelQuery TaskExcluded (WireCommand "list_projects" []);
  DeclareCommand KernelQuery TaskExcluded (WireCommand "read_project" [u32 (req "project_id" KNatural)]);
  DeclareCommand KernelChange TaskExcluded (WireCommand "review_approval" (task_identity ++ [u32 (req "operation_id" KNatural); req "decision" (KEnum "allow" ["deny"]); opt "reason" KText]));
  DeclareCommand KernelChange TaskExcluded (WireCommand "record_speech_transcript" (task_identity ++ [req "session_id" KText; req "item_id" KText; req "speaker" (KEnum "user" ["assistant"]); req "completion" (KEnum "completed" ["interrupted"]); req "text" KText]));
  DeclareCommand KernelChange TaskExcluded (WireCommand "accept_speech_delegation" (task_identity ++ [req "session_id" KText; req "delegation_id" KText; req "message" KText; req "mode" (KEnum "send" ["steer"])]));
  DeclareCommand BoardChange TaskExcluded (WireCommand "create_card" (typed board_clock (opt "observed_at" KText) :: card_metadata ++ [opt "assisted" KBool; opt "draft_profile" KText]));
  DeclareCommand BoardChange TaskExcluded (WireCommand "update_card" (card_identity ++ card_metadata));
  DeclareCommand BoardChange TaskExcluded (WireCommand "move_card" (card_identity ++ [required (typed board_status (opt "status" KText)); optional_identity_text (opt "before_card" KText)]));
  DeclareCommand BoardChange TaskExcluded (WireCommand "archive_card" card_identity);
  DeclareCommand BoardChange TaskExcluded (WireCommand "restore_card" card_identity);
  DeclareCommand BoardChange TaskExcluded (WireCommand "delete_card" card_identity);
  DeclareCommand BoardChange TaskExcluded (WireCommand "run_card" card_identity);
  DeclareCommand BoardChange TaskExcluded (WireCommand "link_card" (card_identity ++ [required (u32 (opt "task_id" KNatural))]));
  DeclareCommand BoardChange TaskExcluded (WireCommand "regenerate_card_title" (card_identity ++ [opt "draft_profile" KText]));
  DeclareCommand BoardChange TaskExcluded (WireCommand "pin_card" (card_identity ++ [required (opt "pinned" KBool)]));
  DeclareCommand BoardChange TaskExcluded (WireCommand "board_settings" [req "automatic" KBool; req "draft_profile" KText]);
  DeclareCommand BoardChange TaskExcluded (WireCommand "save_board_agent" [optional_identity_text (req "agent" KText); u32 (req "revision" KNatural);
   typed BoardParameters.agent_name_declaration (req "name" KText);
   typed BoardParameters.agent_profile_declaration (req "profile" KText);
   typed BoardParameters.agent_reasoning_declaration (req "reasoning" KText);
   typed BoardParameters.agent_instructions_declaration (req "instructions" KText);
   staged settings_declaration (opt "settings" KJson);
   typed BoardParameters.agent_capacity_declaration (req "concurrency" KNatural)]);
  DeclareCommand BoardChange TaskExcluded (WireCommand "delete_board_agent" [u32 (req "agent_id" KNatural); u32 (req "revision" KNatural)]);
  DeclareCommand BoardQuery TaskExcluded (WireCommand "list_cards" []);
  DeclareCommand BoardQuery TaskExcluded (WireCommand "read_card" [u32 (req "card_id" KNatural)]);
  DeclareCommand BoardQuery TaskExcluded (WireCommand "list_board_agents" []);
  DeclareCommand ChatgptChange TaskExcluded (WireCommand "configure_chatgpt_connections" [typed grants_declaration (req "connections" (KArray KJson))]);
  DeclareCommand ChatgptChange TaskExcluded (WireCommand "chatgpt_exec" (connection_project ++ [typed ChatgptArguments.request_declaration (req "request_id" KText); typed ChatgptArguments.declaration (req "arguments" KJson)]));
  DeclareCommand ChatgptChange TaskExcluded (WireCommand "chatgpt_cancel" connection_operation);
  DeclareCommand ChatgptChange TaskExcluded (WireCommand "chatgpt_forget" connection_operation);
  DeclareCommand ChatgptQuery TaskExcluded (WireCommand "chatgpt_projects" [u32 (req "connection_id" KNatural)]);
  DeclareCommand ChatgptQuery TaskExcluded (WireCommand "chatgpt_project" connection_project);
  DeclareCommand ChatgptQuery TaskExcluded (WireCommand "chatgpt_operation" connection_operation);
  DeclareCommand ChatgptQuery TaskExcluded (WireCommand "chatgpt_operations" connection_project);
  DeclareCommand RemoteChange TaskExcluded (WireCommand "remote_enable" []);
  DeclareCommand RemoteChange TaskExcluded (WireCommand "remote_disable" []);
  DeclareCommand RemoteChange TaskExcluded (WireCommand "remote_grant" [typed controller_id_declaration (req "controller_id" KText); typed permissions_declaration (req "permissions" KJson)]);
  DeclareCommand RemoteChange TaskExcluded (WireCommand "remote_revoke" [typed controller_id_declaration (req "controller_id" KText)]);
  DeclareCommand RemoteQuery TaskExcluded (WireCommand "remote_status" []);
  DeclareCommand TaskGraphChange TaskAllowed (WireCommand "create_task_graph" (u32 (opt "work_id" KNatural) :: graph_fields));
  DeclareCommand TaskGraphChange TaskAllowed (WireCommand "update_task_graph" (u32 (req "graph_id" KNatural) :: graph_fields));
  DeclareCommand TaskGraphChange TaskAllowed (WireCommand "delete_task_graph" [u32 (req "graph_id" KNatural)]);
  DeclareCommand TaskGraphQuery TaskAllowed (WireCommand "list_task_graphs" []);
  DeclareCommand TaskGraphQuery TaskAllowed (WireCommand "read_task_graph" [u32 (req "graph_id" KNatural)]);
  DeclareCommand TitleQuery TaskExcluded (WireCommand "read_title_settings" []);
  DeclareCommand TitleChange TaskExcluded (WireCommand "configure_title_settings" [req "revision" KNatural; typed title_prompt_declaration (req "task_prompt" KText); typed title_prompt_declaration (req "agent_prompt" KText)]);
  DeclareCommand WorkChange TaskAllowed (WireCommand "create_work" [typed Selvedge.Features.Domain.work_creation_name_declaration (opt "name" KText)]);
  DeclareCommand WorkChange TaskAllowed (WireCommand "rename_work" [u32 (req "work_id" KNatural); typed Selvedge.Features.Domain.work_name_declaration (req "name" KText)]);
  DeclareCommand WorktreeChange TaskAllowed (WireCommand "create_work_task" (u32 (req "work_id" KNatural) :: creation_fields ++ [opt "create_worktree" KBool]));
  DeclareCommand WorkQuery TaskAllowed (WireCommand "list_works" []);
  DeclareCommand WorkQuery TaskAllowed (WireCommand "read_work" [u32 (req "work_id" KNatural)]);
  DeclareCommand WorkQuery TaskAllowed (WireCommand "read_work_ui" []);
  DeclareCommand WorkChange TaskAllowed (WireCommand "apply_work_ui_patch" [req "patch" KText; u32 (req "revision" KNatural)]);
  DeclareCommand WorktreeChange TaskExcluded (WireCommand "create_worktree_task" creation_fields);
  DeclareCommand WorktreeChange TaskExcluded (WireCommand "create_workspace_task" (req "backend" WorkspaceBackend.declaration :: creation_fields ++ [u32 (opt "work_id" KNatural)]));
  DeclareCommand WorktreeQuery TaskExcluded (WireCommand "list_worktrees" []);
  DeclareCommand WorktreeQuery TaskExcluded (WireCommand "read_worktree" task_identity);
  DeclareCommand WorktreeChange TaskExcluded (WireCommand "retry_worktree_archive" task_identity);
  DeclareCommand WorktreeQuery TaskExcluded (WireCommand "resolve_workspace" [typed (D.nullable workspace_declaration) (nullable "workspace" KJson); typed (D.nullable identity) (nullable "project_id" KNatural)])
].
Definition command_specs := map declared_schema command_declarations.
Definition task_command_allowed (name : string) :=
 match find (fun declaration => String.eqb name (command_name (declared_schema declaration)))
   command_declarations with
 | Some declaration => match declared_task_exposure declaration with
   | TaskAllowed => true | TaskExcluded => false end
 | None => false end.
Definition origin_allowed (task_origin : bool) (name : string) :=
 if task_origin then task_command_allowed name else true.

Theorem excluded_commands_reject_task_origin : forall name,
 task_command_allowed name = false -> origin_allowed true name = false.
Proof. intros name Excluded; exact Excluded. Qed.
Theorem external_origin_preserves_existing_authorization : forall name,
 origin_allowed false name = true.
Proof. reflexivity. Qed.

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
 Arguments.with_description (command_field_description command (field_name field))
   (Arguments.from_field field).

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
