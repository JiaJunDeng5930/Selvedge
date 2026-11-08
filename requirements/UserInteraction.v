(** Browser and CLI requests enter the same command model. HTTP delivers the
    command payload from either entry after authorization and origin checks.
    The browser's request wrapper is transport data. Both entries use the same
    public admission rule, and assessment and submission interpret the
    authoritative worker reply through the same feedback. *)
From Selvedge.Adapters Require ApiProofs HttpProofs UserInteractionProofs.
Export ApiProofs(public_admitted_command_body_is_delivered).
Export HttpProofs(http_body_requires_authorization, http_body_requires_local_origin,
  http_public_command_rejects_sideband_observations).
Export UserInteractionProofs(public_browser_command_delivers_unwrapped_payload,
  public_command_admission_uses_shared_gate, public_reply_status_uses_command_feedback,
  accepted_command_feedback_retains_the_result, refused_command_feedback_retains_the_diagnostic,
  public_assessment_reports_the_command_decision).
