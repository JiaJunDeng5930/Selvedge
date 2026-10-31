(** * An interface that preserves the user's objects and activity

    A control must identify the object and choice it changes, retain the action's
    current authority, and leave unrelated work intact. Presentation may adapt
    to available space without changing that meaning. *)

From Selvedge.Interaction.Experience Require ObservationProof.
From Selvedge.Interaction.Presentation Require EditorsProof.
From Selvedge.Programming.Presentation Require SurfaceProofs.
Export ObservationProof(available_live_assignment_has_current_authority,
  blocked_draft_preserves_all_requirements,
  observed_property_retains_complete_help,
  a_field_diagnostic_is_not_masked_by_an_unrelated_first_cause).
Export EditorsProof(assessment_presentation_retains_complete_observation,
  blocked_editing_explains_all_commit_obstructions,
  field_obstruction_is_explained_at_its_field).
Export SurfaceProofs(unavailable_control_cannot_press,
  unavailable_commit_cannot_dispatch).

(** ** Information has an owner and a purpose

    [Experience.Model.subject] selects an editor-owned field and its value type.
    Alternatives and assignments retain that subject; action feedback retains
    the editor and draft revision. Workspace collections keep the workspace in
    which membership and primary-directory references are meaningful. These
    constructions prevent a valid value from silently belonging to another
    decision without asking every UI caller for a new proof.

    Recognition needs the effective choice and enough identity to distinguish
    its owner. Comparison needs available alternatives and scope; provenance is
    useful when requested; an obstruction needs its cause and repair beside the
    affected field. A stored attribute alone does not justify permanent
    prominence. [Experience.Model.information] distinguishes inapplicability,
    optional absence, required absence, invalidity and unavailable observation.
    A dependency cannot reappear as a misleading missing fact after its editing
    control is hidden.

    Full observations survive compact projection. A model and its parameter,
    or approval strategy and filesystem scope, retain separate subjects and
    reading roles until their shared constructor. Complete selected values are
    recognition units; secondary detail can move to an existing chooser. Group
    adaptation must not fragment a choice or silently omit a consequence.
    Selection, focus, expansion, execution status and pointer interest answer
    different questions and remain distinct observations.

    [assessment_presentation_retains_complete_observation],
    and [blocked_editing_explains_all_commit_obstructions] retain the assessed
    action and its complete obstruction list. Field lookup finds its own cause
    even when an unrelated cause comes first.
    [field_obstruction_is_explained_at_its_field] removes the duplicate global
    hint when the attention cause belongs to a field. An original Project and
    its editable draft remain different even if their displayed names agree.
    Panels derive identity and accessible naming from the same activity; source
    inspection uses the layer stack and returns to its owner.

    Semantic headings, labels, values, explanations and navigation captions have
    different roles. The shared surface preserves them instead of reconstructing
    ownership from strings or HTML ancestry. Ordinary action help derives from
    the current action and property at native construction. Keeping independent
    stale help in each authored button would separate explanation from behavior. *)

From Selvedge.Interaction Require ApplicationProof ObjectActionsProof.
From Selvedge.Interaction.Session Require AuthoringProof NavigationProof.
Export ApplicationProof(live_setting_selection_preserves_the_message_draft,
  stale_element_cannot_produce_a_product_input,
  a_pending_command_is_not_executed_twice).
Export ObjectActionsProof(available_native_has_current_admission).
Export AuthoringProof(an_admitted_captured_submission_executes_its_captured_command,
  completion_of_an_older_revision_preserves_the_newer_editor).
Export NavigationProof(new_selection_intent_prevents_work_completion_selection,
  new_selection_intent_prevents_side_completion_selection).

(** ** A displayed action is still a request to the service

    Menu and editor assessment uses the same command admission as committed
    submission. Its observation is bound to subject, action, occurrence, draft
    revision and world sequence; [available_native_has_current_admission] and
    [an_admitted_captured_submission_executes_its_captured_command] constrain
    those consumers. Filesystem preparation is a separate observation, not a
    fact predicted by read-only assessment. A failed directory observation is
    retained for explicit retry without requiring an unrelated draft change.

    Resource tickets reject unrelated IO, draft revisions protect newer edits,
    and navigation generations prevent an old completion from selecting a Task
    after the user moved on. [completion_of_an_older_revision_preserves_the_newer_editor]
    and the navigation completion results state those distinct requirements.
    Invalid native text remains an editing buffer rather than changing a typed
    value into an unvalidated string.

    Message authoring and committed execution settings have separate owners.
    [live_setting_selection_preserves_the_message_draft] forbids a model choice
    from replacing message text or advancing its revision. A live setting is
    rebased on the latest Task. Creation preferences may seed future Tasks
    without rewriting existing execution; creation-only reset operations have
    no role in an existing Task editor. Public policy observations may include
    descriptive reviewer information, while command encoding retains only the
    identity admitted by the closed command schema.

    [stale_element_cannot_produce_a_product_input] and
    [a_pending_command_is_not_executed_twice] constrain the application entry.
    Browser keys and captured return targets identify a physical presentation;
    they do not create another logical editor or Task document. *)

From Selvedge.Interaction Require DocumentsProof.
From Selvedge.Interaction.Interactive Require Guarantees
  SemanticsGuarantees RenderProof.
Export DocumentsProof(inherited_document_has_no_external_capability,
  accepted_observation_uses_registered_visible_document,
  accepted_parser_prefix_never_regresses,
  continuous_document_preserves_epoch_and_observation,
  discontinuous_document_allocates_fresh_epoch,
  synchronized_retention_respects_limits,
  decoded_retention_uses_fresh_allocator).
Export Guarantees(preview_or_interrupted_actions_issue_no_external_effect,
  edited_restore_ignored, restore_issues_no_authored_effect).
Export SemanticsGuarantees(builtin_budget_safe).
Export RenderProof(chart_accessible_values_keep_order,
  over_budget_presentation_is_replaced).

(** ** Visible source, document lifetime and publication rights

    Stable source identity comes from frozen producer origin and durable
    namespace. A lifetime epoch distinguishes replacement from extension.
    Completion may preserve local state, while non-prefix replacement, eviction
    and namespace reset must make an earlier parser callback stale. The epoch
    allocator therefore survives reset. Viewing inherited output does not make
    the viewer its producer; [inherited_document_has_no_external_capability]
    preserves that authority distinction. Shared Work source uses its committed
    revision as the same kind of lifetime boundary.

    Physical Markdown parsing observes an authoritative visible prefix. Admission
    registers that observation before publishing its source change. Provenance
    fields alone cannot register a source, and producer completion cannot make
    an incomplete parse final. [accepted_observation_uses_registered_visible_document]
    and [accepted_parser_prefix_never_regresses] constrain the production
    document reducer. Mounted occurrence and display policy additionally govern
    authored external actions.

    Interrupted text is retained within shared bounds and eventually becomes a
    literal archive instead of a remounted interactive source. Preview and
    interrupted documents cannot perform authored external actions. Snapshot
    restoration admits the complete canonical payload, is invalidated by edits,
    and restores local state without issuing authored effects. Browser storage
    does not become authority merely because its decoded shape is typed.

    Explicit interactive fences reuse the common scene and bounded expression
    language; ordinary Markdown stays ordinary Markdown. Graph node controls
    retain native size within their own scrollable enclosures, with a readable
    list equivalent. Charts keep source row order in an accessible table and
    require coherent axes. [chart_accessible_values_keep_order] constrains the
    actual rendering projection. [builtin_budget_safe] establishes that metered
    builtins cannot replenish their remaining work budget.
    [over_budget_presentation_is_replaced] replaces oversized expansion with
    a diagnostic. These bounds limit admitted operations and nodes; elapsed
    browser execution remains an observed property. *)

From Selvedge.Interaction.Presentation Require ProjectionProofs.
From Selvedge.Browser Require DocumentProof ControlContentProof
  LayoutProof FocusProof ReadingProof FieldSessionProof PublicationProof.
Export ProjectionProofs(task_forest_retains_every_task).
Export DocumentProof(every_action_retains_motor_extent).
Export ControlContentProof(compact_supporting_preserves_row_when_it_fits,
  undersized_supporting_changes_the_whole_row).
Export LayoutProof(editor_contains_observed_body_line,
  navigation_capacity_keeps_content, supporting_capacity_keeps_reading_measure).
Export FocusProof(exact_focus_target_precedes_aliases,
  closing_child_restores_owner).
Export ReadingProof(reader_occurrences_preserve_the_task_reading_position).
Export FieldSessionProof(superseded_composition_cannot_restore_old_draft).
Export PublicationProof(a_prepared_document_has_no_input_authority,
  stale_completion_cannot_advance_publication,
  renderer_receipt_establishes_the_displayed_identity).

(** ** Native layout preserves semantic relationships

    [Surface.node] is the shared semantic tree. [Document] interprets it into
    closed native DOM/SVG vocabulary; CSS performs physical layout. Product
    actions, labels, availability and layout intent stay in Gallina. A parallel
    pixel engine would duplicate browser sizing and font shaping without proving
    the actual control's geometry or focus behavior.

    Motor targets, writing-line demand, reading width and clearance have different
    purposes. Their observed fonts and dimensions cannot substitute for one
    another. A comfortable prose width is not automatically the minimum space
    needed for usable editing. Embedded editors share their composer's enclosure
    rather than accumulating independent field padding. The current native
    constructors retain those relationships; [every_action_retains_motor_extent]
    and [editor_contains_observed_body_line] state bounds on emitted CSS and
    layout parameters. Perceived readability remains a physical assessment.

    Full and compact forms are selected for the supporting group from its actual
    available space. [compact_supporting_preserves_row_when_it_fits] and
    [undersized_supporting_changes_the_whole_row] constrain that common decision.
    Inert content still occupies space; foreground interaction does not imply
    removal from layout. Workspace navigation and supporting regions receive
    separate allocations from the viewport, so a temporary dialog cannot itself
    force an otherwise viable desktop navigation mode.

    Navigation has coordinated leading, title and trailing roles. A long label
    cannot redefine membership depth or another row's status. Project hierarchy
    follows actual membership; independent Tasks have a named separate group.
    A decorative icon shares its row action while disclosure owns an independent
    target, so visible alignment and hit extent remain different. A compound
    Project row retains its independent actions within that shared organization.
    Contextual actions must remain reachable by focus and non-hover input, and
    revealing them must not move the title. Concealment, selection and command
    availability are not interchangeable.

    Narrow navigation renders the same Task tree through a native drawer, with
    explicit return focus and retained reading position. Modal native behavior
    supplies background inertness and focus isolation. Physical view occurrences
    scope DOM IDs and references while preserving logical document authority.
    [exact_focus_target_precedes_aliases], [closing_child_restores_owner] and
    [reader_occurrences_preserve_the_task_reading_position] constrain the requested
    focus target and retained reading state. The browser performs the physical
    focus and scroll. Anchored menus refer to their actual trigger.

    Publication separates a prepared document from the renderer's accepted
    generation. Markdown and canonical fence observers must catch up before
    actions receive published-prefix authority. Recovery remains visible until
    explicit retry; a stale normal document must not masquerade as fresh success.

    Chromium layout, font shaping, native modality, focus, storage, selection
    coordinates, media devices and parser observations remain physical boundaries.
    Rendered-interface checks establish geometry, focus and readability under
    the observed browser and font conditions. *)
