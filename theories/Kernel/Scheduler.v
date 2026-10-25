From Selvedge.Kernel Require Import TaskScope TaskChange.
From Stdlib Require Import String Ascii List Bool NArith.
From Selvedge.Foundation Require Import Json Schema Utf8.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates State Tasks SideContext Dispatch Capabilities NativeTools Callbacks Reasoning Limits Observation Search TicketedRequest.
From Selvedge.Generated Require Import Commands.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.
Definition executor := Selvedge.Generated.Commands.command -> option Tasks.native_call -> world -> decision.
Definition before_plugins (task : task) :=
 Capabilities.hook_references Capabilities.BeforeTool (contract_plugins (task_contract task)).
Definition commit_changes (id : N) (changes : task -> list TaskChange.edit) (value : world) :=
 match TaskScope.select id value with
 | None => value
 | Some target => TaskChange.interpret
   (TaskChange.Plan value target (changes (TaskScope.selected target)))
 end.
Definition call_result_changes (invocation : call) (result : json) (error : bool) (remaining : list call) :=
 [TaskChange.AppendHistory [FunctionOutput (call_id invocation) result error];
  TaskChange.ChangePhase (PendingCalls remaining)].
Definition call_result (invocation : call) (result : json) (error : bool) (remaining : list call) (task : task) :=
 TaskChange.apply (call_result_changes invocation result error remaining) task.
Definition call_error (id : N) (invocation : call) (code reason : string) (remaining : list call) (task : task) (value : world) :=
 acknowledged (commit_changes id (fun _ => call_result_changes invocation (State.failure code reason) true remaining) value).
Definition operation_notice := TicketedRequest.operation_notice.
Definition announce_operation := TicketedRequest.announce_operation.
Definition publish_operations := TicketedRequest.publish_operations.
Definition append_operation := TicketedRequest.append_operation.
(* Bash may need stdin before it can finish. Other pending external operations
   wait for completion unless another committed input already needs inference. *)
Definition process_needs_model (value : operation) := negb (operation_announced value) &&
 String.eqb (call_name (operation_call value)) "bash" &&
 match operation_stage value with Executing _ | Elevated _ _ => true | _ => false end.
Definition continue_after_calls_changes (task : task) :=
 let promoted := Tasks.promote task in
 Tasks.promote_changes task ++ [TaskChange.ChangePhase
  (if unseen_model_input promoted || existsb process_needs_model (task_operations promoted) then WantsModel else Idle)].
Definition continue_after_calls (task : task) := TaskChange.apply (continue_after_calls_changes task) task.
Definition start_external (id : N) (value : world) :=
 match TicketedRequest.Scoped.start id value with
 | None => State.ignored value
 | Some (request,invocation,remaining) =>
   let task := TaskScope.selected (TicketedRequest.Scoped.target request) in
   if N.ltb (N.of_nat (List.length (task_operations task))) Limits.operation_limit then
     TicketedRequest.Scoped.issue request
   else call_error id invocation "operation_limit" "This task has reached its in-flight operation limit; wait for results or cancel an operation" remaining task value
 end.
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
Definition internal_result_available (task : task) :=
 match Callbacks.after_plugins task with
 | [] => true
 | _ => N.ltb (N.of_nat (List.length (task_operations task))) Limits.operation_limit
 end.
Definition internal_result (id : N) (invocation : call) (remaining : list call)
 (result : json) (error : bool) (task : task) (value : world) :=
 match Callbacks.after_plugins task with
 | [] => acknowledged (commit_changes id (fun _ => call_result_changes invocation result error remaining) value)
 | _ =>
   let '(ticket, value) := allocate_ticket value in
   let operation := Operation ticket invocation false (Executing ticket) in
   Callbacks.tool_completed id ticket result error
     (commit_changes id (fun _ => [TaskChange.AddOperation operation; TaskChange.ChangePhase (PendingCalls remaining)]) value)
 end.
Definition call_admission (tool : tool) (invocation : call) (value : world) :=
 if negb (Capabilities.available (environment_tools (world_environment value)) tool) then
   Some ("tool_unavailable", "The task's frozen tool route is unavailable")
 else if negb (model_call_arguments_valid tool invocation) then
   Some ("invalid_arguments", "Tool arguments do not satisfy its frozen schema")
 else None.
Definition retry_safe (tool : tool) := match tool_origin tool with
 | NativeToolSource _ program => match field "kind" program with
   | Some (JString "Command") | Some (JString "Discover") => true | _ => false end
 | _ => false end.
Definition execute_checked_call (execute : executor) (id : N) (tool : tool) (invocation : call)
 (remaining : list call) (task : task) (value : world) :=
 match call_admission tool invocation value with
 | Some (code,reason) => call_error id invocation code reason remaining task value
 | None => match NativeTools.command id invocation with
 | Some command =>
   if internal_result_available task then
   (* The native action owns this invocation now. A self-archive may cancel
      remaining calls, but must not also close this executing call as pending. *)
   let started := commit_changes id (fun _ => [TaskChange.ChangePhase (PendingCalls remaining)]) value in
   let result := execute command (Some (Tasks.NativeCall id invocation remaining)) started in
   let updated := decision_world result in
   let result_value := if String.eqb (call_name invocation) "fork_task" && bool_default "ok" (decision_reply result) false
     then number 0 else decision_reply result in
   match find_task id updated with
   | Some caller =>
     let settled := internal_result id invocation remaining result_value
       (negb (bool_default "ok" (decision_reply result) false)) caller updated in
     Decision (decision_world settled) (decision_reply result)
       (decision_effects result ++ decision_effects settled)
   | None => result end
   else call_error id invocation "operation_limit" "This task has reached its result-processing operation limit; wait for results or cancel an operation" remaining task value
 | None =>
   if String.eqb (call_name invocation) "discover_tools" then
    if internal_result_available task then
     internal_result id invocation remaining (State.success (discover task (call_arguments invocation))) false task value
    else call_error id invocation "operation_limit" "This task has reached its result-processing operation limit; wait for results or cancel an operation" remaining task value
   else start_external id value
 end end.
Definition before_hook_step (execute : executor) (id : N) (tool : tool) (invocation : call)
 (pending : list json) (remaining : list call) (task : task) (value : world) :=
 match pending with
 | [] => execute_checked_call execute id tool invocation remaining task value
 | plugin :: rest =>
   if Capabilities.hook_available Capabilities.BeforeTool plugin (environment_plugins (world_environment value)) then
   TicketedRequest.Scoped.run (TicketedRequest.Scoped.authorize id value)
   else call_error id invocation "hook_unavailable" "A required frozen plugin revision is unavailable; the tool was not dispatched" remaining task value
 end.
Definition start_call (execute : executor) (id : N) (invocation : call) (remaining : list call) (task : task) (value : world) :=
 match find_tool (call_name invocation) (contract_tools (task_contract task)) with
 | None => call_error id invocation "unknown_tool" "The call does not name a tool in the task contract" remaining task value
 | Some tool => if match call_origin invocation with InitialAttempt => true | RecoveryAttempt => retry_safe tool end then
     before_hook_step execute id tool invocation (before_plugins task) remaining task value
     else call_error id invocation "outcome_unknown"
       "The effect may already have happened; automatic repetition is forbidden" remaining task value
 end.
Definition ready_model (id : N) (value : world) :=
 TicketedRequest.Scoped.run (TicketedRequest.Scoped.model id value).
Definition granted_operation (id : N) (operation : operation) (task : task) (value : world) :=
 match operation_stage operation, find_tool (call_name (operation_call operation)) (contract_tools (task_contract task)) with
 | Granted reviewer, Some tool =>
   if Capabilities.available (environment_tools (world_environment value)) tool then
   TicketedRequest.Scoped.run (TicketedRequest.Scoped.resume id (operation_id operation) value)
   else acknowledged (commit_changes id (Callbacks.begin_result_changes id operation (State.failure "tool_unavailable" "The tool capability changed before the one-operation grant could be used") true) value)
 | Granted _, None => acknowledged (commit_changes id (Callbacks.begin_result_changes id operation (State.failure "tool_unavailable" "The granted tool is not in the frozen task contract") true) value)
 | _,_ => acknowledged value
 end.
Definition ready_hooks (execute : executor) (id : N) (invocation : call) (pending : list json) (remaining : list call) (task : task) (value : world) :=
 match find_tool (call_name invocation) (contract_tools (task_contract task)) with
 | None => call_error id invocation "unknown_tool" "The call does not name a tool in the task contract" remaining task value
 | Some tool => before_hook_step execute id tool invocation pending remaining task value
 end.
Definition after_hooks_step (id : N) (operation : operation) (task : task) (value : world) :=
 match operation_stage operation with
 | AfterHooksReady [] result error => acknowledged (commit_changes id (Callbacks.settle_operation_changes operation result error) value)
 | AfterHooksReady (plugin :: rest) result error =>
   if Capabilities.hook_available Capabilities.AfterTool plugin (environment_plugins (world_environment value)) then
   TicketedRequest.Scoped.run (TicketedRequest.Scoped.after id (operation_id operation) value)
   else acknowledged (commit_changes id (fun task =>
     let receipt := TaskChange.AppendHistory [AfterReceipt id (operation_id operation) plugin
       (Inputs.after_json (Inputs.AfterFailure "The frozen result-processing plugin revision is unavailable"))] in
     [receipt] ++ Callbacks.settle_operation_changes operation
       (State.failure "after_hook_unavailable" "The frozen result-processing plugin revision is unavailable; the tool has already completed") true
       (TaskChange.apply_edit receipt task)) value)
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
     | WantsModel => Some (Reasoning.observe_scheduled_context id value)
     | ReadyForModel => Some (ready_model id value)
     | ReadyForHooks invocation pending remaining => Some (ready_hooks execute id invocation pending remaining task value)
     | PendingCalls (first :: rest) => Some (start_call execute id first rest task value)
     | PendingCalls [] => Some (acknowledged (commit_changes id continue_after_calls_changes value))
     | Idle => match task_queued task with
       | [] => None
       | _ => Some (acknowledged (commit_changes id Tasks.promote_changes value)) end
     | _ => None end
   end
 | Stopped phase operations => match ready_settlement operations with
   | Some operation => Some (operation_step id operation task value)
   | None => match phase with
     | PendingCalls (first :: rest) => Some (start_call execute id first rest task value)
     | ReadyForHooks invocation pending remaining => Some (ready_hooks execute id invocation pending remaining task value)
     | PendingCalls [] | WantsModel | ReadyForModel => Some (acknowledged (commit_changes id (fun task => Tasks.promote_changes task ++ [TaskChange.ChangePhase Idle]) value))
     | _ => None end end
 | Frozen _ operations | Archived operations => match ready_settlement operations with
   | Some operation => Some (operation_step id operation task value) | None => None end
 end.
Definition task_has_work (value : task) :=
 match task_lifecycle value with
 | Running phase operations =>
   match ready_operation operations with Some _ => true | None =>
    match phase with WantsModel | ReadyForModel => true
    | ReadyForHooks _ _ _ | PendingCalls _ => true
    | Idle => negb (Nat.eqb (List.length (task_queued value)) 0) | _ => false end end
 | Stopped phase operations => match ready_settlement operations with Some _ => true | None =>
   match phase with WantsModel | ReadyForModel | ReadyForHooks _ _ _ | PendingCalls _ => true | _ => false end end
 | Frozen _ operations | Archived operations =>
   match ready_settlement operations with Some _ => true | None => false end end.
Inductive runnable_step := SettlementStep (pending : operation) | ExecutionStep.
Definition next_runnable_step (permitted : N -> world -> bool) (id : N) (task : task) (value : world) :=
 if permitted id value then
   if task_has_work task then Some ExecutionStep else None
 else option_map SettlementStep (ready_settlement (task_operations task)).
(* A native fork is committed between scheduler transactions. This selection
   recognizes only the next actual runnable task and only its final dispatch
   gate, so before hooks and earlier task work retain their ordering. *)
Record native_fork_step := NativeForkStep {
 native_fork_owner : N;
 native_fork_invocation : call;
 native_fork_remaining : list call;
 native_fork_tool : tool;
 native_fork_request : Commands.fork_payload
}.
Definition fork_dispatch_call (task : task) :=
 let ready := match task_lifecycle task with
 | Running phase operations => match ready_operation operations with
   | None => Some phase | Some _ => None end
 | Stopped phase operations => match ready_settlement operations with
   | None => Some phase | Some _ => None end
 | _ => None end in
 match ready with
 | Some (ReadyForHooks invocation [] remaining) => Some (invocation,remaining,false)
 | Some (PendingCalls (invocation :: remaining)) =>
   match before_plugins task with [] => Some (invocation,remaining,true) | _ => None end
 | _ => None end.
Definition native_fork_ready (id : N) (task : task) (value : world) :=
 match fork_dispatch_call task with
 | Some (invocation,remaining,retry) =>
   match find_tool (call_name invocation) (contract_tools (task_contract task)) with
   | Some definition =>
     if (if retry then match call_origin invocation with InitialAttempt => true
         | RecoveryAttempt => retry_safe definition end else true) &&
        String.eqb (call_name invocation) "fork_task" && internal_result_available task then
       match call_admission definition invocation value, NativeTools.command id invocation with
       | None, Some (Commands.Cmd_fork request) =>
         if N.eqb id (Commands.fork_task_id request)
         then Some (NativeForkStep id invocation remaining definition request) else None
       | _,_ => None end
     else None
   | None => None end
 | None => None end.
Fixpoint first_native_fork (permitted : N -> world -> bool) (id : N)
 (tasks : list task) (value : world) :=
 match tasks with
 | [] => None
 | task :: rest => match next_runnable_step permitted id task value with
   | Some ExecutionStep => native_fork_ready id task value
   | Some (SettlementStep _) => None
   | None => first_native_fork permitted (N.succ id) rest value end
 end.
Definition interpret_step (execute : executor) (id : N) (task : task) (value : world) (step : runnable_step) :=
 match step with
 | SettlementStep pending => Some (operation_step id pending task value)
 | ExecutionStep => task_step execute id task value end.
Fixpoint find_step (execute : executor) (permitted : N -> world -> bool) (id : N) (tasks : list task) (value : world) : option decision :=
 match tasks with [] => None | task :: rest =>
 match next_runnable_step permitted id task value with
 | Some step => match interpret_step execute id task value step with
   | Some decision => Some decision | None => find_step execute permitted (N.succ id) rest value end
 | None => find_step execute permitted (N.succ id) rest value end end.
Fixpoint schedule (fuel : nat) (execute : executor) (permitted : N -> world -> bool) (value : world) (effects : list effect) : world * list effect :=
 let value := SideContext.reconcile value in
 match fuel with
 | O => (value,if existsb (fun entry => let '(id,task) := entry in match next_runnable_step permitted id task value with Some _ => true | None => false end) (Selvedge.Foundation.Registry.indexed (fun id task => (id,task)) 0 (world_tasks value)) then effects ++ [ContinueScheduling] else effects)
 | S fuel => match first_native_fork permitted 0 (world_tasks value) value with
   | Some _ => (value,effects ++ [ContinueScheduling])
   | None => match find_step execute permitted 0 (world_tasks value) value with
     | None => (value,effects)
     | Some decision => schedule fuel execute permitted (decision_world decision) (effects ++ decision_effects decision)
     end
   end
 end.
Definition run (execute : executor) (permitted : N -> world -> bool) (decision : decision) :=
 let '(value,effects) := schedule Limits.schedule_steps execute permitted (decision_world decision) (decision_effects decision) in
 let '(value,effects) := Dispatch.prepare value effects in
 Decision value (decision_reply decision) effects.
