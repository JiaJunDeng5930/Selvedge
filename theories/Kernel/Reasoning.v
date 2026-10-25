From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State TaskChange Conversation Tasks History ReasoningView ReasoningProtocol Context ContextUpdates ReasoningPlan TicketedRequest.
Import ListNotations.
Open Scope string_scope.

Definition capture (ticket : N) (task : task) :=
 with_activity (ObservingContext ticket (List.length (task_history task))) task.
Definition observe_context (id : N) (value : world) :=
 TicketedRequest.Scoped.run (TicketedRequest.Scoped.observe id false value).
Definition observe_scheduled_context (id : N) (value : world) :=
 TicketedRequest.Scoped.run (TicketedRequest.Scoped.observe id true value).


Definition allowed := ReasoningPlan.allowed.
Definition plan := ReasoningPlan.plan.
Definition Fixed := ReasoningPlan.Fixed.
Definition Reuse := ReasoningPlan.Reuse.
Definition Evaluate := ReasoningPlan.Evaluate.
Definition next := ReasoningPlan.next.
Inductive outcome := Chosen (effort : string) (generations : N) | EvaluationFailed (reason : string).
Definition failed_changes (reason : string) (task : task) :=
 let messages := [FailureMessage ("Automatic reasoning: " ++ reason)] in
 TaskChange.AppendHistory messages :: TaskChange.ChangePhase Idle ::
 Tasks.promote_changes (with_activity Idle (append_history messages task)).
Definition failed (reason : string) (task : task) :=
 TaskChange.apply (failed_changes reason task) task.
Definition complete_changes (owner : N) (outcome : outcome) (task : task) :=
 match profile_policy (task_current_profile task) with
 | FixedReasoning => []
 | AdaptivePolicy policy =>
   match outcome with
   | Chosen effort generations =>
     (* DEFENSE: An external evaluator may return choices outside its frozen
        endpoint policy; that response must not start a model generation. *)
     if allowed policy effort && ReasoningProtocol.valid_generations (reasoning_max_lease policy) generations
     then let messages := [ReasoningRecord owner effort generations false] in
       TaskChange.AppendHistory messages :: TaskChange.ChangePhase ReadyForModel ::
       Tasks.promote_changes (with_activity ReadyForModel (append_history messages task))
     else failed_changes "the evaluator selected an unsupported effort or lease; no model request was sent" task
   | EvaluationFailed reason => failed_changes reason task
   end
 end.
Definition complete (owner : N) (outcome : outcome) (task : task) :=
 TaskChange.apply (complete_changes owner outcome task) task.
Definition last_configuration := TicketedRequest.last_configuration.
Definition trailing_configuration := TicketedRequest.trailing_configuration.
Definition generation := TicketedRequest.generation.
Definition sampling (model : profile) (requested : profile) :=
 let effective := profile_reasoning model in
 JObject [("effective_effort",JString effective);
  ("request_effort",JString (match profile_policy requested with
  | AdaptivePolicy policy => match reasoning_transport_mode policy with ConfigurationUpdates => reasoning_baseline policy | RequestEffort => effective end
  | FixedReasoning => effective end))].
Definition evaluator_history (_ : N) (task : task) := ReasoningView.history (task_history task).

(* Evaluators see the same committed project snapshot as the requested turn.
   Looking up a mutable Project here would change an already captured request. *)
Definition evaluator_project_context (task : task) :=
 match workspace_primary (settings_workspace (task_current_settings task)) with
 | None => JNull
 | Some root => match ContextUpdates.find_snapshot
     (ContextKey Context.project_guidance [("workspace",root)])
     (ContextUpdates.bindings (task_history task)) with
   | Some snapshot => Context.snapshot_json snapshot | None => JNull end
 end.
