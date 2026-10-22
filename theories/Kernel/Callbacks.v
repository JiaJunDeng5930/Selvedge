From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json JsonSchema Utf8.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates State Tasks History Conversation NativeTools Reasoning Inputs Capabilities ApprovalProtocol.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition ignored (value : world) := accept (JObject [("ignored",JBool true)]) value [].
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
   | None => false | Some tool => model_call_arguments_valid tool invocation end) &&
   permitted_items rest allowed task (call_id invocation :: ids) parts
 end.
Definition item_messages (owner ticket : N) (mode : output_mode) (items : list model_item) :=
 map (fun item => match item with
 | TextItem part text => AssistantMessage (OutputOrigin owner ticket part mode) text
 | ContextItem part value => ModelContext (OutputOrigin owner ticket part (Conversation.context_output_mode value mode)) value
 | CallItem invocation => FunctionCall invocation end) items.
Definition item_calls (items : list model_item) := fold_right (fun item rest =>
 match item with CallItem invocation => invocation :: rest | _ => rest end) [] items.
Definition settle_model (task : task) := promote (with_activity
 (if unseen_model_input task then WantsModel else Idle) task).
Definition model_result (owner ticket : N) (allowed : list string) (mode : output_mode)
 (outcome : model_outcome) (task : task) :=
 match outcome with
 | ModelFailure text => settle_model (append_history [FailureMessage text] task)
 | ModelContextLimit => settle_model (append_history [FailureMessage "Model context limit reached; full task history retained"] task)
 | ModelSuccess items =>
   if permitted_items items allowed task [] [] then
   let task := append_history (item_messages owner ticket mode items) task in
   match item_calls items with
   | [] => settle_model task
   | calls => with_activity (PendingCalls calls) task end
   else settle_model (append_history [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"] task)
 end.
Definition model_completed (id ticket : N) (outcome : model_outcome) (value : world) :=
 (* DEFENSE: IO may complete after interruption, archival or a later inference
    request. Only the ticket stored by the accepted request owns this result. *)
 match find_task id value with
 | None => ignored value
 | Some task => match task_activity task with
   | AskingModel expected allowed mode =>
     if N.eqb expected ticket then acknowledged (put_task id (model_result id ticket allowed mode outcome task) value)
     else ignored value
   | _ => ignored value end
 end.
Definition record_context_diagnostic (message : string) (task : task) :=
 (* DEFENSE: A persistently unreadable source is observed before every generation;
    repeat diagnostics must not keep changing history and invalidating leases. *)
 if existsb (fun entry => match entry with
   | FailureMessage previous => String.eqb previous message | _ => false end) (task_history task)
 then task else append_history [FailureMessage message] task.
Definition observed_context (observations : option (list context_observation)) (diagnostic : string) (task : task) :=
 match observations with
 | None => (false,record_context_diagnostic diagnostic task)
 | Some observations =>
   let '(changes,diagnostics) := observe_all observations (ContextUpdates.bindings (task_history task)) in
   (Nat.eqb (List.length diagnostics) 0,
    fold_left (fun task message => record_context_diagnostic message task) diagnostics
      (append_history (map ContextObservation changes) task))
 end.
Definition context_ready (accepted : bool) (id : N) (task : task) (value : world) :=
 let phase := match task_lifecycle task with Running _ _ => ReadyForModel | _ => WantsModel end in
 accept (JObject [("accepted",JBool true);("observations_accepted",JBool accepted)])
  (put_task id (with_activity phase task) value) [].
Definition context_completed (id ticket : N) (observations : option (list context_observation)) (diagnostic : string) (value : world) :=
 match find_task id value with
 | None => ignored value
 | Some task => match task_activity task with
   | ObservingContext expected revision => if N.eqb expected ticket then
     (* DEFENSE: Tool completions and speech input can append history while source
        IO reads the captured prefix. Its patches belong only to that revision. *)
     if Nat.eqb revision (List.length (task_history task)) then
       let '(accepted,task) := observed_context observations diagnostic task in
       context_ready accepted id task value
     else match task_lifecycle task with
       | Running _ _ => Reasoning.observe_context id task value
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
Definition replace_operation (replacement : operation) (values : list operation) :=
 map (fun operation => if N.eqb (operation_id replacement) (operation_id operation) then replacement else operation) values.
Definition settle_operation (operation : operation) (result : json) (error : bool) (task : task) :=
 Tasks.wake_after_result (with_operations (remove_operation (operation_id operation) (task_operations task))
 (append_history [History.operation_result operation result error] task)).
Definition after_plugins (task : task) :=
 Capabilities.hook_references Capabilities.AfterTool (contract_plugins (task_contract task)).
Definition tool_completed (id ticket : N) (result : json) (error : bool) (value : world) :=
 (* DEFENSE: Tool delivery can be duplicated or delayed after cancellation;
    a settled operation cannot acquire another completion or start a hook. *)
 match find_task id value with
 | None => ignored value
 | Some task => match find (operation_executing ticket) (task_operations task) with
   | None => ignored value
   | Some operation => match after_plugins task with
     | [] => acknowledged (put_task id (settle_operation operation result error task) value)
     | pending =>
     let task := append_history [ToolReceipt id (operation_id operation) (operation_call operation) result error] task in
     let waiting := Operation (operation_id operation) (operation_call operation) (operation_announced operation)
         (AfterHooksReady pending result error) in
     acknowledged (put_task id (with_operations (replace_operation waiting (task_operations task)) task) value)
     end
   end
 end.
Definition find_pending_approval (selected : N -> N -> reviewer -> bool) (operations : list operation)
 : option (operation * reviewer) :=
 fold_right (fun pending rest => match operation_stage pending with
 | AwaitingApproval ticket actor =>
   if selected (operation_id pending) ticket actor then Some (pending,actor) else rest
 | _ => rest end) None operations.
Definition approval_decision (owner : N) (operation : operation) (reviewed_by : reviewer)
 (outcome : approval_outcome) (task : task) :=
 let outcome := ApprovalProtocol.normalize_outcome outcome in
 let task := append_history [ApprovalReceipt owner (operation_id operation) (operation_call operation)
   reviewed_by (Inputs.approval_json outcome)] task in
 match outcome with
 | Approved _ =>
   with_operations (replace_operation (Operation (operation_id operation) (operation_call operation)
     (operation_announced operation) (Granted reviewed_by)) (task_operations task)) task
 | Denied reason | ApprovalFailed reason => settle_operation operation
   (State.failure "approval_denied" reason) true task
 end.
Definition approval_completed (id ticket : N) (outcome : approval_outcome) (value : world) :=
 match find_task id value with
 | None => ignored value
 | Some task => match find_pending_approval (fun _ expected actor => match actor with
   | ModelReviewer _ => N.eqb ticket expected | HumanReviewer => false end) (task_operations task) with
   | None => ignored value
   | Some (operation,actor) => acknowledged (put_task id (approval_decision id operation actor outcome task) value)
   end end.
Definition review_approval (id operation : N) (outcome : approval_outcome) (value : world) :=
 let stale := reject "approval_not_pending"
   "This task has no pending human approval with that operation identity" value in
 match find_task id value with
 | None => stale
 | Some task => match find_pending_approval (fun candidate _ actor => N.eqb operation candidate &&
   match actor with HumanReviewer => true | ModelReviewer _ => false end) (task_operations task) with
   | None => stale
   | Some (operation,actor) => acknowledged (put_task id (approval_decision id operation actor outcome task) value)
   end end.
Definition reasoning_completed (id ticket : N) (outcome : Reasoning.outcome) (value : world) :=
 match find_task id value with
 | None => ignored value
 | Some task => match task_activity task with
   | EvaluatingReasoning expected source_length => if N.eqb expected ticket then
      (* DEFENSE: Tool completions and speech transcripts can append evidence
         while the evaluator runs; its lease belongs to the captured history. *)
      let updated := if Nat.eqb source_length (List.length (task_history task))
        then Reasoning.complete id outcome task
        else Tasks.promote (with_activity ReadyForModel task) in
      acknowledged (put_task id updated value)
      else ignored value
   | _ => ignored value end
 end.
