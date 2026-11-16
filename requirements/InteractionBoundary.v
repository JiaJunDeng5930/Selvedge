(** * Entry-independent business interaction

    Users need the same business information and command semantics when they
    switch entry. Shared observations name business objects, their visible
    properties, choices, and consequences. The browser chooses pages, controls,
    and focus. The terminal chooses command-line input and textual output.

    Card save previews depend on their proposal and the authoritative facts
    used to assess it. A commit that only advances the journal cursor cannot
    invalidate a preview. The cursor orders publication while a reply runs
    ahead of the browser's snapshot. Browser layout and navigation supply no
    business facts. The production dependency check enforces this direction
    for every transitive import of an Interaction module.

    The observation, command and card-decision requirements bind the shared
    functions to the actual browser projections and authenticated HTTP
    dispatch. Here the browser reducer also retains the authoritative command
    receipt. A refusal is visible with the service's diagnostic. An explicit
    submission reaches the service with the command captured by the user. *)
From Stdlib Require Import List String NArith.
From Selvedge.Foundation Require Import Json.
From Selvedge.Programming Require Import Resource.
From Selvedge.Interaction Require Import Codec CommandAssessment.
From Selvedge.Interaction Require UserCommand.
From Selvedge.Interaction.Experience Require Model Observation ObservationProof Publication.
From Selvedge.Browser.Session Require State Authoring Services Input InputCodecs.
From Selvedge.Browser.Session Require Import EditorContext.
Open Scope string_scope.

Export Publication(card_save_facts_ignore_journal_cursor).
Export CommandAssessment(current_observation_retains_action_and_facts,
  a_current_card_observation_needs_no_repeat).

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
