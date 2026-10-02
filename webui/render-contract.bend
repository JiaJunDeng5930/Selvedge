import Base
import ../core/interface.bend as UI
import ./interaction.bend as Geometry
import ./rendered.bend as Rendered

def same_bool(+first: Bool, +second: Bool) -> Bool:
  (first && second) || (Bool.not(first) && Bool.not(second))

def enabled_geometry_valid(required: Bool, key: String, +visible: Bool,
  keyboard: Bool, scroll: Bool, bounds: Geometry.Rect, hit: String,
  must_be_visible: Bool, viewport: Geometry.Rect) -> Bool:
  match required:
    case False{}: True{}
    case True{}:
      Bool.not(Bool.not(keyboard && (visible || scroll)) ||
        (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds)))) &&
      Bool.not(visible && Bool.not(String.eq(key, hit)))

def control_geometry_valid(+required: Bool, key: String, found: Maybe<&2, Rendered.Element>,
  must_be_visible: Bool, viewport: Geometry.Rect) -> Bool:
  match found:
    case None{}: False{}
    case Some{Rendered.Element{observed_key, +visible, +enabled, tab, +keyboard, +scroll, +bounds, +hit}}:
      same_bool(required, enabled) &&
      enabled_geometry_valid(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)

def node_controls_valid(is_control: Bool, meaning: UI.Meaning, key: String,
  found: Maybe<&2, Rendered.Element>, must_be_visible: Bool, viewport: Geometry.Rect) -> Bool:
  match is_control:
    case False{}: True{}
    case True{}:
      control_geometry_valid(Rendered.required_enabled(meaning), key, found, must_be_visible, viewport)

def bounded_region(found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  match found:
    case None{}: False{}
    case Some{Rendered.Element{key, +visible, enabled, tab, keyboard, scroll, +bounds, hit}}:
      visible && Geometry.contains(viewport, bounds)

def reachable_toolbar(found: Maybe<&2, Rendered.Element>) -> Bool:
  match found:
    case None{}: False{}
    case Some{Rendered.Element{id, visible, enabled, tab, keyboard, scroll, bounds, hit}}:
      visible || scroll

def region_geometry_valid(role: UI.Role, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  match role:
    case UI.Navigation{}: bounded_region(found, viewport)
    case UI.NavigationHeader{}: bounded_region(found, viewport)
    case UI.Main{}: bounded_region(found, viewport)
    case UI.Heading{}: True{}
    case UI.Timeline{}: True{}
    case UI.Activity{}: True{}
    case UI.Composer{}: bounded_region(found, viewport)
    case UI.Approval{}: True{}
    case UI.Toolbar{}: reachable_toolbar(found)
    case UI.CodeBlock{}: True{}
    case UI.ApprovalQueue{}: bounded_region(found, viewport)
    case UI.Section{}: True{}
    case UI.Dialog{}: bounded_region(found, viewport)
    case UI.Menu{}: bounded_region(found, viewport)
    case UI.Details{}: True{}
    case UI.Card{}: True{}
    case UI.Button{}: True{}
    case UI.PrimaryButton{}: True{}
    case UI.DestructiveButton{}: True{}
    case UI.SelectedButton{}: True{}
    case UI.Field{}: True{}
    case UI.Content{}: True{}
    case UI.Alert{}: True{}
    case UI.UserMessage{}: True{}
    case UI.AssistantMessage{}: True{}
    case UI.ComposerActions{}: True{}

def node_geometry_valid(found: Maybe<&2, Rendered.Element>, is_control: Bool,
  meaning: UI.Meaning, role: UI.Role, key: String, must_be_visible: Bool,
  +viewport: Geometry.Rect) -> Bool:
  match found:
    case None{}: False{}
    case Some{+element}:
      node_controls_valid(is_control, meaning, key, Some{element}, must_be_visible, viewport) &&
      region_geometry_valid(role, Some{element}, viewport)

def node_exists(found: Maybe<&2, UI.Node>) -> Bool:
  match found:
    case None{}: False{}
    case Some{node}: True{}

def node_valid(node: UI.Node, inherited: Bool, elements: +List<Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  UI.Node{+key, semantic, label, +role, +meaning, children} = node
  node_geometry_valid(Rendered.find_element(elements, key), Rendered.interactive(meaning),
    meaning, role, key, inherited || Rendered.persistent(role), viewport)

def child_persistent(inherited: Bool, +role: UI.Role, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  inherited || Rendered.persistent(role) || Rendered.code_in_view(role, found, viewport)

def all_nodes(entries: +List<UI.Node>, +inherited: Bool, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{UI.Node{+key, semantic, label, +role, +meaning, +children}, rest}:
      node_valid(UI.Node{key, semantic, label, role, meaning, children}, inherited, elements, viewport) &&
      (all_nodes(children, child_persistent(inherited, role, Rendered.find_element(elements, key), viewport), elements, viewport) &&
       all_nodes(rest, inherited, elements, viewport))

def focus(owned: Maybe<&2, String>, active: +List<UI.Node>, elements: +List<Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  match owned:
    case None{}: True{}
    case Some{+key}:
      Rendered.focus_visible(Rendered.find_element(elements, key), viewport) &&
      node_exists(UI.find_node(active, key))

def required_focus(scope: Maybe<&2, String>, focused: Maybe<&2, String>) -> Bool:
  match scope:
    case None{}: True{}
    case Some{key}:
      match focused:
        case None{}: False{}
        case Some{focus_key}: True{}

def disjoint_from(first: Rendered.Element, rest: +List<Rendered.Element>) -> Bool:
  Rendered.Element{+key, visible, enabled, tab, keyboard, scroll, +bounds, hit} = first
  match rest:
    case Nil{}: True{}
    case Con{Rendered.Element{other, v, e, t, k, s, other_bounds, h}, tail}:
      Bool.not(Rendered.overlaps(bounds, other_bounds)) &&
      disjoint_from(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail)

def non_overlapping(elements: +List<Rendered.Element>) -> Bool:
  match elements:
    case Nil{}: True{}
    case Con{first, +rest}:
      disjoint_from(first, rest) && non_overlapping(rest)

def valid_parts(+active: +List<UI.Node>, frame: Rendered.Frame) -> Bool:
  Rendered.Frame{+viewport, +elements, +focused, +tab_order} = frame
  all_nodes(active, False{}, elements, viewport) &&
  (focus(focused, active, elements, viewport) &&
   (Rendered.same_order(Rendered.expected_tabs(active, elements), tab_order) &&
    non_overlapping(Rendered.actionable_elements(active, elements))))

def valid(+surface: UI.Surface, +frame: Rendered.Frame) -> Bool:
  UI.Surface{content, base, overlays, +scope} = surface
  Rendered.Frame{viewport, elements, +focused, tab_order} = frame
  valid_parts(UI.active_nodes(surface), frame) && required_focus(scope, focused)
