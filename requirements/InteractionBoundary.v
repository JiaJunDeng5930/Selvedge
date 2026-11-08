(** * Entry-independent business interaction

    Users need the same business information and command semantics when they
    switch entry. Shared observations name business objects, their visible
    properties, choices, and consequences. The browser chooses pages, controls,
    and focus. The terminal chooses command-line input and textual output.

    A draft, a current world sequence, and a correlated service observation
    supply the inputs to a business decision. Browser layout and navigation
    supply no business facts. The production dependency check enforces this
    direction for every transitive import of an Interaction module.

    The observation, command and card-decision requirements bind the shared
    functions to the actual browser projections and authenticated HTTP
    dispatch. Here the browser reducer also retains the authoritative command
    receipt. A refusal is visible with the service's diagnostic, and an
    available command requires a matching admission for the current world. *)
From Stdlib Require Import List String NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Resource.
From Selvedge.Interaction Require Import Codec CommandAssessment.
From Selvedge.Interaction Require UserCommand.
From Selvedge.Interaction.Experience Require Model Observation ObservationProof.
From Selvedge.Browser.Session Require State Authoring Services Input InputCodecs.
From Selvedge.Browser.Session Require Import EditorContext.
Open Scope string_scope.


Theorem browser_ready_command_has_current_admission snapshot state owner revision command :
 Authoring.canonical_ready snapshot state owner revision command=true ->
 exists sequence ticket request observation,
  natural_field "sequence" snapshot=Some sequence /\
  List.find (CommandAssessment.owned_assessment owner)
    (Services.command_assessments (State.service_state state))=Some(Loaded ticket request observation) /\
  CommandAssessment.matches owner revision sequence command request=true /\
  CommandAssessment.observed_owner observation=owner /\
  CommandAssessment.observed_revision observation=revision /\
  CommandAssessment.observed_sequence observation=sequence /\
  CommandAssessment.observed_admission observation=CommandAssessment.Admitted.
Proof.
 unfold Authoring.canonical_ready.
 destruct (Observation.admission snapshot state owner revision command) eqn:Admission.
 - intros _. exact (ObservationProof.available_admission_has_current_authority
    snapshot state owner revision command Admission).
 - discriminate.
Qed.

Theorem browser_direct_refusal_displays_the_shared_diagnostic snapshot state command reply diagnostic :
 UserCommand.feedback_of reply=Some(UserCommand.Refused diagnostic) ->
 Authoring.complete snapshot command State.DirectSubmission (inr reply) state=
 Some(Authoring.alert_diagnostic state diagnostic).
Proof.
 intro Refused.
 unfold Authoring.complete, Authoring.completion_success, Authoring.completion_error,
   UserCommand.accepted, Codec.command_failure, UserCommand.refusal.
 now rewrite Refused.
Qed.

Theorem browser_admits_the_diagnostic_of_an_unsubmitted_command raw ticket reason reply diagnostic :
 string_field "type" raw=Some "completion_failed" ->
 natural_field "ticket" raw=Some ticket ->
 string_field "error" raw=Some reason ->
 field "body" raw=Some reply ->
 field "error" reply=Some diagnostic ->
 text "code" diagnostic="command_not_submitted" ->
 InputCodecs.decode_runtime raw=Some(Input.Completed ticket (inr reply)).
Proof.
 intros Kind Ticket Reason Body Error Code.
 unfold InputCodecs.decode_runtime. rewrite Kind.
 cbn [bind InputCodecs.service_receipts InputCodecs.speech_receipts existsb].
 rewrite Ticket, Reason, Body. cbn [bind]. rewrite Error.
 cbn [value_or]. now rewrite Code.
Qed.
