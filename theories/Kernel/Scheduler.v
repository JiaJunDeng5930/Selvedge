From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates State Tasks SideContext Dispatch Capabilities NativeTools Callbacks Reasoning Limits Observation Search.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition executor := Selvedge.Generated.Commands.command -> option N -> world -> decision.
Definition before_plugins (task : task) :=
 Capabilities.hook_references Capabilities.BeforeTool (contract_plugins (task_contract task)).
Definition output_mode_for (task : task) :=
 if ContextUpdates.interactive_available (ContextUpdates.bindings (task_history task))
 then InteractiveOutput else PlainOutput.
Definition call_result (invocation : call) (result : json) (error : bool) (remaining : list call) (task : task) :=
 with_activity (PendingCalls remaining) (append_history [FunctionOutput (call_id invocation) result error] task).
Definition call_error (id : N) (invocation : call) (code reason : string) (remaining : list call) (task : task) (value : world) :=
 acknowledged (put_task id (with_activity (PendingCalls remaining)
  (append_history [FunctionOutput (call_id invocation) (State.failure code reason) true] task)) value).
Definition call_failure (id : N) (invocation : call) (reason : string) (remaining : list call) (task : task) (value : world) :=
 call_error id invocation "tool_rejected" reason remaining task value.
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
Definition append_operation (operation : operation) (remaining : list call) (task : task) :=
 with_activity (PendingCalls remaining) (with_operations (task_operations task ++ [operation]) task).
(* Bash may need stdin before it can finish. Other pending external operations
   wait for completion unless another committed input already needs inference. *)
Definition process_needs_model (value : operation) := negb (operation_announced value) &&
 String.eqb (call_name (operation_call value)) "bash" &&
 match operation_stage value with Executing _ | Elevated _ _ => true | _ => false end.
Definition continue_after_calls (task : task) :=
 let task := Tasks.promote task in with_activity
 (if unseen_model_input task || existsb process_needs_model (task_operations task) then WantsModel else Idle) task.
Definition start_external (id : N) (tool : tool) (invocation : call) (remaining : list call) (task : task) (value : world) :=
 if N.ltb (N.of_nat (List.length (task_operations task))) Limits.operation_limit then
 let '(ticket, allocated) := allocate_ticket value in
 let settings := task_current_settings task in
 let elevated := match settings_approval settings with
 | FullAccess => true
 | _ => String.eqb (call_name invocation) "bash" &&
   String.eqb (text_default "sandbox_permissions" (call_arguments invocation) "use_default") "require_escalated"
 end in
 if elevated then
 match settings_approval settings with
 | AskForApproval =>
   let operation := Operation ticket invocation false (AwaitingApproval ticket HumanReviewer) in
   acknowledged (put_task id (append_operation operation remaining task) allocated)
 | ReviewWith reviewer =>
     let operation := Operation ticket invocation false (AwaitingApproval ticket (ModelReviewer reviewer)) in
     accept (JObject [("accepted",JBool true)])
      (put_task id (append_operation operation remaining task) allocated)
      [RequestApproval id ticket reviewer invocation task]
 | FullAccess =>
   let operation := Operation ticket invocation false (Elevated ticket HumanReviewer) in
   accept (JObject [("accepted",JBool true)])
    (put_task id (append_operation operation remaining task) allocated)
    [ExecuteTool id ticket ticket tool invocation settings ElevatedAccess]
 end
 else
 let operation := Operation ticket invocation false (Executing ticket) in
 accept (JObject [("accepted",JBool true)])
  (put_task id (append_operation operation remaining task) allocated)
  [ExecuteTool id ticket ticket tool invocation settings DefaultAccess]
 else call_failure id invocation "The task's live operation limit has been reached" remaining task value.
Definition external_tool (tool : tool) :=
 match tool_origin tool with NativeToolSource _ _ => false | ExtensionToolSource _ _ _ | McpToolSource _ _ _ => true end.
Fixpoint keyword_parts (text : string) (current : string) (terms : list string) :=
 match text with EmptyString => rev (current :: terms)
 | String character rest => if Ascii.eqb character " "%char then keyword_parts rest "" (current :: terms)
    else keyword_parts rest (String.append current (String character EmptyString)) terms end.
Definition discover (task : task) (arguments : json) :=
 let tools := filter external_tool (contract_tools (task_contract task)) in
 let names := match Codec.strings (array_default "names" arguments) with Some values => values | None => [] end in
 let exact := negb (Nat.eqb (List.length names) 0) in
 let query := Search.lower (text_default "query" arguments "") in
 let matches := filter (fun tool => if exact then existsb (String.eqb (tool_name tool)) names
  else forallb (fun term => Search.contains term (Search.lower (String.append (tool_name tool) (String.append " " (tool_description tool))))) (keyword_parts query "" [])) tools in
 let offset := natural_default "offset" arguments 0 in
 let limit := natural_default "limit" arguments 5 in
 let page := if exact then matches else
  firstn (N.to_nat limit) (if N.leb offset (N.of_nat (List.length matches)) then skipn (N.to_nat offset) matches else []) in
 JObject [("tools",JArray (map (fun tool => JObject [("name",JString (tool_name tool));("description",JString (tool_description tool));("parameters",tool_schema tool)]) page));
  ("missing",JArray (map JString (filter (fun name => negb (existsb (fun tool => String.eqb name (tool_name tool)) tools)) names)));
  ("total_matches",number (N.of_nat (List.length matches)));
  ("has_more",JBool (negb exact && N.ltb (offset+limit)%N (N.of_nat (List.length matches))))].
Definition fork_receipts (start : N) (invocation : call) (value : world) :=
 with_tasks (indexed (fun id task => if N.leb start id then
  with_lifecycle (Running WantsModel [])
   (append_history [ForkReceipt id invocation (N.succ (id-start)%N)]
    (with_history (filter (History.without_inherited_result (call_id invocation)) (task_history task)) task))
  else task) 0 (world_tasks value)) value.
Definition internal_result_available (task : task) :=
 match Callbacks.after_plugins task with
 | [] => true
 | _ => N.ltb (N.of_nat (List.length (task_operations task))) Limits.operation_limit
 end.
Definition internal_result (id : N) (invocation : call) (remaining : list call)
 (result : json) (error : bool) (task : task) (value : world) :=
 match Callbacks.after_plugins task with
 | [] => acknowledged (put_task id (call_result invocation result error remaining task) value)
 | _ =>
   let '(ticket, value) := allocate_ticket value in
   let operation := Operation ticket invocation false (Executing ticket) in
   match task_lifecycle task with
   | Archived =>
     (* DEFENSE: archive_task can archive its own caller before returning;
        its raw result survives, but archival revoked callback authority. *)
     acknowledged (put_task id (append_history
      [ToolReceipt id ticket invocation result error;
       History.operation_result operation (State.failure "after_hook_interrupted"
        "The caller archived itself; its execution receipt is retained, but no result callback can run") true] task) value)
   | _ => Callbacks.tool_completed id ticket result error
     (put_task id (append_operation operation remaining task) value)
   end
 end.
Definition execute_checked_call (execute : executor) (id : N) (tool : tool) (invocation : call)
 (remaining : list call) (task : task) (value : world) :=
 if Capabilities.available (environment_tools (world_environment value)) tool && model_call_arguments_valid tool invocation then
 match NativeTools.command id invocation with
 | Some command =>
   if internal_result_available task then
   (* The native action owns this invocation now. A self-archive may cancel
      remaining calls, but must not also close this executing call as pending. *)
   let started := put_task id (with_activity (PendingCalls remaining) task) value in
   let result := execute command (Some id) started in
   let updated := if String.eqb (call_name invocation) "fork_task" then fork_receipts (next_task value) invocation (decision_world result)
     else decision_world result in
   let result_value := if String.eqb (call_name invocation) "fork_task" && bool_default "ok" (decision_reply result) false
     then number 0 else decision_reply result in
   match find_task id updated with
   | Some caller =>
     let settled := internal_result id invocation remaining result_value
       (negb (bool_default "ok" (decision_reply result) false)) caller updated in
     Decision (decision_world settled) (decision_reply result)
       (decision_effects result ++ decision_effects settled)
   | None => result end
   else call_failure id invocation "The task's live operation limit has been reached" remaining task value
 | None =>
   if String.eqb (call_name invocation) "discover_tools" then
    if internal_result_available task then
     internal_result id invocation remaining (State.success (discover task (call_arguments invocation))) false task value
    else call_failure id invocation "The task's live operation limit has been reached" remaining task value
   else start_external id tool invocation remaining task value
 end
 else call_failure id invocation "Arguments do not satisfy the tool's frozen schema" remaining task value.
Definition before_hook_step (execute : executor) (id : N) (tool : tool) (invocation : call)
 (pending : list json) (remaining : list call) (task : task) (value : world) :=
 match pending with
 | [] => execute_checked_call execute id tool invocation remaining task value
 | plugin :: rest =>
   if Capabilities.hook_available Capabilities.BeforeTool plugin (environment_plugins (world_environment value)) then
   let '(ticket, allocated) := allocate_ticket value in
   accept (JObject [("accepted",JBool true)])
    (put_task id (with_activity (CheckingHook ticket plugin invocation rest remaining) task) allocated)
    [CheckTool id ticket plugin tool invocation]
   else acknowledged (put_task id (call_result invocation
    (State.failure "hook_unavailable" "A required frozen plugin revision is unavailable; the tool was not dispatched")
    true remaining task) value)
 end.
Definition start_call (execute : executor) (id : N) (invocation : call) (remaining : list call) (task : task) (value : world) :=
 match find_tool (call_name invocation) (contract_tools (task_contract task)) with
 | None => call_failure id invocation "The tool is unavailable in the task's frozen contract" remaining task value
 | Some tool => before_hook_step execute id tool invocation (before_plugins task) remaining task value
 end.
Definition emit_model (id : N) (model : profile) (task : task) (value : world) :=
 let '(ticket, allocated) := allocate_ticket value in
 let callable := Capabilities.callable task (world_environment value) in
 let waiting := with_activity (AskingModel ticket callable (output_mode_for task))
  (with_model_cursor (List.length (task_history task)) task) in
 accept (JObject [("accepted",JBool true)])
  (put_task id waiting allocated) [RequestModel id ticket model waiting "" 0].
Definition ready_model (id : N) (task : task) (value : world) :=
 match Reasoning.next id task with
 | Reasoning.Fixed model => emit_model id model task value
 | Reasoning.Reuse model remaining => emit_model id model (Reasoning.generation id model remaining task) value
 | Reasoning.Evaluate =>
   let '(ticket, allocated) := allocate_ticket value in
   accept (JObject [("accepted",JBool true)])
    (put_task id
      (with_activity (EvaluatingReasoning ticket (List.length (task_history task))) task) allocated)
    [RequestReasoning id ticket (task_current_profile task) task]
 end.
Definition granted_operation (id : N) (operation : operation) (task : task) (value : world) :=
 match operation_stage operation, find_tool (call_name (operation_call operation)) (contract_tools (task_contract task)) with
 | Granted reviewer, Some tool =>
   if Capabilities.available (environment_tools (world_environment value)) tool then
   let '(ticket, allocated) := allocate_ticket value in
   let running := Operation (operation_id operation) (operation_call operation) (operation_announced operation) (Elevated ticket reviewer) in
   accept (JObject [("accepted",JBool true)])
    (put_task id (Tasks.wake_after_result (with_operations (replace_operation running (task_operations task)) task)) allocated)
    [ExecuteTool id ticket (operation_id operation) tool (operation_call operation) (task_current_settings task) ElevatedAccess]
   else acknowledged (put_task id (settle_operation operation (State.failure "approval_expired" "The tool capability changed before the one-operation grant could be used") true task) value)
 | Granted _, None => acknowledged (put_task id (settle_operation operation (State.failure "unknown_tool" "The granted tool is not in the frozen task contract") true task) value)
 | _,_ => acknowledged value
 end.
Definition ready_hooks (execute : executor) (id : N) (invocation : call) (pending : list json) (remaining : list call) (task : task) (value : world) :=
 match find_tool (call_name invocation) (contract_tools (task_contract task)) with
 | None => call_failure id invocation "The tool is unavailable in the task's frozen contract" remaining task value
 | Some tool => before_hook_step execute id tool invocation pending remaining task value
 end.
Definition after_hooks_step (id : N) (operation : operation) (task : task) (value : world) :=
 match operation_stage operation with
 | AfterHooksReady [] result error => acknowledged (put_task id (settle_operation operation result error task) value)
 | AfterHooksReady (plugin :: rest) result error =>
   if Capabilities.hook_available Capabilities.AfterTool plugin (environment_plugins (world_environment value)) then
   let '(ticket, allocated) := allocate_ticket value in
   let waiting := Operation (operation_id operation) (operation_call operation) (operation_announced operation)
    (AwaitingAfterHook ticket plugin rest result error) in
   accept (JObject [("accepted",JBool true)])
    (put_task id (with_operations (replace_operation waiting (task_operations task)) task) allocated)
    [CheckResult id ticket (operation_id operation) plugin (operation_call operation) result error]
   else let task := append_history [AfterReceipt id (operation_id operation) plugin
     (Inputs.after_json (Inputs.AfterFailure "The frozen result-processing plugin revision is unavailable"))] task in
   acknowledged (put_task id (settle_operation operation
     (State.failure "after_hook_unavailable" "The frozen result-processing plugin revision is unavailable; the tool has already completed") true task) value)
 | _ => acknowledged value
 end.
Definition ready_operation (operations : list operation) := find (fun operation =>
 match operation_stage operation with Granted _ | AfterHooksReady _ _ _ => true | _ => false end) operations.
Definition ready_settlement (operations : list operation) := find (fun operation =>
 match operation_stage operation with AfterHooksReady _ _ _ => true | _ => false end) operations.
Definition operation_step (id : N) (operation : operation) (task : task) (value : world) :=
 match operation_stage operation with Granted _ => granted_operation id operation task value
 | _ => after_hooks_step id operation task value end.
Definition task_step (execute : executor) (id : N) (task : task) (value : world) : option decision :=
 match task_lifecycle task with
 | Running phase operations =>
   match ready_operation operations with
   | Some operation => Some (operation_step id operation task value)
   | None => match phase with
     | WantsModel => Some (Reasoning.observe_context id (publish_operations (Tasks.promote task)) value)
     | ReadyForModel => Some (ready_model id task value)
     | ReadyForHooks invocation pending remaining => Some (ready_hooks execute id invocation pending remaining task value)
     | PendingCalls (first :: rest) => Some (start_call execute id first rest task value)
     | PendingCalls [] => Some (acknowledged (put_task id (continue_after_calls task) value))
     | Idle => match task_queued task with
       | [] => None
       | _ => Some (acknowledged (put_task id (Tasks.promote task) value)) end
     | _ => None end
   end
 | Stopped phase operations => match ready_settlement operations with
   | Some operation => Some (operation_step id operation task value)
   | None => match phase with
     | PendingCalls (first :: rest) => Some (start_call execute id first rest task value)
     | ReadyForHooks invocation pending remaining => Some (ready_hooks execute id invocation pending remaining task value)
     | PendingCalls [] | WantsModel | ReadyForModel => Some (acknowledged (put_task id (with_activity Idle (Tasks.promote task)) value))
     | _ => None end end
 | Frozen _ _ | Archived => None
 end.
Fixpoint find_step (execute : executor) (permitted : N -> world -> bool) (id : N) (tasks : list task) (value : world) : option decision :=
 match tasks with [] => None | task :: rest =>
 if permitted id value then
 match task_step execute id task value with Some decision => Some decision | None => find_step execute permitted (N.succ id) rest value end
 else find_step execute permitted (N.succ id) rest value end.
Definition task_has_work (value : task) :=
 match task_lifecycle value with
 | Running phase operations =>
   match ready_operation operations with Some _ => true | None =>
    match phase with WantsModel | ReadyForModel => true
    | ReadyForHooks _ _ _ | PendingCalls _ => true
    | Idle => negb (Nat.eqb (List.length (task_queued value)) 0) | _ => false end end
 | Stopped phase operations => match ready_settlement operations with Some _ => true | None =>
   match phase with WantsModel | ReadyForModel | ReadyForHooks _ _ _ | PendingCalls _ => true | _ => false end end
 | Frozen _ _ | Archived => false end.
Fixpoint schedule (fuel : nat) (execute : executor) (permitted : N -> world -> bool) (value : world) (effects : list effect) : world * list effect :=
 let value := SideContext.reconcile value in
 match fuel with
 | O => (value,if existsb (fun entry => let '(id,task) := entry in permitted id value && task_has_work task) (Numbers.indexed (fun id task => (id,task)) 0 (world_tasks value)) then effects ++ [ContinueScheduling] else effects)
 | S fuel => match find_step execute permitted 0 (world_tasks value) value with
   | None => (value,effects)
   | Some decision => schedule fuel execute permitted (decision_world decision) (effects ++ decision_effects decision)
   end
 end.
Definition run (execute : executor) (permitted : N -> world -> bool) (decision : decision) :=
 let '(value,effects) := schedule Limits.schedule_steps execute permitted (decision_world decision) (decision_effects decision) in
 let '(value,effects) := Dispatch.prepare value effects in
 Decision value (decision_reply decision) effects.
