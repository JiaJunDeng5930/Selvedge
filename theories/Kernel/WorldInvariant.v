From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8 TextJson.
From Selvedge.Kernel Require Import Numbers Domain Codec State Configuration Workspace
 Tasks Context ContextSelection ContextUpdates Inputs Callbacks Scheduler Capabilities Limits PluginProtocol ChatgptArguments HookRules.
From Selvedge.Features Require Import Domain Titles TitleRuntime Board Remote Chatgpt TaskGraph Work Compaction CompactionTypes.
Module F := Selvedge.Features.Domain.
Module C := Selvedge.Features.CompactionTypes.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition same_values {A : Type} (encode : A -> json) (left right : list A) :=
 Json.equal (JArray (map encode left)) (JArray (map encode right)).
Definition same_call (left right : Domain.call) := Json.equal (call_json left) (call_json right).
Definition same_reference := PluginProtocol.same_reference.
Definition same_references := same_values PluginProtocol.reference_json.
Definition unique_tickets (tickets : list N) := Nat.eqb (List.length tickets)
 (List.length (nodup N.eq_dec tickets)).

Definition profile_valid (value : Domain.profile) :=
 match parse_profile (profile_metadata value) with
 | None => false
 | Some original =>
   String.eqb (profile_key value) (profile_key original) &&
   String.eqb (profile_provider value) (profile_provider original) &&
   String.eqb (profile_model value) (profile_model original) &&
   same_values JString (profile_reasoning_options value) (profile_reasoning_options original) &&
   Json.equal (reasoning_policy_json (profile_policy value)) (reasoning_policy_json (profile_policy original)) &&
   match Tasks.selected_reasoning (Some (profile_reasoning value)) original with
   | Some selected => String.eqb (profile_reasoning value) (profile_reasoning selected) | None => false end
 end.
Definition tools_valid (tools : list tool) :=
 forallb (fun tool => nonempty (tool_name tool)) tools && Schema.unique_names (map tool_name tools).
Definition plugins_valid (plugins : list json) :=
 forallb Configuration.valid_plugin plugins && N.leb (N.of_nat (List.length plugins)) Limits.plugin_limit &&
 Schema.unique_names (map (fun plugin => text_default "name" (value_or_null "reference" plugin) "") plugins).
Definition profiles_valid (profiles : list Domain.profile) :=
 forallb profile_valid profiles && Schema.unique_names (map profile_key profiles).
Definition approval_valid (value : Domain.approval_policy) := match value with
 | ReviewWith reviewer => profile_valid reviewer | _ => true end.
Definition settings_valid (value : Domain.task_settings) :=
 Workspace.valid_workspace (settings_workspace value) && valid_guidance (settings_guidance value) &&
 guidance_member (settings_workspace value) (settings_guidance value) && approval_valid (settings_approval value).
Definition environment_valid (value : Domain.environment) :=
 profiles_valid (environment_profiles value) && tools_valid (environment_tools value) &&
 forallb (fun tool => match tool_origin tool with ExtensionToolSource _ reference _ =>
   Capabilities.plugin_present reference (environment_plugins value) | _ => true end) (environment_tools value) &&
 plugins_valid (environment_plugins value) &&
 ((0 <? environment_max_fork value) && (0 <? environment_max_descendants value))%N &&
 valid_guidance (environment_project value) &&
 Configuration.valid_instructions (JObject [("configured",JString (environment_instructions value));
   ("global",match environment_global_instructions value with Some source => source | None => JNull end)]).
Definition contract_valid (value : Domain.contract) :=
 profile_valid (contract_profile value) && tools_valid (contract_tools value) &&
 forallb (fun tool => match tool_origin tool with ExtensionToolSource _ reference _ =>
   Capabilities.plugin_present reference (contract_plugins value) | _ => true end) (contract_tools value) &&
 plugins_valid (contract_plugins value) && settings_valid (contract_settings value) &&
 ((0 <? contract_max_fork value) && (0 <? contract_max_descendants value))%N.
Definition inherited_creation (child parent : Domain.contract) :=
 same_values tool_json (contract_tools child) (contract_tools parent) &&
 N.eqb (contract_max_fork child) (contract_max_fork parent) &&
 N.eqb (contract_max_descendants child) (contract_max_descendants parent) &&
 same_values (fun value => value) (contract_plugins child) (contract_plugins parent).
Definition lineage_valid (id : N) (value : Domain.task) (state : world) :=
 match task_lineage value with
 | [] => true
 | parent :: tail => match find_task parent state with
   | None => false
   | Some original => (parent <? id)%N &&
     same_values number tail (task_lineage original) &&
     inherited_creation (task_contract value) (task_contract original)
   end
 end.
Definition project_valid (value : Domain.project) :=
 if project_deleted value then true else Workspace.valid_project_name (project_name value) && Workspace.valid_workspace (project_workspace value) &&
 valid_guidance (Domain.project_guidance value) && guidance_member (project_workspace value) (Domain.project_guidance value).
Definition project_binding (settings : Domain.task_settings) (state : world) := match settings_project settings with
 | None => true | Some id => match registry_at id (world_projects state) with Some project => negb (project_deleted project) | None => false end end.

Definition phase_tickets (phase : Domain.activity) := match phase with
 | ObservingContext ticket _ | AskingModel ticket _ _ | EvaluatingReasoning ticket _
 | CheckingHook ticket _ _ _ _ => [ticket] | _ => [] end.
Definition operation_tickets (value : Domain.operation) :=
 operation_id value :: match operation_stage value with
 | Executing ticket | AwaitingApproval ticket _ => if N.eqb ticket (operation_id value) then [] else [ticket]
 | Elevated ticket _ | AwaitingAfterHook ticket _ _ _ _ => if N.eqb ticket (operation_id value) then [] else [ticket]
 | Granted _ | AfterHooksReady _ _ _ => [] end.
Definition task_tickets (value : Domain.task) :=
 phase_tickets (task_activity value) ++ flat_map operation_tickets (task_operations value).
Definition phase_calls (phase : Domain.activity) := match phase with
 | PendingCalls calls => calls
 | ReadyForHooks invocation _ calls | CheckingHook _ _ invocation _ calls => invocation :: calls
 | _ => [] end.
Definition call_open (history : list Domain.message) (invocation : Domain.call) :=
 Callbacks.call_known (call_id invocation) history &&
 negb (ContextSelection.has_output history (call_id invocation)).
Definition calls_valid (history : list Domain.message) (calls : list Domain.call) :=
 forallb (call_open history) calls && Schema.unique_names (map call_id calls).
Definition phase_valid (value : Domain.task) :=
 let phase := task_activity value in
 calls_valid (task_history value) (phase_calls phase) &&
 match phase with
 | AskingModel _ names _ => Schema.unique_names names && forallb (fun name =>
   match find_tool name (contract_tools (task_contract value)) with Some _ => true | None => false end) names
 | ObservingContext _ revision => Nat.leb revision (List.length (task_history value))
 | EvaluatingReasoning _ revision => Nat.leb revision (List.length (task_history value)) &&
   match profile_policy (task_current_profile value) with AdaptivePolicy _ => true | _ => false end
 | _ => true end.

(* The ordered receipts certify the pending before-hook suffix. A rewrite changes
   the current invocation only after the receipt for its original arguments. *)
Inductive hook_progress := HookAbsent | HookWaiting (invocation : Domain.call) (pending : list json) | HookRefused.
Definition hook_step (owner : N) (identity : string) (chain : list json)
 (progress : hook_progress) (entry : Domain.message) := match entry with
 | FunctionCall invocation => if String.eqb identity (call_id invocation) then
   match progress with HookAbsent => HookWaiting invocation chain | _ => HookRefused end else progress
 | HookReceipt actual invocation plugin outcome =>
   if N.eqb actual owner && String.eqb identity (call_id invocation) then
   match progress with
   | HookWaiting expected (first :: rest) =>
     if same_call invocation expected && same_reference first plugin then
     match HookRules.parse_hook outcome with
     | Some outcome => match HookRules.before_apply invocation outcome with
       | HookRules.Proceed updated => HookWaiting updated rest
       | HookRules.Refuse _ _ => HookRefused end
     | None => HookRefused end else HookRefused
   | _ => HookRefused end else progress
 | _ => progress end.
Definition hooks_correspond (owner : N) (value : Domain.task) (invocation : Domain.call) (pending : list json) :=
 match fold_left (hook_step owner (call_id invocation) (Scheduler.before_plugins value))
   (task_history value) HookAbsent with
 | HookWaiting expected rest => same_call invocation expected && same_references pending rest
 | _ => false end.
(* A pending generation retains its sampling certificate even when later user
   input or another operation completes. Lease reuse has a different lifetime. *)
Definition sampled_reasoning (owner : N) (value : Domain.task) :=
 match profile_policy (task_current_profile value) with
 | FixedReasoning => true
 | AdaptivePolicy policy =>
   let sampled := fold_left (fun previous entry => match entry with
   | ReasoningRecord actual effort remaining generation =>
     N.eqb owner actual && generation && Reasoning.allowed policy effort && (remaining <? reasoning_max_lease policy)%N
   | _ => previous end) (task_history value) false in
   let effective := match reasoning_transport_mode policy with
   | ConfigurationUpdates => match Reasoning.last_configuration (task_history value) with
     | Some effort => effort | None => reasoning_baseline policy end
   | RequestEffort => fold_left (fun previous entry => match entry with
     | ReasoningRecord actual effort _ true => if N.eqb owner actual then effort else reasoning_baseline policy
     | ContextReplacement _ => reasoning_baseline policy
     | ModelContext _ content => if String.eqb (text_default "type" (Conversation.provider_value content) "") "compaction"
       then reasoning_baseline policy else previous
     | _ => previous end) (task_history value) (reasoning_baseline policy)
   end in sampled && Reasoning.allowed policy effective
 end.
Definition checked_phase (owner : N) (value : Domain.task) := match task_activity value with
 | AskingModel _ _ _ => sampled_reasoning owner value
 | ReadyForHooks invocation pending _ => hooks_correspond owner value invocation pending
 | CheckingHook _ plugin invocation pending _ =>
   match find_tool (call_name invocation) (contract_tools (task_contract value)) with
   | Some _ => hooks_correspond owner value invocation (plugin :: pending) | None => false end
 | _ => true end.

(* A later receipt for the same operation revokes an earlier grant. Other
   owners and operations cannot certify this operation's authority. *)
Definition approval_corresponds (owner : N) (value : Domain.task) (operation : Domain.operation) (reviewed_by : Domain.reviewer) :=
 match fold_left (fun previous entry => match entry with
 | ApprovalReceipt actual identity invocation reviewer outcome =>
   if N.eqb actual owner && N.eqb identity (operation_id operation)
   then Some (invocation,reviewer,outcome) else previous
 | _ => previous end) (task_history value) None with
 | Some (invocation,reviewer,outcome) => same_call invocation (operation_call operation) &&
   Json.equal (reviewer_json reviewer) (reviewer_json reviewed_by) &&
   String.eqb (text_default "decision" outcome "") "allow"
 | None => false end.
Definition review_right (value : Domain.task) (operation : Domain.operation) (reviewed_by : Domain.reviewer) :=
 let invocation := operation_call operation in
 String.eqb (call_name invocation) "bash" &&
 String.eqb (text_default "sandbox_permissions" (call_arguments invocation) "") "require_escalated" &&
 match find_tool (call_name invocation) (contract_tools (task_contract value)) with
 | Some tool => match tool_origin tool with NativeToolSource _ _ =>
   Callbacks.model_call_arguments_valid tool invocation &&
   match settings_approval (task_current_settings value),reviewed_by with
   | AskForApproval,HumanReviewer => true
   | ReviewWith expected,ModelReviewer actual => Domain.same_profile expected actual
   | _,_ => false end
   | _ => false end
 | None => false end.

Inductive result_progress := ResultAbsent | ResultWaiting (value : json) (error : bool) (pending : list json) | ResultRefused.
Definition after_step (owner : N) (operation : Domain.operation) (chain : list json)
 (progress : result_progress) (entry : Domain.message) := match entry with
 | ToolReceipt actual identity invocation value error =>
   if N.eqb actual owner && N.eqb identity (operation_id operation) then
   match progress with ResultAbsent =>
     if same_call invocation (operation_call operation) then ResultWaiting value error chain else ResultRefused
   | _ => ResultRefused end else progress
 | AfterReceipt actual identity plugin outcome =>
   if N.eqb actual owner && N.eqb identity (operation_id operation) then
   match progress with ResultWaiting value error (first :: rest) =>
     if same_reference first plugin then match HookRules.parse_after outcome with
     | Some outcome => match HookRules.after_apply value outcome with
       | HookRules.ContinueResult updated => ResultWaiting updated error rest
       | HookRules.RefuseResult _ _ => ResultRefused end
     | None => ResultRefused end else ResultRefused
   | _ => ResultRefused end else progress
 | _ => progress end.
Definition results_correspond (owner : N) (value : Domain.task) (operation : Domain.operation)
 (result : json) (error : bool) (pending : list json) :=
 match fold_left (after_step owner operation (Callbacks.after_plugins value)) (task_history value) ResultAbsent with
 | ResultWaiting actual failed remaining => Json.equal actual result && Bool.eqb error failed &&
   same_references pending remaining
 | _ => false end.
Definition operation_history (value : Domain.task) (operation : Domain.operation) :=
 if operation_announced operation then
 existsb (fun entry => match entry with
 | FunctionOutput identity result false =>
   String.eqb identity (call_id (operation_call operation)) &&
   (Json.equal result (Scheduler.operation_notice (Operation (operation_id operation) (operation_call operation) true (Executing (operation_id operation)))) ||
    match settings_approval (task_current_settings value) with
    | FullAccess => false
    | policy => let reviewer := match policy with ReviewWith model => ModelReviewer model | _ => HumanReviewer end in
      Json.equal result (Scheduler.operation_notice (Operation (operation_id operation) (operation_call operation) true (AwaitingApproval (operation_id operation) reviewer))) ||
      Json.equal result (Scheduler.operation_notice (Operation (operation_id operation) (operation_call operation) true (Granted reviewer))) end)
 | _ => false end) (task_history value)
 else call_open (task_history value) (operation_call operation).
Definition operation_stage_valid (owner : N) (value : Domain.task) (operation : Domain.operation) :=
 match operation_stage operation with
 | Executing ticket => N.eqb ticket (operation_id operation)
 | AwaitingApproval ticket reviewer => N.eqb ticket (operation_id operation) && review_right value operation reviewer
 | Granted reviewer => review_right value operation reviewer && approval_corresponds owner value operation reviewer
 | Elevated ticket reviewer =>
   match settings_approval (task_current_settings value) with
   | FullAccess => (operation_id operation <=? ticket)%N
   | _ => (operation_id operation <? ticket)%N && review_right value operation reviewer &&
     approval_corresponds owner value operation reviewer end
 | AfterHooksReady pending result error => results_correspond owner value operation result error pending
 | AwaitingAfterHook ticket plugin pending result error =>
   (operation_id operation <? ticket)%N && results_correspond owner value operation result error (plugin :: pending)
 end.
Definition operations_valid (owner : N) (value : Domain.task) :=
 N.leb (N.of_nat (List.length (task_operations value))) Limits.operation_limit &&
 Schema.unique_names (map call_id (phase_calls (task_activity value)) ++
   map (fun operation => call_id (operation_call operation)) (task_operations value)) &&
 forallb (fun operation =>
   hooks_correspond owner value (operation_call operation) [] &&
   operation_history value operation && operation_stage_valid owner value operation &&
   match find_tool (call_name (operation_call operation)) (contract_tools (task_contract value)) with
   | Some _ => true | None => false end) (task_operations value).
Definition task_valid (owner : N) (value : Domain.task) (state : world) :=
 contract_valid (task_contract value) && profile_valid (task_current_profile value) &&
 settings_valid (task_current_settings value) &&
 forallb ContextUpdates.valid_snapshot (ContextUpdates.bindings (task_history value)) &&
 project_binding (contract_settings (task_contract value)) state && project_binding (task_current_settings value) state &&
 lineage_valid owner value state &&
 N.leb (Tasks.descendant_count owner (world_tasks state)) (contract_max_descendants (task_contract value)) &&
 phase_valid value && checked_phase owner value && operations_valid owner value.
Fixpoint tasks_valid (owner : N) (entries : list Domain.task) (state : world) := match entries with
 | [] => true | value :: rest => task_valid owner value state && tasks_valid (N.succ owner) rest state end.

Definition character_limit (text : string) (limit : N) := match Utf8.scalar_count text with
 | Some count => N.leb (N.of_nat count) limit | None => false end.
Definition present {A : Type} (value : option A) := match value with Some _ => true | None => false end.
Definition within_u32 (value : N) := (value <=? 4294967295)%N.
Definition registry_bound {A : Type} (entries : list A) := within_u32 (N.of_nat (List.length entries)).
Definition title_valid (value : F.title_entry) (state : world) :=
 present (find_task (F.title_task value) state) &&
 match F.title_value value with
 | F.TitlePending ticket selected prompt => (ticket <? world_next_ticket state)%N &&
   profile_valid selected && TitleRuntime.capable selected &&
   N.leb (N.of_nat (String.length prompt))
     (Titles.maximum_instruction_bytes + N.of_nat (String.length Titles.title_format) +
       (Titles.prompt_bytes - N.of_nat (String.length (Titles.instructions ++ Titles.title_format))))%N
 | F.Named title => nonempty title && character_limit title (N.of_nat Titles.maximum_characters)
 | F.TitleFailed _ => true end.
Definition titles_valid (state : world) :=
 let features := world_features state in let settings := F.feature_title_settings features in
 Titles.valid_instructions (F.title_task_prompt settings) && Titles.valid_instructions (F.title_agent_prompt settings) &&
 unique_tickets (map F.title_task (F.feature_titles features)) &&
 forallb (fun value => title_valid value state) (F.feature_titles features).
Definition remote_valid := Remote.valid.
Definition tree_owner_valid (entry : F.worktree) (state : world) :=
 Workspace.valid_path (F.worktree_source entry) &&
 (match F.worktree_root entry with Some root => Workspace.valid_path root | None => true end) &&
 match find_task (F.worktree_task entry) state with
 | None => false | Some task =>
   match F.worktree_phase entry,task_lifecycle task with
   | F.TreeCreating false,Frozen _ [] | F.TreeCreating true,Archived _ => true
   | F.TreeCreateFailed _ _,Stopped Idle [] | F.TreeCreateFailed _ _,Archived _ => true
   | F.TreeArchiving _ _,Archived _ | F.TreeArchiveFailed _ _ _,Archived _ | F.TreeArchived _ _,Archived _ => true
   | F.TreeReady _ _,_ => true | _,_ => false end
 end.
Definition worktrees_valid (state : world) :=
 unique_tickets (map F.worktree_task (F.feature_worktrees (world_features state))) &&
 forallb (fun entry => tree_owner_valid entry state) (F.feature_worktrees (world_features state)).

Definition stored_agent_valid (value : F.board_agent) :=
 Board.agent_name_valid (F.agent_name value) && Board.agent_profile_valid (F.agent_profile value) &&
 Board.agent_reasoning_valid (F.agent_reasoning value) && Board.agent_instructions_valid (F.agent_instructions value) &&
 Board.agent_concurrency_valid (F.agent_concurrency value).
Definition card_valid (value : F.card) (state : world) :=
 Board.valid_draft (F.card_contents value) state &&
 (match F.draft_owner (F.card_contents value) with F.ProfileOwner key => Board.agent_profile_valid key | _ => true end) &&
 forallb (fun attachment => present (BoardParameters.attachment (Selvedge.Features.Observation.attachment_json attachment)))
   (F.draft_attachments (F.card_contents value)) && BoardParameters.limited (F.card_start_error value) 4096 &&
 (match F.card_task value with Some id => present (find_task id state) | None => true end) &&
 match F.card_enrichment value with
 | F.Enriching ticket revision _ => (ticket <? world_next_ticket state)%N &&
   N.eqb revision (F.card_revision value) && negb (F.card_archived value)
 | F.EnrichmentFailed reason => BoardParameters.limited reason 4096 | _ => true end.
Definition cards_present (state : F.board) := fold_right (fun value rest => match value with Some card => card :: rest | None => rest end) [] (F.board_cards state).
Definition board_valid (state : world) :=
 let board := F.feature_board (world_features state) in let cards := cards_present board in
 Nat.leb (List.length cards) 512 &&
 Nat.leb (List.length (filter present (F.board_agents board))) 64 &&
 registry_bound (F.board_cards board) && registry_bound (F.board_agents board) &&
 forallb (fun value => card_valid value state) cards &&
 unique_tickets (flat_map (fun value => match F.card_task value with Some id => [id] | None => [] end) cards) &&
 forallb (fun value => match value with None => true | Some agent => stored_agent_valid agent end) (F.board_agents board) &&
 BoardParameters.limited (F.board_draft_profile board) 1024.

Definition sharing_valid (state : world) :=
 let sharing := F.feature_sharing (world_features state) in
 Nat.leb (List.length (F.sharing_grants sharing)) 32 &&
 unique_tickets (map F.connection_id (F.sharing_grants sharing)) &&
 forallb (fun grant => within_u32 (F.connection_id grant) &&
   Nat.leb (List.length (F.connection_projects grant)) 32 && unique_tickets (F.connection_projects grant) &&
   forallb (fun id => present (registry_at id (world_projects state))) (F.connection_projects grant)) (F.sharing_grants sharing) &&
 Nat.leb (List.length (F.sharing_jobs sharing)) 128 && within_u32 (F.sharing_next sharing) &&
 unique_tickets (map fst (F.sharing_jobs sharing)) &&
 forallb (fun entry => let '(id,job) := entry in (id <? F.sharing_next sharing)%N &&
   Remote.identifier_valid (F.job_request job) &&
   ChatgptArguments.valid_args (F.job_arguments_json job) &&
   Workspace.valid_workspace (F.job_workspace job) &&
   match F.job_state job with
   | F.JobRunning => WorkspaceBinding.resource_ready (F.job_workspace job) (F.job_resource job) state
   | _ => true end) (F.sharing_jobs sharing).
Definition graph_valid (id : N) (graph : F.task_graph) (state : world) :=
 TaskGraph.valid_declaration (F.graph_name graph)
   (map (fun node => F.ExistingNode (F.node_key node) (F.node_task node)) (F.graph_nodes graph)) (F.graph_rules graph) &&
 Nat.leb (List.length (F.graph_receipts graph)) 256 &&
 forallb (fun node => present (find_task (F.node_task node) state) &&
   TaskGraph.task_in_work (F.association id (F.feature_graph_owners (world_features state))) (F.node_task node) state) (F.graph_nodes graph).
Fixpoint graphs_valid (id : N) (entries : list (option F.task_graph)) (state : world) := match entries with
 | [] => true | graph :: rest =>
   (match graph with Some graph => graph_valid id graph state | None => true end) && graphs_valid (N.succ id) rest state end.
Definition work_valid (value : F.work) := Work.valid_name (F.work_name value) &&
 character_limit (F.work_ui_source value) 100000 && within_u32 (F.work_ui_revision value).
Definition work_owners_valid (entries : list (N * N)) (state : world) :=
 unique_tickets (map fst entries) && forallb (fun entry => within_u32 (fst entry) &&
   present (Work.lookup (snd entry) state)) entries.
Definition works_valid (state : world) := let features := world_features state in
 registry_bound (F.feature_works features) && forallb work_valid (F.feature_works features) &&
 work_owners_valid (F.feature_task_owners features) state && work_owners_valid (F.feature_graph_owners features) state &&
 forallb (fun entry => match find_task (fst entry) state with Some task =>
   match task_lineage task with [] => true | _ => false end | None => false end) (F.feature_task_owners features) &&
 forallb (fun entry => match registry_at (fst entry) (F.feature_graphs features) with Some (Some _) => true | _ => false end) (F.feature_graph_owners features).
Definition graph_registry_valid (state : world) := let features := world_features state in
 Nat.leb (List.length (filter present (F.feature_graphs features))) 32 &&
 graphs_valid 0 (F.feature_graphs features) state.

Definition job_history_valid (job : C.job) (history : list Domain.message) := match job with
 | C.NoJob | C.WaitingForResource _ | C.AwaitingContext _ _ _ => true
 | C.Resuming input _ | C.Preparing _ input _ _ | C.Compacting _ input _ _ _ | C.Validating _ input _ _ _ _ =>
   ContextSelection.history_extends (C.captured_history input) history end.
Definition maintenance_entry_valid (entry : N * C.entry) (state : world) := let '(id,entry) := entry in
 match find_task id state with None => false | Some task =>
 ((C.entry_maintained entry <=? C.entry_useful entry) &&
  (C.entry_attempted entry <=? Compaction.useful (task_history task)) &&
  (C.entry_useful entry <=? Compaction.useful (task_history task)))%N &&
 job_history_valid (C.entry_job entry) (task_history task) end.
Definition compaction_valid (state : world) :=
 let maintenance := F.feature_compaction (world_features state) in
 unique_tickets (map fst (C.maintenance_entries maintenance)) &&
 forallb (fun entry => maintenance_entry_valid entry state) (C.maintenance_entries maintenance).
Definition feature_tickets (features : F.state) :=
 flat_map (fun entry => match F.title_value entry with F.TitlePending ticket _ _ => [ticket] | _ => [] end) (F.feature_titles features) ++
 flat_map (fun value => match F.card_enrichment value with F.Enriching ticket _ _ => [ticket] | _ => [] end) (cards_present (F.feature_board features)) ++
 flat_map (fun entry =>
   (match Compaction.measurement_ticket (C.entry_measurement (snd entry)) with Some ticket => [ticket] | None => [] end) ++
   (match Compaction.provider_job_ticket (C.entry_job (snd entry)) with Some ticket => [ticket] | None => [] end)) (C.maintenance_entries (F.feature_compaction features)).
Definition features_valid (state : world) :=
 titles_valid state && remote_valid (F.feature_remote (world_features state)) && worktrees_valid state &&
 board_valid state && sharing_valid state && graph_registry_valid state && works_valid state && compaction_valid state.
Definition tickets_valid (state : world) :=
 let tickets := flat_map task_tickets (world_tasks state) ++ feature_tickets (world_features state) in
 unique_tickets tickets && forallb (fun ticket => (ticket <? world_next_ticket state)%N) tickets.
(* Journal sequence numbers do not change the domain's registry, capabilities or
   pending ownership. The original world invariant did not contain that cursor. *)
Definition world_structure (state : world) := with_sequence 0 state.
Definition projects_valid (state : world) :=
 registry_bound (world_projects state) &&
 Nat.leb (List.length (filter (fun project => negb (project_deleted project)) (world_projects state))) 256 &&
 forallb project_valid (world_projects state).
Definition world_valid (value : world) := let state := world_structure value in
 environment_valid (world_environment state) && projects_valid state &&
 tasks_valid 0 (world_tasks state) state && tickets_valid state && features_valid state.


Record well_formed (value : world) : Prop := WellFormed {
 environment_requirement : environment_valid (world_environment (world_structure value)) = true;
 projects_requirement : projects_valid (world_structure value) = true;
 tasks_requirement : tasks_valid 0 (world_tasks (world_structure value)) (world_structure value) = true;
 tickets_requirement : tickets_valid (world_structure value) = true;
 features_requirement : features_valid (world_structure value) = true
}.
Definition validate_with_status (before : world) (candidate : decision) :=
 (* DEFENSE: User commands and external callbacks can propose a candidate whose
    references, correlation ownership or execution certificates violate the
    commit contract. Reject its complete state and effects before delivery. *)
 if world_valid (decision_world candidate) then (true,candidate) else
 (false,reject "invariant_violation" "The candidate violates a world invariant; no state change or effect was committed" before).
Definition validate (before : world) (candidate : decision) :=
 snd (validate_with_status before candidate).
