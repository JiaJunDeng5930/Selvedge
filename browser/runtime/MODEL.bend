import ../layout/PROGRAM.bend as Allocation
import ../layout/anchor-geometry.bend as AnchorGeometry
import ./native-fields.bend as NativeFields
import ../layout/physical-space.bend as Space
import ../document/RENDERED.bend as Rendered
import ../document/code-observation.bend as CodeObservation
import Base
import ./frontend-utility.bend as Utility
import ../document/FRAME.bend as SourceFrame
import ../../interaction/IDENTITY.bend as UIIdentity
import ./SEMANTICS.bend as Legacy
import ../MODEL.bend as Web
import ./PLATFORM.bend as Platform
import ../document/MODEL.bend as Doc
import ../layout/MODEL.bend as World
import ../layout/physical-plan.bend as Plan
import ../layout/CONTENT.bend as Content
import ../layout/RENDERER.bend as Renderer
import ../layout/physical-probe.bend as Probe
import ../controls/SHELL.bend as Shell
import ../document/SOURCE.bend as Source
import ../layout/GEOMETRY.bend as Spatial
import ../appearance/DESIGN.bend as Design
import ../appearance/FONT.bend as F
import ../appearance/TYPOGRAPHY.bend as T
import ../appearance/PROGRAM.bend as Paint
import ../layout/natural-size.bend as NaturalSize
import ../document/presentation-order.bend as Order
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/STATE.bend as Core
import ../focus/MODEL.bend as Focus
import ../../harness/MODEL.bend as M
import ../editor/MODEL.bend as Editor
import ../reading/MODEL.bend as Reading
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/conversation/CODE.bend as Code
import ../../interaction/session/MODEL.bend as E
import ../../interaction/MODEL.bend as Product
import ../../bendlib/json.bend as J
type MeasurementTicket is Data:
  MeasurementTicket{generation: Nat, round: Nat}
type MeasurementRequest is Data:
  MeasurementRequest{ticket: MeasurementTicket, plan: Plan.Plan}
type Lifecycle is Data:
  WaitingEnvironment{}
  WaitingFont{}
  Measuring{candidate_index: Nat, capacity: View.Capacity, engine: World.Engine, semantic: InterfaceView.Surface, round: Nat}
  Displaying{capacity: View.Capacity, engine: World.Engine, semantic: InterfaceView.Surface}
  UtilityMeasuring{purpose: Utility.Purpose, engine: World.Engine, round: Nat, glyph_only: Bool}
  UtilityDisplaying{purpose: Utility.Purpose, engine: World.Engine}
  UtilityRejected{problem: String}
  Blocked{problem: String}
type Published is Data:
  Published{world: Content.AllocatedWorld, semantic: InterfaceView.Surface, scope: Focus.Scope,
    basis: NativeFields.Basis, frame: Maybe<&2, Rendered.Frame>}
type State is Data:
  State{legacy: Legacy.State, generation: Nat, anchors: +List<Shell.Anchor>, lifecycle: Lifecycle,
    displayed: Maybe<&2, Published>}
def generation(state: State) -> Nat:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed} = state
  value_generation

def anchors(state: State) -> +List<Shell.Anchor>:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed} = state
  value_anchors

def lifecycle(state: State) -> Lifecycle:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed} = state
  value_lifecycle

def displayed(state: State) -> Maybe<&2, Published>:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed} = state
  value_displayed

def with_lifecycle(value: Lifecycle, state: State) -> State:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed} = state
  State{value_legacy, value_generation, value_anchors, value, value_displayed}

def with_displayed(value: Maybe<&2, Published>, state: State) -> State:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed} = state
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value}

type RenderInspection is Data:
  RenderInspection{frame: Maybe<&2, Rendered.Frame>, expected_tabs: Maybe<&2, +List<String>>,
    native_valid: Maybe<&2, Bool>, current_layer: Maybe<&2, String>, dismiss_target: Maybe<&2, Legacy.DismissTarget>}
type Publication is Data:
  KeepPublished{fields: +List<NativeFields.Update>}
  Publish{generation: Nat, document: Doc.Document, fields: +List<NativeFields.Update>}
type Decision is Data:
  Decision{state: State, effects: +List<Legacy.Effect>}
type KeyResult is Data:
  KeyResult{handled: Bool, decision: Decision}
type Search is Data:
  Searching{index: Nat, state: State}
  Stopped{decision: Decision}
type OutsideDecision is Data:
  OutsideDecision{handled: Bool, decision: Decision}
def realization_frame(realization: Rendered.State) -> Maybe<&2, Rendered.Frame>:
  match realization:
    case Rendered.AwaitingFrame{generation}: None{}
    case Rendered.Realized{generation, frame}: Some{frame}
    case Rendered.Unmet{generation, frame, violations}: Some{frame}

def inspect_frame(frame: Maybe<&2, Rendered.Frame>, +active: +List<InterfaceView.Node>, +layer: Maybe<&2, String>, +dismiss: Maybe<&2, Legacy.DismissTarget>) -> RenderInspection:
  match frame:
    case None{}: RenderInspection{None{}, None{}, None{}, layer, dismiss}
    case Some{+observed}:
      Rendered.Frame{viewport, elements, focused, tabs, native_focus} = observed
      RenderInspection{Some{observed}, Some{Rendered.expected_tabs(active, elements, native_focus)},
        Some{Rendered.native_valid(native_focus, active, elements)}, layer, dismiss}

def inspect_published(frame: Maybe<&2, Rendered.Frame>, +layer: Maybe<&2, String>, displayed: Maybe<&2, Published>) -> RenderInspection:
  match displayed:
    case None{}: RenderInspection{frame, None{}, None{}, layer, None{}}
    case Some{Published{world, semantic, scope, basis, published_frame}}:
      +active = InterfaceView.active_nodes(semantic)
      +dismiss = Legacy.dismiss_target(active)
      inspect_frame(frame, active, layer, dismiss)

def utility_owned(state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case Some{Published{Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}: Utility.owned(source)
    case None{}: False{}

def utility_inspection(displayed: Maybe<&2, Published>) -> RenderInspection:
  match displayed:
    case None{}: RenderInspection{None{}, None{}, None{}, None{}, None{}}
    case Some{Published{+world, semantic, scope, basis, frame}}:
      RenderInspection{frame, Some{SourceFrame.tabs(SourceFrame.expected(world))}, Some{SourceFrame.no_native(world)}, None{}, None{}}

def render_inspection_owned(utility: Bool, +stored: Legacy.State, +displayed: Maybe<&2, Published>) -> RenderInspection:
  match utility:
    case True{}: utility_inspection(displayed)
    case False{}:
      +observed_web_1 = Legacy.web(stored)
      +realization = Web.realization(observed_web_1)
      inspect_published(realization_frame(realization), Legacy.current_layer_key(stored), displayed)

def utility_rejected(lifecycle: Lifecycle) -> Bool:
  match lifecycle:
    case UtilityRejected{reason}: True{}
    case _: False{}

def auxiliary_owned(+state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  utility_owned(state) || utility_rejected(lifecycle)

def render_inspection(+state: State) -> RenderInspection:
  State{stored, serial, anchors, lifecycle, displayed} = state
  render_inspection_owned(auxiliary_owned(state), stored, displayed)

def pending_frame_effects_for(lifecycle: Lifecycle, realization: Rendered.State, displayed: Maybe<&2, Published>) -> +List<Legacy.Effect>:
  match lifecycle:
    case Displaying{capacity, engine, semantic}:
      match realization:
        case Rendered.AwaitingFrame{generation}:
          match displayed:
            case Some{Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
              [Legacy.BrowserEffect{Web.MeasureFrame{physical_generation}}]
            case None{}: Nil{}
        case _: Nil{}
    case UtilityDisplaying{purpose, engine}:
      match displayed:
        case Some{Published{Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}, semantic, scope, basis, None{}}}: [Legacy.BrowserEffect{Web.MeasureFrame{generation}}]
        case _: Nil{}
    case _: Nil{}

def pending_frame_effects(+state: State) -> +List<Legacy.Effect>:
  State{+observed_state_1, serial, anchors, lifecycle, displayed} = state
  +observed_web_2 = Legacy.web(observed_state_1)
  +realization = Web.realization(observed_web_2)
  pending_frame_effects_for(lifecycle, realization, displayed)

def with_generation(value: Nat, state: State) -> State:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed} = state
  State{value_legacy, value, value_anchors, value_lifecycle, value_displayed}

def with_legacy(value: Legacy.State, state: State) -> State:
  State{value_legacy, value_generation, value_anchors, value_lifecycle, value_displayed} = state
  State{value, value_generation, value_anchors, value_lifecycle, value_displayed}

def initial(+program: M.World(), +sequence: Nat) -> State:
  State{Legacy.initial(program, sequence), 0n, Nil{}, WaitingEnvironment{}, None{}}

def legacy(+state: State) -> Legacy.State:
  State{value, generation, anchors, lifecycle, displayed} = state
  value

def candidate(+index: Nat) -> View.Capacity:
  match index:
    case 0n: View.Capacity{True{}, True{}}
    case 1n: View.Capacity{True{}, False{}}
    case 2n: View.Capacity{False{}, True{}}
    case _: View.Capacity{False{}, False{}}

def semantic_surface(+capacity: View.Capacity, +state: Legacy.State) -> InterfaceView.Surface:
  Legacy.semantic_surface(capacity, state)

def published(+world: Content.AllocatedWorld, +capacity: View.Capacity, +state: Legacy.State, +semantic: InterfaceView.Surface) -> Published:
  Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies} = world
  Published{world, semantic, Focus.realized_scope(semantic, Legacy.active_focus_scope(state)), NativeFields.basis([source], semantic), None{}}

def admitted(+decision: Legacy.Decision, +world: Content.AllocatedWorld, +capacity: View.Capacity, +engine: World.Engine, +serial: Nat, +anchors: +List<Shell.Anchor>, +semantic: InterfaceView.Surface) -> Decision:
  Legacy.Decision{+accepted, collected} = decision
  Decision{State{accepted, serial, anchors, Displaying{capacity, engine, semantic}, Some{published(world, capacity, accepted, semantic)}}, collected}

def current_legacy_surface(+state: Legacy.State) -> InterfaceView.Surface:
  +observed_web_1 = Legacy.web(state)
  +observed_application_2 = Web.application(observed_web_1)
  +observed_platform_3 = Platform.platform(observed_application_2)
  editors = Platform.editors(observed_platform_3)
  +capacity = Platform.capacity(observed_platform_3)
  Legacy.semantic_surface(capacity, state)

def current_surface(+state: State) -> InterfaceView.Surface:
  current_legacy_surface(legacy(state))

def published_world(value: Published) -> Content.AllocatedWorld:
  Published{world, semantic, scope, basis, frame} = value
  world

def native_updates(+state: State) -> +List<NativeFields.Update>:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case None{}: Nil{}
    case Some{Published{world, semantic, scope, basis, frame}}: NativeFields.updates(basis, current_surface(state))

def field_owned(+key: String, +state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case None{}: False{}
    case Some{Published{world, semantic, scope, basis, frame}}: NativeFields.field_owned(basis, key, current_surface(state))

def admit(+world: Content.AllocatedWorld, +capacity: View.Capacity, +engine: World.Engine, +state: State, +semantic: InterfaceView.Surface) -> Decision:
  State{+observed_state_1, serial, anchors, lifecycle, displayed} = state
  +observed_web_2 = Legacy.web(observed_state_1)
  +observed_application_3 = Web.application(observed_web_2)
  +core = Platform.core(observed_application_3)
  +platform = Platform.platform(observed_application_3)
  +generation = Web.generation(observed_web_2)
  +environment = Web.environment(observed_web_2)
  +font = Web.typography(observed_web_2)
  +sequence = Legacy.sequence(observed_state_1)
  +ticket = Legacy.next_ticket(observed_state_1)
  +pending = Legacy.pending(observed_state_1)
  +receipt = Legacy.receipt(observed_state_1)
  +decision = Platform.reflow_capacity(Platform.Decision{Platform.unchanged(core), platform, Nil{}}, capacity)
  admitted(Legacy.finish(Web.production_commit(decision, generation, environment, font), sequence, ticket, pending, "", receipt), world, capacity, engine, serial, anchors, semantic)

def display_ready(+state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case Displaying{capacity, engine, semantic}: True{}
    case UtilityDisplaying{purpose, engine}: True{}
    case _: False{}

def displayed_generation(+state: State) -> Nat:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case None{}: 0n
    case Some{Published{Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}: generation

def realization_status(realization: Rendered.State) -> String:
  match realization:
    case Rendered.AwaitingFrame{generation}: "awaiting-frame"
    case Rendered.Realized{generation, frame}: "ready"
    case Rendered.Unmet{generation, frame, violations}: "unmet"

def legacy_render_status(+state: Legacy.State) -> String:
  +observed_web_1 = Legacy.web(state)
  +realization = Web.realization(observed_web_1)
  realization_status(realization)

def utility_render_status(displayed: Maybe<&2, Published>) -> String:
  match displayed:
    case Some{Published{world, semantic, scope, basis, Some{frame}}}: "ready"
    case _: "awaiting-frame"

def render_status(+state: State) -> String:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case Displaying{capacity, engine, semantic}: legacy_render_status(legacy)
    case UtilityDisplaying{purpose, engine}: utility_render_status(displayed)
    case UtilityRejected{reason}: "blocked"
    case Blocked{reason}: "blocked"
    case _: "waiting"

def realization_violations(realization: Rendered.State) -> +List<Rendered.Violation>:
  match realization:
    case Rendered.Unmet{generation, frame, violations}: violations
    case _: Nil{}

def render_violations(+state: State) -> +List<Rendered.Violation>:
  realization_violations(Web.realization(Legacy.web(legacy(state))))

def measurement_request_plan(plan: Plan.Plan, generation: Nat, round: Nat) -> Maybe<&2, MeasurementRequest>:
  match plan:
    case Plan.Awaiting{plan_generation, first, remaining}:
      Some{MeasurementRequest{MeasurementTicket{generation, round}, Plan.Awaiting{plan_generation, first, remaining}}}
    case other: None{}

def measurement_request(+state: State) -> Maybe<&2, MeasurementRequest>:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case Measuring{index, capacity, +engine, semantic, round}:
      measurement_request_plan(World.plan(engine), World.snapshot_generation(World.snapshot(engine)), round)
    case UtilityMeasuring{purpose, +engine, round, glyph_only}:
      measurement_request_plan(World.plan(engine), World.snapshot_generation(World.snapshot(engine)), round)
    case other: None{}

def application_document(nodes: +List<Doc.Node>) -> Doc.Document:
  Doc.Document{Doc.Element{"@browser/application", "div", [Doc.Property{"class", "native-application"}], Nil{}, Nil{}, nodes}, "Selvedge"}

def observed_lifecycle_at(+capacity: Nat, +lifecycle: Lifecycle, +displayed: Maybe<&2, Published>, +font: T.Presentation) -> Doc.Document:
  match displayed:
    case Some{world}: application_document(Renderer.nodes(published_world(world)))
    case None{}: application_document(Nil{})

def observed_lifecycle(+lifecycle: Lifecycle, +displayed: Maybe<&2, Published>, +font: T.Presentation) -> Doc.Document:
  observed_lifecycle_at(NaturalSize.limit(), lifecycle, displayed, font)

def observed(+displayed: Maybe<&2, Published>, +lifecycle: Lifecycle, +font: T.Presentation) -> Doc.Document:
  observed_lifecycle(lifecycle, displayed, font)

def observe(+capacity: Nat, +state: State) -> Doc.Document:
  State{+legacy, serial, anchors, lifecycle, displayed} = state
  +observed_web_1 = Legacy.web(legacy)
  +font = Web.typography(observed_web_1)
  observed_lifecycle_at(capacity, lifecycle, displayed, T.Presentation{T.Body{}, T.Regular{}, F.scale(font)})

def published_document_at(+capacity: Nat, ready: Bool, +state: State) -> Publication:
  match ready:
    case True{}: Publish{displayed_generation(state), observe(capacity, state), native_updates(state)}
    case False{}: Publish{0n, observe(capacity, state), native_updates(state)}

def publication_policy_at(+capacity: Nat, existing: Bool, +ready: Bool, current: Bool, state: State) -> Publication:
  match existing ready current:
    case True{} False{} _: KeepPublished{native_updates(state)}
    case True{} True{} True{}: KeepPublished{native_updates(state)}
    case _ _ _: published_document_at(capacity, ready, state)

def publication_lifecycle_at(+capacity: Nat, lifecycle: Lifecycle, existing: Bool, ready: Bool, current: Bool, state: State) -> Publication:
  match lifecycle:
    case UtilityRejected{problem}: published_document_at(capacity, False{}, state)
    case Blocked{problem}: publication_policy_at(capacity, existing, ready, current, state)
    case other: publication_policy_at(capacity, existing, ready, current, state)

def publication_for_at(+capacity: Nat, existing: Bool, ready: Bool, current: Bool, +state: State) -> Publication:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  publication_lifecycle_at(capacity, lifecycle, existing, ready, current, state)

def publication(+capacity: Nat, +last_published: Nat, +state: State) -> Publication:
  publication_for_at(capacity, Bool.not(Nat.is_eq(last_published, 0n)), display_ready(state),
    Nat.is_eq(displayed_generation(state), last_published), state)

def publication_focus_loss(confirmed: Bool, ticket: Nat, before: Focus.Target) -> Maybe<&2, Platform.Input>:
  match confirmed:
    case True{}: Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}}
    case False{}: None{}

def publication_focus_feedback(+publication: Publication, ticket: Nat, before: Maybe<&2, Focus.Target>, after: Maybe<&2, Focus.Target>) -> Maybe<&2, Platform.Input>:
  match publication before after:
    case Publish{generation, document, fields} Some{target} None{}:
      publication_focus_loss(Bool.not(Nat.is_eq(generation, 0n)), ticket, target)
    case _ _ _: None{}

def probe_document(+job: Plan.Job) -> Doc.Document: Probe.document(job)

def probe_target_keys(+job: Plan.Job) -> +List<String>: Probe.target_keys(job)

def decision_state(value: Decision) -> State:
  Decision{state, effects} = value
  state

def visible_anchor(environment: Design.Environment, left: AnchorGeometry.Origin, top: AnchorGeometry.Origin, width: Nat, height: Nat) -> Spatial.Box:
  Design.Environment{Design.Viewport{viewport_width, viewport_height}, dark, root} = environment
  AnchorGeometry.visible(left, top, width, height, viewport_width, viewport_height)

def capture_anchor(key: String, left: AnchorGeometry.Origin, top: AnchorGeometry.Origin, width: Nat, height: Nat, +state: State) -> Decision:
  State{+legacy, serial, anchors, lifecycle, displayed} = state
  bounds = visible_anchor(Web.environment(Legacy.web(legacy)), left, top, width, height)
  Decision{State{legacy, serial, Shell.Anchor{key, bounds} <> anchors, lifecycle, displayed}, Nil{}}

def legacy_focus_ticket(+state: Legacy.State) -> Nat:
  +observed_web_1 = Legacy.web(state)
  +observed_application_2 = Web.application(observed_web_1)
  +observed_platform_3 = Platform.platform(observed_application_2)
  editors = Platform.editors(observed_platform_3)
  +focus_ticket = Platform.focus_ticket(observed_platform_3)
  focus_ticket

def focus_ticket(+state: State) -> Nat:
  legacy_focus_ticket(legacy(state))

def scope_if_rejected(rejected: Bool, +scope: Focus.Scope) -> Focus.Scope:
  match rejected:
    case True{}: Focus.Document{}
    case False{}: scope

def active_scope(+state: State) -> Focus.Scope:
  State{+legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case None{}: scope_if_rejected(utility_rejected(lifecycle), Legacy.active_focus_scope(legacy))
    case Some{Published{world, semantic, scope, basis, frame}}: scope

def empty() -> M.World(): Legacy.empty()

def program(+state: State) -> M.World(): Legacy.program(legacy(state))

def code_key(+source: Code.Source, +ordinal: Nat) -> String: Legacy.code_key(source, ordinal)

def font_budget(+font: F.State) -> Nat:
  match font:
    case F.Pending{generation, scale}: 1n
    case _: 0n

def source_changed(+input: Web.Input) -> Bool:
  match input:
    case Web.FrameObserved{generation, frame}: False{}
    case Web.PlatformInput{Platform.FocusObserved{identity}}: False{}
    case Web.PlatformInput{Platform.FocusApplied{ticket, identity, observed}}: False{}
    case Web.PlatformInput{Platform.PublicationFocusObserved{ticket, before, after}}: False{}
    case Web.PlatformInput{Platform.ReadingInput{task, generation, event}}: False{}
    case Web.PlatformInput{Platform.MotionPreference{reduced}}: False{}
    case _: True{}

def legacy_outside(+identity: String, +stored: Legacy.State) -> Legacy.OutsideDecision:
  Legacy.outside_event(identity, stored)

def append(+first: +List<Legacy.Effect>, +value: Decision) -> Decision:
  Decision{next, later} = value
  Decision{next, List.append(&2, Legacy.Effect, first, later)}

def current_font(+state: Legacy.State) -> F.State:
  +observed_web_1 = Legacy.web(state)
  +font = Web.typography(observed_web_1)
  font

def measurement_plan(+state: State) -> F.Plan:
  F.request(current_font(legacy(state)), Nil{})

def measurement_budget(+state: State) -> Nat:
  font_budget(current_font(legacy(state)))

def semantic_generation(+state: Legacy.State) -> Nat:
  +observed_web_1 = Legacy.web(state)
  +generation = Web.generation(observed_web_1)
  generation

def set_lifecycle(+state: State, lifecycle: Lifecycle) -> State:
  State{legacy, serial, anchors, old, displayed} = state
  State{legacy, serial, anchors, lifecycle, displayed}

def no_candidate(state: State) -> Decision:
  Decision{set_lifecycle(state, Blocked{"The interface does not fit the available space"}), Nil{}}

def retry_candidate(+more: Bool, +index: Nat, +state: State) -> Search:
  match more:
    case True{}: Searching{(index + 1n : Nat), state}
    case False{}: Stopped{no_candidate(state)}

def failure_axis(axis: Allocation.Axis) -> String:
  match axis:
    case Allocation.InlineAxis{}: "width"
    case Allocation.BlockAxis{}: "height"

def failure_reason(reason: Allocation.FailureReason) -> String:
  match reason:
    case Allocation.AuthoredRangeConflict{}: "authored range conflict"
    case Allocation.InsufficientSpace{}: "insufficient space"
    case Allocation.AllocationBoundExceeded{budget}: "allocation bound exceeded (budget " ++ Nat.show(budget) ++ ")"

def failure_message(failure: Allocation.Failure) -> String:
  Allocation.Failure{key, axis, required, available, reason} = failure
  "The interface does not fit the available space: " ++ key ++ "; " ++ failure_axis(axis) ++
    " required " ++ Nat.show(required) ++ "px, available " ++ Nat.show(available) ++ "px; " ++ failure_reason(reason)

def infeasible_candidate(+more: Bool, +index: Nat, +state: State, failure: Allocation.Failure) -> Search:
  match more:
    case True{}: Searching{(index + 1n : Nat), state}
    case False{}: Stopped{Decision{set_lifecycle(state, Blocked{failure_message(failure)}), Nil{}}}

def selected(+outcome: Plan.Plan, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +state: State, +semantic: InterfaceView.Surface, round: Nat) -> Search:
  match outcome:
    case Plan.Ready{world}: Stopped{admit(world, capacity, engine, state, semantic)}
    case Plan.Awaiting{generation, first, remaining}: Stopped{Decision{set_lifecycle(state, Measuring{index, capacity, engine, semantic, round}), Nil{}}}
    case Plan.Invalid{error}: Stopped{Decision{set_lifecycle(state, Blocked{"Physical source or receipt is invalid"}), Nil{}}}
    case Plan.Infeasible{failure}: infeasible_candidate(Nat.is_lt(index, 3n), index, state, failure)

def surface_layers(surface: InterfaceView.Surface) -> +List<View.Layer>:
  InterfaceView.Surface{Core.Scene{View.Scene{navigation, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker}, base, overlays, scope} = surface
  layers

def viewport_box(environment: Design.Environment) -> Spatial.Box:
  Design.Environment{Design.Viewport{width, height}, dark, root} = environment
  Spatial.Box{0n, 0n, width, height}

# Browser feedback participates in the same authored tree and measurements.

def notice(+ticket: Nat, reason: String, +font: T.Presentation) -> Source.Node:
  Source.Box{UIIdentity.entity(UIIdentity.place("@browser"), "unknown", Nat.show(ticket)), Source.Paragraph{},
    Shell.neutral(T.with_tier(font, T.Support{}), Space.Vertical{}, Space.StretchSize{}, Space.NaturalSize{}, Spatial.Stretch{}),
    [Source.RoleAttribute{"status"}],
    [Source.Text{UIIdentity.part(UIIdentity.entity(UIIdentity.place("@browser"), "unknown", Nat.show(ticket)), "text"), "Connection interrupted. Submission status is unknown. " ++ reason,
      Source.ExplicitFont{T.with_tier(font, T.Support{})}, T.WrapWords{}}]}

def notices(entries: +List<Legacy.Pending>, +font: T.Presentation) -> +List<Source.Node>:
  match entries:
    case Nil{}: Nil{}
    case Con{Legacy.Pending{ticket, completion, command, origin, Legacy.OutcomeUnknown{reason}}, rest}: notice(ticket, reason, font) <> notices(rest, font)
    case Con{entry, rest}: notices(rest, font)

def busy_attrs(busy: Bool, attrs: +List<Source.Attribute>) -> +List<Source.Attribute>:
  match busy:
    case True{}: Source.AriaAttribute{"busy", "true"} <> attrs
    case False{}: attrs

def main_children(tag: Source.BoxTag, children: +List<Source.Node>, pending: +List<Legacy.Pending>, font: T.Presentation) -> +List<Source.Node>:
  match tag:
    case Source.Main{}: List.append(&2, Source.Node, children, notices(pending, font))
    case _: children

def feedback_nodes(nodes: +List<Source.Node>, +pending: +List<Legacy.Pending>, +font: T.Presentation) -> +List<Source.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Source.Box{+key, +tag, style, attrs, children}, rest}:
      Source.Box{key, tag, style, busy_attrs(Legacy.busy(pending, UIIdentity.encode(key)), attrs), main_children(tag, feedback_nodes(children, pending, font), pending, font)} <> feedback_nodes(rest, pending, font)
    case Con{Source.Control{+key, tag, style, attrs, name, enabled, first, remaining, children}, rest}:
      Source.Control{key, tag, style, busy_attrs(Legacy.busy(pending, UIIdentity.encode(key)), attrs), name, enabled, first, remaining, feedback_nodes(children, pending, font)} <> feedback_nodes(rest, pending, font)
    case Con{Source.NativeAttachment{+key, target, attrs, style, children}, rest}:
      Source.NativeAttachment{key, target, busy_attrs(Legacy.busy(pending, UIIdentity.encode(key)), attrs), style, feedback_nodes(children, pending, font)} <> feedback_nodes(rest, pending, font)
    case Con{Source.Field{+key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}, rest}:
      Source.Field{key, kind, style, busy_attrs(Legacy.busy(pending, UIIdentity.encode(key)), attrs), value, placeholder, options, policy, name, enabled, first, remaining} <> feedback_nodes(rest, pending, font)
    case Con{Source.RichText{key, style, content, attachments, native_owner}, rest}:
      Source.RichText{key, style, content, feedback_nodes(attachments, pending, font), native_owner} <> feedback_nodes(rest, pending, font)
    case Con{Source.Text{key, value, choice, wrapping}, rest}:
      Source.Text{key, value, choice, wrapping} <> feedback_nodes(rest, pending, font)
    case Con{Source.Glyph{key, drawing, style}, rest}:
      Source.Glyph{key, drawing, style} <> feedback_nodes(rest, pending, font)

def only_root(nodes: +List<Source.Node>, fallback: Source.Node) -> Source.Node:
  match nodes:
    case Nil{}: fallback
    case Con{node, rest}: node

def pending(+state: Legacy.State) -> +List<Legacy.Pending>:
  +entries = Legacy.pending(state)
  entries

def feedback_root(+source: Source.Node, +entries: +List<Legacy.Pending>, +font: T.Presentation) -> Source.Node:
  only_root(feedback_nodes(source <> Nil{}, entries, font), source)

def frozen(+source: Source.Node, +index: Nat, +capacity: View.Capacity, +font: T.Presentation, +viewport: Spatial.Box, +state: State, +semantic: InterfaceView.Surface) -> Search:
  State{legacy, +serial, anchors, lifecycle, displayed} = state
  +engine = World.initial(Content.Snapshot{(serial + 1n : Nat), feedback_root(source, pending(legacy), font), font}, viewport)
  selected(World.plan(engine), index, capacity, engine, State{legacy, (serial + 1n : Nat), anchors, lifecycle, displayed}, semantic, 0n)

def authored(+result: Shell.ShellAuthorship, +index: Nat, +capacity: View.Capacity, +font: T.Presentation,
  +viewport: Spatial.Box, +state: State, +semantic: InterfaceView.Surface) -> Search:
  match result:
    case Shell.Rejected{key, problem}: Stopped{Decision{set_lifecycle(state, Blocked{"Unsupported authored content: " ++ UIIdentity.encode(key)}), Nil{}}}
    case Shell.Ready{source}: frozen(source, index, capacity, font, viewport, state, semantic)

def calibrated_parameters(parameters: Maybe<&2, Design.LayoutParameters>, +index: Nat, +state: State) -> Search:
  match parameters:
    case None{}: Stopped{Decision{set_lifecycle(state, Blocked{"Font metrics exceed supported layout size."}), Nil{}}}
    case Some{parameters}:
      State{+observed_state_1, serial, +anchors, lifecycle, displayed} = state
      +observed_web_2 = Legacy.web(observed_state_1)
      +observed_application_3 = Web.application(observed_web_2)
      +environment = Web.environment(observed_web_2)
      +font = Web.typography(observed_web_2)
      +stored: Legacy.State = Legacy.with_web(Web.with_application(observed_application_3, observed_web_2), observed_state_1)
      +capacity = candidate(index)
      +semantic = semantic_surface(capacity, stored)
      +layers = surface_layers(semantic)
      +surface = Web.appearance_surface(semantic, environment, font)
      +presentation: T.Presentation = T.Presentation{T.Body{}, T.Regular{}, F.scale(font)}
      authored(Shell.source(surface, parameters, capacity, layers, anchors, presentation),
        index, capacity, presentation, viewport_box(environment), State{stored, serial, anchors, lifecycle, displayed}, semantic)

def calibrated_body(metric: T.Metric, +index: Nat, +state: State) -> Search:
  calibrated_parameters(Design.parameters(NaturalSize.limit(), F.scale(current_font(legacy(state))), metric), index, state)

def calibrated(+body: Maybe<&2, T.Metric>, +index: Nat, +state: State) -> Search:
  match body:
    case None{}: Stopped{Decision{set_lifecycle(state, WaitingFont{}), Nil{}}}
    case Some{metric}: calibrated_body(metric, index, state)

def font_candidate(font: F.State, +index: Nat, +state: State) -> Search:
  match font:
    case F.Failed{generation, scale}: Stopped{Decision{set_lifecycle(state, Blocked{"Font measurements could not be validated."}), Nil{}}}
    case other: calibrated(F.body(other), index, state)

def one_candidate(+index: Nat, +state: State) -> Search:
  font_candidate(current_font(legacy(state)), index, state)

def search_step(search: Search) -> Search:
  match search:
    case Stopped{decision}: Stopped{decision}
    case Searching{index, state}: one_candidate(index, state)
# A bounded data machine visits one frozen candidate at a time.

def search_run(remaining: Nat, search: Search) -> Search:
  match remaining:
    case 0n: search
    case 1n+predecessor: search_run(predecessor, search_step(search))

def finish_search(search: Search) -> Decision:
  match search:
    case Stopped{decision}: decision
    case Searching{index, state}: no_candidate(state)

def utility_publish(+world: Content.AllocatedWorld, purpose: Utility.Purpose, engine: World.Engine, state: State) -> Decision:
  State{+stored, serial, anchors, lifecycle, displayed} = state
  Decision{State{stored, serial, anchors, UtilityDisplaying{purpose, engine},
    Some{Published{world, current_legacy_surface(stored), Focus.Document{}, NativeFields.Basis{Nil{}, Nil{}}, None{}}}}, Nil{}}

def utility_selected(plan: Plan.Plan, +purpose: Utility.Purpose, +engine: World.Engine, round: Nat, glyph_only: Bool, +state: State) -> Decision:
  match plan:
    case Plan.Ready{world}: utility_publish(world, purpose, engine, state)
    case Plan.Awaiting{generation, first, remaining}: Decision{set_lifecycle(state, UtilityMeasuring{purpose, engine, round, glyph_only}), Nil{}}
    case Plan.Infeasible{failure}: Decision{set_lifecycle(state, Blocked{failure_message(failure)}), Nil{}}
    case Plan.Invalid{error}: Decision{set_lifecycle(state, Blocked{"Frontend utility source is invalid"}), Nil{}}

def utility_start(+purpose: Utility.Purpose, +glyph_only: Bool, +state: State) -> Decision:
  State{+stored, +serial, anchors, lifecycle, displayed} = state
  +observed_web_1 = Legacy.web(stored)
  +environment = Web.environment(observed_web_1)
  +font = Web.typography(observed_web_1)
  +presentation: T.Presentation = T.Presentation{T.Body{}, T.Regular{}, F.scale(font)}
  +engine = World.initial(Content.Snapshot{(serial + 1n : Nat), Utility.source(purpose, presentation, glyph_only), presentation}, viewport_box(environment))
  utility_selected(World.plan(engine), purpose, engine, 0n, glyph_only, State{stored, (serial + 1n : Nat), anchors, lifecycle, displayed})

def utility_if_needed(decision: Decision) -> Decision:
  Decision{+state, effects} = decision
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case WaitingEnvironment{}: append(effects, utility_start(Utility.Preparing{}, False{}, state))
    case WaitingFont{}: append(effects, utility_start(Utility.Preparing{}, False{}, state))
    case Blocked{reason}: append(effects, utility_start(Utility.Recovery{reason}, False{}, state))
    case _: Decision{state, effects}

def build(index: Nat, state: State) -> Decision:
  utility_if_needed(finish_search(search_run(4n, Searching{index, state})))

def accepted(+rebuild: Bool, +first: +List<Legacy.Effect>, +state: State) -> Decision:
  match rebuild:
    case False{}: Decision{state, List.append(&2, Legacy.Effect, first, pending_frame_effects(state))}
    case True{}:
      append(first, build(0n, state))

def accept(+rebuild: Bool, +value: Legacy.Decision, +state: State) -> Decision:
  Legacy.Decision{next, first} = value
  State{old, serial, anchors, lifecycle, displayed} = state
  accepted(rebuild, first, State{next, serial, anchors, lifecycle, displayed})

def command_rejected(+ticket: Nat, +reason: String, +state: State) -> Decision: accept(True{}, Legacy.command_rejected(ticket, reason, legacy(state)), state)

def activate(+key: String, +state: State) -> Decision: accept(True{}, Legacy.activate(key, legacy(state)), state)

def edit_text_owned(+owned: Bool, +key: String, +text: String, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: accept(True{}, Legacy.edit_text(key, text, legacy(state)), state)

def edit_text(+key: String, +text: String, +state: State) -> Decision: edit_text_owned(field_owned(key, state), key, text, state)

def confirm_text_owned(+owned: Bool, +key: String, +keyboard: String, +composing: Bool, +control: Bool, +alt: Bool, +shift: Bool, +meta: Bool, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: accept(True{}, Legacy.confirm_text(key, keyboard, composing, control, alt, shift, meta, legacy(state)), state)

def confirm_text(+key: String, +keyboard: String, +composing: Bool, +control: Bool, +alt: Bool, +shift: Bool, +meta: Bool, +state: State) -> Decision: confirm_text_owned(field_owned(key, state), key, keyboard, composing, control, alt, shift, meta, state)

def edit_toggle_owned(+owned: Bool, +key: String, +enabled: Bool, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: accept(True{}, Legacy.edit_toggle(key, enabled, legacy(state)), state)

def edit_toggle(+key: String, +enabled: Bool, +state: State) -> Decision: edit_toggle_owned(field_owned(key, state), key, enabled, state)

def attach_owned(+owned: Bool, +key: String, +file: Services.SelectedFile, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: accept(True{}, Legacy.attach(key, file, legacy(state)), state)

def attach(+key: String, +file: Services.SelectedFile, +state: State) -> Decision: attach_owned(field_owned(key, state), key, file, state)

def place(+key: String, +target: String, +state: State) -> Decision: accept(True{}, Legacy.place(key, target, legacy(state)), state)

def connect(+credential: String, +state: State) -> Decision: accept(True{}, Legacy.connect(credential, legacy(state)), state)

def directories_completed(+ticket: Nat, +ok: Bool, +body: J.Json, +state: State) -> Decision: accept(True{}, Legacy.directories_completed(ticket, ok, body, legacy(state)), state)

def code_same_source(left: Code.Source, right: Code.Source) -> Bool:
  match left:
    case Code.Message{task, message}:
      match right:
        case Code.Message{other_task, other_message}: Nat.is_eq(task, other_task) && Nat.is_eq(message, other_message)
        case _: False{}
    case Code.StreamingPart{task, operation, part}:
      match right:
        case Code.StreamingPart{other_task, other_operation, other_part}:
          Nat.is_eq(task, other_task) && Nat.is_eq(operation, other_operation) && Nat.is_eq(part, other_part)
        case _: False{}

def code_declared_owned(declared: Maybe<&2, Code.Source>, value: String, source: Code.Source, source_value: String) -> Bool:
  match declared:
    case None{}: False{}
    case Some{owner}: code_same_source(owner, source) && String.eq(value, source_value)

def code_content_owned(content: Source.RichContent, +identity: Code.Identity, +source_value: String) -> Bool:
  Source.RichContent{declared, value, policy} = content
  Code.Identity{source, ordinal} = identity
  code_declared_owned(declared, value, source, source_value)

def code_node_owned(+node: Source.Node, +identity: Code.Identity, +source_value: String) -> Bool:
  match node:
    case Source.RichText{key, style, content, attachments, native_owner}: code_content_owned(content, identity, source_value)
    case _: False{}

def code_children_owned(nodes: +List<Source.Node>, +identity: Code.Identity, +source_value: String) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{Source.Box{key, tag, style, attributes, children}, rest}:
      code_children_owned(children, identity, source_value) || code_children_owned(rest, identity, source_value)
    case Con{Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}, rest}:
      code_children_owned(children, identity, source_value) || code_children_owned(rest, identity, source_value)
    case Con{Source.NativeAttachment{key, target, attributes, style, children}, rest}:
      code_children_owned(children, identity, source_value) || code_children_owned(rest, identity, source_value)
    case Con{Source.RichText{key, style, content, attachments, native_owner}, rest}:
      code_content_owned(content, identity, source_value) || code_children_owned(attachments, identity, source_value) || code_children_owned(rest, identity, source_value)
    case Con{Source.Text{key, value, font, wrapping}, rest}:
      code_children_owned(rest, identity, source_value)
    case Con{Source.Glyph{key, drawing, style}, rest}:
      code_children_owned(rest, identity, source_value)
    case Con{Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}, rest}:
      code_children_owned(rest, identity, source_value)

def code_source_owned(+node: Source.Node, +identity: Code.Identity, +source_value: String) -> Bool:
  nodes: +List<Source.Node> = Con{node, Nil{}}
  code_children_owned(nodes, identity, source_value)

def code_observations_owned(observations: +List<CodeObservation.Observation>, +source: Source.Node) -> Bool:
  match observations:
    case Nil{}: True{}
    case Con{CodeObservation.Observation{identity, text, source_value}, rest}:
      code_source_owned(source, identity, source_value) && code_observations_owned(rest, source)

def code_batch_owned(observations: +List<CodeObservation.Observation>, source: Source.Node) -> Bool:
  match observations:
    case Nil{}: False{}
    case Con{observation, rest}: code_observations_owned(Con{observation, rest}, source)

def code_batch_qualified(+generation: Nat, observations: +List<CodeObservation.Observation>, state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case None{}: False{}
    case Some{Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
      code_batch_owned(observations, source)

# NOTE: Qualify against one published snapshot before any source update can publish a new generation.

def code_sources_fold(observations: +List<CodeObservation.Observation>, decision: Legacy.Decision) -> Legacy.Decision:
  match observations:
    case Nil{}: decision
    case Con{CodeObservation.Observation{Code.Identity{source, ordinal}, text, source_value}, rest}:
      Legacy.Decision{state, effects} = decision
      code_sources_fold(rest, Legacy.append_decision(effects, Legacy.code_source(source, ordinal, text, state)))

def code_sources_if_qualified(qualified: Bool, observations: +List<CodeObservation.Observation>, +state: State) -> Decision:
  match qualified:
    case False{}: Decision{state, Nil{}}
    case True{}: accept(True{}, code_sources_fold(observations, Legacy.Decision{legacy(state), Nil{}}), state)

def code_sources(+generation: Nat, +observations: +List<CodeObservation.Observation>, +state: State) -> Decision:
  code_sources_if_qualified(code_batch_qualified(generation, observations, state), observations, state)

def editor_event(+key: String, +event: Editor.EditorEvent, +state: State) -> Decision: accept(True{}, Legacy.editor_event(key, event, legacy(state)), state)

def reading(+task: Nat, +generation: Nat, +event: Reading.ReadingEvent, +state: State) -> Decision: accept(False{}, Legacy.reading(task, generation, event, legacy(state)), state)

def streams(+body: J.Json, +state: State) -> Decision: accept(True{}, Legacy.streams(body, legacy(state)), state)

def directory_listed(+ticket: Nat, +ok: Bool, +body: J.Json, +state: State) -> Decision: accept(True{}, Legacy.directory_listed(ticket, ok, body, legacy(state)), state)

def measurements(+observation: F.Observation, +state: State) -> Decision:
  accept(True{}, Legacy.measurements(observation, legacy(state)), state)

def frame_forward_ready(+ready: Bool, +state: State, +frame: Rendered.Frame) -> Decision:
  match ready:
    case False{}: Decision{state, Nil{}}
    case True{}:
      State{+stored, serial, anchors, lifecycle, displayed} = state
      match displayed:
        case None{}: Decision{State{stored, serial, anchors, lifecycle, None{}}, Nil{}}
        case Some{+value}:
          Published{world, semantic, scope, basis, old} = value
          accept(False{}, Legacy.observe_frame(semantic_generation(stored), semantic, frame, stored),
            State{stored, serial, anchors, lifecycle, Some{value}})

def frame_forward(+state: State, +frame: Rendered.Frame) -> Decision:
  frame_forward_ready(display_ready(state), state, frame)

def frame_capture(+frame: Rendered.Frame, state: State) -> State:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case None{}: State{legacy, serial, anchors, lifecycle, None{}}
    case Some{Published{world, semantic, scope, basis, old}}:
      State{legacy, serial, anchors, lifecycle, Some{Published{world, semantic, scope, basis, Some{frame}}}}

def frame_owned(+received: Nat, +state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case None{}: False{}
    case Some{published}: Nat.is_eq(received, displayed_generation(state))

def utility_frame_result(violations: +List<Rendered.Violation>, +frame: Rendered.Frame, state: State) -> Decision:
  match violations:
    case Nil{}: Decision{frame_capture(frame, state), Nil{}}
    case other:
      State{legacy, serial, anchors, lifecycle, displayed} = state
      Decision{State{legacy, serial, anchors, UtilityRejected{"Frontend utility frame does not match its admitted source"}, None{}}, Nil{}}

def correlated_frame_owned(utility: Bool, +frame: Rendered.Frame, +state: State) -> Decision:
  match utility:
    case False{}: frame_forward(frame_capture(frame, state), frame)
    case True{}:
      State{legacy, serial, anchors, lifecycle, displayed} = state
      match displayed:
        case None{}: Decision{state, Nil{}}
        case Some{Published{world, semantic, scope, basis, old}}:
          utility_frame_result(SourceFrame.check(world, frame), frame, state)

def correlated_frame(+frame: Rendered.Frame, +state: State) -> Decision:
  correlated_frame_owned(utility_owned(state), frame, state)

def received_frame(+owned: Bool, +frame: Rendered.Frame, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: correlated_frame(frame, state)

def rich_delegates(node: Source.Node, +owner: String) -> Bool:
  match node:
    case Source.RichText{key, style, content, attachments, Some{delegated}}: String.eq(delegated, owner)
    case _: False{}

def source_children_delegate(nodes: +List<Source.Node>, +owner: String) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{node, rest}:
      match node:
        case Source.NativeAttachment{key, target, attributes, style, +children}:
          (rich_delegates(Source.NativeAttachment{key, target, attributes, style, children}, owner) || source_children_delegate(children, owner)) || source_children_delegate(rest, owner)
        case Source.Box{key, tag, style, attributes, +children}:
          (rich_delegates(Source.Box{key, tag, style, attributes, children}, owner) || source_children_delegate(children, owner)) || source_children_delegate(rest, owner)
        case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, +children}:
          (rich_delegates(Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}, owner) || source_children_delegate(children, owner)) || source_children_delegate(rest, owner)
        case Source.Text{key, value, font, wrapping}:
          (rich_delegates(Source.Text{key, value, font, wrapping}, owner) || False{}) || source_children_delegate(rest, owner)
        case Source.Glyph{key, drawing, style}:
          (rich_delegates(Source.Glyph{key, drawing, style}, owner) || False{}) || source_children_delegate(rest, owner)
        case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}:
          (rich_delegates(Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}, owner) || False{}) || source_children_delegate(rest, owner)
        case Source.RichText{key, style, content, +attachments, native_owner}:
          (rich_delegates(Source.RichText{key, style, content, attachments, native_owner}, owner) || source_children_delegate(attachments, owner)) || source_children_delegate(rest, owner)

def source_delegates(+node: Source.Node, +owner: String) -> Bool:
  source_children_delegate([node], owner)

def native_pair(entries: +List<Rendered.NativeFocus>, +owner: String, +identity: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{Rendered.NativeFocus{key, parent}, rest}: (String.eq(key, identity) && String.eq(parent, owner)) || native_pair(rest, owner, identity)

def native_frame_owned(frame: Maybe<&2, Rendered.Frame>, +semantic: InterfaceView.Surface, +owner: String, +identity: String) -> Bool:
  match frame:
    case None{}: False{}
    case Some{Rendered.Frame{viewport, +elements, focused, order, +native_focus}}:
      Rendered.native_valid(native_focus, InterfaceView.active_nodes(semantic), elements) && native_pair(native_focus, owner, identity)

def native_observation_owned(+generation: Nat, +owner: String, +identity: String, state: State) -> Bool:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case None{}: False{}
    case Some{Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, +semantic, scope, basis, frame}}:
      Nat.is_eq(generation, published) && source_delegates(source, owner) &&
      Rendered.read_only(InterfaceView.find_node(InterfaceView.active_nodes(semantic), owner)) && native_frame_owned(frame, semantic, owner, identity)

def native_focus_if_owned(owned: Bool, owner: String, identity: String, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: accept(False{}, Legacy.native(Web.PlatformInput{Platform.ContentFocusObserved{owner, identity}}, legacy(state)), state)

def native_focus_observed(+generation: Nat, +owner: String, +identity: String, +state: State) -> Decision:
  native_focus_if_owned(native_observation_owned(generation, owner, identity, state), owner, identity, state)

def auxiliary_focus_owned(utility: Bool, input: Web.Input, +state: State) -> Decision:
  match utility:
    case True{}: Decision{state, Nil{}}
    case False{}: accept(False{}, Legacy.native(input, legacy(state)), state)

def auxiliary_focus(+input: Web.Input, +state: State) -> Decision:
  auxiliary_focus_owned(auxiliary_owned(state), input, state)

def step(+input: Legacy.Input, +state: State) -> Decision:
  match input:
    case Legacy.Native{Web.CodeSourcesObserved{generation, observations}}: code_sources(generation, observations, state)
    case Legacy.Native{Web.PlatformInput{Platform.ProductInput{Product.CodeSource{identity, text}}}}: Decision{state, Nil{}}
    case Legacy.Native{Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{Core.ApplicationInput{E.ContentInput{identity, Code.SourceChanged{text}}}}}}}: Decision{state, Nil{}}
    case Legacy.Native{Web.NativeFocusObserved{generation, owner, identity}}: native_focus_observed(generation, owner, identity, state)
    case Legacy.Native{Web.PlatformInput{Platform.ContentFocusObserved{owner, identity}}}: Decision{state, Nil{}}
    case Legacy.Native{Web.FrameObserved{generation, frame}}:
      received_frame(frame_owned(generation, state), frame, state)
    case Legacy.Native{Web.PlatformInput{Platform.FocusObserved{identity}}}: auxiliary_focus(Web.PlatformInput{Platform.FocusObserved{identity}}, state)
    case Legacy.Native{Web.PlatformInput{Platform.FocusApplied{ticket, identity, observed}}}: auxiliary_focus(Web.PlatformInput{Platform.FocusApplied{ticket, identity, observed}}, state)
    case Legacy.Native{Web.PlatformInput{Platform.PublicationFocusObserved{ticket, before, after}}}: auxiliary_focus(Web.PlatformInput{Platform.PublicationFocusObserved{ticket, before, after}}, state)
    case Legacy.Native{+input}: accept(source_changed(input), Legacy.native(input, legacy(state)), state)
    case other: accept(True{}, Legacy.step(other, legacy(state)), state)

def outside_result(+result: Legacy.OutsideDecision, +state: State) -> OutsideDecision:
  Legacy.OutsideDecision{handled, decision} = result
  OutsideDecision{handled, accept(handled, decision, state)}

def outside_owned(utility: Bool, +identity: String, +state: State) -> OutsideDecision:
  match utility:
    case True{}: OutsideDecision{False{}, Decision{state, Nil{}}}
    case False{}: outside_result(legacy_outside(identity, legacy(state)), state)

def outside_event(+identity: String, +state: State) -> OutsideDecision:
  outside_owned(auxiliary_owned(state), identity, state)

def observed_eligible(found: Maybe<&2, Rendered.Element>) -> Bool:
  match found:
    case None{}: False{}
    case Some{Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit, +paint_bounds}}: enabled && (visible || scroll)

def published_order_eligible(eligible: Bool, key: String, tail: +List<String>) -> +List<String>:
  match eligible:
    case False{}: tail
    case True{}: key <> tail

def published_order(order: +List<String>, +basis: NativeFields.Basis, +elements: +List<Rendered.Element>, +semantic: InterfaceView.Surface, +native_focus: +List<Rendered.NativeFocus>) -> +List<String>:
  match order:
    case Nil{}: Nil{}
    case Con{+key, rest}:
      published_order_eligible((NativeFields.control_owned(basis, key) || Rendered.native_owned(native_focus, InterfaceView.active_nodes(semantic), elements, key)) && observed_eligible(Rendered.find_element(elements, key)), key, published_order(rest, basis, elements, semantic, native_focus))

def native_target_match(hit: Bool, owner: String, identity: String, fallback: Focus.Target) -> Focus.Target:
  match hit:
    case True{}: Focus.Content{owner, identity}
    case False{}: fallback

def native_target(entries: +List<Rendered.NativeFocus>, +key: String) -> Focus.Target:
  match entries:
    case Nil{}: Focus.Product{key}
    case Con{Rendered.NativeFocus{+identity, owner}, rest}:
      native_target_match(String.eq(identity, key), owner, identity, native_target(rest, key))

def admitted_native_focus(valid: Bool, entries: +List<Rendered.NativeFocus>) -> +List<Rendered.NativeFocus>:
  match valid:
    case True{}: entries
    case False{}: Nil{}

def published_target(found: Maybe<&2, String>, native_focus: +List<Rendered.NativeFocus>) -> Maybe<&2, Focus.Target>:
  match found:
    case None{}: None{}
    case Some{key}: Some{native_target(native_focus, key)}

def published_cycle(scope: Focus.Scope, basis: NativeFields.Basis, +semantic: InterfaceView.Surface, frame: Maybe<&2, Rendered.Frame>, reverse: Bool) -> Maybe<&2, Focus.Target>:
  match frame:
    case None{}: None{}
    case Some{Rendered.Frame{viewport, +elements, focused, +order, +native_focus}}:
      published_target(Focus.cycle(scope, published_order(order, basis, elements, semantic, native_focus), focused, reverse),
        admitted_native_focus(Rendered.native_valid(native_focus, InterfaceView.active_nodes(semantic), elements), native_focus))

def published_escape(found: Maybe<&2, Legacy.DismissTarget>, +state: State) -> KeyResult:
  match found:
    case None{}: KeyResult{False{}, Decision{state, Nil{}}}
    case Some{Legacy.DismissTarget{identity, input, outside, +escape}}:
      KeyResult{escape, accept(escape, Legacy.dismiss_permitted(escape && Legacy.outside_layer_owned(identity, Legacy.current_layer_key(legacy(state))), input, legacy(state)), state)}

def published_key_kind(tab: Bool, escape: Bool, shift: Bool, scope: Focus.Scope, basis: NativeFields.Basis, semantic: InterfaceView.Surface, frame: Maybe<&2, Rendered.Frame>, +state: State) -> KeyResult:
  match tab escape:
    case True{} _: KeyResult{True{}, accept(False{}, Legacy.cycle_target_found(published_cycle(scope, basis, semantic, frame, shift), legacy(state)), state)}
    case False{} True{}: published_escape(Legacy.dismiss_target(InterfaceView.active_nodes(semantic)), state)
    case False{} False{}: KeyResult{False{}, Decision{state, Nil{}}}

def published_key(+key: String, shift: Bool, +scope: Focus.Scope, basis: NativeFields.Basis, semantic: InterfaceView.Surface, frame: Maybe<&2, Rendered.Frame>, +state: State) -> KeyResult:
  match scope:
    case Focus.Document{}: KeyResult{False{}, Decision{state, Nil{}}}
    case Focus.Temporary{identity, initial, restore, occurrence}:
      published_key_kind(String.eq(key, "Tab"), String.eq(key, "Escape"), shift, scope, basis, semantic, frame, state)

def key_captured(+key: String, +shift: Bool, +state: State) -> KeyResult:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match displayed:
    case None{}: KeyResult{False{}, Decision{state, Nil{}}}
    case Some{Published{world, semantic, scope, basis, frame}}: published_key(key, shift, scope, basis, semantic, frame, state)

def key_event(+key: String, +shift: Bool, +received: Nat, +frame: Rendered.Frame, +state: State) -> KeyResult:
  key_captured(key, shift, decision_state(received_frame(frame_owned(received, state), frame, state)))

def receipt_selection(status: World.ReceiptStatus, +index: Nat, +capacity: View.Capacity, +engine: World.Engine, +state: State, +semantic: InterfaceView.Surface, round: Nat) -> Decision:
  match status:
    case World.Rejected{reason}: Decision{set_lifecycle(state, Blocked{reason}), Nil{}}
    case _: finish_search(search_run(4n, selected(World.plan(engine), index, capacity, engine, state, semantic, round)))

def utility_fallback(reason: String, state: State) -> Decision:
  utility_start(Utility.Recovery{reason}, True{}, state)

def utility_measurement_failure(reason: String, +state: State) -> Decision:
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case UtilityMeasuring{purpose, engine, round, False{}}: utility_fallback(reason, state)
    case UtilityMeasuring{purpose, engine, round, True{}}: Decision{set_lifecycle(state, Blocked{reason}), Nil{}}
    case _: utility_start(Utility.Recovery{reason}, False{}, state)

def utility_receipt(status: World.ReceiptStatus, +purpose: Utility.Purpose, +engine: World.Engine, round: Nat, glyph_only: Bool, +state: State) -> Decision:
  match status:
    case World.Rejected{reason}: utility_measurement_failure(reason, state)
    case _: utility_selected(World.plan(engine), purpose, engine, round, glyph_only, state)

def measured_pending(+receipts: +List<String>, +state: State) -> Decision:
  match state:
    case State{legacy, serial, anchors, Measuring{index, capacity, +engine, semantic, +round}, displayed}:
      +next = World.receive(World.snapshot_generation(World.snapshot(engine)), receipts, engine)
      receipt_selection(World.receipt_status(next), index, capacity, next, State{legacy, serial, anchors, Measuring{index, capacity, engine, semantic, round}, displayed}, semantic, (round + 1n : Nat))
    case State{legacy, serial, anchors, UtilityMeasuring{purpose, +engine, +round, glyph_only}, displayed}:
      +next = World.receive(World.snapshot_generation(World.snapshot(engine)), receipts, engine)
      utility_receipt(World.receipt_status(next), purpose, next, (round + 1n : Nat), glyph_only, State{legacy, serial, anchors, UtilityMeasuring{purpose, engine, round, glyph_only}, displayed})
    case other: Decision{other, Nil{}}

def measured_current(+owned: Bool, +receipts: +List<String>, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: measured_pending(receipts, state)

def measurement_owned(ticket: MeasurementTicket, state: State) -> Bool:
  MeasurementTicket{generation, received_round} = ticket
  State{legacy, serial, anchors, lifecycle, displayed} = state
  match lifecycle:
    case Measuring{index, capacity, engine, semantic, round}: Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))) && Nat.is_eq(received_round, round)
    case UtilityMeasuring{purpose, engine, round, glyph_only}: Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))) && Nat.is_eq(received_round, round)
    case _: False{}

def measurement_failed(+owned: Bool, +reason: String, +state: State) -> Decision:
  match owned:
    case False{}: Decision{state, Nil{}}
    case True{}: utility_measurement_failure(reason, state)

def physical_measurement_failed(+ticket: MeasurementTicket, +reason: String, +state: State) -> Decision:
  measurement_failed(measurement_owned(ticket, state), reason, state)

def physical_measured(+ticket: MeasurementTicket, +receipts: +List<String>, +state: State) -> Decision:
  measured_current(measurement_owned(ticket, state), receipts, state)

def capacity_index(capacity: View.Capacity) -> Nat:
  match capacity:
    case View.Capacity{True{}, True{}}: 0n
    case View.Capacity{True{}, False{}}: 1n
    case View.Capacity{False{}, True{}}: 2n
    case _: 3n

def refrozen_source(source: Source.Node, font: T.Presentation, viewport: Spatial.Box, +index: Nat, +capacity: View.Capacity, +state: State, +semantic: InterfaceView.Surface) -> Decision:
  State{legacy, +serial, anchors, lifecycle, displayed} = state
  +engine = World.initial(Content.Snapshot{(serial + 1n : Nat), source, font}, viewport)
  finish_search(search_run(4n, selected(World.plan(engine), index, capacity, engine,
    State{legacy, (serial + 1n : Nat), anchors, lifecycle, displayed}, semantic, 0n)))

def refrozen(snapshot: Content.Snapshot, viewport: Spatial.Box, +index: Nat, +capacity: View.Capacity, +state: State, +semantic: InterfaceView.Surface) -> Decision:
  Content.Snapshot{old, source, font} = snapshot
  refrozen_source(source, font, viewport, index, capacity, state, semantic)

def refreeze(+index: Nat, +capacity: View.Capacity, +engine: World.Engine, +state: State, +semantic: InterfaceView.Surface) -> Decision:
  State{legacy, +serial, anchors, lifecycle, displayed} = state
  refrozen(World.snapshot(engine), World.viewport(engine), index, capacity, State{legacy, serial, anchors, lifecycle, displayed}, semantic)

def remeasure(+state: State) -> Decision:
  match state:
    case State{legacy, serial, anchors, Measuring{index, capacity, engine, semantic, round}, displayed}: refreeze(index, capacity, engine, State{legacy, serial, anchors, Measuring{index, capacity, engine, semantic, round}, displayed}, semantic)
    case State{legacy, serial, anchors, Displaying{capacity, engine, semantic}, displayed}: refreeze(capacity_index(capacity), capacity, engine, State{legacy, serial, anchors, Displaying{capacity, engine, semantic}, displayed}, semantic)
    case State{legacy, serial, anchors, UtilityMeasuring{purpose, engine, round, glyph_only}, displayed}:
      utility_start(purpose, glyph_only, State{legacy, serial, anchors, UtilityMeasuring{purpose, engine, round, glyph_only}, displayed})
    case State{legacy, serial, anchors, UtilityDisplaying{purpose, engine}, displayed}:
      utility_start(purpose, False{}, State{legacy, serial, anchors, UtilityDisplaying{purpose, engine}, displayed})
    case other: Decision{other, Nil{}}

def key_decision(result: KeyResult) -> Decision:
  KeyResult{handled, decision} = result
  decision

def key_input(+key: String, +shift: Bool, +received: Nat, +frame: Rendered.Frame, +state: State) -> Decision: key_decision(key_event(key, shift, received, frame, state))

def key_handled(result: KeyResult) -> Bool:
  KeyResult{handled, decision} = result
  handled
