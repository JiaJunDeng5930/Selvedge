From Selvedge.Kernel Require TaskWake.
From Selvedge.Programming Require TaskChange TaskResult TaskScope TaskScopeProofs.
From Selvedge.Kernel Require Import CallbackChangesProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Programming Require OptionObservationProofs.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Reasoning ReasoningProtocol ReasoningView ContextUpdates Callbacks Scheduler Dispatch LifecycleProofs.
From Selvedge.Kernel Require Import ReasoningPlan.
From Selvedge.Kernel Require Import TicketedRequest ScopedRequestProofs TicketedRequestProofs.
Import ListNotations.
Open Scope list_scope.

Theorem nonzero_process_exit_invalidates_the_reasoning_lease :
 forall owner history identity result code,
 natural_field "exit_code"%string result = Some code -> (0 <? code)%N = true ->
 History.history_lease owner (history ++ [FunctionOutput identity result false]) = History.NoLease.
Proof.
 intros owner history identity result code Exit Failed.
 unfold History.history_lease. rewrite fold_left_app. cbn.
 unfold History.failed_result. rewrite Exit, Failed. reflexivity.
Qed.

Theorem a_supported_evaluator_choice_continues_the_running_task :
 forall owner effort generations task policy phase operations,
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 task_lifecycle task = Running phase operations ->
 Reasoning.allowed policy effort = true ->
 ReasoningProtocol.valid_generations (reasoning_max_lease policy) generations = true ->
 let completed := Reasoning.complete owner (Reasoning.Chosen effort generations) task in
 task_activity completed = ReadyForModel /\
 task_history completed = task_history task ++ [ReasoningRecord owner effort generations false].
Proof.
 intros owner effort generations
  [contract profile settings lifecycle history queued lineage parent cursor consumed]
  policy phase operations Policy RunningTask Effort Duration.
 cbn in Policy, RunningTask. subst lifecycle.
 unfold Reasoning.complete, Reasoning.complete_changes. cbn [task_current_profile]. rewrite Policy, Effort, Duration.
 unfold TaskWake.promote, TaskWake.promote_changes, TaskChange.apply, TaskChange.apply_edit, with_activity, append_history, with_history, task_activity.
 split; reflexivity.
Qed.

Theorem failed_reasoning_with_no_queued_input_is_idle : forall owner reason task policy,
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 task_queued task = [] ->
 task_activity (Reasoning.complete owner (Reasoning.EvaluationFailed reason) task) = Idle.
Proof.
 intros owner reason [contract profile settings lifecycle history queued lineage parent cursor consumed] policy Policy Queued.
 cbn in Policy, Queued. subst queued.
 unfold Reasoning.complete, Reasoning.complete_changes. cbn [task_current_profile]. rewrite Policy.
 unfold Reasoning.failed, Reasoning.failed_changes; unfold TaskWake.promote, TaskWake.promote_changes, TaskChange.apply, TaskChange.apply_edit, with_activity, append_history, with_history, task_activity.
 destruct lifecycle; reflexivity.
Qed.

Theorem unsupported_reasoning_with_no_queued_input_is_idle : forall owner effort generations task policy,
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 Reasoning.allowed policy effort && ReasoningProtocol.valid_generations (reasoning_max_lease policy) generations = false ->
 task_queued task = [] -> task_activity (Reasoning.complete owner (Reasoning.Chosen effort generations) task) = Idle.
Proof.
 intros owner effort generations [contract profile settings lifecycle history queued lineage parent cursor consumed] policy Policy Rejected Queued.
 cbn in Policy, Queued. subst queued.
 unfold Reasoning.complete, Reasoning.complete_changes. cbn [task_current_profile]. rewrite Policy, Rejected.
 unfold Reasoning.failed, Reasoning.failed_changes; unfold TaskWake.promote, TaskWake.promote_changes, TaskChange.apply, TaskChange.apply_edit, with_activity, append_history, with_history, task_activity.
 destruct lifecycle; reflexivity.
Qed.

Theorem actual_stale_evaluator_completion_retains_its_evidence : forall id ticket length outcome value task,
 find_task id value = Some task ->
 task_activity task = EvaluatingReasoning ticket length ->
 Nat.eqb length (List.length (task_history task)) = false ->
 decision_effects (Callbacks.reasoning_completed id ticket outcome value) = [] /\
 exists updated,
 find_task id (decision_world (Callbacks.reasoning_completed id ticket outcome value)) = Some updated /\
 task_activity updated = ReadyForModel /\ task_history updated = task_history task.
Proof.
 intros id ticket length outcome value task Found Phase Changed.
 rewrite !reasoning_completed_expression. rewrite Found, Phase, N.eqb_refl, Changed.
 split; [reflexivity|]. eexists; split; [eapply find_put_task; exact Found|].
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle; cbn in Phase; try discriminate; split; reflexivity.
Qed.

Lemma failed_evaluation_is_never_ready_for_a_model : forall reason task,
 task_activity (Reasoning.failed reason task) <> ReadyForModel.
Proof.
 intros reason [contract profile settings lifecycle history queued lineage parent cursor consumed].
 unfold Reasoning.failed, Reasoning.failed_changes; unfold TaskWake.promote, TaskWake.promote_changes, TaskChange.apply, TaskChange.apply_edit, with_activity, append_history, with_history, task_activity.
 destruct lifecycle; destruct queued; discriminate.
Qed.
Theorem a_ready_evaluator_choice_has_a_supported_frozen_duration : forall owner effort generations task policy,
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 task_activity (Reasoning.complete owner (Reasoning.Chosen effort generations) task) = ReadyForModel ->
 (generations = 1%N \/ generations = 2%N \/ generations = 5%N \/ generations = 10%N) /\
 (generations <= reasoning_max_lease policy)%N.
Proof.
 intros owner effort generations task policy Policy Ready.
 unfold Reasoning.complete, Reasoning.complete_changes in Ready. rewrite Policy in Ready.
 destruct (Reasoning.allowed policy effort && ReasoningProtocol.valid_generations (reasoning_max_lease policy) generations) eqn:Admitted.
 - apply andb_true_iff in Admitted as [_ Duration].
   unfold ReasoningProtocol.valid_generations in Duration.
   apply andb_true_iff in Duration as [Member Bounded].
   apply existsb_exists in Member as [choice [Choices Equal]].
   apply N.eqb_eq in Equal; subst choice.
   unfold ReasoningProtocol.lease_generations in Choices. simpl in Choices.
   split; [intuition congruence|now apply N.leb_le].
 - exfalso. eapply failed_evaluation_is_never_ready_for_a_model; exact Ready.
Qed.

Theorem task_settings_do_not_revoke_a_reasoning_lease : forall owner history settings profile effort,
 History.history_lease owner (history ++ [SettingsMessage settings profile effort]) =
 History.history_lease owner history.
Proof. intros; unfold History.history_lease; rewrite fold_left_app; reflexivity. Qed.

Theorem a_before_hook_receipt_breaks_the_trailing_configuration_frame :
 forall history owner invocation plugin outcome,
 Reasoning.trailing_configuration (history ++ [HookReceipt owner invocation plugin outcome]) = false.
Proof. intros; unfold Reasoning.trailing_configuration, TicketedRequest.trailing_configuration, ReasoningPlan.trailing_configuration; rewrite fold_left_app; reflexivity. Qed.

Theorem an_adaptive_profile_without_a_lease_requests_its_evaluator : forall id task value policy,
 find_task id value = Some task ->
 TicketedRequest.Scoped.can_infer task value = true ->
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 History.history_lease id (task_history task) = History.NoLease ->
 decision_effects (Scheduler.ready_model id value) =
 [RequestReasoning id (world_next_ticket value) task].
Proof.
 intros id task value policy Found InferAllowed Policy Lease. unfold Scheduler.ready_model.
 destruct (model_selects_the_current_task id value task Found InferAllowed)
   as [plan [Selected [Owner [Current Intent]]]].
 unfold TicketedRequest.Scoped.run; rewrite Selected,issued_effects.
 unfold TicketedRequest.Scoped.build; rewrite Intent,Owner,Current.
 assert (Evaluator : ModelRequest.Plans.next id task = ModelRequest.Plans.Evaluate).
 { unfold ModelRequest.Plans.next; rewrite Policy,Lease; reflexivity. }
 rewrite (ModelRequestConstructionProofs.choosing_an_evaluator id task Evaluator); reflexivity.
Qed.

Theorem actual_model_requests_retain_the_complete_committed_history : forall id model task value,
 find_task id value = Some task ->
 TicketedRequest.Scoped.can_infer task value = true ->
 ReasoningPlan.next id task = ReasoningPlan.Fixed model ->
 exists request,
 decision_effects (Scheduler.ready_model id value) = [RequestModel request] /\
 ModelRequest.history request = task_history task /\
 task_contract (ModelRequest.context_task request) = task_contract task.
Proof.
 intros id model task value Found InferAllowed Fixed. unfold Scheduler.ready_model.
 destruct (model_selects_the_current_task id value task Found InferAllowed)
   as [plan [Selected [Owner [Current Intent]]]].
 unfold TicketedRequest.Scoped.run; rewrite Selected.
 destruct (fixed_inference_freezes_its_complete_context value plan model Intent
   ltac:(now rewrite Owner,Current))
   as [request [Effects [Owned [Ticket [Origin [Model [History [Cursor Contract]]]]]]]].
 exists request; rewrite Current in *; repeat split; assumption.
Qed.

Theorem actual_model_generation_consumes_one_lease_step : forall owner model remaining task,
 exists prefix suffix,
 task_history (Reasoning.generation owner model remaining task) =
 prefix ++ [ReasoningRecord owner (profile_reasoning model) (N.pred remaining) true] ++ suffix /\
 (prefix = task_history task \/
  prefix = task_history task ++ [FailureMessage "The previous generation has no retained output after its configuration update; continuing from the committed request prefix."]) /\
 (suffix = [] \/ suffix = [ReasoningConfigurationMessage (profile_reasoning model)]).
Proof.
 intros owner model remaining task. unfold Reasoning.generation, TicketedRequest.generation, ReasoningPlan.generation, ModelRequest.Plans.generation_messages.
 destruct (match profile_policy (task_current_profile task) with
 | AdaptivePolicy policy => match reasoning_transport_mode policy with
   | RequestEffort => false | ConfigurationUpdates =>
     match ReasoningPlan.last_configuration (task_history task) with None => true | Some previous => negb (String.eqb previous (profile_reasoning model)) end end
 | FixedReasoning => false end);
 destruct (ReasoningPlan.trailing_configuration (task_history task));
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed];
 cbn [andb app Domain.append_history Domain.with_history task_history].
 - exists (history ++ [FailureMessage "The previous generation has no retained output after its configuration update; continuing from the committed request prefix."]),
     [ReasoningConfigurationMessage (profile_reasoning model)].
   split; [now rewrite <- app_assoc|split; [now right|now right]].
 - exists history, [ReasoningConfigurationMessage (profile_reasoning model)].
   split; [reflexivity|split; [now left|now right]].
 - exists history, []. repeat rewrite app_nil_r; split; [reflexivity|split; now left].
 - exists history, []. repeat rewrite app_nil_r; split; [reflexivity|split; now left].
Qed.

Theorem context_requests_capture_the_current_history_revision : forall id task value phase operations,
 find_task id value = Some task ->
 TicketedRequest.Scoped.can_observe false task value = true -> task_lifecycle task = Running phase operations ->
 decision_effects (Reasoning.context_retry id value) =
 [ObserveContext id (world_next_ticket value) task] /\
 exists waiting,
 find_task id (decision_world (Reasoning.context_retry id value)) = Some waiting /\
 task_activity waiting = ObservingContext (world_next_ticket value) (List.length (task_history task)) /\
 task_history waiting = task_history task /\ task_contract waiting = task_contract task.
Proof.
 intros id task value phase operations Found ObserveAllowed RunningTask.
 destruct (observing_selects_the_current_task id value task false Found ObserveAllowed)
   as [request [Selected [Owner [Current Intent]]]].
 assert (Issued : Reasoning.context_retry id value = TicketedRequest.Scoped.issue request).
 { unfold TicketedRequest.Scoped.observe in Selected; unfold Reasoning.context_retry.
   destruct (TaskScope.select id value); [now rewrite Selected|discriminate]. }
 rewrite Issued; split.
 - rewrite issued_effects; unfold TicketedRequest.Scoped.build; rewrite Intent,Owner,Current; reflexivity.
 - rewrite <- Owner,issued_task.
   eexists; split; [reflexivity|].
   unfold TicketedRequest.Scoped.build; rewrite Intent,Current; cbn [fst app].
   change (task_activity (with_activity (ObservingContext (world_next_ticket value)
     (List.length (task_history task))) task) = ObservingContext (world_next_ticket value)
     (List.length (task_history task)) /\
     task_history (with_activity (ObservingContext (world_next_ticket value)
       (List.length (task_history task))) task) = task_history task /\
     task_contract (with_activity (ObservingContext (world_next_ticket value)
       (List.length (task_history task))) task) = task_contract task).
   unfold with_activity; rewrite RunningTask; repeat split; reflexivity.
Qed.

Theorem the_actual_scheduler_observes_before_preparing_a_model : forall execute id task value operations,
 task_lifecycle task = Running WantsModel operations ->
 Scheduler.ready_operation operations = None ->
 Scheduler.task_step execute id task value =
 Some (Reasoning.observe_scheduled_context id value).
Proof.
 intros execute id task value operations RunningTask NoOperation.
 unfold Scheduler.task_step; rewrite RunningTask, NoOperation; reflexivity.
Qed.

Theorem context_completion_requires_the_current_ticket : forall id ticket expected revision observations diagnostic value task,
 find_task id value = Some task -> task_activity task = ObservingContext expected revision ->
 N.eqb expected ticket = false ->
 Callbacks.context_completed id ticket observations diagnostic value = Callbacks.ignored value.
Proof. intros; rewrite context_completed_expression; now rewrite H, H0, H1. Qed.

Theorem an_actual_stale_context_result_restarts_from_the_current_prefix :
 forall id ticket revision observations diagnostic value task phase operations,
 find_task id value = Some task -> task_activity task = ObservingContext ticket revision ->
 task_lifecycle task = Running phase operations ->
 Nat.eqb revision (List.length (task_history task)) = false ->
 Callbacks.context_completed id ticket observations diagnostic value = Reasoning.context_retry id value.
Proof.
 intros id ticket revision observations diagnostic value task phase operations Found Phase RunningTask Stale.
 rewrite context_completed_expression; rewrite Found, Phase, N.eqb_refl, Stale, RunningTask; reflexivity.
Qed.

Theorem unavailable_context_retry_keeps_unsatisfied_demand :
 forall id ticket revision observations diagnostic value task operations,
 find_task id value = Some task ->
 task_lifecycle task = Running (ObservingContext ticket revision) operations ->
 Nat.eqb revision (List.length (task_history task)) = false ->
 TicketedRequest.Scoped.resources_available task value = false ->
 Callbacks.context_completed id ticket observations diagnostic value =
 accept (JObject [("accepted"%string,JBool false)]) (put_task id (with_activity WantsModel task) value) [].
Proof.
 intros id ticket revision observations diagnostic value task operations Found Status Stale Resource.
 assert (Phase : task_activity task = ObservingContext ticket revision).
 { unfold task_activity; now rewrite Status. }
 rewrite context_completed_expression, Found, Phase, N.eqb_refl, Stale, Status.
 destruct (TaskScopeProofs.selecting_an_existing_task_retains_its_key id value task Found)
   as [reference [Selected [Owner Current]]].
 unfold Reasoning.context_retry; rewrite Selected.
 unfold TicketedRequest.Scoped.observe_selected.
 pattern (TicketedRequest.Scoped.observe_allowed false reference _ eq_refl).
 apply (@OptionObservationProofs.observed_value_elimination _ _ _
   (@TicketedRequest.Scoped.observe_allowed value false reference)); intros condition Evidence.
 assert (Unavailable : condition = false).
 { rewrite Current in Evidence; unfold TicketedRequest.Scoped.can_observe in Evidence.
   rewrite Resource in Evidence; cbn in Evidence; symmetry; exact Evidence. }
 revert Evidence; rewrite Unavailable; intro Evidence; cbn [TicketedRequest.Scoped.observe_allowed].
 rewrite Owner,Current; unfold Reasoning.context_retry_wait; now rewrite Status.
Qed.

Theorem a_frozen_context_completion_waits_for_a_new_observation :
 forall id ticket revision observations diagnostic value task phase operations,
 find_task id value = Some task -> task_activity task = ObservingContext ticket revision ->
 task_lifecycle task = Frozen phase operations ->
 decision_effects (Callbacks.context_completed id ticket observations diagnostic value) = [] /\
 exists waiting,
 find_task id (decision_world (Callbacks.context_completed id ticket observations diagnostic value)) = Some waiting /\
 task_lifecycle waiting = Frozen WantsModel operations.
Proof.
 intros id ticket revision observations diagnostic value task phase operations Found Phase FrozenTask.
 rewrite context_completed_expression; rewrite Found, Phase, N.eqb_refl.
 destruct (Nat.eqb revision (List.length (task_history task))).
 - destruct (Callbacks.observed_context_history observations diagnostic (task_history task)) as [accepted messages].
   unfold Callbacks.context_phase; rewrite FrozenTask.
   split; [reflexivity|].
   eexists; split; [eapply find_put_task; exact Found|].
   change (change_activity WantsModel (task_lifecycle task) =
     Frozen WantsModel operations).
   now rewrite FrozenTask.
 - rewrite FrozenTask, context_ready_expression, Found.
   unfold Callbacks.context_phase; rewrite FrozenTask. split; [reflexivity|].
   eexists; split; [eapply find_put_task; exact Found|].
   change (change_activity WantsModel (task_lifecycle task) = Frozen WantsModel operations).
   now rewrite FrozenTask.
Qed.

Theorem a_stopped_context_completion_waits_for_a_new_observation :
 forall id ticket revision observations diagnostic value task phase operations,
 find_task id value = Some task -> task_activity task = ObservingContext ticket revision ->
 task_lifecycle task = Stopped phase operations ->
 decision_effects (Callbacks.context_completed id ticket observations diagnostic value) = [] /\
 exists waiting,
 find_task id (decision_world (Callbacks.context_completed id ticket observations diagnostic value)) = Some waiting /\
 task_lifecycle waiting = Stopped WantsModel operations.
Proof.
 intros id ticket revision observations diagnostic value task phase operations Found Phase StoppedTask.
 rewrite context_completed_expression; rewrite Found, Phase, N.eqb_refl.
 destruct (Nat.eqb revision (List.length (task_history task))).
 - destruct (Callbacks.observed_context_history observations diagnostic (task_history task)) as [accepted messages].
   unfold Callbacks.context_phase; rewrite StoppedTask.
   split; [reflexivity|].
   eexists; split; [eapply find_put_task; exact Found|].
   change (change_activity WantsModel (task_lifecycle task) =
     Stopped WantsModel operations).
   now rewrite StoppedTask.
 - rewrite StoppedTask, context_ready_expression, Found.
   unfold Callbacks.context_phase; rewrite StoppedTask. split; [reflexivity|].
   eexists; split; [eapply find_put_task; exact Found|].
   change (change_activity WantsModel (task_lifecycle task) = Stopped WantsModel operations).
   now rewrite StoppedTask.
Qed.

Theorem actual_evaluator_history_is_bounded_in_encoded_bytes : forall owner task,
 (String.length (TextJson.render_json (JArray (Reasoning.evaluator_history owner task))) <= 16384)%nat.
Proof.
 intros; unfold Reasoning.evaluator_history, ReasoningView.history.
 match goal with |- context [if ?condition then _ else _] => destruct condition eqn:Full end;
 [now apply Nat.leb_le in Full|].
 match goal with |- context [if ?condition then _ else _] => destruct condition eqn:Essential end;
 [now apply Nat.leb_le in Essential|].
 apply Nat.leb_le; vm_compute; reflexivity.
Qed.

Theorem public_evaluator_history_omits_fork_receipts : forall owner invocation branch,
 ReasoningView.public_message (ForkReceipt owner invocation branch) = None.
Proof. reflexivity. Qed.

Theorem public_evaluator_messages_keep_call_identity : forall id arguments,
 field "call_id" (ReasoningView.preview_message
   (JObject [("role",JString "function_output");("call_id",JString id);("content",arguments)])) = Some (JString id).
Proof. reflexivity. Qed.

Theorem public_evaluator_notes_keep_their_reasoning_category : forall text,
 ReasoningView.preview_message (ReasoningView.text_message "reasoning_summary" text) =
 ReasoningView.text_message "reasoning_summary" (ReasoningView.excerpt text).
Proof. reflexivity. Qed.

Theorem encrypted_provider_continuations_are_redacted_before_preview : forall secret,
 ReasoningView.public_value 512 (JObject [("encrypted_content",secret)]) =
 JObject [("encrypted_content",JString "[Private provider continuation omitted]")].
Proof. reflexivity. Qed.

Theorem provider_reasoning_exposes_only_its_public_summary : forall secret summary,
 ReasoningView.public_value 512 (JObject [("type",JString "reasoning");
   ("encrypted_content",secret);("summary",JArray summary)]) =
 JObject [("type",JString "reasoning");("summary",JArray (ReasoningView.public_parts summary))].
Proof. reflexivity. Qed.

Theorem short_unicode_evaluator_text_is_retained : forall text parts,
 Utf8.chunks text = Some parts -> (List.length parts <=? 1024)%nat = true ->
 ReasoningView.excerpt text = text.
Proof. intros; unfold ReasoningView.excerpt; now rewrite H, H0. Qed.

Theorem configuration_transport_keeps_the_request_baseline : forall model requested policy,
 profile_policy requested = AdaptivePolicy policy -> reasoning_transport_mode policy = ConfigurationUpdates ->
 Reasoning.sampling model requested = JObject [
   ("effective_effort",JString (profile_reasoning model));("request_effort",JString (reasoning_baseline policy))].
Proof. intros; unfold Reasoning.sampling; now rewrite H, H0. Qed.

Theorem side_context_rebasing_recaptures_its_updated_history : forall id ticket original value current revision,
 Dispatch.side_task id value = Some current ->
 task_activity current = ObservingContext ticket revision ->
 Dispatch.capture_request (ObserveContext id ticket original) value =
 (put_task id (Reasoning.capture ticket current) value,
  ObserveContext id ticket (with_history (task_history current) original)).
Proof.
 intros id ticket original value current revision Selected Phase.
 unfold Dispatch.side_task in Selected.
 destruct (find_task id value) as [task|] eqn:Found; [|discriminate].
 destruct (task_side_parent task); inversion Selected; subst task.
 unfold Dispatch.capture_request, RequestReceiver.pending_phase, RequestReceiver.phase_receiver; now rewrite Found, Phase, N.eqb_refl.
Qed.

Theorem public_evaluator_assistant_content_remains_text : forall origin text,
 option_map ReasoningView.preview_message (ReasoningView.public_message (AssistantMessage origin text)) =
 Some (ReasoningView.text_message "assistant" (ReasoningView.excerpt text)).
Proof. reflexivity. Qed.

Theorem model_context_preview_exposes_only_the_public_reasoning_summary : forall origin secret summary,
 ReasoningView.public_message (ModelContext origin (JObject [("type",JString "reasoning");
   ("encrypted_content",secret);("summary",JArray summary)])) =
 Some (ReasoningView.text_message "reasoning_summary" (ReasoningView.public_parts_text summary)).
Proof. reflexivity. Qed.
