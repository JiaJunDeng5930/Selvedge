import ../layout/PROGRAM.bend as Allocation
import ../../interaction/submission/MODEL.bend as Receipt
import ../layout/anchor-geometry.bend as AnchorGeometry
import ./native-fields-rules.bend as NativeRules
import ../focus/MODEL.bend as Focus
import ./native-fields.bend as Native
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import Base
import ./frontend-utility.bend as Utility
import ../document/FRAME.bend as SourceFrame
import ./PLATFORM.bend as Platform
import ../appearance/DESIGN.bend as Design
import ../appearance/FONT.bend as F
import ../appearance/TYPOGRAPHY.bend as T
import ./MODEL.bend as Browser
import ../layout/physical-plan.bend as Plan
import ./SEMANTICS.bend as Legacy
import ../MODEL.bend as Web
import ../document/RENDERED.bend as Rendered
import ../layout/MODEL.bend as World
import ../layout/CONTENT.bend as Content
import ../layout/RENDERER.bend as Renderer
import ../controls/SHELL.bend as Shell
import ../document/MODEL.bend as Doc
import ../../interaction/presentation/MODEL.bend as View
import ../../harness/MODEL.bend as M
def stale_frames_claim(+received: Nat, +frame: Rendered.Frame, +state: Browser.State) -> Type:
  {Browser.step(Legacy.Native{Web.FrameObserved{received, frame}}, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

def stale_measurements_claim(+received: Browser.MeasurementTicket, +tokens: +List<String>, +state: Browser.State) -> Type:
  {Browser.physical_measured(received, tokens, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

def ready_document_claim(+model_state: Browser.State, +rendering_capacity: Nat, +layout_capacity: View.Capacity, +engine: World.Engine, +world: Content.AllocatedWorld, +semantic: InterfaceView.Surface) -> Type:
  {Browser.observe(rendering_capacity, Browser.with_displayed(Some{Browser.published(world, layout_capacity, Browser.legacy(model_state), semantic)}, Browser.with_lifecycle(Browser.Displaying{layout_capacity, engine, semantic}, model_state))) ==
    Doc.Document{Doc.Element{"@browser/application", "div", [Doc.Property{"class", "native-application"}], Nil{}, Nil{}, Renderer.nodes(world)}, "Selvedge"} : Doc.Document}

def anchor_preserves_program_claim(+key: String, +left: AnchorGeometry.Origin, +top: AnchorGeometry.Origin, +width: Nat, +height: Nat, +state: Browser.State) -> Type:
  {Browser.program(Browser.decision_state(Browser.capture_anchor(key, left, top, width, height, state))) == Browser.program(state) : M.World()}

def pending_lifecycle(lifecycle: Browser.Lifecycle) -> Bool:
  match lifecycle:
    case Browser.WaitingEnvironment{}: True{}
    case Browser.WaitingFont{}: True{}
    case Browser.Measuring{index, capacity, engine, semantic, round}: True{}
    case Browser.UtilityMeasuring{purpose, engine, round, glyph_only}: True{}
    case other: False{}

def publication_pending(+state: Browser.State) -> Bool:
  +lifecycle = Browser.lifecycle(state)
  pending_lifecycle(lifecycle)

def blocked_publication_claim_at(+model_state: Browser.State, +capacity: Nat, +last_published: Nat, +problem: String) -> Type:
  {Browser.publication(capacity, last_published, Browser.with_lifecycle(Browser.Blocked{problem}, model_state)) ==
    Browser.publication_policy_at(capacity, Bool.not(Nat.is_eq(last_published, 0n)), False{},
      Nat.is_eq(Browser.displayed_generation(Browser.with_lifecycle(Browser.Blocked{problem}, model_state)), last_published),
      Browser.with_lifecycle(Browser.Blocked{problem}, model_state)) : Browser.Publication}

def publication_preserves_pending_claim_at(+capacity: Nat, +last_published: Nat, +state: Browser.State) -> Type:
  {Browser.publication(capacity, last_published, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}

def publication_current_claim_at(+capacity: Nat, +last_published: Nat, +state: Browser.State) -> Type:
  {Browser.publication(capacity, last_published, state) == Browser.KeepPublished{Browser.native_updates(state)} : Browser.Publication}

def frame_capture_program_claim(+frame: Rendered.Frame, +state: Browser.State) -> Type:
  {Browser.program(Browser.frame_capture(frame, state)) == Browser.program(state) : M.World()}

def document_keyboard_claim(+key: String, +shift: Bool, +basis: Native.Basis, +semantic: InterfaceView.Surface, +frame: Maybe<&2, Rendered.Frame>, +state: Browser.State) -> Type:
  {Browser.published_key(key, shift, Focus.Document{}, basis, semantic, frame, state) == Browser.KeyResult{False{}, Browser.Decision{state, Nil{}}} : Browser.KeyResult}

def temporary_tab_claim(+shift: Bool, +identity: String, +initial: String, +restore: String, +occurrence: Maybe<&2, Nat>, +basis: Native.Basis, +semantic: InterfaceView.Surface, +frame: Maybe<&2, Rendered.Frame>, +state: Browser.State) -> Type:
  {Browser.key_handled(Browser.published_key("Tab", shift, Focus.Temporary{identity, initial, restore, occurrence}, basis, semantic, frame, state)) == True{} : Bool}

type Requirements is Type:
  Requirements{
    temporary_tab: @+shift:Bool -> @+identity:String -> @+initial:String -> @+restore:String -> @+occurrence:Maybe<&2, Nat> -> @+basis:Native.Basis -> @+semantic:InterfaceView.Surface -> @+frame:Maybe<&2, Rendered.Frame> -> @+state:Browser.State -> temporary_tab_claim(shift, identity, initial, restore, occurrence, basis, semantic, frame, state),
    native_fields: NativeRules.Requirements,
    frame_capture_program: @+frame:Rendered.Frame -> @+state:Browser.State -> frame_capture_program_claim(frame, state),
    document_keyboard: @+key:String -> @+shift:Bool -> @+basis:Native.Basis -> @+semantic:InterfaceView.Surface -> @+frame:Maybe<&2, Rendered.Frame> -> @+state:Browser.State -> document_keyboard_claim(key, shift, basis, semantic, frame, state),
    stale_frames: @+received:Nat -> @+frame:Rendered.Frame -> @+state:Browser.State ->
      {Browser.frame_owned(received, state) == False{} : Bool} -> stale_frames_claim(received, frame, state),
    stale_measurements: @+received:Browser.MeasurementTicket -> @+tokens:+List<String> -> @+state:Browser.State ->
      {Browser.measurement_owned(received, state) == False{} : Bool} -> stale_measurements_claim(received, tokens, state),
    ready_document: @+model_state:Browser.State ->  @+rendering_capacity:Nat -> @+layout_capacity:View.Capacity -> @+engine:World.Engine -> @+world:Content.AllocatedWorld -> @+semantic:InterfaceView.Surface -> ready_document_claim(Browser.with_displayed(Some{Browser.published(world, layout_capacity, Browser.legacy(model_state), semantic)}, Browser.with_lifecycle(Browser.Displaying{layout_capacity, engine, semantic}, model_state)), rendering_capacity, layout_capacity, engine, world, semantic),
    anchor_preserves_program: @+key:String -> @+left:AnchorGeometry.Origin -> @+top:AnchorGeometry.Origin -> @+width:Nat -> @+height:Nat -> @+state:Browser.State -> anchor_preserves_program_claim(key, left, top, width, height, state),
    publication_preserves_pending_at: @+capacity:Nat -> @+last_published:Nat -> @+state:Browser.State ->
      {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool} ->
      {publication_pending(state) == True{} : Bool} -> publication_preserves_pending_claim_at(capacity, last_published, state),
    blocked_publication_at: @+model_state:Browser.State ->  @+capacity:Nat -> @+last_published:Nat -> @+problem:String -> blocked_publication_claim_at(Browser.with_lifecycle(Browser.Blocked{problem}, model_state), capacity, last_published, problem),
    publication_current_at: @+capacity:Nat -> @+last_published:Nat -> @+state:Browser.State ->
      {Bool.not(Nat.is_eq(last_published, 0n)) == True{} : Bool} ->
      @+ready:{Browser.display_ready(state) == True{} : Bool} ->
      {Nat.is_eq(Browser.displayed_generation(state), last_published) == True{} : Bool} -> publication_current_claim_at(capacity, last_published, state)}
law forwarded_frame_uses_published_surface:
  for +model_state: Browser.State
  for +world: Content.AllocatedWorld
  for +semantic: InterfaceView.Surface
  for +scope: Focus.Scope
  for +basis: Native.Basis
  for +old: Maybe<&2, Rendered.Frame>
  for +frame: Rendered.Frame
  {Browser.frame_forward_ready(True{}, Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state), frame) ==
    Browser.accept(False{}, Legacy.observe_frame(Browser.semantic_generation(Browser.legacy(model_state)), semantic, frame, Browser.legacy(model_state)),
      Browser.with_displayed(Some{Browser.Published{world, semantic, scope, basis, old}}, model_state)) : Browser.Decision}

law failed_font_candidate_blocked:
  for +model_state: Browser.State
  for +font_generation: Nat
  for +scale: T.Scale
  for +index: Nat
  {Browser.one_candidate(index, Browser.with_legacy(Legacy.with_receipt(None{}, Legacy.with_web(Web.with_typography(F.Failed{font_generation, scale}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state))), model_state)) ==
    Browser.Stopped{Browser.Decision{Browser.with_lifecycle(Browser.Blocked{"Font measurements could not be validated."}, Browser.with_legacy(Legacy.with_receipt(None{}, Legacy.with_web(Web.with_typography(F.Failed{font_generation, scale}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state))), model_state)), Nil{}}} : Browser.Search}

law unmet_frame_status:
  for +model_state: Browser.State
  for +semantic: InterfaceView.Surface
  for +frame_generation: Nat
  for +frame: Rendered.Frame
  for +violations: +List<Rendered.Violation>
  for +capacity: View.Capacity
  for +engine: World.Engine
  {Browser.render_status(Browser.with_lifecycle(Browser.Displaying{capacity, engine, semantic}, Browser.with_legacy(Legacy.with_receipt(None{}, Legacy.with_web(Web.with_realization(Rendered.Unmet{frame_generation, frame, violations}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state))), model_state))) == "unmet" : String}

def element_enabled(element: Rendered.Element) -> Bool:
  Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit, +paint_bounds} = element
  enabled

def element_reachable(element: Rendered.Element) -> Bool:
  Rendered.Element{key, visible, enabled, tab_stop, keyboard, scroll, bounds, hit, +paint_bounds} = element
  visible || scroll

law enabled_reachable_tab_member:
  for +element: Rendered.Element
  for admitted: {element_enabled(element) == True{} : Bool}
  for reachable: {element_reachable(element) == True{} : Bool}
  {Browser.observed_eligible(Some{element}) == True{} : Bool}
law rejected_native_focus_preserves_state:
  for +generation: Nat
  for +owner: String
  for +identity: String
  for +state: Browser.State
  for rejected: {Browser.native_observation_owned(generation, owner, identity, state) == False{} : Bool}
  {Browser.native_focus_observed(generation, owner, identity, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
law missing_native_frame_rejects:
  for semantic: InterfaceView.Surface
  for owner: String
  for identity: String
  {Browser.native_frame_owned(None{}, semantic, owner, identity) == False{} : Bool}
law stale_native_focus_preserves_state:
  for +generation: Nat
  for +owner: String
  for +identity: String
  for +state: Browser.State
  for stale: {Browser.frame_owned(generation, state) == False{} : Bool}
  {Browser.native_focus_observed(generation, owner, identity, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
def measuring_lifecycle(lifecycle: Browser.Lifecycle) -> Bool:
  match lifecycle:
    case Browser.Measuring{index, capacity, engine, semantic, round}: True{}
    case Browser.UtilityMeasuring{purpose, engine, round, glyph_only}: True{}
    case other: False{}

def measurement_phase(+state: Browser.State) -> Bool:
  +lifecycle = Browser.lifecycle(state)
  measuring_lifecycle(lifecycle)

law stale_measurement_failure:
  for +ticket: Browser.MeasurementTicket
  for +reason: String
  for +state: Browser.State
  for stale: {Browser.measurement_owned(ticket, state) == False{} : Bool}
  {Browser.physical_measurement_failed(ticket, reason, state) == Browser.Decision{state, Nil{}} : Browser.Decision}
law current_measurement_failure:
  for +ticket: Browser.MeasurementTicket
  for +reason: String
  for +state: Browser.State
  for owned: {Browser.measurement_owned(ticket, state) == True{} : Bool}
  {Browser.physical_measurement_failed(ticket, reason, state) ==
    Browser.utility_measurement_failure(reason, state) : Browser.Decision}
law measurement_ownership_only_measuring:
  for +ticket: Browser.MeasurementTicket
  for +state: Browser.State
  for owned: {Browser.measurement_owned(ticket, state) == True{} : Bool}
  {measurement_phase(state) == True{} : Bool}
law measurement_request_unavailable:
  for +state: Browser.State
  for inactive: {measurement_phase(state) == False{} : Bool}
  {Browser.measurement_request(state) == None{} : Maybe<&2, Browser.MeasurementRequest>}
law measurement_wrong_round:
  for +model_state: Browser.State
  for +generation: Nat
  for +received_round: Nat
  for +round: Nat
  for +index: Nat
  for +capacity: View.Capacity
  for +engine: World.Engine
  for +semantic: InterfaceView.Surface
  for same_generation: {Nat.is_eq(generation, World.snapshot_generation(World.snapshot(engine))) == True{} : Bool}
  for stale_round: {Nat.is_eq(received_round, round) == False{} : Bool}
  {Browser.measurement_owned(Browser.MeasurementTicket{generation, received_round},
    Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) == False{} : Bool}

law measurement_request_canonical:
  for +model_state: Browser.State
  for +index: Nat
  for +capacity: View.Capacity
  for +engine: World.Engine
  for +semantic: InterfaceView.Surface
  for +round: Nat
  for +generation: Nat
  for +first: Plan.Job
  for +remaining: +List<Plan.Job>
  for awaiting: {World.plan(engine) == Plan.Awaiting{generation, first, remaining} : Plan.Plan}
  {Browser.measurement_request(Browser.with_lifecycle(Browser.Measuring{index, capacity, engine, semantic, round}, model_state)) ==
    Some{Browser.MeasurementRequest{Browser.MeasurementTicket{World.snapshot_generation(World.snapshot(engine)), round},
      Plan.Awaiting{generation, first, remaining}}} : Maybe<&2, Browser.MeasurementRequest>}

law render_violations_unmet:
  for +model_state: Browser.State
  for +observed_generation: Nat
  for +frame: Rendered.Frame
  for +violations: +List<Rendered.Violation>
  {Browser.render_violations(Browser.with_legacy(Legacy.with_web(Web.with_realization(Rendered.Unmet{observed_generation, frame, violations}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state)), model_state)) == violations : +List<Rendered.Violation>}

law render_violations_awaiting:
  for +model_state: Browser.State
  for +observed_generation: Nat
  {Browser.render_violations(Browser.with_legacy(Legacy.with_web(Web.with_realization(Rendered.AwaitingFrame{observed_generation}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state)), model_state)) == Nil{} : +List<Rendered.Violation>}

law render_violations_realized:
  for +model_state: Browser.State
  for +observed_generation: Nat
  for +frame: Rendered.Frame
  {Browser.render_violations(Browser.with_legacy(Legacy.with_web(Web.with_realization(Rendered.Realized{observed_generation, frame}, Legacy.web(Browser.legacy(model_state))), Browser.legacy(model_state)), model_state)) == Nil{} : +List<Rendered.Violation>}

def pending_frame_effects_expected_for(lifecycle: Browser.Lifecycle, realization: Rendered.State, displayed: Maybe<&2, Browser.Published>) -> +List<Legacy.Effect>:
  match lifecycle:
    case Browser.Displaying{capacity, engine, semantic}:
      match realization:
        case Rendered.AwaitingFrame{generation}:
          match displayed:
            case Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{physical_generation, source, observed_font}, tree, roots, policies}, published_semantic, scope, basis, frame}}:
              [Legacy.BrowserEffect{Web.MeasureFrame{physical_generation}}]
            case None{}: Nil{}
        case _: Nil{}
    case Browser.UtilityDisplaying{purpose, engine}:
      match displayed:
        case Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{generation, source, font}, tree, roots, policies}, semantic, scope, basis, None{}}}: [Legacy.BrowserEffect{Web.MeasureFrame{generation}}]
        case _: Nil{}
    case _: Nil{}

def pending_frame_effects_expected(+state: Browser.State) -> +List<Legacy.Effect>:
  +observed_legacy_1 = Browser.legacy(state)
  +observed_web_2 = Legacy.web(observed_legacy_1)
  +realization = Web.realization(observed_web_2)
  +lifecycle = Browser.lifecycle(state)
  +displayed = Browser.displayed(state)
  pending_frame_effects_expected_for(lifecycle, realization, displayed)

def pending_frame_effects_claim(+state: Browser.State) -> Type:
  {Browser.pending_frame_effects(state) == pending_frame_effects_expected(state) : +List<Legacy.Effect>}

def retained_frame_decision_claim(+first: +List<Legacy.Effect>, +state: Browser.State) -> Type:
  {Browser.accepted(False{}, first, state) == Browser.Decision{state,
    List.append(&2, Legacy.Effect, first, pending_frame_effects_expected(state))} : Browser.Decision}

def rebuilt_frame_decision_claim(+first: +List<Legacy.Effect>, +state: Browser.State) -> Type:
  {Browser.accepted(True{}, first, state) == Browser.append(first, Browser.build(0n, state)) : Browser.Decision}

def inspection_frame_expected(frame: Maybe<&2, Rendered.Frame>, +active: +List<InterfaceView.Node>, +layer: Maybe<&2, String>, +dismiss: Maybe<&2, Legacy.DismissTarget>) -> Browser.RenderInspection:
  match frame:
    case None{}: Browser.RenderInspection{None{}, None{}, None{}, layer, dismiss}
    case Some{+observed}:
      Rendered.Frame{viewport, elements, focused, tabs, native_focus} = observed
      Browser.RenderInspection{Some{observed}, Some{Rendered.expected_tabs(active, elements, native_focus)},
        Some{Rendered.native_valid(native_focus, active, elements)}, layer, dismiss}

def inspection_frame(realization: Rendered.State) -> Maybe<&2, Rendered.Frame>:
  match realization:
    case Rendered.AwaitingFrame{generation}: None{}
    case Rendered.Realized{generation, frame}: Some{frame}
    case Rendered.Unmet{generation, frame, violations}: Some{frame}

def inspection_display_expected(+frame: Maybe<&2, Rendered.Frame>, +layer: Maybe<&2, String>, displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  match displayed:
    case None{}: Browser.RenderInspection{frame, None{}, None{}, layer, None{}}
    case Some{Browser.Published{world, semantic, scope, basis, published_frame}}:
      +active = InterfaceView.active_nodes(semantic)
      +dismiss = Legacy.dismiss_target(active)
      inspection_frame_expected(frame, active, layer, dismiss)

def inspection_expected(+stored: Legacy.State, displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  +observed_web_1 = Legacy.web(stored)
  +realization = Web.realization(observed_web_1)
  +layer = Legacy.current_layer_key(stored)
  inspection_display_expected(inspection_frame(realization), layer, displayed)

def inspection_utility_expected(displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  match displayed:
    case None{}: Browser.RenderInspection{None{}, None{}, None{}, None{}, None{}}
    case Some{Browser.Published{+world, semantic, scope, basis, frame}}:
      Browser.RenderInspection{frame, Some{SourceFrame.tabs(SourceFrame.expected(world))}, Some{SourceFrame.no_native(world)}, None{}, None{}}

def inspection_owned_expected(utility: Bool, +stored: Legacy.State, displayed: Maybe<&2, Browser.Published>) -> Browser.RenderInspection:
  match utility:
    case True{}: inspection_utility_expected(displayed)
    case False{}: inspection_expected(stored, displayed)

def render_inspection_claim(+model_state: Browser.State) -> Type:
  {Browser.render_inspection(model_state) ==
    inspection_owned_expected(Browser.auxiliary_owned(model_state), Browser.legacy(model_state), Browser.displayed(model_state)) : Browser.RenderInspection}

law pending_frame_effects:
  for +state: Browser.State
  pending_frame_effects_claim(state)
law retained_frame_decision:
  for +first: +List<Legacy.Effect>
  for +state: Browser.State
  retained_frame_decision_claim(first, state)
law rebuilt_frame_decision:
  for +first: +List<Legacy.Effect>
  for +state: Browser.State
  rebuilt_frame_decision_claim(first, state)
law render_inspection:
  for +model_state: Browser.State
  render_inspection_claim(model_state)

law evidence:
  Requirements
law unconfirmed_publication_has_no_focus_feedback:
  for +document: Doc.Document
  for +fields: +List<Native.Update>
  for +ticket: Nat
  for +before: Maybe<&2, Focus.Target>
  for +after: Maybe<&2, Focus.Target>
  {Browser.publication_focus_feedback(Browser.Publish{0n, document, fields}, ticket, before, after) == None{} : Maybe<&2, Platform.Input>}
law retained_publication_has_no_focus_feedback:
  for +fields: +List<Native.Update>
  for +ticket: Nat
  for +before: Maybe<&2, Focus.Target>
  for +after: Maybe<&2, Focus.Target>
  {Browser.publication_focus_feedback(Browser.KeepPublished{fields}, ticket, before, after) == None{} : Maybe<&2, Platform.Input>}
law absent_focus_has_no_publication_feedback:
  for +publication: Browser.Publication
  for +ticket: Nat
  for +after: Maybe<&2, Focus.Target>
  {Browser.publication_focus_feedback(publication, ticket, None{}, after) == None{} : Maybe<&2, Platform.Input>}
law owned_focus_has_no_publication_feedback:
  for +publication: Browser.Publication
  for +ticket: Nat
  for +before: Maybe<&2, Focus.Target>
  for +after: Focus.Target
  {Browser.publication_focus_feedback(publication, ticket, before, Some{after}) == None{} : Maybe<&2, Platform.Input>}
law confirmed_publication_focus_loss:
  for +generation: Nat
  for +document: Doc.Document
  for +fields: +List<Native.Update>
  for +ticket: Nat
  for +before: Focus.Target
  for confirmed: {Bool.not(Nat.is_eq(generation, 0n)) == True{} : Bool}
  {Browser.publication_focus_feedback(Browser.Publish{generation, document, fields}, ticket, Some{before}, None{}) ==
    Some{Platform.PublicationFocusObserved{ticket, Some{before}, None{}}} : Maybe<&2, Platform.Input>}
def failure_axis_text(axis: Allocation.Axis) -> String:
  match axis:
    case Allocation.InlineAxis{}: "width"
    case Allocation.BlockAxis{}: "height"

def failure_reason_text(reason: Allocation.FailureReason) -> String:
  match reason:
    case Allocation.AuthoredRangeConflict{}: "authored range conflict"
    case Allocation.InsufficientSpace{}: "insufficient space"
    case Allocation.AllocationBoundExceeded{budget}: "allocation bound exceeded (budget " ++ Nat.show(budget) ++ ")"

law failure_message:
  for +key: String
  for +axis: Allocation.Axis
  for +required: Nat
  for +available: Nat
  for +reason: Allocation.FailureReason
  {Browser.failure_message(Allocation.Failure{key, axis, required, available, reason}) ==
    "The interface does not fit the available space: " ++ key ++ "; " ++
      failure_axis_text(axis) ++
      " required " ++ Nat.show(required) ++ "px, available " ++ Nat.show(available) ++ "px; " ++
      failure_reason_text(reason) : String}
law infeasible_candidate_retries:
  for +index: Nat
  for +state: Browser.State
  for +failure: Allocation.Failure
  {Browser.infeasible_candidate(True{}, index, state, failure) == Browser.Searching{(index + 1n : Nat), state} : Browser.Search}
law infeasible_candidate_reports:
  for +model_state: Browser.State
  for +index: Nat
  for +failure: Allocation.Failure
  {Browser.infeasible_candidate(False{}, index, model_state, failure) ==
    Browser.Stopped{Browser.Decision{Browser.with_lifecycle(Browser.Blocked{Browser.failure_message(failure)}, model_state), Nil{}}} : Browser.Search}

law selected_infeasible:
  for +failure: Allocation.Failure
  for +index: Nat
  for +capacity: View.Capacity
  for +engine: World.Engine
  for +state: Browser.State
  for +semantic: InterfaceView.Surface
  for +round: Nat
  {Browser.selected(Plan.Infeasible{failure}, index, capacity, engine, state, semantic, round) ==
    Browser.infeasible_candidate(Nat.is_lt(index, 3n), index, state, failure) : Browser.Search}
