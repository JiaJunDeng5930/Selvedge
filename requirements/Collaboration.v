(** * Undertakings, tickets and workflow instances

    A Work groups an undertaking. A workflow definition describes reusable
    message routing, a workflow instance executes one invocation of that
    definition, and a Task retains a conversation. A board card (ticket)
    records a deliverable and can delegate its execution to an instance.
    Users must be able to run the same definition for different tickets without
    mixing their messages, conversations or results. Independent names and
    shared source remain editable without rewriting the execution they describe.
    Refusal contracts require failure, unchanged state and no emitted effects;
    human-readable diagnostic wording is not part of that behavior.
    Deletion, renaming and board settings need an acknowledgement of the
    admitted change. Repeating their supplied fields adds no outcome.
    Creation returns the new identity, versioned saves return the revision
    needed for another edit, and derived results retain their observed data. *)

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
    A Work can hold independent workflow definitions. Each instance belongs
    to its definition's Work, as do the Tasks it creates. Changing the selected
    Work in the browser changes the view without changing those associations.

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

From Selvedge.Features Require TaskGraphProofs.
Export TaskGraphProofs(expansion_has_declared_meaning,
  pending_deliveries_obey_registry_order,
  actual_delivery_reaches_idle_task,
  unchanged_history_has_no_new_outputs,
  observed_provider_text_retains_its_requested_mode_and_is_routed).

(** ** A workflow definition is callable at any of its entrance nodes

    A definition contains nodes and directed connections. Saving it makes its
    nodes and connections available to start and inspect. It does not start an
    instance or create its Tasks. A start names the definition and one of its
    entrance nodes and supplies a message. The accepted start creates a fresh
    instance, captures the selected definition and admits the message to that
    entrance. A refused start leaves no instance, Task, ticket association or
    dispatch effect. Edits affect later starts. An existing instance retains
    the definition it started with, including its connection choices.

    A graph can have several entrances. An entrance produces the received
    message unchanged, and its outgoing connections use ordinary forwarding.
    In particular, an entrance with several outgoing connections forwards
    along each of them. An exit records the received message and ends the path
    that reached it. Reaching an exit does not finish other paths.

    A Task node uses ordinary conversation admission. When configured to
    create a Task, it either creates a fresh Task for every delivery or creates
    one on its first delivery and uses that same Task for later deliveries to
    the node in the same instance. Separate instances have separate created
    Tasks. This lets later work retain its context where requested and makes
    fresh context available where requested. If a node refers to an existing
    conversation, that reference retains ordinary Task identity and Work
    admission. The work sent to a Task and the result accepted from it still
    belong to a particular delivery in a particular instance. When multiple
    deliveries target the same conversation, keep each outstanding until its
    own result is accepted or its failure recorded. A later delivery must
    not silently replace one the workflow still needs to settle. *)

(** ** Tasks choose a connection for the current delivery

    Connections retain the declared output, literal and concatenation message
    rules. [expansion_has_declared_meaning] selects the existing meaning of
    those rules. Ordinary input admission still governs the destination. A
    refusal remains observable and leaves the path unfinished. The exported
    delivery and provider theorems cover the existing handoff operation. The
    workflow extension must bind forwarding and its receipt to the actual
    instance and delivery; those theorems alone do not establish this binding.

    Each outgoing connection of a Task node with multiple choices has an
    identity and a description of when to use it. Supply those choices and
    descriptions to the Task at creation, or with the workflow's input if
    the conversation already exists. Use the captured definition to interpret
    its choice. The Task calls a tool before its final answer to
    select one outgoing connection for the current delivery. Acceptance of a
    choice sends no message. The tool refuses a connection outside that
    delivery's outgoing choices without changing its routing. Once the
    corresponding final answer arrives, forward its content through the
    chosen connection only. With one outgoing connection, forward the final
    answer without requiring the tool.

    A final answer without the required choice sends a reminder to the same
    Task and leaves its delivery outstanding. Forwarding then requires both a
    choice and a subsequent final answer. A choice for an earlier delivery,
    a result from another instance, old conversation history, an unrelated
    turn or an intermediate reply that requests tools cannot advance the
    current delivery. Accepting the final answer consumes that delivery's
    authority to forward, so a late or repeated result cannot act on later
    work in the same Task. In particular, reusing a conversation does not
    reuse its previous choice. *)

(** ** Every path must reach an exit before the instance completes

    An accepted start establishes a path. Forwarding replaces the current
    position with the resulting paths and carries each through pending
    delivery, Task activity or waiting for a result. Paths may revisit a node.
    A blocked delivery or a path that runs out of connections at a node other
    than an exit remains unfinished. Neither inactivity nor a Task failure
    supplies an exit receipt. The instance retains its observed exit results.

    The completion contract below uses the instance's full set of current path
    dispositions, including paths that already reached exits. Its
    binding must account for every branch admitted by the actual start and
    forwarding operations. In particular, it cannot derive paths from visible
    activity dots or discard a queued, blocked or failed path to prove success.
    Outstanding work includes work awaiting admission, routing, a choice or a
    final answer, as well as Tasks still executing work for that instance.
    Unrelated turns in a conversation do not count as instance work. The last
    valid exit and settlement of outstanding work must make completion
    observable without another user action. External providers are responsible
    for supplying results; the system does not guarantee that a model answers
    or that an arbitrary cycle reaches an exit. *)

Definition workflow_completion_contract {Path : Type} (paths : list Path)
    (reached_exit : Path -> Prop) (outstanding complete : Prop) : Prop :=
  complete <-> paths <> nil /\ List.Forall reached_exit paths /\ ~ outstanding.

From Selvedge.Features Require WorkflowProofs.
Export WorkflowProofs(completion_reports_all_paths_at_exits,
  workflow_processing_selects_exactly_the_active_instances,
  completion_does_not_hide_outstanding_paths).

From Selvedge.Features Require BoardProofs TitleProofs TitleRuntime.
From Selvedge.Kernel Require FeatureAdmissionProofs.
From Selvedge.Programming Require FeatureRequestProofs.
From Selvedge.Kernel Require TitleCommit.
From Selvedge.Programming Require CardScopeProofs.
Export CardScopeProofs(stale_card_is_atomic).
Export BoardProofs(ordinary_card_creation_installs_the_requested_draft,
  automatic_queue_follows_pin_priority_and_board_order,
  selecting_the_next_card_follows_the_automatic_queue,
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
  explicit_title_profile_uses_only_saved_key,
  title_scope_preserves_the_first_resolvable_task,
  title_configuration_preserves_generation_entries,
  title_recovery_keeps_execution_state,
  title_recovery_keeps_saved_instructions).

(** ** Plans remain editable without rewriting execution

    Launching a card assigned to an ordinary model captures a Task request.
    The card remains a plan:
    its title, description, Project, attachments, priority and labels may change
    while the linked Task runs. [admitted_card_edit_preserves_its_execution]
    requires the actual update to save the exact patch and retain the complete
    Task registry, its association and independent conversation titles.
    Revision conflict is an atomic refusal. Archived plans must be restored
    before editing. An active Task keeps its card in progress; same-column
    ordering and pinning remain independent of that execution.

    Cards and title settings use revisions to reject
    stale writes. Callers return the revision they observed; they do not
    calculate its next value. Successful updates invalidate the previous
    revision while retaining the requested content. A particular initial
    revision or increment size is not part of that conflict contract.

    Launching a card requires its assigned model profile to have no other
    active card. Changing the assignee could free the profile's slot while
    the linked Task still runs, including a later resumed turn.
    [linked_assignment_cannot_be_transferred]
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

    A conversation can create a board card through one command that captures
    its plan and applies the existing association. A missing or already linked
    conversation refuses the command without leaving an unlinked card or
    requesting drafting effects. An existing association opens its card from
    the conversation's actions.

    A workflow-backed ticket selects a definition and an entrance before
    launch. Launch supplies the ticket's captured request as the entrance
    message, creates the instance and records it as the ticket's current
    execution in one accepted operation. A refused launch leaves the ticket
    and execution state unchanged. An instance can also start directly from
    its Work without a ticket. Editing the ticket's plan does not change an
    accepted invocation.

    At most one instance is current for a ticket. Starting again creates a
    new instance and retains the earlier one for inspection. Only successful
    completion of the ticket's current instance authorizes automatic entry
    into Done, and that completion updates the ticket without manual review.
    An earlier instance's result and the state of one constituent Task have
    no such authority. A failed or blocked instance leaves the deliverable
    unfinished and its execution available for inspection. This requirement
    is specific to workflow-backed tickets; ordinary Task associations keep
    their existing stage rules.

    Ordinary creation retains the requested draft. Automatic execution selects
    pinned cards first, then urgent through unprioritized cards, retaining manual
    board order within each group; only runnable cards enter this selection.
    [automatic_queue_follows_pin_priority_and_board_order] constrains that actual
    queue. Board eligibility and concurrency belong to [Board]. Filtering
    changes the view, not the stored card. The bounded scheduler requests a
    continuation when work remains. Automatic title selection traverses Tasks
    in registry order and passes the observed task directly to
    [FeatureRequestAdmission.resolve_title_at]. With the default Auto setting,
    it prefers an ordinary gpt-5.6-luna profile on the Task's ChatGPT account
    and otherwise uses the Task profile when available; an echo profile cannot
    issue a title request. An explicitly saved Agent conversation title model
    uses only that profile key while it remains ordinary (non-echo with fixed
    reasoning). When that key is missing or no longer ordinary, no title request
    is sent and the existing request summary remains its title. A matching
    ordinary profile remains the only eligible request target.
    [explicit_title_profile_uses_only_saved_key] constrains this selection.
    The setting may retain an unavailable key so journal replay does not
    reinterpret a prior choice. Its admission theorem retains the
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
    guidance and a handoff that keeps its recipient and delivery cursor together.
    Explicit return selects the unseen conversational suffix and sends it as
    quoted input through that recipient's ordinary admission.
    Closing the supporting presentation only changes the view.

    The birth theorem establishes the captured guidance and initial handoff.
    A successful return advances its cursor to the observed history length;
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
