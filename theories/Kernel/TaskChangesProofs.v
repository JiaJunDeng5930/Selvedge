From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates State TaskScope TaskScopeProofs TaskChange TaskChangeProofs Tasks TaskWakeProofs History.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(* These views are derived from the interpreter. Their statements do not
   maintain another copy of each task command's control flow. *)
Ltac reduce_task_plan expression :=
 eval cbv beta iota zeta delta [TaskChange.interpret TaskChange.configure TaskChange.target TaskChange.changes
   TaskScope.owner TaskScope.selected Tasks.interpret_result] in expression.

Definition send_expression (id : N) (contents : content) (value : world) := ltac:(
 let body := eval cbv beta iota zeta delta [Tasks.send Tasks.send_result] in (Tasks.send id contents value) in
 derive_task_lookup_view constr:(Tasks.send id contents value) body id value reduce_task_plan).

Definition control_command_expression (id : N) (command : control) (value : world) := ltac:(
 let body := eval unfold Tasks.control_command in (Tasks.control_command id command value) in
 derive_task_lookup_view constr:(Tasks.control_command id command value) body id value reduce_task_plan).

Definition steer_expression (id : N) (contents : content) (value : world) := ltac:(
 let body := eval cbv beta iota zeta delta [Tasks.steer Tasks.steer_result] in (Tasks.steer id contents value) in
 derive_task_lookup_view constr:(Tasks.steer id contents value) body id value reduce_task_plan).

Ltac reduce_cancellation_plan expression :=
 let reduced := reduce_task_plan expression in
 eval cbv beta iota zeta delta [Tasks.apply_result Tasks.result_changes] in reduced.

Definition cancel_operation_expression (id identity : N) (value : world) := ltac:(
 let body := eval unfold Tasks.cancel_operation in (Tasks.cancel_operation id identity value) in
 derive_task_lookup_view constr:(Tasks.cancel_operation id identity value) body id value reduce_cancellation_plan).

Definition configure_execution_with_expression (normalize : task_settings -> task_settings) (id : N)
 (name reasoning : option string) (sandbox_source approval_source : option json) (value : world) := ltac:(
 let body := eval unfold Tasks.configure_execution_with in
   (Tasks.configure_execution_with normalize id name reasoning sandbox_source approval_source value) in
 derive_task_lookup_view constr:(Tasks.configure_execution_with normalize id name reasoning sandbox_source approval_source value) body id value reduce_task_plan).

Definition fork_with_caller_expression (entry : fork_entry) (origin : fork_settings_origin) (id count : N)
 (messages : list content) (settings : option json) (value : world) := ltac:(
 let body := eval cbv beta iota zeta delta [Tasks.fork_with_caller Tasks.fork_result] in
   (Tasks.fork_with_caller entry origin id count messages settings value) in
 derive_task_lookup_view constr:(Tasks.fork_with_caller entry origin id count messages settings value) body id value reduce_task_plan).
