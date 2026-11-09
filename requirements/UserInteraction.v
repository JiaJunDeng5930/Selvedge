(** Browser and CLI requests enter the same command model. HTTP delivers the
    command payload from either entry after authorization and origin checks.
    The browser's request wrapper is transport data. Both entries use the same
    public admission rule, and assessment and submission interpret the
    authoritative worker reply through the same feedback.

    For timed invocation, a [launchd] job or a service activated by a [systemd]
    timer calls [host/cli.mjs] against the running service with its usual
    credentials. The external program supplies when to invoke the command.
    Selvedge enforces authorization and command admission and reports the
    command result through the existing path below. Durable acceptance is
    governed by the journal contract in [requirements/Host.v]. *)
From Selvedge.Adapters Require ApiProofs HttpProofs UserInteractionProofs.
Export ApiProofs(public_admitted_command_body_is_delivered).
Export HttpProofs(http_body_requires_authorization, http_body_requires_local_origin,
  http_public_command_rejects_sideband_observations).

(** Service configuration belongs to local administration. Both reading and
    changing it require the local credential and origin guard. The body
    authorization contracts above govern the change request. *)
Export HttpProofs(http_service_configuration_read_requires_local_authorization).

Export UserInteractionProofs(public_browser_command_delivers_unwrapped_payload,
  public_command_admission_uses_shared_gate, public_reply_status_uses_command_feedback,
  accepted_command_feedback_retains_the_result, refused_command_feedback_retains_the_diagnostic,
  public_assessment_reports_the_command_decision).
