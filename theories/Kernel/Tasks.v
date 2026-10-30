From Selvedge.Kernel Require CommandResult.
From Selvedge.Kernel Require Import TaskScope TaskChange.
From Selvedge.Features Require Import WorkspaceBinding State.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Utf8 FreshNames.
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
 match effort with None => Some profile
 | Some value => if String.eqb value "default" then Some profile
   else if Domain.reasoning_allowed value profile then Some (with_reasoning value profile) else None end.
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
 | Some JNull => None
 | Some source => match natural source with
   | None => None
   | Some id => match registry_at id (world_projects value) with
     | Some project => if project_deleted project then None else
       Some (Settings (project_workspace project) (Some id) (settings_sandbox fallback)
        (settings_approval fallback) (Domain.project_guidance project) (project_worktree project) (project_resource project))
     | None => None end end
 end in
 match base with
 | Some base => match parse_settings model (environment_profiles (world_environment value)) raw base with
   | Some settings =>
     let selected := match field "workspace_binding" raw, field "workspace" raw with
       | None, Some (JObject _) => WorkspaceBinding.select_bound_workspace base settings value
       | _, _ => Some settings end in
     option_map (fun settings => WorkspaceBinding.normalize_settings settings value) selected
   | None => None end
 | None => None end.
Definition resolve_for_profile (name : string) (source : option json) (fallback : task_settings) (value : world) :=
 match find_profile name (environment_profiles (world_environment value)) with
 | Some model => resolve_settings model source fallback value | None => None end.

(* Native commands cannot perform realpath or observe guidance. Only roots
   from committed caller, environment or project observations may be reused. *)
Definition observed_creation_roots (selected caller : task_settings) (value : world) :=
 let roots_in reference space :=
   if WorkspaceBinding.same_environment (settings_resource selected) reference value
   then workspace_roots space else [] in
 let defaults := creation_defaults (world_environment value) in
 roots_in (settings_resource caller) (settings_workspace caller) ++
 roots_in (settings_resource defaults) (settings_workspace defaults) ++
 List.concat (map (fun project => if project_deleted project then []
   else roots_in (project_resource project) (project_workspace project)) (world_projects value)).
Definition no_resource_observation (options : option json) :=
 match options with None => true | Some source => match field "workspace_binding" source with
 | None => true | Some _ => false end end.
Definition native_creation_allowed (options : option json) (selected caller : task_settings) (value : world) :=
 let no_guidance := match options with None => true | Some options =>
   match field "guidance" options with None => true | Some _ => false end end in
 Workspace.may_delegate selected caller && no_guidance && no_resource_observation options &&
 forallb (fun root => existsb (String.eqb root) (observed_creation_roots selected caller value))
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
  | Some source => match ContextUpdates.global_guidance_snapshot source with
    | Some snapshot => [ContextObservation (Introduce snapshot)]
    | None => [] end end) ++
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
(* A start is resolved against one observation of the environment. Feature
   installation may append other tasks before interpreting this immutable plan. *)
Inductive creation_entry := OrdinaryCreation | IdleCreation | NativeCreation
 | NativeFeatureCreation | Configuration | NativeForkEntry | ManagedCreation
 | WorkspaceCreation | WorktreeCreation.
Inductive failure_cause := UnknownProfile | InvalidSettings | InvalidReasoning
 | EmptyInput | InvalidPolicy | AuthorityExpansion | DescendantCapacity | InvalidForkRequest
 | MissingPrimaryWorkspace | WorkspaceUnavailable | ProjectPrimaryMismatch | InvalidWorkspace.
Definition failure_code (entry : creation_entry) (cause : failure_cause) :=
 match cause with
 | UnknownProfile => match entry with Configuration => "invalid_profile" | _ => "unknown_profile" end
 | InvalidPolicy => "invalid_policy"
 | InvalidReasoning | EmptyInput => match entry with
   | OrdinaryCreation | NativeCreation | IdleCreation => "invalid_arguments"
   | _ => "invalid_reasoning" end
 | InvalidSettings => "invalid_settings"
 | AuthorityExpansion => match entry with
   | NativeFeatureCreation => "invalid_native_feature"
   | NativeForkEntry => "approval_required"
   | _ => "invalid_settings" end
 | DescendantCapacity => "resource_limit"
 | InvalidForkRequest => "fork_unavailable"
 | MissingPrimaryWorkspace => match entry with
   | IdleCreation => "invalid_arguments"
   | WorkspaceCreation => "workspace_requires_git"
   | WorktreeCreation | NativeFeatureCreation => "worktree_requires_git"
   | _ => "invalid_workspace" end
 | WorkspaceUnavailable => match entry with IdleCreation => "invalid_arguments" | _ => "workspace_unavailable" end
 | ProjectPrimaryMismatch => "invalid_settings"
 | InvalidWorkspace => match entry with IdleCreation => "invalid_arguments" | _ => "invalid_workspace" end
 end.
Definition failure_message (cause : failure_cause) := match cause with
 | UnknownProfile => profile_required_message
 | InvalidReasoning => invalid_reasoning_message
 | EmptyInput => input_required_message
 | InvalidPolicy => "The approval reviewer must be an existing fixed-reasoning profile"
 | AuthorityExpansion => "Task tools cannot expand the caller's workspace, sandbox or approval authority"
 | DescendantCapacity => "The task descendant capacity is exhausted"
 | InvalidForkRequest => "Forking requires an eligible task, a positive count within its fork limit, no messages or exactly one per child, and capacity within every ancestor's descendant limit"
 | InvalidSettings => "Task settings do not resolve to a current project and workspace"
 | MissingPrimaryWorkspace => "Managed task creation requires a primary workspace root"
 | WorkspaceUnavailable => "The workspace execution environment is unavailable"
 | ProjectPrimaryMismatch => "The cloud project primary root does not match the selected workspace"
 | InvalidWorkspace => "The selected workspace is invalid or unavailable"
 end.
Definition start_refusal (entry : creation_entry) (cause : failure_cause) :=
 CommandResult.Refusal (failure_code entry cause) (failure_message cause).
Definition refuse_start (entry : creation_entry) (cause : failure_cause) (value : world) :=
 CommandResult.reject value (start_refusal entry cause).
Record resolved_start := ResolvedStart {
 start_profile : profile;
 start_settings : task_settings;
 start_contents : content;
 start_idle : bool;
 start_environment : environment
}.
Inductive start_resolution := StartRefused (cause : failure_cause)
 | StartResolved (plan : resolved_start).
Definition resolve_start (entry : creation_entry) (name : string) (reasoning : option string)
 (contents : content) (settings : option json) (idle : bool) (fallback : task_settings) (value : world) :=
 match find_profile name (environment_profiles (world_environment value)) with
 | None => StartRefused UnknownProfile
 | Some profile => match resolve_settings profile settings fallback value with
   | None => StartRefused InvalidSettings
   | Some resolved => match selected_reasoning reasoning profile with
     | None => StartRefused InvalidReasoning
     | Some chosen => if idle || content_nonempty contents then
       StartResolved (ResolvedStart chosen resolved contents idle (world_environment value))
       else StartRefused EmptyInput
     end
   end
 end.
Record birth_result (before : world) := BirthResult {
 birth_id : N;
 birth_task : task;
 birth_world : world;
 birth_fresh : birth_id = next_task before;
 birth_tasks : world_tasks birth_world = world_tasks before ++ [birth_task];
 birth_sequence : world_sequence birth_world = world_sequence before;
 birth_ticket : world_next_ticket birth_world = world_next_ticket before;
 birth_environment : world_environment birth_world = world_environment before;
 birth_projects : world_projects birth_world = world_projects before;
 birth_features : world_features birth_world = world_features before
}.
Arguments birth_id {before}.
Arguments birth_task {before}.
Arguments birth_world {before}.
Definition start_task (plan : resolved_start) :=
 make_task (start_profile plan) (start_settings plan) (start_contents plan)
   (start_idle plan) (start_environment plan).
Definition birth_prepared (created : task) (value : world) : birth_result value :=
 BirthResult value (next_task value) created (append_task created value)
   eq_refl eq_refl eq_refl eq_refl eq_refl eq_refl eq_refl.
Definition birth_start (plan : resolved_start) (value : world) :=
 birth_prepared (start_task plan) value.
Definition interpret_start (plan : resolved_start) (value : world) :=
 let born := birth_start plan value in
 accept (JObject [("task_id", number (birth_id born))]) (birth_world born) [].
Definition create_with_defaults (name : string) (reasoning : option string) (contents : content)
 (settings : option json) (idle : bool) (fallback : task_settings) (value : world) : decision :=
 let entry := if idle then IdleCreation else OrdinaryCreation in
 match resolve_start entry name reasoning contents settings idle fallback value with
 | StartRefused cause => refuse_start entry cause value
 | StartResolved plan => interpret_start plan value
 end.
Definition create (name : string) (reasoning : option string) (contents : content)
 (settings : option json) (idle : bool) (value : world) :=
 create_with_defaults name reasoning contents settings idle (creation_defaults (world_environment value)) value.
Definition queue (contents : content) (value : task) :=
 TaskChange.apply [TaskChange.AppendQueued contents] value.
Definition receive_changes (contents : content) (value : task) : list TaskChange.edit :=
 match task_lifecycle value with
 | Archived _ => []
 | Frozen _ _ => [TaskChange.AppendQueued contents]
 | Running Idle [] | Running (PendingCalls []) [] | Stopped Idle [] | Stopped (PendingCalls []) [] =>
   [TaskChange.AppendHistory (map UserMessage (task_queued value ++ [contents]));
    TaskChange.ReplaceQueued []; TaskChange.ChangeStatus TaskChange.RunningStatus;
    TaskChange.ChangePhase WantsModel]
 | Running _ _ => [TaskChange.AppendQueued contents]
 | Stopped _ _ => [TaskChange.ChangeStatus TaskChange.RunningStatus; TaskChange.AppendQueued contents]
 end.
Definition receive (contents : content) (value : task) := TaskChange.apply (receive_changes contents value) value.
Definition send_result (id : N) (contents : content) (value : world) :=
 match TaskScope.select id value with
 | None => CommandResult.refuse "task_not_found" "The target task does not exist"
 | Some target => let task := TaskScope.selected target in match task_lifecycle task with
   | Archived _ => CommandResult.refuse "invalid_arguments" "Archived tasks cannot accept input"
   | _ => if content_nonempty contents then
      CommandResult.Accepted (CommandResult.Change (JObject [("task_id",number id)])
        (TaskChange.interpret (TaskChange.Plan value target (receive_changes contents task))) [])
     else CommandResult.refuse "invalid_arguments" input_required_message
   end end.
Definition send (id : N) (contents : content) (value : world) :=
 CommandResult.decide value (send_result id contents value).
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
 | Interrupt, Archived _ | Archive, Archived _ => None
 | Interrupt, _ => Some (Stopped Idle [])
 | Archive, _ => Some (Archived [])
 | _,_ => None end.
Definition control_target (command : control) (value : task) := control_transition command (task_lifecycle value).
Definition control_name (value : control) := match value with Freeze => "freeze" | Unfreeze => "unfreeze"
 | Stop => "stop" | Interrupt => "interrupt" | Archive => "archive" end.
Definition available_controls (value : lifecycle) := fold_right (fun request rest =>
 match control_transition request value with Some _ => JString (control_name request) :: rest | None => rest end)
 [] [Freeze;Unfreeze;Stop;Interrupt;Archive].
Definition control_changes (command : control) (task : task) : list TaskChange.edit :=
 match control_target command task with
 | None => []
 | Some _ => match command with
   | Freeze => [TaskChange.ChangeStatus TaskChange.FrozenStatus]
   | Unfreeze => [TaskChange.ChangeStatus TaskChange.RunningStatus]
   | Stop => [TaskChange.ChangeStatus TaskChange.StoppedStatus]
   | Interrupt => [TaskChange.AppendHistory
       (unknown_operations (task_operations task) ++ History.interrupted_phase (task_activity task));
       TaskChange.ChangeStatus TaskChange.StoppedStatus; TaskChange.ChangePhase Idle; TaskChange.ClearOperations]
   | Archive => [TaskChange.AppendHistory
       (History.interrupted_phase (task_activity task) ++ unknown_operations (task_operations task));
       TaskChange.ChangeStatus TaskChange.ArchivedStatus; TaskChange.ClearOperations]
   end
 end.
Definition control_task (command : control) (task : task) := TaskChange.apply (control_changes command task) task.
Definition control_effects (id : N) (command : control) (task : task) :=
 match command with
 | Freeze | Unfreeze => []
 | Stop => []
 | Interrupt | Archive => [CancelTask id]
 end.
Definition control_command (id : N) (command : control) (value : world) :=
 match TaskScope.select id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some target => let task := TaskScope.selected target in match control_target command task with
   | None => reject "invalid_transition" "This lifecycle control is unavailable for the task" value
   | Some _ => accept (JObject [("task_id", number id)])
      (TaskChange.interpret (TaskChange.Plan value target (control_changes command task))) (control_effects id command task)
   end end.
Definition steer_result (id : N) (contents : content) (value : world) :=
 match TaskScope.select id value with
 | None => CommandResult.refuse "task_not_found" "The target task does not exist"
 | Some target => let task := TaskScope.selected target in match task_lifecycle task with
   | Archived _ => CommandResult.refuse "invalid_arguments" "Archived tasks cannot accept input"
   | current => if content_nonempty contents then
     let changes := [TaskChange.AppendHistory
       (History.interrupted_phase (task_activity task) ++ [UserMessage contents]);
       TaskChange.ChangeStatus (match current with Frozen _ _ => TaskChange.FrozenStatus
        | _ => TaskChange.RunningStatus end); TaskChange.ChangePhase WantsModel] in
     CommandResult.Accepted (CommandResult.Change (JObject [("task_id",number id)])
       (TaskChange.interpret (TaskChange.Plan value target changes)) (inference_effects id task))
     else CommandResult.refuse "invalid_arguments" input_required_message
   end end.
Definition steer (id : N) (contents : content) (value : world) :=
 CommandResult.decide value (steer_result id contents value).
Definition promote_changes (task : task) : list TaskChange.edit :=
 match task_lifecycle task, task_queued task with
 | Running Idle operations, first :: rest | Running (PendingCalls []) operations, first :: rest
 | Running WantsModel operations, first :: rest =>
   [TaskChange.ChangePhase WantsModel; TaskChange.ReplaceQueued [];
    TaskChange.AppendHistory (map UserMessage (first :: rest))]
 | Stopped Idle operations, first :: rest | Stopped (PendingCalls []) operations, first :: rest =>
   [TaskChange.ChangePhase Idle; TaskChange.ReplaceQueued [];
    TaskChange.AppendHistory (map UserMessage (first :: rest))]
 | _,_ => [] end.
Definition promote (task : task) := TaskChange.apply (promote_changes task) task.
Definition wake_after_result_changes (task : task) : list TaskChange.edit :=
 match task_lifecycle task with
 | Running Idle _ | Frozen Idle _ => [TaskChange.ChangePhase WantsModel]
 | _ => promote_changes task end.
Definition wake_after_result (task : task) := TaskChange.apply (wake_after_result_changes task) task.
(* A result transition records whether it calls the shared wake operation.
   Its interpreter also preserves that demand when maintenance temporarily
   owns the task's ObservingContext phase. Callers cannot separate those two
   consequences of an actual wake. *)
Inductive result_update := KeepDemand (changes : list TaskChange.edit) | WakeDemand (changes : list TaskChange.edit).
Definition result_changes (update : result_update) (current : task) := match update with
 | KeepDemand changes => changes
 | WakeDemand changes => changes ++ wake_after_result_changes (TaskChange.apply changes current) end.
Definition prefix_result (prefix : list TaskChange.edit) (update : result_update) := match update with
 | KeepDemand changes => KeepDemand (prefix ++ changes)
 | WakeDemand changes => WakeDemand (prefix ++ changes) end.
Definition wake_context_entry (owner ticket : N) (pair : N * Selvedge.Features.CompactionTypes.entry) :=
 let '(id,entry) := pair in
 if N.eqb owner id then match Selvedge.Features.CompactionTypes.entry_job entry with
   | Selvedge.Features.CompactionTypes.AwaitingContext expected purpose demand =>
     if N.eqb ticket expected then (id, set Selvedge.Features.CompactionTypes.entry_job
       (fun _ => Selvedge.Features.CompactionTypes.AwaitingContext expected purpose true) entry) else pair
   | _ => pair end else pair.
Definition mark_context_wake (owner : N) (current : task) (value : world) :=
 match task_lifecycle current with
 | Running (ObservingContext ticket _) _ | Frozen (ObservingContext ticket _) _ =>
   let features := world_features value in
   let state := Selvedge.Features.Domain.feature_compaction features in
   let entries := map (wake_context_entry owner ticket) (Selvedge.Features.CompactionTypes.maintenance_entries state) in
   with_features (Selvedge.Features.State.with_compaction
     (set Selvedge.Features.CompactionTypes.maintenance_entries (fun _ => entries) state) features) value
 | _ => value end.
Definition apply_result (owner : N) (current : task) (update : result_update) (before : world) :=
 let value := put_task owner (TaskChange.apply (result_changes update current) current) before in
 match update with
 | KeepDemand _ => value
 | WakeDemand _ => mark_context_wake owner current value end.
Definition interpret_result {before} (target : TaskScope.task_reference before) (update : result_update) :=
 apply_result (TaskScope.owner target) (TaskScope.selected target) update before.
Definition commit_result (id : N) (update : task -> result_update) (before : world) :=
 match TaskScope.select id before with
 | Some target => interpret_result target (update (TaskScope.selected target))
 | None => before end.
Definition cancel_operation (id operation_id : N) (value : world) :=
 match TaskScope.select id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some target => let task := TaskScope.selected target in
   match find (fun operation => N.eqb operation_id (Domain.operation_id operation)) (task_operations task) with
   | None => reject "operation_not_found" "The operation is not live in this task" value
   | Some operation =>
     let changes := [TaskChange.CancelOperation operation] in
     accept (JObject [("task_id", number id); ("operation_id", number operation_id)])
      (interpret_result target (WakeDemand changes))
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
Record native_call := NativeCall {
 native_owner : N; native_invocation : call; native_remaining : list call
}.
Inductive fork_entry := ManualFork | AcceptedNativeFork (invocation : call) (remaining : list call).
Definition fork_parent_ready (entry : fork_entry) (task : task) :=
 match entry, task_lifecycle task with
 | ManualFork, Running Idle _ => true
 | AcceptedNativeFork _ _, Running (PendingCalls _) _
 | AcceptedNativeFork _ _, Running (ReadyForHooks _ _ _) _
 | AcceptedNativeFork _ _, Stopped (PendingCalls _) _
 | AcceptedNativeFork _ _, Stopped (ReadyForHooks _ _ _) _ => true
 | _, _ => false end.
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
 let inherited := selected_context_history settings parent
   (if side then History.snapshot_history parent_id parent else History.snapshot_operations parent_id parent) in
 (* Keep birth guidance in provider history, outside the side return cursor. *)
 if side then inherited ++ [SideConversationBirth owner parent_id
   (N.succ (N.of_nat (List.length inherited)))] else inherited.
Definition optional_input (contents : option content) :=
 match contents with Some contents => [UserMessage contents] | None => [] end.
Definition side_input (contents : content) := if content_nonempty contents then Some contents else None.
Definition fork_child (owner parent_id : N) (parent : task) (contents : option content) (settings : task_settings)
 (side : bool) :=
 let chosen := task_current_profile parent in
 let contract := Contract chosen (contract_tools (task_contract parent)) settings
  (contract_max_fork (task_contract parent)) (contract_max_descendants (task_contract parent))
  (contract_plugins (task_contract parent)) (contract_reviewers (task_contract parent)) in
 Task contract chosen settings
 (Running (match contents with Some _ => WantsModel | None => Idle end) [])
 (fork_child_history owner parent_id parent settings side ++ optional_input contents) []
 (parent_id :: task_lineage parent)
 (if side then Some parent_id else None)
 (if side then N.of_nat (List.length (fork_child_history owner parent_id parent settings side)) else 0) 0.
Definition fork_child_receipt (entry : fork_entry) (start owner : N) (invocation : call) (child : task) :=
 let child := with_history (History.fork_receipt_history
   (ForkReceipt owner invocation (N.succ (owner-start)%N)) (task_history child)) child in
 with_activity (match entry with
 | ManualFork => WantsModel
 | AcceptedNativeFork _ remaining => match remaining with
   | [] => WantsModel | _ => PendingCalls (map Domain.recovery_call remaining) end end) child.
(* This fork owns its ordered birth suffix before feature maintenance can
   append independent roots to the same registry. *)
Fixpoint constructed_children (count : nat) (id : N) (parent : task) (messages : list content)
 (settings : task_settings) (entry : fork_entry) (start owner : N) (invocation : call) : list task :=
 match count with
 | O => []
 | S count =>
   let message := hd_error messages in
   fork_child_receipt entry start owner invocation
     (fork_child owner id parent message settings false) ::
   constructed_children count id parent (tl messages) settings entry start (N.succ owner) invocation
 end.
Definition fork_children (count : nat) (id : N) (parent : task) (messages : list content)
 (settings : task_settings) (entry : fork_entry) (start : N) (invocation : call) (value : world) : world :=
 with_tasks (world_tasks value ++
   constructed_children count id parent messages settings entry start (next_task value) invocation) value.
Definition same_approval (left right : approval_policy) :=
 match left, right with
 | FullAccess, FullAccess | AskForApproval, AskForApproval => true
 | ReviewWith reviewer_left, ReviewWith reviewer_right => Domain.same_profile reviewer_left reviewer_right
 | _, _ => false end.

Inductive fork_settings_origin := ParentSettings | EnvironmentSettings.
Definition fork_settings_base origin (parent:task) (value:world) := match origin with
 | ParentSettings => task_current_settings parent
 | EnvironmentSettings =>
   let defaults := creation_defaults (world_environment value) in
   if match WorkspaceBinding.resolve (task_current_settings parent) value with
     | Some tree => WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree) | None => false end then
     let fixed := task_current_settings parent in
     Settings (settings_workspace fixed) (settings_project fixed) (settings_sandbox defaults)
       (settings_approval defaults) (settings_guidance fixed) (settings_worktree defaults) (settings_resource fixed)
   else defaults end.
Definition fork_selection_fixed (parent : task) (selected : task_settings) (value : world) :=
 match WorkspaceBinding.resolve (task_current_settings parent) value with
 | Some tree => if WorkspaceBackend.cloud (Selvedge.Features.Domain.worktree_backend tree) then
     Workspace.same_resource (settings_resource selected) (Some (Selvedge.Features.Domain.worktree_task tree)) &&
     Json.equal (workspace_json (settings_workspace selected)) (workspace_json (settings_workspace (task_current_settings parent))) &&
     Workspace.same_resource (settings_project selected) (settings_project (task_current_settings parent))
   else true
 | None => true end.
Record admitted_fork_selection (parent : task) (value : world) := AdmittedForkSelection {
 fork_selected : task_settings;
 fork_environment_fixed : fork_selection_fixed parent fork_selected value = true
}.
Definition admit_fork_selection (parent : task) (value : world) (selected : task_settings)
 : option (admitted_fork_selection parent value) :=
 match fork_selection_fixed parent selected value as allowed return
   fork_selection_fixed parent selected value = allowed -> option (admitted_fork_selection parent value) with
 | true => fun proof => Some (AdmittedForkSelection parent value selected proof)
 | false => fun _ => None end eq_refl.
(* A fork selects child settings; the retained parent's execution contract and operations stay its own. *)
Definition fork_message_call_ids (message : Domain.message) : list string :=
 match message with
 | FunctionCall invocation | OperationResult _ invocation _ _
 | HookReceipt _ invocation _ _ | ApprovalReceipt _ _ invocation _ _
 | ToolReceipt _ _ invocation _ _ | ForkReceipt _ invocation _ => [call_id invocation]
 | FunctionOutput identity _ _ => [identity]
 | _ => [] end.
Definition fork_call_ids (task : Domain.task) : list string :=
 flat_map fork_message_call_ids (task_history task) ++
 map call_id (History.pending_invocations (task_activity task)) ++
 map (fun operation => call_id (operation_call operation)) (task_operations task).
Definition manual_fork_identity (ticket : N) (task : Domain.task) : string :=
 FreshNames.fresh_name ("manual-fork-" ++ number_text ticket ++ "-") (fork_call_ids task).

Definition fork_refusal_reason (entry : fork_entry) (id count : N) (parent : task) (value : world) :=
 match entry with
 | ManualFork => if fork_parent_ready entry parent then
     CommandResult.Refusal "resource_limit" "Fork count, aligned messages, or an ancestor descendant limit is invalid"
   else CommandResult.Refusal "task_busy" "A manual fork requires an active, idle task"
 | AcceptedNativeFork _ _ => start_refusal NativeForkEntry
     (if ancestors_fit (id :: task_lineage parent) count value then InvalidForkRequest else DescendantCapacity)
 end.
Definition fork_result (entry : fork_entry) (origin:fork_settings_origin) (id count : N)
 (messages : list content) (settings : option json) (value : world) :=
 match TaskScope.select id value with
 | None => CommandResult.refuse "task_not_found" "The parent task does not exist"
 | Some target => let task := TaskScope.selected target in
   if fork_parent_ready entry task &&
    TaskConstraints.fork_count_valid count (contract_max_fork (task_contract task)) &&
    TaskConstraints.fork_messages_valid count (List.length messages) &&
    ancestors_fit (id :: task_lineage task) count value then
    match resolve_settings (task_current_profile task) settings (fork_settings_base origin task value) value with
    | None => CommandResult.refuse "invalid_settings" "Child settings do not resolve to a current workspace"
    | Some selected => match admit_fork_selection task value selected with
      | None => CommandResult.refuse "cloud_workspace_fixed" "A cloud task keeps its bound workspace; forks inherit that environment"
      | Some selection =>
      let selected := fork_selected task value selection in
      if match entry with ManualFork => false | AcceptedNativeFork _ _ =>
        negb (Workspace.may_delegate selected (task_current_settings task) && no_resource_observation settings) end then
       CommandResult.Rejected (start_refusal NativeForkEntry AuthorityExpansion) else
      let '(ticket, allocated) := allocate_ticket value in
      let invocation := match entry with
       | AcceptedNativeFork invocation _ => invocation
       | ManualFork => Call (manual_fork_identity ticket task) "fork_task"
         (JObject [("child_count",number count);("messages",JArray (map content_json messages))]) InitialAttempt end in
      let retained := match entry with ManualFork =>
        with_ticket (world_next_ticket allocated) (TaskChange.interpret (TaskChange.Plan value target
          [TaskChange.AppendHistory [FunctionCall invocation; ForkReceipt id invocation 0]; TaskChange.ChangePhase WantsModel]))
        | _ => value end in
      let children := fork_children (N.to_nat count) id
        (match entry with ManualFork => append_history [FunctionCall invocation] task | _ => task end)
        messages selected entry (next_task value) invocation retained in
      CommandResult.Accepted (CommandResult.Change (JObject [("children", JArray (map (fun offset => number (next_task value + N.of_nat offset)) (seq 0 (N.to_nat count))))]) children [])
      end
    end
   else CommandResult.Rejected (fork_refusal_reason entry id count task value)
 end.
Definition fork_refusal (entry : fork_entry) (id count : N) (parent : task) (value : world) :=
 CommandResult.reject value (fork_refusal_reason entry id count parent value).
Definition fork_with_caller (entry : fork_entry) (origin:fork_settings_origin) (id count : N)
 (messages : list content) (settings : option json) (value : world) :=
 CommandResult.decide value (fork_result entry origin id count messages settings value).
Definition fork := fork_with_caller ManualFork ParentSettings.
Definition open_side (id : N) (contents : content) (value : world) :=
 match find_task id value with
 | None => reject "task_not_found" "The parent task does not exist" value
 | Some task => if String.eqb (task_status task) "archived" then
   reject "side_unavailable" "Archived tasks cannot create a side conversation" value
   else if ancestors_fit (id :: task_lineage task) 1 value then
   accept (JObject [("task_id", number (next_task value)); ("parent_task_id", number id)])
    (append_task (fork_child (next_task value) id task (side_input contents) (task_current_settings task) true) value) []
   else reject "side_unavailable" "The parent task has no remaining descendant capacity" value
 end.
(* The wire approval DTO names its reviewer. An explicit selection can replace
   the frozen profile behind that same key, so wire equality is insufficient. *)
Definition execution_reasoning (effort : option string) (current : profile) :=
 match effort with
 | Some value => if String.eqb value "default" then Some (with_reasoning (profile_default current) current)
   else selected_reasoning effort current
 | None => selected_reasoning effort current end.

Definition configure_execution_with (normalize : task_settings -> task_settings) (id : N)
 (name reasoning : option string) (sandbox_source approval_source : option json) (value : world) :=
 match TaskScope.select id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some target => let task := TaskScope.selected target in
   let current := task_current_settings task in
   let model := match name with
    | None => Some (task_current_profile task)
    | Some name => find_profile name (environment_profiles (world_environment value)) end in
   (* Reviewer selection precedes model, reasoning and busy failures. Omitted
      fields retain the captured settings rather than re-resolving defaults. *)
   let reviewer_model := match model with Some selected => selected
     | None => task_current_profile task end in
   match match approval_source with
    | None => Some (settings_approval current)
    | Some source => parse_approval reviewer_model (environment_profiles (world_environment value)) source end with
   | None => refuse_start Configuration InvalidPolicy value
   | Some approval => match model with
     | None => refuse_start Configuration UnknownProfile value
     | Some profile => match execution_reasoning reasoning profile with
       | None => refuse_start Configuration InvalidReasoning value
       | Some chosen => match match sandbox_source with
         | None => Some (settings_sandbox current)
         | Some source => parse_sandbox_patch (settings_sandbox current) source end with
         | None => reject "invalid_settings" "Sandbox settings do not satisfy the domain protocol" value
         | Some sandbox =>
           if quiescent task && negb (String.eqb (task_status task) "archived") &&
            (match History.history_lease id (task_history task) with History.NoLease => true | _ => false end) then
           let settings := normalize (Settings (settings_workspace current) (settings_project current)
            sandbox approval (settings_guidance current) (settings_worktree current) (settings_resource current)) in
           let same := Domain.same_profile chosen (task_current_profile task) &&
             Json.equal (settings_json settings) (settings_json current) &&
             same_approval (settings_approval settings) (settings_approval current) in
           let receipt := if same then None else
             Some [SettingsMessage settings (profile_key chosen) (profile_reasoning chosen)] in
           accept (JObject [("task_id", number id)])
            (TaskChange.configure target chosen settings receipt)
            (if same then [] else [ResetModelSession id])
           else reject "task_busy" "Execution settings require a quiescent unarchived task without a live reasoning lease" value
         end
       end
     end
   end
 end.

Definition configure_execution := configure_execution_with (fun settings=>settings).
