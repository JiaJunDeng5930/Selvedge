From Selvedge.Programming Require RequestTypes.
From Selvedge.Programming Require TaskChange TaskResult.
From Selvedge.Programming Require Import TaskScope.
From Selvedge.Kernel Require Import RequestReceiver.
From Selvedge.Programming Require CommandResult.
From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonObjects OptionList.
From Selvedge.Programming Require Import Receiver Schema.
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
   let prepared := if publish then TaskResult.promote_changes current ++
     publication_changes (TaskResult.promote current) else [] in
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
     changes ++ TaskResult.promote_changes (TaskChange.apply changes current) in
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
   (changes ++ TaskResult.wake_after_result_changes (TaskChange.apply changes current),
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
 | ResumeOperation _ _ _ => TaskResult.mark_context_wake (owner target) (selected target) installed
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
Definition connection_jobs := Receiver.field F.sharing_jobs
 (Receiver.keyed (@fst N F.connection_job)).
Definition connection_slot := Receiver.field F.feature_sharing connection_jobs.
Definition install_feature {input} (receiver : Receiver.t F.state input) request value :=
 with_features (Receiver.install receiver request (world_features value)) value.
Definition put_card owner := install_feature (card_slot owner).
Definition put_connection identity job := install_feature connection_slot (identity,job).
(** A channel consumes a domain selection. Its payload and located protocol
    are projections of that one selection; only domain-specific eligibility is
    part of the source. Allocation and receiver installation belong here. *)
Record feature_channel (source : world -> Type) (payload : Type) := FeatureChannel {
 channel_space : identity_space;
 channel_input : forall before, source before -> payload;
 channel_protocol : forall before, source before ->
   RequestTypes.located payload (world_features (snd (allocate_identity channel_space before)))
}.
Arguments FeatureChannel {source payload}.
Arguments channel_space {source payload}.
Arguments channel_input {source payload} _ {before}.
Arguments channel_protocol {source payload} _ {before}.
Record feature_plan (before : world) := FeaturePlan {
 feature_source : world -> Type;
 feature_payload : Type;
 feature_protocol : feature_channel feature_source feature_payload;
 feature_selected : feature_source before
}.
Arguments FeaturePlan {before feature_source feature_payload}.
Arguments feature_source {before}.
Arguments feature_payload {before}.
Arguments feature_protocol {before}.
Arguments feature_selected {before}.
Definition feature_input {before} (request : feature_plan before) :=
 channel_input (feature_protocol request) (feature_selected request).
Definition feature_envelope {before} (request : feature_plan before) :=
 RequestEnvelope.Envelope (next_identity (channel_space (feature_protocol request)) before) (feature_input request).
Definition feature_request {before} (request : feature_plan before) :=
 RequestTypes.Packet
   (RequestTypes.release (channel_protocol (feature_protocol request) (feature_selected request)))
   (feature_envelope request).
Definition feature_issue_change {before} (request : feature_plan before) : CommandResult.change :=
 let '(_,allocated) := allocate_identity (channel_space (feature_protocol request)) before in
 let sent := feature_request request in
 CommandResult.Change (JObject [("accepted",JBool true)])
   (with_features (RequestTypes.install sent (world_features allocated)) allocated)
   [RequestFeature sent].
Definition feature_issue {before} (request : feature_plan before) : decision :=
 CommandResult.accept (feature_issue_change request).

End Scoped.
