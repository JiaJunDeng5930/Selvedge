(** * Recorded context and bounded model input

    A user must be able to inspect the content supplied to a Task and recover
    that work without depending on today's mutable instructions. Retained
    history is the authority for model input. A provider encoding may translate
    it, but cannot add privately refreshed instructions or turn an audit record
    into an instruction. *)

From Selvedge.Kernel Require ContextProofs ReasoningProofs
  ModelRequestConstructionProofs HistoryRoleProofs RequestDeliveryProofs.
Export ContextProofs(context_history_reconstructs_each_accepted_change,
  an_observed_amendment_matches_its_baseline_and_patch,
  failed_context_observation_retains_the_last_admitted_binding).
Export ReasoningProofs(the_actual_scheduler_observes_before_preparing_a_model,
  context_requests_capture_the_current_history_revision,
  context_completion_requires_the_current_ticket,
  an_actual_stale_context_result_restarts_from_the_current_prefix,
  a_frozen_context_completion_waits_for_a_new_observation,
  a_stopped_context_completion_waits_for_a_new_observation,
  actual_model_requests_retain_the_complete_committed_history).
Export RequestDeliveryProofs(context_completion_commits_before_following_scheduling,
  a_transport_refusal_retains_the_complete_task_history,
  an_after_budget_refusal_keeps_raw_evidence_and_retires_the_operation).
Export ModelRequestConstructionProofs(every_frozen_model_is_supported_by_its_frozen_profile,
  captured_history_cannot_reselect_the_model).
Export HistoryRoleProofs(codec_roles_follow_the_shared_projection_vocabulary).

(** ** Observe changes before requesting work

    A tracked source has a stable identity distinct from its revision. Its
    introduction records its value; later accepted patches and withdrawals
    target that identity. [context_history_reconstructs_each_accepted_change]
    and [an_observed_amendment_matches_its_baseline_and_patch] constrain the
    actual update interpreter. An external diff algorithm only proposes edits;
    admission checks both the baseline and captured result.

    Source failures retain the last admitted binding. Descriptor reads and
    UTF-8, JSON and YAML decoders already reject their invalid external input;
    their errors flow into the same observation failure. The requirement is a
    visible failed observation with the previous binding retained; it does not
    prescribe another layer of diagnostic wording.
    [ContextTypes] constructs the admitted snapshots and [ContextUpdates]
    checks each external change against its baseline and reconstructed value.
    The provider adapters consume the committed [Codec] projection directly;
    journal replay runs the admitted inputs again rather than importing arbitrary
    history records. Re-parsing those private records supplies no new source
    observation. Context selection keeps original fixed records and excludes
    replacement-provided instruction records.
    A tool's ordinary file read is not automatically an instruction update, and
    observing instruction text cannot grant workspace or tool authority. [ContextTypes.definition]
    shares identity, fields, scope and observation declarations across admission
    and provider translation. New uses of existing observation operations reuse
    that language; new physical observations still need an interpreter.

    Discovery can produce many sources from one captured observer declaration.
    Reinterpreting its unchanged descriptor supplies no new observation and
    must not multiply boundary work by the source count. The host caches only
    this pure descriptor; file contents and revisions are observed on each
    requested refresh. Its single synchronous cache insertion per live observer
    supplies this bound by construction, without a wall-clock threshold.

    Discovery observes one directory at a time. Its controller selects an
    optional inspection from the current scan state; the host observes that
    directory before another transition. The scan state already owns failure
    and collected sources. A parallel completion flag, action list or repeated
    copy of that result supplies no additional observation.

    [the_actual_scheduler_observes_before_preparing_a_model] binds this order
    to the scheduler. Model and evaluator requests capture current history and
    an admitted profile choice. [every_frozen_model_is_supported_by_its_frozen_profile]
    and [captured_history_cannot_reselect_the_model] are properties of the
    source-indexed selection, not comparisons with a duplicate model field.
    An oversized request fails while retaining the complete history and
    unrelated operations. An after-hook transport refusal retains the original
    tool evidence, retires its operation and records the same failure reason in
    its receipt and result. These outcomes do not prescribe diagnostic wording.
    Frozen choices are captured domain values. Host configuration, credential
    views and prepared-request containers supply observations; freezing their
    JavaScript properties does not establish Task authority or capture a choice.
    The Task retains settings and the output mode used to interpret its reply.
    A provider dispatch does not consume another copy of either value; it keeps
    the resource binding needed by the physical archive barrier. Evaluator
    previews obtain their bounds from their construction and encoded-request
    admission, without self-reported preview flags or byte-limit labels.
    A matching ticket also captures a history revision. Another completed
    operation may have extended that history while observation was outstanding;
    the actual callback then requests a new observation of the current prefix.
    Frozen and stopped completions retain ordinary inference demand for a new
    observation when resumed. [context_completion_commits_before_following_scheduling]
    binds this callback to packet preparation and its committed continuation.
    Real-file discovery and global-guidance delivery are exercised through the
    public service in [tests/filesystem-boundaries.test.mjs] and
    [tests/context-discovery-control.test.mjs].

    Final comparisons against a subsequently changed Task remain necessary.
    Evaluator judgments and their quality remain external observations; their
    previews are bounded. The history's [ModelContext] constructor identifies
    provider output: its projection retains public reasoning summaries and
    excludes opaque continuations. Tool arguments and results remain ordinary
    evidence, including a tool's public read of another Task. Their field names
    and [type] values do not acquire provider semantics. Recursively guessing
    that meaning would discard valid tool data; the existing excerpt and total
    byte bounds already limit this evidence. The captured public history owns
    evidence selection and excerpting. [ReasoningView]
    also constructs the effect's history roles and string previews. The evaluator
    adapter organizes those values directly without another admission of its
    private input or a parallel text-part representation. The frozen adaptive
    policy has already passed domain admission, including its effort set,
    evaluator, transport and lease bound. The host consumes that policy without
    parsing it again. Credential and budget
    admission either reject or allow the awaited request to continue; they do
    not select another evaluator or dispatch a host action through an unused
    success payload. It forwards the selected
    tool excerpts directly: another per-call truncation would discard useful
    evidence without bounding a distinct resource. The
    complete encoded request remains subject to byte and local-token admission
    before dispatch. *)

From Selvedge.Kernel Require ContextSelectionProofs ModelRequestProofs.
From Selvedge.Features Require CompactionProofs.
Export ContextSelectionProofs(adoption_keeps_the_original_history,
  selected_replacement_keeps_the_exact_suffix,
  selected_replacement_drops_compacted_reasoning_updates,
  portable_replacement_keeps_the_exact_suffix,
  another_scope_cannot_select_native_context,
  an_unresolved_captured_call_cannot_be_compacted).
Export CompactionProofs(measured_scope_and_reserve_reach_the_executed_request,
  manual_compaction_captures_context_before_any_summary_request,
  suspended_manual_context_completion_cancels_its_job,
  a_compaction_failure_is_not_immediately_resubmitted).
Export ModelRequestProofs(selected_model_request_uses_the_measured_scope,
  unselected_model_request_uses_portable_context,
  evaluator_history_obeys_its_transport_budget).
Export ReasoningProofs(evaluator_tool_evidence_keeps_the_original_json,
  model_context_preview_exposes_only_the_public_reasoning_summary,
  model_context_compaction_has_no_public_preview).

(** ** Replacement input preserves its independent source

    Retaining original records and selecting a smaller provider window have
    different purposes. [adoption_keeps_the_original_history] makes adoption
    append-only. [selected_replacement_keeps_the_exact_suffix] and
    [portable_replacement_keeps_the_exact_suffix] constrain the actual selected
    replacement plus records added after its captured span. Incompatible native
    scope cannot authorize selection; readable originals remain available for
    a portable rebuild. Fixed tracked context and image references retain their
    distinct roles when ordinary dialogue is summarized. Reasoning configuration
    updates control the following generation; they are not tracked instructions
    to move before a replacement summary. Selection drops updates in the replaced
    span, and the next generation records its current effort again. This also
    follows the provider's requirement to restate configuration after compaction
    (https://developers.openai.com/api/docs/guides/reasoning).

    A ticket identifies a request, but does not establish that its measurement
    still describes the current history, settings, tool capabilities or suffix.
    Compaction therefore retains its captured typed input across measurement,
    preparation and validation. [measured_scope_and_reserve_reach_the_executed_request]
    connects the measurement to the request actually sent. Manual compaction
    first uses the same context-observation operation as inference. A frozen or
    stopped completion cancels that manual job and records the reason while
    retaining the original history. Its cleared job cannot itself authorize a
    later summary request. This is the actual maintenance operation constrained by
    [suspended_manual_context_completion_cancels_its_job]. Unresolved
    captured calls cannot be discarded before their outputs arrive.

    Compaction has its own feature state so preparatory work can coexist with
    ordinary execution. Each physical invocation receives a fresh ticket;
    retained useful-work revision and failure state prevent idle reissuance.
    Cache maintenance uses the observed prefix and deadline. A separate last
    activity timestamp or old consumer label cannot select further work; the
    next maintenance request observes its consumer scope before dispatch.
    [a_compaction_failure_is_not_immediately_resubmitted] excludes treating
    every failure as permission to repeat. Recovery retires pending receivers
    while retaining the Task's actual inference demand.

    Provider token counts, endpoint scope, clocks and summary fidelity are
    observations, not static facts supplied by a budget type. A token window
    does not bound the escaped JSON transport. Complete encoded requests and
    carried summary metadata must fit their actual byte budgets; bounded
    fragment processing must not assume that the whole source fits another
    model. No fallback is allowed to silently discard original history.
    Portable progress is the remaining ordered scalar list and its carried
    continuation note; a second cumulative offset neither selects work nor
    establishes completion. The executed plan owns the method and budget.
    Once that plan exists, retaining its original target configuration adds
    no input to a subsequent fragment or portable rebuild.
    The captured receiver owns validation purpose and settings compatibility,
    so neither needs another unused copy in the physical request. A portable
    summary carries readable text and usage; its callback does not consume a
    provider scope, which remains relevant to native replacements and measurement. *)

From Selvedge.Kernel Require NativeTools NativeCatalogProofs.
Export NativeTools(presentation_catalog).
Export NativeCatalogProofs(native_catalog_contains_every_declared_tool).
Export ContextSelectionProofs(selecting_a_summary_preserves_each_original_image).

(** ** Tool discovery and images do not create another context store

    A frozen external tool catalog is execution authority. Loading a full
    parameter schema for the model is presentation. Native definitions remain
    resident; a Task with a discovery capability may receive lightweight
    external declarations and load full definitions through ordinary committed
    results. [presentation_catalog] makes that presentation choice from the
    frozen catalog's actual discovery capability. Known exact names remain
    reachable independently of keyword ranking. A Task without a discovery
    route retains its full definitions.
    History already preserves discovery results across inheritance and replay;
    a second persistent loaded-tools set would compete with that history.

    Ordered image parts refer to content-addressed snapshots, not filenames or
    provider upload identities. The original bytes may outlive their local
    path and are materialized only at the physical provider boundary. Summary
    selection retains the original references; it does not copy image bytes
    into replacement state. [selecting_a_summary_preserves_each_original_image]
    is the corresponding selection requirement. Vault availability and provider
    image capability remain separate physical and protocol obligations.
    [tests/tool-discovery.test.mjs] exercises the discovery entry and committed
    provider presentation; the catalog theorem above establishes native-tool
    inclusion, not that complete transport behavior. *)

(** ** Reading and search address the original conversation

    Public queries observe the committed world without advancing execution or
    issuing effects. Search is scoped by Project and Work and matches visible
    conversation text. Its positions address the original committed history:
    hidden context records still occupy positions. Pagination continues after
    the delivered prefix, so a user can open the original message and resume a
    search without renumbering history after filtering. *)
From Selvedge.Kernel Require Queries PacketProofs SearchProofs.
Export Queries(read_task).
Export PacketProofs(actual_query_preserves_world_and_emits_no_effect).
Export SearchProofs(rejected_scope_contributes_no_history,
  a_matching_visible_record_has_its_original_position,
  a_delivered_prefix_leaves_exactly_the_next_page).

(** ** Adaptive reasoning uses an admitted, finite choice

    An adaptive profile requests its evaluator when it has no active lease.
    The result must select a supported reasoning effort and a duration admitted
    by the frozen policy. Each actual generation consumes one lease step.
    An explicit settings change supersedes the judgment made for the previous
    execution configuration. [task_settings_revoke_a_reasoning_lease] retires
    that lease, so the next adaptive generation requests a new evaluation.
    Repeating the current settings adds no settings record and keeps its lease.
    The retained owner, effort and remaining count reconstruct that lease;
    an extra marker distinguishing evaluation from generation supplies no input
    to that calculation. It records the lease and any changed effort. Absence of retained output
    does not itself establish a failed request; model completion, cancellation
    and recovery report their observed outcomes. A changed effort precedes the
    lease record, whose ordinary provider input begins that generation after
    the control update. No synthetic failure is needed to create an input item.
    Compaction and settings changes require a fresh update even when the
    selected effort string is unchanged. That later update selects the current
    effort without deleting earlier updates from ordinary history replay.
    Evaluation failure is recorded; with no queued input the Task becomes idle
    instead of inventing an effort or issuing an unsupported model request.
    The evaluator's judgment quality is a provider observation. *)
Export ReasoningProofs(an_adaptive_profile_without_a_lease_requests_its_evaluator,
  task_settings_revoke_a_reasoning_lease,
  a_supported_evaluator_choice_continues_the_running_task,
  a_ready_evaluator_choice_has_a_supported_frozen_duration,
  actual_model_generation_consumes_one_lease_step,
  a_generation_after_compaction_restates_its_effort,
  a_generation_after_settings_restates_its_effort,
  failed_reasoning_with_no_queued_input_is_idle).

(** The evaluator supplies HTTP text. Both admission and successful delivery
    constrain that same parsed entry: an admitted model/provider and supported
    effort/lease must produce the requested decision. A theorem about a separate
    pre-parsed input would not constrain the response path used by the host. *)
From Selvedge.Adapters Require ApiProofs.
Export ApiProofs(public_evaluator_authorizes_only_configured_decision,
  public_evaluator_accepts_configured_decision,
  public_evaluator_request_preserves_tool_output_excerpt).
