import Base
import ./typography.bend as T
import ./typography-laws.bend as TypographyLaws
import ./space-laws.bend as SpaceLaws
import ./font-observation.bend as F
import ./font-observation-laws.bend as FontLaws
import ./viewport-space.bend as ViewportSpace
import ./viewport-space-laws.bend as ViewportSpaceLaws
import ./fact-content-laws.bend as FactContentLaws
import ./request-laws.bend as RequestLaws
import ./laws.bend as Interaction
import ./render-laws.bend as Rendering
import ./layout-laws.bend as LayoutLaws
import ./appearance-laws.bend as AppearanceLaws
import ./surface-laws.bend as SurfaceLaws
import ./enclosure-laws.bend as EnclosureLaws
import ./frame-relation-laws.bend as FrameRelationLaws
import ./enclosure-render-laws.bend as EnclosureRenderLaws
import ./surface-render-laws.bend as SurfaceRenderLaws
import ./presentation-laws.bend as PresentationLaws
import ./presentation-order-laws.bend as PresentationOrderLaws
import ./control-laws.bend as ControlLaws
import ./control-content-laws.bend as ControlContentLaws
import ../core/user-experience-laws.bend as UserExperienceLaws
import ./browser-laws.bend as BrowserLaws
import ./dismissal-laws.bend as DismissalLaws
import ./persistent-trigger-laws.bend as PersistentTriggerLaws
import ./renderer-laws.bend as RendererLaws
import ./page-region-laws.bend as PageRegionLaws
import ./visibility.bend as Visibility
import ./focus.bend as Focus
import ./reading.bend as Reading
import ./form-input-laws.bend as FormInputLaws
import ./dock-laws.bend as DockLaws
import ./card-destination-laws.bend as CardDestinationLaws
import ./board-spatial-laws.bend as BoardSpatialLaws
import ./shell-spatial-laws.bend as ShellSpatialLaws
import ./dialog-spatial-laws.bend as DialogSpatialLaws
import ./context-control-laws.bend as ContextControlLaws
import ./project-presentation-laws.bend as ProjectPresentationLaws
import ./execution-presentation-laws.bend as ExecutionPresentationLaws
import ./directory-entry-laws.bend as DirectoryEntryLaws
import ./focus-retention-laws.bend as FocusRetentionLaws
import ./submission-feedback-laws.bend as SubmissionFeedbackLaws

# These witnesses bind interaction, rendered geometry, and the complete
# prescribed presentation to the Web model.
def persistent_trigger_evidence() -> PersistentTriggerLaws.Requirements:
  PersistentTriggerLaws.evidence()

type Realization is Type:
  Realization{typography: TypographyLaws.Requirements, font_stale: @+state: F.State -> @+received: Nat -> @+metrics: +List<T.Metric> -> @different: {Nat.is_eq(F.generation(state), received) == False{} : Bool} -> {F.accept(state, F.Observation{received, metrics}) == state : F.State},
    font_ready_duplicate: @+generation: Nat -> @+scale: T.Scale -> @+body: T.Metric -> @received: Nat -> @metrics: +List<T.Metric> -> {F.accept(F.Ready{generation, scale, body}, F.Observation{received, metrics}) ==
    F.Ready{generation, scale, body} : F.State},
    font_failed_duplicate: @+generation: Nat -> @+scale: T.Scale -> @received: Nat -> @metrics: +List<T.Metric> -> {F.accept(F.Failed{generation, scale}, F.Observation{received, metrics}) ==
    F.Failed{generation, scale} : F.State},
    font_current_pending: @+generation: Nat -> @+scale: T.Scale -> @+received: Nat -> @+metrics: +List<T.Metric> -> @owned: {Nat.is_eq(generation, received) == True{} : Bool} -> {F.accept(F.Pending{generation, scale}, F.Observation{received, metrics}) ==
    F.admit(generation, scale, metrics) : F.State},
    font_received_success: @+generation: Nat -> @+scale: T.Scale -> @+received: Nat -> @+metric: T.Metric -> @owned: {Nat.is_eq(generation, received) == True{} : Bool} -> @valid: {T.valid_body(metric) == True{} : Bool} -> {F.accept(F.Pending{generation, scale}, F.Observation{received, [metric]}) ==
    F.Ready{generation, scale, metric} : F.State},
    font_received_invalid: @+generation: Nat -> @+scale: T.Scale -> @+received: Nat -> @+metric: T.Metric -> @owned: {Nat.is_eq(generation, received) == True{} : Bool} -> @bad: {T.valid_body(metric) == False{} : Bool} -> {F.accept(F.Pending{generation, scale}, F.Observation{received, [metric]}) ==
    F.Failed{generation, scale} : F.State},
    font_received_empty: @+generation: Nat -> @+scale: T.Scale -> @+received: Nat -> @owned: {Nat.is_eq(generation, received) == True{} : Bool} -> {F.accept(F.Pending{generation, scale}, F.Observation{received, Nil{}}) ==
    F.Failed{generation, scale} : F.State},
    font_received_multiple: @+generation: Nat -> @+scale: T.Scale -> @+received: Nat -> @+first: T.Metric -> @+second: T.Metric -> @+rest: +List<T.Metric> -> @owned: {Nat.is_eq(generation, received) == True{} : Bool} -> {F.accept(F.Pending{generation, scale}, F.Observation{received, Con{first, Con{second, rest}}}) ==
    F.Failed{generation, scale} : F.State},
    font_received_valid: @+generation: Nat -> @+scale: T.Scale -> @+received: Nat -> @+metrics: +List<T.Metric> -> @owned: {Nat.is_eq(generation, received) == True{} : Bool} -> {FontLaws.ready_valid(F.accept(F.Pending{generation, scale}, F.Observation{received, metrics})) == True{} : Bool},
    font_retag_scale: @state: F.State -> @generation: Nat -> {F.scale(F.retag(state, generation)) == F.scale(state) : T.Scale},
    font_retag_body: @state: F.State -> @generation: Nat -> {F.body(F.retag(state, generation)) == F.body(state) : Maybe<&2, T.Metric>},
    font_retag_pending: @state: F.State -> @generation: Nat -> {F.pending(F.retag(state, generation)) == F.pending(state) : Bool},
    font_retag_generation: @state: F.State -> @generation: Nat -> {F.generation(F.retag(state, generation)) == generation : Nat},
    font_retag_pending_variant: @old: Nat -> @generation: Nat -> @scale: T.Scale -> {F.retag(F.Pending{old, scale}, generation) == F.Pending{generation, scale} : F.State},
    font_retag_ready_variant: @old: Nat -> @generation: Nat -> @scale: T.Scale -> @body: T.Metric -> {F.retag(F.Ready{old, scale, body}, generation) == F.Ready{generation, scale, body} : F.State},
    font_retag_failed_variant: @old: Nat -> @generation: Nat -> @scale: T.Scale -> {F.retag(F.Failed{old, scale}, generation) == F.Failed{generation, scale} : F.State},
    font_pending_request: @generation: Nat -> @scale: T.Scale -> {F.request(F.Pending{generation, scale}) == F.Plan{generation,
    [T.spec(T.Probe{"@font/body", "0", T.resolved(T.Presentation{T.Body{}, T.Regular{}, scale}),
      T.WrapWords{}, None{}, "0"})]} : F.Plan},
    font_ready_request: @generation: Nat -> @scale: T.Scale -> @metric: T.Metric -> {F.request(F.Ready{generation, scale, metric}) == F.Plan{generation, Nil{}} : F.Plan},
    font_failed_request: @generation: Nat -> @scale: T.Scale -> {F.request(F.Failed{generation, scale}) == F.Plan{generation, Nil{}} : F.Plan},
    font_begin_scale: @generation: Nat -> @root: Nat -> {F.begin(generation, root) == F.Pending{generation,
    T.Scale{Nat.sub(Nat.max(1000n, Nat.div(root, 16n)), 1000n)}} : F.State},
    viewport_space: ViewportSpaceLaws.Requirements,
    fact_contents: FactContentLaws.Requirements, directory_picker: DirectoryEntryLaws.PickerRequirements, requests: RequestLaws.Requirements, interaction: Interaction.Requirements, rendering: Rendering.Requirements,
    layout: LayoutLaws.Requirements, appearance: AppearanceLaws.Requirements, surfaces: SurfaceLaws.Requirements, enclosures: EnclosureLaws.Requirements, frame_relations: FrameRelationLaws.Requirements, enclosure_rendering: EnclosureRenderLaws.Requirements, surface_rendering: SurfaceRenderLaws.Requirements,
    presentation: PresentationLaws.Requirements, presentation_order: PresentationOrderLaws.Requirements,
    controls: ControlLaws.Requirements, control_contents: ControlContentLaws.Requirements,
    commands: UserExperienceLaws.CommandRequirements, browser: BrowserLaws.Requirements, persistent_trigger: PersistentTriggerLaws.Requirements, dismissal: DismissalLaws.Requirements, renderer: RendererLaws.Requirements, page_regions: PageRegionLaws.Requirements, visibility: Visibility.Requirements,
    focus_cycle: Focus.CycleRequirements, scroll_ownership: Reading.ScrollOwnershipRequirements,
    form_inputs: FormInputLaws.Requirements, dock: DockLaws.Requirements, card_destinations: CardDestinationLaws.Requirements,
    board_space: BoardSpatialLaws.Requirements, shell_space: ShellSpatialLaws.Requirements, dialog_space: DialogSpatialLaws.Requirements,
    context_controls: ContextControlLaws.Requirements, project_presentation: ProjectPresentationLaws.Requirements,
    execution_presentation: ExecutionPresentationLaws.Requirements, directory_entry: DirectoryEntryLaws.Requirements, focus_retention: FocusRetentionLaws.Requirements, submission_feedback: SubmissionFeedbackLaws.Requirements}

def realization() -> Realization:
  Realization{TypographyLaws.evidence(), FontLaws.stale, FontLaws.ready_duplicate, FontLaws.failed_duplicate, FontLaws.current_pending, FontLaws.received_success, FontLaws.received_invalid, FontLaws.received_empty, FontLaws.received_multiple, FontLaws.received_valid, FontLaws.retag_scale, FontLaws.retag_body, FontLaws.retag_pending, FontLaws.retag_generation, FontLaws.retag_pending_variant, FontLaws.retag_ready_variant, FontLaws.retag_failed_variant, FontLaws.pending_request, FontLaws.ready_request, FontLaws.failed_request, FontLaws.begin_scale, ViewportSpaceLaws.evidence(), FactContentLaws.evidence(), DirectoryEntryLaws.picker_requirements(), RequestLaws.evidence(), Interaction.evidence(), Rendering.evidence(), LayoutLaws.evidence(),
    AppearanceLaws.evidence(), SurfaceLaws.evidence(), EnclosureLaws.evidence(), FrameRelationLaws.evidence(), EnclosureRenderLaws.evidence(), SurfaceRenderLaws.evidence(), PresentationLaws.evidence(), PresentationOrderLaws.evidence(), ControlLaws.evidence(), ControlContentLaws.evidence(),
    UserExperienceLaws.command_evidence(), BrowserLaws.evidence(), persistent_trigger_evidence(), DismissalLaws.evidence(), RendererLaws.evidence(), PageRegionLaws.evidence(), Visibility.evidence(),
    Focus.cycle_evidence(), Reading.scroll_ownership_evidence(),
    FormInputLaws.evidence(), DockLaws.evidence(), CardDestinationLaws.evidence(),
    BoardSpatialLaws.evidence(), ShellSpatialLaws.evidence(), DialogSpatialLaws.evidence(), ContextControlLaws.evidence(), ProjectPresentationLaws.evidence(), ExecutionPresentationLaws.evidence(), DirectoryEntryLaws.evidence(), FocusRetentionLaws.evidence(), SubmissionFeedbackLaws.evidence()}
