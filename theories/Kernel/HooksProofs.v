From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain Codec State Tasks Capabilities Inputs Callbacks Scheduler HookCallbacks.
Import ListNotations.
Open Scope string_scope.

Theorem hook_references_preserve_enabled_plugin_order : forall phase plugin rest,
 Capabilities.hook_references phase (plugin :: rest) =
   if bool_default (Capabilities.hook_field phase) plugin false
   then value_or_null "reference" plugin :: Capabilities.hook_references phase rest
   else Capabilities.hook_references phase rest.
Proof.
 intros phase plugin rest; unfold Capabilities.hook_references; simpl.
 destruct (bool_default (Capabilities.hook_field phase) plugin false); reflexivity.
Qed.

Theorem before_hook_dispatches_the_first_pending_plugin :
 forall execute id tool invocation plugin rest remaining task value,
 Capabilities.hook_available Capabilities.BeforeTool plugin
   (environment_plugins (world_environment value)) = true ->
 let '(ticket, allocated) := allocate_ticket value in
 decision_effects (Scheduler.before_hook_step execute id tool invocation
   (plugin :: rest) remaining task value) =
   [CheckTool id ticket plugin tool invocation].
Proof.
 intros execute id tool invocation plugin rest remaining task value Available.
 unfold Scheduler.before_hook_step; rewrite Available; reflexivity.
Qed.

Theorem after_hook_dispatches_the_first_pending_plugin_for_its_operation :
 forall id current task value plugin rest result error,
 operation_stage current = AfterHooksReady (plugin :: rest) result error ->
 Capabilities.hook_available Capabilities.AfterTool plugin
   (environment_plugins (world_environment value)) = true ->
 let '(ticket, allocated) := allocate_ticket value in
 decision_effects (Scheduler.after_hooks_step id current task value) =
   [CheckResult id ticket (operation_id current) plugin (operation_call current) result error].
Proof.
 intros id current task value plugin rest result error Stage Available.
 unfold Scheduler.after_hooks_step; rewrite Stage, Available; reflexivity.
Qed.

Theorem tool_completion_enters_the_ordered_after_hooks_with_its_error :
 forall id ticket result error value task current plugin rest,
 find_task id value = Some task ->
 find (Callbacks.operation_executing ticket) (task_operations task) = Some current ->
 Callbacks.after_plugins task = plugin :: rest ->
 let recorded := append_history
   [ToolReceipt id (operation_id current) (operation_call current) result error] task in
 let waiting := Operation (operation_id current) (operation_call current)
   (operation_announced current) (AfterHooksReady (plugin :: rest) result error) in
 Callbacks.tool_completed id ticket result error value =
   acknowledged (put_task id
     (with_operations (replace_operation waiting (task_operations recorded)) recorded) value).
Proof.
 intros id ticket result error value task current plugin rest Found Owned Hooks.
 unfold Callbacks.tool_completed; rewrite Found, Owned, Hooks; reflexivity.
Qed.

Theorem allowed_before_hook_resumes_the_same_call_before_its_suffix :
 forall id ticket plugin invocation pending remaining value task,
 find_task id value = Some task ->
 task_activity task = CheckingHook ticket plugin invocation pending remaining ->
 HookCallbacks.hook_completed id ticket HookAllow value =
   acknowledged (put_task id
     (with_activity (ReadyForHooks invocation pending remaining)
       (append_history [HookReceipt id invocation plugin (Inputs.hook_json HookAllow)] task)) value).
Proof.
 intros id ticket plugin invocation pending remaining value task Found Checking.
 unfold HookCallbacks.hook_completed; rewrite Found, Checking, N.eqb_refl; reflexivity.
Qed.

Theorem denied_before_hook_ends_this_call_without_dispatch :
 forall id ticket plugin invocation pending remaining reason value task,
 find_task id value = Some task ->
 task_activity task = CheckingHook ticket plugin invocation pending remaining ->
 HookCallbacks.hook_completed id ticket (HookDeny reason) value =
   Scheduler.call_error id invocation "hook_denied" reason remaining
     (append_history [HookReceipt id invocation plugin
       (Inputs.hook_json (HookDeny reason))] task) value /\
 decision_effects (HookCallbacks.hook_completed id ticket (HookDeny reason) value) = [].
Proof.
 intros id ticket plugin invocation pending remaining reason value task Found Checking.
 unfold HookCallbacks.hook_completed; rewrite Found, Checking, N.eqb_refl.
 split; [reflexivity|reflexivity].
Qed.

Theorem after_hook_rewrite_keeps_operation_owner_and_error_for_the_suffix :
 forall id identity ticket plugin next rest result error replacement value task current,
 find_task id value = Some task ->
 find (fun pending => N.eqb identity (operation_id pending)) (task_operations task) = Some current ->
 operation_stage current = AwaitingAfterHook ticket plugin (next :: rest) result error ->
 let updated := append_history
   [AfterReceipt id (operation_id current) plugin (Inputs.after_json (RewriteResult replacement))] task in
 let continued := Operation (operation_id current) (operation_call current)
   (operation_announced current) (AfterHooksReady (next :: rest) replacement error) in
 HookCallbacks.after_completed id identity ticket (RewriteResult replacement) value =
   acknowledged (put_task id
     (with_operations (replace_operation continued (task_operations updated)) updated) value).
Proof.
 intros id identity ticket plugin next rest result error replacement value task current Found Owned Waiting.
 unfold HookCallbacks.after_completed; rewrite Found, Owned, Waiting, N.eqb_refl.
 reflexivity.
Qed.

Theorem before_hook_callback_with_a_stale_ticket_is_ignored :
 forall id expected ticket plugin invocation pending remaining outcome value task,
 find_task id value = Some task ->
 task_activity task = CheckingHook expected plugin invocation pending remaining ->
 ticket <> expected ->
 HookCallbacks.hook_completed id ticket outcome value = Callbacks.ignored value.
Proof.
 intros id expected ticket plugin invocation pending remaining outcome value task Found Checking Stale.
 unfold HookCallbacks.hook_completed; rewrite Found, Checking.
 assert (N.eqb expected ticket = false) as Mismatch by
   (apply N.eqb_neq; congruence).
 rewrite Mismatch; reflexivity.
Qed.

Theorem after_hook_callback_for_another_operation_is_ignored :
 forall id identity ticket outcome value task,
 find_task id value = Some task ->
 find (fun pending => N.eqb identity (operation_id pending)) (task_operations task) = None ->
 HookCallbacks.after_completed id identity ticket outcome value = Callbacks.ignored value.
Proof.
 intros id identity ticket outcome value task Found NoOperation.
 unfold HookCallbacks.after_completed; rewrite Found, NoOperation; reflexivity.
Qed.

Theorem after_hook_callback_with_a_stale_ticket_is_ignored :
 forall id identity expected ticket plugin pending result error outcome value task current,
 find_task id value = Some task ->
 find (fun operation => N.eqb identity (operation_id operation)) (task_operations task) = Some current ->
 operation_stage current = AwaitingAfterHook expected plugin pending result error ->
 ticket <> expected ->
 HookCallbacks.after_completed id identity ticket outcome value = Callbacks.ignored value.
Proof.
 intros id identity expected ticket plugin pending result error outcome value task current
   Found Owned Waiting Stale.
 unfold HookCallbacks.after_completed; rewrite Found, Owned, Waiting.
 assert (N.eqb expected ticket = false) as Mismatch by
   (apply N.eqb_neq; congruence).
 rewrite Mismatch; reflexivity.
Qed.

Theorem denied_after_hook_ends_the_operation_chain :
 forall id identity ticket expected plugin pending result error reason value task current,
 find_task id value = Some task ->
 find (fun operation => N.eqb identity (operation_id operation)) (task_operations task) = Some current ->
 operation_stage current = AwaitingAfterHook expected plugin pending result error ->
 ticket = expected ->
 HookCallbacks.after_completed id identity ticket (DenyResult reason) value =
   acknowledged (put_task id
     (Callbacks.settle_operation current (State.failure "after_hook_denied" reason) true
       (append_history [AfterReceipt id (operation_id current) plugin
         (Inputs.after_json (DenyResult reason))] task)) value) /\
 decision_effects (HookCallbacks.after_completed id identity ticket (DenyResult reason) value) = [].
Proof.
 intros id identity ticket expected plugin pending result error reason value task current
   Found Owned Waiting Matches.
 subst ticket.
 unfold HookCallbacks.after_completed; rewrite Found, Owned, Waiting, N.eqb_refl.
 split; [reflexivity|reflexivity].
Qed.

Theorem before_hook_callback_for_a_missing_task_is_ignored :
 forall id ticket outcome value,
 find_task id value = None ->
 HookCallbacks.hook_completed id ticket outcome value = Callbacks.ignored value.
Proof.
 intros id ticket outcome value Missing.
 unfold HookCallbacks.hook_completed; rewrite Missing; reflexivity.
Qed.

Theorem after_hook_callback_for_a_missing_task_is_ignored :
 forall id identity ticket outcome value,
 find_task id value = None ->
 HookCallbacks.after_completed id identity ticket outcome value = Callbacks.ignored value.
Proof.
 intros id identity ticket outcome value Missing.
 unfold HookCallbacks.after_completed; rewrite Missing; reflexivity.
Qed.

Theorem a_before_rewrite_preserves_call_identity_and_the_remaining_chain :
 forall id ticket plugin invocation pending remaining arguments value task,
 find_task id value = Some task ->
 task_activity task = CheckingHook ticket plugin invocation pending remaining ->
 HookCallbacks.hook_completed id ticket (HookRewrite arguments) value =
 acknowledged (put_task id
  (with_activity
   (ReadyForHooks (Call (call_id invocation) (call_name invocation) (JObject arguments)) pending remaining)
   (append_history [HookReceipt id invocation plugin (Inputs.hook_json (HookRewrite arguments))] task)) value).
Proof.
 intros id ticket plugin invocation pending remaining arguments value task Found Checking.
 unfold HookCallbacks.hook_completed; rewrite Found, Checking, N.eqb_refl; reflexivity.
Qed.

Theorem final_invalid_arguments_never_dispatch :
 forall execute id tool invocation remaining task value,
 Callbacks.model_call_arguments_valid tool invocation = false ->
 decision_effects (Scheduler.before_hook_step execute id tool invocation [] remaining task value) = [].
Proof.
 intros execute id tool invocation remaining task value Invalid.
 unfold Scheduler.before_hook_step, Scheduler.execute_checked_call.
 rewrite Invalid, andb_false_r; reflexivity.
Qed.
