From Stdlib Require Import List Bool NArith.
From Selvedge.Foundation Require Import Json OptionListProofs.
From Selvedge.Kernel Require Import Domain State TaskScope TaskScopeProofs RequestReceiver RequestReceiverProofs
 HookCallbacks HookRules TerminalSettlement.

Theorem a_selected_terminal_plan_consumes_its_observed_callback :
 forall before (accepted : plan before),
 interpret accepted = HookCallbacks.after_completed (owner (request accepted))
   (operation (request accepted)) (ticket (request accepted)) (outcome (request accepted)) before.
Proof.
 intros before accepted.
 pose proof (observed_update accepted) as Update.
 unfold resolved_update in Update.
 destruct (task_lifecycle (TaskScope.selected (target accepted))); try discriminate.
 destruct (RequestReceiver.pending_after (operation (request accepted)) (ticket (request accepted))
   (TaskScope.selected (target accepted))) as [[[[[original plugin] pending] previous] failed]|] eqn:Receiver; [|discriminate].
 destruct (final_action (HookRules.after_apply previous (outcome (request accepted))) pending); [|discriminate].
 injection Update as Update.
 pose proof (TaskScope.observed (target accepted)) as Found; rewrite (owns_request accepted) in Found.
 destruct (selecting_an_existing_task_retains_its_key _ _ _ Found)
   as [selected [Selected [Owner Current]]].
 unfold HookCallbacks.after_completed,RequestReceiver.deliver.
 erewrite RequestReceiverProofs.deliver_selected; [|exact Selected|rewrite Current; exact Receiver].
 unfold interpret,interpret_change,CommandResult.accept; cbn [CommandResult.change_world CommandResult.change_value CommandResult.change_effects].
 rewrite <- Update; unfold HookCallbacks.after_result_plan,Tasks.interpret_result.
 rewrite Owner,Current,(owns_request accepted); reflexivity.
Qed.

Theorem a_terminal_candidate_matches_the_callback_continuation : forall before (accepted : plan before),
 candidate accepted = DeferredCommit.continue (HookCallbacks.after_completed
   (owner (request accepted)) (operation (request accepted)) (ticket (request accepted)) (outcome (request accepted)) before).
Proof.
 intros; rewrite <- a_selected_terminal_plan_consumes_its_observed_callback; reflexivity.
Qed.

Lemma observed_resolution_tracks_its_eligibility : forall payload before current observed,
 (match resolve_observed payload before current observed with Some _ => true | None => false end) = eligible payload current.
Proof.
 intros; unfold resolve_observed; eapply observe_cases.
 - intros selected Observed; unfold eligible; now rewrite Observed.
 - intros Missing; unfold eligible; now rewrite Missing.
Qed.
Lemma terminal_resolution_tracks_the_real_eligibility : forall payload before,
 (match resolve_request payload before with Some _ => true | None => false end) =
 (match find_task (owner payload) before with Some current => eligible payload current | None => false end).
Proof.
 intros; unfold resolve_request; eapply observe_cases.
 - intros current Found; rewrite observed_resolution_tracks_its_eligibility; now rewrite Found.
 - intros Missing; now rewrite Missing.
Qed.
Lemma observed_resolution_retains_the_callback_payload : forall payload before current observed accepted,
 resolve_observed payload before current observed = Some accepted -> request accepted = payload.
Proof.
 intros payload before current observed accepted; unfold resolve_observed; eapply observe_cases.
 - intros selected Observed Equal; inversion Equal; reflexivity.
 - intros Missing Equal; discriminate.
Qed.
Lemma resolution_retains_the_callback_payload : forall payload before accepted,
 resolve_request payload before = Some accepted -> request accepted = payload.
Proof.
 intros payload before accepted; unfold resolve_request; eapply observe_cases.
 - intros current Found; apply observed_resolution_retains_the_callback_payload.
 - intros Missing Equal; discriminate.
Qed.
