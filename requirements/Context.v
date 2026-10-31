(** * Recorded context and bounded model input

    A user must be able to inspect the content supplied to a Task and recover
    that work without depending on today's mutable instructions. Retained
    history is the authority for model input. A provider encoding may translate
    it, but cannot add privately refreshed instructions or turn an audit record
    into an instruction. *)

From Selvedge.Kernel Require ContextProofs ReasoningProofs
  ModelRequestConstructionProofs HistoryRoleProofs.
Export ContextProofs(context_history_reconstructs_each_accepted_change,
  an_observed_amendment_matches_its_baseline_and_patch,
  failed_context_observation_retains_the_last_admitted_binding).
Export ReasoningProofs(the_actual_scheduler_observes_before_preparing_a_model,
  context_requests_capture_the_current_history_revision,
  actual_model_requests_retain_the_complete_committed_history).
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

    Source failures retain the last admitted binding. A tool's ordinary file
    read is not automatically an instruction update, and observing instruction
    text cannot grant workspace or tool authority. [ContextTypes.definition]
    shares identity, fields, scope and observation declarations across admission
    and provider translation. New uses of existing observation operations reuse
    that language; new physical observations still need an interpreter.

    [the_actual_scheduler_observes_before_preparing_a_model] binds this order
    to the scheduler. Model and evaluator requests capture current history and
    an admitted profile choice. [every_frozen_model_is_supported_by_its_frozen_profile]
    and [captured_history_cannot_reselect_the_model] are properties of the
    source-indexed selection, not comparisons with a duplicate model field.
    Final comparisons against a subsequently changed Task remain necessary.
    Evaluator judgments and their quality remain external observations; their
    previews are bounded and omit private provider continuations. *)

From Selvedge.Kernel Require ContextSelectionProofs ModelRequestProofs.
From Selvedge.Features Require CompactionProofs.
Export ContextSelectionProofs(adoption_keeps_the_original_history,
  selected_replacement_keeps_the_exact_suffix,
  portable_replacement_keeps_the_exact_suffix,
  another_scope_cannot_select_native_context,
  an_unresolved_captured_call_cannot_be_compacted).
Export CompactionProofs(measured_scope_and_reserve_reach_the_executed_request,
  manual_compaction_captures_context_before_any_summary_request,
  a_compaction_failure_is_not_immediately_resubmitted).
Export ModelRequestProofs(selected_model_request_uses_the_measured_scope,
  unselected_model_request_uses_portable_context,
  evaluator_history_obeys_its_transport_budget,
  encrypted_provider_payload_cannot_affect_public_preview).

(** ** Replacement input preserves its independent source

    Retaining original records and selecting a smaller provider window have
    different purposes. [adoption_keeps_the_original_history] makes adoption
    append-only. [selected_replacement_keeps_the_exact_suffix] and
    [portable_replacement_keeps_the_exact_suffix] constrain the actual selected
    replacement plus records added after its captured span. Incompatible native
    scope cannot authorize selection; readable originals remain available for
    a portable rebuild. Fixed tracked context and image references retain their
    distinct roles when ordinary dialogue is summarized.

    A ticket identifies a request, but does not establish that its measurement
    still describes the current history, settings, tool capabilities or suffix.
    Compaction therefore retains its captured typed input across measurement,
    preparation and validation. [measured_scope_and_reserve_reach_the_executed_request]
    connects the measurement to the request actually sent. Manual compaction
    first uses the same context-observation operation as inference. Unresolved
    captured calls cannot be discarded before their outputs arrive.

    Compaction has its own feature state so preparatory work can coexist with
    ordinary execution. Each physical invocation receives a fresh ticket;
    retained useful-work revision and failure state prevent idle reissuance.
    [a_compaction_failure_is_not_immediately_resubmitted] excludes treating
    every failure as permission to repeat. Recovery retires pending receivers
    while retaining the Task's actual inference demand.

    Provider token counts, endpoint scope, clocks and summary fidelity are
    observations, not static facts supplied by a budget type. A token window
    does not bound the escaped JSON transport. Complete encoded requests and
    carried summary metadata must fit their actual byte budgets; bounded
    fragment processing must not assume that the whole source fits another
    model. No fallback is allowed to silently discard original history. *)

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
    Evaluation failure is recorded; with no queued input the Task becomes idle
    instead of inventing an effort or issuing an unsupported model request.
    The evaluator's judgment quality is a provider observation. *)
Export ReasoningProofs(an_adaptive_profile_without_a_lease_requests_its_evaluator,
  a_supported_evaluator_choice_continues_the_running_task,
  a_ready_evaluator_choice_has_a_supported_frozen_duration,
  actual_model_generation_consumes_one_lease_step,
  failed_reasoning_with_no_queued_input_is_idle).
