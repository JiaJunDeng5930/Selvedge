From Stdlib Require Import String List Bool NArith Numbers.DecimalString.
From Selvedge.Foundation Require Import Json Schema.
From Selvedge.Features Require Import Titles CompactionTypes.
From Selvedge.Kernel Require Import Domain ChatgptArguments WorkspaceBackend.
From Selvedge.Foundation Require Export RemoteIdentity.
Import ListNotations.

Inductive board_stage := Backlog | Todo | InProgress | InReview | Completed | Blocked.
Inductive priority := NoPriority | Low | Medium | High | Urgent.
Inductive owner := Unassigned | Self | ProfileOwner (profile : string) | AgentOwner (id : N).
Record attachment := Attachment { attachment_id : string; attachment_name : string;
 attachment_mime : string; attachment_path : string; attachment_bytes : N }.
Record card_draft := CardDraft { draft_title : string; draft_description : string;
 draft_stage : board_stage; draft_priority : priority; draft_owner : owner;
 draft_project : option N; draft_labels : list string; draft_attachments : list attachment }.
Inductive enrichment := NoEnrichment | Enriching (ticket revision : N) (retitle : bool) | EnrichmentFailed (reason : string).
Record card := Card { card_revision : N; card_contents : card_draft;
 card_task : option N; card_archived : bool; card_created : N; card_updated : N;
 card_enrichment : enrichment; card_start_error : string; card_pinned : bool }.
Record board_agent := BoardAgent { agent_revision : N; agent_name : string;
 agent_profile : string; agent_reasoning : string; agent_instructions : string;
 agent_settings : json; agent_concurrency : N }.
Record board := Board { board_cards : list (option card); board_order : list N;
 board_agents : list (option board_agent); board_agent_order : list N; board_automatic : bool; board_draft_profile : string }.
Record work := Work { work_name : string; work_ui_source : string; work_ui_revision : N }.
Inductive graph_message := GraphOutput | GraphLiteral (text : string) | GraphConcat (parts : list graph_message).
Record graph_action := GraphAction { action_target : string; action_message : graph_message }.
Record graph_rule := GraphRule { rule_key : string; rule_source : string; rule_actions : list graph_action }.
Inductive graph_node := ExistingNode (key : string) (task : N)
 | SpawnNode (key profile reasoning : string) (message : content) (settings : json).
Record resolved_node := ResolvedNode { node_key : string; node_task : N }.
Record graph_receipt := GraphReceipt { receipt_source : N; receipt_rule : string;
 receipt_target : N; receipt_reply : json }.
Record task_graph := TaskGraph { graph_name : string; graph_nodes : list resolved_node;
 graph_rules : list graph_rule; graph_receipts : list graph_receipt }.
Inductive worktree_status := Creating | CreatingArchived | Ready | CreationFailed | Archiving | ArchiveFailed | WorktreeArchived.
Inductive tree_phase := TreeCreating (archived : bool)
 | TreeReady (root primary : string)
 | TreeCreateFailed (root : option string) (reason : string)
 | TreeArchiving (root primary : string)
 | TreeArchiveFailed (root primary reason : string)
 | TreeArchived (root : option string) (primary : string).
Record worktree := Worktree { worktree_task : N; worktree_source : string; worktree_phase : tree_phase;
 worktree_backend : WorkspaceBackend.backend }.
Definition with_worktree_phase (phase : tree_phase) (value : worktree) :=
 Worktree (worktree_task value) (worktree_source value) phase (worktree_backend value).
Definition worktree_state (value:worktree) := match worktree_phase value with
 | TreeCreating false=>Creating | TreeCreating true=>CreatingArchived | TreeReady _ _=>Ready
 | TreeCreateFailed _ _=>CreationFailed | TreeArchiving _ _=>Archiving
 | TreeArchiveFailed _ _ _=>ArchiveFailed | TreeArchived _ _=>WorktreeArchived end.
Definition worktree_root (value:worktree) := match worktree_phase value with
 | TreeCreating _=>None | TreeCreateFailed root _ | TreeArchived root _=>root
 | TreeReady root _ | TreeArchiving root _ | TreeArchiveFailed root _ _=>Some root end.
Definition worktree_target_primary (value:worktree) := match worktree_phase value with
 | TreeReady _ primary | TreeArchiving _ primary | TreeArchiveFailed _ primary _ | TreeArchived _ primary=>primary | _=>""%string end.
Definition worktree_message (value:worktree) := match worktree_phase value with
 | TreeCreateFailed _ message | TreeArchiveFailed _ _ message=>message | _=>""%string end.
Record rights := Rights { may_read : bool; may_control : bool; may_configure : bool; may_approve : bool }.
Definition rights_fields := [Field "read"%string KBool; Field "control"%string KBool;
 Field "configure"%string KBool; Field "approve"%string KBool].
Record remote_grant := RemoteGrant { grant_controller : controller_id; grant_epoch : RemoteIdentity.grant_epoch; grant_rights : rights }.
Record remote_receipt := RemoteReceipt { remote_controller : controller_id; remote_epoch : RemoteIdentity.grant_epoch;
 remote_request : RemoteIdentity.request_id; remote_intent : json; remote_reply : json }.
Record remote := Remote { remote_enabled : bool; remote_grants : list remote_grant;
 remote_next_epoch : N; remote_receipts : list remote_receipt }.
Record connection_grant := ConnectionGrant { connection_id : N; connection_projects : list N;
 connection_sandbox : sandbox }.
Inductive job_status := JobRunning | JobFinished (value : json) (error : bool) | JobInterrupted (reason : string).
Record connection_job := ConnectionJob { job_connection : N; job_project : N;
 job_request : string; job_arguments : Schema.fields ChatgptArguments.argument_declaration;
 job_workspace : workspace; job_resource : option N; job_sandbox : sandbox; job_state : job_status }.
Definition job_arguments_json job := Schema.encode ChatgptArguments.argument_declaration (job_arguments job).
Record connection_state := ConnectionState { sharing_grants : list connection_grant;
 sharing_jobs : list (N * connection_job); sharing_next : N }.
Record title_settings := TitleSettings { title_revision : N; title_task_prompt : string; title_agent_prompt : string }.
Inductive title_state := TitlePending (ticket : N) (selected : profile) (prompt : string) | Named (text : string) | TitleFailed (reason : string).
Record title_entry := TitleEntry { title_task : N; title_value : title_state }.
Record state := State {
 feature_board : board;
 feature_works : list work;
 feature_task_owners : list (N * N);
 feature_graph_owners : list (N * N);
 feature_graphs : list (option task_graph);
 feature_worktrees : list worktree;
 feature_remote : remote;
 feature_sharing : connection_state;
 feature_titles : list title_entry;
 feature_title_settings : title_settings;
 feature_compaction : CompactionTypes.state
}.
Definition initial := State (Board [] [] [] [] false ""%string) [] [] [] [] []
 (Remote false [] 1 []) (ConnectionState [] [] 0) [] (TitleSettings 0 Titles.instructions Titles.instructions) CompactionTypes.initial.

Definition stages := [Backlog; Todo; InProgress; InReview; Completed; Blocked].
Definition priorities := [NoPriority; Low; Medium; High; Urgent].
Definition stage_name (value : board_stage) := match value with
 | Backlog => "backlog"%string | Todo => "todo"%string | InProgress => "in_progress"%string
 | InReview => "in_review"%string | Completed => "done"%string | Blocked => "blocked"%string end.
Definition stage_label (value : board_stage) := match value with
 | Backlog => "待规划"%string | Todo => "待办"%string | InProgress => "进行中"%string
 | InReview => "待审核"%string | Completed => "已完成"%string | Blocked => "已阻塞"%string end.
Definition priority_name (value : priority) := match value with
 | NoPriority => "none"%string | Low => "low"%string | Medium => "medium"%string
 | High => "high"%string | Urgent => "urgent"%string end.
Definition priority_label (value : priority) := match value with
 | NoPriority => "无"%string | Low => "低"%string | Medium => "中"%string
 | High => "高"%string | Urgent => "紧急"%string end.

Definition decimal_text (value:N) := NilZero.string_of_uint (N.to_uint value).
Definition owner_name (value:owner) := match value with
 | Unassigned=>"none"%string | Self=>"self"%string
 | ProfileOwner name=>String.append "profile/" name
 | AgentOwner id=>String.append "agent/" (decimal_text id) end.
Definition association (id:N) (bindings:list (N*N)) := option_map (@snd N N) (find (fun entry=>N.eqb id (fst entry)) bindings).
Fixpoint lineage_owner (lineage:list N) (owners:list (N*N)) :option N :=
 match lineage with []=>None | ancestor::rest=>
 match association ancestor owners with Some owner=>Some owner | None=>lineage_owner rest owners end end.
Definition owner_id (id:N) (lineage:list N) (value:state) :=
 match association id (feature_task_owners value) with Some owner=>Some owner
 | None=>lineage_owner lineage (feature_task_owners value) end.
