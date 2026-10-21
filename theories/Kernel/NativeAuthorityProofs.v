From Stdlib Require Import String List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Domain State Tasks CommandExecution Scheduler Codec Limits Inputs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Lemma unobserved_roots_fail_native_admission : forall options selected caller value root,
 In root (workspace_roots (settings_workspace selected)) ->
 ~ In root (Tasks.observed_creation_roots caller value) ->
 Tasks.native_settings_bound options selected caller value = false.
Proof.
 intros options selected caller value root Member Unknown.
 destruct (Tasks.native_settings_bound options selected caller value) eqn:Admitted; [|reflexivity].
 unfold Tasks.native_settings_bound in Admitted.
 apply andb_true_iff in Admitted as [_ Roots].
 apply forallb_forall with (x:=root) in Roots; [|exact Member].
 apply existsb_exists in Roots as [known [Known Equal]].
 apply String.eqb_eq in Equal; subst known; contradiction.
Qed.
Theorem actual_native_creation_rejects_unobserved_roots : forall name effort contents options caller_id value caller selected root,
 find_task caller_id value = Some caller ->
 resolve_for_profile name options (task_current_settings caller) value = Some selected ->
 In root (workspace_roots (settings_workspace selected)) ->
 ~ In root (Tasks.observed_creation_roots (task_current_settings caller) value) ->
 decision_world (CommandExecution.create_in_context name effort contents options false (Some caller_id) value) = value /\
 decision_effects (CommandExecution.create_in_context name effort contents options false (Some caller_id) value) = [].
Proof.
 intros name effort contents options caller_id value caller selected root Found Resolved Member Unknown.
 unfold CommandExecution.create_in_context; rewrite Found, Resolved.
 rewrite (unobserved_roots_fail_native_admission options selected (task_current_settings caller) value root Member Unknown).
 split; reflexivity.
Qed.
Theorem native_calls_cannot_supply_guidance_observations : forall source selected caller value guidance,
 field "guidance" source = Some guidance ->
 Tasks.native_settings_bound (Some source) selected caller value = false.
Proof.
 intros; unfold Tasks.native_settings_bound; rewrite H.
 destruct (Workspace.settings_bound selected caller); reflexivity.
Qed.
(* No catalog-membership premise is needed: the actual authorization request
   carries the reviewer frozen in task settings, including across reloads. *)
Theorem actual_approval_uses_the_frozen_reviewer : forall id tool invocation remaining task value reviewer,
 N.ltb (N.of_nat (List.length (task_operations task))) Limits.operation_limit = true ->
 call_name invocation = "bash" ->
 text_default "sandbox_permissions" (call_arguments invocation) "use_default" = "require_escalated" ->
 settings_approval (task_current_settings task) = ReviewWith reviewer ->
 decision_effects (Scheduler.start_external id tool invocation remaining task value) =
 [RequestApproval id (world_next_ticket value) reviewer invocation task].
Proof.
 intros id tool invocation remaining task value reviewer Room Bash Elevated Policy.
 unfold Scheduler.start_external; rewrite Room, Bash, Elevated; cbn.
 rewrite Policy; reflexivity.
Qed.

(* An announcement closes the provider call's immediate obligation. The
   underlying external operation may remain live during independent inference. *)
Theorem announced_operations_allow_an_independent_model_turn : forall execute id task value operations,
 task_lifecycle task = Running WantsModel operations ->
 Scheduler.ready_operation operations = None ->
 exists result,
 Scheduler.task_step execute id task value = Some result /\
 decision_effects result = [ObserveContext id (world_next_ticket value) (Scheduler.publish_operations task)].
Proof.
 intros execute id task value operations Phase NoReady.
 unfold Scheduler.task_step; rewrite Phase, NoReady.
 eexists; split; reflexivity.
Qed.

Theorem actual_model_request_freezes_the_consumed_history : forall id model task value,
 exists waiting,
 decision_effects (Scheduler.emit_model id model task value) =
 [RequestModel id (world_next_ticket value) model waiting "" 0] /\
 task_history waiting = task_history task /\
 task_model_cursor waiting = List.length (task_history task).
Proof.
 intros id model [contract chosen settings state history queued lineage parent cursor consumed] value.
 destruct state; eexists; repeat split; reflexivity.
Qed.

Theorem a_result_after_the_model_snapshot_is_unconsumed : forall task prefix suffix operation invocation result error,
 task_model_cursor task = List.length prefix ->
 task_history task = prefix ++ OperationResult operation invocation result error :: suffix ->
 unseen_model_input task = true.
Proof.
 intros task prefix suffix operation invocation result error Cursor History.
 unfold unseen_model_input; rewrite Cursor, History, skipn_app, skipn_all, Nat.sub_diag; reflexivity.
Qed.

(* A completion can arrive while the accepted model request is in flight. Its
   result did not belong to that request's frozen input and must get a turn. *)
Theorem an_unconsumed_result_survives_a_model_reply : forall id ticket allowed mode task value operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (AskingModel ticket allowed mode) operations ->
 unseen_model_input task = true ->
 exists updated,
 decision_world (Callbacks.model_completed id ticket (ModelSuccess []) value) = put_task id updated value /\
 task_lifecycle updated = Running WantsModel operations.
Proof.
 intros id ticket allowed mode task value operations Found Phase Unseen.
 unfold Callbacks.model_completed; rewrite Found.
 unfold task_activity; rewrite Phase, N.eqb_refl.
 eexists; split; [reflexivity|].
 unfold Callbacks.model_result; cbn [Callbacks.permitted_items Callbacks.item_messages Callbacks.item_calls].
 assert (NoOutput : append_history [] task = task).
 { unfold append_history; rewrite app_nil_r; destruct task; reflexivity. }
 change (task_lifecycle (Callbacks.settle_model (append_history [] task)) = Running WantsModel operations).
 rewrite NoOutput. unfold Callbacks.settle_model; rewrite Unseen.
 unfold with_activity; rewrite Phase; reflexivity.
Qed.

(** These certificates concern the catalog consumed by the actual native
    dispatcher: no declaration disappears and no tool name shadows another. *)
Theorem production_native_names_are_unique : forall maximum,
 NoDup (map Selvedge.Kernel.Domain.tool_name (Selvedge.Kernel.NativeTools.catalog maximum)).
Proof. intros maximum; vm_compute. repeat (apply NoDup_cons; [simpl; intuition discriminate|]); apply NoDup_nil. Qed.
Theorem production_native_bindings_are_registered : forall binding,
 In binding Selvedge.Kernel.NativeTools.bindings ->
 exists specification, In specification Selvedge.Kernel.Commands.command_specs /\
 Selvedge.Foundation.Schema.command_name specification = Selvedge.Kernel.NativeTools.binding_command binding.
Proof.
 intros binding member.
 assert (registered:forallb (fun binding=>existsb
   (fun specification=>String.eqb (Selvedge.Kernel.NativeTools.binding_command binding)
     (Selvedge.Foundation.Schema.command_name specification))
   Selvedge.Kernel.Commands.command_specs) Selvedge.Kernel.NativeTools.bindings=true) by (vm_compute;reflexivity).
 apply forallb_forall with (x:=binding) in registered; [|exact member].
 apply existsb_exists in registered as [specification [present equal]].
 exists specification;split;[exact present|]. apply String.eqb_eq in equal;congruence.
Qed.
