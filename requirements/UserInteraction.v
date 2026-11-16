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
Export HttpProofs(http_body_route_requires_authorization, http_body_route_requires_local_origin,
  http_public_command_rejects_sideband_observations).

(** Service configuration belongs to local administration. Both reading and
    changing it require the local credential and origin guard. The body
    route contracts above govern the change request. Only a selected body route
    can request the media type check, which grants the read of its body. *)
Export HttpProofs(http_service_configuration_read_requires_local_authorization).

Export UserInteractionProofs(public_browser_command_delivers_unwrapped_payload,
  public_command_admission_uses_shared_gate, public_reply_status_uses_command_feedback,
  accepted_command_feedback_retains_the_result, refused_command_feedback_retains_the_diagnostic,
  public_assessment_reports_the_command_decision).

(** A task's reading history distinguishes the accepted answer from its
    preceding commentary and tool activity. Commentary separates consecutive
    invocations. A delayed result belongs to its invocation at the original
    reading position, including when a model has already published an answer.
    The disclosure levels let readers follow live work and revisit its evidence
    without interrupting the answer. One invocation has its own disclosure;
    a group of invocations has a separate disclosure. Output is closed until
    explicitly requested. The assistant attribution introduces its process
    and answer once. A collapsed tool stack previews the latest invocation
    itself, so its icon and command remain distinguishable during motion.
    The browser measures motion, time and scrollports against the
    corresponding DOM and service observations. *)
From Selvedge.Interaction Require TaskHistoryProofs.
Export TaskHistoryProofs(grouping_preserves_visible_history_positions,
  an_execution_receipt_is_disclosed_only_if_distinct_from_the_result).
