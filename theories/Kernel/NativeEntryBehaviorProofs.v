From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks NativeTools Callbacks Scheduler Capabilities SchedulerChangesProofs.
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

(* Native fork completion commits both successful and refused business results. *)
From Selvedge.Kernel Require Export NativeForkPacketProofs.
