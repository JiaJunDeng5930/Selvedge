(** * Task execution and correlated operations

    A Task is persistent work with an inspectable conversation and a particular
    execution authority. Continuing that work must preserve its creation and
    ancestry; changing its current execution settings is a separate, explicit
    operation. *)

From Selvedge.Programming Require TaskChangeProofs.
From Selvedge.Kernel Require HistoryProofs WorkspaceProofs.
Export TaskChangeProofs(append_only_changes_retain_history,
  field_changes_keep_the_immutable_task_identity,
  field_changes_keep_execution_configuration,
  a_field_plan_preserves_every_other_task).
Export HistoryProofs(an_after_hook_retains_the_original_execution_receipt,
  native_results_append_their_completed_observation).
Export WorkspaceProofs(updating_a_project_preserves_all_existing_tasks).

(** [append_only_changes_retain_history],
    [field_changes_keep_the_immutable_task_identity] and
    [field_changes_keep_execution_configuration] quantify over every edit in
    the actual [TaskChange] language. Its writable part contains execution
    progress and queued input; its history operation appends. An extension of
    that language therefore inherits these facts instead of repeating a proof
    for each command. [TaskChange.configure] is the distinct operation for
    admitted execution settings.

    A fork continues recorded context and captures its own overrides. It must
    not reread mutable defaults as if they were the parent's original context,
    or compare an immutable birth to a parent's subsequently edited settings.
    A new root deliberately captures current defaults and external guidance.
    Project preferences, creation provenance and a Task's current settings
    consequently have different owners and lifetimes.

    Tool execution evidence also has a lifetime independent of its displayed
    result. A result hook may redact or reject output after execution has
    occurred. [an_after_hook_retains_the_original_execution_receipt] constrains
    that distinction. [OperationEvent] constructs the receipt and continuation
    from one observation; a caller does not supply those outcomes independently.
    Native operations directly construct their completed result processing,
    without inventing an external execution callback. *)

From Selvedge.Kernel Require EntryBehaviorProofs ForkConstructionProofs
  ForkCommitProofs NativeForkPacketProofs PacketSettlementProofs.
Export EntryBehaviorProofs(
  every_resolved_exported_creation_returns_and_installs_its_fresh_reference).
Export ForkConstructionProofs(constructed_children_have_the_requested_count,
  constructed_children_have_the_parent_lineage).
Export ForkCommitProofs(a_fork_with_an_admitted_output_budget_is_delivered).
Export NativeForkPacketProofs(a_selected_native_fork_commits_within_its_delivery_budget).
Export PacketSettlementProofs(every_owned_terminal_callback_commits_at_the_public_packet).

(** ** Accepted work has a positive result

    Rejecting every operation would preserve many safety properties. The
    exported creation theorem instead derives the successful reply, installed
    fresh Task and retained existing Tasks from the actual resolution and
    transport premises. Its quantified world may contain unrelated active
    Tasks and feature requests.

    Creation, manual fork and owned final settlement do not require all
    background work to succeed atomically. Their business change is delivered
    with [ContinueScheduling]; the journal commits it before that continuation
    can issue physical work. The manual-fork contract reaches [ForkCommit.packet]
    with the admitted candidate and output budget. The native-fork contract
    reaches [Packet.packet] under the actual invocation selection and delivery
    budget. The terminal-settlement contract also reaches [Packet.packet], including
    the matching final after-hook callback of an archived Task. Settlement
    does not restore ordinary execution authority to that Task.

    Deferral must preserve event order: an earlier runnable action cannot be
    skipped, and newly accepted assistant output reaches Task-graph routing
    before subsequent scheduling yields. The actual input and complete output
    budgets remain delivery premises. *)

From Selvedge.Programming Require DecisionCompositionProofs.
From Selvedge.Kernel Require NotificationsProofs.
Export DecisionCompositionProofs(transformation_retains_reply,
  maintenance_retains_reply_and_effects).
Export NotificationsProofs(notification_envelopes_preserve_all_business_effects,
  oversized_notification_batch_leaves_the_complete_base_envelope).

(** ** Composition cannot rewrite another operation's answer

    [DecisionComposition.transformation] reads the initiating reply but cannot
    return another reply. Its narrower maintenance language can append effects
    but cannot replace earlier emissions. [transformation_retains_reply] and
    [maintenance_retains_reply_and_effects] follow from those actual interfaces.
    Scheduling and final delivery may still withdraw cancelled or unsendable
    requests; they therefore use the broader transformation interface.

    Optional plugin notifications are derived from the admitted final decision.
    Their size limit cannot discard the business reply or its effects:
    [notification_envelopes_preserve_all_business_effects] and
    [oversized_notification_batch_leaves_the_complete_base_envelope] constrain
    the encoder used by the packet. Notifications observe an operation; they
    are not a substitute for its reliable committed continuation. *)

From Selvedge.Kernel Require CommandDeclarationsProofs CommandOriginProofs.
From Selvedge.Programming Require FeatureRequestProofs.
From Selvedge.Programming Require CompletionProofs.
Export CommandDeclarationsProofs(malformed_commands_are_not_durable).
Export CommandOriginProofs(task_excluded_commands_are_read_only_rejections_at_every_handler_entry).
Export FeatureRequestProofs(every_feature_request_has_its_installed_receiver,
  feature_requests_preserve_execution_frame).
Export CompletionProofs(consumed_once, wrong_ticket_is_ignored,
  receipt_rejects_repeated_completion).

(** ** Admission and ownership travel with the operation

    Public command vocabulary remains constructible and inspectable. Its
    declaration supplies the schema, admitted payload and complete handler
    record. Internal typed values do not authenticate arbitrary JSON:
    [malformed_commands_are_not_durable] concerns the actual packet decoder,
    while [task_excluded_commands_are_read_only_rejections_at_every_handler_entry]
    concerns the caller authority used by the handlers.

    An admitted local fact is not authority over an unrelated world or source.
    [TaskScope.task_reference], planned births and
    [TicketedRequest.Scoped.feature_plan] retain their actual source context.
    The latter allocates one [RequestEnvelope], installs it through its located
    receiver and emits that same value. The universal
    [every_feature_request_has_its_installed_receiver] and
    [feature_requests_preserve_execution_frame] are inherited by compatible
    feature channels. A new channel still owns its project, revision, resource
    and capacity prerequisites; it does not reproduce generic receiver proofs.

    Completion reads the same receiver and recognizes its pending constructor.
    Its terminal constructor is outside that pending case. [consumed_once],
    [wrong_ticket_is_ignored] and [receipt_rejects_repeated_completion] establish
    correlation and retirement without a case for every feature. Related row
    assignments consume the actual receipt and write the terminal phase last.
    Owner-only protocols explicitly use [Completion.Owner]; this does not
    distinguish attempts after a later explicit retry.

    Field-name uniqueness, declaration-indexed callback coordinates and input
    grammar ownership are already enforced by [ModelDeclarations],
    [CallbackDeclarations], [SchemaProjection] and [InputRoute]. Physical dispatch
    still has to preserve the committed identity and report the actual outcome. *)

(** ** Lifecycle controls retain their distinct purposes

    Freeze suspends dispatch while preserving accepted results and their
    inference demand for unfreeze. Stop allows accepted calls to settle without
    requesting another model turn. Interrupt revokes current execution, records
    uncertain outcomes and permits later input to resume. Archive ends ordinary
    input. Steering replaces current inference work while retaining independent
    operations and queued follow-ups. An idle inference phase therefore does
    not imply an empty operation list.

    The existing control and input definitions give these operations their
    meaning. Their changes use the same frame-preserving Task construction. *)
From Selvedge.Kernel Require Tasks SchedulerLifecycleProofs CallbacksProofs
  TasksProofs NativeAuthorityProofs.
Export Selvedge.Kernel.Tasks(control_transition, input_changes, input_effects).
Export SchedulerLifecycleProofs(frozen_tasks_without_ready_results_do_not_take_scheduler_steps,
  stopped_inference_requests_settle_without_effects,
  stopped_tasks_can_finish_an_already_accepted_call).
Export CallbacksProofs(an_owned_tool_completion_while_frozen_keeps_the_unfreeze_demand).
Export TasksProofs(stopped_idle_receive_reactivates,
  archived_send_rejects_without_changing_world).
Export NativeAuthorityProofs(announced_operations_allow_an_independent_model_turn).

(** ** Approval concerns one captured operation

    Full Access, Ask for Approval and Approval for Me determine how an operation
    obtains the authority needed for its requested execution. Approval grants
    one captured operation; it does not change the Task's persistent settings or
    authorize subsequent commands. A pending operation retains its reviewer and
    ticket, so a later configuration change cannot choose who approved it.
    Denial follows the same frozen result-hook chain as an execution result.

    The authority constructor and granted-operation interpreter bind the
    decision to that operation. The TaskChange configuration law retains the
    persistent settings; the shared independent-request language gives an
    automatic reviewer no tool authority. *)
From Selvedge.Programming Require TicketedRequest OperationEvent.
From Selvedge.Kernel Require Scheduler ApprovalEvidenceProofs.
Export TicketedRequest.Scoped(external_authority_for).
Export OperationEvent(plan).
Export Scheduler(granted_operation).
Export NativeAuthorityProofs(actual_approval_uses_the_frozen_reviewer).
Export ApprovalEvidenceProofs(pending_approval_selection_retains_the_frozen_actor,
  human_approval_command_records_its_actual_reviewer,
  an_approval_denial_runs_the_frozen_result_chain).
