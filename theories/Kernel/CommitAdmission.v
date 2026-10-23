From Stdlib Require Import String List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import Json JsonObjects Schema.
From Selvedge.Kernel Require Import Numbers Domain State Codec ContextSelection
 Dispatch Notifications Inputs Workspace WorkspaceBackend WorldInvariant CompactionPlan Reasoning SideContext.
From Selvedge.Features Require Import Domain State Observation Titles
 CompactionTypes Compaction Worktree TitleRuntime Remote.
Import ListNotations.
Open Scope string_scope.
Open Scope N_scope.

Module D := Selvedge.Kernel.Domain.
Module K := Selvedge.Kernel.State.
Module F := Selvedge.Features.Domain.
Module C := Selvedge.Features.CompactionTypes.
Module G := Selvedge.Generated.Commands.
Module Remote := Selvedge.Features.Remote.

Definition same_option_nat (left right : option N) :=
 match left, right with
 | None, None => true
 | Some first, Some second => N.eqb first second
 | _, _ => false
 end.
Definition same_strings (left right : list string) :=
 Json.equal (JArray (map JString left)) (JArray (map JString right)).
Fixpoint same_naturals (left right : list N) :=
 match left, right with
 | [], [] => true
 | first :: rest_first, second :: rest_second =>
   N.eqb first second && same_naturals rest_first rest_second
 | _, _ => false
 end.
Definition same_history (left right : list D.message) :=
 Nat.eqb (List.length left) (List.length right) &&
 ContextSelection.history_extends left right.
Definition same_content_lists (left right : list D.content) :=
 Json.equal (JArray (map Codec.content_json left)) (JArray (map Codec.content_json right)).
Definition same_call (left right : D.call) := Json.equal (Codec.call_json left) (Codec.call_json right).
Definition same_profile (left right : D.profile) :=
 Json.equal (Codec.model_json left) (Codec.model_json right) &&
 Json.equal (Codec.profile_json left) (Codec.profile_json right) &&
 Json.equal (JArray (map JString (D.profile_reasoning_options left)))
   (JArray (map JString (D.profile_reasoning_options right))) &&
 String.eqb (D.profile_reasoning left) (D.profile_reasoning right).
Definition same_tool (left right : D.tool) := Json.equal (Codec.tool_json left) (Codec.tool_json right).
Definition same_tools (left right : list D.tool) :=
 Json.equal (JArray (map Codec.tool_json left)) (JArray (map Codec.tool_json right)).
Definition same_settings (left right : D.task_settings) :=
 Json.equal (Codec.settings_json left) (Codec.settings_json right) &&
 Json.equal (D.settings_guidance left) (D.settings_guidance right) &&
 Bool.eqb (D.settings_worktree left) (D.settings_worktree right).
Definition same_reviewers (left right : list D.profile) :=
 Json.equal (JArray (map (fun value => Codec.reviewer_json (D.ModelReviewer value)) left))
   (JArray (map (fun value => Codec.reviewer_json (D.ModelReviewer value)) right)).
Definition same_reviewer (left right : D.reviewer) :=
 match left, right with
 | D.HumanReviewer, D.HumanReviewer => true
 | D.ModelReviewer first, D.ModelReviewer second => same_profile first second
 | _, _ => false
 end.
Definition same_output_mode (left right : D.output_mode) :=
 match left, right with
 | D.PlainOutput, D.PlainOutput | D.InteractiveOutput, D.InteractiveOutput => true
 | _, _ => false
 end.
Definition same_json_lists (left right : list Json.json) := Json.equal (JArray left) (JArray right).
Definition same_calls (left right : list D.call) :=
 Json.equal (JArray (map Codec.call_json left)) (JArray (map Codec.call_json right)).
Definition same_operation_state (left right : D.operation_state) :=
 match left, right with
 | D.Executing first, D.Executing second => N.eqb first second
 | D.AwaitingApproval lt lr, D.AwaitingApproval rt rr => N.eqb lt rt && same_reviewer lr rr
 | D.Granted first, D.Granted second => same_reviewer first second
 | D.Elevated lt lr, D.Elevated rt rr => N.eqb lt rt && same_reviewer lr rr
 | D.AfterHooksReady lp lv le, D.AfterHooksReady rp rv re =>
   same_json_lists lp rp && Json.equal lv rv && Bool.eqb le re
 | D.AwaitingAfterHook lt lp lr lv le, D.AwaitingAfterHook rt rp rr rv re =>
   N.eqb lt rt && Json.equal lp rp && same_json_lists lr rr && Json.equal lv rv && Bool.eqb le re
 | _, _ => false
 end.
Definition same_operation (left right : D.operation) :=
 N.eqb (D.operation_id left) (D.operation_id right) &&
 same_call (D.operation_call left) (D.operation_call right) &&
 Bool.eqb (D.operation_announced left) (D.operation_announced right) &&
 same_operation_state (D.operation_stage left) (D.operation_stage right).
Fixpoint same_operations (left right : list D.operation) :=
 match left, right with
 | [], [] => true
 | first :: rest_first, second :: rest_second =>
   same_operation first second && same_operations rest_first rest_second
 | _, _ => false
 end.
Definition same_activity (left right : D.activity) :=
 match left, right with
 | D.Idle, D.Idle | D.WantsModel, D.WantsModel | D.ReadyForModel, D.ReadyForModel => true
 | D.ObservingContext lt ll, D.ObservingContext rt rl => N.eqb lt rt && Nat.eqb ll rl
 | D.AskingModel lt ln lm, D.AskingModel rt rn rm => N.eqb lt rt && same_strings ln rn && same_output_mode lm rm
 | D.EvaluatingReasoning lt ll, D.EvaluatingReasoning rt rl => N.eqb lt rt && Nat.eqb ll rl
 | D.PendingCalls first, D.PendingCalls second => same_calls first second
 | D.ReadyForHooks li lp lc, D.ReadyForHooks ri rp rc =>
   same_call li ri && same_json_lists lp rp && same_calls lc rc
 | D.CheckingHook lt lp li lr lc, D.CheckingHook rt rp ri rr rc =>
   N.eqb lt rt && Json.equal lp rp && same_call li ri && same_json_lists lr rr && same_calls lc rc
 | _, _ => false
 end.
Definition same_lifecycle (left right : D.lifecycle) :=
 match left, right with
 | D.Running lp lo, D.Running rp ro
 | D.Frozen lp lo, D.Frozen rp ro
 | D.Stopped lp lo, D.Stopped rp ro => same_activity lp rp && same_operations lo ro
 | D.Archived, D.Archived => true
 | _, _ => false
 end.
Definition same_contract (left right : D.contract) :=
 same_profile (D.contract_profile left) (D.contract_profile right) &&
 same_tools (D.contract_tools left) (D.contract_tools right) &&
 same_settings (D.contract_settings left) (D.contract_settings right) &&
 N.eqb (D.contract_max_fork left) (D.contract_max_fork right) &&
 N.eqb (D.contract_max_descendants left) (D.contract_max_descendants right) &&
 Json.equal (JArray (D.contract_plugins left)) (JArray (D.contract_plugins right)) &&
 same_reviewers (D.contract_reviewers left) (D.contract_reviewers right).
Definition same_task_except_history (left right : D.task) :=
 same_contract (D.task_contract left) (D.task_contract right) &&
 same_profile (D.task_current_profile left) (D.task_current_profile right) &&
 same_settings (D.task_current_settings left) (D.task_current_settings right) &&
 same_lifecycle (D.task_lifecycle left) (D.task_lifecycle right) &&
 same_content_lists (D.task_queued left) (D.task_queued right) &&
 same_naturals (D.task_lineage left) (D.task_lineage right) &&
 same_option_nat (D.task_side_parent left) (D.task_side_parent right) &&
 N.eqb (D.task_side_cursor left) (D.task_side_cursor right) &&
 Nat.eqb (D.task_model_cursor left) (D.task_model_cursor right).
Definition same_task (left right : D.task) :=
 same_task_except_history left right && same_history (D.task_history left) (D.task_history right).
Definition worktree_completion_lifecycle (expected actual : D.task) :=
 match D.task_lifecycle expected, D.task_lifecycle actual with
 | D.Running D.WantsModel expected_operations,
   D.Running (D.ObservingContext _ _) actual_operations => same_operations expected_operations actual_operations
 | _, _ => same_lifecycle (D.task_lifecycle expected) (D.task_lifecycle actual)
 end.
Definition worktree_entry (owner : N) (features : F.state) :=
 find (fun entry => N.eqb owner (F.worktree_task entry)) (F.feature_worktrees features).
Definition worktree_initialization (owner : N) (before after : F.state) :=
 match worktree_entry owner before, worktree_entry owner after with
 | Some old, Some next =>
   match F.worktree_phase old, F.worktree_phase next with
   | F.TreeCreating false, F.TreeReady root primary =>
     String.eqb (F.worktree_source old) (F.worktree_source next) &&
     String.eqb (WorkspaceBackend.name (F.worktree_backend old))
       (WorkspaceBackend.name (F.worktree_backend next)) &&
     Workspace.valid_path root &&
     Workspace.valid_path primary &&
     (String.eqb primary root || String.prefix (String.append root "/") primary)
   | _, _ => false
   end
 | _, _ => false
 end.
Definition setup_history_matches (old expected next : D.task) :=
 match D.task_side_parent old with
 | None => same_history (D.task_history expected) (D.task_history next)
 | Some parent =>
   ContextSelection.history_extends (D.task_history expected) (D.task_history next) &&
   forallb (fun entry => match entry with
    | D.ContextObservation change =>
      let key := match change with ContextTypes.Introduce snapshot => ContextTypes.snapshot_key snapshot
       | ContextTypes.Amend key _ _ _ | ContextTypes.Remove key _ => key end in
      ContextUpdates.same_key key (SideContext.parent_key parent)
    | _ => false end)
    (skipn (List.length (D.task_history expected)) (D.task_history next))
 end.
Definition worktree_contract_update (owner : N) (before after : F.state)
 (old next : D.task) :=
 match D.task_lifecycle old,
  D.settings_resource (D.contract_settings (D.task_contract old)),
  D.settings_resource (D.task_current_settings old) with
 | D.Archived,_,_ => false
 | _,Some resource,Some selected =>
   N.eqb resource selected &&
   match worktree_entry resource after with
   | Some tree => match F.worktree_phase tree with
     | F.TreeReady _ primary =>
       let chosen := D.task_current_settings next in
       let space := D.settings_workspace chosen in
       let guidance := D.settings_guidance chosen in
       worktree_initialization resource before after &&
       String.eqb (Worktree.primary space) primary &&
       Json.equal (Codec.workspace_json space)
         (Codec.workspace_json (Worktree.selected_workspace primary
           (D.settings_workspace (D.task_current_settings old)))) &&
       let expected := if N.eqb owner resource then Worktree.completed_task space guidance old
         else Worktree.install_workspace (D.task_lifecycle old) space guidance old in
       same_task_except_history (D.with_lifecycle (D.task_lifecycle expected) next) expected &&
       setup_history_matches old expected next &&
       worktree_completion_lifecycle expected next
     | _ => false end
   | None => false end
 | _,_,_ => false
 end.
Definition execution_configuration_target (command : G.command) (owner : N) :=
 match command with
 | G.Cmd_configure_task_execution payload => N.eqb owner (G.configure_task_execution_task_id payload)
 | _ => false
 end.
Definition task_is_configurable (old : D.task) :=
 negb (D.task_busy old) && Nat.eqb (List.length (D.task_queued old)) 0 &&
 match D.task_lifecycle old with D.Archived => false | _ => true end.
Definition remote_execution_configuration_authorizes (raw_source : Json.json) (owner : N) (before : K.world) :=
 match string_field "kind" raw_source, Remote.parse_request true raw_source,
   field "intent" raw_source, field "command" raw_source with
 | Some kind, Some request, Some intent, Some prepared_source =>
   String.eqb kind "remote_command" &&
   match G.decode intent, G.decode prepared_source with
   | Some original, Some prepared =>
     execution_configuration_target original owner && execution_configuration_target prepared owner &&
     Remote.configuration_allowed original raw_source && Remote.configuration_allowed prepared raw_source &&
     String.eqb (Schema.command_name (G.declared_command original))
       (Schema.command_name (G.declared_command prepared)) &&
     match Remote.authorize_command true original request (Remote.registry before) with
     | Remote.Admitted => match Remote.authorize_command true prepared request (Remote.registry before) with
       | Remote.Admitted => true | _ => false end
     | _ => false end
   | _, _ => false end
 | _, _, _, _ => false
 end.
Definition configure_execution_source_authorizes (source : option input) (raw_source : Json.json)
 (owner : N) (before : K.world) (old : D.task) :=
 (match source with
  | Some (UserCommand command) => execution_configuration_target command owner
  | _ => false end || remote_execution_configuration_authorizes raw_source owner before) &&
 task_is_configurable old.
Definition operation_nonexecuting (operation : D.operation) :=
 match D.operation_stage operation with D.Executing _ | D.Elevated _ _ => false | _ => true end.
Definition archived_message (owner : N) (operations : list D.operation) (message : D.message) :=
 match message with
 | D.AfterReceipt actual operation _ _ => N.eqb owner actual &&
   match find (fun value => N.eqb operation (D.operation_id value)) operations with
   | Some value => operation_nonexecuting value | None => false end
 | D.FunctionOutput call_id _ _ => existsb (fun value =>
   String.eqb call_id (D.call_id (D.operation_call value)) && operation_nonexecuting value) operations
 | D.OperationResult operation invocation _ _ =>
   match find (fun value => N.eqb operation (D.operation_id value)) operations with
   | Some value => String.eqb (D.call_id invocation) (D.call_id (D.operation_call value)) &&
     operation_nonexecuting value
   | None => false end
 | _ => false
 end.
Definition archived_suffix_valid (owner : N) (old next : D.task) :=
 forallb (archived_message owner (D.task_operations old))
   (skipn (List.length (D.task_history old)) (D.task_history next)).
Definition same_archived_task (owner : N) (old next : D.task) :=
 match D.task_lifecycle old with
 | D.Archived =>
   match D.task_lifecycle next with
   | D.Archived => ContextSelection.history_extends (D.task_history old) (D.task_history next) &&
       archived_suffix_valid owner old next &&
       same_content_lists (D.task_queued old) (D.task_queued next)
   | _ => false
   end
 | _ => true
 end.
Definition retained_task (source : option input) (raw_source : Json.json) (world_before : K.world)
 (owner : N) (before after : F.state)
 (old next : D.task) :=
 same_naturals (D.task_lineage old) (D.task_lineage next) &&
 (same_contract (D.task_contract old) (D.task_contract next) ||
   worktree_contract_update owner before after old next) &&
 (same_profile (D.task_current_profile old) (D.task_current_profile next) &&
    same_settings (D.task_current_settings old) (D.task_current_settings next) ||
   worktree_contract_update owner before after old next ||
   configure_execution_source_authorizes source raw_source owner world_before old) &&
 ContextSelection.history_extends (D.task_history old) (D.task_history next) &&
 same_archived_task owner old next.
Fixpoint retained_tasks_from (source : option input) (raw_source : Json.json) (world_before : K.world)
 (owner : N) (before after : F.state)
 (old next : list D.task) :=
 match old, next with
 | [], _ => true
 | old_task :: old_rest, next_task :: next_rest =>
   retained_task source raw_source world_before owner before after old_task next_task &&
   retained_tasks_from source raw_source world_before (N.succ owner) before after old_rest next_rest
 | _, _ => false
 end.
Definition retained_tasks (source : option input) (raw_source : Json.json) (before after : K.world) :=
 retained_tasks_from source raw_source before 0 (K.world_features before) (K.world_features after)
   (K.world_tasks before) (K.world_tasks after).

Definition same_option_card_task (before after : option N) :=
 match before, after with
 | None, _ => true
 | Some first, Some second => N.eqb first second
 | Some _, None => false
 end.
Definition board_card_at (cards : list (option F.card)) (id : N) :=
 match Numbers.registry_at id cards with Some card => card | None => None end.
Definition retained_card (before after : F.card) :=
 N.leb (F.card_revision before) (F.card_revision after) &&
 same_option_card_task (F.card_task before) (F.card_task after).
Fixpoint retained_board_cards (before after : list (option F.card)) (id : N) :=
 match before with
 | [] => true
 | None :: rest =>
   (match board_card_at after id with None => true | Some _ => false end) &&
   retained_board_cards rest after (N.succ id)
 | Some old :: rest =>
   (match board_card_at after id with None => true | Some next => retained_card old next end) &&
   retained_board_cards rest after (N.succ id)
 end.
Definition board_evolution (before after : F.board) :=
 N.leb (N.of_nat (List.length (F.board_cards before))) (N.of_nat (List.length (F.board_cards after))) &&
 N.leb (N.of_nat (List.length (F.board_agents before))) (N.of_nat (List.length (F.board_agents after))) &&
 retained_board_cards (F.board_cards before) (F.board_cards after) 0.

Definition title_entry_at (owner : N) (entries : list F.title_entry) :=
 find (fun entry => N.eqb owner (F.title_task entry)) entries.
Definition title_value_retained (before : F.title_state) (after : option F.title_state) :=
 match before, after with
 | F.TitlePending old_ticket old_profile old_prompt, Some (F.TitlePending next_ticket next_profile next_prompt) =>
   N.eqb old_ticket next_ticket && same_profile old_profile next_profile && String.eqb old_prompt next_prompt
 | F.TitlePending _ _ _, Some (F.Named _) | F.TitlePending _ _ _, Some (F.TitleFailed _) => true
 | F.Named old, Some (F.Named next) => String.eqb old next
 | F.TitleFailed _, Some (F.TitleFailed _) => true
 | _, _ => false
 end.
Fixpoint retained_titles (before after : list F.title_entry) :=
 match before with
 | [] => true
 | entry :: rest =>
   title_value_retained (F.title_value entry)
     (option_map F.title_value (title_entry_at (F.title_task entry) after)) && retained_titles rest after
 end.
Definition same_title_prompts (left right : F.title_settings) :=
 String.eqb (F.title_task_prompt left) (F.title_task_prompt right) &&
 String.eqb (F.title_agent_prompt left) (F.title_agent_prompt right).
Definition titles_evolution (before after : F.state) :=
 retained_titles (F.feature_titles before) (F.feature_titles after) &&
 N.leb (F.title_revision (F.feature_title_settings before)) (F.title_revision (F.feature_title_settings after)) &&
 (negb (N.eqb (F.title_revision (F.feature_title_settings before))
   (F.title_revision (F.feature_title_settings after))) ||
  same_title_prompts (F.feature_title_settings before) (F.feature_title_settings after)).

Definition retained_worktree (old next : F.worktree) :=
 String.eqb (F.worktree_source old) (F.worktree_source next) &&
 String.eqb (WorkspaceBackend.name (F.worktree_backend old)) (WorkspaceBackend.name (F.worktree_backend next)).
Definition worktree_list_entry (owner : N) (entries : list F.worktree) :=
 find (fun entry => N.eqb owner (F.worktree_task entry)) entries.
Fixpoint retained_worktrees (before after : list F.worktree) :=
 match before with
 | [] => true
 | old :: rest =>
   (match worktree_list_entry (F.worktree_task old) after with
    | Some next => retained_worktree old next | None => false end) && retained_worktrees rest after
 end.
Definition compaction_entry_at (owner : N) (entries : list (N * C.entry)) :=
 option_map snd (find (fun entry => N.eqb owner (fst entry)) entries).
Definition retained_compaction_entry (before : C.entry) (after : option C.entry) :=
 match after with
 | None => false
 | Some next =>
   N.leb (C.entry_useful before) (C.entry_useful next) &&
   N.leb (C.entry_maintained before) (C.entry_maintained next) &&
   N.leb (C.entry_attempted before) (C.entry_attempted next)
 end.
Fixpoint retained_compaction_entries (before after : list (N * C.entry)) :=
 match before with
 | [] => true
 | (owner, entry) :: rest =>
   retained_compaction_entry entry (compaction_entry_at owner after) &&
   retained_compaction_entries rest after
 end.
Definition compaction_evolution (before after : C.state) :=
 N.leb (C.maintenance_now before) (C.maintenance_now after) &&
 retained_compaction_entries (C.maintenance_entries before) (C.maintenance_entries after).
Definition features_evolution (before after : F.state) :=
 titles_evolution before after &&
 N.leb (F.remote_next_epoch (F.feature_remote before)) (F.remote_next_epoch (F.feature_remote after)) &&
 retained_worktrees (F.feature_worktrees before) (F.feature_worktrees after) &&
 board_evolution (F.feature_board before) (F.feature_board after) &&
 N.leb (F.sharing_next (F.feature_sharing before)) (F.sharing_next (F.feature_sharing after)) &&
 N.leb (N.of_nat (List.length (F.feature_graphs before))) (N.of_nat (List.length (F.feature_graphs after))) &&
 compaction_evolution (F.feature_compaction before) (F.feature_compaction after) &&
 N.leb (N.of_nat (List.length (F.feature_works before))) (N.of_nat (List.length (F.feature_works after))).
Definition world_evolution (source : option input) (raw_source : Json.json) (before after : K.world) :=
 retained_tasks source raw_source before after &&
 N.leb (K.world_next_ticket before) (K.world_next_ticket after) &&
 N.leb (N.of_nat (List.length (K.world_projects before))) (N.of_nat (List.length (K.world_projects after))) &&
 features_evolution (K.world_features before) (K.world_features after).

Definition effect_ticket (value : K.effect) : option N :=
 match value with
 | K.ObserveContext _ ticket _ | K.RequestModel _ ticket _ _ _ _
 | K.RequestReasoning _ ticket _ _ | K.ExecuteTool _ ticket _ _ _ _ _
 | K.RequestApproval _ ticket _ _ _ | K.CheckTool _ ticket _ _ _
 | K.CheckResult _ ticket _ _ _ _ _ | K.SuggestTitle _ ticket _ _
 | K.SuggestCard _ ticket _ _ _ _ _ => Some ticket
 | K.MaintainContext request => match request with
   | C.Scope _ ticket _ | C.Measure _ ticket _ _ _ | C.Compact _ ticket _ _ _ _ => Some ticket
   | _ => None end
 | _ => None
 end.
Fixpoint has_effect_ticket (effects : list K.effect) (ticket : N) :=
 match effects with
 | [] => false
 | effect :: rest =>
   (match effect_ticket effect with Some other => N.eqb ticket other | None => false end) ||
   has_effect_ticket rest ticket
 end.
Fixpoint unique_effect_tickets (effects : list K.effect) :=
 match effects with
 | [] => true
 | effect :: rest =>
   (match effect_ticket effect with
    | Some ticket => negb (has_effect_ticket rest ticket)
    | None => true end) && unique_effect_tickets rest
 end.
Definition effect_tickets_fresh (first after : N) (effects : list K.effect) :=
 forallb (fun effect => match effect_ticket effect with
 | Some ticket => N.leb first ticket && N.ltb ticket after
 | None => true end) effects &&
 unique_effect_tickets effects.

Definition task_is_running (value : D.task) :=
 match D.task_lifecycle value with D.Running _ _ => true | _ => false end.
(* Stop prevents another inference, while already accepted calls and their
   hook/approval/result continuations retain their operation authority. *)
Definition task_allows_settlement (value : D.task) :=
 match D.task_lifecycle value with
 | D.Running _ _ | D.Stopped _ _ => true
 | D.Frozen _ _ | D.Archived => false
 end.
Definition operation_at (operation : N) (value : D.task) :=
 find (fun entry => N.eqb operation (D.operation_id entry)) (D.task_operations value).
Definition tool_member (tool : D.tool) (tools : list D.tool) :=
 existsb (same_tool tool) tools.
Definition task_context_matches (snapshot current : D.task) :=
 same_settings (D.task_current_settings snapshot) (D.task_current_settings current) &&
 same_settings (D.contract_settings (D.task_contract snapshot)) (D.contract_settings (D.task_contract current)).
Definition task_history_matches (snapshot current : D.task) :=
 same_history (D.task_history snapshot) (D.task_history current).
Definition approval_history_retained (snapshot current : D.task) :=
 ContextSelection.history_extends (D.task_history snapshot) (D.task_history current).
Definition active_manual_context_matches (owner : N) (snapshot : D.task) (after : K.world) :=
 match C.entry_job (Compaction.current_entry owner (Compaction.registry after)) with
 | C.Resuming input C.Manual => Compaction.same_input input snapshot after
 | _ => true
 end.
Definition observe_effect_valid (owner ticket : N) (snapshot : D.task) (after : K.world) :=
 match K.find_task owner after with
 | Some current => task_is_running snapshot && task_is_running current && task_context_matches snapshot current &&
   task_history_matches snapshot current &&
   active_manual_context_matches owner snapshot after &&
   match D.task_activity current with
   | D.ObservingContext expected length =>
     N.eqb ticket expected && Nat.eqb length (List.length (D.task_history current))
   | _ => false end
 | None => false
 end.
Definition model_profile_matches (owner : N) (model : D.profile) (snapshot : D.task) :=
 let requested := D.task_current_profile snapshot in
 match D.profile_policy requested with
 | D.FixedReasoning => same_profile model requested
 | D.AdaptivePolicy policy =>
   match Reasoning.history_lease owner (D.task_history snapshot) with
   | Reasoning.Lease effort _ =>
     Reasoning.allowed policy effort && same_profile model (Codec.with_reasoning effort requested)
   | Reasoning.NoLease => false
   end
 end.
Definition model_effect_valid (owner ticket : N) (model : D.profile) (snapshot : D.task) (after : K.world) :=
 match K.find_task owner after with
 | Some current => task_is_running current && task_context_matches snapshot current &&
   task_history_matches snapshot current &&
   model_profile_matches owner model snapshot &&
   same_profile (D.task_current_profile snapshot) (D.task_current_profile current) &&
   same_contract (D.task_contract snapshot) (D.task_contract current) &&
   match D.task_activity current, D.task_activity snapshot with
   | D.AskingModel expected allowed mode, D.AskingModel sent sent_allowed sent_mode =>
     N.eqb ticket expected && N.eqb expected sent && same_strings allowed sent_allowed &&
     same_output_mode mode sent_mode
   | _, _ => false end
 | None => false
 end.
Definition reasoning_effect_valid (owner ticket : N) (model : D.profile) (snapshot : D.task) (after : K.world) :=
 match K.find_task owner after with
 | Some current => task_is_running current && task_context_matches snapshot current &&
   task_history_matches snapshot current && same_profile model (D.task_current_profile current) &&
   same_profile model (D.task_current_profile snapshot) &&
   match D.task_activity current with
   | D.EvaluatingReasoning expected length =>
     N.eqb ticket expected && Nat.eqb length (List.length (D.task_history snapshot)) &&
     Nat.eqb length (List.length (D.task_history current)) &&
     match D.profile_policy (D.task_current_profile current) with D.AdaptivePolicy _ => true | _ => false end
   | _ => false end
 | None => false
 end.
Definition tool_effect_valid (owner ticket operation_id : N) (tool : D.tool) (call : D.call)
 (settings : D.task_settings) (access : K.execution_access) (after : K.world) :=
 match K.find_task owner after with
 | Some task => task_allows_settlement task && same_settings settings (D.task_current_settings task) &&
   tool_member tool (D.contract_tools (D.task_contract task)) &&
   String.eqb (D.tool_name tool) (D.call_name call) &&
   match operation_at operation_id task with
   | Some operation => same_call call (D.operation_call operation) &&
     match D.operation_stage operation, access with
     | D.Executing expected, K.DefaultAccess => N.eqb expected ticket
     | D.Elevated expected reviewer, K.ElevatedAccess =>
       N.eqb expected ticket && match D.settings_approval (D.task_current_settings task) with
       | D.FullAccess => true
       | _ => WorldInvariant.approval_corresponds owner task operation reviewer &&
         WorldInvariant.review_right task operation reviewer end
     | _, _ => false end
   | None => false end
 | None => false
 end.
Definition approval_effect_valid (owner ticket : N) (profile : D.profile) (call : D.call)
 (snapshot : D.task) (after : K.world) :=
 match K.find_task owner after with
 | Some task => task_allows_settlement task && task_context_matches snapshot task &&
   approval_history_retained snapshot task &&
   match find (fun operation => match D.operation_stage operation with
     | D.AwaitingApproval expected _ => N.eqb expected ticket
     | _ => false end) (D.task_operations task) with
   | Some operation => same_call call (D.operation_call operation) &&
     match D.operation_stage operation with
     | D.AwaitingApproval _ (D.ModelReviewer reviewer) => same_profile profile reviewer
     | _ => false end
   | None => false end
 | None => false
 end.
Definition hook_effect_valid (owner ticket : N) (plugin : Json.json) (tool : D.tool)
 (call : D.call) (after : K.world) :=
 match K.find_task owner after with
 | Some task => task_allows_settlement task && tool_member tool (D.contract_tools (D.task_contract task)) &&
   String.eqb (D.tool_name tool) (D.call_name call) &&
   match D.task_activity task with
   | D.CheckingHook expected reference invocation _ _ =>
     N.eqb ticket expected && Json.equal plugin reference && same_call call invocation
   | _ => false end
 | None => false
 end.
Definition after_effect_valid (owner ticket operation_id : N) (plugin : Json.json) (call : D.call)
 (value : Json.json) (error : bool) (after : K.world) :=
 match K.find_task owner after with
 | Some task => task_allows_settlement task &&
   match operation_at operation_id task with
   | Some operation => same_call call (D.operation_call operation) &&
     match D.operation_stage operation with
     | D.AwaitingAfterHook expected reference _ actual actual_error =>
       N.eqb ticket expected && Json.equal plugin reference && Json.equal value actual &&
       Bool.eqb error actual_error
     | _ => false end
   | None => false end
 | None => false
 end.

Definition same_card_draft (left right : F.card_draft) :=
 Json.equal
   (Selvedge.Features.Observation.card_json 0 (F.Card 0 left None false 0 0 F.NoEnrichment "" false))
   (Selvedge.Features.Observation.card_json 0 (F.Card 0 right None false 0 0 F.NoEnrichment "" false)).
Definition configured_profile (profile : D.profile) (after : K.world) :=
 existsb (same_profile profile) (D.environment_profiles (K.world_environment after)).
Definition title_effect_valid (owner ticket : N) (profile : D.profile) (prompt : string) (after : K.world) :=
 match K.find_task owner after, TitleRuntime.entry owner after with
 | Some task, Some entry => match F.title_value entry with
   | F.TitlePending expected selected sent_prompt =>
     N.eqb ticket expected && same_profile profile selected &&
     (match TitleRuntime.selected_profile task after with
      | Some actual => same_profile profile actual | None => false end) &&
     String.eqb prompt sent_prompt &&
     String.eqb prompt (TitleRuntime.prompt
       (F.title_agent_prompt (F.feature_title_settings (K.world_features after)))
       (TitleRuntime.first_request (D.task_history task)))
   | _ => false end
 | _, _ => false
 end.
Definition card_effect_valid (card_id ticket revision : N) (profile : D.profile)
 (prompt : string) (draft : F.card_draft) (retitle : bool) (after : K.world) :=
 match board_card_at (F.board_cards (F.feature_board (K.world_features after))) card_id with
 | Some card =>
   N.eqb revision (F.card_revision card) &&
   same_card_draft draft (F.card_contents card) &&
   match F.card_enrichment card with
   | F.Enriching expected expected_revision expected_retitle =>
     N.eqb ticket expected && N.eqb revision expected_revision &&
     Bool.eqb retitle expected_retitle && negb (F.card_archived card) &&
     configured_profile profile after && TitleRuntime.ordinary profile &&
     String.eqb prompt (Titles.board_prompt
       (F.title_task_prompt (F.feature_title_settings (K.world_features after)))
       (F.draft_title (F.card_contents card)) (F.draft_description (F.card_contents card)) retitle)
   | _ => false end
 | None => false
 end.

Definition same_connection_job (left right : F.connection_job) :=
 N.eqb (F.job_connection left) (F.job_connection right) &&
 N.eqb (F.job_project left) (F.job_project right) &&
 String.eqb (F.job_request left) (F.job_request right) &&
 Json.equal (F.job_arguments_json left) (F.job_arguments_json right) &&
 Json.equal (Codec.workspace_json (F.job_workspace left)) (Codec.workspace_json (F.job_workspace right)) &&
 Workspace.same_resource (F.job_resource left) (F.job_resource right) &&
 Json.equal (Codec.sandbox_json (F.job_sandbox left)) (Codec.sandbox_json (F.job_sandbox right)) &&
 match F.job_state left, F.job_state right with
 | F.JobRunning, F.JobRunning => true
 | F.JobFinished lv le, F.JobFinished rv re => Json.equal lv rv && Bool.eqb le re
 | F.JobInterrupted lr, F.JobInterrupted rr => String.eqb lr rr
 | _, _ => false end.
Definition connection_job_at (id : N) (state : F.connection_state) :=
 option_map snd (find (fun entry => N.eqb id (fst entry)) (F.sharing_jobs state)).

Definition same_capture (left right : C.capture) :=
 same_history (C.captured_history left) (C.captured_history right) &&
 same_profile (C.captured_profile left) (C.captured_profile right) &&
 same_settings (C.captured_settings left) (C.captured_settings right) &&
 same_tools (C.captured_tools left) (C.captured_tools right) &&
 same_strings (C.captured_callable left) (C.captured_callable right).
Definition same_capture_except_history (left right : C.capture) (history : list D.message) :=
 same_profile (C.captured_profile left) (C.captured_profile right) &&
 same_settings (C.captured_settings left) (C.captured_settings right) &&
 same_tools (C.captured_tools left) (C.captured_tools right) &&
 same_strings (C.captured_callable left) (C.captured_callable right) &&
 same_history (C.captured_history left) history.
Definition same_compaction_target (left right : C.target) :=
 String.eqb (C.target_key left) (C.target_key right) &&
 N.eqb (C.reserve_room (C.target_budget left)) (C.reserve_room (C.target_budget right)) &&
 N.eqb (C.window_room (C.target_budget left)) (C.window_room (C.target_budget right)) &&
 N.eqb (C.target_cache_ttl left) (C.target_cache_ttl right).
Definition same_inspection_stage (left right : C.inspection_stage) :=
 match left, right with C.InspectScope, C.InspectScope => true
 | C.InspectCount first, C.InspectCount second => String.eqb first second
 | _, _ => false end.
Definition compaction_cancel_retired (owner ticket : N) (before after : K.world) :=
 let before_entries := C.maintenance_entries (F.feature_compaction (K.world_features before)) in
 let after_entries := C.maintenance_entries (F.feature_compaction (K.world_features after)) in
 let was_pending := match compaction_entry_at owner before_entries with
 | Some entry =>
   (match Compaction.measurement_ticket (C.entry_measurement entry) with Some pending => N.eqb ticket pending | None => false end) ||
   (match Compaction.job_ticket (C.entry_job entry) with Some pending => N.eqb ticket pending | None => false end)
 | None => false end in
 let still_pending := match compaction_entry_at owner after_entries with
 | Some entry =>
   (match Compaction.measurement_ticket (C.entry_measurement entry) with Some pending => N.eqb ticket pending | None => false end) ||
   (match Compaction.job_ticket (C.entry_job entry) with Some pending => N.eqb ticket pending | None => false end)
 | None => false end in
 was_pending && negb still_pending.
Definition compaction_effect_valid (request : C.effect) (before after : K.world) :=
 let entries := C.maintenance_entries (F.feature_compaction (K.world_features after)) in
 match request with
 | C.Scope owner ticket input => match compaction_entry_at owner entries with
   | Some entry =>
     (match C.entry_measurement entry with
      | C.Measuring expected actual C.InspectScope => N.eqb ticket expected && same_capture input actual
      | _ => false end) ||
     (match C.entry_job entry with
      | C.Preparing expected actual _ C.InspectScope => N.eqb ticket expected && same_capture input actual
      | C.Validating expected actual _ _ _ C.InspectScope => N.eqb ticket expected && same_capture input actual
      | _ => false end)
   | None => false end
 | C.Measure owner ticket input scope validating => match compaction_entry_at owner entries with
   | Some entry =>
     (match C.entry_measurement entry with
      | C.Measuring expected actual (C.InspectCount expected_scope) =>
        N.eqb ticket expected && String.eqb scope expected_scope && negb validating && same_capture input actual
      | _ => false end) ||
     (match C.entry_job entry with
      | C.Preparing expected actual _ (C.InspectCount expected_scope) =>
        N.eqb ticket expected && String.eqb scope expected_scope && negb validating && same_capture input actual
      | C.Validating expected actual _ _ preview (C.InspectCount expected_scope) =>
        N.eqb ticket expected && String.eqb scope expected_scope && validating &&
        same_capture_except_history input actual preview
      | _ => false end)
   | None => false end
 | C.Compact owner ticket input target progress scope =>
   match compaction_entry_at owner entries, K.find_task owner after with
   | Some entry, Some task =>
     match C.entry_job entry with
     | C.Compacting expected actual _ current_progress expected_scope =>
       N.eqb ticket expected && same_capture input actual &&
       Json.equal (CompactionPlan.plan_json progress) (CompactionPlan.plan_json current_progress) &&
       String.eqb scope expected_scope &&
       match Compaction.configured_target task (F.feature_compaction (K.world_features after)) with
       | Some configured => same_compaction_target target configured &&
         (match C.target_method target, C.target_method configured with
          | Selvedge.Kernel.Compaction.Summary, _ => true
          | Selvedge.Kernel.Compaction.Automatic, Selvedge.Kernel.Compaction.Automatic => true
          | _, _ => false end)
       | None => false end
     | _ => false end
   | _, _ => false end
 | C.ArmClock deadline => N.eqb deadline
   (C.maintenance_timer (F.feature_compaction (K.world_features after)))
 | C.Cancel owner ticket => compaction_cancel_retired owner ticket before after
 end.

Definition task_has_ticket (owner ticket : N) (value : K.world) :=
 match K.find_task owner value with
 | Some task => existsb (N.eqb ticket) (WorldInvariant.task_tickets task)
 | None => false end.
Definition ticket_retirement_authorized (owner ticket : N) (before after : K.world) :=
 (task_has_ticket owner ticket before ||
   (N.leb (K.world_next_ticket before) ticket && N.ltb ticket (K.world_next_ticket after))) &&
 negb (task_has_ticket owner ticket after).
Definition task_cancellation_authorized (owner : N) (after : K.world) :=
 match K.find_task owner after with
 | Some task => match D.task_lifecycle task with
   | D.Stopped D.Idle _ => true
   | D.Archived => true
   | _ => false end
 | None => false end.
Definition pending_worktree (owner : N) (after : K.world) :=
 worktree_entry owner (K.world_features after).
Definition worktree_create_effect_valid (owner : N) (source_root : string)
 (space : D.workspace) (backend : WorkspaceBackend.backend) (after : K.world) :=
 match K.find_task owner after, pending_worktree owner after with
 | Some task, Some tree =>
   String.eqb source_root (F.worktree_source tree) &&
   String.eqb (WorkspaceBackend.name backend) (WorkspaceBackend.name (F.worktree_backend tree)) &&
   match F.worktree_phase tree with F.TreeCreating _ =>
     Workspace.valid_workspace space &&
     String.eqb source_root (Worktree.primary space) &&
     Json.equal (Codec.workspace_json space)
       (Codec.workspace_json (D.settings_workspace (D.task_current_settings task)))
   | _ => false end
 | _, _ => false
 end.
Definition worktree_archive_effect_valid (owner : N) (source_root root : string)
 (backend : WorkspaceBackend.backend) (after : K.world) :=
 match pending_worktree owner after with
 | Some tree =>
   String.eqb source_root (F.worktree_source tree) &&
   String.eqb (WorkspaceBackend.name backend) (WorkspaceBackend.name (F.worktree_backend tree)) &&
   match F.worktree_phase tree with
   | F.TreeArchiving expected _ => String.eqb root expected
   | _ => false end
 | None => false end.
Definition fresh_connection_job (id : N) (before after : K.world) :=
 N.leb (F.sharing_next (F.feature_sharing (K.world_features before))) id &&
 N.ltb id (F.sharing_next (F.feature_sharing (K.world_features after))).
Definition feature_effect_valid (effect : K.effect) (before after : K.world) :=
 match effect with
 | K.SuggestTitle owner ticket profile prompt => title_effect_valid owner ticket profile prompt after
 | K.SuggestCard card_id ticket revision profile prompt draft retitle =>
   card_effect_valid card_id ticket revision profile prompt draft retitle after
 | K.CreateWorktree owner source space backend =>
   worktree_create_effect_valid owner source space backend after
 | K.ArchiveWorktree owner source root backend =>
   worktree_archive_effect_valid owner source root backend after
 | K.RunConnectionJob id job =>
   fresh_connection_job id before after &&
   match connection_job_at id (F.feature_sharing (K.world_features after)) with
   | Some current => same_connection_job job current | None => false end
 | K.CancelConnectionJob id =>
   match connection_job_at id (F.feature_sharing (K.world_features after)) with
   | Some job => match F.job_state job with
     | F.JobInterrupted reason => String.eqb reason "Cancellation requested; physical changes are not undone"
     | _ => false end
   | None => false end
 | K.MaintainContext request => compaction_effect_valid request before after
 | _ => true
 end.

Definition effect_authorized (source : option input) (raw_source : Json.json)
 (effect : K.effect) (before after : K.world) :=
 match effect with
 | K.ObserveContext owner ticket snapshot => observe_effect_valid owner ticket snapshot after
 | K.RequestModel owner ticket model snapshot _ _ => model_effect_valid owner ticket model snapshot after
 | K.RequestReasoning owner ticket model snapshot => reasoning_effect_valid owner ticket model snapshot after
 | K.ExecuteTool owner ticket operation tool call settings access =>
   tool_effect_valid owner ticket operation tool call settings access after
 | K.RequestApproval owner ticket profile call snapshot =>
   approval_effect_valid owner ticket profile call snapshot after
 | K.CheckTool owner ticket plugin tool call => hook_effect_valid owner ticket plugin tool call after
 | K.CheckResult owner ticket operation plugin call value error =>
   after_effect_valid owner ticket operation plugin call value error after
 | K.CancelTask owner => task_cancellation_authorized owner after
 | K.CancelTicket owner ticket => ticket_retirement_authorized owner ticket before after
 | K.ResetModelSession owner =>
   match K.find_task owner before, K.find_task owner after with
   | Some old, Some next => configure_execution_source_authorizes source raw_source owner before old &&
     (negb (same_profile (D.task_current_profile old) (D.task_current_profile next)) ||
      negb (same_settings (D.task_current_settings old) (D.task_current_settings next)))
   | _, _ => false end
 | K.NotifyPlugins _ => true
 | _ => feature_effect_valid effect before after
 end.
Fixpoint effects_authorized (source : option input) (raw_source : Json.json)
 (before after : K.world) (effects : list K.effect) :=
 match effects with
 | [] => true
 | effect :: rest => effect_authorized source raw_source effect before after &&
   effects_authorized source raw_source before after rest
 end.
Definition effect_notifications_valid (durable : bool) (source : option input)
 (before : K.world) (candidate : K.decision) :=
 let effects := K.decision_effects candidate in
 let without_trailing := match List.last effects K.ContinueScheduling with
   | K.NotifyPlugins _ => removelast effects | _ => effects end in
 let expected := if durable then
   (Notifications.input_events source before (K.decision_world candidate) ++
    List.concat (Numbers.indexed (fun id task =>
      Notifications.task_events before id task (K.decision_world candidate)) 0
      (K.world_tasks (K.decision_world candidate))) ++
    flat_map (Notifications.effect_events (K.decision_world candidate)) without_trailing)%list
   else [] in
 match List.last effects K.ContinueScheduling with
 | K.NotifyPlugins events =>
   negb (existsb (fun effect => match effect with K.NotifyPlugins _ => true | _ => false end) without_trailing) &&
   negb (Nat.eqb (List.length expected) 0) && Json.equal (JArray events) (JArray expected)
 | _ => negb (existsb (fun effect => match effect with K.NotifyPlugins _ => true | _ => false end) effects)
 end.

Fixpoint explicitly_cancelled (effects : list K.effect) (owner ticket : N) :=
 match effects with
 | [] => false
 | K.CancelTask cancelled_owner :: rest =>
   N.eqb owner cancelled_owner || explicitly_cancelled rest owner ticket
 | K.CancelTicket cancelled_owner cancelled_ticket :: rest =>
   (N.eqb owner cancelled_owner && N.eqb ticket cancelled_ticket) ||
   explicitly_cancelled rest owner ticket
 | _ :: rest => explicitly_cancelled rest owner ticket
 end.
Definition archived_after (owner : N) (after : K.world) :=
 match K.find_task owner after with
 | Some task => match D.task_lifecycle task with D.Archived => true | _ => false end
 | None => false
 end.
Definition after_ticket_pending (owner operation ticket : N) (after : K.world) :=
 match K.find_task owner after with
 | Some task => match operation_at operation task with
   | Some value => match D.operation_stage value with
     | D.AwaitingAfterHook expected _ _ _ _ => N.eqb ticket expected
     | _ => false end
   | None => false end
 | None => false
 end.
Definition live_effect (after : K.world) (effects : list K.effect) (effect : K.effect) :=
 match effect with
 | K.ObserveContext owner ticket _ | K.RequestModel owner ticket _ _ _ _
 | K.RequestReasoning owner ticket _ _ | K.ExecuteTool owner ticket _ _ _ _ _
 | K.RequestApproval owner ticket _ _ _ | K.CheckTool owner ticket _ _ _ =>
   negb (archived_after owner after) && negb (explicitly_cancelled effects owner ticket)
 | K.CheckResult owner ticket operation _ _ _ _ =>
   after_ticket_pending owner operation ticket after
 | _ => true
 end.
(** A later cancellation in the same scheduled decision withdraws earlier
    provider work before notification construction or delivery. *)
Definition retain_live_effects (candidate : K.decision) :=
 let effects := K.decision_effects candidate in
 K.Decision (K.decision_world candidate) (K.decision_reply candidate)
   (List.filter (live_effect (K.decision_world candidate) effects) effects).

Definition transition_authorized (durable : bool) (source : option input) (raw_source : Json.json)
 (before : K.world) (candidate : K.decision) :=
 world_evolution source raw_source before (K.decision_world candidate) &&
 effect_tickets_fresh (K.world_next_ticket before) (K.world_next_ticket (K.decision_world candidate))
   (K.decision_effects candidate) &&
 effects_authorized source raw_source before (K.decision_world candidate) (K.decision_effects candidate) &&
 effect_notifications_valid durable source before candidate.
Definition validate (durable : bool) (source : option input) (raw_source : Json.json)
 (before : K.world) (candidate : K.decision) :=
 if transition_authorized durable source raw_source before candidate then candidate
 else K.reject "invalid_transition"
   "The candidate state change or emitted effect is not authorized" before.

