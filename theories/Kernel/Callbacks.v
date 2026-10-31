From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import JsonSchema.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates State TaskScope RequestReceiver TaskChange Tasks History Conversation NativeTools Reasoning Inputs Capabilities ApprovalProtocol OperationEvent.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition ignored := State.ignored.
Definition acknowledged (value : world) := accept (JObject [("accepted",JBool true)]) value [].
Definition model_call_arguments_valid (tool : tool) (invocation : call) :=
  match tool_origin tool with
  | NativeToolSource _ _ => NativeTools.arguments_valid tool invocation
  | ExtensionToolSource parameters _ _ => JsonSchema.check_registered parameters (call_arguments invocation)
  | McpToolSource _ _ _ => match call_arguments invocation with JObject _ => true | _ => false end
  end.
Definition call_known (id : string) (history : list message) :=
 existsb (fun message => match message with FunctionCall invocation => String.eqb id (call_id invocation) | _ => false end) history.
Definition permitted_items (items : list model_item) (allowed : list string) (task : task) :=
 forallb (fun item => match item with
 | CallItem invocation =>
   negb (call_known (call_id invocation) (task_history task)) &&
   existsb (String.eqb (call_name invocation)) allowed &&
   (match find_tool (call_name invocation) (contract_tools (task_contract task)) with
   | None => false | Some _ => true end)
 | _ => true end) items.
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
 | ModelSuccess batch =>
   let items := Codec.model_items batch in
   if permitted_items items allowed task then
   let messages := item_messages owner ticket mode items in
   TaskChange.AppendHistory messages ::
   match item_calls items with
   | [] => settle_model_changes (append_history messages task)
   | calls => [TaskChange.ChangePhase (PendingCalls calls)] end
   else settle [FailureMessage "Invalid model reply: previously used call identity or unavailable tool"]
 end.
Definition model_result (owner ticket : N) (allowed : list string) (mode : output_mode)
 (outcome : model_outcome) (task : task) :=
 TaskChange.apply (model_result_changes owner ticket allowed mode outcome task) task.
Definition model_completed (id ticket : N) (outcome : model_outcome) (value : world) :=
 RequestReceiver.deliver id value (RequestReceiver.pending_phase RequestReceiver.ModelReceiver ticket)
   (fun target payload => let '(allowed,mode) := payload in
    acknowledged (TaskChange.interpret (TaskChange.Plan value target
      (model_result_changes id ticket allowed mode outcome (TaskScope.selected target))))).
Definition context_diagnostic (diagnostic : string) (history : list message) :=
 (* DEFENSE: A persistently unreadable source is observed before every generation;
    repeat diagnostics must not keep changing history and invalidating leases. *)
 if existsb (fun entry => match entry with
   | FailureMessage previous => String.eqb previous diagnostic | _ => false end) history
 then [] else [FailureMessage diagnostic].
Fixpoint context_diagnostics (diagnostics : list string) (history : list message) :=
 match diagnostics with
 | [] => []
 | diagnostic :: rest => let messages := context_diagnostic diagnostic history in
   messages ++ context_diagnostics rest (history ++ messages)
 end.
(** Source observation owns only appended history. The callback interpreter
    chooses the task phase after receiving this result. *)
Definition observed_context_history (observations : option (list context_observation))
 (diagnostic : string) (history : list message) :=
 match observations with
 | None => (false,context_diagnostic diagnostic history)
 | Some observations =>
   let '(changes,diagnostics) := observe_all observations (ContextUpdates.bindings history) in
   let messages := map ContextObservation changes in
   (Nat.eqb (List.length diagnostics) 0,
    messages ++ context_diagnostics diagnostics (history ++ messages))
 end.
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
 RequestReceiver.deliver id value (RequestReceiver.pending_phase RequestReceiver.ContextReceiver ticket)
   (fun target revision => let task := TaskScope.selected target in
    (* DEFENSE: Source IO belongs to its captured history revision; concurrent
       tool or speech results require a new observation. *)
    if Nat.eqb revision (List.length (task_history task)) then
      let '(accepted,messages) := observed_context_history observations diagnostic (task_history task) in
      context_response accepted (TaskChange.interpret (TaskChange.Plan value target
        [TaskChange.AppendHistory messages; TaskChange.ChangePhase (context_phase task)]))
    else match task_lifecycle task with
      | Running _ _ => Reasoning.context_retry id value
      | _ => context_ready false id task value end).
Definition operation_executing := RequestReceiver.operation_executing.
Definition remove_operation (id : N) (values : list operation) := filter (fun operation => negb (N.eqb id (operation_id operation))) values.

Definition settle_operation_plan := OperationEvent.settle.
Definition settle_operation_changes (operation : operation) (result : json) (error : bool) (task : task) :=
 Tasks.result_changes (settle_operation_plan operation result error) task.
Definition settle_operation (operation : operation) (result : json) (error : bool) (task : task) :=
 TaskChange.apply (settle_operation_changes operation result error task) task.
Definition after_plugins := OperationEvent.after_plugins.
Definition begin_result_plan (owner : N) (operation : operation) (result : json) (error : bool) (task : task) :=
 OperationEvent.plan owner (OperationEvent.Returned operation result error) task.
Definition begin_result_changes (owner : N) (operation : operation) (result : json) (error : bool) (task : task) :=
 Tasks.result_changes (begin_result_plan owner operation result error task) task.
Definition begin_result (owner : N) (operation : operation) (result : json) (error : bool) (task : task) :=
 TaskChange.apply (begin_result_changes owner operation result error task) task.
Definition tool_completed (id ticket : N) (result : json) (error : bool) (value : world) :=
 RequestReceiver.deliver id value (RequestReceiver.pending_tool ticket)
   (fun target operation => acknowledged (Tasks.interpret_result target
     (begin_result_plan id operation result error (TaskScope.selected target)))).
Definition find_pending_approval := RequestReceiver.find_approval.
Definition approval_decision_plan (owner : N) (operation : operation) (reviewed_by : reviewer)
 (outcome : approval_outcome) (task : task) :=
 OperationEvent.plan owner (OperationEvent.Reviewed operation reviewed_by outcome) task.
Definition approval_decision_changes (owner : N) (operation : operation) (reviewed_by : reviewer)
 (outcome : approval_outcome) (task : task) :=
 Tasks.result_changes (approval_decision_plan owner operation reviewed_by outcome task) task.
Definition approval_decision (owner : N) (operation : operation) (reviewed_by : reviewer)
 (outcome : approval_outcome) (task : task) :=
 TaskChange.apply (approval_decision_changes owner operation reviewed_by outcome task) task.
Definition approval_completed (id ticket : N) (outcome : approval_outcome) (value : world) :=
 RequestReceiver.deliver id value (RequestReceiver.pending_approval ticket)
   (fun target payload => let '(operation,actor) := payload in
    acknowledged (Tasks.interpret_result target
      (approval_decision_plan id operation actor outcome (TaskScope.selected target)))).
Definition review_approval (id operation : N) (outcome : approval_outcome) (value : world) :=
 RequestReceiver.deliver_or id value (RequestReceiver.pending_human_approval operation)
   (reject "approval_not_pending" "This task has no pending human approval with that operation identity" value)
   (fun target payload => let '(operation,actor) := payload in
    acknowledged (Tasks.interpret_result target
      (approval_decision_plan id operation actor outcome (TaskScope.selected target)))).
Definition reasoning_completed (id ticket : N) (outcome : Reasoning.outcome) (value : world) :=
 RequestReceiver.deliver id value (RequestReceiver.pending_phase RequestReceiver.ReasoningReceiver ticket)
   (fun target source_length => let task := TaskScope.selected target in
    (* DEFENSE: The evaluator lease belongs to its captured history revision. *)
    let changes := if Nat.eqb source_length (List.length (task_history task))
      then Reasoning.complete_changes id outcome task
      else TaskChange.ChangePhase ReadyForModel :: Tasks.promote_changes (with_activity ReadyForModel task) in
    acknowledged (TaskChange.interpret (TaskChange.Plan value target changes))).
