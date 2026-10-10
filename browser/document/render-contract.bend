import Base
import ../controls/MODEL.bend as Authored
import ./SOURCE.bend as Source
import ../appearance/DESIGN.bend as Design
import ../layout/enclosure.bend as Enclosure
import ../../interaction/presentation/PROGRAM.bend as Interface
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
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ./RENDERED.bend as Model
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

def published_display_claim(displayed: Maybe<&2, Browser.Published>, +generation: Nat, +observations: +List<Observation.Observation>, +state: Browser.State) -> Type:
  match displayed:
    case None{}: {Browser.code_batch_qualified(generation, observations, state) == False{} : Bool}
    case Some{Browser.Published{Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}, semantic, scope, basis, frame}}:
      {Browser.code_batch_qualified(generation, observations, state) ==
        Browser.code_batch_owned(observations, source) : Bool}

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

def actual_membership(observations: +List<Observation.Observation>, +state: Browser.State) -> Bool:
  published_membership(Browser.displayed(state), observations)

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

law stream_source:
  for +task: Nat
  for +operation: Nat
  for +index: Nat
  for +text: String
  for +parent: Identity.Key
  for +state: InteractionTypes.State
  {Interface.live_parts([Live.Part{index, text}], task, operation, parent, state) ==
    [SurfaceTypes.Node{Identity.Entity{parent, "part", Nat.show(index)}, "stream/part/" ++ Nat.show(index), "Agent output", SurfaceTypes.Content{},
      SurfaceTypes.RichText{Code.StreamingPart{task, operation, index}, text},
      Interface.code_nodes(Core.code_scenes(Interface.application(state)), Code.StreamingPart{task, operation, index}, Identity.Entity{parent, "part", Nat.show(index)})}] : +List<SurfaceTypes.Node>}

law stale_frame_retains_state:
  for +current: Nat
  for +received: Nat
  for +surface: SurfaceTypes.Surface
  for +frame: Model.Frame
  for +previous: Model.State
  for different: {Nat.is_eq(current, received) == False{} : Bool}
  {Model.observe(current, received, surface, frame, previous) == previous : Model.State}

law native_ownership_is_complete:
  for +identity: String
  for owner: String
  for +rest: +List<Model.NativeFocus>
  for +active: +List<SurfaceTypes.Node>
  for +elements: +List<Model.Element>
  {Model.native_valid(Model.NativeFocus{identity, owner} <> rest, active, elements) ==
    (Model.read_only(Interface.find_node(active, owner)) && Bool.not(Model.exists(Interface.find_node(active, identity))) &&
     Model.native_element(Model.find_element(elements, identity)) && Bool.not(Model.native_member(rest, identity)) && Model.native_valid(rest, active, elements)) : Bool}

law native_order_is_owned:
  for +owner: String
  for +identity: String
  for +parent: String
  for rest: +List<Model.NativeFocus>
  {Model.owner_tabs(Model.NativeFocus{identity, parent} <> rest, owner) ==
    Model.tab_entry(String.eq(parent, owner), identity, Model.owner_tabs(rest, owner)) : +List<String>}

law native_tab_contract:
  for +active: +List<SurfaceTypes.Node>
  for +elements: +List<Model.Element>
  for +native_focus: +List<Model.NativeFocus>
  for order: +List<String>
  {Model.tabs_valid(active, elements, native_focus, order) ==
    (Model.native_valid(native_focus, active, elements) && Model.same_order(Model.expected_tabs(active, elements, native_focus), order)) : Bool}

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
    actual_tree: @+snapshot:Content.Snapshot -> @+tree:Allocation.AllocatedTree<Content.Value, Observation.DOMEvent> -> @+roots:+List<Content.AllocatedNative> -> @+policies:+List<Content.NativePolicy> ->
      {Frame.expected(Content.AllocatedWorld{snapshot, tree, roots, policies}) == Frame.forest([tree]) : +List<Frame.Expected>},
    complete_node: @+key:String -> @+bounds:Spatial.Box -> @+interaction:Model2.Interaction<Observation.DOMEvent> -> @+rest:+List<Frame.Expected> -> @+elements:+List<Model.Element> -> @+viewport:Geometry.Rect ->
      {Frame.nodes(Frame.Expected{key, bounds, interaction} <> rest, elements, viewport) ==
        List.append(&2, Model.Violation, Model.issue(Bool.not(Nat.is_eq(Frame.occurrences(elements, key), 1n)), Model.MissingElement{key}),
          List.append(&2, Model.Violation, Frame.node_geometry(key, bounds, interaction, Model.find_element(elements, key), viewport), Frame.nodes(rest, elements, viewport))) : +List<Model.Violation>},
    source_tab_order: @+key:String -> @+bounds:Spatial.Box -> @+interaction:Model2.Interaction<Observation.DOMEvent> -> @+rest:+List<Frame.Expected> ->
      {Frame.tabs(Frame.Expected{key, bounds, interaction} <> rest) == Model.tab_entry(Frame.interactive(interaction), key, Frame.tabs(rest)) : +List<String>},
    leaf_traversal: @+physical:String -> @+value:Content.Value -> @+interaction:Model2.Interaction<Observation.DOMEvent> -> @+rule:Model2.Rule -> @+demand:Space.Demand -> @+height:Model2.Height -> @+bounds:Spatial.Box -> @+canvas:Enclosure.Extent -> @+rest:+List<Allocation.AllocatedTree<Content.Value, Observation.DOMEvent>> ->
      {Frame.forest(Allocation.AllocatedLeaf{physical, value, interaction, rule, demand, height, bounds, canvas} <> rest) == Frame.entry(value, bounds, interaction, Frame.forest(rest)) : +List<Frame.Expected>},
    container_traversal: @+physical:String -> @+value:Content.Value -> @+interaction:Model2.Interaction<Observation.DOMEvent> -> @+rule:Model2.Rule -> @+bounds:Spatial.Box -> @+canvas:Enclosure.Extent -> @+direction:Allocation.ResolvedDirection -> @+children:+List<Allocation.AllocatedTree<Content.Value, Observation.DOMEvent>> -> @+rest:+List<Allocation.AllocatedTree<Content.Value, Observation.DOMEvent>> ->
      {Frame.forest(Allocation.AllocatedContainer{physical, value, interaction, rule, bounds, canvas, direction, children} <> rest) == Frame.entry(value, bounds, interaction, List.append(&2, Frame.Expected, Frame.forest(children), Frame.forest(rest))) : +List<Frame.Expected>},
    full_contract: @+world:Content.AllocatedWorld -> @+viewport:Geometry.Rect -> @+elements:+List<Model.Element> -> @+focused:Maybe<&2, String> -> @+tab_order:+List<String> -> @+native_focus:+List<Model.NativeFocus> ->
      {Frame.check(world, Model.Frame{viewport, elements, focused, tab_order, native_focus}) ==
        List.append(&2, Model.Violation, Frame.nodes(Frame.expected(world), elements, viewport),
          List.append(&2, Model.Violation, Model.issue(Bool.not(Model.same_order(Frame.tabs(Frame.expected(world)), tab_order)), Model.WrongTabOrder{}),
            List.append(&2, Model.Violation, Model.issue(Bool.not(Frame.no_native(world) && Frame.native_free(native_focus)), Model.FocusOutsideScope{}),
              List.append(&2, Model.Violation, Frame.focus_checks(focused, Frame.expected(world), elements, viewport),
                Model.independent_targets(Frame.controls(Frame.expected(world), elements)))))) : +List<Model.Violation>},
    allocated_rectangle: @+left:Nat -> @+top:Nat -> @+width:Nat -> @+height:Nat ->
      {Frame.rectangle(Spatial.Box{left, top, width, height}) == Geometry.Rect{F32.from_nat(left), F32.from_nat(top), F32.from_nat((left + width : Nat)), F32.from_nat((top + height : Nat))} : Geometry.Rect},
    observed_geometry: @+key:String -> @+bounds:Spatial.Box -> @+interaction:Model2.Interaction<Observation.DOMEvent> -> @+viewport:Geometry.Rect -> @+observed:String -> @+visible:Bool -> @+enabled:Bool -> @+tab:Bool -> @+keyboard:Bool -> @+scroll:Bool -> @+measured:Geometry.Rect -> @+hit:String -> @+paint:Geometry.Rect ->
      {Frame.node_geometry(key, bounds, interaction, Some{Model.Element{observed, visible, enabled, tab, keyboard, scroll, measured, hit, paint}}, viewport) ==
        List.append(&2, Model.Violation, Model.issue(Bool.not(visible && Frame.same_rectangle(Frame.rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Model.paint_geometry_valid(visible, measured, paint, viewport)), Model.InvalidPaintGeometry{key}),
          Frame.operable_geometry(interaction, key, Model.Element{observed, visible, enabled, tab, keyboard, scroll, measured, hit, paint}, viewport)) : +List<Model.Violation>},
    focus_contract: @+focused:Maybe<&2, String> -> @+entries:+List<Frame.Expected> -> @+elements:+List<Model.Element> -> @+viewport:Geometry.Rect ->
      {Frame.focus_checks(focused, entries, elements, viewport) == List.append(&2, Model.Violation, Model.issue(Bool.not(Frame.focused_owned(focused, entries)), Model.FocusOutsideScope{}), Frame.focus_geometry(focused, elements, viewport)) : +List<Model.Violation>},
    display_only: @+key:String -> @+element:Model.Element -> @+viewport:Geometry.Rect ->
      {Frame.operable_geometry(Model2.DisplayOnly{}, key, element, viewport) == Nil{} : +List<Model.Violation>}}

law source_frame_evidence:
  SourceFrameRequirements
