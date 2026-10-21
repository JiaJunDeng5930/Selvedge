From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks NativeTools Callbacks Scheduler Capabilities.
Import ListNotations.
Open Scope string_scope.

(* This is the real model-item admission gate, before FunctionCall history and
   before-hook work are constructed. Numeric and structural contracts are
   discharged by the shared argument interpreter, not a second model checker. *)
Theorem invalid_native_arguments_cannot_enter_model_items :
 forall invocation rest allowed task ids parts definition parameters program,
 find_tool (call_name invocation) (contract_tools (task_contract task)) = Some definition ->
 tool_origin definition = NativeToolSource parameters program ->
 NativeTools.arguments_valid definition invocation = false ->
 Callbacks.permitted_items (CallItem invocation :: rest) allowed task ids parts = false.
Proof.
 intros invocation rest allowed task ids parts definition parameters program Found Native Invalid.
 cbn [Callbacks.permitted_items]. rewrite Found.
 unfold Callbacks.model_call_arguments_valid; rewrite Native, Invalid.
 repeat rewrite andb_false_r. reflexivity.
Qed.

(* A successful native fork has a real positive result. The command executor is
   shared with Packet; after-hook handling is separately specified by callback
   proofs. This local bridge does not normalize an entire service workflow. *)
Theorem a_successful_native_fork_returns_the_parent_branch :
 forall execute id definition invocation remaining task value command result caller,
 Capabilities.available (environment_tools (world_environment value)) definition = true ->
 Callbacks.model_call_arguments_valid definition invocation = true ->
 NativeTools.command id invocation = Some command ->
 Scheduler.internal_result_available task = true ->
 call_name invocation = "fork_task" ->
 execute command (Some id) (put_task id (with_activity (PendingCalls remaining) task) value) = result ->
 bool_default "ok" (decision_reply result) false = true ->
 find_task id (Scheduler.fork_receipts (next_task value) invocation (decision_world result)) = Some caller ->
 Callbacks.after_plugins caller = [] ->
 decision_world (Scheduler.execute_checked_call execute id definition invocation remaining task value) =
 put_task id (Scheduler.call_result invocation (number 0) false remaining caller)
   (Scheduler.fork_receipts (next_task value) invocation (decision_world result)).
Proof.
 intros execute id definition invocation remaining task value command result caller
   Available Valid Command Room Name Executed Success Found NoHooks.
 unfold Scheduler.execute_checked_call.
 rewrite Available, Valid, Command, Room, Executed, Name, String.eqb_refl. cbn [andb].
 rewrite Success, Found. cbn [negb].
 unfold Scheduler.internal_result. rewrite NoHooks. reflexivity.
Qed.
