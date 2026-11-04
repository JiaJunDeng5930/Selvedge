(** * Undertakings, planned work and declared handoffs

    A Work groups an undertaking, a Task executes a conversation, a graph routes
    replies, and a board card records planned work. Linking them does not merge
    their identity, authority or lifecycle. Independent names and shared source
    must remain editable without rewriting the execution they describe.
    Refusal contracts require failure, unchanged state and no emitted effects;
    human-readable diagnostic wording is not part of that behavior. *)

From Selvedge.Features Require WorkProofs.
Export WorkProofs(witnessed_root_birth_records_its_work,
  new_root_ownership_preserves_existing_roots,
  stale_ui_is_atomic, failed_patch_is_atomic,
  admitted_patch_updates_shared_source,
  shared_ui_patch_preserves_task_ownership, ui_requires_task_call).

(** ** Work ownership and shared source

    A Task resolves its Work through its explicit root association and nearest
    associated ancestor. [witnessed_root_birth_records_its_work] consumes the
    actual fresh birth rather than an arbitrary world-changing callback;
    [new_root_ownership_preserves_existing_roots] preserves earlier ownership.

    The shared interface belongs to the Work registry, so changing conversations
    does not erase it. Tool callers supply no competing Work target. Patches
    require the observed revision and exact source context:
    [stale_ui_is_atomic], [failed_patch_is_atomic] and
    [admitted_patch_updates_shared_source] constrain the public transition.
    Source admission is intentionally independent of interactive-language
    validity so an unfinished interface can be inspected and repaired.
    Browser-local edits and feedback need not become shared persistent state.
    [shared_ui_patch_preserves_task_ownership] prevents source editing from
    transferring execution ownership. *)

From Selvedge.Features Require GraphConstructionProofs TaskGraphProofs.
Export GraphConstructionProofs(public_resolved_graph_installs_its_exact_typed_plan,
  existing_birth_keeps_its_original_identity,
  failed_create_graph_keeps_the_complete_world).
Export TaskGraphProofs(resolved_installation_succeeds,
  expansion_has_declared_meaning,
  pending_deliveries_obey_registry_order,
  actual_delivery_reaches_idle_task,
  unchanged_history_has_no_new_outputs,
  observed_provider_text_retains_its_requested_mode_and_is_routed).

(** ** Graphs express connections using ordinary Task operations

    A graph stores finite task references and output reactions. Its declaration
    supplies both execution and presentation; arbitrary captured callbacks
    would need a separate persistence and display meaning. Existing references
    are resolved against the original observation, before any new Tasks are
    allocated. A guessed future identity cannot acquire the meaning Existing.
    Installation establishes all connections before new Tasks can execute, and
    rejected installation is atomic.

    [TaskGraphSemantics] gives the ordered meaning independently of the runtime
    expander. [expansion_has_declared_meaning],
    [pending_deliveries_obey_registry_order] and
    [actual_delivery_reaches_idle_task] connect it to actual delivery. An
    implementation that emits no handoffs cannot satisfy the positive result.
    Fresh nonempty assistant replies trigger reactions; installation does not
    replay old outputs. [unchanged_history_has_no_new_outputs] binds that
    boundary to the committed history position. The request receiver already
    consumes each model completion once, and inherited fork context retains its
    original producer. Rechecking every old origin adds no routing authority.
    Routing follows the returned assistant message, so the
    source's requested output mode cannot silently discard its text.
    [observed_provider_text_retains_its_requested_mode_and_is_routed] connects
    that requirement to the actual provider callback and reaction hook.
    Replies containing tool calls await their results instead of triggering a
    handoff; nonassistant context is not handoff text.

    Reliable handoff is part of the committed transition and reuses normal
    input admission. A target refusal remains observable without discarding the
    source reply. Optional plugin observations and tool hooks do not substitute
    for that transport. Editing rules affects subsequent journal inputs, not
    already delivered messages. Removing a graph removes its connections,
    leaving Task and Work lifecycle to their owners. Cycles cause later Task
    activity; they do not synchronously run a model inside a graph transition
    or establish termination of an entire conversation. *)

From Selvedge.Features Require BoardProofs TitleProofs TitleRuntime.
From Selvedge.Kernel Require FeatureAdmissionProofs.
From Selvedge.Programming Require FeatureRequestProofs.
From Selvedge.Kernel Require TitleCommit.
From Selvedge.Programming Require CardScopeProofs.
Export CardScopeProofs(stale_card_is_atomic).
Export BoardProofs(ordinary_card_creation_installs_the_requested_draft,
  automatic_queue_follows_pin_priority_and_board_order,
  admitted_card_edit_preserves_its_execution,
  admitted_link_preserves_execution_and_drafting,
  linked_assignment_cannot_be_transferred,
  stopped_operation_retains_its_concurrency_slot,
  archive_busy_card_retains_task_authority,
  current_board_text_retains_other_plan_fields,
  board_text_without_current_lease_is_ignored).
Export FeatureAdmissionProofs(admitted_title_resolves_without_rechecking,
  a_pending_title_is_not_resolved_again).
Export FeatureRequestProofs(every_feature_request_has_its_installed_receiver).
Export TitleRuntime(issue).
Export TitleCommit(candidate).
Export TitleProofs(admitted_title_issues_observed_request,
  title_configuration_preserves_generation_entries,
  title_recovery_keeps_execution_state,
  title_recovery_keeps_saved_instructions).

(** ** Plans remain editable without rewriting execution

    Launching a card captures an ordinary Task request. The card remains a plan:
    its title, description, Project, attachments, priority and labels may change
    while the linked Task runs. [admitted_card_edit_preserves_its_execution]
    requires the actual update to save the exact patch and retain the complete
    Task registry, its association and independent conversation titles.
    Revision conflict is an atomic refusal. Archived plans must be restored
    before editing. An active Task keeps its card in progress; same-column
    ordering and pinning remain independent of that execution.

    Cards, Board agent settings and title settings use revisions to reject
    stale writes. Callers return the revision they observed; they do not
    calculate its next value. Successful updates invalidate the previous
    revision while retaining the requested content. A particular initial
    revision or increment size is not part of that conflict contract.

    The agent limit counts configured agents. Updating an existing agent keeps
    that count, including at capacity; deleting an unassigned agent releases
    one slot. Retained empty storage positions do not consume that capacity,
    so their number is not part of the update or deletion contract.

    The linked assignee is also the attribution used by the agent concurrency
    limit. Changing it could free the old agent's slot while its Task still
    runs, including a later resumed turn. [linked_assignment_cannot_be_transferred]
    therefore freezes that association, while resubmitting its current value
    is allowed. [stopped_operation_retains_its_concurrency_slot] requires active
    operations to keep their slot after the next model turn has been stopped.
    The same slot must settle before deleting its card. Archival may request
    the ordinary Task interruption but cannot invent new cancellation authority
    from old receipt data.

    Card drafting owns a request ticket, not the whole card revision. Pinning,
    ordering, plan metadata and linked Task progress do not invalidate its
    prompt or chosen output fields. The current result amends the current card,
    preserving those changes as [current_board_text_retains_other_plan_fields]
    requires. Explicit title or description edits supersede that request;
    archiving clears its receiver and deletion removes it. The shared receiver
    then rejects stale results without waiting for the external invocation to
    finish. A second generation is refused while the first remains current.
    This keeps request ownership separate from optimistic edit conflicts.
    Linking an existing Task also keeps the current drafting receiver and card
    plan. [admitted_link_preserves_execution_and_drafting] requires that actual
    successful association while preserving the Task registry and independent
    conversation titles; linking must not recreate execution or lose a paid
    request that still owns its receiver.

    Ordinary creation retains the requested draft. Automatic execution selects
    pinned cards first, then urgent through unprioritized cards, retaining manual
    board order within each group; only runnable cards enter this selection.
    [automatic_queue_follows_pin_priority_and_board_order] constrains that actual
    queue. Board eligibility and concurrency belong to [Board]. Filtering
    changes the view, not the stored card. The bounded scheduler requests a
    continuation when work remains. Automatic title selection uses
    [FeatureRequestAdmission.resolve_title]. Its admission theorem retains the
    actually observed Task and selected profile; a pending entry prevents
    another selection. [TitleCommit.candidate] calls [TitleRuntime.issue], which
    constructs the shared feature-request plan containing the frozen profile
    and prompt. [admitted_title_issues_observed_request] binds its emitted request
    to the observed owner, selected profile and prompt. The shared receiver
    theorem governs installation of the receiver.
    [tests/title-request-settings.test.mjs] exercises the automatic request's
    frozen settings and its completed title through public read. The selected
    theorems constrain admission and receiver construction; the public test
    covers their composed delivery through the service.
    A card title and its linked conversation title remain independent.
    [board_text_without_current_lease_is_ignored] constrains the actual callback:
    stale completions cannot overwrite a newer request. Recovery marks
    interrupted generation as failed instead of replaying uncertain inference.

    Generated-title quality and external model completion remain provider
    observations. *)

(** ** A side conversation returns content only on request

    Opening a side conversation captures the parent's context while leaving its
    work running. The child is an ordinary persistent Task with private birth
    guidance and its own cursor. Explicit return selects the unseen conversational
    suffix and sends it as quoted input through the parent's ordinary admission.
    Closing the supporting presentation only changes the view.

    The birth theorem establishes the captured guidance and initial cursor.
    A successful return advances that cursor to the observed history length;
    repeating it without new history cannot resend the same content. Refusal
    preserves the complete world and emits no effects. These guarantees apply
    to the actual [return_side] transition; diagnostic wording is not part of
    the no-repeat contract. *)
From Selvedge.Kernel Require SideConversationProofs CommandExecution History.
Export SideConversationProofs(successful_open_side_records_private_birth_guidance,
  successful_side_return_consumes_the_observed_suffix,
  a_refused_side_return_keeps_the_world_and_effects).
Export CommandExecution(return_side).
Export History(returned_content).
