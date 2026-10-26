From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates State TaskScope TaskScopeProofs TaskChange TaskChangeProofs Tasks TaskWakeProofs History.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Lemma promotion_expression : forall task, Tasks.promote task =
 match task_lifecycle task, task_queued task with
 | Running Idle operations, first :: rest | Running (PendingCalls []) operations, first :: rest
 | Running WantsModel operations, first :: rest =>
   with_lifecycle (Running WantsModel operations)
    (with_queued [] (append_history (map UserMessage (first :: rest)) task))
 | Stopped Idle operations, first :: rest | Stopped (PendingCalls []) operations, first :: rest =>
   with_lifecycle (Stopped Idle operations)
    (with_queued [] (append_history (map UserMessage (first :: rest)) task))
 | _,_ => task end.
Proof.
 intros [contract profile settings lifecycle history queued lineage side cursor consumed].
 destruct lifecycle as [phase operations|phase operations|phase operations|operations];
 try destruct phase; try destruct calls; destruct queued; reflexivity.
Qed.

Lemma waking_result_expression : forall task, Tasks.wake_after_result task =
 match task_lifecycle task with
 | Running Idle operations => with_lifecycle (Running WantsModel operations) task
 | Frozen Idle operations => with_lifecycle (Frozen WantsModel operations) task
 | _ => Tasks.promote task end.
Proof.
 intros [contract profile settings lifecycle history queued lineage side cursor consumed].
 destruct lifecycle as [phase operations|phase operations|phase operations|operations];
 try destruct phase; reflexivity.
Qed.

Lemma queue_expression : forall (contents : content) (value : task),
 Tasks.queue contents value =
 with_queued (task_queued value ++ [contents]) value.
Proof.
 intros; reflexivity.
Qed.

Lemma receive_expression : forall (contents : content) (value : task),
 Tasks.receive contents value =
 match task_lifecycle value with
 | Archived _ => value
 | Frozen _ _ => queue contents value
 | Running Idle [] | Running (PendingCalls []) [] | Stopped Idle [] | Stopped (PendingCalls []) [] =>
   with_lifecycle (Running WantsModel []) (with_queued []
    (append_history (map UserMessage (task_queued value ++ [contents])) value))
 | Running _ _ => queue contents value
 | Stopped phase operations => with_lifecycle (Running phase operations) (queue contents value)
 end.
Proof.
 intros contents [contract profile settings lifecycle history queued lineage side cursor consumed].
 destruct lifecycle as [phase operations|phase operations|phase operations|operations];
 try destruct phase; try destruct calls; destruct operations; reflexivity.
Qed.

Lemma control_task_expression : forall (command : control) (task : task),
 Tasks.control_task command task =
 match control_target command task with
 | None => task
 | Some target => with_lifecycle target
   (match command with
    | Interrupt => append_history (unknown_operations (task_operations task) ++ History.interrupted_phase (task_activity task)) task
    | Archive => append_history (History.interrupted_phase (task_activity task) ++ unknown_operations (task_operations task)) task
    | _ => task end)
 end.
Proof.
 intros command [contract profile settings lifecycle history queued lineage side cursor consumed].
 destruct command; destruct lifecycle; reflexivity.
Qed.

Lemma send_expression : forall (id : N) (contents : content) (value : world),
 Tasks.send id contents value =
 match find_task id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some task => match task_lifecycle task with
   | Archived _ => reject "invalid_arguments" "Archived tasks cannot accept input" value
   | _ => if content_nonempty contents then
      accept (JObject [("task_id", number id)]) (put_task id (receive contents task) value) []
     else reject "invalid_arguments" input_required_message value
   end
 end.
Proof.
 intros. unfold Tasks.send.
 pattern (TaskScope.select id value) at 1.
 apply selected_reference_elimination.
 - intros reference Owner.
   pose proof (TaskScope.observed reference) as Selected; rewrite Owner in Selected.
   rewrite Selected. unfold TaskChange.interpret; cbn. rewrite Owner.
   cbv beta zeta.
   repeat match goal with |- context [match ?term with _ => _ end] => destruct term eqn:? end;
     try reflexivity.
 - intros Missing. now rewrite Missing.
Qed.

Lemma control_command_expression : forall (id : N) (command : control) (value : world),
 Tasks.control_command id command value =
 match find_task id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some task => match control_target command task with
   | None => reject "invalid_transition" "This lifecycle control is unavailable for the task" value
   | Some _ => accept (JObject [("task_id", number id)])
      (put_task id (control_task command task) value) (control_effects id command task)
   end end.
Proof.
 intros. unfold Tasks.control_command.
 pattern (TaskScope.select id value) at 1.
 apply selected_reference_elimination.
 - intros reference Owner.
   pose proof (TaskScope.observed reference) as Selected; rewrite Owner in Selected.
   rewrite Selected. unfold TaskChange.interpret; cbn. rewrite Owner.
   cbv beta zeta.
   repeat match goal with |- context [match ?term with _ => _ end] => destruct term eqn:? end;
     try reflexivity.
 - intros Missing. now rewrite Missing.
Qed.

Lemma steer_expression : forall (id : N) (contents : content) (value : world),
 Tasks.steer id contents value =
 match find_task id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some task => match task_lifecycle task with
   | Archived _ => reject "invalid_arguments" "Archived tasks cannot accept input" value
   | current => if content_nonempty contents then
     let lifecycle := match current with Frozen _ operations => Frozen WantsModel operations
       | _ => Running WantsModel (task_operations task) end in
     accept (JObject [("task_id", number id)])
      (put_task id (with_lifecycle lifecycle (append_history (History.interrupted_phase (task_activity task) ++ [UserMessage contents]) task)) value)
      (inference_effects id task)
     else reject "invalid_arguments" input_required_message value
   end end.
Proof.
 intros. unfold Tasks.steer.
 pattern (TaskScope.select id value) at 1.
 apply selected_reference_elimination.
 - intros reference Owner.
   pose proof (TaskScope.observed reference) as Selected; rewrite Owner in Selected.
   rewrite Selected. unfold TaskChange.interpret; cbn. rewrite Owner.
   cbv beta zeta.
   repeat match goal with |- context [match ?term with _ => _ end] => destruct term eqn:? end;
     try reflexivity.
   destruct (TaskScope.selected reference) as [contract profile settings lifecycle history queued lineage side cursor consumed].
   cbn in *; subst lifecycle; reflexivity.
 - intros Missing. now rewrite Missing.
Qed.

Lemma cancel_operation_expression : forall (id operation_id : N) (value : world),
 Tasks.cancel_operation id operation_id value =
 match find_task id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some task =>
   match find (fun operation => N.eqb operation_id (Domain.operation_id operation)) (task_operations task) with
   | None => reject "operation_not_found" "The operation is not live in this task" value
   | Some operation =>
     let remaining := filter (fun operation => negb (N.eqb operation_id (Domain.operation_id operation))) (task_operations task) in
     accept (JObject [("task_id", number id); ("operation_id", number operation_id)])
      (mark_context_wake id task (put_task id (wake_after_result (with_operations remaining
       (append_history [History.cancelled_operation operation] task))) value))
      (match operation_stage operation with
       | Executing ticket | Elevated ticket _ | AwaitingApproval ticket _ | AwaitingAfterHook ticket _ _ _ _ => [CancelTicket id ticket]
       | Granted _ | AfterHooksReady _ _ _ => [] end)
   end end.
Proof.
 intros. unfold Tasks.cancel_operation.
 pattern (TaskScope.select id value) at 1.
 apply selected_reference_elimination.
 - intros reference Owner.
   pose proof (TaskScope.observed reference) as Selected; rewrite Owner in Selected.
   rewrite Selected. unfold Tasks.interpret_result, Tasks.apply_result, Tasks.result_changes; cbn -[Tasks.mark_context_wake]. rewrite Owner.
   cbv beta zeta.
   repeat match goal with |- context [match ?term with _ => _ end] => destruct term eqn:? end;
     try reflexivity.
 - intros Missing. now rewrite Missing.
Qed.

Lemma configure_execution_with_expression : forall (normalize : task_settings -> task_settings) (id : N)
 (name reasoning : option string) (sandbox_source approval_source : option json) (value : world),
 Tasks.configure_execution_with normalize id name reasoning sandbox_source approval_source value =
 match find_task id value with
 | None => reject "task_not_found" "The target task does not exist" value
 | Some task =>
   let current := task_current_settings task in
   let model := match name with
    | None => Some (task_current_profile task)
    | Some name => find_profile name (environment_profiles (world_environment value)) end in
   (* Reviewer selection precedes model, reasoning and busy failures. Omitted
      fields retain the captured settings rather than re-resolving defaults. *)
   let reviewer_model := match model with Some selected => selected
     | None => task_current_profile task end in
   match match approval_source with
    | None => Some (settings_approval current)
    | Some source => parse_approval reviewer_model (environment_profiles (world_environment value)) source end with
   | None => refuse_start Configuration InvalidPolicy value
   | Some approval => match model with
     | None => refuse_start Configuration UnknownProfile value
     | Some profile => match execution_reasoning reasoning profile with
       | None => refuse_start Configuration InvalidReasoning value
       | Some chosen => match match sandbox_source with
         | None => Some (settings_sandbox current)
         | Some source => parse_sandbox_patch (settings_sandbox current) source end with
         | None => reject "invalid_settings" "Sandbox settings do not satisfy the domain protocol" value
         | Some sandbox =>
           if quiescent task && negb (String.eqb (task_status task) "archived") &&
            (match History.history_lease id (task_history task) with History.NoLease => true | _ => false end) then
           let settings := normalize (Settings (settings_workspace current) (settings_project current)
            sandbox approval (settings_guidance current) (settings_worktree current) (settings_resource current)) in
           let same := Domain.same_profile chosen (task_current_profile task) &&
             Json.equal (settings_json settings) (settings_json current) &&
             same_approval (settings_approval settings) (settings_approval current) in
           let updated := with_execution chosen settings task in
           let updated := if same then updated else append_history [SettingsMessage settings (profile_key chosen) (profile_reasoning chosen)] updated in
           accept (JObject [("task_id", number id)]) (put_task id updated value)
            (if same then [] else [ResetModelSession id])
           else reject "task_busy" "Execution settings require a quiescent unarchived task without a live reasoning lease" value
         end
       end
     end
   end
 end.
Proof.
 intros. unfold Tasks.configure_execution_with.
 pattern (TaskScope.select id value) at 1.
 apply selected_reference_elimination.
 - intros reference Owner.
   pose proof (TaskScope.observed reference) as Selected; rewrite Owner in Selected.
   rewrite Selected. unfold TaskChange.interpret; cbn. rewrite Owner.
   cbv beta zeta.
   repeat match goal with |- context [match ?term with _ => _ end] => destruct term eqn:? end;
     try reflexivity.
 - intros Missing. now rewrite Missing.
Qed.

Lemma fork_with_caller_expression : forall (entry : fork_entry) (origin:fork_settings_origin) (id count : N)
 (messages : list content) (settings : option json) (value : world),
 Tasks.fork_with_caller entry origin id count messages settings value =
 match find_task id value with
 | None => reject "task_not_found" "The parent task does not exist" value
 | Some task =>
   if fork_parent_ready entry task &&
    TaskConstraints.fork_count_valid count (contract_max_fork (task_contract task)) &&
    TaskConstraints.fork_messages_valid count (List.length messages) &&
    ancestors_fit (id :: task_lineage task) count value then
    match resolve_settings (task_current_profile task) settings (fork_settings_base origin task value) value with
    | None => reject "invalid_settings" "Child settings do not resolve to a current workspace" value
    | Some selected => match admit_fork_selection task value selected with
      | None => reject "cloud_workspace_fixed" "A cloud task keeps its bound workspace; forks inherit that environment" value
      | Some selection =>
      let selected := fork_selected task value selection in
      if match entry with ManualFork => false | AcceptedNativeFork _ _ =>
        negb (Workspace.may_delegate selected (task_current_settings task) && no_resource_observation settings) end then
       refuse_start NativeForkEntry AuthorityExpansion value else
      let '(ticket, allocated) := allocate_ticket value in
      let invocation := match entry with
       | AcceptedNativeFork invocation _ => invocation
       | ManualFork => Call (manual_fork_identity ticket task) "fork_task"
         (JObject [("child_count",number count);("messages",JArray (map content_json messages))]) InitialAttempt end in
      let parent := match entry with
       | AcceptedNativeFork _ _ => task
       | ManualFork => with_activity WantsModel (append_history
           [FunctionCall invocation; ForkReceipt id invocation 0] task) end in
      let retained := match entry with ManualFork => put_task id parent allocated | _ => value end in
      let children := fork_children (N.to_nat count) id
        (match entry with ManualFork => append_history [FunctionCall invocation] task | _ => task end)
        messages selected entry (next_task value) invocation retained in
      accept (JObject [("children", JArray (map (fun offset => number (next_task value + N.of_nat offset)) (seq 0 (N.to_nat count))))]) children []
      end
    end
   else fork_refusal entry id count task value
 end.
Proof.
 intros. unfold Tasks.fork_with_caller.
 pattern (TaskScope.select id value) at 1.
 apply selected_reference_elimination.
 - intros reference Owner.
   pose proof (TaskScope.observed reference) as Selected; rewrite Owner in Selected.
   rewrite Selected. unfold TaskChange.interpret; cbn. rewrite Owner.
   cbv beta zeta.
   repeat match goal with |- context [match ?term with _ => _ end] => destruct term eqn:? end;
     try reflexivity.
 - intros Missing. now rewrite Missing.
Qed.

