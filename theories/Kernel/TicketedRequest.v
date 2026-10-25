From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Tasks Capabilities ContextUpdates Codec ReasoningPlan.
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
Definition issue (owner : N) (source : request) (before : world) :=
 let ticket := world_next_ticket before in
 let '(pending,effects) := build owner ticket (world_environment before) source in
 accept (JObject [("accepted",JBool true)])
   (put_task owner pending (with_ticket (N.succ ticket) before)) effects.

Module Scoped.
Record task_reference (before : world) := TaskReference {
 owner : N;
 selected : task;
 observed : find_task owner before = Some selected
}.
Arguments owner {before}.
Arguments selected {before}.
Arguments observed {before}.
Definition select (id : N) (before : world) : option (task_reference before) :=
 match find_task id before as found return find_task id before = found -> option (task_reference before) with
 | Some current => fun evidence => Some (TaskReference before id current evidence)
 | None => fun _ => None end eq_refl.
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
Definition call_action (current : task) : option action :=
 let prepare invocation pending remaining :=
   match find_tool (call_name invocation) (contract_tools (task_contract current)) with
   | None => None
   | Some tool => Some (match pending with
     | [] => StartCall tool invocation remaining (external_authority_for current invocation)
     | plugin :: rest => AuthorizeCall plugin tool invocation rest remaining end)
   end in
 match task_activity current with
 | PendingCalls (invocation :: remaining) => prepare invocation
     (Capabilities.hook_references Capabilities.BeforeTool (contract_plugins (task_contract current))) remaining
 | ReadyForHooks invocation pending remaining => prepare invocation pending remaining
 | _ => None end.
Definition admitted_action (owner : N) (current : task) (source : action) : Prop := match source with
 | AuthorizeCall _ _ _ _ _ | StartCall _ _ _ _ => call_action current = Some source
 | ResumeOperation operation tool reviewer =>
   operation_at (operation_id operation) current = Some operation /\
   operation_stage operation = Granted reviewer /\
   find_tool (call_name (operation_call operation)) (contract_tools (task_contract current)) = Some tool
 | AfterOperation operation plugin pending result error =>
   operation_at (operation_id operation) current = Some operation /\
   operation_stage operation = AfterHooksReady (plugin :: pending) result error
 | _ => True end.
Record plan (before : world) := Plan {
 target : task_reference before;
 intent : action;
 operation_observed : admitted_action (owner target) (selected target) intent
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
Definition observe (id : N) (publish : bool) (before : world) : option (plan before) :=
 match select id before with
 | Some target => Some (Plan before target (ObserveTask publish) I)
 | None => None end.
Definition model (id : N) (before : world) : option (plan before) :=
 match select id before with
 | Some target => Some (Plan before target InferTask I)
 | None => None end.
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
         Some (Plan before target (ResumeOperation current tool reviewer)
           (conj (eq_ind identity (fun key => operation_at key (selected target) = Some current) found
             (operation_id current) (operation_at_identity identity (selected target) current found)) (conj granted known)))
       end eq_refl
     | _ => fun _ => None end eq_refl
   end eq_refl
 end.
Definition run {before} (candidate : option (plan before)) :=
 match candidate with Some value => issue value
 (* DEFENSE: A selected task or operation may have been removed by an earlier
    action in this atomic schedule; an absent current reference has no IO right. *)
 | None => State.ignored before end.
End Scoped.
