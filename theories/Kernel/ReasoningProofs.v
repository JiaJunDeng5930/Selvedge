From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State Tasks Reasoning ReasoningProtocol Callbacks LifecycleProofs.
Import ListNotations.

Theorem nonzero_process_exit_invalidates_the_reasoning_lease :
 forall owner history identity result code,
 natural_field "exit_code"%string result = Some code -> (0 <? code)%N = true ->
 Reasoning.history_lease owner (history ++ [FunctionOutput identity result false]) = Reasoning.NoLease.
Proof.
 intros owner history identity result code Exit Failed.
 unfold Reasoning.history_lease. rewrite fold_left_app. cbn.
 unfold Reasoning.failed_result. rewrite Exit, Failed. reflexivity.
Qed.

Theorem failed_reasoning_with_no_queued_input_is_idle : forall owner reason task policy,
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 task_queued task = [] ->
 task_activity (Reasoning.complete owner (Reasoning.EvaluationFailed reason) task) = Idle.
Proof.
 intros owner reason [contract profile settings lifecycle history queued lineage parent cursor consumed] policy Policy Queued.
 cbn in Policy, Queued. subst queued.
 unfold Reasoning.complete. cbn [task_current_profile]. rewrite Policy.
 unfold Reasoning.failed, Tasks.promote, with_activity, append_history, with_history, task_activity.
 destruct lifecycle; reflexivity.
Qed.

Theorem unsupported_reasoning_with_no_queued_input_is_idle : forall owner effort generations task policy,
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 Reasoning.allowed policy effort && ReasoningProtocol.valid_generations (reasoning_max_lease policy) generations = false ->
 task_queued task = [] -> task_activity (Reasoning.complete owner (Reasoning.Chosen effort generations) task) = Idle.
Proof.
 intros owner effort generations [contract profile settings lifecycle history queued lineage parent cursor consumed] policy Policy Rejected Queued.
 cbn in Policy, Queued. subst queued.
 unfold Reasoning.complete. cbn [task_current_profile]. rewrite Policy, Rejected.
 unfold Reasoning.failed, Tasks.promote, with_activity, append_history, with_history, task_activity.
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
 unfold Callbacks.reasoning_completed. rewrite Found, Phase, N.eqb_refl, Changed.
 split; [reflexivity|]. eexists; split; [eapply find_put_task; exact Found|].
 destruct task as [contract profile settings lifecycle history queued lineage parent cursor consumed].
 destruct lifecycle; cbn in Phase; try discriminate; split; reflexivity.
Qed.

Lemma failed_evaluation_is_never_ready_for_a_model : forall reason task,
 task_activity (Reasoning.failed reason task) <> ReadyForModel.
Proof.
 intros reason [contract profile settings lifecycle history queued lineage parent cursor consumed].
 unfold Reasoning.failed, Tasks.promote, with_activity, append_history, with_history, task_activity.
 destruct lifecycle; destruct queued; discriminate.
Qed.
Theorem a_ready_evaluator_choice_has_a_supported_frozen_duration : forall owner effort generations task policy,
 profile_policy (task_current_profile task) = AdaptivePolicy policy ->
 task_activity (Reasoning.complete owner (Reasoning.Chosen effort generations) task) = ReadyForModel ->
 (generations = 1%N \/ generations = 2%N \/ generations = 5%N \/ generations = 10%N) /\
 (generations <= reasoning_max_lease policy)%N.
Proof.
 intros owner effort generations task policy Policy Ready.
 unfold Reasoning.complete in Ready. rewrite Policy in Ready.
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
