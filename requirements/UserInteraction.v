(** An authenticated user can inspect the current business information and
    candidate choices from either entry. The terminal asks the shared
    interaction model for those observations. It may assess a proposed
    command without submitting it. Assessment and submission retain the
    authoritative decision and its diagnostic across the entries. *)
From Selvedge.Adapters Require HttpProofs UserInteractionProofs.
Export HttpProofs(http_body_requires_authorization, http_body_requires_local_origin).
Export UserInteractionProofs(public_interaction_delivers_authenticated_request,
  public_interaction_shares_business_observations, public_interaction_shares_object_choices,
  public_interaction_shares_card_choices,
  public_reply_status_uses_command_feedback, accepted_command_feedback_retains_the_result,
  refused_command_feedback_retains_the_diagnostic, public_assessment_reports_the_command_decision).
