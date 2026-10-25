From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State TaskScope TaskScopeProofs TaskChange TaskChangeProofs Tasks TaskChangesProofs History Context ContextUpdates Callbacks HookCallbacks Reasoning Inputs
 ApprovalProtocol Scheduler HookRules.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Definition applying_change_lists := TaskChangeProofs.apply_app.

Lemma model_completed_expression : forall id ticket outcome value,
 Callbacks.model_completed id ticket outcome value =
 match find_task id value with
 | None => ignored value
 | Some task => match task_activity task with
   | AskingModel expected allowed mode =>
     if N.eqb expected ticket then acknowledged (put_task id (Callbacks.model_result id ticket allowed mode outcome task) value)
     else ignored value
   | _ => ignored value end
 end.
Proof.
 intros. unfold Callbacks.model_completed.
 apply (selected_result_erases_its_lookup_witness decision id value
   (fun candidate => match candidate with
    | None => ignored value
    | Some target => let task := TaskScope.selected target in match task_activity task with
      | AskingModel expected allowed mode => if N.eqb expected ticket then
        acknowledged (TaskChange.interpret (TaskChange.Plan value target (Callbacks.model_result_changes id ticket allowed mode outcome task)))
        else ignored value
      | _ => ignored value end end)
   (fun owner task => match task_activity task with
    | AskingModel expected allowed mode => if N.eqb expected ticket then
      acknowledged (put_task owner (Callbacks.model_result id ticket allowed mode outcome task) value)
      else ignored value
    | _ => ignored value end) (ignored value)); intros; reflexivity.
Qed.

Lemma settle_model_expression : forall task,
 Callbacks.settle_model task = Tasks.promote (with_activity
 (if unseen_model_input task then WantsModel else Idle) task).
Proof. reflexivity. Qed.
Lemma model_result_expression : forall owner ticket allowed mode outcome task,
 Callbacks.model_result owner ticket allowed mode outcome task =
 match outcome with
 | ModelFailure text => Callbacks.settle_model (append_history [FailureMessage text] task)
 | ModelContextLimit => Callbacks.settle_model (append_history [FailureMessage "Model context limit reached; full task history retained"] task)
 | ModelSuccess items =>
   if Callbacks.permitted_items items allowed task [] [] then
   let task := append_history (Callbacks.item_messages owner ticket mode items) task in
   match Callbacks.item_calls items with
   | [] => Callbacks.settle_model task
   | calls => with_activity (PendingCalls calls) task end
   else Callbacks.settle_model (append_history [FailureMessage "Invalid model reply: duplicate output part or call identity, unavailable tool, or invalid arguments"] task)
 end.
Proof.
 intros owner ticket allowed mode [items|text|] task;
 unfold Callbacks.model_result, Callbacks.model_result_changes;
 try reflexivity.
 destruct (Callbacks.permitted_items items allowed task [] []); [|reflexivity].
 destruct (Callbacks.item_calls items); reflexivity.
Qed.
Lemma record_context_diagnostic_expression : forall message task,
 Callbacks.record_context_diagnostic message task =
 if existsb (fun entry => match entry with
   | FailureMessage previous => String.eqb previous message | _ => false end) (task_history task)
 then task else append_history [FailureMessage message] task.
Proof.
 intros; unfold Callbacks.record_context_diagnostic, Callbacks.record_context_diagnostic_changes.
 destruct (existsb _ _); reflexivity.
Qed.
Lemma context_diagnostic_changes_expression : forall messages task,
 TaskChange.apply (Callbacks.context_diagnostic_changes messages task) task =
 fold_left (fun task message => Callbacks.record_context_diagnostic message task) messages task.
Proof.
 induction messages as [|message rest IH]; intros task; [reflexivity|].
 cbn [Callbacks.context_diagnostic_changes fold_left]. rewrite applying_change_lists, IH.
 reflexivity.
Qed.
Lemma observed_context_expression : forall observations diagnostic task,
 Callbacks.observed_context observations diagnostic task =
 match observations with
 | None => (false,Callbacks.record_context_diagnostic diagnostic task)
 | Some observations =>
   let '(changes,diagnostics) := ContextUpdates.observe_all observations (ContextUpdates.bindings (task_history task)) in
   (Nat.eqb (List.length diagnostics) 0,
    fold_left (fun task message => Callbacks.record_context_diagnostic message task) diagnostics
      (append_history (map ContextObservation changes) task))
 end.
Proof.
 intros [observations|] diagnostic task; [|reflexivity].
 unfold Callbacks.observed_context, Callbacks.observed_context_changes.
 destruct (ContextUpdates.observe_all observations (ContextUpdates.bindings (task_history task))) as [changes diagnostics].
 cbn [TaskChange.apply fold_left TaskChange.apply_edit].
 rewrite <- context_diagnostic_changes_expression. reflexivity.
Qed.
Lemma settle_operation_expression : forall operation result error task,
 Callbacks.settle_operation operation result error task =
 Tasks.wake_after_result (with_operations (Callbacks.remove_operation (operation_id operation) (task_operations task))
 (append_history [History.operation_result operation result error] task)).
Proof.
 intros; unfold Callbacks.settle_operation, Callbacks.settle_operation_changes.
 rewrite applying_change_lists. reflexivity.
Qed.

Lemma tool_completed_expression : forall (id ticket : N) (result : json) (error : bool) (value : world),
 Callbacks.tool_completed id ticket result error value =
 match find_task id value with
 | None => ignored value
 | Some task => match find (operation_executing ticket) (task_operations task) with
   | None => ignored value
   | Some operation => acknowledged (put_task id (begin_result id operation result error task) value)
   end
 end.
Proof.
 intros. unfold Callbacks.tool_completed.
 apply (selected_result_erases_its_lookup_witness decision id value
 (fun candidate => 
 match candidate with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match find (operation_executing ticket) (task_operations task) with
   | None => ignored value
   | Some operation => acknowledged (TaskChange.interpret (TaskChange.Plan value target (begin_result_changes id operation result error task)))
   end
 end)
 (fun owner task => match find (operation_executing ticket) (task_operations task) with
   | None => ignored value
   | Some operation => acknowledged (put_task owner (begin_result id operation result error task) value)
   end)
 (ignored value)); intros; reflexivity.
Qed.

Lemma approval_completed_expression : forall (id ticket : N) (outcome : approval_outcome) (value : world),
 Callbacks.approval_completed id ticket outcome value =
 match find_task id value with
 | None => ignored value
 | Some task => match find_pending_approval (fun _ expected actor => match actor with
   | ModelReviewer _ => N.eqb ticket expected | HumanReviewer => false end) (task_operations task) with
   | None => ignored value
   | Some (operation,actor) => acknowledged (put_task id (approval_decision id operation actor outcome task) value)
   end end.
Proof.
 intros. unfold Callbacks.approval_completed.
 apply (selected_result_erases_its_lookup_witness decision id value
 (fun candidate => 
 match candidate with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match find_pending_approval (fun _ expected actor => match actor with
   | ModelReviewer _ => N.eqb ticket expected | HumanReviewer => false end) (task_operations task) with
   | None => ignored value
   | Some (operation,actor) => acknowledged (TaskChange.interpret (TaskChange.Plan value target (approval_decision_changes id operation actor outcome task)))
   end end)
 (fun owner task => match find_pending_approval (fun _ expected actor => match actor with
   | ModelReviewer _ => N.eqb ticket expected | HumanReviewer => false end) (task_operations task) with
   | None => ignored value
   | Some (operation,actor) => acknowledged (put_task owner (approval_decision id operation actor outcome task) value)
   end)
 (ignored value)); intros; reflexivity.
Qed.

Lemma review_approval_expression : forall (id operation : N) (outcome : approval_outcome) (value : world),
 Callbacks.review_approval id operation outcome value =
 let stale := reject "approval_not_pending"
   "This task has no pending human approval with that operation identity" value in
 match find_task id value with
 | None => stale
 | Some task => match find_pending_approval (fun candidate _ actor => N.eqb operation candidate &&
   match actor with HumanReviewer => true | ModelReviewer _ => false end) (task_operations task) with
   | None => stale
   | Some (operation,actor) => acknowledged (put_task id (approval_decision id operation actor outcome task) value)
   end end.
Proof.
 intros. unfold Callbacks.review_approval.
 cbn zeta.
 apply (selected_result_erases_its_lookup_witness decision id value
 (fun candidate => 
 let stale := reject "approval_not_pending"
   "This task has no pending human approval with that operation identity" value in
 match candidate with
 | None => stale
 | Some target => let task := TaskScope.selected target in match find_pending_approval (fun candidate _ actor => N.eqb operation candidate &&
   match actor with HumanReviewer => true | ModelReviewer _ => false end) (task_operations task) with
   | None => stale
   | Some (operation,actor) => acknowledged (TaskChange.interpret (TaskChange.Plan value target (approval_decision_changes id operation actor outcome task)))
   end end)
 (fun owner task => 
 let stale := reject "approval_not_pending"
   "This task has no pending human approval with that operation identity" value in
 match find_pending_approval (fun candidate _ actor => N.eqb operation candidate &&
   match actor with HumanReviewer => true | ModelReviewer _ => false end) (task_operations task) with
   | None => stale
   | Some (operation,actor) => acknowledged (put_task owner (approval_decision id operation actor outcome task) value)
   end)
 (reject "approval_not_pending" "This task has no pending human approval with that operation identity" value)); intros; reflexivity.
Qed.

Lemma reasoning_completed_expression : forall (id ticket : N) (outcome : Reasoning.outcome) (value : world),
 Callbacks.reasoning_completed id ticket outcome value =
 match find_task id value with
 | None => ignored value
 | Some task => match task_activity task with
   | EvaluatingReasoning expected source_length => if N.eqb expected ticket then
      let updated := if Nat.eqb source_length (List.length (task_history task))
        then Reasoning.complete id outcome task
        else Tasks.promote (with_activity ReadyForModel task) in
      acknowledged (put_task id updated value)
      else ignored value
   | _ => ignored value end
 end.
Proof.
 intros. unfold Callbacks.reasoning_completed.
 apply (selected_result_erases_its_lookup_witness decision id value
 (fun candidate => 
 match candidate with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match task_activity task with
   | EvaluatingReasoning expected source_length => if N.eqb expected ticket then
      let changes := if Nat.eqb source_length (List.length (task_history task))
        then Reasoning.complete_changes id outcome task
        else TaskChange.ChangePhase ReadyForModel :: Tasks.promote_changes (with_activity ReadyForModel task) in
      acknowledged (TaskChange.interpret (TaskChange.Plan value target changes))
      else ignored value
   | _ => ignored value end
 end)
 (fun owner task => match task_activity task with
   | EvaluatingReasoning expected source_length => if N.eqb expected ticket then
      let updated := if Nat.eqb source_length (List.length (task_history task))
        then Reasoning.complete id outcome task
        else Tasks.promote (with_activity ReadyForModel task) in
      acknowledged (put_task owner updated value)
      else ignored value
   | _ => ignored value end)
 (ignored value)); [|reflexivity].
 intros reference; cbn zeta; destruct (task_activity (TaskScope.selected reference)); try reflexivity;
 repeat match goal with |- context [if ?test then _ else _] => destruct test end; reflexivity.
Qed.

Lemma begin_result_expression : forall owner operation result error task,
 Callbacks.begin_result owner operation result error task =
 match Callbacks.after_plugins task with
 | [] => Callbacks.settle_operation operation result error task
 | pending => with_operations
   (map (fun current => if N.eqb (operation_id operation) (operation_id current)
     then Operation (operation_id current) (operation_call current) (operation_announced current)
       (AfterHooksReady pending result error) else current) (task_operations task))
   (append_history [ToolReceipt owner (operation_id operation) (operation_call operation) result error] task)
 end.
Proof.
 intros; unfold Callbacks.begin_result, Callbacks.begin_result_changes.
 destruct (Callbacks.after_plugins task); [reflexivity|].
 destruct task as [contract profile settings lifecycle history queued lineage side cursor consumed]; destruct lifecycle; reflexivity.
Qed.
Lemma approval_decision_expression : forall owner operation reviewed_by outcome task,
 Callbacks.approval_decision owner operation reviewed_by outcome task =
 let outcome := ApprovalProtocol.normalize_outcome outcome in
 let task := append_history [ApprovalReceipt owner (operation_id operation) (operation_call operation)
   reviewed_by (Inputs.approval_json outcome)] task in
 match outcome with
 | Approved _ => with_operations
   (map (fun current => if N.eqb (operation_id operation) (operation_id current)
     then Operation (operation_id current) (operation_call current) (operation_announced current)
       (Granted reviewed_by) else current) (task_operations task)) task
 | Denied reason | ApprovalFailed reason => Callbacks.begin_result owner operation
   (State.failure "approval_denied" ("Bash was not started. " ++ reason)) true task
 end.
Proof.
 intros; unfold Callbacks.approval_decision, Callbacks.approval_decision_changes.
 destruct (ApprovalProtocol.normalize_outcome outcome); reflexivity.
Qed.
Lemma failed_reasoning_expression : forall reason task,
 Reasoning.failed reason task = Tasks.promote
 (with_activity Idle (append_history [FailureMessage ("Automatic reasoning: " ++ reason)] task)).
Proof. reflexivity. Qed.
Lemma complete_reasoning_expression : forall owner outcome task,
 Reasoning.complete owner outcome task =
 match profile_policy (task_current_profile task) with
 | FixedReasoning => task
 | AdaptivePolicy policy =>
   match outcome with
   | Reasoning.Chosen effort generations =>
     if Reasoning.allowed policy effort && ReasoningProtocol.valid_generations (reasoning_max_lease policy) generations
     then Tasks.promote (with_activity ReadyForModel
       (append_history [ReasoningRecord owner effort generations false] task))
     else Reasoning.failed "the evaluator selected an unsupported effort or lease; no model request was sent" task
   | Reasoning.EvaluationFailed reason => Reasoning.failed reason task
   end
 end.
Proof.
 intros; unfold Reasoning.complete, Reasoning.complete_changes.
 destruct (profile_policy (task_current_profile task)); [reflexivity|].
 destruct outcome; [destruct (Reasoning.allowed _ _ && ReasoningProtocol.valid_generations _ _)|]; reflexivity.
Qed.

Definition promotion_expression := TaskChangesProofs.promotion_expression.
Definition waking_result_expression := TaskChangesProofs.waking_result_expression.

Lemma context_ready_expression : forall (accepted : bool) (id : N) (task : task) (value : world),
 Callbacks.context_ready accepted id task value =
 match find_task id value with | None => ignored value | Some current => context_response accepted
   (put_task id (TaskChange.apply [TaskChange.ChangePhase (context_phase task)] current) value) end.
Proof.
 intros. unfold Callbacks.context_ready.
 apply (selected_result_erases_its_lookup_witness decision id value
 (fun candidate => 
 match candidate with
 | None => ignored value
 | Some target => context_response accepted
   (TaskChange.interpret (TaskChange.Plan value target [TaskChange.ChangePhase (context_phase task)]))
 end)
 (fun owner current => context_response accepted
   (put_task owner (TaskChange.apply [TaskChange.ChangePhase (context_phase task)] current) value)) (ignored value)); intros; reflexivity.
Qed.

Lemma context_completed_expression : forall (id ticket : N) (observations : option (list context_observation)) (diagnostic : string) (value : world),
 Callbacks.context_completed id ticket observations diagnostic value =
 match find_task id value with | None => ignored value | Some task => match task_activity task with
   | ObservingContext expected revision => if N.eqb expected ticket then
     if Nat.eqb revision (List.length (task_history task)) then
       let '(accepted,changes) := observed_context_changes observations diagnostic task in
       context_response accepted (put_task id (TaskChange.apply (changes ++ [TaskChange.ChangePhase (context_phase task)]) task) value)
     else match task_lifecycle task with
       | Running _ _ => Reasoning.observe_context id value
       | _ => context_ready false id task value end
     else ignored value
   | _ => ignored value end end.
Proof.
 intros. unfold Callbacks.context_completed.
 apply (selected_result_erases_its_lookup_witness decision id value
 (fun candidate => 
 match candidate with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match task_activity task with
   | ObservingContext expected revision => if N.eqb expected ticket then
     if Nat.eqb revision (List.length (task_history task)) then
       let '(accepted,changes) := observed_context_changes observations diagnostic task in
       context_response accepted (TaskChange.interpret (TaskChange.Plan value target          (changes ++ [TaskChange.ChangePhase (context_phase task)])))
     else match task_lifecycle task with
       | Running _ _ => Reasoning.observe_context id value
       | _ => context_ready false id task value end
     else ignored value
   | _ => ignored value end
 end)
 (fun owner task => match task_activity task with
   | ObservingContext expected revision => if N.eqb expected ticket then
     if Nat.eqb revision (List.length (task_history task)) then
       let '(accepted,changes) := observed_context_changes observations diagnostic task in
       context_response accepted (put_task owner (TaskChange.apply (changes ++ [TaskChange.ChangePhase (context_phase task)]) task) value)
     else match task_lifecycle task with
       | Running _ _ => Reasoning.observe_context id value
       | _ => context_ready false id task value end
     else ignored value
   | _ => ignored value end) (ignored value)); intros; reflexivity.
Qed.

Lemma task_changes_preserve_the_frozen_contract : forall changes task,
 task_contract (TaskChange.apply changes task) = task_contract task.
Proof.
 intros changes task; exact (proj1 (TaskChangeProofs.field_changes_keep_the_immutable_task_identity changes task)).
Qed.

Lemma hook_completed_expression : forall (id ticket : N) (outcome : hook_outcome) (value : world),
 HookCallbacks.hook_completed id ticket outcome value =
 match find_task id value with | None => ignored value | Some task => match task_activity task with
   | CheckingHook expected plugin invocation pending remaining =>
     if N.eqb expected ticket then
     let receipt := TaskChange.AppendHistory [HookReceipt id invocation plugin (hook_json outcome)] in
     let changes := receipt :: match HookRules.before_apply invocation outcome with
     | HookRules.Proceed invocation => [TaskChange.ChangePhase (ReadyForHooks invocation pending remaining)]
     | HookRules.Refuse code reason =>
       [TaskChange.AppendHistory [FunctionOutput (call_id invocation) (State.failure code reason) true];
        TaskChange.ChangePhase (PendingCalls remaining)]
     end in
     acknowledged (put_task id (TaskChange.apply changes task) value)
     else ignored value
   | _ => ignored value
   end end.
Proof.
 intros. unfold HookCallbacks.hook_completed.
 apply (selected_result_erases_its_lookup_witness decision id value
 (fun candidate => 
 match candidate with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match task_activity task with
   | CheckingHook expected plugin invocation pending remaining =>
     if N.eqb expected ticket then
     let receipt := TaskChange.AppendHistory [HookReceipt id invocation plugin (hook_json outcome)] in
     let changes := receipt :: match HookRules.before_apply invocation outcome with
     | HookRules.Proceed invocation => [TaskChange.ChangePhase (ReadyForHooks invocation pending remaining)]
     | HookRules.Refuse code reason =>
       [TaskChange.AppendHistory [FunctionOutput (call_id invocation) (State.failure code reason) true];
        TaskChange.ChangePhase (PendingCalls remaining)]
     end in
     acknowledged (TaskChange.interpret (TaskChange.Plan value target changes))
     else ignored value
   | _ => ignored value
   end
 end)
 (fun owner task => match task_activity task with
   | CheckingHook expected plugin invocation pending remaining =>
     if N.eqb expected ticket then
     let receipt := TaskChange.AppendHistory [HookReceipt id invocation plugin (hook_json outcome)] in
     let changes := receipt :: match HookRules.before_apply invocation outcome with
     | HookRules.Proceed invocation => [TaskChange.ChangePhase (ReadyForHooks invocation pending remaining)]
     | HookRules.Refuse code reason =>
       [TaskChange.AppendHistory [FunctionOutput (call_id invocation) (State.failure code reason) true];
        TaskChange.ChangePhase (PendingCalls remaining)]
     end in
     acknowledged (put_task owner (TaskChange.apply changes task) value)
     else ignored value
   | _ => ignored value
   end) (ignored value)); intros; reflexivity.
Qed.

Lemma after_completed_expression : forall (id operation ticket : N) (outcome : after_outcome) (value : world),
 HookCallbacks.after_completed id operation ticket outcome value =
 match find_task id value with | None => ignored value | Some task => match find (fun pending => N.eqb operation (operation_id pending)) (task_operations task) with
   | None => ignored value
   | Some operation => match operation_stage operation with
     | AwaitingAfterHook expected plugin pending result error =>
       if N.eqb expected ticket then
       let receipt := [AfterReceipt id (operation_id operation) plugin (after_json outcome)] in
       let recorded := append_history receipt task in
       let changes := TaskChange.AppendHistory receipt :: match HookRules.after_apply result outcome with
       | HookRules.RefuseResult code reason => settle_operation_changes operation (State.failure code reason) true recorded
       | HookRules.ContinueResult result =>
         match pending with
         | [] => settle_operation_changes operation result error recorded
         | _ => [TaskChange.ChangeOperationStage (operation_id operation) (AfterHooksReady pending result error)]
         end
       end in
       acknowledged (put_task id (TaskChange.apply changes task) value)
       else ignored value
     | _ => ignored value end
   end end.
Proof.
 intros. unfold HookCallbacks.after_completed.
 apply (selected_result_erases_its_lookup_witness decision id value
 (fun candidate => 
 match candidate with
 | None => ignored value
 | Some target => let task := TaskScope.selected target in match find (fun pending => N.eqb operation (operation_id pending)) (task_operations task) with
   | None => ignored value
   | Some operation => match operation_stage operation with
     | AwaitingAfterHook expected plugin pending result error =>
       if N.eqb expected ticket then
       let receipt := [AfterReceipt id (operation_id operation) plugin (after_json outcome)] in
       let recorded := append_history receipt task in
       let changes := TaskChange.AppendHistory receipt :: match HookRules.after_apply result outcome with
       | HookRules.RefuseResult code reason => settle_operation_changes operation (State.failure code reason) true recorded
       | HookRules.ContinueResult result =>
         match pending with
         | [] => settle_operation_changes operation result error recorded
         | _ => [TaskChange.ChangeOperationStage (operation_id operation) (AfterHooksReady pending result error)]
         end
       end in
       acknowledged (TaskChange.interpret (TaskChange.Plan value target changes))
       else ignored value
     | _ => ignored value end
   end
 end)
 (fun owner task => match find (fun pending => N.eqb operation (operation_id pending)) (task_operations task) with
   | None => ignored value
   | Some operation => match operation_stage operation with
     | AwaitingAfterHook expected plugin pending result error =>
       if N.eqb expected ticket then
       let receipt := [AfterReceipt id (operation_id operation) plugin (after_json outcome)] in
       let recorded := append_history receipt task in
       let changes := TaskChange.AppendHistory receipt :: match HookRules.after_apply result outcome with
       | HookRules.RefuseResult code reason => settle_operation_changes operation (State.failure code reason) true recorded
       | HookRules.ContinueResult result =>
         match pending with
         | [] => settle_operation_changes operation result error recorded
         | _ => [TaskChange.ChangeOperationStage (operation_id operation) (AfterHooksReady pending result error)]
         end
       end in
       acknowledged (put_task owner (TaskChange.apply changes task) value)
       else ignored value
     | _ => ignored value end
   end) (ignored value)); intros; reflexivity.
Qed.
