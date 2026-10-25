From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec Conversation Capabilities ContextUpdates.
Import ListNotations.
Open Scope string_scope.

Module LeaseState.
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

End LeaseState.
Module Plans.
Import LeaseState.
Definition allowed (policy : adaptive_reasoning) (effort : string) := existsb (String.eqb effort) (reasoning_efforts policy).
Inductive plan := Fixed (model : profile) | Reuse (model : profile) (remaining : N) | Evaluate.
Definition next (owner : N) (task : task) :=
 let profile := task_current_profile task in
 match profile_policy profile with
 | FixedReasoning => Fixed profile
 | AdaptivePolicy policy =>
   match LeaseState.history_lease owner (task_history task) with
   | Lease effort remaining => if allowed policy effort && N.ltb 0 remaining then
      Reuse (with_reasoning effort profile) remaining else Evaluate
   | NoLease => Evaluate
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

End Plans.

(* Selection is justified at the task's canonical reasoning branch. Its evidence
   is erased; capturing later context does not select another model. *)
Definition chosen_plan (model : profile) (remaining : option N) :=
 match remaining with None => Plans.Fixed model | Some count => Plans.Reuse model count end.
Definition prepared (owner : N) (source : task) (model : profile) (remaining : option N) :=
 match remaining with None => source | Some count => Plans.generation owner model count source end.
Definition canonical (owner : N) (model : profile) (snapshot : task) : Prop :=
 exists source remaining,
   Plans.next owner source = chosen_plan model remaining /\
   snapshot = prepared owner source model remaining.
Record frozen (owner : N) := Frozen {
 model : profile;
 base : task;
 selected_by_reasoning : canonical owner model base
}.
Definition freeze (owner : N) (source : task) (model : profile) (remaining : option N)
 (selection : Plans.next owner source = chosen_plan model remaining) : frozen owner :=
 Frozen owner model (prepared owner source model remaining)
   (ex_intro _ source (ex_intro _ remaining (conj selection eq_refl))).
Definition choose (owner : N) (source : task) : option (frozen owner) :=
 match Plans.next owner source as selected return Plans.next owner source = selected -> option (frozen owner) with
 | Plans.Fixed model => fun evidence => Some (freeze owner source model None evidence)
 | Plans.Reuse model remaining => fun evidence => Some (freeze owner source model (Some remaining) evidence)
 | Plans.Evaluate => fun _ => None end eq_refl.
Arguments model {owner}.
Arguments base {owner}.
Arguments selected_by_reasoning {owner}.
Record t := Request {
 owner : N;
 selection : frozen owner;
 ticket : N;
 callable : list string;
 mode : output_mode;
 history : list message;
 scope : string;
 reserve : N
}.
(* The request phase has one representation. The task view contains only the
   committed execution context; it does not carry another independent phase. *)
Definition request_activity (value : t) := AskingModel (ticket value) (callable value) (mode value).
Definition context_task (value : t) : Domain.task :=
 Domain.with_history (history value)
   (with_model_cursor (List.length (task_history (base (selection value)))) (base (selection value))).
Definition pending_task (value : t) := with_activity (request_activity value) (context_task value).
Definition issue (owner : N) (choice : frozen owner) (ticket : N) (environment : environment) : t :=
 let source := base choice in
 Request owner choice ticket (Capabilities.callable source environment)
   (if ContextUpdates.interactive_available (ContextUpdates.bindings (task_history source))
    then InteractiveOutput else PlainOutput)
   (task_history source) "" 0.
Definition with_history (replacement : list message) (value : t) : t :=
 Request (owner value) (selection value) (ticket value) (callable value) (mode value) replacement (scope value) (reserve value).
Definition with_context (replacement_scope : string) (replacement_reserve : N) (value : t) : t :=
 Request (owner value) (selection value) (ticket value) (callable value) (mode value) (history value)
   replacement_scope replacement_reserve.
