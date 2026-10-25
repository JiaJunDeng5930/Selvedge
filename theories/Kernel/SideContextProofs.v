From Stdlib Require Import List Bool NArith.
From Selvedge.Kernel Require Import Domain State Dispatch Context ContextTypes ContextProtocol SideContext.
Import ListNotations.

Theorem side_parent_native_state_observer_roundtrips : forall parent_id,
 ContextProtocol.parse_observer
   (Context.observer_json
     (ContextTypes.definition_observer (SideContext.parent_definition parent_id))) =
 Some (ContextTypes.definition_observer (SideContext.parent_definition parent_id)).
Proof. reflexivity. Qed.

Local Lemma capture_requests_member_has_capture_origin : forall effects value committed captured target,
 Dispatch.capture_requests effects value = (committed,captured) ->
 In target captured ->
 exists source before after,
   In source effects /\ Dispatch.capture_request source before = (after,target).
Proof.
 induction effects as [|request rest IH]; intros value committed captured target Captured Member.
 - simpl in Captured; inversion Captured; subst; contradiction.
 - cbn [Dispatch.capture_requests] in Captured.
   destruct (Dispatch.capture_request request value) as [middle dispatched] eqn:Head.
   destruct (Dispatch.capture_requests rest middle) as [final remaining] eqn:Tail.
   inversion Captured; subst committed captured.
   simpl in Member.
   destruct Member as [Same|InRest].
   + subst target.
     exists request, value, middle.
     split; [simpl; auto|exact Head].
   + destruct (IH middle final remaining target Tail InRest)
       as [source [before [after [InSource Step]]]].
     exists source, before, after.
     split; [simpl; right; exact InSource|exact Step].
Qed.

Theorem prepared_request_has_capture_origin : forall value effects committed prepared target,
 Dispatch.prepare value effects = (committed,prepared) ->
 In target prepared ->
 exists source before after,
   In source effects /\ Dispatch.capture_request source before = (after,target).
Proof.
 intros value effects committed prepared target Prepared Member.
 unfold Dispatch.prepare in Prepared.
 destruct (Dispatch.capture_requests effects value) as [captured_world captured_effects] eqn:Capture.
 inversion Prepared; subst committed prepared.
 apply filter_In in Member as [Member _].
 eapply capture_requests_member_has_capture_origin; eauto.
Qed.

Theorem matching_side_model_capture_uses_full_history : forall value id ticket model original scope reserve current callable mode,
 Dispatch.side_task id value = Some current ->
 task_activity current = AskingModel ticket callable mode ->
 Dispatch.capture_request (RequestModel id ticket model original scope reserve) value =
 (put_task id (with_model_cursor (List.length (task_history current)) current) value,
  RequestModel id ticket model (with_history (task_history current) original) scope reserve).
Proof.
 intros; unfold Dispatch.capture_request; now rewrite H, H0, N.eqb_refl.
Qed.

Theorem matching_side_reasoning_capture_uses_full_history : forall value id ticket model original current source_length,
 Dispatch.side_task id value = Some current ->
 task_activity current = EvaluatingReasoning ticket source_length ->
 Dispatch.capture_request (RequestReasoning id ticket model original) value =
 (put_task id (with_activity (EvaluatingReasoning ticket (List.length (task_history current))) current) value,
  RequestReasoning id ticket model (with_history (task_history current) original)).
Proof.
 intros; unfold Dispatch.capture_request; now rewrite H, H0, N.eqb_refl.
Qed.

Theorem nonmatching_side_model_capture_preserves_original_history : forall value id ticket model original scope reserve current,
 find_task id value = Some current ->
 (task_side_parent current = None \/
   exists parent, task_side_parent current = Some parent /\
     forall callable mode, task_activity current <> AskingModel ticket callable mode) ->
 Dispatch.capture_request (RequestModel id ticket model original scope reserve) value =
 (value,RequestModel id ticket model original scope reserve).
Proof.
 intros value id ticket model original scope reserve current Found Mismatch.
 unfold Dispatch.capture_request, Dispatch.side_task.
 rewrite Found.
 destruct Mismatch as [NoParent|[parent [Parent WrongPhase]]].
 - rewrite NoParent; reflexivity.
 - rewrite Parent.
   destruct (task_activity current) as
     [| | | contextTicket contextLength | modelTicket callable mode
      | reasoningTicket reasoningLength | pendingCalls
      | invocation pendingCalls' calls | hookTicket plugin invocation' remaining calls']
     eqn:Activity; try reflexivity.
   destruct (N.eqb modelTicket ticket) eqn:TicketMatches; [|reflexivity].
   apply N.eqb_eq in TicketMatches.
   subst modelTicket.
   specialize (WrongPhase callable mode).
   exfalso; apply WrongPhase; reflexivity.
Qed.

Theorem nonmatching_side_reasoning_capture_preserves_original_history : forall value id ticket model original current,
 find_task id value = Some current ->
 (task_side_parent current = None \/
   exists parent, task_side_parent current = Some parent /\
     forall source_length, task_activity current <> EvaluatingReasoning ticket source_length) ->
 Dispatch.capture_request (RequestReasoning id ticket model original) value =
 (value,RequestReasoning id ticket model original).
Proof.
 intros value id ticket model original current Found Mismatch.
 unfold Dispatch.capture_request, Dispatch.side_task.
 rewrite Found.
 destruct Mismatch as [NoParent|[parent [Parent WrongPhase]]].
 - rewrite NoParent; reflexivity.
 - rewrite Parent.
   destruct (task_activity current) as
     [| | | contextTicket contextLength | modelTicket callable mode
      | reasoningTicket reasoningLength | pendingCalls
      | invocation pendingCalls' calls | hookTicket plugin invocation' remaining calls']
     eqn:Activity; try reflexivity.
   destruct (N.eqb reasoningTicket ticket) eqn:TicketMatches; [|reflexivity].
   apply N.eqb_eq in TicketMatches.
   subst reasoningTicket.
   specialize (WrongPhase reasoningLength).
   exfalso; apply WrongPhase; reflexivity.
Qed.
