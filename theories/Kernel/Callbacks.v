From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonSchema Utf8.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates State TaskScope TaskChange Tasks History Conversation NativeTools Reasoning Inputs Capabilities ApprovalProtocol.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition ignored := State.ignored.
Definition acknowledged (value : world) := accept (JObject [("accepted",JBool true)]) value [].
Definition matching_activity (ticket : N) (phase : activity) := match phase with
 | ObservingContext expected _ | AskingModel expected _ _ | EvaluatingReasoning expected _
 | CheckingHook expected _ _ _ _ => N.eqb ticket expected | _ => false end.
Definition model_call_arguments_valid (tool : tool) (invocation : call) :=
  match tool_origin tool with
  | NativeToolSource _ _ => NativeTools.arguments_valid tool invocation
  | ExtensionToolSource parameters _ _ => JsonSchema.valid parameters (call_arguments invocation)
  | McpToolSource _ _ _ => match call_arguments invocation with JObject _ => true | _ => false end
  end.
Definition call_known (id : string) (history : list message) :=
 existsb (fun message => match message with FunctionCall invocation => String.eqb id (call_id invocation) | _ => false end) history.
Fixpoint permitted_items (items : list model_item) (allowed : list string) (task : task)
 (ids : list string) (parts : list N) :=
 match items with
 | [] => true
 | TextItem part text :: rest | ContextItem part (JString text) :: rest =>
   negb (existsb (N.eqb part) parts) && Utf8.well_formed text && permitted_items rest allowed task ids (part :: parts)
 | ContextItem part _ :: rest => negb (existsb (N.eqb part) parts) && permitted_items rest allowed task ids (part :: parts)
 | CallItem invocation :: rest =>
   negb (existsb (String.eqb (call_id invocation)) ids) && negb (call_known (call_id invocation) (task_history task)) &&
   existsb (String.eqb (call_name invocation)) allowed &&
   (match find_tool (call_name invocation) (contract_tools (task_contract task)) with
   | None => false | Some _ => match call_arguments invocation with JObject _ => true | _ => false end end) &&
   permitted_items rest allowed task (call_id invocation :: ids) parts
 end.
Definition item_messages (owner ticket : N) (mode : output_mode) (items : list model_item) :=
 map (fun item => match item with
 | TextItem part text => AssistantMessage (OutputOrigin owner ticket part mode) text
 | ContextItem part value => ModelContext (OutputOrigin owner ticket part (Conversation.context_output_mode value mode)) value
 | CallItem invocation => FunctionCall invocation end) items.
Definition item_calls (items : list model_item) := fold_right (fun item rest =>
 match item with CallItem invocation => invocation :: rest | _ => rest end) [] items.
Definition settle_model_changes (task : task) :=
 let phase := if unseen_model_input task then WantsModel else Idle in
 TaskChange.ChangePhase phase :: Tasks.promote_changes (with_activity phase task).
Definition settle_model (task : task) := TaskChange.apply (settle_model_changes task) task.
Definition model_result_changes (owner ticket : N) (allowed : list string) (mode : output_mode)
 (outcome : model_outcome) (task : task) :=
 let settle messages := TaskChange.AppendHistory messages ::
   settle_model_changes (append_history messages task) in
 match outcome with
 | ModelFailure text => settle [FailureMessage text]
 | ModelContextLimit => settle [FailureMessage "Model context limit reached; full task history retained"]
 | ModelSuccess items =>
   if permitted_items items allowed task [] [] then
   let messages := item_messages owner ticket mode items in
   TaskChange.AppendHistory messages ::
   match item_calls items with
   | [] => settle_model_changes (append_history messages task)
   | calls => [TaskChange.ChangePhase (PendingCalls calls)] end
   else settle [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"]
 end.
Definition model_result (owner ticket : N) (allowed : list string) (mode : output_mode)
 (outcome : model_outcome) (task : task) :=
 TaskChange.apply (model_result_changes owner ticket allowed mode outcome task) task.
Definition model_completed (id ticket : N) (outcome : model_outcome) (value : world) :=
 (* DEFENSE: IO may complete after interruption, archival or a later inference
    request. Only the ticket stored by the accepted request owns this result. *)
 match TaskScope.select id value with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match task_activity task with
   | AskingModel expected allowed mode =>
     if N.eqb expected ticket then acknowledged (TaskChange.interpret (TaskChange.Plan value target (model_result_changes id ticket allowed mode outcome task)))
     else ignored value
   | _ => ignored value end
 end.
Definition record_context_diagnostic_changes (message : string) (task : task) :=
 (* DEFENSE: A persistently unreadable source is observed before every generation;
    repeat diagnostics must not keep changing history and invalidating leases. *)
 if existsb (fun entry => match entry with
   | FailureMessage previous => String.eqb previous message | _ => false end) (task_history task)
 then [] else [TaskChange.AppendHistory [FailureMessage message]].
Definition record_context_diagnostic (message : string) (task : task) :=
 TaskChange.apply (record_context_diagnostic_changes message task) task.
Fixpoint context_diagnostic_changes (messages : list string) (task : task) :=
 match messages with
 | [] => []
 | message :: rest => let changes := record_context_diagnostic_changes message task in
   changes ++ context_diagnostic_changes rest (TaskChange.apply changes task)
 end.
Definition observed_context_changes (observations : option (list context_observation)) (diagnostic : string) (task : task) :=
 match observations with
 | None => (false,record_context_diagnostic_changes diagnostic task)
 | Some observations =>
   let '(changes,diagnostics) := observe_all observations (ContextUpdates.bindings (task_history task)) in
   let messages := map ContextObservation changes in
   (Nat.eqb (List.length diagnostics) 0,
    TaskChange.AppendHistory messages :: context_diagnostic_changes diagnostics (append_history messages task))
 end.
Definition observed_context (observations : option (list context_observation)) (diagnostic : string) (task : task) :=
 let '(accepted,changes) := observed_context_changes observations diagnostic task in
 (accepted,TaskChange.apply changes task).
Definition context_phase (task : task) :=
 match task_lifecycle task with Running _ _ => ReadyForModel | _ => WantsModel end.
Definition context_response (accepted : bool) (value : world) :=
 accept (JObject [("accepted",JBool true);("observations_accepted",JBool accepted)]) value [].
Definition context_ready (accepted : bool) (id : N) (task : task) (value : world) :=
 match TaskScope.select id value with
 | None => ignored value
 | Some target => context_response accepted
   (TaskChange.interpret (TaskChange.Plan value target [TaskChange.ChangePhase (context_phase task)]))
 end.
Definition context_completed (id ticket : N) (observations : option (list context_observation)) (diagnostic : string) (value : world) :=
 match TaskScope.select id value with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match task_activity task with
   | ObservingContext expected revision => if N.eqb expected ticket then
     (* DEFENSE: Tool completions and speech input can append history while source
        IO reads the captured prefix. Its patches belong only to that revision. *)
     if Nat.eqb revision (List.length (task_history task)) then
       let '(accepted,changes) := observed_context_changes observations diagnostic task in
       context_response accepted (TaskChange.interpret (TaskChange.Plan value target
         (changes ++ [TaskChange.ChangePhase (context_phase task)])))
     else match task_lifecycle task with
       | Running _ _ => Reasoning.observe_context id value
       | _ => context_ready false id task value end
     else ignored value
   | _ => ignored value end
 end.
Definition operation_ticket (value : operation) : option N := match operation_stage value with
 | Executing ticket | Elevated ticket _ | AwaitingApproval ticket _ | AwaitingAfterHook ticket _ _ _ _ => Some ticket
 | Granted _ | AfterHooksReady _ _ _ => None end.
Definition operation_matches (ticket : N) (value : operation) := match operation_ticket value with
 | Some expected => N.eqb expected ticket | None => false end.
Definition operation_executing (ticket : N) (value : operation) := match operation_stage value with
 | Executing expected | Elevated expected _ => N.eqb expected ticket | _ => false end.
Definition remove_operation (id : N) (values : list operation) := filter (fun operation => negb (N.eqb id (operation_id operation))) values.
Definition replace_operation := TicketedRequest.replace_operation.

Definition settle_operation_changes (operation : operation) (result : json) (error : bool) (task : task) :=
 let initial := [TaskChange.AppendHistory [History.operation_result operation result error];
   TaskChange.RemoveOperation (operation_id operation)] in
 initial ++ Tasks.wake_after_result_changes (TaskChange.apply initial task).
Definition settle_operation (operation : operation) (result : json) (error : bool) (task : task) :=
 TaskChange.apply (settle_operation_changes operation result error task) task.
Definition after_plugins (task : task) :=
 Capabilities.hook_references Capabilities.AfterTool (contract_plugins (task_contract task)).
Definition begin_result_changes (owner : N) (operation : operation) (result : json) (error : bool) (task : task) :=
 match after_plugins task with
 | [] => settle_operation_changes operation result error task
 | pending =>
   [TaskChange.AppendHistory [ToolReceipt owner (operation_id operation) (operation_call operation) result error];
    TaskChange.ChangeOperationStage (operation_id operation) (AfterHooksReady pending result error)]
 end.
Definition begin_result (owner : N) (operation : operation) (result : json) (error : bool) (task : task) :=
 TaskChange.apply (begin_result_changes owner operation result error task) task.
Definition tool_completed (id ticket : N) (result : json) (error : bool) (value : world) :=
 (* DEFENSE: Tool delivery can be duplicated or delayed after cancellation;
    a settled operation cannot acquire another completion or start a hook. *)
 match TaskScope.select id value with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match find (operation_executing ticket) (task_operations task) with
   | None => ignored value
   | Some operation => acknowledged (TaskChange.interpret (TaskChange.Plan value target (begin_result_changes id operation result error task)))
   end
 end.
Definition find_pending_approval (selected : N -> N -> reviewer -> bool) (operations : list operation)
 : option (operation * reviewer) :=
 fold_right (fun pending rest => match operation_stage pending with
 | AwaitingApproval ticket actor =>
   if selected (operation_id pending) ticket actor then Some (pending,actor) else rest
 | _ => rest end) None operations.
Definition approval_decision_changes (owner : N) (operation : operation) (reviewed_by : reviewer)
 (outcome : approval_outcome) (task : task) :=
 let outcome := ApprovalProtocol.normalize_outcome outcome in
 let receipt := [ApprovalReceipt owner (operation_id operation) (operation_call operation)
   reviewed_by (Inputs.approval_json outcome)] in
 TaskChange.AppendHistory receipt ::
 match outcome with
 | Approved _ => [TaskChange.ChangeOperationStage (operation_id operation) (Granted reviewed_by)]
 | Denied reason | ApprovalFailed reason => begin_result_changes owner operation
   (State.failure "approval_denied" ("Bash was not started. " ++ reason)) true (append_history receipt task)
 end.
Definition approval_decision (owner : N) (operation : operation) (reviewed_by : reviewer)
 (outcome : approval_outcome) (task : task) :=
 TaskChange.apply (approval_decision_changes owner operation reviewed_by outcome task) task.
Definition approval_completed (id ticket : N) (outcome : approval_outcome) (value : world) :=
 match TaskScope.select id value with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match find_pending_approval (fun _ expected actor => match actor with
   | ModelReviewer _ => N.eqb ticket expected | HumanReviewer => false end) (task_operations task) with
   | None => ignored value
   | Some (operation,actor) => acknowledged (TaskChange.interpret (TaskChange.Plan value target (approval_decision_changes id operation actor outcome task)))
   end end.
Definition review_approval (id operation : N) (outcome : approval_outcome) (value : world) :=
 let stale := reject "approval_not_pending"
   "This task has no pending human approval with that operation identity" value in
 match TaskScope.select id value with
 | None => stale
 | Some target => let task := TaskScope.selected target in match find_pending_approval (fun candidate _ actor => N.eqb operation candidate &&
   match actor with HumanReviewer => true | ModelReviewer _ => false end) (task_operations task) with
   | None => stale
   | Some (operation,actor) => acknowledged (TaskChange.interpret (TaskChange.Plan value target (approval_decision_changes id operation actor outcome task)))
   end end.
Definition reasoning_completed (id ticket : N) (outcome : Reasoning.outcome) (value : world) :=
 match TaskScope.select id value with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match task_activity task with
   | EvaluatingReasoning expected source_length => if N.eqb expected ticket then
      (* DEFENSE: Tool completions and speech transcripts can append evidence
         while the evaluator runs; its lease belongs to the captured history. *)
      let changes := if Nat.eqb source_length (List.length (task_history task))
        then Reasoning.complete_changes id outcome task
        else TaskChange.ChangePhase ReadyForModel :: Tasks.promote_changes (with_activity ReadyForModel task) in
      acknowledged (TaskChange.interpret (TaskChange.Plan value target changes))
      else ignored value
   | _ => ignored value end
 end.
