(** * An interface that preserves the user's objects and activity

    A control must identify the object and choice it changes, retain the action's
    current authority, and leave unrelated work intact. Presentation may adapt
    to available space without changing that meaning. *)

From Selvedge.Interaction.Experience Require ObservationProof.
From Selvedge.Browser.Presentation Require EditorsProof.
From Selvedge.Browser.Scene Require SurfaceProofs.
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

    A prepared application scene lets a native click resolve its binding and
    present its result without decoding the accepted world or deriving the
    displayed scene again. State, world and environment changes retire the
    corresponding preparation. The displayed generation still governs
    element admission. The native browser measures the new layout after
    giving the resulting document a paint opportunity.

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
    stale help in each authored button would separate explanation from behavior.
    Navigation shows the full caption on hover when the available space clips
    it. A visible caption already names the destination. *)

(** ** Reading and acting in a conversation

    The conversation shows messages and activity that helps the reader follow
    the work. Provider bookkeeping and inherited context remain in the source
    history. An execution record describes a real call, outcome or failure
    before offering its detail. The task inspector shows each working directory
    once and identifies the primary one when there are multiple roots. It shows
    a separate guidance or managed directory when that path differs. The
    inspector shows effective settings, while commands act at the level of
    their target. Interrupting current work
    belongs beside its status, and cancelling a tool call belongs beside that
    call. Forking the current history belongs at the end of an idle
    conversation. The icon names the action on hover and keyboard focus.
    The action menu puts controls that can open immediately before commands
    whose availability needs a service check. It groups refused commands
    after the other actions and keeps their reasons available.

    A chooser explains why a choice is unavailable at the point of selection.
    Model choices with the same name show the configuration difference in
    their captions, including the reasoning policy where it distinguishes them.
    Each delivery choice has one name and explains what happens to the next
    message in the conversation's current state. Delivery uses a separate
    control from submission. An adjustable range displays its current value
    with the track so the reader can connect their change to its result. *)

From Selvedge.Browser Require ApplicationProof.
From Selvedge.Browser Require IncrementalSceneProof.
Export IncrementalSceneProof(retained_live_preview_has_no_action,
  projected_picker_overlays_are_the_scene_overlays,
  scope_only_projection_retains_picker_and_focus).
From Selvedge.Browser.Session Require ObjectActionsProof.
From Selvedge.Browser.Session Require AuthoringProof NavigationProof.
Export ApplicationProof(live_setting_selection_preserves_the_message_draft,
  stale_element_cannot_produce_a_product_input,
  rebasing_a_canonical_prepared_state_agrees_with_prepare,
  a_pending_command_is_not_executed_twice).
Export ObjectActionsProof(available_native_has_current_admission).
Export AuthoringProof(an_admitted_captured_submission_executes_its_captured_command,
  completion_of_an_older_revision_preserves_the_newer_editor,
  git_observation_settles_only_the_workspace_check,
  a_blocked_directory_choice_does_not_change_the_draft).
Export NavigationProof(new_selection_intent_prevents_work_completion_selection,
  new_selection_intent_prevents_side_completion_selection).

(** ** A displayed action is still a request to the service

    Menu and editor assessment uses the same command admission as committed
    submission. A composer can capture a locally valid message while its
    admission is pending. Only the exact captured command may run after
    admission. Sending from an existing conversation shows a visible status
    in the composer and leaves the draft and send control in place. Starting a
    conversation places its captured message and submission status in a temporary
    conversation view before the receipt. A refusal restores the creation draft.
    A successful receipt selects the persisted conversation when the creation is
    still in the foreground. The conversation shows progress at the reply position
    while it awaits model output. The admission observation is bound to subject,
    action, occurrence, draft revision and world sequence.
    [available_native_has_current_admission] and
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

From Selvedge.Browser Require DocumentsProof.
From Selvedge.Interaction.Interactive Require Guarantees SemanticsGuarantees PlotProof.
From Selvedge.Browser.Interactive Require RenderProof.
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
Export PlotProof(chart_axis_covers_values, chart_axis_coordinates_reach_both_plot_edges).

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
    authored external actions. A refusal is visible beside the control that
    produced it. Filling the composer preserves existing text and attachments
    and explains when they prevented the fill.

    Interrupted text is retained within shared bounds and eventually becomes a
    literal archive instead of a remounted interactive source. Preview and
    interrupted documents cannot perform authored external actions. Snapshot
    restoration admits the complete canonical payload, is invalidated by edits,
    and restores local state without issuing authored effects. Browser storage
    does not become authority merely because its decoded shape is typed.

    Explicit interactive fences reuse the common scene and bounded expression
    language. Ordinary Markdown keeps its standard presentation. A pending
    interactive preview reserves space and shows a loading status in place
    of its source. The conversation end action waits for pending previews.
    Opening a conversation shows one loading status until its available
    Markdown and closed interactive previews are ready at the intended position.
    An unfinished preview can stay at the end of a live reply while it streams.
    An already visible timeline continues displaying live replies.
    Mounting a preview above the current passage preserves its reading
    position. A refusal leaves the original source available by disclosure.
    Headings distinguish sections in a long interactive answer. Each source
    disclosure stays with its fence as an icon with an accessible label. A
    fence containing only a chart places its source and data disclosures in
    the same row. A fence containing multiple widgets keeps its source
    disclosure in a separate footer at the leading edge.
    Source copy and wrapping appear beside the revealed source.
    A final reset for the fence stays at the leading edge of the same footer.
    Markdown and authored tables share row separators and header emphasis.
    Sortable column headings show the available control and its current
    direction while numeric headings remain aligned with their values.
    Default and muted badges differ in visual weight. Danger and accent
    remain distinct in both light and dark appearance.
    Graph node controls
    retain native size within their own scrollable enclosures, with a readable
    list equivalent. Charts display categories or numeric ticks along the axes,
    using authored axis labels for units. The axes enclose the plotted range
    and their endpoints agree with its coordinates. Grid lines remain subordinate
    to the marks. The data disclosure below each plot and its compact table
    align to the same footer. The table shares header and row separators with
    other tables, keeps exact plotted rows in source order and aligns numbers
    for comparison. It uses the same numeric grouping as the chart.
    An adjacent slider and numeric input for the same value share a field
    outline and centerline while preserving both editing methods.
    Compact list choices keep the check mark beside its label, and paired form
    cards share their row height when the available width keeps them side by side.
    [chart_accessible_values_keep_order] constrains that rendering projection.
    [builtin_budget_safe] establishes that metered
    builtins cannot replenish their remaining work budget.
    [over_budget_presentation_is_replaced] replaces oversized expansion with
    a diagnostic. These bounds limit admitted operations and nodes; elapsed
    browser execution remains an observed property. *)

From Selvedge.Browser.Presentation Require ProjectionProofs.
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
Export PublicationProof(a_prepared_document_has_no_prefix_authority,
  committed_dom_accepts_native_controls_before_prefix,
  replacing_the_namespace_retires_both_receipts,
  stale_completion_cannot_advance_publication,
  renderer_receipt_establishes_the_displayed_identity).

(** ** Native layout preserves semantic relationships

    [Surface.node] is the shared semantic tree. [Document] interprets it into
    closed native DOM/SVG vocabulary; CSS performs physical layout. Product
    actions, labels, availability and layout intent stay in Gallina. A parallel
    pixel engine would duplicate browser sizing and font shaping without proving
    the actual control's geometry or focus behavior.

    The model picker can materialize its native roots through an extracted
    algebra. It shares the ordinary Document projection for choices, labels,
    properties and event bindings. The adapter receives native child handles.
    Local publication retains element-generation admission, field sessions and
    native modal focus. The synchronous DOM receipt authorizes ordinary native
    controls while Markdown and canonical fences catch up. Authored controls
    require the receipt for their published prefix. Replacing the source
    namespace retires both receipts.

    Appending to a passive reply may publish the changed preview and retain the
    existing action bindings. A picker projected separately must use the same
    overlays and focus scope as the complete view.

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
    force an otherwise viable desktop navigation mode. Centered dialogs fit
    the current viewport while a new layout observation is pending.
    Collapsed desktop navigation keeps the new conversation and search actions
    beside the control that reopens the sidebar.
    Returning to the latest message uses the reading area's outer edge.
    Its control stays clear of inline reading actions and does not change
    how much of the conversation or composer is visible when it appears.

    A Work scopes the conversation tree, graph views and shared interface.
    Project groups organize the conversations in that scope independently of
    Work membership. The conversation scope selector identifies the current
    scope and gives the conversation count for each choice. A project name opens
    its details, and a separate control starts a conversation with its defaults.
    The board and project management are global. The board identifies its items
    as cards and exposes the action to link or open a conversation on the card.
    Its execution filter shows a count distinct from the stage counts and
    explains when the selected filter leaves no executing cards.
    View choices and filters are adjacent. Search has a compact field beside
    them. An empty stage keeps its heading and count on the board background.
    An available destination is highlighted while a card is dragged over it.
    Stage lanes follow one horizontal track. Their minimum width leaves room
    to read a card title alongside its action menu. Empty lanes retain a drop
    target with the same height. Previous and next controls join the toolbar
    when columns extend beyond the viewport. The filter and lane heading use the same
    icon for each stage. The assignee filter distinguishes people, models
    and unassigned cards while keeping its options searchable and its
    selected indicator distinct from keyboard focus.
    Curved tree branches represent conversation lineage. Directed graph connections
    represent output routing, with the same rules and receipts available as text.
    The graph destination, its empty state and the creation action name the same
    object. The empty state describes how a graph routes conversation replies.
    A conversation transfer names its source and receiver beside the direction
    between them. Its optional JSON definition opens in a separate section
    that leaves the selected conversations and submit action available.

    Creation starts with the input needed for the common operation. A new
    conversation starts with a message, and a board card can be captured with a
    title. Optional settings remain available at the corresponding editor.
    A project can be created with its name alone. Its editor marks the default
    working directory as optional and uses the language of the project page.
    Browse and actions on a typed path share its input row. Saved directory
    choices have a separate list.
    The project empty state groups its explanation with the creation action.
    A directory chooser identifies the execution environment that owns its paths.
    The chooser keeps the address and confirmation in place during directory
    reads, with confirmation unavailable until it has the matching result.
    Opening a directory keeps the heading, address and confirmation in place
    while the chooser updates its scrollable results.
    Confirmation applies to an opened directory that matches the address
    field. A failed lookup explains the problem in the chooser's language,
    keeps that field editable, and offers a return to the last successfully
    opened directory when available.
    A conversation keeps its selected run environment when verification is
    pending or fails. [git_observation_settles_only_the_workspace_check]
    constrains the actual receipt. A local Git worktree requires verifying
    that the current primary directory belongs to a repository with a commit.
    A project requires the same verification when saving a local worktree as
    the default. The directory chooser shows Git readiness before a candidate
    becomes the primary directory. [a_blocked_directory_choice_does_not_change_the_draft]
    constrains the confirmation action. Additional working directories may
    be outside the Git repository.
    New choices of run environment reflect the host configuration. Cloud run
    settings identify the primary directory for the GitHub source and offer a
    way to correct it. The pushed revision must contain the setup script, and
    the task directories must lie within that repository.
    The new conversation composer exposes a compact settings icon in its
    toolbar. The menu displays project, actual directory and run settings
    with the current choices. Its submenus open at the same anchor and use
    the same language. Each menu has one visible title. Opening them keeps
    the composer in place.
    Conversation details show the full working directory after expansion,
    prefer line breaks at directory separators and offer to copy it from its
    header row. The details panel grows to fit its facts until it
    reaches the available height, then scrolls within the panel.
    On desktop, the model menu keeps the new conversation heading clear when
    the viewport has room for both.
    The permissions menu describes what happens when an operation needs more
    access and presents shared filesystem and network limits on a separate line.
    A graph can route new replies between existing conversations by selecting
    its source and receiver in the current scope. The empty graph page
    identifies conversation relay as the available relation and shows its
    direction beside the creation action. The entry action, form
    title and commit label use the same name for creating a conversation relay.
    Each endpoint choice leads with its conversation title and includes an
    identifier for titles shared by multiple choices in the scope.
    The same graph editor can also accept a structured declaration for other
    rules. The expanded declaration starts with indented JSON in a monospace
    editor. Collapsing it preserves edits and manual formatting.
    When the current scope has too few conversations, the source and receiver
    form and its unavailable commit identify how many more are needed.
    A conversation created from graph setup belongs to that scope. The
    conversation composer offers an explicit return to the graph draft and
    successful creation returns there while that navigation intent still owns
    the page.

    Opening a search result leaves the query, filters and page of results
    available for further comparison. A return action in the conversation
    header restores those results. When no matches remain, the results area
    shows the outcome and keeps the entered keyword and filters. Results lead with a short readable
    excerpt and mark the matching text with a contrasting foreground and
    background. A result group names its conversation once, separates each
    actionable row and identifies each message by its speaker role.
    A source-only match links to the original message and shows a short label.
    Opening a readable match scrolls to the matching text once it is rendered
    and marks it long enough to identify the landing point.
    The conversation offers a direct return to the result list at the reader's
    previous position.
    Before adding a conversation to the board or linking it to an existing
    card, the interface shows the destination stage for the currently observed
    conversation. A card assigned to a model shows near the commit whether
    saving schedules execution or leaves the card for a later action. An
    unfilled required field gives a neutral prompt while submission is unavailable.
    Invalid entered text names the repair beside the relevant field when both fit.
    The assignee filter keeps complete rows in its scrollable list. Action menus
    show actions relevant to the card and keep their order while service checks
    change their availability. Applicable actions explain any current refusal.
    The card action menu separates deletion from routine actions. The card editor
    identifies its linked conversation. The conversation's execution state is
    secondary within its open action on the board.
    The card reference and timestamp share a metadata row.
    Assisted capture places its model controls beside the card title and description.
    Assisted capture offers the board default when it names an eligible
    drafting model. When models are available and no default applies, the picker
    prompts for a selection. An unavailable configured model explains the repair.
    Cancelling a dialog with its own draft discards all unsaved fields,
    including choices inside collapsed options. A new card starts in the
    stage selected by its entry point. Label entry starts at one line and
    grows for multiple labels. Continuous creation stays next to submit.
    The action area shows progress while a submitted edit is being processed.
    The fixed action area shows the same repair when the field or its inline
    explanation does not fit in view. Each repair is visible in one place.
    Settings editors retain their category context when opened from a setting,
    with that settings page as their only background.
    Settings holds its pane and theme positions from the first frame.
    Conversation defaults keep their positions while service settings load.
    Desktop settings category names fit on one line.
    Skill paths can be edited and saved inline under Extensions.
    A scrolling settings form separates its fields from the fixed action area.
    Selected project directories show the short name and role before the full
    path. An unadded directory path shows one reminder beside its input.
    The automatic execution setting explains which cards can start and when,
    including eligible cards already on the board.

    Navigation has coordinated leading, title and trailing roles. A long label
    cannot redefine membership depth or another row's status. Project hierarchy
    follows actual membership; independent Tasks have a named separate group.
    A sidebar destination fills its row, and the conversation marker is part
    of the open target when it has no separate disclosure action.
    A decorative icon shares its row action while disclosure owns an independent
    target, so visible alignment and hit extent remain different. A compound
    Project row retains its independent actions within that shared organization.
    Contextual actions must remain reachable by focus and non-hover input, and
    revealing them must not move the title. Opening an editor, details or a card
    destination picker from an action menu closes that menu and transfers focus
    to the dialog. A card's action trigger retains its identity when the card
    changes stage.
    Concealment, selection and command availability are not interchangeable.
    A Task with branches keeps its title as a conversation link while its
    adjacent disclosure controls the visibility of its descendants.

    Narrow navigation renders the same Task tree through a native drawer, with
    explicit return focus and retained reading position. Modal native behavior
    supplies background inertness and focus isolation. Physical view occurrences
    scope DOM IDs and references while preserving logical document authority.
    [exact_focus_target_precedes_aliases], [closing_child_restores_owner] and
    [reader_occurrences_preserve_the_task_reading_position] constrain the requested
    focus target and retained reading state. The browser performs the physical
    focus and scroll. Anchored menus refer to their actual trigger.
    Menus in the composer share an attachment edge. When there is space below
    the new-conversation composer, they open there to keep the title clear.
    The narrow portrait model picker has a dedicated bottom sheet.
    The task graph is reachable with the other workspace destinations. Task
    details separate the environment, permissions and execution into readable
    groups. A shown directory path breaks at separators when its segments fit.
    On desktop the conversation reader leaves space between the content and its
    scrollbar. The scrollbar uses a subdued color from the reading palette.

    Publication separates a prepared document from the renderer's accepted
    generation. Markdown and canonical fence observers must catch up before
    actions receive published-prefix authority. Recovery remains visible until
    explicit retry; a stale normal document must not masquerade as fresh success.

    Before the first snapshot, preserve the basic navigation and content layout.
    Show the connection attempt or its failure and let the user reconnect.
    After the snapshot, a missing measurement selects
    the compact layout until real dimensions are available. A page change can
    continue to present the workspace while the browser measures it.

    Search is a read operation. After a valid query it can start without a
    separate permission preview. While the request is pending, the search
    form shows progress and ignores repeat submission. A lost search reply
    leaves the query available for retry and makes no claim about its results.

    Chromium layout, font shaping, native modality, focus, storage, selection
    coordinates, media devices and parser observations remain physical boundaries.
    Rendered-interface checks establish geometry, focus and readability under
    the observed browser and font conditions. *)
Export NavigationProof(a_pending_history_search_does_not_submit_twice).
