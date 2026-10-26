From Selvedge.Kernel Require Import TaskScope.
From Selvedge.Kernel Require Import FeatureRequestAdmission.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects.
From Selvedge.Kernel Require Import Numbers Domain State Tasks Capabilities ContextUpdates Codec ReasoningPlan Compaction ContextSelection.
From Selvedge.Features Require Import WorkspaceBinding State.
From Selvedge.ThirdParty.RecordUpdate Require Import RecordUpdate.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(* A request chooses a domain operation, rather than supplying an independently
   writable pending state and effect. The interpreter binds their shared ticket. *)
Inductive external_authority := Ordinary | Unrestricted | AskHuman | AskModel (reviewer : profile).
Inductive request :=
| Observe (task : task)
| Infer (task : task)
| Before (plugin : json) (tool : tool) (invocation : call)
    (pending : list json) (remaining : list call) (task : task)
| Start (tool : tool) (invocation : call) (remaining : list call)
    (authority : external_authority) (task : task)
| Resume (operation : operation) (tool : tool) (reviewer : reviewer) (task : task)
| After (operation : operation) (plugin : json) (pending : list json)
    (result : json) (error : bool) (task : task).
Definition append_operation (operation : operation) (remaining : list call) (task : task) :=
 with_activity (PendingCalls remaining) (with_operations (task_operations task ++ [operation]) task).
Definition replace_operation (replacement : operation) (values : list operation) :=
 map (fun operation => if N.eqb (operation_id replacement) (operation_id operation) then replacement else operation) values.
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
Definition publish_operations (task : task) :=
 let notices := fold_right (fun operation rest => if operation_announced operation then rest else
  FunctionOutput (call_id (operation_call operation)) (operation_notice operation) false :: rest) [] (task_operations task) in
 with_operations (map announce_operation (task_operations task)) (append_history notices task).
Definition last_configuration := ReasoningPlan.last_configuration.
Definition trailing_configuration := ReasoningPlan.trailing_configuration.
Definition generation := ReasoningPlan.generation.
Definition build (owner ticket : N) (environment : environment) (source : request) : task * list effect :=
 match source with
 | Observe task =>
   (with_activity (ObservingContext ticket (List.length (task_history task))) task,
    [ObserveContext owner ticket task])
 | Infer source =>
   match ModelRequest.choose owner source with
   | Some choice => let request := ModelRequest.issue owner choice ticket environment in
     (ModelRequest.pending_task request,[RequestModel request])
   | None => (with_activity (EvaluatingReasoning ticket (List.length (task_history source))) source,
     [RequestReasoning owner ticket source]) end
 | Before plugin tool invocation pending remaining task =>
   (with_activity (CheckingHook ticket plugin invocation pending remaining) task,
    [CheckTool owner ticket plugin tool invocation])
 | Start tool invocation remaining authority task =>
   let settings := task_current_settings task in
   match authority with
   | Ordinary =>
     (append_operation (Operation ticket invocation false (Executing ticket)) remaining task,
      [ExecuteTool owner ticket ticket tool invocation settings DefaultAccess])
   | Unrestricted =>
     (append_operation (Operation ticket invocation false (Elevated ticket HumanReviewer)) remaining task,
      [ExecuteTool owner ticket ticket tool invocation settings ElevatedAccess])
   | AskHuman =>
     (Tasks.promote (append_operation (Operation ticket invocation false (AwaitingApproval ticket HumanReviewer)) remaining task),[])
   | AskModel reviewer =>
     let waiting := Tasks.promote (append_operation
       (Operation ticket invocation false (AwaitingApproval ticket (ModelReviewer reviewer))) remaining task) in
     (waiting,[RequestApproval owner ticket reviewer invocation waiting])
   end
 | Resume operation tool reviewer task =>
   let running := Operation (operation_id operation) (operation_call operation)
     (operation_announced operation) (Elevated ticket reviewer) in
   (Tasks.wake_after_result (with_operations (replace_operation running (task_operations task)) task),
    [ExecuteTool owner ticket (operation_id operation) tool (operation_call operation) (task_current_settings task) ElevatedAccess])
 | After operation plugin pending result error task =>
   let waiting := Operation (operation_id operation) (operation_call operation)
     (operation_announced operation) (AwaitingAfterHook ticket plugin pending result error) in
   (with_operations (replace_operation waiting (task_operations task)) task,
    [CheckResult owner ticket (operation_id operation) plugin (operation_call operation) result error])
 end.
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
Definition issue (owner : N) (source : request) (before : world) :=
 let '(ticket,allocated) := allocate_identity TaskTicket before in
 let '(pending,effects) := build owner ticket (world_environment before) source in
 let installed := put_task owner pending allocated in
 let installed := match source with
 | Resume _ _ _ current => Tasks.mark_context_wake owner current installed
 | _ => installed end in
 accept (JObject [("accepted",JBool true)]) installed effects.

Module Scoped.
Import TaskScope.
Inductive action :=
| ObserveTask (publish : bool)
| InferTask
| AuthorizeCall (plugin : json) (tool : tool) (invocation : call) (pending : list json) (remaining : list call)
| StartCall (tool : tool) (invocation : call) (remaining : list call) (authority : external_authority)
| ResumeOperation (operation : operation) (tool : tool) (reviewer : reviewer)
| AfterOperation (operation : operation) (plugin : json) (pending : list json) (result : json) (error : bool).
Definition operation_at (identity : N) (current : task) :=
 find (fun operation => N.eqb identity (operation_id operation)) (task_operations current).
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
Definition lower {before} (value : plan before) : request :=
 let current := selected (target value) in
 match intent value with
 | ObserveTask publish => Observe (if publish then publish_operations (Tasks.promote current) else current)
 | InferTask => Infer current
 | AuthorizeCall plugin tool invocation pending remaining => Before plugin tool invocation pending remaining current
 | StartCall tool invocation remaining authority => Start tool invocation remaining authority current
 | ResumeOperation operation tool reviewer => Resume operation tool reviewer current
 | AfterOperation operation plugin pending result error => After operation plugin pending result error current
 end.
Definition issue {before} (value : plan before) := TicketedRequest.issue (owner (target value)) (lower value) before.
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
Definition next_call (id : N) (before : world) : option (plan before) :=
 match select id before with
 | None => None
 | Some target =>
   match call_action (selected target) as source
     return call_action (selected target) = source -> option (plan before) with
   | Some (AuthorizeCall plugin tool invocation pending remaining) => fun evidence =>
     Some (Plan before target (AuthorizeCall plugin tool invocation pending remaining) evidence)
   | Some (StartCall tool invocation remaining authority) => fun evidence =>
     Some (Plan before target (StartCall tool invocation remaining authority) evidence)
   | _ => fun _ => None end eq_refl
 end.
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
Definition after (id identity : N) (before : world) : option (plan before) :=
 match select id before with
 | None => None
 | Some target =>
   match operation_at identity (selected target) as found
     return operation_at identity (selected target) = found -> option (plan before) with
   | None => fun _ => None
   | Some current => fun found =>
     match operation_stage current as stage return operation_stage current = stage -> option (plan before) with
     | AfterHooksReady (plugin :: pending) result error => fun ready =>
       Some (Plan before target (AfterOperation current plugin pending result error)
         (conj (eq_ind identity (fun key => operation_at key (selected target) = Some current) found
           (operation_id current) (operation_at_identity identity (selected target) current found)) ready))
     | _ => fun _ => None end eq_refl
   end eq_refl
 end.
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
 option_map (@snd N C.entry) (find (fun pair => N.eqb (fst pair) owner)
   (C.maintenance_entries (F.feature_compaction (world_features before)))).
(* A provider request consumes an observation from the actual registry. A
   caller's proposed entry or captured history cannot create that capability. *)
Definition maintenance_ready (owner : N) (input : C.capture) (before : world) :=
 match find_task owner before, compaction_entry owner before with
 | Some current, Some entry =>
   (match task_lifecycle current with Running _ _ => true | _ => false end) &&
   resources_available current before && capture_compatible input current before &&
   match C.entry_observation entry with
   | Some observed => capture_compatible observed current before &&
       ContextSelection.history_extends (C.captured_history observed) (C.captured_history input)
   | None => false end
 | _, _ => false end.
Inductive maintenance_action :=
| ScopeRequest (input : C.capture) (purpose : option C.reason) (entry : C.entry)
| ValidationScopeRequest (input : C.capture) (purpose : C.reason)
    (candidate : ContextSelection.artifact) (preview : list message) (entry : C.entry)
| MeasureRequest (input : C.capture) (purpose : option C.reason)
    (candidate : option (ContextSelection.artifact * list message)) (scope : string) (entry : C.entry)
| CompactRequest (input : C.capture) (purpose : C.reason)
    (target : C.target) (progress : Compaction.compaction_state) (scope : string) (entry : C.entry).
Inductive feature_action :=
| TitleRequest (owner : N) (selected : profile) (prompt : string)
| CardRequest (owner : N) (card : F.card) (selected : profile) (prompt : string) (retitle : bool)
| ConnectionRequest (job : F.connection_job)
| MaintainRequest (owner : N) (request : maintenance_action).
Definition feature_valid (before : world) (source : feature_action) :=
 match source with
 | TitleRequest owner selected prompt => FeatureRequestAdmission.title owner selected prompt before
 | CardRequest owner card selected prompt retitle =>
   N.leb owner (N.of_nat (List.length (F.board_cards (F.feature_board (world_features before))))) &&
   FeatureRequestAdmission.card owner card selected prompt retitle before
 | ConnectionRequest job => match F.job_state job with
   | F.JobRunning => FeatureRequestAdmission.connection job before | _ => false end
 | MaintainRequest owner request => maintenance_ready owner
    (match request with ScopeRequest input _ _ | ValidationScopeRequest input _ _ _ _ |
      MeasureRequest input _ _ _ _ | CompactRequest input _ _ _ _ _ => input end) before
 end.
Record feature_plan (before : world) := FeaturePlan {
 feature_intent : feature_action;
 feature_admitted : feature_valid before feature_intent = true
}.
Arguments FeaturePlan {before}.
Arguments feature_intent {before}.
Definition feature_space (source : feature_action) := match source with
 | ConnectionRequest _ => ConnectionIdentity | _ => TaskTicket end.
Definition put_title owner state value :=
 with_features (FS.with_titles
   (F.TitleEntry owner state :: filter (fun item => negb (N.eqb owner (F.title_task item)))
     (F.feature_titles (world_features value))) (world_features value)) value.
Definition put_card owner card value :=
 let board := F.feature_board (world_features value) in
 with_features (FS.with_board
  (set F.board_order (fun order => if existsb (N.eqb owner) order then order else order ++ [owner])
   (set F.board_cards (fun cards => if N.eqb owner (N.of_nat (List.length cards))
      then cards ++ [Some card] else replace owner (Some card) cards) board))
  (world_features value)) value.
Definition put_connection identity job value :=
 let state := F.feature_sharing (world_features value) in
 with_features (FS.with_sharing
  (set F.sharing_jobs (fun jobs => (identity,job) :: filter (fun item => negb (N.eqb identity (fst item))) jobs) state)
  (world_features value)) value.
Definition put_compaction owner entry value :=
 let state := F.feature_compaction (world_features value) in
 with_features (FS.with_compaction
  (set C.maintenance_entries (fun entries => (owner,entry) :: filter (fun item => negb (N.eqb (fst item) owner)) entries) state)
  (world_features value)) value.
Definition can_observe_maintenance (current : task) (before : world) :=
 resources_available current before && match task_lifecycle current with
 | Running Idle _ | Running ReadyForModel _ => true | _ => false end.
Record maintenance_context_plan (before : world) := MaintenanceContextPlan {
 maintenance_context_target : task_reference before;
 maintenance_context_purpose : option C.reason;
 maintenance_context_entry : C.entry;
 maintenance_context_admitted : can_observe_maintenance (selected maintenance_context_target) before = true
}.
Arguments MaintenanceContextPlan {before}.
Arguments maintenance_context_target {before}.
Arguments maintenance_context_purpose {before}.
Arguments maintenance_context_entry {before}.
Definition maintenance_context (owner : N) (purpose : option C.reason) (entry : C.entry) (before : world)
 : option (maintenance_context_plan before) :=
 match select owner before with
 | None => None
 | Some target => match Bool.bool_dec (can_observe_maintenance (selected target) before) true with
   | left admitted => Some (MaintenanceContextPlan target purpose entry admitted)
   | right _ => None end end.
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
Definition feature_build identity source allocated : world * effect :=
 match source with
 | TitleRequest owner selected prompt =>
   (put_title owner (F.TitlePending identity selected prompt) allocated, SuggestTitle owner identity selected prompt)
 | CardRequest owner card selected prompt retitle =>
   (put_card owner (set F.card_enrichment (fun _ => F.Enriching identity (F.card_revision card) retitle) card) allocated,
     SuggestCard owner identity (F.card_revision card) selected prompt (F.card_contents card) retitle)
 | ConnectionRequest job => (put_connection identity job allocated, RunConnectionJob identity job)
 | MaintainRequest owner request =>
   let '(pending, request_effect) := maintenance_build owner identity request in
   let pending := set C.entry_observation (fun _ => match compaction_entry owner allocated with
     | Some current => C.entry_observation current | None => None end) pending in
   (put_compaction owner pending allocated, MaintainContext request_effect) end.
Definition feature_issue {before} (request : feature_plan before) : decision :=
 let '(identity,allocated) := allocate_identity (feature_space (feature_intent request)) before in
 let '(installed,request_effect) := feature_build identity (feature_intent request) allocated in
 accept (JObject [("accepted",JBool true)]) installed [request_effect].
Definition feature (source : feature_action) (before : world) : option (feature_plan before) :=
 match Bool.bool_dec (feature_valid before source) true with
 | left evidence => Some (FeaturePlan source evidence)
 | right _ => None end.
Definition feature_with_reply (reply : json) (source : feature_action) (before : world) :=
 match feature source before with
 | Some request => let issued:=feature_issue request in
   Decision (decision_world issued) reply (decision_effects issued)
 (* DEFENSE: A positional card receiver cannot be installed beyond the append
    key, and a completed connection job is not a new pending execution. *)
 | None => reject "invalid_request_receiver" "The request has no installable pending receiver" before end.
Definition feature_run (source : feature_action) (before : world) :=
 feature_with_reply (success (JObject [("accepted",JBool true)])) source before.
End Scoped.
