From Selvedge.Features Require Import WorkspaceBinding.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates State History ModelCapabilities TaskConstraints.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition find_profile (name : string) (catalog : list profile) :=
 find (fun profile => String.eqb name (profile_key profile)) catalog.
Definition find_tool (name : string) (catalog : list tool) :=
 find (fun tool => String.eqb name (tool_name tool)) catalog.
Definition content_text := Domain.content_text.
Definition content_nonempty (parts : content) :=
 existsb (fun part => match part with TextPart text => Utf8.nonblank text | ImagePart _ => true end) parts.
Definition input_required_message := "A task input needs text or an image".
Definition profile_required_message := "The configured model profile does not exist".
Definition invalid_reasoning_message := "The selected reasoning effort is unavailable for this profile".
Definition selected_reasoning (effort : option string) (profile : profile) :=
 match effort with None | Some "default" => Some profile
 | Some value =>
   if match profile_policy profile with
     | AdaptivePolicy _ => String.eqb value "auto"
     | FixedReasoning => nonempty value && negb (String.eqb value "auto") &&
       match profile_reasoning_options profile with [] => true | options => existsb (String.eqb value) options end
     end then Some (with_reasoning value profile) else None end.
Definition creation_defaults (environment : environment) :=
 let project := environment_project environment in
 let workspace := match value_or_null "workspace" project with
 | JString root => Workspace [root] (Some root)
 | value => match parse_workspace value with Some workspace => workspace | None => default_workspace end end in
 Settings workspace None (settings_sandbox default_settings)
  (settings_approval default_settings) project false None.
Definition resolve_settings (model : profile) (source : option json) (fallback : task_settings) (value : world) :=
 let raw := match source with Some raw => raw | None => JNull end in
 let base := match field "project_id" raw with
 | None => Some fallback
 | Some JNull => Some (Settings (settings_workspace fallback) None (settings_sandbox fallback)
    (settings_approval fallback) (settings_guidance fallback) (settings_worktree fallback) (settings_resource fallback))
 | Some source => match natural source with
   | None => None
   | Some id => match registry_at id (world_projects value) with
     | Some project => if project_deleted project then None else
       Some (Settings (project_workspace project) (Some id) (settings_sandbox fallback)
        (settings_approval fallback) (Domain.project_guidance project) (project_worktree project) None)
     | None => None end end
 end in
 match base with
 | Some base => match parse_settings model (environment_profiles (world_environment value)) raw base with
   | Some settings => Some (WorkspaceBinding.normalize_settings settings value) | None => None end
 | None => None end.
Definition resolve_for_profile (name : string) (source : option json) (fallback : task_settings) (value : world) :=
 match find_profile name (environment_profiles (world_environment value)) with
 | Some model => resolve_settings model source fallback value | None => None end.

(* Native commands cannot perform realpath or observe guidance. Only roots
   from committed caller, environment or project observations may be reused. *)
Definition observed_creation_roots (caller : task_settings) (value : world) :=
 workspace_roots (settings_workspace caller) ++
 workspace_roots (settings_workspace (creation_defaults (world_environment value))) ++
 List.concat (map (fun project => if project_deleted project then [] else workspace_roots (project_workspace project)) (world_projects value)).
Definition native_creation_allowed (options : option json) (selected caller : task_settings) (value : world) :=
 let no_guidance := match options with None => true | Some options =>
   match field "guidance" options with None => true | Some _ => false end end in
 Workspace.may_delegate selected caller && no_guidance &&
 forallb (fun root => existsb (String.eqb root) (observed_creation_roots caller value))
   (workspace_roots (settings_workspace selected)).
Definition initial_project_guidance (settings : task_settings) :=
 let source := settings_guidance settings in
 match string_field "workspace" source, string_field "path" source,
       string_field "revision" source, string_field "instructions" source with
 | Some workspace, Some path, Some revision, Some content =>
   ContextUpdates.construct_snapshot Context.project_guidance [("workspace",workspace)] revision
     [("content",content);("path",path);("applies_to",workspace);("precedence",workspace)]
 | _,_,_,_ => None end.
Definition initial_history (environment : environment) (chosen : profile) (settings : task_settings) :=
 let configured := Snapshot (ContextKey Context.configured [("origin","configured")]) "initial"
   [("content",environment_instructions environment)] in
 [ContextObservation (Introduce configured)] ++
 (match environment_global_instructions environment with
  | None => []
  | Some source => [ContextObservation (Introduce (Snapshot
    (ContextKey Context.global_guidance [("path",text_default "path" source "")])
    (text_default "revision" source "") [("content",text_default "content" source "")]))] end) ++
 (match initial_project_guidance settings with
  | Some snapshot => [ContextObservation (Introduce snapshot)] | None => [] end) ++
 [SettingsMessage settings (profile_key chosen) (profile_reasoning chosen)].
Definition make_task (chosen : profile) (settings : task_settings) (contents : content)
 (idle : bool) (environment : environment) :=
 let contract := Contract chosen (environment_tools environment) settings
   (environment_max_fork environment) (environment_max_descendants environment)
   (environment_plugins environment) (environment_profiles environment) in
 Task contract chosen settings (Running (if idle then Idle else WantsModel) [])
  (initial_history environment chosen settings ++ if idle then [] else [UserMessage contents])
  [] [] None 0 0.
Definition create_with_defaults (name : string) (reasoning : option string) (contents : content)
 (settings : option json) (idle : bool) (fallback : task_settings) (value : world) : decision :=
 match find_profile name (environment_profiles (world_environment value)) with
 | None => reject "profile_not_found" profile_required_message value
 | Some profile => match selected_reasoning reasoning profile,
    resolve_for_profile name settings fallback value with
   | Some chosen, Some resolved =>
     if idle || content_nonempty contents then
       accept (JObject [("task_id", number (next_task value))])
         (append_task (make_task chosen resolved contents idle (world_environment value)) value) []
     else reject "invalid_message" input_required_message value
   | None,_ => reject "invalid_reasoning" invalid_reasoning_message value
   | _,None => reject "invalid_settings" "Task settings do not resolve to a current project and workspace" value
   end
 end.
Definition create (name : string) (reasoning : option string) (contents : content)
 (settings : option json) (idle : bool) (value : world) :=
 create_with_defaults name reasoning contents settings idle (creation_defaults (world_environment value)) value.
Definition queue (contents : content) (value : task) :=
 with_queued (task_queued value ++ [contents]) value.
Definition receive (contents : content) (value : task) :=
 match task_lifecycle value with
 | Archived => value
 | Frozen _ _ => queue contents value
 | Running Idle [] | Running (PendingCalls []) [] | Stopped Idle [] | Stopped (PendingCalls []) [] =>
   with_lifecycle (Running WantsModel []) (with_queued []
    (append_history (map UserMessage (task_queued value ++ [contents])) value))
 | Running _ _ => queue contents value
 | Stopped phase operations => with_lifecycle (Running phase operations) (queue contents value)
 end.
Definition send (id : N) (contents : content) (value : world) :=
 match find_task id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some task => match task_lifecycle task with
   | Archived => reject "task_archived" "Archived tasks cannot accept input" value
   | _ => if content_nonempty contents then
      accept (JObject [("task_id", number id)]) (put_task id (receive contents task) value) []
     else reject "invalid_message" input_required_message value
   end
 end.
Definition inference_effects (id : N) (task : task) :=
 match task_activity task with
 | ObservingContext ticket _ | AskingModel ticket _ _ | EvaluatingReasoning ticket _
 | CheckingHook ticket _ _ _ _ => [CancelTicket id ticket]
 | _ => [] end.
Definition unknown_operations (operations : list operation) :=
 map (History.interrupted_result "outcome_unknown"
 "The external operation may already have run. Its side effects cannot be inferred or undone; it will not be repeated automatically.") operations.
Inductive control := Freeze | Unfreeze | Stop | Interrupt | Archive.
Definition control_transition (command : control) (current : lifecycle) : option lifecycle :=
 match command, current with
 | Freeze, Running phase operations => Some (Frozen phase operations)
 | Unfreeze, Frozen phase operations => Some (Running phase operations)
 | Stop, Running phase operations => Some (Stopped phase operations)
 | Interrupt, Archived | Archive, Archived => None
 | Interrupt, _ => Some (Stopped Idle [])
 | Archive, _ => Some Archived
 | _,_ => None end.
Definition control_target (command : control) (value : task) := control_transition command (task_lifecycle value).
Definition control_name (value : control) := match value with Freeze => "freeze" | Unfreeze => "unfreeze"
 | Stop => "stop" | Interrupt => "interrupt" | Archive => "archive" end.
Definition available_controls (value : lifecycle) := fold_right (fun request rest =>
 match control_transition request value with Some _ => JString (control_name request) :: rest | None => rest end)
 [] [Freeze;Unfreeze;Stop;Interrupt;Archive].
Definition control_task (command : control) (task : task) :=
 match control_target command task with
 | None => task
 | Some target => with_lifecycle target
   (match command with
    | Interrupt | Archive => append_history (History.interrupted_phase (task_activity task) ++ unknown_operations (task_operations task)) task
    | _ => task end)
 end.
Definition control_effects (id : N) (command : control) (task : task) :=
 match command with
 | Freeze | Unfreeze => []
 | Stop => []
 | Interrupt | Archive => [CancelTask id]
 end.
Definition control_command (id : N) (command : control) (value : world) :=
 match find_task id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some task => match control_target command task with
   | None => reject "invalid_control" "This lifecycle control is unavailable for the task" value
   | Some _ => accept (JObject [("task_id", number id)])
      (put_task id (control_task command task) value) (control_effects id command task)
   end end.
Definition steer (id : N) (contents : content) (value : world) :=
 match find_task id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some task => match task_lifecycle task with
   | Archived => reject "task_archived" "Archived tasks cannot accept input" value
   | current => if content_nonempty contents then
     let lifecycle := match current with Frozen _ operations => Frozen WantsModel operations
       | _ => Running WantsModel (task_operations task) end in
     accept (JObject [("task_id", number id)])
      (put_task id (with_lifecycle lifecycle (append_history (History.interrupted_phase (task_activity task) ++ [UserMessage contents]) task)) value)
      (inference_effects id task)
     else reject "invalid_message" input_required_message value
   end end.
Definition promote (task : task) :=
 match task_lifecycle task, task_queued task with
 (* WantsModel is still before request capture. Input queued while workspace
    preparation froze the task belongs to that first request after setup. *)
 | Running Idle operations, first :: rest | Running (PendingCalls []) operations, first :: rest
 | Running WantsModel operations, first :: rest =>
   with_lifecycle (Running WantsModel operations)
    (with_queued [] (append_history (map UserMessage (first :: rest)) task))
 | Stopped Idle operations, first :: rest | Stopped (PendingCalls []) operations, first :: rest =>
   with_lifecycle (Stopped Idle operations)
    (with_queued [] (append_history (map UserMessage (first :: rest)) task))
 | _,_ => task end.
Definition wake_after_result (task : task) :=
 match task_lifecycle task with
 | Running Idle operations => with_lifecycle (Running WantsModel operations) task
 | _ => promote task end.
Definition cancel_operation (id operation_id : N) (value : world) :=
 match find_task id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some task =>
   match find (fun operation => N.eqb operation_id (Domain.operation_id operation)) (task_operations task) with
   | None => reject "operation_not_found" "The operation is not live in this task" value
   | Some operation =>
     let remaining := filter (fun operation => negb (N.eqb operation_id (Domain.operation_id operation))) (task_operations task) in
     accept (JObject [("task_id", number id); ("operation_id", number operation_id)])
      (put_task id (wake_after_result (with_operations remaining
       (append_history [History.cancelled_operation operation] task))) value)
      (match operation_stage operation with
       | Executing ticket | Elevated ticket _ | AwaitingApproval ticket _ | AwaitingAfterHook ticket _ _ _ _ => [CancelTicket id ticket]
       | Granted _ | AfterHooksReady _ _ _ => [] end)
   end end.
Definition quiescent (task : task) :=
 negb (task_busy task) && Nat.eqb (List.length (task_queued task)) 0.
Definition descendant_count (ancestor : N) (tasks : list task) :=
 N.of_nat (List.length (filter (fun task => existsb (N.eqb ancestor) (task_lineage task)) tasks)).
Definition ancestor_capacity (value:world)(ancestor:N):option(N*N):=
 match find_task ancestor value with
 |Some task=>Some(descendant_count ancestor(world_tasks value),contract_max_descendants(task_contract task))
 |None=>None end.
Definition ancestors_fit (parents : list N) (count : N) (value : world) :=
 TaskConstraints.fork_capacities_valid count(map(ancestor_capacity value)parents).
Definition fork_parent_ready (invoked:bool)(task:task) :=
 (quiescent task || (invoked && match task_lifecycle task with
  |Running(PendingCalls _)[]|Running(ReadyForHooks _ _ _)[]=>true|_=>false end)) &&
 negb(String.eqb(task_status task)"archived").
Definition context_selected (selected : workspace) (key : context_key) :=
 match definition_scope (key_definition key) with
 | Global => true
 | EveryWorkspace | PrimaryWorkspace => match ContextUpdates.scoped_root key with
   | None => false
   | Some root => existsb (String.eqb root) (workspace_roots selected) &&
     match definition_scope (key_definition key) with
     | PrimaryWorkspace => match workspace_primary selected with
       | Some primary => String.eqb root primary | None => false end
     | _ => true end end
 end.
Definition selected_context_history (settings : task_settings) (parent : task) (history : list message) :=
 let previous := task_current_settings parent in
 if Json.equal (settings_json settings) (settings_json previous) &&
    Json.equal (settings_guidance settings) (settings_guidance previous) then history else
 let removals := fold_right (fun snapshot rest =>
   if context_selected (settings_workspace settings) (snapshot_key snapshot) then rest
   else ContextObservation (Remove (snapshot_key snapshot) (snapshot_revision snapshot)) :: rest)
   [] (ContextUpdates.bindings history) in
 let history := (history ++ removals)%list in
 let history := match initial_project_guidance settings with
 | None => history
 | Some snapshot =>
   (* Explicit selection admits the current source. The same workspace identity
      must not hide a newly admitted guidance revision or body. *)
   let same := match ContextUpdates.find_snapshot (snapshot_key snapshot) (ContextUpdates.bindings history) with
   | Some previous => Json.equal (Context.snapshot_json previous) (Context.snapshot_json snapshot)
   | None => false end in
   if same then history else (history ++ [ContextObservation (Introduce snapshot)])%list end in
 (history ++ [SettingsMessage settings (profile_key (task_current_profile parent))
   (profile_reasoning (task_current_profile parent))])%list.
Definition fork_child_history (owner parent_id : N) (parent : task) (settings : task_settings) (side : bool) :=
 let inherited := selected_context_history settings parent (History.snapshot_history parent_id parent) in
 (* Keep birth guidance in provider history, outside the side return cursor. *)
 if side then inherited ++ [SideConversationBirth owner parent_id
   (N.succ (N.of_nat (List.length inherited)))] else inherited.
Definition fork_child (owner parent_id : N) (parent : task) (contents : content) (settings : task_settings)
 (side : bool) :=
 let chosen := task_current_profile parent in
 let contract := Contract chosen (contract_tools (task_contract parent)) settings
  (contract_max_fork (task_contract parent)) (contract_max_descendants (task_contract parent))
  (contract_plugins (task_contract parent)) (contract_reviewers (task_contract parent)) in
 Task contract chosen settings
 (Running (if content_nonempty contents then WantsModel else Idle) [])
 (fork_child_history owner parent_id parent settings side ++
  if content_nonempty contents then [UserMessage contents] else []) []
 (parent_id :: task_lineage parent)
 (if side then Some parent_id else None)
 (if side then N.of_nat (List.length (fork_child_history owner parent_id parent settings side)) else 0) 0.
Fixpoint fork_children (count : nat) (id : N) (parent : task) (messages : list content)
 (settings : task_settings) (value : world) : world :=
 match count with
 | O => value
 | S count =>
   let message := match messages with [] => [] | first :: _ => first end in
   let owner := next_task value in
   fork_children count id parent (tl messages) settings
      (append_task (fork_child owner id parent message settings false) value)
 end.
Definition fork_with_caller (invoked : bool) (id count : N) (messages : list content) (settings : option json) (value : world) :=
 match find_task id value with
 | None => reject "task_not_found" "The parent task does not exist" value
 | Some task =>
   if fork_parent_ready invoked task &&
    TaskConstraints.fork_count_valid count (contract_max_fork (task_contract task)) &&
    TaskConstraints.fork_messages_valid count (List.length messages) &&
    ancestors_fit (id :: task_lineage task) count value then
    match resolve_settings (task_current_profile task) settings (task_current_settings task) value with
    | None => reject "invalid_settings" "Child settings do not resolve to a current workspace" value
    | Some selected =>
      if invoked && negb (Workspace.may_delegate selected (task_current_settings task)) then
       reject "settings_forbidden" "Task tools cannot expand the caller's workspace, sandbox or approval authority" value else
      let settings := selected in
      let '(ticket, allocated) := allocate_ticket value in
      let invocation := Call ("manual-fork-" ++ number_text ticket) "fork_task"
        (JObject [("child_count",number count);("messages",JArray (map content_json messages))]) in
      let parent := if invoked then task else append_history [FunctionCall invocation] task in
      let children := fork_children (N.to_nat count) id parent messages settings
        (if invoked then value else allocated) in
      let children := if invoked then children else
        with_tasks (Numbers.indexed (fun child task =>
          if N.leb (next_task value) child then with_activity WantsModel
           (append_history [ForkReceipt child invocation (N.succ (child-next_task value)%N)] task)
          else if N.eqb child id then with_activity WantsModel (append_history [ForkReceipt id invocation 0] parent)
          else task) 0 (world_tasks children)) children in
      accept (JObject [("children", JArray (map (fun offset => number (next_task value + N.of_nat offset)) (seq 0 (N.to_nat count))))]) children []
    end
   else reject "fork_unavailable" "Forking requires an eligible task, a positive count within its fork limit, no messages or exactly one per child, and capacity within every ancestor's descendant limit" value
 end.
Definition fork := fork_with_caller false.
Definition open_side (id : N) (contents : content) (value : world) :=
 match find_task id value with
 | None => reject "task_not_found" "The parent task does not exist" value
 | Some task => if String.eqb (task_status task) "archived" then
   reject "task_archived" "Archived tasks cannot create a side conversation" value
   else if ancestors_fit (id :: task_lineage task) 1 value then
   accept (JObject [("task_id", number (next_task value)); ("parent_task_id", number id)])
    (append_task (fork_child (next_task value) id task contents (task_current_settings task) true) value) []
   else reject "descendant_limit" "The parent task has no remaining descendant capacity" value
 end.
(* The wire approval DTO names its reviewer. An explicit selection can replace
   the frozen profile behind that same key, so wire equality is insufficient. *)
Definition same_approval (left right : approval_policy) :=
 match left, right with
 | FullAccess, FullAccess | AskForApproval, AskForApproval => true
 | ReviewWith reviewer_left, ReviewWith reviewer_right => Domain.same_profile reviewer_left reviewer_right
 | _, _ => false end.

(* Resetting effort uses the captured definition, even after the catalog changes.
   An omitted effort still retains the task's current selection. *)
Definition execution_reasoning (effort : option string) (current : profile) :=
 match effort with
 | Some "default" => match parse_profile (profile_metadata current) with
   | Some configured => Some (with_reasoning (profile_reasoning configured) current)
   | None => None end
 | _ => selected_reasoning effort current
 end.

Definition configure_execution_with (normalize : task_settings -> task_settings) (id : N)
 (name reasoning : option string) (sandbox_source approval_source : option json) (value : world) :=
 match find_task id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some task =>
   if quiescent task && negb (String.eqb (task_status task) "archived") then
   let current := task_current_settings task in
   let model := match name with
    | None => Some (task_current_profile task)
    | Some name => find_profile name (environment_profiles (world_environment value)) end in
   match model with
   | None => reject "profile_not_found" profile_required_message value
   | Some profile => match execution_reasoning reasoning profile with
     | None => reject "invalid_reasoning" "The selected reasoning effort is unavailable" value
     | Some chosen =>
       match match sandbox_source with
        | None => Some (settings_sandbox current)
        | Some source => parse_sandbox_patch (settings_sandbox current) source end with
       | None => reject "invalid_settings" "Sandbox settings do not satisfy the domain protocol" value
       | Some sandbox =>
         match match approval_source with
          | None => Some (settings_approval current)
          | Some source => parse_approval chosen (environment_profiles (world_environment value)) source end with
         | None => reject "invalid_approval" "The approval reviewer must be an existing fixed-reasoning profile" value
         | Some approval =>
           let settings := normalize (Settings (settings_workspace current) (settings_project current)
            sandbox approval (settings_guidance current) (settings_worktree current) (settings_resource current)) in
           let same := Domain.same_profile chosen (task_current_profile task) &&
             Json.equal (settings_json settings) (settings_json current) &&
             same_approval (settings_approval settings) (settings_approval current) in
           let updated := with_execution chosen settings task in
           let updated := if same then updated else append_history [SettingsMessage settings (profile_key chosen) (profile_reasoning chosen)] updated in
           accept (JObject [("task_id", number id)]) (put_task id updated value)
            (if same then [] else [ResetModelSession id])
         end
       end
     end
   end
   else reject "task_busy" "Execution settings require a quiescent unarchived task" value
 end.

Definition configure_execution := configure_execution_with (fun settings=>settings).
