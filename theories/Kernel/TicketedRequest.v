From Selvedge.Kernel Require Import TaskScope RequestReceiver.
From Selvedge.Kernel Require CommandResult.
From Selvedge.Kernel Require Import FeatureRequestAdmission.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects OptionList Receiver Schema.
From Selvedge.Kernel Require Import Numbers Domain State Tasks Capabilities ContextUpdates Codec ReasoningPlan Compaction ContextSelection.
From Selvedge.Features Require Import WorkspaceBinding State.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(* A request chooses a domain operation, rather than supplying an independently
   writable pending state and effect. The interpreter binds their shared ticket. *)
Inductive external_authority := Ordinary | Unrestricted | AskHuman | AskModel (reviewer : profile).
Definition opening_changes (operation : operation) (remaining : list call) :=
 [TaskChange.AddOperation operation; TaskChange.ChangePhase (PendingCalls remaining)].
Definition append_operation operation remaining current :=
 TaskChange.apply (opening_changes operation remaining) current.
Definition operation_notice (value : operation) := JObject [
 ("status",JString (match operation_stage value with AwaitingApproval _ _ => "awaiting_approval"
  | Granted _ => "approved_waiting_to_run" | _ => "running" end));
 ("operation_id",number (operation_id value));("tool",JString (call_name (operation_call value)));
 ("message",JString (match operation_stage value with
 | AwaitingApproval _ HumanReviewer => "Bash has not started. This exact command is waiting for the user's one-operation approval in the UI. Continue independent work or end the turn; do not poll or try to approve it yourself."
 | AwaitingApproval _ (ModelReviewer _) => "Bash has not started. An independent, tool-free reviewer is assessing this exact command. The result arrives automatically; do not poll or create another task to review it."
 | Granted _ => "A one-operation grant is committed, but Bash has not started. It will run only when the task is active."
 | _ => "This operation is still running, not completed. Its result will arrive as an asynchronous operation result. Continue independent work, or end your turn to wait; do not poll or sleep just to wait." end))].
Definition announce_operation (value : operation) :=
 Operation (operation_id value) (operation_call value) true (operation_stage value).
Definition publication_changes (task : task) :=
 let notices := fold_right (fun operation rest => if operation_announced operation then rest else
  FunctionOutput (call_id (operation_call operation)) (operation_notice operation) false :: rest) [] (task_operations task) in
 [TaskChange.AppendHistory notices; TaskChange.operation_change (map announce_operation)].
Definition publish_operations current := TaskChange.apply (publication_changes current) current.
Definition last_configuration := ReasoningPlan.last_configuration.
Definition trailing_configuration := ReasoningPlan.trailing_configuration.
Definition generation := ReasoningPlan.generation.
Inductive identity_space := TaskTicket | ConnectionIdentity.
Definition next_identity (space : identity_space) (before : world) :=
 match space with
 | TaskTicket => world_next_ticket before
 | ConnectionIdentity => Selvedge.Features.Domain.sharing_next
     (Selvedge.Features.Domain.feature_sharing (world_features before)) end.
Definition allocate_identity (space : identity_space) (before : world) : N * world :=
 let identity := next_identity space before in
 (identity, match space with
 | TaskTicket => with_ticket (N.succ identity) before
 | ConnectionIdentity => with_features
   (Selvedge.Features.State.with_sharing
     (set Selvedge.Features.Domain.sharing_next (fun _ => N.succ identity)
       (Selvedge.Features.Domain.feature_sharing (world_features before)))
     (world_features before)) before end).

Module Scoped.
Import TaskScope.
Inductive action :=
| ObserveTask (publish : bool)
| InferTask
| AuthorizeCall (plugin : json) (tool : tool) (invocation : call) (pending : list json) (remaining : list call)
| StartCall (tool : tool) (invocation : call) (remaining : list call) (authority : external_authority)
| ResumeOperation (operation : operation) (tool : tool) (reviewer : reviewer)
| AfterOperation (operation : operation) (plugin : json) (pending : list json) (result : json) (error : bool).
Definition operation_at := RequestReceiver.operation_at.
Lemma operation_at_identity : forall identity current operation,
 operation_at identity current = Some operation -> identity = operation_id operation.
Proof.
 intros identity current operation Found. unfold operation_at in Found.
 apply find_some in Found as [_ Equal]. apply N.eqb_eq; exact Equal.
Qed.
Definition external_authority_for (current : task) (invocation : call) :=
 let settings := task_current_settings current in
 let elevated := match settings_approval settings with
 | FullAccess => true
 | _ => String.eqb (call_name invocation) "bash" &&
   String.eqb (text_default "sandbox_permissions" (call_arguments invocation) "use_default") "require_escalated"
 end in
 if elevated then match settings_approval settings with
 | AskForApproval => AskHuman | ReviewWith reviewer => AskModel reviewer
 | FullAccess => Unrestricted end else Ordinary.
Definition can_execute (current : task) := match task_lifecycle current with
 | Running _ _ | Stopped _ _ => true | _ => false end.
Definition call_action (current : task) : option action :=
 let prepare invocation pending remaining :=
   match find_tool (call_name invocation) (contract_tools (task_contract current)) with
   | None => None
   | Some tool => Some (match pending with
     | [] => StartCall tool invocation remaining (external_authority_for current invocation)
     | plugin :: rest => AuthorizeCall plugin tool invocation rest remaining end)
   end in
 if can_execute current then match task_activity current with
 | PendingCalls (invocation :: remaining) => prepare invocation
     (Capabilities.hook_references Capabilities.BeforeTool (contract_plugins (task_contract current))) remaining
 | ReadyForHooks invocation pending remaining => prepare invocation pending remaining
 | _ => None end else None.
Definition resources_available (current : task) (before : world) :=
 let settings := task_current_settings current in
 WorkspaceBinding.resource_ready (settings_workspace settings) (settings_resource settings) before &&
 WorkspaceBinding.settings_execution_ready settings before.
(* Scheduled inference captures WantsModel. A direct observation retries the
   existing read; maintenance uses its purpose-bound receiver below. *)
Definition can_observe (publish : bool) (current : task) (before : world) :=
 resources_available current before && match task_lifecycle current with
 | Running phase _ => if publish then match phase with WantsModel => true | _ => false end
   else match phase with ObservingContext _ _ => true | _ => false end
 | _ => false end.
Definition can_infer (current : task) (before : world) :=
 resources_available current before && match task_lifecycle current with
 | Running ReadyForModel _ => true | _ => false end.
Definition admitted_action (before : world) (owner : N) (current : task) (source : action) : Prop := match source with
 | AuthorizeCall _ _ _ _ _ | StartCall _ _ _ _ => call_action current = Some source
 | ResumeOperation operation tool reviewer =>
   can_execute current = true /\
   operation_at (operation_id operation) current = Some operation /\
   operation_stage operation = Granted reviewer /\
   find_tool (call_name (operation_call operation)) (contract_tools (task_contract current)) = Some tool
 | AfterOperation operation plugin pending result error =>
   operation_at (operation_id operation) current = Some operation /\
   operation_stage operation = AfterHooksReady (plugin :: pending) result error
 | ObserveTask publish => can_observe publish current before = true
 | InferTask => can_infer current before = true end.
Record plan (before : world) := Plan {
 target : task_reference before;
 intent : action;
 operation_observed : admitted_action before (owner target) (selected target) intent
}.
Arguments target {before}.
Arguments intent {before}.
(** The admitted plan is the only task issuance language. Its interpreter can
    only append history and change task progress; allocation and installation
    use the selected owner once for the whole request. *)
Definition build {before} (value : plan before) (ticket : N) : list TaskChange.edit * list effect :=
 let target := target value in
 let owner := owner target in
 let current := selected target in
 match intent value with
 | ObserveTask publish =>
   let prepared := if publish then Tasks.promote_changes current ++
     publication_changes (Tasks.promote current) else [] in
   let captured := TaskChange.apply prepared current in
   (prepared ++ [TaskChange.ChangePhase (ObservingContext ticket (List.length (task_history captured)))],
    [ObserveContext owner ticket captured])
 | InferTask => match ModelRequest.choose owner current with
   | Some choice =>
     let sent := ModelRequest.issue owner choice ticket (world_environment before) in
     ((match ModelRequest.receipts choice with
       | Some messages => [TaskChange.AppendHistory messages] | None => [] end) ++
       [TaskChange.ChangeModelCursor (List.length (task_history (ModelRequest.base choice)));
        TaskChange.ChangePhase (ModelRequest.request_activity sent)], [RequestModel sent])
   | None => ([TaskChange.ChangePhase (EvaluatingReasoning ticket (List.length (task_history current)))],
     [RequestReasoning owner ticket current]) end
 | AuthorizeCall plugin tool invocation pending remaining =>
   ([TaskChange.ChangePhase (CheckingHook ticket plugin invocation pending remaining)],
    [CheckTool owner ticket plugin tool invocation])
 | StartCall tool invocation remaining authority =>
   let begin stage := opening_changes (Operation ticket invocation false stage) remaining in
   let wait actor := let changes := begin (AwaitingApproval ticket actor) in
     changes ++ Tasks.promote_changes (TaskChange.apply changes current) in
   match authority with
   | Ordinary => (begin (Executing ticket),
     [ExecuteTool owner ticket ticket tool invocation (task_current_settings current) DefaultAccess])
   | Unrestricted => (begin (Elevated ticket HumanReviewer),
     [ExecuteTool owner ticket ticket tool invocation (task_current_settings current) ElevatedAccess])
   | AskHuman => (wait HumanReviewer, [])
   | AskModel reviewer => let changes := wait (ModelReviewer reviewer) in
     (changes,[RequestApproval owner ticket reviewer invocation (TaskChange.apply changes current)])
   end
 | ResumeOperation operation tool reviewer =>
   let changes := [TaskChange.ChangeOperationStage (operation_id operation) (Elevated ticket reviewer)] in
   (changes ++ Tasks.wake_after_result_changes (TaskChange.apply changes current),
    [ExecuteTool owner ticket (operation_id operation) tool (operation_call operation)
      (task_current_settings current) ElevatedAccess])
 | AfterOperation operation plugin pending result error =>
   ([TaskChange.ChangeOperationStage (operation_id operation)
       (AwaitingAfterHook ticket plugin pending result error)],
    [CheckResult owner ticket (operation_id operation) plugin (operation_call operation) result error])
 end.
Definition issue {before} (value : plan before) :=
 let target := target value in
 let '(ticket,allocated) := allocate_identity TaskTicket before in
 let '(changes,effects) := build value ticket in
 let installed := put_task (owner target) (TaskChange.apply changes (selected target)) allocated in
 let installed := match intent value with
 | ResumeOperation _ _ _ => Tasks.mark_context_wake (owner target) (selected target) installed
 | _ => installed end in
 accept (JObject [("accepted",JBool true)]) installed effects.
Definition observe_allowed {before} (publish : bool) (target : task_reference before) (allowed : bool)
 (evidence : can_observe publish (selected target) before = allowed) : option (plan before) :=
 match allowed as allowed
   return can_observe publish (selected target) before = allowed -> option (plan before) with
 | true => fun admitted => Some (Plan before target (ObserveTask publish) admitted)
 | false => fun _ => None end evidence.
Definition observe_selected {before} (publish : bool) (target : task_reference before) :=
 observe_allowed publish target _ eq_refl.
Definition observe (id : N) (publish : bool) (before : world) : option (plan before) :=
 match select id before with Some target => observe_selected publish target | None => None end.
Definition model_allowed {before} (target : task_reference before) (allowed : bool)
 (evidence : can_infer (selected target) before = allowed) : option (plan before) :=
 match allowed as allowed
   return can_infer (selected target) before = allowed -> option (plan before) with
 | true => fun admitted => Some (Plan before target InferTask admitted)
 | false => fun _ => None end evidence.
Definition model_selected {before} (target : task_reference before) := model_allowed target _ eq_refl.
Definition model (id : N) (before : world) : option (plan before) :=
 match select id before with Some target => model_selected target | None => None end.
Definition next_call_selected {before} (target : task_reference before)
 (source : option action) (evidence : call_action (selected target) = source) : option (plan before) :=
 match source as source return call_action (selected target) = source -> option (plan before) with
 | Some (AuthorizeCall plugin tool invocation pending remaining) => fun evidence =>
   Some (Plan before target (AuthorizeCall plugin tool invocation pending remaining) evidence)
 | Some (StartCall tool invocation remaining authority) => fun evidence =>
   Some (Plan before target (StartCall tool invocation remaining authority) evidence)
 | _ => fun _ => None end evidence.
Definition next_call (id : N) (before : world) : option (plan before) :=
 match select id before with
 | None => None | Some target => next_call_selected target _ eq_refl end.
Definition authorize (id : N) (before : world) : option (plan before) :=
 match next_call id before with
 | Some request => match intent request with
   | AuthorizeCall _ _ _ _ _ => Some request | _ => None end
 | None => None end.
Definition start (id : N) (before : world) : option (plan before * call * list call) :=
 match next_call id before with
 | Some request => match intent request with
   | StartCall _ invocation remaining _ => Some (request,invocation,remaining) | _ => None end
 | None => None end.
Definition after_stage_selected {before} (target : task_reference before) identity current
 (found : operation_at identity (selected target) = Some current)
 (stage : operation_state) (ready : operation_stage current = stage) : option (plan before) :=
 match stage as stage return operation_stage current = stage -> option (plan before) with
 | AfterHooksReady (plugin :: pending) result error => fun ready =>
   Some (Plan before target (AfterOperation current plugin pending result error)
     (conj (eq_ind identity (fun key => operation_at key (selected target) = Some current) found
       (operation_id current) (operation_at_identity identity (selected target) current found)) ready))
 | _ => fun _ => None end ready.
Definition after_operation_selected {before} (target : task_reference before) identity
 (found : option operation) (owned : operation_at identity (selected target) = found) : option (plan before) :=
 match found as found return operation_at identity (selected target) = found -> option (plan before) with
 | None => fun _ => None
 | Some current => fun owned => after_stage_selected target identity current owned _ eq_refl
 end owned.
Definition after (id identity : N) (before : world) : option (plan before) :=
 match select id before with
 | None => None | Some target => after_operation_selected target identity _ eq_refl end.
Definition resume (id identity : N) (before : world) : option (plan before) :=
 match select id before with
 | None => None
 | Some target =>
   match operation_at identity (selected target) as found
     return operation_at identity (selected target) = found -> option (plan before) with
   | None => fun _ => None
   | Some current => fun found =>
     match operation_stage current as stage return operation_stage current = stage -> option (plan before) with
     | Granted reviewer => fun granted =>
       match find_tool (call_name (operation_call current)) (contract_tools (task_contract (selected target))) as selected_tool
         return find_tool (call_name (operation_call current)) (contract_tools (task_contract (selected target))) = selected_tool -> option (plan before) with
       | None => fun _ => None
       | Some tool => fun known =>
         match can_execute (selected target) as allowed
           return can_execute (selected target) = allowed -> option (plan before) with
         | true => fun active => Some (Plan before target (ResumeOperation current tool reviewer)
           (conj active (conj (eq_ind identity (fun key => operation_at key (selected target) = Some current) found
             (operation_id current) (operation_at_identity identity (selected target) current found)) (conj granted known))))
         | false => fun _ => None end eq_refl
       end eq_refl
     | _ => fun _ => None end eq_refl
   end eq_refl
 end.
Definition run {before} (candidate : option (plan before)) :=
 match candidate with Some value => issue value
 (* DEFENSE: A task or operation can disappear before a callback is handled;
    lifecycle, phase or resource admission can also refuse a new request. *)
 | None => State.ignored before end.
(* Feature requests extend the same before-indexed request family. An action
   records its receiver and frozen domain input once; callers cannot choose an
   effect independently of the receiver installed by the interpreter. *)
Module F := Selvedge.Features.Domain.
Module FS := Selvedge.Features.State.
Module C := Selvedge.Features.CompactionTypes.
Definition capture_task (current : task) (before : world) :=
 C.Capture (task_history current) (task_current_profile current) (task_current_settings current)
   (Capabilities.task_tools current) (Capabilities.callable current (world_environment before)).
Definition input_description (input : C.capture) := JObject [
 ("model", Codec.model_json (C.captured_profile input)); ("profile", profile_metadata (C.captured_profile input));
 ("settings", Codec.settings_json (C.captured_settings input)); ("guidance", settings_guidance (C.captured_settings input));
 ("worktree", JBool (settings_worktree (C.captured_settings input)));
 ("tools", JArray (map Codec.tool_json (C.captured_tools input))); ("callable", JArray (map JString (C.captured_callable input)))].
Definition same_description (input : C.capture) (current : task) (before : world) :=
 JsonObjects.equivalent (input_description input) (input_description (capture_task current before)).
Definition capture_compatible (input : C.capture) (current : task) (before : world) :=
 same_description input current before && ContextSelection.history_extends (C.captured_history input) (task_history current).
Definition compaction_entry (owner : N) (before : world) :=
 option_map (@snd N C.entry) (find (fun pair => N.eqb owner (fst pair))
   (C.maintenance_entries (F.feature_compaction (world_features before)))).
(* A provider request consumes an observation from the actual registry. A
   caller's proposed entry or captured history cannot create that capability. *)
Definition maintenance_ready_from (input : C.capture) (current : task) (entry : C.entry) (before : world) :=
 (match task_lifecycle current with Running _ _ => true | _ => false end) &&
 resources_available current before && capture_compatible input current before &&
 match C.entry_observation entry with
 | Some observed => capture_compatible observed current before &&
     ContextSelection.history_extends (C.captured_history observed) (C.captured_history input)
 | None => false end.
Definition maintenance_ready (owner : N) (input : C.capture) (before : world) :=
 match find_task owner before, compaction_entry owner before with
 | Some current, Some entry => maintenance_ready_from input current entry before
 | _, _ => false end.
Inductive maintenance_action :=
| ScopeRequest (input : C.capture) (purpose : option C.reason) (entry : C.entry)
| ValidationScopeRequest (input : C.capture) (purpose : C.reason)
    (candidate : ContextSelection.artifact) (preview : list message) (entry : C.entry)
| MeasureRequest (input : C.capture) (purpose : option C.reason)
    (candidate : option (ContextSelection.artifact * list message)) (scope : string) (entry : C.entry)
| CompactRequest (input : C.capture) (purpose : C.reason)
    (target : C.target) (progress : Compaction.compaction_state) (scope : string) (entry : C.entry).
Definition maintenance_input (request : maintenance_action) := match request with
 | ScopeRequest input _ _ | ValidationScopeRequest input _ _ _ _ |
   MeasureRequest input _ _ _ _ | CompactRequest input _ _ _ _ _ => input end.
Definition maintenance_waiting_entry (request : maintenance_action) := match request with
 | ScopeRequest _ purpose entry | MeasureRequest _ purpose _ _ entry => (purpose,entry)
 | ValidationScopeRequest _ purpose _ _ entry | CompactRequest _ purpose _ _ _ entry => (Some purpose,entry) end.
Definition maintenance_replacement_ready (request : maintenance_action) :=
 match request with
 | ScopeRequest _ _ _ | MeasureRequest _ _ None _ _ => true
 | ValidationScopeRequest input _ _ _ _ | MeasureRequest input _ (Some _) _ _
 | CompactRequest input _ _ _ _ _ => ContextSelection.closed_prefix (C.captured_history input)
 end.
Definition maintenance_admission owner request before :=
 maintenance_ready owner (maintenance_input request) before && maintenance_replacement_ready request.
Record maintenance_reference (before : world) (owner : N) (request : maintenance_action) := MaintenanceReference {
 maintenance_current : task;
 maintenance_current_found : find_task owner before = Some maintenance_current;
 maintenance_previous : C.entry;
 maintenance_previous_found : compaction_entry owner before = Some maintenance_previous;
 maintenance_eligible : maintenance_ready_from (maintenance_input request) maintenance_current maintenance_previous before &&
   maintenance_replacement_ready request = true
}.
Arguments maintenance_current {before owner request}.
Arguments maintenance_current_found {before owner request}.
Arguments maintenance_previous {before owner request}.
Arguments maintenance_previous_found {before owner request}.
Arguments maintenance_eligible {before owner request}.
Definition boolean_admission (condition : bool) : option (condition = true) :=
 match Bool.bool_dec condition true with left evidence => Some evidence | right _ => None end.
Definition maintenance_observed owner request before current
 (Found : find_task owner before = Some current) entry
 (Stored : compaction_entry owner before = Some entry) : option (maintenance_reference before owner request) :=
 option_map (fun Eligible => MaintenanceReference before owner request current Found entry Stored Eligible)
   (boolean_admission (maintenance_ready_from (maintenance_input request) current entry before &&
     maintenance_replacement_ready request)).
Definition maintenance_selected owner request before current
 (Found : find_task owner before = Some current) : option (maintenance_reference before owner request) :=
 OptionList.observe (compaction_entry owner before)
   (fun entry Stored => maintenance_observed owner request before current Found entry Stored) (fun _ => None).
Definition title_slot owner :=
 Receiver.field F.feature_titles
   (Receiver.inject (F.TitleEntry owner) (Receiver.keyed owner F.title_task)).
Definition board_contents : Focus.t F.board (list (option F.card) * list N).
Proof.
 refine (Focus.Focus _ _ _
   (fun board => ((F.board_cards board,F.board_order board),
     (F.board_agents board,F.board_agent_order board,F.board_automatic board,F.board_draft_profile board)))
   (fun parts => let '((cards,order),(agents,agent_order,automatic,profile)) := parts in
     F.Board cards order agents agent_order automatic profile) _ _).
 - intros []; reflexivity.
 - intros [[cards order] [[[agents agent_order] automatic] profile]]; reflexivity.
Defined.
Definition card_slot owner := Receiver.field F.feature_board
 (Receiver.focused board_contents (Receiver.inject (@Some F.card) (Receiver.ordered owner))).
Definition connection_jobs identity := Receiver.field F.sharing_jobs
 (Receiver.keyed identity (@fst N F.connection_job)).
Definition connection_slot identity := Receiver.field F.feature_sharing (connection_jobs identity).
Definition compaction_entries owner := Receiver.field C.maintenance_entries
 (Receiver.inject (@pair N C.entry owner) (Receiver.keyed owner (@fst N C.entry))).
Definition compaction_slot owner := Receiver.field F.feature_compaction (compaction_entries owner).
Definition install_feature {input} (receiver : Receiver.t F.state input) request value :=
 with_features (Receiver.install receiver request (world_features value)) value.
Definition put_title owner := install_feature (title_slot owner).
Definition put_card owner := install_feature (card_slot owner).
Definition put_connection identity job := install_feature (connection_slot identity) (identity,job).
Definition put_compaction owner := install_feature (compaction_slot owner).
Definition can_observe_maintenance (current : task) (before : world) :=
 resources_available current before && match task_lifecycle current with
 | Running Idle _ | Running ReadyForModel _ => true | _ => false end.
Definition maintenance_prefix_ready (purpose : option C.reason) (history : list message) :=
 match purpose with None => true | Some _ => ContextSelection.closed_prefix history end.
Definition maintenance_context_ready (purpose : option C.reason) (current : task) (before : world) :=
 can_observe_maintenance current before && maintenance_prefix_ready purpose (task_history current).
Record maintenance_context_plan (before : world) := MaintenanceContextPlan {
 maintenance_context_target : task_reference before;
 maintenance_context_purpose : option C.reason;
 maintenance_context_entry : C.entry;
 maintenance_context_admitted : maintenance_context_ready maintenance_context_purpose
   (selected maintenance_context_target) before = true
}.
Arguments MaintenanceContextPlan {before}.
Arguments maintenance_context_target {before}.
Arguments maintenance_context_purpose {before}.
Arguments maintenance_context_entry {before}.
Definition maintenance_context_selected {before} (target : task_reference before) purpose entry
 : option (maintenance_context_plan before) :=
 option_map (fun admitted => MaintenanceContextPlan target purpose entry admitted)
   (boolean_admission (maintenance_context_ready purpose (selected target) before)).
Definition maintenance_observe {before} (request : maintenance_context_plan before) :=
 let target := maintenance_context_target request in
 let current := selected target in
 let '(ticket,allocated) := allocate_identity TaskTicket before in
 let resume_model := match task_activity current with ReadyForModel => true | _ => false end in
 let entry := set C.entry_observation (fun _ => None)
   (set C.entry_measurement (fun _ => C.Unmeasured)
    (set C.entry_job (fun _ => C.AwaitingContext ticket (maintenance_context_purpose request) resume_model)
      (maintenance_context_entry request))) in
 accept (JObject [("accepted",JBool true)])
  (put_compaction (owner target) entry
    (put_task (owner target) (with_activity (ObservingContext ticket (List.length (task_history current))) current) allocated))
  [ObserveContext (owner target) ticket current].
Definition maintenance_build owner identity source : C.entry * C.effect :=
 match source with
 | ScopeRequest input purpose entry =>
   let pending := match purpose with
   | None => set C.entry_measurement (fun _ => C.Measuring identity input C.InspectScope) entry
   | Some purpose => set C.entry_measurement (fun _ => C.Unmeasured)
       (set C.entry_job (fun _ => C.Preparing identity input purpose C.InspectScope) entry) end in
   (pending, C.Scope owner identity input)
 | ValidationScopeRequest input purpose candidate preview entry =>
   (set C.entry_measurement (fun _ => C.Unmeasured)
     (set C.entry_job (fun _ => C.Validating identity input purpose candidate preview C.InspectScope) entry),
    C.Scope owner identity input)
 | MeasureRequest input purpose candidate scope entry =>
   let pending := match purpose,candidate with
   | Some purpose,Some (candidate,preview) => set C.entry_job
       (fun _ => C.Validating identity input purpose candidate preview (C.InspectCount scope)) entry
   | Some purpose,None => set C.entry_job (fun _ => C.Preparing identity input purpose (C.InspectCount scope)) entry
   | None,_ => set C.entry_measurement (fun _ => C.Measuring identity input (C.InspectCount scope)) entry end in
   let measured_input := match candidate with Some (_,preview) => set C.captured_history (fun _ => preview) input | None => input end in
   (pending, C.Measure owner identity measured_input scope (match candidate with Some _ => true | None => false end))
 | CompactRequest input purpose target progress scope entry =>
   (set C.entry_job (fun _ => C.Compacting identity input purpose progress scope) entry,
    C.Compact owner identity input target progress scope) end.
(** A protocol declares its receiver and external operation together. Extending
    the request language adds a declaration; no global feature enumeration or
    preservation-case table is involved. The interpreter owns allocation and
    the single envelope supplied to both projections. *)
Record feature_channel (payload : Type) := FeatureChannel {
 channel_space : identity_space;
 channel_protocol : N -> RequestTypes.protocol payload;
 channel_admission : world -> payload -> Type
}.
Arguments FeatureChannel {payload}.
Arguments channel_space {payload}.
Arguments channel_protocol {payload}.
Arguments channel_admission {payload}.
Record feature_plan (before : world) := FeaturePlan {
 feature_payload : Type;
 feature_protocol : feature_channel feature_payload;
 feature_input : feature_payload;
 feature_admitted : channel_admission feature_protocol before feature_input;
 feature_available : Receiver.available
   (RequestTypes.receiver (channel_protocol feature_protocol (next_identity (channel_space feature_protocol) before)))
   (RequestEnvelope.Envelope (next_identity (channel_space feature_protocol) before) feature_input)
   (world_features (snd (allocate_identity (channel_space feature_protocol) before))) = true
}.
Arguments FeaturePlan {before feature_payload}.
Arguments feature_payload {before}.
Arguments feature_protocol {before}.
Arguments feature_input {before}.
Arguments feature_admitted {before}.
Arguments feature_available {before}.
Definition feature_envelope {before} (request : feature_plan before) :=
 RequestEnvelope.Envelope (next_identity (channel_space (feature_protocol request)) before) (feature_input request).
Definition feature_request {before} (request : feature_plan before) :=
 RequestTypes.Packet
   (channel_protocol (feature_protocol request) (RequestEnvelope.identity (feature_envelope request)))
   (feature_envelope request).
Definition feature_issue_change {before} (request : feature_plan before) : CommandResult.change :=
 let '(_,allocated) := allocate_identity (channel_space (feature_protocol request)) before in
 let sent := feature_request request in
 CommandResult.Change (JObject [("accepted",JBool true)])
   (with_features (RequestTypes.install sent (world_features allocated)) allocated)
   [RequestFeature sent].
Definition feature_issue {before} (request : feature_plan before) : decision :=
 CommandResult.accept (feature_issue_change request).

Definition title_protocol owner : RequestTypes.protocol (profile * string) :=
 RequestTypes.Protocol (Receiver.inject F.TitlePending (title_slot owner))
   ModelDeclarations.task_title_request
   (fun input _ => Schema.of_tuple (ModelDeclarations.request_body_fields ModelDeclarations.task_title_request)
     [!Codec.task_text_model_json (fst input);snd input!]).
Definition title_channel owner : feature_channel (profile * string) :=
 FeatureChannel TaskTicket (fun _ => title_protocol owner)
   (fun before input => FeatureRequestAdmission.title owner (fst input) (snd input) before = true).
Definition card_protocol owner card selected prompt : RequestTypes.protocol (N * bool) :=
 RequestTypes.Protocol
   (Receiver.in_record (card_slot owner) F.card_enrichment F.Enriching card)
   ModelDeclarations.board_text_request
   (fun input _ => Schema.of_tuple (ModelDeclarations.request_body_fields ModelDeclarations.board_text_request)
     [!Codec.task_text_model_json selected;prompt;snd input!]).
Definition card_channel owner card selected prompt : feature_channel (N * bool) :=
 FeatureChannel TaskTicket (fun _ => card_protocol owner card selected prompt)
   (fun before input => fst input = F.card_revision card /\
     FeatureRequestAdmission.card owner card selected prompt (snd input) before = true).
Definition connection_protocol identity : RequestTypes.protocol F.connection_job :=
 RequestTypes.Protocol (Receiver.inject RequestEnvelope.as_pair (connection_slot identity))
   ModelDeclarations.chatgpt_exec_request
   (fun job features => Schema.of_tuple (ModelDeclarations.request_body_fields ModelDeclarations.chatgpt_exec_request)
     [!F.job_arguments_json job;JObject [
       ("workspace",workspace_json (F.job_workspace job));
       ("resource",F.reference_execution (F.job_resource job) features);
       ("sandbox",sandbox_json (F.job_sandbox job));("access",JString "sandboxed");("scope",JString "project")]!]).
Definition connection_channel : feature_channel F.connection_job :=
 FeatureChannel ConnectionIdentity connection_protocol
   (fun before job => F.job_state job = F.JobRunning /\ FeatureRequestAdmission.connection job before = true).
Definition maintenance_issue {before owner request}
 (reference : maintenance_reference before owner request) : decision :=
 let '(identity,allocated) := allocate_identity TaskTicket before in
 let '(pending,request_effect) := maintenance_build owner identity request in
 accept (JObject [("accepted",JBool true)])
   (put_compaction owner (set C.entry_observation (fun _ => C.entry_observation (maintenance_previous reference)) pending) allocated)
   [MaintainContext request_effect].
Definition card_plan {before} owner card selected prompt retitle
 (Bound : N.leb owner (N.of_nat (List.length (F.board_cards (F.feature_board (world_features before))))) = true)
 (Admitted : FeatureRequestAdmission.card owner card selected prompt retitle before = true)
 : feature_plan before :=
 FeaturePlan (card_channel owner card selected prompt) (F.card_revision card,retitle)
   (conj eq_refl Admitted) Bound.
Definition connection_plan {before identity project request_id}
 (request : FeatureRequestAdmission.resolved_connection before identity project request_id)
 : feature_plan before :=
 FeaturePlan connection_channel (FeatureRequestAdmission.resolved_job request)
   (conj (FeatureRequestAdmission.resolved_running request) (FeatureRequestAdmission.resolved_admitted request))
   (N.eqb_refl _).
Definition title_plan {before} (request : FeatureRequestAdmission.resolved_title before) : feature_plan before.
Proof.
 refine (FeaturePlan (title_channel (TaskScope.owner (FeatureRequestAdmission.title_reference request)))
   (FeatureRequestAdmission.title_profile request,
    FeatureRequestAdmission.title_prompt (TaskScope.selected (FeatureRequestAdmission.title_reference request)) before) _ (N.eqb_refl _)).
 cbn [channel_admission title_channel fst snd]. apply FeatureRequestAdmission.title_from_observations.
 - apply TaskScope.observed.
 - apply FeatureRequestAdmission.title_absent.
 - exact (proj1 (proj1 (andb_true_iff _ _) (FeatureRequestAdmission.title_eligible request))).
 - exact (proj2 (proj1 (andb_true_iff _ _) (FeatureRequestAdmission.title_eligible request))).
 - apply FeatureRequestAdmission.title_chosen.
Defined.
End Scoped.
