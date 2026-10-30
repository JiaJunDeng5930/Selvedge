From Stdlib Require Import String List Bool NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Kernel Require Import Numbers Domain Codec Conversation Capabilities ContextUpdates.
Import ListNotations.
Open Scope string_scope.
Open Scope list_scope.

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
Definition generation_messages (owner : N) (model : profile) (remaining : N) (task : task) :=
 let effort := profile_reasoning model in
 let emit := match profile_policy (task_current_profile task) with
 | AdaptivePolicy policy => match reasoning_transport_mode policy with
   | RequestEffort => false | ConfigurationUpdates =>
     match last_configuration (task_history task) with None => true | Some previous => negb (String.eqb previous effort) end end
 | FixedReasoning => false end in
 (if emit && trailing_configuration (task_history task) then
   [FailureMessage "The previous generation has no retained output after its configuration update; continuing from the committed request prefix."] else []) ++
 [ReasoningRecord owner effort (N.pred remaining) true] ++
 (if emit then [ReasoningConfigurationMessage effort] else []).
Definition generation owner model remaining source :=
 append_history (generation_messages owner model remaining source) source.

End Plans.

(* Selection is justified at the task's canonical reasoning branch. Its evidence
   is erased; capturing later context does not select another model. *)
Definition chosen_plan (model : profile) (remaining : option N) :=
 match remaining with None => Plans.Fixed model | Some count => Plans.Reuse model count end.
Definition prepared (owner : N) (source : task) (model : profile) (remaining : option N) :=
 match remaining with None => source | Some count => Plans.generation owner model count source end.
(** A selection is indexed by the actual task that was read. Its prepared
    history is derived from that source and its reasoning lease; there is no
    independently supplied snapshot or existential alternate source. *)
Record frozen (owner : N) (source : task) := Frozen {
 model : profile;
 remaining : option N;
 selected_by_reasoning : Plans.next owner source = chosen_plan model remaining
}.
Definition freeze (owner : N) (source : task) (model : profile) (remaining : option N)
 (selection : Plans.next owner source = chosen_plan model remaining) : frozen owner source :=
 Frozen owner source model remaining selection.
Definition choose (owner : N) (source : task) : option (frozen owner source) :=
 match Plans.next owner source as selected return Plans.next owner source = selected -> option (frozen owner source) with
 | Plans.Fixed model => fun evidence => Some (freeze owner source model None evidence)
 | Plans.Reuse model remaining => fun evidence => Some (freeze owner source model (Some remaining) evidence)
 | Plans.Evaluate => fun _ => None end eq_refl.
Arguments model {owner source}.
Arguments remaining {owner source}.
Arguments selected_by_reasoning {owner source}.
Definition base {owner source} (choice : frozen owner source) :=
 prepared owner source (model choice) (remaining choice).
Definition receipts {owner source} (choice : frozen owner source) :=
 match remaining choice with
 | None => None
 | Some count => Some (Plans.generation_messages owner (model choice) count source) end.

Record t := Request {
 owner : N;
 origin : task;
 selection : frozen owner origin;
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
Definition issue (owner : N) {origin : task} (choice : frozen owner origin) (ticket : N) (environment : environment) : t :=
 let source := base choice in
 Request owner origin choice ticket (Capabilities.callable source environment)
   (if ContextUpdates.interactive_available (ContextUpdates.bindings (task_history source))
    then InteractiveOutput else PlainOutput)
   (task_history source) "" 0.
Definition with_history (replacement : list message) (value : t) : t :=
 Request (owner value) (origin value) (selection value) (ticket value) (callable value) (mode value) replacement (scope value) (reserve value).
Definition with_context (replacement_scope : string) (replacement_reserve : N) (value : t) : t :=
 Request (owner value) (origin value) (selection value) (ticket value) (callable value) (mode value) (history value)
   replacement_scope replacement_reserve.
