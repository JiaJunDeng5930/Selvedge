import Base
import ../layout/PROGRAM.bend as Allocation
import ../layout/CONTENT.bend as Content
import ../layout/physical-space.bend as Model
import ../layout/RENDERER.bend as Renderer
import ./SOURCE.bend as Source
import ../layout/GEOMETRY.bend as Spatial
import ../controls/GEOMETRY.bend as Geometry
import ./RENDERED.bend as Rendered
import ./MODEL.bend as Doc

type Expected is Data:
  Expected{key: String, bounds: Spatial.Box, interaction: Model.Interaction<Doc.DOMEvent>, exposure: Source.Exposure}

def rectangle(box: Spatial.Box) -> Geometry.Rect:
  Spatial.Box{+left, +top, width, height} = box
  Geometry.Rect{F32.from_nat(left), F32.from_nat(top), F32.from_nat((left + width : Nat)), F32.from_nat((top + height : Nat))}

def ordinary(value: Content.Value) -> Bool:
  Content.Value{node, font} = value
  match node:
    case Source.NativeAttachment{key, target, attrs, style, children}: False{}
    case _: True{}

def value_exposure(parent: Source.Exposure, value: Content.Value) -> Source.Exposure:
  Content.Value{node, font} = value
  Source.combine_exposure(parent, Source.node_exposure(node))

def entry_if(ordinary: Bool, +value: Content.Value, +bounds: Spatial.Box, +interaction: Model.Interaction<Doc.DOMEvent>, exposure: Source.Exposure, rest: +List<Expected>) -> +List<Expected>:
  match ordinary:
    case True{}: Expected{Renderer.observation_key(value), bounds, interaction, exposure} <> rest
    case False{}: rest

def entry(+value: Content.Value, +bounds: Spatial.Box, +interaction: Model.Interaction<Doc.DOMEvent>, rest: +List<Expected>) -> +List<Expected>:
  entry_if(ordinary(value), value, bounds, interaction, value_exposure(Source.Exposed{}, value), rest)

def forest_with(trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>, +parent: Source.Exposure) -> +List<Expected>:
  match trees:
    case Nil{}: Nil{}
    case Con{Allocation.AllocatedLeaf{physical, +value, interaction, rule, demand, height, bounds, canvas}, rest}:
      entry_if(ordinary(value), value, bounds, interaction, value_exposure(parent, value), forest_with(rest, parent))
    case Con{Allocation.AllocatedContainer{physical, +value, interaction, rule, bounds, canvas, direction, children}, rest}:
      +exposure = value_exposure(parent, value)
      entry_if(ordinary(value), value, bounds, interaction, exposure, List.append(&2, Expected, forest_with(children, exposure), forest_with(rest, parent)))

def forest(trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>) -> +List<Expected>:
  forest_with(trees, Source.Exposed{})

def expected(world: Content.AllocatedWorld) -> +List<Expected>:
  Content.AllocatedWorld{snapshot, tree, roots, policies} = world
  forest([tree])

def add_occurrence(same: Bool, count: Nat) -> Nat:
  match same:
    case True{}: (1n + count : Nat)
    case False{}: count

def occurrences(elements: +List<Rendered.Element>, +key: String) -> Nat:
  match elements:
    case Nil{}: 0n
    case Con{Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, bounds, hit, paint}, rest}:
      add_occurrence(String.eq(observed, key), occurrences(rest, key))

def same_rectangle(first: Geometry.Rect, second: Geometry.Rect) -> Bool:
  Geometry.Rect{left, top, right, bottom} = first
  Geometry.Rect{other_left, other_top, other_right, other_bottom} = second
  F32.is_eq(left, other_left) && F32.is_eq(top, other_top) && F32.is_eq(right, other_right) && F32.is_eq(bottom, other_bottom)

def interactive(interaction: Model.Interaction<Doc.DOMEvent>) -> Bool:
  match interaction:
    case Model.DisplayOnly{}: False{}
    case Model.Operable{first, remaining, enabled}: enabled

def operable_exposure(exposure: Source.Exposure, +enabled: Bool, +key: String, +element: Rendered.Element, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match exposure:
    case Source.Concealed{}:
      Rendered.Element{observed, visible, +observed_enabled, tab, keyboard, scroll, bounds, hit, paint} = element
      Rendered.issue(Bool.not(((enabled && observed_enabled) || (Bool.not(enabled) && Bool.not(observed_enabled)))), Rendered.UnreachableControl{key})
    case Source.Exposed{}:
      Rendered.Element{observed, visible, observed_enabled, +tab, keyboard, scroll, bounds, hit, paint} = element
      List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(((enabled && tab) || (Bool.not(enabled) && Bool.not(tab)))), Rendered.UnreachableControl{key}),
        Rendered.control_geometry(enabled, key, Some{Rendered.Element{observed, visible, observed_enabled, tab, keyboard, scroll, bounds, hit, paint}}, True{}, viewport))

def operable_geometry(exposure: Source.Exposure, interaction: Model.Interaction<Doc.DOMEvent>, key: String, element: Rendered.Element, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match interaction:
    case Model.DisplayOnly{}: Nil{}
    case Model.Operable{first, remaining, enabled}: operable_exposure(exposure, enabled, key, element, viewport)

def exposure_geometry(exposure: Source.Exposure, +visible: Bool, tab: Bool, keyboard: Bool, hit: String, bounds: Geometry.Rect, paint: Geometry.Rect, viewport: Geometry.Rect) -> Bool:
  match exposure:
    case Source.Exposed{}: visible && Rendered.paint_geometry_valid(visible, bounds, paint, viewport)
    case Source.Concealed{}: Bool.not(visible) && Bool.not(tab) && Bool.not(keyboard) && String.eq(hit, "")

def node_geometry(+exposure: Source.Exposure, +key: String, +bounds: Spatial.Box, interaction: Model.Interaction<Doc.DOMEvent>, found: Maybe<&2, Rendered.Element>, +viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match found:
    case None{}: [Rendered.MissingElement{key}]
    case Some{+element}:
      Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, measured, hit, paint} = element
      List.append(&2, Rendered.Violation,
        Rendered.issue(Bool.not(same_rectangle(rectangle(bounds), measured) && Geometry.contains(viewport, measured) && exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}),
        operable_geometry(exposure, interaction, key, element, viewport))

def nodes(entries: +List<Expected>, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match entries:
    case Nil{}: Nil{}
    case Con{Expected{+key, bounds, interaction, exposure}, rest}:
      List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Nat.is_eq(occurrences(elements, key), 1n)), Rendered.MissingElement{key}),
        List.append(&2, Rendered.Violation, node_geometry(exposure, key, bounds, interaction, Rendered.find_element(elements, key), viewport), nodes(rest, elements, viewport)))

def tabs(entries: +List<Expected>) -> +List<String>:
  match entries:
    case Nil{}: Nil{}
    case Con{Expected{key, bounds, interaction, exposure}, rest}: Rendered.tab_entry(Source.exposed(exposure) && interactive(interaction), key, tabs(rest))

def controls(entries: +List<Expected>, +elements: +List<Rendered.Element>) -> +List<Rendered.Element>:
  match entries:
    case Nil{}: Nil{}
    case Con{Expected{key, bounds, interaction, exposure}, rest}:
      Rendered.include_element(Source.exposed(exposure) && interactive(interaction), Rendered.find_element(elements, key), controls(rest, elements))

def focused_owned(focused: Maybe<&2, String>, entries: +List<Expected>) -> Bool:
  match focused:
    case None{}: True{}
    case Some{key}: List.contains(String, (first => second => String.eq(first, second)), tabs(entries), key)

def no_native(world: Content.AllocatedWorld) -> Bool:
  Content.AllocatedWorld{snapshot, tree, roots, policies} = world
  match roots policies:
    case Nil{} Nil{}: True{}
    case _ _: False{}

def focus_geometry(focused: Maybe<&2, String>, +elements: +List<Rendered.Element>, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match focused:
    case None{}: Nil{}
    case Some{key}: Rendered.issue(Bool.not(Rendered.focus_visible(Rendered.find_element(elements, key), viewport)), Rendered.InvisibleFocus{})

def native_free(entries: +List<Rendered.NativeFocus>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{first, rest}: False{}

def focus_checks(+focused: Maybe<&2, String>, +entries: +List<Expected>, +elements: +List<Rendered.Element>, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(focused_owned(focused, entries)), Rendered.FocusOutsideScope{}), focus_geometry(focused, elements, viewport))

def check(+world: Content.AllocatedWorld, frame: Rendered.Frame) -> +List<Rendered.Violation>:
  Rendered.Frame{+viewport, +elements, +focused, tab_order, native_focus} = frame
  +entries = expected(world)
  List.append(&2, Rendered.Violation, nodes(entries, elements, viewport),
    List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Rendered.same_order(tabs(entries), tab_order)), Rendered.WrongTabOrder{}),
      List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(no_native(world) && native_free(native_focus)), Rendered.FocusOutsideScope{}),
        List.append(&2, Rendered.Violation, focus_checks(focused, entries, elements, viewport),
          Rendered.independent_targets(controls(entries, elements))))))

def command_enabled(interaction: Model.Interaction<Doc.DOMEvent>) -> Maybe<&2, Bool>:
  match interaction:
    case Model.DisplayOnly{}: None{}
    case Model.Operable{first, remaining, enabled}: Some{enabled}

def value_inert(value: Content.Value) -> Bool:
  Content.Value{node, font} = value
  Source.node_inert(node)

def exposure_entry(inert: Bool, ordinary: Bool, +value: Content.Value, interaction: Model.Interaction<Doc.DOMEvent>, exposure: Source.Exposure) -> +List<Rendered.ControlExposure>:
  match inert ordinary:
    case False{} True{}: [Rendered.ControlExposure{Renderer.observation_key(value), exposure, command_enabled(interaction)}]
    case _ _: Nil{}

def retain_exposure(inert: Bool, own: +List<Rendered.ControlExposure>, rest: +List<Rendered.ControlExposure>) -> +List<Rendered.ControlExposure>:
  match inert:
    case True{}: rest
    case False{}: List.append(&2, Rendered.ControlExposure, own, rest)

def exposure_forest(trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>, +parent: Source.Exposure) -> +List<Rendered.ControlExposure>:
  match trees:
    case Nil{}: Nil{}
    case Con{Allocation.AllocatedLeaf{physical, +value, interaction, rule, demand, height, bounds, canvas}, rest}:
      List.append(&2, Rendered.ControlExposure, exposure_entry(value_inert(value), ordinary(value), value, interaction, value_exposure(parent, value)), exposure_forest(rest, parent))
    case Con{Allocation.AllocatedContainer{physical, +value, interaction, rule, bounds, canvas, direction, children}, rest}:
      +exposure = value_exposure(parent, value)
      retain_exposure(value_inert(value), List.append(&2, Rendered.ControlExposure, exposure_entry(False{}, ordinary(value), value, interaction, exposure), exposure_forest(children, exposure)), exposure_forest(rest, parent))

def expectations(world: Content.AllocatedWorld, frame: Rendered.Frame) -> Rendered.FrameExpectations:
  Content.AllocatedWorld{snapshot, tree, roots, policies} = world
  Rendered.FrameExpectations{exposure_forest([tree], Source.Exposed{})}
