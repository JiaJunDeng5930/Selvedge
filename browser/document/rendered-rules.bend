import Base
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ./RENDERED.bend as Model
import ../controls/GEOMETRY.bend as Geometry
import ../../interaction/presentation/MODEL.bend as View

law stale_frame_retains_state:
  for +current: Nat
  for +received: Nat
  for +surface: InterfaceView.Surface
  for +frame: Model.Frame
  for +previous: Model.State
  for different: {Nat.is_eq(current, received) == False{} : Bool}
  {Model.observe(current, received, surface, frame, previous) == previous : Model.State}


law native_ownership_is_complete:
  for +identity: String
  for owner: String
  for +rest: +List<Model.NativeFocus>
  for +active: +List<InterfaceView.Node>
  for +elements: +List<Model.Element>
  {Model.native_valid(Model.NativeFocus{identity, owner} <> rest, active, elements) ==
    (Model.read_only(InterfaceView.find_node(active, owner)) && Bool.not(Model.exists(InterfaceView.find_node(active, identity))) &&
     Model.native_element(Model.find_element(elements, identity)) && Bool.not(Model.native_member(rest, identity)) && Model.native_valid(rest, active, elements)) : Bool}

law native_order_is_owned:
  for +owner: String
  for +identity: String
  for +parent: String
  for rest: +List<Model.NativeFocus>
  {Model.owner_tabs(Model.NativeFocus{identity, parent} <> rest, owner) ==
    Model.tab_entry(String.eq(parent, owner), identity, Model.owner_tabs(rest, owner)) : +List<String>}

law native_tab_contract:
  for +active: +List<InterfaceView.Node>
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
  {Model.persistent(InterfaceView.DialogActions{}) == True{} : Bool}

law dialog_actions_bounded:
  for key: String
  for found: Maybe<&2, Model.Element>
  for viewport: Geometry.Rect
  {Model.region_geometry(InterfaceView.DialogActions{}, key, found, viewport) == Model.bounded_dialog(key, found, viewport) : +List<Model.Violation>}

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
  {Model.code_in_view(InterfaceView.CodeBlock{}, Some{Model.Element{key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds}}, viewport) ==
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
  {Model.code_in_view(InterfaceView.CodeBlock{}, Some{Model.Element{key,False{},enabled,tab,keyboard,scroll,bounds,hit,paint_bounds}}, viewport) == False{} : Bool}

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
  {Model.code_in_view(InterfaceView.CodeBlock{}, Some{Model.Element{key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds}}, viewport) == False{} : Bool}

law movement_is_interactive:
  for destinations: +List<InterfaceView.Placement>
  for face: View.CardFace
  {Model.interactive(InterfaceView.MovableCard{destinations, face}) == True{} : Bool}

law movement_enabled_by_offered_input:
  for +destinations: +List<InterfaceView.Placement>
  for face: View.CardFace
  {Model.required_enabled(InterfaceView.MovableCard{destinations, face}) == InterfaceView.has_available_destination(destinations) : Bool}
