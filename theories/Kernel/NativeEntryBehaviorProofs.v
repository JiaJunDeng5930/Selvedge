From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks NativeTools Callbacks Scheduler Capabilities.
Import ListNotations.
Open Scope string_scope.

(* Before hooks can repair initial or intermediate object arguments. Only their
   final value reaches this gate: an invalid native invocation records an error
   without executing its command or allocating a child. *)
Theorem invalid_native_arguments_cannot_pass_final_dispatch_gate :
 forall execute id invocation remaining task value definition parameters program,
 tool_origin definition = NativeToolSource parameters program ->
 Capabilities.available (environment_tools (world_environment value)) definition = true ->
 NativeTools.arguments_valid definition invocation = false ->
 Scheduler.before_hook_step execute id definition invocation [] remaining task value =
 Scheduler.call_error id invocation "invalid_arguments" "Tool arguments do not satisfy its frozen schema" remaining task value.
Proof.
 intros execute id invocation remaining task value definition parameters program Native Available Invalid.
 unfold Scheduler.before_hook_step, Scheduler.execute_checked_call, Scheduler.call_admission.
 rewrite Available. cbn [negb].
 unfold Callbacks.model_call_arguments_valid; rewrite Native, Invalid. reflexivity.
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
 execute command (Some (Tasks.NativeCall id invocation remaining)) (put_task id (with_activity (PendingCalls remaining) task) value) = result ->
 bool_default "ok" (decision_reply result) false = true ->
 find_task id (decision_world result) = Some caller ->
 Callbacks.after_plugins caller = [] ->
 decision_world (Scheduler.execute_checked_call execute id definition invocation remaining task value) =
 put_task id (Scheduler.call_result invocation (number 0) false remaining caller)
   (decision_world result).
Proof.
 intros execute id definition invocation remaining task value command result caller
   Available Valid Command Room Name Executed Success Found NoHooks.
 unfold Scheduler.execute_checked_call, Scheduler.call_admission.
 rewrite Available, Valid. cbn [negb].
 rewrite Command, Room, Executed, Name, String.eqb_refl. cbn [andb].
 rewrite Success, Found. cbn [negb].
 unfold Scheduler.internal_result. rewrite NoHooks. reflexivity.
Qed.
