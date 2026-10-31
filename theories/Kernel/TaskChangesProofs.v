From Stdlib Require Import String List Bool NArith.
From Selvedge.Programming Require CommandResult TaskResult.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec Context ContextUpdates State.
From Selvedge.Programming Require Import TaskScope TaskScopeProofs TaskChange TaskChangeProofs.
From Selvedge.Kernel Require Import Tasks.
From Selvedge.Programming Require Import TaskWakeProofs.
From Selvedge.Kernel Require Import History.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

(* These views are derived from the interpreter. Their statements do not
   maintain another copy of each task command's control flow. *)
Ltac reduce_task_plan expression :=
 eval cbv beta iota zeta delta [TaskChange.interpret TaskChange.configure TaskChange.target TaskChange.changes
   TaskScope.owner TaskScope.selected TaskResult.interpret_result
   Tasks.receive_input Tasks.perform_control Tasks.control_resource_available
   Tasks.input_admission Tasks.control_admission
   Tasks.input_effects Tasks.input_changes Tasks.admit_input Tasks.admit_control
   Refinement.admit CommandResult.map CommandResult.bind CommandResult.decide
   CommandResult.resolve CommandResult.accept CommandResult.reject proj1_sig] in expression.

Definition input_result_expression (mode : input_mode) (id : N) (contents : content) (value : world) := ltac:(
 let body := eval unfold Tasks.input_result in (Tasks.input_result mode id contents value) in
 derive_task_lookup_view constr:(Tasks.input_result mode id contents value) body id value reduce_task_plan).

Definition send_expression (id : N) (contents : content) (value : world) := ltac:(
 let body := eval cbv beta iota zeta delta [Tasks.send Tasks.send_result Tasks.input_result] in (Tasks.send id contents value) in
 derive_task_lookup_view constr:(Tasks.send id contents value) body id value reduce_task_plan).

Definition control_command_expression (id : N) (command : control) (value : world) := ltac:(
 let body := eval cbv beta iota zeta delta [Tasks.control_command Tasks.control_result] in (Tasks.control_command id command value) in
 derive_task_lookup_view constr:(Tasks.control_command id command value) body id value reduce_task_plan).

Definition steer_expression (id : N) (contents : content) (value : world) := ltac:(
 let body := eval cbv beta iota zeta delta [Tasks.steer Tasks.steer_result Tasks.input_result] in (Tasks.steer id contents value) in
 derive_task_lookup_view constr:(Tasks.steer id contents value) body id value reduce_task_plan).

Ltac reduce_cancellation_plan expression :=
 let reduced := reduce_task_plan expression in
 eval cbv beta iota zeta delta [TaskResult.apply_result TaskResult.result_changes] in reduced.

Definition cancel_operation_expression (id identity : N) (value : world) := ltac:(
 let body := eval unfold Tasks.cancel_operation in (Tasks.cancel_operation id identity value) in
 derive_task_lookup_view constr:(Tasks.cancel_operation id identity value) body id value reduce_cancellation_plan).

Definition configure_execution_expression (id : N)
 (name reasoning : option string)
 (sandbox_source : option (D.denote sandbox_patch_declaration))
 (approval_source : option (D.denote approval_declaration)) (value : world) := ltac:(
 let body := eval unfold Tasks.configure_execution in
   (Tasks.configure_execution id name reasoning sandbox_source approval_source value) in
 derive_task_lookup_view constr:(Tasks.configure_execution id name reasoning sandbox_source approval_source value) body id value reduce_task_plan).

Definition fork_with_caller_expression (entry : fork_entry) (origin : fork_settings_origin) (id : N) (count : TaskConstraints.fork_count)
 (messages : list content) (settings : option settings_request) (value : world) := ltac:(
 let body := eval cbv beta iota zeta delta [Tasks.fork_with_caller Tasks.fork_result] in
   (Tasks.fork_with_caller entry origin id count messages settings value) in
 derive_task_lookup_view constr:(Tasks.fork_with_caller entry origin id count messages settings value) body id value reduce_task_plan).
