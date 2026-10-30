From Selvedge.Kernel Require Import CallbackChangesProofs.
From Selvedge.Kernel Require Import TaskChangesProofs.
From Stdlib Require Import String List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain State Tasks CommandExecution Scheduler Codec Limits Inputs TicketedRequest ScopedRequestProofs ReasoningPlan TicketedRequestProofs.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

Theorem full_access_dispatch_is_unrestricted : forall id tool invocation remaining task value,
 find_task id value = Some task ->
 TicketedRequest.Scoped.can_execute task = true ->
 task_activity task = ReadyForHooks invocation [] remaining ->
 find_tool (call_name invocation) (contract_tools (task_contract task)) = Some tool ->
 settings_approval (task_current_settings task) = FullAccess ->
 N.ltb (N.of_nat (List.length (task_operations task))) Limits.operation_limit = true ->
 decision_effects (Scheduler.start_external id value) =
 [ExecuteTool id (world_next_ticket value) (world_next_ticket value) tool invocation
   (task_current_settings task) ElevatedAccess].
Proof.
 intros id tool invocation remaining task value Found ExecuteAllowed Ready Known Full Room.
 destruct (starting_selects_the_current_call id value task tool invocation remaining
   (TicketedRequest.Scoped.external_authority_for task invocation) Found
   ltac:(unfold TicketedRequest.Scoped.call_action; now rewrite ExecuteAllowed,Ready,Known))
   as [request [Selected [Owner [Current Intent]]]].
 unfold Scheduler.start_external; rewrite Selected,Current,Room.
 rewrite issued_effects; unfold TicketedRequest.Scoped.build; rewrite Intent,Owner,Current.
 cbn [snd].
 unfold TicketedRequest.Scoped.external_authority_for; now rewrite Full.
Qed.

Lemma unobserved_roots_fail_native_admission : forall options selected caller value root,
 In root (workspace_roots (settings_workspace selected)) ->
 ~ In root (Tasks.observed_creation_roots selected caller value) ->
 Tasks.native_creation_allowed options selected caller value = false.
Proof.
 intros options selected caller value root Member Unknown.
 destruct (Tasks.native_creation_allowed options selected caller value) eqn:Admitted; [|reflexivity].
 unfold Tasks.native_creation_allowed in Admitted.
 apply andb_true_iff in Admitted as [_ Roots].
 apply forallb_forall with (x:=root) in Roots; [|exact Member].
 apply existsb_exists in Roots as [known [Known Equal]].
 apply String.eqb_eq in Equal; subst known; contradiction.
Qed.
Theorem actual_native_creation_rejects_unobserved_roots : forall name effort contents options caller_id value caller plan root,
 find_task caller_id value = Some caller ->
 CommandExecution.resolve_context_start NativeCreation name effort contents options false (Some caller_id) value = StartResolved plan ->
 In root (workspace_roots (settings_workspace (start_settings plan))) ->
 ~ In root (Tasks.observed_creation_roots (start_settings plan) (task_current_settings caller) value) ->
 decision_world (CommandExecution.create_in_context name effort contents options false (Some caller_id) value) = value /\
 decision_effects (CommandExecution.create_in_context name effort contents options false (Some caller_id) value) = [].
Proof.
 intros name effort contents options caller_id value caller plan root Found Resolved Member Unknown.
 unfold CommandExecution.create_in_context; rewrite Resolved.
 unfold CommandExecution.creation_allowed; rewrite Found.
 rewrite (unobserved_roots_fail_native_admission options (start_settings plan) (task_current_settings caller) value root Member Unknown).
 split; reflexivity.
Qed.
Theorem native_creation_cannot_supply_guidance_observations : forall source selected caller value guidance,
 field "guidance" source = Some guidance ->
 Tasks.native_creation_allowed (Some source) selected caller value = false.
Proof.
 intros; unfold Tasks.native_creation_allowed; rewrite H.
 destruct (Workspace.may_delegate selected caller); reflexivity.
Qed.

(* Native fork runs while its caller's model calls are pending. Unlike creation,
   it delegates an already resolved selection and does not observe directories. *)
Theorem a_full_access_native_fork_accepts_a_fixed_selection :
 forall invocation origin id count messages options value task selected selection remaining operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (PendingCalls remaining) operations ->
 TaskConstraints.fork_count_valid count (contract_max_fork (task_contract task)) = true ->
 TaskConstraints.fork_messages_valid count (List.length messages) = true ->
 Tasks.ancestors_fit (id :: task_lineage task) count value = true ->
 Tasks.resolve_settings (task_current_profile task) options (Tasks.fork_settings_base origin task value) value = Some selected ->
 Tasks.admit_fork_selection task value selected = Some selection ->
 Tasks.no_resource_observation options = true ->
 settings_approval (task_current_settings task) = FullAccess ->
 decision_world (Tasks.fork_with_caller (Tasks.AcceptedNativeFork invocation remaining) origin id count messages options value) =
   Tasks.fork_children (N.to_nat count) id task messages (Tasks.fork_selected task value selection)
     (Tasks.AcceptedNativeFork invocation remaining) (next_task value) invocation value.
Proof.
 intros invocation origin id count messages options value task selected selection remaining operations
   Found Pending Count Messages Capacity Resolved Fixed Observed Full.
 rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta; unfold Tasks.fork_parent_ready; rewrite Found, Pending.
 cbn [andb]. rewrite Count, Messages, Capacity, Resolved, Fixed.
 unfold Workspace.may_delegate; rewrite Full, Observed; cbn [negb andb].
 destruct (allocate_ticket value); reflexivity.
Qed.

(* No catalog-membership premise is needed: the actual authorization request
   carries the reviewer frozen in task settings, including across reloads. *)
Theorem actual_approval_uses_the_frozen_reviewer : forall id tool invocation remaining task value reviewer,
 find_task id value = Some task ->
 TicketedRequest.Scoped.can_execute task = true ->
 task_activity task = ReadyForHooks invocation [] remaining ->
 find_tool (call_name invocation) (contract_tools (task_contract task)) = Some tool ->
 N.ltb (N.of_nat (List.length (task_operations task))) Limits.operation_limit = true ->
 call_name invocation = "bash" ->
 text_default "sandbox_permissions" (call_arguments invocation) "use_default" = "require_escalated" ->
 settings_approval (task_current_settings task) = ReviewWith reviewer ->
 decision_effects (Scheduler.start_external id value) =
 [RequestApproval id (world_next_ticket value) reviewer invocation
   (Tasks.promote (Scheduler.append_operation
     (Operation (world_next_ticket value) invocation false
       (AwaitingApproval (world_next_ticket value) (ModelReviewer reviewer))) remaining task))].
Proof.
 intros id tool invocation remaining task value reviewer Found ExecuteAllowed Ready Known Room Bash Elevated Policy.
 destruct (starting_selects_the_current_call id value task tool invocation remaining
   (TicketedRequest.Scoped.external_authority_for task invocation) Found
   ltac:(unfold TicketedRequest.Scoped.call_action; now rewrite ExecuteAllowed,Ready,Known))
   as [request [Selected [Owner [Current Intent]]]].
 unfold Scheduler.start_external; rewrite Selected,Current,Room.
 rewrite issued_effects; unfold TicketedRequest.Scoped.build; rewrite Intent,Owner,Current.
 unfold TicketedRequest.Scoped.external_authority_for.
 rewrite Policy, Bash, Elevated; reflexivity.
Qed.

(* An announcement closes the provider call's immediate obligation. The
   underlying external operation may remain live during independent inference;
   queued input is promoted before that turn observes and captures context. *)
Theorem announced_operations_allow_an_independent_model_turn : forall execute id task value operations,
 find_task id value = Some task ->
 TicketedRequest.Scoped.can_observe true task value = true ->
 task_lifecycle task = Running WantsModel operations ->
 Scheduler.ready_operation operations = None ->
 exists result,
 Scheduler.task_step execute id task value = Some result /\
 decision_effects result = [ObserveContext id (world_next_ticket value) (Scheduler.publish_operations (Tasks.promote task))].
Proof.
 intros execute id task value operations Found ObserveAllowed Phase NoReady.
 unfold Scheduler.task_step; rewrite Phase, NoReady.
 eexists; split; [reflexivity|].
 unfold Reasoning.observe_scheduled_context.
 destruct (observing_selects_the_current_task id value task true Found ObserveAllowed)
   as [request [Selected [Owner [Current Intent]]]].
 unfold TicketedRequest.Scoped.run; rewrite Selected,issued_effects.
 unfold TicketedRequest.Scoped.build; rewrite Intent,Owner,Current; cbn [snd].
 rewrite TaskChangeProofs.apply_app; reflexivity.
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
 rewrite CallbackChangesProofs.model_completed_expression; rewrite Found.
 unfold task_activity; rewrite Phase, N.eqb_refl.
 eexists; split; [reflexivity|].
 unfold Callbacks.model_result, Callbacks.model_result_changes; cbn [Callbacks.permitted_items Callbacks.item_messages Callbacks.item_calls].
 assert (NoOutput : append_history [] task = task).
 { unfold append_history; rewrite app_nil_r; destruct task; reflexivity. }
 change (task_lifecycle (Callbacks.settle_model (append_history [] task)) = Running WantsModel operations).
 rewrite NoOutput. rewrite CallbackChangesProofs.settle_model_expression; rewrite Unseen.
 destruct task as [contract chosen settings lifecycle history queued lineage parent cursor consumed].
 cbn in Phase; subst lifecycle; destruct queued; reflexivity.
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

Theorem an_eligible_native_fork_accepts_its_observed_selection :
 forall invocation remaining origin id count messages options value task selected selection,
 find_task id value = Some task ->
 Tasks.fork_parent_ready (Tasks.AcceptedNativeFork invocation remaining) task = true ->
 TaskConstraints.fork_count_valid count (contract_max_fork (task_contract task)) = true ->
 TaskConstraints.fork_messages_valid count (List.length messages) = true ->
 Tasks.ancestors_fit (id :: task_lineage task) count value = true ->
 Tasks.resolve_settings (task_current_profile task) options (Tasks.fork_settings_base origin task value) value = Some selected ->
 Tasks.admit_fork_selection task value selected = Some selection ->
 Workspace.may_delegate (Tasks.fork_selected task value selection) (task_current_settings task) = true ->
 Tasks.no_resource_observation options = true ->
 Tasks.fork_with_caller (Tasks.AcceptedNativeFork invocation remaining) origin id count messages options value =
 accept (JObject [("children", JArray (map (fun offset => number (next_task value + N.of_nat offset))
   (seq 0 (N.to_nat count))))])
   (Tasks.fork_children (N.to_nat count) id task messages (Tasks.fork_selected task value selection)
     (Tasks.AcceptedNativeFork invocation remaining) (next_task value) invocation value) [].
Proof.
 intros invocation remaining origin id count messages options value task selected selection
   Found Eligible Count Messages Capacity Resolved Fixed Delegated Observed.
 rewrite TaskChangesProofs.fork_with_caller_expression; cbv beta zeta; rewrite Found, Eligible, Count, Messages, Capacity, Resolved, Fixed.
 cbn [andb]. rewrite Delegated, Observed. cbn [negb andb].
 destruct (allocate_ticket value); reflexivity.
Qed.
