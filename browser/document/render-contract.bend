import ../../interaction/experience/MODEL.bend as UXTypes
import ../../interaction/experience/PROGRAM.bend as UX
import Base
import ../controls/MODEL.bend as Authored
import ./SOURCE.bend as Source
import ../appearance/DESIGN.bend as Design
import ../layout/enclosure.bend as Enclosure
import ../../interaction/presentation/PROGRAM.bend as Interface
import ../../interaction/presentation/CONTRACT.bend as FenceRules
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/conversation/OUTPUT.bend as Live
import ./MODEL.bend as Observation
import ../runtime/MODEL.bend as Browser
import ../layout/CONTENT.bend as Content
import ../runtime/SEMANTICS.bend as Legacy
import ../MODEL.bend as Web
import ../runtime/PLATFORM.bend as Platform
import ../../interaction/MODEL.bend as Product
import ../../interaction/STATE.bend as Core
import ../../interaction/session/MODEL.bend as E
import ../../interaction/conversation/CODE.bend as Code
import ../../interaction/TYPES.bend as InteractionTypes
import ../../harness/DOMAIN.bend as D
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ./RENDERED.bend as Model
import ./SPEC.bend as Spec
import ../controls/GEOMETRY.bend as Geometry
import ../../interaction/presentation/MODEL.bend as View
import ./FRAME.bend as Frame
import ../layout/PROGRAM.bend as Allocation
import ../layout/GEOMETRY.bend as Spatial
import ../layout/SPACE.bend as Space
import ../layout/physical-space.bend as Model2

def frame_is_canonical(+visual: Design.Style) -> Type:
  {Source.code_surface_frame(Authored.code_surface(visual)) == Design.style_frame(visual) : Enclosure.Frame}

def chrome_is_canonical(+visual: Design.Style) -> Type:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  {Source.code_surface_chrome(Authored.code_surface(visual)) == chrome : Design.Chrome}

def policy_uses_code_surface(visual: Design.Style, +code_visual: Design.Style, reserve: Nat) -> Type:
  {Source.rich_policy_code_surface(Authored.rich_policy(visual, code_visual, reserve)) == Authored.code_surface(code_visual) : Source.CodeSurface}

type CodeSurfaceRequirements is Type:
  CodeSurfaceRequirements{
    canonical_frame: @+visual:Design.Style -> frame_is_canonical(visual),
    canonical_chrome: @+visual:Design.Style -> chrome_is_canonical(visual),
    policy_projection: @visual:Design.Style -> @+code_visual:Design.Style -> @reserve:Nat -> policy_uses_code_surface(visual, code_visual, reserve)
  }

law code_surface_evidence:
  CodeSurfaceRequirements

def expected_known_code_observations(observations: +List<Observation.Observation>, +session: E.Session) -> Bool:
  match observations:
    case Nil{}: True{}
    case Con{Observation.Observation{identity, text, source_value}, rest}:
      E.code_source_known(identity, session) && expected_known_code_observations(rest, session)

def observation_session(state: Browser.State) -> E.Session:
  E.session(Core.application(Platform.core(Web.application(Legacy.web(Browser.legacy(state))))))

def published_display_claim(displayed: Maybe<&2, Browser.Published>, +generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State) -> Type:
  match displayed:
    case None{}: {Browser.code_batch_qualified(generation, observations, state) == False{} : Bool}
    case Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
      {Browser.code_batch_qualified(generation, observations, state) ==
        (Browser.code_batch_owned(observations, source) && expected_known_code_observations(observations, observation_session(state))) : Bool}

def published_qualification_claim(+generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State) -> Type:
  published_display_claim(Browser.displayed(state), generation, observations, state)

law published_qualification:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  published_qualification_claim(generation, observations, state)

law rejected_batch:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  for rejected: {Browser.code_batch_qualified(generation, observations, state) == False{} : Bool}
  {Browser.code_sources(generation, observations, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law qualified_batch:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  for qualified: {Browser.code_batch_qualified(generation, observations, state) == True{} : Bool}
  {Browser.code_sources(generation, observations, state) ==
    Browser.accept(True{}, Browser.code_sources_fold(observations, Legacy.Decision{Browser.legacy(state), Nil{}}), state) : Browser.Decision}

law empty_batch:
  for +generation: Nat
  for +state: Browser.State
  {Browser.code_sources(generation, Nil{}, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

# NOTE: Rejection concerns the published source version, independently of tracing generation.

law unowned_entry:
  for +identity: Code.Identity
  for +text: String
  for +source_value: String
  for +rest: +List<Observation.Observation>
  for +source: Source.Node
  for unowned: {Browser.code_source_owned(source, identity, source_value) == False{} : Bool}
  {Browser.code_batch_owned(Con{Observation.Observation{identity, text, source_value}, rest}, source) == False{} : Bool}

law unowned_tail:
  for +observation: Observation.Observation
  for +rest: +List<Observation.Observation>
  for +source: Source.Node
  for invalid: {Browser.code_observations_owned(rest, source) == False{} : Bool}
  {Browser.code_batch_owned(Con{observation, rest}, source) == False{} : Bool}

law fold_empty:
  for decision: Legacy.Decision
  {Browser.code_sources_fold(Nil{}, decision) == decision : Legacy.Decision}

law fold_order:
  for source: Code.Source
  for ordinal: Nat
  for text: String
  for source_value: String
  for rest: +List<Observation.Observation>
  for state: Legacy.State
  for effects: +List<Legacy.Effect>
  {Browser.code_sources_fold(Con{Observation.Observation{Code.Identity{source, ordinal}, text, source_value}, rest}, Legacy.Decision{state, effects}) ==
    Browser.code_sources_fold(rest, Legacy.append_decision(effects, Legacy.code_source(source, ordinal, text, state))) : Legacy.Decision}

law native_batch:
  for generation: Nat
  for observations: +List<Observation.Observation>
  for state: Browser.State
  {Browser.step(Legacy.Native{Web.CodeSourcesObserved{generation, observations}}, state) == Browser.code_sources(generation, observations, state) : Browser.Decision}

law raw_source_rejected:
  for identity: Code.Identity
  for text: String
  for state: Browser.State
  {Browser.step(Legacy.Native{Web.PlatformInput{Platform.ProductInput{Product.CodeSource{identity, text}}}}, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law raw_content_rejected:
  for identity: Code.Identity
  for text: String
  for state: Browser.State
  {Browser.step(Legacy.Native{Web.PlatformInput{Platform.ProductInput{Product.InterfaceInput{InteractionTypes.ApplicationInput{E.ContentInput{identity, Code.SourceChanged{text}}}}}}}, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

def direct_web_claim(+generation: Nat, +observations: +List<Observation.Observation>, +state: Web.State) -> Type:
  +application = Web.application(state)
  +serial = Web.generation(state)
  +realization = Web.realization(state)
  +environment = Web.environment(state)
  +font = Web.typography(state)
  {Web.step(Web.CodeSourcesObserved{generation, observations}, state) == Web.idle(application, serial, realization, environment, font) : Web.Decision}

law direct_web_rejected:
  for generation: Nat
  for observations: +List<Observation.Observation>
  for +state: Web.State
  direct_web_claim(generation, observations, state)

def missing_publication_claim(+generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State) -> Type:
  {Browser.code_sources(generation, observations, Browser.with_displayed(None{}, state)) ==
    Browser.Decision{Browser.with_displayed(None{}, state), Nil{}} : Browser.Decision}

law missing_publication:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  missing_publication_claim(generation, observations, state)

law all_entries:
  for identity: Code.Identity
  for text: String
  for source_value: String
  for rest: +List<Observation.Observation>
  for source: Source.Node
  {Browser.code_batch_owned(Con{Observation.Observation{identity, text, source_value}, rest}, source) ==
    (Browser.code_source_owned(source, identity, source_value) && Browser.code_observations_owned(rest, source)) : Bool}

def declared_content_claim(owner: Code.Source, identity: Code.Identity, value: String, source_value: String) -> Bool:
  Code.Identity{source, ordinal} = identity
  Browser.code_same_source(owner, source) && String.eq(value, source_value)

law declared_content:
  for +owner: Code.Source
  for +identity: Code.Identity
  for +value: String
  for +source_value: String
  for policy: Source.RichPolicy
  {Browser.code_content_owned(Source.RichContent{Some{owner}, value, policy}, identity, source_value) ==
    declared_content_claim(owner, identity, value, source_value) : Bool}

law undeclared_content:
  for +identity: Code.Identity
  for +value: String
  for +source_value: String
  for policy: Source.RichPolicy
  {Browser.code_content_owned(Source.RichContent{None{}, value, policy}, identity, source_value) == False{} : Bool}

law generation_independent:
  for +first: Nat
  for +second: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  {Browser.code_batch_qualified(first, observations, state) ==
    Browser.code_batch_qualified(second, observations, state) : Bool}

def published_membership(displayed: Maybe<&2, Browser.Published>, observations: +List<Observation.Observation>) -> Bool:
  match displayed:
    case None{}: False{}
    case Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
      Browser.code_batch_owned(observations, source)

def actual_membership(+observations: +List<Observation.Observation>, +state: Browser.State) -> Bool:
  published_membership(Browser.displayed(state), observations) && expected_known_code_observations(observations, observation_session(state))

law stale_batch:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  for stale: {actual_membership(observations, state) == False{} : Bool}
  {Browser.code_sources(generation, observations, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law invalid_published_batch:
  for +generation: Nat
  for +observations: +List<Observation.Observation>
  for +state: Browser.State
  for invalid: {actual_membership(observations, state) == False{} : Bool}
  {Browser.code_sources(generation, observations, state) == Browser.Decision{state, Nil{}} : Browser.Decision}

law authored_source:
  for +key: Identity.Key
  for +value: String
  for +visual: Design.Style
  for +code_visual: Design.Style
  for +owner: Code.Source
  for +attachments: +List<Source.Node>
  for +native_owner: Maybe<&2, String>
  for +identity: Code.Identity
  for +source_value: String
  {Browser.code_node_owned(Authored.rich_leaf(key, value, visual, code_visual, Some{owner}, attachments, native_owner), identity, source_value) ==
    declared_content_claim(owner, identity, value, source_value) : Bool}

def expected_preview_origin(origin: Maybe<&2, D.OutputOrigin>, namespace: String, +task: Nat, operation: Nat, part: Nat) -> Code.Source:
  match origin:
    case None{}: Code.StreamingPart{task, operation, part}
    case Some{value}: Code.Generated{namespace, task, value, False{}}

def expected_preview_source(+task: Nat, +operation: Nat, +part: Nat, +state: InteractionTypes.State) -> Code.Source:
  expected_preview_origin(Live.origin(Live.Output{task, operation, Nil{}}, part, E.program(Core.application(state))),
    E.namespace(E.session(Core.application(state))), task, operation, part)

def expected_output_key(+source: Code.Source, fallback: Identity.Key) -> Identity.Key:
  match source:
    case Code.Generated{namespace, viewer, origin, complete}: Identity.Entity{Identity.Place{"generated-output"}, "part", Code.source_key(source)}
    case _: fallback

type StreamPartPresentation<-task: Nat, -operation: Nat, -part: Nat, -text: String,
  -parent: Identity.Key, -state: InteractionTypes.State> is Type:
  StreamPartPresentation{
    node: SurfaceTypes.Node,
    complete: {Interface.live_parts([Live.Part{part, text}], task, operation, parent, state) == [node] : +List<SurfaceTypes.Node>},
    attachments: FenceRules.LivePartAttachments(part, text, task, operation, parent, state, node)
  }

law stream_source:
  @+task:Nat -> @+operation:Nat -> @+index:Nat -> @+text:String -> @+parent:Identity.Key -> @+state:InteractionTypes.State ->
  StreamPartPresentation<task, operation, index, text, parent, state>

law stale_frame_retains_state:
  for +current: Nat
  for +received: Nat
  for +surface: SurfaceTypes.Surface
  for +frame: Model.Frame
  for +previous: Model.State
  for different: {Nat.is_eq(current, received) == False{} : Bool}
  {Model.observe(current, received, surface, frame, previous) == previous : Model.State}

law absent_control_is_not_tab_stop:
  {Model.tab_stop(None{}) == False{} : Bool}

law observed_tab_participation:
  for key: String
  for +visible: Bool
  for +enabled: Bool
  for +tab: Bool
  for keyboard: Bool
  for +scroll: Bool
  for bounds: Geometry.Rect
  for hit: String
  for paint_bounds: Geometry.Rect
  {Model.tab_stop(Some{Model.Element{key,visible,enabled,tab,keyboard,scroll,bounds,hit, paint_bounds}}) == (enabled && tab && (visible || scroll)) : Bool}

law dialog_actions_persistent:
  {Model.persistent(SurfaceTypes.DialogActions{}) == True{} : Bool}

law dialog_actions_bounded:
  for key: String
  for found: Maybe<&2, Model.Element>
  for viewport: Geometry.Rect
  {Model.region_geometry(SurfaceTypes.DialogActions{}, key, found, viewport) == Model.bounded_dialog(key, found, viewport) : +List<Model.Violation>}

# Independent controls use paint regions; complete layout bounds remain intact.

def element_paint(element: Model.Element) -> Geometry.Rect:
  Model.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds} = element
  paint_bounds

law disjoint_paint_controls_do_not_overlap:
  for +first: Model.Element
  for +second: Model.Element
  for disjoint: {Model.overlaps(element_paint(first), element_paint(second)) == False{} : Bool}
  {Model.against(first, [second]) == Nil{} : +List<Model.Violation>}

law observed_visible_paint_is_bounded:
  for +bounds: Geometry.Rect
  for +paint_bounds: Geometry.Rect
  for +viewport: Geometry.Rect
  {Model.paint_geometry_valid(True{}, bounds, paint_bounds, viewport) ==
    (Geometry.contains(bounds, paint_bounds) && Geometry.contains(viewport, paint_bounds)) : Bool}

law observed_hidden_paint_is_inactive:
  for bounds: Geometry.Rect
  for paint_bounds: Geometry.Rect
  for viewport: Geometry.Rect
  {Model.paint_geometry_valid(False{}, bounds, paint_bounds, viewport) == True{} : Bool}

law observed_code_in_view:
  for key: String
  for +visible: Bool
  for enabled: Bool
  for tab: Bool
  for keyboard: Bool
  for scroll: Bool
  for bounds: Geometry.Rect
  for hit: String
  for +paint_bounds: Geometry.Rect
  for +viewport: Geometry.Rect
  {Model.code_in_view(SurfaceTypes.CodeBlock{}, Some{Model.Element{key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds}}, viewport) ==
    (visible && Model.overlaps(paint_bounds, viewport)) : Bool}

law unpainted_code_is_not_in_view:
  for key: String
  for enabled: Bool
  for tab: Bool
  for keyboard: Bool
  for scroll: Bool
  for bounds: Geometry.Rect
  for hit: String
  for paint_bounds: Geometry.Rect
  for viewport: Geometry.Rect
  {Model.code_in_view(SurfaceTypes.CodeBlock{}, Some{Model.Element{key,False{},enabled,tab,keyboard,scroll,bounds,hit,paint_bounds}}, viewport) == False{} : Bool}

law cropped_disjoint_code_is_not_in_view:
  for key: String
  for +visible: Bool
  for enabled: Bool
  for tab: Bool
  for keyboard: Bool
  for scroll: Bool
  for bounds: Geometry.Rect
  for hit: String
  for +paint_bounds: Geometry.Rect
  for +viewport: Geometry.Rect
  for disjoint: {Model.overlaps(paint_bounds, viewport) == False{} : Bool}
  {Model.code_in_view(SurfaceTypes.CodeBlock{}, Some{Model.Element{key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds}}, viewport) == False{} : Bool}

law movement_is_interactive:
  for destinations: +List<SurfaceTypes.Placement>
  for face: View.CardFace
  {Model.interactive(SurfaceTypes.MovableCard{destinations, face}) == True{} : Bool}

law movement_enabled_by_offered_input:
  for +destinations: +List<SurfaceTypes.Placement>
  for face: View.CardFace
  {Model.required_enabled(SurfaceTypes.MovableCard{destinations, face}) == Interface.has_available_destination(destinations) : Bool}

type SourceFrameRequirements is Type:
  SourceFrameRequirements{
    normal_projection: @+world:Content.AllocatedWorld -> @+frame:Model.Frame ->
      {Frame.expectations(world, frame) == Spec.allocated_expectations(world, frame) : Model.FrameExpectations},
    complete_observation: @+current:Nat -> @+received:Nat -> @+surface:SurfaceTypes.Surface -> @+frame:Model.Frame -> @+previous:Model.State -> @+expectations:Model.FrameExpectations ->
      {Model.observe_with(current, received, surface, frame, previous, expectations) == Spec.observed_frame(current, received, surface, frame, previous, expectations) : Model.State},
    complete_allocation: @+world:Content.AllocatedWorld -> @+frame:Model.Frame ->
      {Frame.check(world, frame) == Spec.allocated_frame_diagnostics(world, frame) : +List<Model.Violation>}}

law source_frame_evidence:
  SourceFrameRequirements

law supporting_is_interactive:
  for +support: UXTypes.Support
  for property: UXTypes.Property
  for input: InteractionTypes.Input
  for availability: View.Availability
  {Model.interactive(SurfaceTypes.SupportingControl{support, property, input, availability}) == UX.support_visible(support) : Bool}

law supporting_enabled_by_availability:
  for +support: UXTypes.Support
  for property: UXTypes.Property
  for input: InteractionTypes.Input
  for +availability: View.Availability
  {Model.required_enabled(SurfaceTypes.SupportingControl{support, property, input, availability}) == UX.support_visible(support) && Model.enabled(availability) : Bool}

# Public requirements describe engineering results, not a prepared lookup tree.
law complete_element_lookup:
  @+elements:+List<Model.Element> -> @+key:String ->
  {Model.find_element(elements, key) == Spec.first_observed_element(elements, key) : Maybe<&2, Model.Element>}

law complete_ordered_tabs:
  @+nodes:+List<SurfaceTypes.Node> -> @+elements:+List<Model.Element> -> @+native_focus:+List<Model.NativeFocus> ->
  {Model.expected_tabs(nodes, elements, native_focus) == Spec.expected_tabs(nodes, elements, native_focus) : +List<String>}

law complete_native_ownership:
  @+native_focus:+List<Model.NativeFocus> -> @+nodes:+List<SurfaceTypes.Node> -> @+elements:+List<Model.Element> ->
  {Model.native_valid(native_focus, nodes, elements) == Spec.native_valid(native_focus, nodes, elements) : Bool}

law complete_layout_check_with:
  @+active:+List<SurfaceTypes.Node> -> @+frame:Model.Frame -> @+controls:+List<Model.ControlExposure> ->
  {Model.layout_check_with(active, frame, controls) == Spec.layout_diagnostics(active, frame, controls) : +List<Model.Violation>}

law complete_check:
  @+active:+List<SurfaceTypes.Node> -> @+frame:Model.Frame ->
  {Model.check(active, frame) == Spec.check_diagnostics(active, frame) : +List<Model.Violation>}

law complete_violations:
  @+surface:SurfaceTypes.Surface -> @+frame:Model.Frame ->
  {Model.violations(surface, frame) == Spec.ordinary_frame_diagnostics(surface, frame) : +List<Model.Violation>}

law complete_violations_with:
  @+surface:SurfaceTypes.Surface -> @+frame:Model.Frame -> @+expectations:Model.FrameExpectations ->
  {Model.violations_with(surface, frame, expectations) == Spec.frame_diagnostics(surface, frame, expectations) : +List<Model.Violation>}

law complete_observation:
  @+current:Nat -> @+received:Nat -> @+surface:SurfaceTypes.Surface -> @+frame:Model.Frame -> @+previous:Model.State -> @+expectations:Model.FrameExpectations ->
  {Model.observe_with(current, received, surface, frame, previous, expectations) ==
    Spec.observed_frame(current, received, surface, frame, previous, expectations) : Model.State}

law complete_ordinary_observation:
  @+current:Nat -> @+received:Nat -> @+surface:SurfaceTypes.Surface -> @+frame:Model.Frame -> @+previous:Model.State ->
  {Model.observe(current, received, surface, frame, previous) == Spec.ordinary_observed_frame(current, received, surface, frame, previous) : Model.State}

law complete_allocated_frame:
  @+world:Content.AllocatedWorld -> @+frame:Model.Frame ->
  {Frame.check(world, frame) == Spec.allocated_frame_diagnostics(world, frame) : +List<Model.Violation>}
