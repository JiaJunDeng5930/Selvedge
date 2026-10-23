From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec State Conversation Tasks ReasoningView ReasoningProtocol Context ContextUpdates.
Import ListNotations.
Open Scope string_scope.

Definition capture (ticket : N) (task : task) :=
 with_activity (ObservingContext ticket (List.length (task_history task))) task.
Definition observe_context (id : N) (task : task) (value : world) :=
 let '(ticket, allocated) := allocate_ticket value in
 accept (JObject [("accepted",JBool true)])
  (put_task id (capture ticket task) allocated) [ObserveContext id ticket task].

Definition failed_result (error : bool) (value : json) :=
 error || match natural_field "exit_code" value with Some code => N.ltb 0 code | None => false end.
Inductive lease := NoLease | Lease (effort : string) (remaining : N).
Definition lease_step (owner : N) (previous : lease) (message : message) :=
 match message with
 | ReasoningRecord actual effort remaining _ => if N.eqb owner actual then Lease effort remaining else NoLease
 | UserMessage _ | SpeechTranscript _ _ _ UserSpeaker _ _ | ContextObservation _
 | FailureMessage _ | ContextReplacement _ => NoLease
 | FunctionOutput _ value error | OperationResult _ _ value error | ToolReceipt _ _ _ value error =>
   if failed_result error value then NoLease else previous
 | ModelContext _ value => if String.eqb (text_default "type" (provider_value value) "") "compaction" then NoLease else previous
 | _ => previous end.
Definition history_lease (owner : N) (history : list message) := fold_left (lease_step owner) history NoLease.
Definition allowed (policy : adaptive_reasoning) (effort : string) := existsb (String.eqb effort) (reasoning_efforts policy).
Inductive plan := Fixed (model : profile) | Reuse (model : profile) (remaining : N) | Evaluate.
Definition next (owner : N) (task : task) :=
 let profile := task_current_profile task in
 match profile_policy profile with
 | FixedReasoning => Fixed profile
 | AdaptivePolicy policy =>
   match history_lease owner (task_history task) with
   | Lease effort remaining => if allowed policy effort && N.ltb 0 remaining then
      Reuse (with_reasoning effort profile) remaining else Evaluate
   | NoLease => Evaluate
   end
 end.
Inductive outcome := Chosen (effort : string) (generations : N) | EvaluationFailed (reason : string).
Definition failed (reason : string) (task : task) :=
 Tasks.promote (with_activity Idle (append_history [FailureMessage ("Automatic reasoning: " ++ reason)] task)).
Definition complete (owner : N) (outcome : outcome) (task : task) :=
 match profile_policy (task_current_profile task) with
 | FixedReasoning => task
 | AdaptivePolicy policy =>
   match outcome with
   | Chosen effort generations =>
     (* DEFENSE: An external evaluator may return choices outside its frozen
        endpoint policy; that response must not start a model generation. *)
     if allowed policy effort && ReasoningProtocol.valid_generations (reasoning_max_lease policy) generations
     then Tasks.promote (with_activity ReadyForModel
       (append_history [ReasoningRecord owner effort generations false] task))
     else failed "the evaluator selected an unsupported effort or lease; no model request was sent" task
   | EvaluationFailed reason => failed reason task
   end
 end.
Definition last_configuration (history : list message) :=
 fold_left (fun previous entry => match entry with
 | ReasoningConfigurationMessage effort => Some effort | _ => previous end) history None.
Definition trailing_configuration (history : list message) :=
 fold_left (fun previous entry => match entry with
 | ReasoningConfigurationMessage _ => true
 | ReasoningRecord _ _ _ _ | AfterReceipt _ _ _ _
 | ApprovalReceipt _ _ _ _ _ | ToolReceipt _ _ _ _ _ => previous
 | _ => false end) history false.
Definition generation (owner : N) (model : profile) (remaining : N) (task : task) :=
 let effort := profile_reasoning model in
 let emit := match profile_policy (task_current_profile task) with
 | AdaptivePolicy policy => match reasoning_transport_mode policy with
   | RequestEffort => false | ConfigurationUpdates =>
     match last_configuration (task_history task) with None => true | Some previous => negb (String.eqb previous effort) end end
 | FixedReasoning => false end in
 let task := if emit && trailing_configuration (task_history task) then
  append_history [FailureMessage "The previous generation has no retained output after its configuration update; continuing from the committed request prefix."] task else task in
 let task := append_history [ReasoningRecord owner effort (N.pred remaining) true] task in
 if emit then append_history [ReasoningConfigurationMessage effort] task else task.
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
