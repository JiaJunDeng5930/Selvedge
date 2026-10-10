import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../controls/GEOMETRY.bend as Geometry
import ./RENDERED.bend as Rendered
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes

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
    case Some{Rendered.Element{observed_key, +visible, +enabled, tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}}:
      same_bool(required, enabled) &&
      enabled_geometry_valid(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)

def node_controls_valid(is_control: Bool, meaning: SurfaceTypes.Meaning, key: String,
  found: Maybe<&2, Rendered.Element>, must_be_visible: Bool, viewport: Geometry.Rect) -> Bool:
  match is_control:
    case False{}: True{}
    case True{}:
      control_geometry_valid(Rendered.required_enabled(meaning), key, found, must_be_visible, viewport)

def bounded_region(found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  match found:
    case None{}: False{}
    case Some{Rendered.Element{key, +visible, enabled, tab, keyboard, scroll, +bounds, hit, +paint_bounds}}:
      visible && Geometry.contains(viewport, bounds)

def reachable_toolbar(found: Maybe<&2, Rendered.Element>) -> Bool:
  match found:
    case None{}: False{}
    case Some{Rendered.Element{id, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}:
      visible || scroll

def region_geometry_valid(role: SurfaceTypes.Role, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  match role:
    case SurfaceTypes.Navigation{}: bounded_region(found, viewport)
    case SurfaceTypes.NavigationHeader{}: bounded_region(found, viewport)
    case SurfaceTypes.Main{}: bounded_region(found, viewport)
    case SurfaceTypes.Heading{}: True{}
    case SurfaceTypes.Timeline{}: True{}
    case SurfaceTypes.Activity{}: True{}
    case SurfaceTypes.Composer{}: bounded_region(found, viewport)
    case SurfaceTypes.Approval{}: True{}
    case SurfaceTypes.Toolbar{}: reachable_toolbar(found)
    case SurfaceTypes.CodeBlock{}: True{}
    case SurfaceTypes.ApprovalQueue{}: bounded_region(found, viewport)
    case SurfaceTypes.Section{}: True{}
    case SurfaceTypes.DialogActions{}: bounded_region(found, viewport)
    case SurfaceTypes.Dialog{}: bounded_region(found, viewport)
    case SurfaceTypes.Menu{}: bounded_region(found, viewport)
    case SurfaceTypes.Details{}: True{}
    case SurfaceTypes.Card{}: True{}
    case SurfaceTypes.Button{}: True{}
    case SurfaceTypes.PrimaryButton{}: True{}
    case SurfaceTypes.DestructiveButton{}: True{}
    case SurfaceTypes.SelectedButton{}: True{}
    case SurfaceTypes.Field{}: True{}
    case SurfaceTypes.Content{}: True{}
    case SurfaceTypes.Alert{}: True{}
    case SurfaceTypes.UserMessage{}: True{}
    case SurfaceTypes.AssistantMessage{}: True{}
    case SurfaceTypes.ComposerActions{}: True{}

def node_geometry_valid(found: Maybe<&2, Rendered.Element>, is_control: Bool,
  meaning: SurfaceTypes.Meaning, role: SurfaceTypes.Role, key: String, must_be_visible: Bool,
  +viewport: Geometry.Rect) -> Bool:
  match found:
    case None{}: False{}
    case Some{+element}:
      node_controls_valid(is_control, meaning, key, Some{element}, must_be_visible, viewport) &&
      region_geometry_valid(role, Some{element}, viewport)

def node_exists(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case None{}: False{}
    case Some{node}: True{}

def node_valid(node: SurfaceTypes.Node, inherited: Bool, elements: +List<Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  SurfaceTypes.Node{+key, semantic, label, +role, +meaning, children} = node
  node_geometry_valid(Rendered.find_element(elements, UIIdentity.encode(key)), Rendered.interactive(meaning),
    meaning, role, UIIdentity.encode(key), inherited || Rendered.persistent(role), viewport)

def child_persistent(inherited: Bool, +role: SurfaceTypes.Role, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  inherited || Rendered.persistent(role) || Rendered.code_in_view(role, found, viewport)

def all_nodes(entries: +List<SurfaceTypes.Node>, +inherited: Bool, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{SurfaceTypes.Node{+key, semantic, label, +role, +meaning, +children}, rest}:
      node_valid(SurfaceTypes.Node{key, semantic, label, role, meaning, children}, inherited, elements, viewport) &&
      (all_nodes(children, child_persistent(inherited, role, Rendered.find_element(elements, UIIdentity.encode(key)), viewport), elements, viewport) &&
       all_nodes(rest, inherited, elements, viewport))

def focus(owned: Maybe<&2, String>, active: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>, viewport: Geometry.Rect, +native_focus: +List<Rendered.NativeFocus>) -> Bool:
  match owned:
    case None{}: True{}
    case Some{+key}:
      Rendered.focus_visible(Rendered.find_element(elements, key), viewport) &&
      Rendered.focus_owned(active, elements, native_focus, key)

def required_focus(scope: Maybe<&2, String>, focused: Maybe<&2, String>) -> Bool:
  match scope:
    case None{}: True{}
    case Some{key}:
      match focused:
        case None{}: False{}
        case Some{focus_key}: True{}

def disjoint_from(first: Rendered.Element, rest: +List<Rendered.Element>) -> Bool:
  Rendered.Element{+key, visible, enabled, tab, keyboard, scroll, +bounds, hit, +paint_bounds} = first
  match rest:
    case Nil{}: True{}
    case Con{Rendered.Element{other, v, e, t, k, s, other_bounds, h, +other_paint_bounds}, tail}:
      Bool.not(Rendered.overlaps(paint_bounds, other_paint_bounds)) &&
      disjoint_from(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)

def non_overlapping(elements: +List<Rendered.Element>) -> Bool:
  match elements:
    case Nil{}: True{}
    case Con{first, +rest}:
      disjoint_from(first, rest) && non_overlapping(rest)

def layout_valid_parts(+active: +List<SurfaceTypes.Node>, frame: Rendered.Frame) -> Bool:
  Rendered.Frame{+viewport, +elements, +focused, +tab_order, +native_focus} = frame
  all_nodes(active, False{}, elements, viewport) &&
  (focus(focused, active, elements, viewport, native_focus) &&
   (Rendered.tabs_valid(active, elements, native_focus, tab_order) &&
    non_overlapping(Rendered.actionable_elements(active, elements))))

def paint_geometry_valid(elements: +List<Rendered.Element>, +viewport: Geometry.Rect) -> Bool:
  match elements:
    case Nil{}: True{}
    case Con{Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, rest}:
      Rendered.paint_geometry_valid(visible, bounds, paint_bounds, viewport) && paint_geometry_valid(rest, viewport)

def valid_parts(+active: +List<SurfaceTypes.Node>, +frame: Rendered.Frame) -> Bool:
  Rendered.Frame{viewport, elements, focused, tab_order, native_focus} = frame
  paint_geometry_valid(elements, viewport) && layout_valid_parts(active, frame)

def valid(+surface: SurfaceTypes.Surface, +frame: Rendered.Frame) -> Bool:
  SurfaceTypes.Surface{content, base, overlays, +scope} = surface
  Rendered.Frame{viewport, elements, +focused, tab_order, +native_focus} = frame
  valid_parts(InterfaceView.active_nodes(surface), frame) && required_focus(scope, focused)
