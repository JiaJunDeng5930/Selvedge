(** * Undertakings, planned work and declared handoffs

    A Work groups an undertaking, a Task executes a conversation, a graph routes
    replies, and a board card records planned work. Linking them does not merge
    their identity, authority or lifecycle. Independent names and shared source
    must remain editable without rewriting the execution they describe. *)

From Selvedge.Features Require WorkProofs.
Export WorkProofs(witnessed_root_birth_records_its_work,
  new_root_ownership_preserves_existing_roots,
  stale_ui_is_atomic, failed_patch_is_atomic,
  admitted_patch_updates_shared_source,
  shared_ui_patch_preserves_task_ownership).

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
  actual_delivery_reaches_idle_task).

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
    Fresh ordinary assistant replies trigger reactions; installation does not
    replay old outputs. Interactive output and tool calls are not ordinary
    handoff text.

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
Export BoardProofs(linked_execution_inputs_are_immutable,
  archive_busy_card_retains_task_authority,
  card_title_result_preserves_conversation,
  saving_card_preserves_conversations_and_their_titles).
Export FeatureAdmissionProofs(admitted_title_resolves_without_rechecking,
  a_pending_title_is_not_resolved_again).
Export FeatureRequestProofs(every_feature_request_has_its_installed_receiver).
Export TitleRuntime(issue).
Export TitleCommit(candidate).
Export TitleProofs(title_configuration_preserves_generation_entries,
  title_recovery_keeps_execution_state,
  title_recovery_keeps_saved_instructions).

(** ** Plans and generated titles retain their own revisions

    Launching a card freezes an ordinary Task request. Later role, Project or
    title changes govern future requests rather than rewriting that accepted
    execution. Revision conflict is an atomic refusal; linked execution inputs
    remain immutable. Archival may request the ordinary Task interruption but
    cannot invent new cancellation authority from old receipt data.

    Board eligibility, concurrency and ordering belong to [Board]. Filtering
    changes the view, not the stored card. The bounded scheduler requests a
    continuation when work remains. Automatic title selection uses
    [FeatureRequestAdmission.resolve_title]. Its admission theorem retains the
    actually observed Task and selected profile; a pending entry prevents
    another selection. [TitleCommit.candidate] calls [TitleRuntime.issue], which
    constructs the shared feature-request plan containing the frozen profile
    and prompt. The shared receiver theorem governs that construction.
    [tests/title-request-settings.test.mjs] exercises the automatic request's
    frozen settings and its completed title through public read. The selected
    theorems constrain admission and receiver construction; the public test
    covers their composed delivery through the service.
    A card title and its linked conversation title remain independent, as
    [card_title_result_preserves_conversation] requires. Stale completions do
    not overwrite a newer request; recovery marks interrupted generation as
    failed instead of replaying uncertain inference.

    Generated-title quality and external model completion remain provider
    observations. *)

(** ** A side conversation returns content only on request

    Opening a side conversation captures the parent's context while leaving its
    work running. The child is an ordinary persistent Task with private birth
    guidance and its own cursor. Explicit return selects the unseen conversational
    suffix and sends it as quoted input through the parent's ordinary admission.
    Closing the supporting presentation only changes the view.

    The birth theorem establishes the captured guidance and initial cursor.
    [return_side] and [returned_content] are the executable definitions of return
    and content selection; the birth theorem does not establish return delivery. *)
From Selvedge.Kernel Require SideConversationProofs CommandExecution History.
Export SideConversationProofs(successful_open_side_records_private_birth_guidance).
Export CommandExecution(return_side).
Export History(returned_content).
