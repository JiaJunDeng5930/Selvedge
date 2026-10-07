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
  Expected{key: String, bounds: Spatial.Box, interaction: Model.Interaction<Doc.DOMEvent>}

def rectangle(box: Spatial.Box) -> Geometry.Rect:
  Spatial.Box{+left, +top, width, height} = box
  Geometry.Rect{F32.from_nat(left), F32.from_nat(top), F32.from_nat((left + width : Nat)), F32.from_nat((top + height : Nat))}

def ordinary(value: Content.Value) -> Bool:
  Content.Value{node, font} = value
  match node:
    case Source.NativeAttachment{key, target, attrs, style, children}: False{}
    case _: True{}

def entry_if(ordinary: Bool, +value: Content.Value, +bounds: Spatial.Box, +interaction: Model.Interaction<Doc.DOMEvent>, rest: +List<Expected>) -> +List<Expected>:
  match ordinary:
    case True{}: Expected{Renderer.observation_key(value), bounds, interaction} <> rest
    case False{}: rest

def entry(+value: Content.Value, +bounds: Spatial.Box, +interaction: Model.Interaction<Doc.DOMEvent>, rest: +List<Expected>) -> +List<Expected>:
  entry_if(ordinary(value), value, bounds, interaction, rest)

def forest(trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>) -> +List<Expected>:
  match trees:
    case Nil{}: Nil{}
    case Con{Allocation.AllocatedLeaf{physical, value, interaction, rule, demand, height, bounds, canvas}, rest}:
      entry(value, bounds, interaction, forest(rest))
    case Con{Allocation.AllocatedContainer{physical, value, interaction, rule, bounds, canvas, direction, children}, rest}:
      entry(value, bounds, interaction, List.append(&2, Expected, forest(children), forest(rest)))

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

def operable_geometry(interaction: Model.Interaction<Doc.DOMEvent>, +key: String, element: Rendered.Element, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match interaction:
    case Model.DisplayOnly{}: Nil{}
    case Model.Operable{first, remaining, +enabled}:
      Rendered.Element{observed, visible, observed_enabled, +tab, keyboard, scroll, bounds, hit, paint} = element
      List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(((enabled && tab) || (Bool.not(enabled) && Bool.not(tab)))), Rendered.UnreachableControl{key}),
        Rendered.control_geometry(enabled, key, Some{Rendered.Element{observed, visible, observed_enabled, tab, keyboard, scroll, bounds, hit, paint}}, True{}, viewport))

def node_geometry(+key: String, +bounds: Spatial.Box, interaction: Model.Interaction<Doc.DOMEvent>, found: Maybe<&2, Rendered.Element>, +viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match found:
    case None{}: [Rendered.MissingElement{key}]
    case Some{+element}:
      Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, measured, hit, paint} = element
      List.append(&2, Rendered.Violation,
        Rendered.issue(Bool.not(visible && same_rectangle(rectangle(bounds), measured) && Geometry.contains(viewport, measured) && Rendered.paint_geometry_valid(visible, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}),
        operable_geometry(interaction, key, element, viewport))

def nodes(entries: +List<Expected>, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match entries:
    case Nil{}: Nil{}
    case Con{Expected{+key, bounds, interaction}, rest}:
      List.append(&2, Rendered.Violation, Rendered.issue(Bool.not(Nat.is_eq(occurrences(elements, key), 1n)), Rendered.MissingElement{key}),
        List.append(&2, Rendered.Violation, node_geometry(key, bounds, interaction, Rendered.find_element(elements, key), viewport), nodes(rest, elements, viewport)))

def tabs(entries: +List<Expected>) -> +List<String>:
  match entries:
    case Nil{}: Nil{}
    case Con{Expected{key, bounds, interaction}, rest}: Rendered.tab_entry(interactive(interaction), key, tabs(rest))

def controls(entries: +List<Expected>, +elements: +List<Rendered.Element>) -> +List<Rendered.Element>:
  match entries:
    case Nil{}: Nil{}
    case Con{Expected{key, bounds, interaction}, rest}:
      Rendered.include_element(interactive(interaction), Rendered.find_element(elements, key), controls(rest, elements))

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
