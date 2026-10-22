From Stdlib Require Import List Bool NArith PeanoNat.
From Selvedge.Foundation Require Import JsonObjectsProofs.
From Selvedge.Kernel Require Import State WorldInvariant CommitAdmission.
Import ListNotations.

Theorem an_authorized_transition_has_state_and_effect_authority : forall durable source raw_source before candidate,
 CommitAdmission.transition_authorized durable source raw_source before candidate = true ->
 CommitAdmission.world_evolution source raw_source before (decision_world candidate) = true /\
 CommitAdmission.effect_tickets_fresh (world_next_ticket before)
   (world_next_ticket (decision_world candidate)) (decision_effects candidate) = true /\
 CommitAdmission.effects_authorized source raw_source before (decision_world candidate) (decision_effects candidate) = true /\
 CommitAdmission.effect_notifications_valid durable source before candidate = true.
Proof.
 intros durable source raw_source before candidate Authorized.
 unfold CommitAdmission.transition_authorized in Authorized.
 repeat rewrite andb_true_iff in Authorized.
 destruct Authorized as [[[Evolution Fresh] Effects] Notices].
 repeat split; assumption.
Qed.

Theorem an_authorized_candidate_is_preserved : forall durable source raw_source before candidate,
 CommitAdmission.transition_authorized durable source raw_source before candidate = true ->
 CommitAdmission.validate durable source raw_source before candidate = candidate.
Proof. intros; unfold CommitAdmission.validate; rewrite H; reflexivity. Qed.

Theorem an_unauthorized_candidate_is_rolled_back : forall durable source raw_source before candidate,
 CommitAdmission.transition_authorized durable source raw_source before candidate = false ->
 decision_world (CommitAdmission.validate durable source raw_source before candidate) = before /\
 decision_effects (CommitAdmission.validate durable source raw_source before candidate) = [].
Proof.
 intros durable source raw_source before candidate Unauthorized.
 unfold CommitAdmission.validate; rewrite Unauthorized; split; reflexivity.
Qed.

Theorem every_global_admission_preserves_or_rolls_back : forall durable source raw_source before candidate,
 (decision_world (CommitAdmission.validate durable source raw_source before candidate) = before /\
  decision_effects (CommitAdmission.validate durable source raw_source before candidate) = []) \/
 (CommitAdmission.transition_authorized durable source raw_source before candidate = true /\
  CommitAdmission.validate durable source raw_source before candidate = candidate).
Proof.
 intros durable source raw_source before candidate; unfold CommitAdmission.validate.
 destruct (CommitAdmission.transition_authorized durable source raw_source before candidate) eqn:Authorized.
 - right; split; reflexivity.
 - left; split; reflexivity.
Qed.

Theorem global_admission_preserves_world_validity : forall durable source raw_source before candidate,
 world_valid before = true ->
 world_valid (decision_world candidate) = true ->
 world_valid (decision_world (CommitAdmission.validate durable source raw_source before candidate)) = true.
Proof.
 intros durable source raw_source before candidate Before Candidate.
 unfold CommitAdmission.validate.
 destruct (CommitAdmission.transition_authorized durable source raw_source before candidate); assumption.
Qed.

Lemma an_exact_history_match_preserves_every_message : forall snapshot current,
 CommitAdmission.task_history_matches snapshot current = true ->
 List.length (Domain.task_history snapshot) = List.length (Domain.task_history current) /\
 JsonObjectsProofs.same_json_meaning
   (Json.JArray (ContextSelection.history_json 0 (Domain.task_history snapshot)))
   (Json.JArray (ContextSelection.history_json 0 (Domain.task_history current))).
Proof.
 intros snapshot current Matched.
 unfold CommitAdmission.task_history_matches, CommitAdmission.same_history in Matched.
 apply andb_true_iff in Matched; destruct Matched as [Length Prefix].
 apply Nat.eqb_eq in Length; split; [exact Length|].
 unfold ContextSelection.history_extends in Prefix.
 apply andb_true_iff in Prefix; destruct Prefix as [_ Retained].
 unfold ContextSelection.history_json in Retained; rewrite length_map in Retained.
 rewrite Length in Retained.
 rewrite firstn_all2 in Retained by now rewrite length_map.
 apply JsonObjectsProofs.equivalent_preserves_json_meaning; exact Retained.
Qed.

Definition inference_snapshot (request : effect) : option (N * Domain.task) :=
 match request with
 | ObserveContext owner _ snapshot | RequestModel owner _ _ snapshot _ _
 | RequestReasoning owner _ _ snapshot => Some (owner,snapshot)
 | _ => None
 end.
Definition inference_history_bound (after : world) (request : effect) : Prop :=
 match inference_snapshot request with
 | Some (owner,snapshot) => exists current,
   find_task owner after = Some current /\
   CommitAdmission.task_is_running current = true /\
   List.length (Domain.task_history snapshot) = List.length (Domain.task_history current) /\
   JsonObjectsProofs.same_json_meaning
     (Json.JArray (ContextSelection.history_json 0 (Domain.task_history snapshot)))
     (Json.JArray (ContextSelection.history_json 0 (Domain.task_history current)))
 | None => True
 end.

Lemma an_observation_has_exact_running_history : forall owner ticket snapshot after,
 CommitAdmission.observe_effect_valid owner ticket snapshot after = true ->
 exists current, find_task owner after = Some current /\
 CommitAdmission.task_is_running current = true /\
 CommitAdmission.task_history_matches snapshot current = true.
Proof.
 intros owner ticket snapshot after Authorized.
 unfold CommitAdmission.observe_effect_valid in Authorized.
 destruct (find_task owner after) as [current|] eqn:Found; [|discriminate].
 repeat rewrite andb_true_iff in Authorized.
 exists current; repeat split; tauto.
Qed.

Lemma a_model_request_has_exact_running_history : forall owner ticket model snapshot after,
 CommitAdmission.model_effect_valid owner ticket model snapshot after = true ->
 exists current, find_task owner after = Some current /\
 CommitAdmission.task_is_running current = true /\
 CommitAdmission.task_history_matches snapshot current = true.
Proof.
 intros owner ticket model snapshot after Authorized.
 unfold CommitAdmission.model_effect_valid in Authorized.
 destruct (find_task owner after) as [current|] eqn:Found; [|discriminate].
 repeat rewrite andb_true_iff in Authorized.
 exists current; repeat split; tauto.
Qed.

Lemma a_reasoning_request_has_exact_running_history : forall owner ticket model snapshot after,
 CommitAdmission.reasoning_effect_valid owner ticket model snapshot after = true ->
 exists current, find_task owner after = Some current /\
 CommitAdmission.task_is_running current = true /\
 CommitAdmission.task_history_matches snapshot current = true.
Proof.
 intros owner ticket model snapshot after Authorized.
 unfold CommitAdmission.reasoning_effect_valid in Authorized.
 destruct (find_task owner after) as [current|] eqn:Found; [|discriminate].
 repeat rewrite andb_true_iff in Authorized.
 exists current; repeat split; tauto.
Qed.

Theorem authorized_effects_bind_the_exact_inference_history :
 forall source raw_source before after request,
 CommitAdmission.effect_authorized source raw_source request before after = true ->
 inference_history_bound after request.
Proof.
 intros source raw_source before after request Authorized.
 destruct request; cbn [inference_history_bound inference_snapshot]; try exact I.
 all: match goal with
 | H : CommitAdmission.effect_authorized _ _ (ObserveContext _ _ _) _ _ = true |- _ =>
   apply an_observation_has_exact_running_history in H
 | H : CommitAdmission.effect_authorized _ _ (RequestModel _ _ _ _ _ _) _ _ = true |- _ =>
   apply a_model_request_has_exact_running_history in H
 | H : CommitAdmission.effect_authorized _ _ (RequestReasoning _ _ _ _) _ _ = true |- _ =>
   apply a_reasoning_request_has_exact_running_history in H
 end.
 all: destruct Authorized as [current [Found [Running History]]];
   exists current; repeat split; try assumption;
   apply an_exact_history_match_preserves_every_message in History; tauto.
Qed.

Theorem every_authorized_effect_has_its_inference_history_bound :
 forall source raw_source before after effects,
 CommitAdmission.effects_authorized source raw_source before after effects = true ->
 Forall (inference_history_bound after) effects.
Proof.
 intros source raw_source before after effects; induction effects as [|request rest IH]; intros Authorized.
 - constructor.
 - cbn [CommitAdmission.effects_authorized] in Authorized.
   apply andb_true_iff in Authorized; destruct Authorized as [Request Rest].
   constructor; [eapply authorized_effects_bind_the_exact_inference_history; exact Request|auto].
Qed.

Theorem an_authorized_request_cannot_start_inference_in_a_stopped_task :
 forall source raw_source before after request owner snapshot current phase operations,
 CommitAdmission.effect_authorized source raw_source request before after = true ->
 inference_snapshot request = Some (owner,snapshot) ->
 find_task owner after = Some current ->
 Domain.task_lifecycle current = Domain.Stopped phase operations -> False.
Proof.
 intros source raw_source before after request owner snapshot current phase operations
   Authorized Captured Found Stopped.
 pose proof (authorized_effects_bind_the_exact_inference_history
   source raw_source before after request Authorized) as Bound.
 unfold inference_history_bound in Bound; rewrite Captured in Bound.
 destruct Bound as [actual [Actual [Running History]]].
 rewrite Found in Actual; inversion Actual; subst actual.
 unfold CommitAdmission.task_is_running in Running; rewrite Stopped in Running; discriminate.
Qed.

Definition settlement_owner (request : effect) : option N := match request with
 | ExecuteTool owner _ _ _ _ _ _ | RequestApproval owner _ _ _ _
 | CheckTool owner _ _ _ _ | CheckResult owner _ _ _ _ _ _ => Some owner
 | _ => None
 end.

(* This compares the authority of the same accepted operation across Stop;
   no operation, call, result, reviewer or correlation ticket is changed. *)
Theorem stopping_retains_the_authority_of_accepted_work :
 forall source raw_source before request owner phase operations task running stopped,
 settlement_owner request = Some owner ->
 find_task owner running = Some (Domain.with_lifecycle (Domain.Running phase operations) task) ->
 find_task owner stopped = Some (Domain.with_lifecycle (Domain.Stopped phase operations) task) ->
 CommitAdmission.effect_authorized source raw_source request before running =
 CommitAdmission.effect_authorized source raw_source request before stopped.
Proof.
 intros source raw_source before request owner phase operations task running stopped
   Owned Running Stopped.
 destruct request; cbn [settlement_owner] in Owned; try discriminate;
   inversion Owned; subst;
   cbn [CommitAdmission.effect_authorized];
   unfold CommitAdmission.tool_effect_valid, CommitAdmission.approval_effect_valid,
     CommitAdmission.hook_effect_valid, CommitAdmission.after_effect_valid;
   rewrite Running, Stopped;
   destruct task; reflexivity.
Qed.
