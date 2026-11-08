(** * Task execution and correlated operations

    A Task is persistent work with an inspectable conversation and a particular
    execution authority. Continuing that work must preserve its creation and
    ancestry; changing its current execution settings is a separate, explicit
    operation. *)

From Selvedge.Programming Require TaskChangeProofs.
From Selvedge.Kernel Require HistoryProofs WorkspaceProofs ExecutionSettingsProofs.
Export TaskChangeProofs(append_only_changes_retain_history,
  field_changes_keep_the_immutable_task_identity,
  field_changes_keep_execution_configuration,
  a_field_plan_preserves_every_other_task).
Export HistoryProofs(an_after_hook_retains_the_original_execution_receipt,
  native_results_append_their_completed_observation).
Export WorkspaceProofs(updating_a_project_preserves_all_existing_tasks).
Export ExecutionSettingsProofs(admitted_execution_settings_take_effect,
  default_effort_restores_frozen_configuration).

(** [append_only_changes_retain_history],
    [field_changes_keep_the_immutable_task_identity] and
    [field_changes_keep_execution_configuration] quantify over every edit in
    the actual [TaskChange] language. Its writable part contains execution
    progress and queued input; its history operation appends. An extension of
    that language therefore inherits these facts instead of repeating a proof
    for each command. [TaskChange.configure] is the distinct operation for
    admitted execution settings. An unarchived Task with no active or queued
    work may change its current profile, reasoning, sandbox and approval policy.
    [admitted_execution_settings_take_effect] requires that admitted choice to
    succeed and become the current configuration, regardless of any retained
    reasoning lease. Selecting default reasoning restores the captured profile
    default while preserving the creation contract.
    Approval selection uses the resolved model. An unknown model therefore
    refuses configuration directly; consulting the current model only to prefer
    a different refusal adds no configuration behavior.

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
    without inventing an external execution callback.
    Hook receipts retain the admitted outcome type. Execution and notification
    authorization consume that same outcome; JSON encoding belongs to the
    history output boundary. Encoding and reparsing an internal outcome would
    introduce a failure case that the accepted callback cannot produce. *)

From Selvedge.Kernel Require EntryBehaviorProofs ForkConstructionProofs TasksProofs
  ForkCommitProofs NativeForkPacketProofs PacketSettlementProofs.
Export EntryBehaviorProofs(
  every_resolved_exported_creation_returns_and_installs_its_fresh_reference).
Export ForkConstructionProofs(constructed_children_have_the_requested_count,
  constructed_children_have_the_parent_lineage).
Export TasksProofs(actual_fork_rejects_observed_ancestor_capacity).
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
    can issue physical work. The manual-fork contract finalizes the actual [ForkCommit.select]
    with the admitted candidate and output budget. The native-fork contract
    reaches [Packet.packet] under the actual invocation selection and delivery
    budget. Its final dispatch gate is justified by lookup in the selected
    Task's frozen contract; that proof does not require retaining an otherwise
    unused tool value in the commit plan.
    A native fork already owns its issued invocation. Only the manual entry
    allocates a correlation ticket for its newly recorded fork call. The source
    of a native fork comes from the call context; a manual fork uses its command's
    requested Task. Comparing those two identity copies, or treating a native
    call as a manual one when they differ, adds no valid fork behavior.
    Ancestor capacity failure must reject the whole fork without changing the
    world, even when another admission condition also fails. A single refusal
    lists the admission conditions; checking readiness or capacity again only
    to prioritize an error label provides no additional fork behavior.
    The terminal-settlement contract also reaches [Packet.packet], including
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
From Selvedge.Programming Require FeatureRequest FeatureRequestProofs.
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
    [FeatureRequest.feature_plan] retain their actual source context.
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

    A callback acknowledgement confirms that the service handled its submitted
    observation. An expired or repeated result may successfully leave the world
    unchanged. The receiver and packet outcomes determine ownership, durability
    and further scheduling; a second acceptance marker in the reply has no
    consumer. Startup recovery and shared feature issuance use the same success
    envelope: their resulting state and effects establish recovery and request
    ownership. These contracts require successful acknowledgement and the
    appropriate world and effects, without prescribing a second result marker.
    Speech transcripts and operation cancellation confirm successful handling
    without repeating the supplied identities. Transcript history retains the
    identity and content needed to reject conflicts and consume duplicates
    without another history entry. Both new and matching repeated transcripts
    acknowledge success; only explicit delegation requests execution. A
    delegation's replay indicator remains meaningful because it prevents a
    repeated receipt from requesting another scheduling pass.

    Field-name uniqueness, declaration-indexed callback coordinates and input
    grammar ownership are already enforced by [ModelDeclarations],
    [CallbackDeclarations], [SchemaProjection] and [InputRoute]. Physical dispatch
    still has to preserve the committed identity and report the actual outcome.

    [Capabilities.callable] constructs a request's callable names by filtering
    the Task's frozen tool contract. Completion checks returned names against
    that captured set and rejects call identities already used in history.
    Contract membership follows from that construction and the immutable
    contract; another membership lookup adds no admission condition. *)

(** ** Lifecycle controls retain their distinct purposes

    Freeze suspends dispatch while preserving accepted results and their
    inference demand for unfreeze. Stop allows accepted calls to settle without
    requesting another model turn. Interrupt revokes current execution, records
    uncertain outcomes and permits later input to resume. Archive ends ordinary
    input. Steering replaces current inference work while retaining independent
    operations and queued follow-ups. An idle inference phase therefore does
    not imply an empty operation list.

    A Task permitted to run with admitted context observation must issue it
    before inference. A frozen Task without a ready result must leave selection
    of subsequent Tasks unchanged. These guarantees constrain the actual
    [Scheduler.find_step]; a separately callable wrapper could satisfy them
    while dispatch behavior changes.
    [a_runnable_task_requests_context_before_inference] also requires
    the correlation supply to advance. Callback owners compare ticket identity;
    consecutive numeric labels add no correlation guarantee.

    The existing control and input definitions give these operations their
    meaning. Their changes use the same frame-preserving Task construction.
    Lifecycle availability is a Boolean observation shared by the command and
    its public control list. The accepted command builds its changes once;
    constructing a second lifecycle only to discard it adds no execution meaning.
    Refused controls, input submissions and configuration changes retain the
    Task state and emit no newly authorized effects.
    Successful replies acknowledge the admitted operation. Callers already
    supplied its Task identity, so repeating that identity adds no result needed
    for control, input delivery or execution configuration.
    Diagnostic labels explain the current rejection; they do not authorize
    lifecycle changes or select the pending operation's result-hook chain.
    The actual command rejects every control on an archived Task without changing
    the world or emitting effects. Its private edit
    helper therefore does not need a second availability check or an identity
    guarantee for that already-refused state.
    [steering_replaces_inference_and_preserves_independent_work] additionally
    constrains the actual admitted steering transition, including its new input
    and cancellation of the current inference ticket. *)
From Selvedge.Kernel Require Tasks SchedulerLifecycleProofs CallbacksProofs
  NativeAuthorityProofs SchedulerProofs NativeForkCommitProofs.
Export Selvedge.Kernel.Tasks(control_command, input_changes, input_effects).
Export SchedulerLifecycleProofs(a_runnable_task_requests_context_before_inference,
  frozen_tasks_without_ready_results_do_not_take_scheduler_steps,
  stopped_inference_requests_settle_without_effects,
  stopped_tasks_can_finish_an_already_accepted_call).
Export CallbacksProofs(an_owned_tool_completion_while_frozen_keeps_the_unfreeze_demand).
Export TasksProofs(stopped_idle_receive_reactivates,
  archived_controls_reject_without_changing_world,
  archived_send_rejects_without_changing_world,
  steering_replaces_inference_and_preserves_independent_work).
Export NativeAuthorityProofs(announced_operations_allow_an_independent_model_turn).
Export NativeForkCommitProofs(a_native_fork_uses_its_calling_task).
Export SchedulerProofs(continuation_tracks_available_work,
  a_full_task_records_external_call_refusal,
  a_full_task_refuses_native_result_work_before_execution).

(** After an admitted scheduling pass exhausts its budget, the continuation
    predicate must agree with whether an eligible step remains.
    [continuation_tracks_available_work] connects that predicate to the actual
    step interpreter. Both use the same
    selected action, so readiness cannot drift from execution or require an
    impossible-step fallback.

    The public per-Task operation bound limits concurrent processes, pending
    approval and result processing. At capacity, a new external call or a native
    call that needs result hooks must record a call failure without starting
    its execution or allocating another operation. The two refusal contracts
    constrain those actual dispatch functions and retain the accepted work.
    A synchronous native result with no result hooks needs no operation slot. *)

(** ** Publishing an operation changes where its result is delivered

    A result closes the provider's call while that call still awaits a reply.
    If inference resumes while the operation is live, publishing its notice
    closes the call and opens delivery by the operation's identity. The
    publishing edit installs that result route and appends the matching notice
    together. A subsequent inference keeps the route without emitting another
    notice. Approval, execution, cancellation and result processing retain the
    selected route. *)
Export SchedulerProofs(publishing_operations_routes_results_and_emits_each_first_notice).
Export HistoryProofs(an_unannounced_interruption_closes_the_provider_call,
  an_announced_interruption_retains_operation_identity).

(** ** Approval concerns one captured operation

    Full Access, Ask for Approval and Approval for Me determine how an operation
    obtains the authority needed for its requested execution. Approval grants
    one captured operation; it does not change the Task's persistent settings or
    authorize subsequent commands. A pending operation retains its reviewer and
    ticket until settlement. Its completed history retains the actual command
    and decision reason so the user can understand what was approved or denied;
    the reviewer's complete profile is not a second historical configuration.
    A before-tool hook can rewrite the original call, so this explanation must
    retain the effective invocation that reached approval.
    Escalation admission checks the bounded, nonblank justification in that
    invocation. Review uses the same captured arguments, so process transport
    does not need another stored permission value.
    Denial follows the same frozen result-hook chain as an execution result.

    The authority constructor and granted-operation interpreter bind the
    decision to that operation. The TaskChange configuration law retains the
    persistent settings; the shared independent-request language gives an
    automatic reviewer no tool authority. *)
From Selvedge.Kernel Require TicketedRequest OperationEvent.
From Selvedge.Kernel Require Scheduler ApprovalEvidenceProofs.
Export TicketedRequest.Scoped(external_authority_for).
Export OperationEvent(plan).
Export Scheduler(granted_operation).
Export NativeAuthorityProofs(actual_approval_uses_the_frozen_reviewer).
Export ApprovalEvidenceProofs(pending_approval_selection_retains_the_frozen_actor,
  approval_decision_retains_its_command_and_outcome,
  an_approval_denial_runs_the_frozen_result_chain).
