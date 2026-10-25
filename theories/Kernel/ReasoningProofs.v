From Selvedge.Kernel Require Import CallbackChangesProofs.
From Stdlib Require Import String List Bool NArith PeanoNat Lia.
From Selvedge.Foundation Require Import Json TextJson.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Reasoning ReasoningProtocol ReasoningView ContextUpdates Callbacks Scheduler Dispatch WorldInvariant LifecycleProofs.
From Selvedge.Kernel Require Import ReasoningPlan TicketedRequest ScopedRequestProofs.
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
 rewrite !complete_reasoning_expression. cbn [task_current_profile]. rewrite Policy, Effort, Duration.
 unfold Tasks.promote, Tasks.promote_changes, TaskChange.apply, TaskChange.apply_edit, with_activity, append_history, with_history, task_activity.
 split; reflexivity.
Qed.

Theorem failed_reasoning_with_no_queued_input_is_idle : forall owner reason task policy,
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 task_queued task = [] ->
 task_activity (Reasoning.complete owner (Reasoning.EvaluationFailed reason) task) = Idle.
Proof.
 intros owner reason [contract profile settings lifecycle history queued lineage parent cursor consumed] policy Policy Queued.
 cbn in Policy, Queued. subst queued.
 rewrite !complete_reasoning_expression. cbn [task_current_profile]. rewrite Policy.
 rewrite !failed_reasoning_expression; unfold Tasks.promote, Tasks.promote_changes, TaskChange.apply, TaskChange.apply_edit, with_activity, append_history, with_history, task_activity.
 destruct lifecycle; reflexivity.
Qed.

Theorem unsupported_reasoning_with_no_queued_input_is_idle : forall owner effort generations task policy,
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 Reasoning.allowed policy effort && ReasoningProtocol.valid_generations (reasoning_max_lease policy) generations = false ->
 task_queued task = [] -> task_activity (Reasoning.complete owner (Reasoning.Chosen effort generations) task) = Idle.
Proof.
 intros owner effort generations [contract profile settings lifecycle history queued lineage parent cursor consumed] policy Policy Rejected Queued.
 cbn in Policy, Queued. subst queued.
 rewrite !complete_reasoning_expression. cbn [task_current_profile]. rewrite Policy, Rejected.
 rewrite !failed_reasoning_expression; unfold Tasks.promote, Tasks.promote_changes, TaskChange.apply, TaskChange.apply_edit, with_activity, append_history, with_history, task_activity.
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
 rewrite !failed_reasoning_expression; unfold Tasks.promote, Tasks.promote_changes, TaskChange.apply, TaskChange.apply_edit, with_activity, append_history, with_history, task_activity.
 destruct lifecycle; destruct queued; discriminate.
Qed.
Theorem a_ready_evaluator_choice_has_a_supported_frozen_duration : forall owner effort generations task policy,
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 task_activity (Reasoning.complete owner (Reasoning.Chosen effort generations) task) = ReadyForModel ->
 (generations = 1%N \/ generations = 2%N \/ generations = 5%N \/ generations = 10%N) /\
 (generations <= reasoning_max_lease policy)%N.
Proof.
 intros owner effort generations task policy Policy Ready.
 rewrite !complete_reasoning_expression in Ready. rewrite Policy in Ready.
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

Theorem a_fixed_profile_bypasses_the_evaluator : forall id task value,
 find_task id value = Some task ->
 TicketedRequest.Scoped.can_infer task value = true ->
 profile_policy (task_current_profile task) = FixedReasoning ->
 Scheduler.ready_model id value = TicketedRequest.issue id
   (TicketedRequest.Infer task) value.
Proof.
 intros id task value Found InferAllowed Fixed. unfold Scheduler.ready_model.
 rewrite (ScopedRequestProofs.model_selection_uses_the_current_task id value task Found InferAllowed).
 reflexivity.
Qed.

Theorem an_adaptive_profile_without_a_lease_requests_its_evaluator : forall id task value policy,
 find_task id value = Some task ->
 TicketedRequest.Scoped.can_infer task value = true ->
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 History.history_lease id (task_history task) = History.NoLease ->
 decision_effects (Scheduler.ready_model id value) =
 [RequestReasoning id (world_next_ticket value) task].
Proof.
 intros id task value policy Found InferAllowed Policy Lease. unfold Scheduler.ready_model.
 rewrite (ScopedRequestProofs.model_selection_uses_the_current_task id value task Found InferAllowed).
 assert (Selected : ModelRequest.Plans.next id task = ModelRequest.Plans.Evaluate).
 { unfold ModelRequest.Plans.next; rewrite Policy, Lease; reflexivity. }
 pose proof (ModelRequestConstructionProofs.choosing_an_evaluator id task Selected) as Chosen.
 unfold ScopedRequestProofs.computed_model, TicketedRequest.issue, TicketedRequest.build.
 rewrite Chosen; reflexivity.
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
 rewrite (ScopedRequestProofs.model_selection_uses_the_current_task id value task Found InferAllowed).
 destruct (TicketedRequestProofs.fixed_inference_freezes_its_complete_context id task value model Fixed)
   as [request [Effects [Owner [Ticket [Model [History [Cursor Contract]]]]]]].
 exists request; repeat split; assumption.
Qed.

Theorem actual_model_generation_consumes_one_lease_step : forall owner model remaining task,
 exists prefix suffix,
 task_history (Reasoning.generation owner model remaining task) =
 prefix ++ [ReasoningRecord owner (profile_reasoning model) (N.pred remaining) true] ++ suffix /\
 (prefix = task_history task \/
  prefix = task_history task ++ [FailureMessage "The previous generation has no retained output after its configuration update; continuing from the committed request prefix."]) /\
 (suffix = [] \/ suffix = [ReasoningConfigurationMessage (profile_reasoning model)]).
Proof.
 intros owner model remaining task. unfold Reasoning.generation, TicketedRequest.generation, ReasoningPlan.generation.
 destruct (match profile_policy (task_current_profile task) with
 | AdaptivePolicy policy => match reasoning_transport_mode policy with
   | RequestEffort => false | ConfigurationUpdates =>
     match ReasoningPlan.last_configuration (task_history task) with None => true | Some previous => negb (String.eqb previous (profile_reasoning model)) end end
 | FixedReasoning => false end);
 destruct (ReasoningPlan.trailing_configuration (task_history task));
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed];
 cbn [append_history with_history task_history].
 - exists (history ++ [FailureMessage "The previous generation has no retained output after its configuration update; continuing from the committed request prefix."]),
     [ReasoningConfigurationMessage (profile_reasoning model)].
   split; [now rewrite app_assoc|split; [now right|now right]].
 - exists history, [ReasoningConfigurationMessage (profile_reasoning model)].
   split; [now rewrite app_assoc|split; [now left|now right]].
 - exists history, []. rewrite app_nil_r; split; [reflexivity|split; now left].
 - exists history, []. rewrite app_nil_r; split; [reflexivity|split; now left].
Qed.

Theorem context_requests_capture_the_current_history_revision : forall id task value phase operations,
 find_task id value = Some task ->
 TicketedRequest.Scoped.can_observe false task value = true -> task_lifecycle task = Running phase operations ->
 decision_effects (Reasoning.observe_context id value) =
 [ObserveContext id (world_next_ticket value) task] /\
 exists waiting,
 find_task id (decision_world (Reasoning.observe_context id value)) = Some waiting /\
 task_activity waiting = ObservingContext (world_next_ticket value) (List.length (task_history task)) /\
 task_history waiting = task_history task /\ task_contract waiting = task_contract task.
Proof.
 intros id task value phase operations Found ObserveAllowed RunningTask.
 unfold Reasoning.observe_context.
 rewrite (ScopedRequestProofs.observing_uses_the_current_task id value task false Found ObserveAllowed).
 split; [reflexivity|].
 eexists; split; [eapply find_put_task; exact Found|].
 unfold Reasoning.capture, with_activity. rewrite RunningTask. repeat split; reflexivity.
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
 Callbacks.context_completed id ticket observations diagnostic value = Reasoning.observe_context id value.
Proof.
 intros id ticket revision observations diagnostic value task phase operations Found Phase RunningTask Stale.
 rewrite context_completed_expression; rewrite Found, Phase, N.eqb_refl, Stale, RunningTask; reflexivity.
Qed.

Local Lemma context_diagnostic_retains_lifecycle : forall message task,
 task_lifecycle (Callbacks.record_context_diagnostic message task) = task_lifecycle task.
Proof. intros; rewrite !record_context_diagnostic_expression; destruct existsb; reflexivity. Qed.
Local Lemma context_diagnostics_retain_lifecycle : forall messages task,
 task_lifecycle (fold_left (fun task message => Callbacks.record_context_diagnostic message task) messages task) = task_lifecycle task.
Proof. induction messages; intros; cbn [fold_left]; [reflexivity|rewrite IHmessages; apply context_diagnostic_retains_lifecycle]. Qed.
Local Lemma actual_context_observations_retain_lifecycle : forall observations diagnostic task,
 task_lifecycle (snd (Callbacks.observed_context observations diagnostic task)) = task_lifecycle task.
Proof.
 intros [observations|] diagnostic task; rewrite !observed_context_expression.
 - destruct (ContextUpdates.observe_all observations (ContextUpdates.bindings (task_history task))) as [changes diagnostics].
   cbn [snd]. rewrite context_diagnostics_retain_lifecycle; reflexivity.
 - cbn [snd]; apply context_diagnostic_retains_lifecycle.
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
 - pose proof (actual_context_observations_retain_lifecycle observations diagnostic task) as Lifecycle.
   destruct (Callbacks.observed_context_changes observations diagnostic task) as [accepted changes] eqn:Observed.
   unfold Callbacks.observed_context in Lifecycle; rewrite Observed in Lifecycle; cbn [snd] in Lifecycle.
   unfold Callbacks.context_phase; rewrite FrozenTask, applying_change_lists.
   cbn [TaskChange.apply fold_left TaskChange.apply_edit]. split; [reflexivity|].
   eexists; split; [eapply find_put_task; exact Found|].
   unfold with_activity; rewrite Lifecycle, FrozenTask; reflexivity.
 - rewrite FrozenTask, context_ready_expression, Found.
   unfold Callbacks.context_phase; rewrite FrozenTask. split; [reflexivity|].
   eexists; split; [eapply find_put_task; exact Found|].
   cbn [TaskChange.apply fold_left TaskChange.apply_edit]. unfold with_activity; rewrite FrozenTask; reflexivity.
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
 - pose proof (actual_context_observations_retain_lifecycle observations diagnostic task) as Lifecycle.
   destruct (Callbacks.observed_context_changes observations diagnostic task) as [accepted changes] eqn:Observed.
   unfold Callbacks.observed_context in Lifecycle; rewrite Observed in Lifecycle; cbn [snd] in Lifecycle.
   unfold Callbacks.context_phase; rewrite StoppedTask, applying_change_lists.
   cbn [TaskChange.apply fold_left TaskChange.apply_edit]. split; [reflexivity|].
   eexists; split; [eapply find_put_task; exact Found|].
   unfold with_activity; rewrite Lifecycle, StoppedTask; reflexivity.
 - rewrite StoppedTask, context_ready_expression, Found.
   unfold Callbacks.context_phase; rewrite StoppedTask. split; [reflexivity|].
   eexists; split; [eapply find_put_task; exact Found|].
   cbn [TaskChange.apply fold_left TaskChange.apply_edit]. unfold with_activity; rewrite StoppedTask; reflexivity.
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

Theorem generation_preserves_the_frozen_task_contract : forall owner model remaining task,
 task_contract (Reasoning.generation owner model remaining task) = task_contract task.
Proof.
 intros. unfold Reasoning.generation, TicketedRequest.generation, ReasoningPlan.generation.
 destruct (match profile_policy (task_current_profile task) with
 | AdaptivePolicy policy => match reasoning_transport_mode policy with
   | RequestEffort => false | ConfigurationUpdates =>
     match ReasoningPlan.last_configuration (task_history task) with None => true | Some previous => negb (String.eqb previous (profile_reasoning model)) end end
 | FixedReasoning => false end);
 destruct (ReasoningPlan.trailing_configuration (task_history task)); destruct task; reflexivity.
Qed.

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
Proof. intros; unfold Dispatch.capture_request; now rewrite H, H0, N.eqb_refl. Qed.


Theorem captured_context_revisions_satisfy_the_actual_phase_contract : forall ticket task,
 WorldInvariant.phase_valid (Reasoning.capture ticket task) = true.
Proof.
 intros ticket [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle; unfold Reasoning.capture, WorldInvariant.phase_valid, WorldInvariant.calls_valid, WorldInvariant.phase_calls;
 cbn; try reflexivity; apply Nat.leb_refl.
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
