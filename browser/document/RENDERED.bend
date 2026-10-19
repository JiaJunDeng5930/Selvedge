import ./SOURCE.bend as Source
import ../../interaction/experience/PROGRAM.bend as UX
import Base
import ../../bendlib/string-equality.bend as SafeText
import ../../interaction/interactive_markdown/TYPES.bend as Interactive
import ../../bendlib/categories.bend as Categories
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/submission/FIELDS.bend as Forms
import ../controls/GEOMETRY.bend as Geometry
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes

type Element is Data:
  Element{key: String, visible: Bool, enabled: Bool, tab_stop: Bool,
    keyboard_reachable: Bool, scroll_reachable: Bool, bounds: Geometry.Rect,
    center_hit_owner: String, paint_bounds: Geometry.Rect}

type ResolvedNode is Data:
  ResolvedNode{original: SurfaceTypes.Node, identity: String,
    observation: Maybe<&2, Element>, children: +List<ResolvedNode>}

type PreparedElement is Data:
  PreparedElement{fingerprint: U32, original: Element}

type NativeFocus is Data:
  NativeFocus{identity: String, owner: String}

type Frame is Data:
  Frame{viewport: Geometry.Rect, elements: +List<Element>, focused: Maybe<&2, String>, tab_order: +List<String>, native_focus: +List<NativeFocus>}

type Violation is Data:
  MissingElement{key: String}
  DisabledAppearance{key: String}
  UnreachableControl{key: String}
  OccludedControl{key: String}
  OverlappingControls{first: String, second: String}
  InvalidPaintGeometry{key: String}
  EscapedDialog{key: String}
  InvisibleFocus{}
  FocusOutsideScope{}
  MissingModalFocus{}
  WrongTabOrder{}

type ControlExposure is Data:
  ControlExposure{key: String, exposure: Source.Exposure, command_enabled: Maybe<&2, Bool>}

type FrameExpectations is Data:
  FrameExpectations{controls: +List<ControlExposure>}

def empty_expectations() -> FrameExpectations:
  FrameExpectations{Nil{}}

def choose_exposure(same: Bool, current: Source.Exposure, fallback: Source.Exposure) -> Source.Exposure:
  match same:
    case True{}: current
    case False{}: fallback

def declared_exposure(controls: +List<ControlExposure>, +key: String) -> Source.Exposure:
  match controls:
    case Nil{}: Source.Exposed{}
    case Con{ControlExposure{owner, exposure, command_enabled}, rest}:
      choose_exposure(SafeText.string_equal(owner, key), exposure, declared_exposure(rest, key))

type State is Data:
  AwaitingFrame{generation: Nat}
  Realized{generation: Nat, frame: Frame}
  Unmet{generation: Nat, frame: Frame, violations: +List<Violation>}

def enabled(availability: View.Availability) -> Bool:
  match availability:
    case View.Unavailable{reason}: False{}
    case _: True{}

def field_control(entry: Forms.Entry) -> Bool:
  match entry:
    case Forms.DisplayOnly{}: False{}
    case Forms.FileCollection{}: False{}
    case Forms.DirectoryCollection{}: False{}
    case _: True{}

def interactive(meaning: SurfaceTypes.Meaning) -> Bool:
  match meaning:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}}: True{}
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.ActionBinding{kind, enabled, pending}, children}}: True{}
    case SurfaceTypes.InteractiveView{event, command, label, enabled}: True{}
    case SurfaceTypes.SupportingControl{support, property, input, availability}: UX.support_visible(support)
    case SurfaceTypes.MovableCard{destinations, face}: True{}
    case SurfaceTypes.ActionCommit{assessment, input, availability}: True{}
    case SurfaceTypes.Activate{input, availability}: True{}
    case SurfaceTypes.SettingEntry{subject, value, input, availability}: True{}
    case SurfaceTypes.PanelToggle{expanded, input, availability}: True{}
    case SurfaceTypes.Choice{kind, icon, selected, description, input, availability}: True{}
    case SurfaceTypes.Edit{editor, field, entry, value, choices}: field_control(entry)
    case SurfaceTypes.SearchChoices{query}: True{}
    case SurfaceTypes.BoardSearch{filter}: True{}
    case SurfaceTypes.ReceiveFile{editor, enabled}: True{}
    case SurfaceTypes.EnterDirectory{editor, text}: True{}
    case SurfaceTypes.DirectoryBrowserLocation{value}: True{}
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: True{}
    case _: False{}

def required_enabled(meaning: SurfaceTypes.Meaning) -> Bool:
  match meaning:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.FieldBinding{state_id, schema, raw, canonical, validation, enabled}, children}}: enabled
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, Interactive.ActionBinding{kind, enabled, pending}, children}}: enabled && Bool.not(pending)
    case SurfaceTypes.InteractiveView{event, command, label, enabled}: enabled
    case SurfaceTypes.SupportingControl{support, property, input, availability}: UX.support_visible(support) && enabled(availability)
    case SurfaceTypes.MovableCard{destinations, face}: InterfaceView.has_available_destination(destinations)
    case SurfaceTypes.ActionCommit{assessment, input, availability}: UX.assessment_ready(assessment) && enabled(availability)
    case SurfaceTypes.Activate{input, availability}: enabled(availability)
    case SurfaceTypes.SettingEntry{subject, value, input, availability}: enabled(availability)
    case SurfaceTypes.PanelToggle{expanded, input, availability}: enabled(availability)
    case SurfaceTypes.Choice{kind, icon, selected, description, input, availability}: enabled(availability)
    case SurfaceTypes.ReceiveFile{editor, enabled}: enabled
    case SurfaceTypes.BoardProfile{automatic, selected, choices, enabled}: enabled
    case other: interactive(other)

def element_key(element: Element) -> String:
  Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds} = element
  key

def find_element_match(same: Bool, element: Element, fallback: Unit -> Maybe<&2, Element>) -> Maybe<&2, Element>:
  match same:
    case True{}: Some{element}
    case False{}: fallback(Unit{})

def find_element(elements: +List<Element>, +key: String) -> Maybe<&2, Element>:
  match elements:
    case Nil{}: None{}
    case Con{+element, rest}:
      find_element_match(SafeText.string_equal(element_key(element), key), element, (_ => find_element(rest, key)))

def key_fingerprint_acc(text: String, accumulator: U32) -> U32:
  match text:
    case SNil{}: accumulator
    case SCon{Chr{code}, rest}:
      key_fingerprint_acc(rest, U32.add(U32.mul(accumulator, 31), code))

def key_fingerprint(text: String) -> U32:
  key_fingerprint_acc(text, 0)

def prepare_elements(elements: +List<Element>) -> +List<PreparedElement>:
  match elements:
    case Nil{}: Nil{}
    case Con{+element, rest}:
      PreparedElement{key_fingerprint(element_key(element)), element} <> prepare_elements(rest)

def fingerprint_match_admitted(admitted: Bool, left: String, right: String) -> Bool:
  match admitted:
    case False{}: False{}
    case True{}: SafeText.string_equal(left, right)

def fingerprint_match(left_fingerprint: U32, right_fingerprint: U32,
  left: String, right: String) -> Bool:
  fingerprint_match_admitted(U32.is_eq(left_fingerprint, right_fingerprint), left, right)

def find_prepared_element(elements: +List<PreparedElement>, +fingerprint: U32,
  +key: String) -> Maybe<&2, Element>:
  match elements:
    case Nil{}: None{}
    case Con{PreparedElement{stored, +element}, rest}:
      find_element_match(fingerprint_match(stored, fingerprint, element_key(element), key),
        element, (_ => find_prepared_element(rest, fingerprint, key)))

def persistent(role: SurfaceTypes.Role) -> Bool:
  match role:
    case SurfaceTypes.Composer{}: True{}
    case SurfaceTypes.DialogActions{}: True{}
    case SurfaceTypes.Approval{}: False{}
    case SurfaceTypes.Toolbar{}: False{}
    case _: False{}

def issue(violated: Bool, violation: Violation) -> +List<Violation>:
  match violated:
    case True{}: [violation]
    case False{}: Nil{}

def enabled_geometry(required: Bool, +key: String, +visible: Bool, keyboard: Bool, scroll: Bool, bounds: Geometry.Rect, hit: String, must_be_visible: Bool, viewport: Geometry.Rect) -> +List<Violation>:
  match required:
    case False{}: Nil{}
    case True{}:
      List.append(&2, Violation,
        issue(Bool.not(keyboard && (visible || scroll)) || (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))), UnreachableControl{key}),
        issue(visible && Bool.not(SafeText.string_equal(key, hit)), OccludedControl{key}))

def control_geometry(+required: Bool, +key: String, found: Maybe<&2, Element>, must_be_visible: Bool, viewport: Geometry.Rect) -> +List<Violation>:
  match found:
    case None{}: [MissingElement{key}]
    case Some{Element{observed, visible, +enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}:
      List.append(&2, Violation, issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), DisabledAppearance{key}),
        enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport))

def bounded_dialog(key: String, found: Maybe<&2, Element>, viewport: Geometry.Rect) -> +List<Violation>:
  match found:
    case None{}: [MissingElement{key}]
    case Some{Element{id, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}:
      issue(Bool.not(visible && Geometry.contains(viewport, bounds)), EscapedDialog{key})

def dialog_geometry(role: SurfaceTypes.Role, key: String, found: Maybe<&2, Element>, viewport: Geometry.Rect) -> +List<Violation>:
  match role:
    case SurfaceTypes.Dialog{}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.Menu{}: bounded_dialog(key, found, viewport)
    case _: Nil{}

def concealed_control(+required: Bool, +key: String, found: Maybe<&2, Element>) -> +List<Violation>:
  match found:
    case None{}: [MissingElement{key}]
    case Some{Element{observed, visible, +enabled, tab, keyboard, scroll, bounds, hit, paint}}:
      List.append(&2, Violation, issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), DisabledAppearance{key}),
        issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), UnreachableControl{key}))

def exposed_control(exposure: Source.Exposure, meaning: SurfaceTypes.Meaning, key: String, found: Maybe<&2, Element>, persistent: Bool, viewport: Geometry.Rect) -> +List<Violation>:
  match exposure:
    case Source.Exposed{}: control_geometry(required_enabled(meaning), key, found, persistent, viewport)
    case Source.Concealed{}: concealed_control(required_enabled(meaning), key, found)

def node_controls_with(is_control: Bool, meaning: SurfaceTypes.Meaning, +key: String, found: Maybe<&2, Element>, persistent: Bool, viewport: Geometry.Rect, controls: +List<ControlExposure>) -> +List<Violation>:
  match is_control:
    case False{}: Nil{}
    case True{}: exposed_control(declared_exposure(controls, key), meaning, key, found, persistent, viewport)

def reachable_toolbar(key: String, found: Maybe<&2, Element>) -> +List<Violation>:
  match found:
    case None{}: [MissingElement{key}]
    case Some{Element{id, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}:
      issue(Bool.not(visible || scroll), EscapedDialog{key})

def region_geometry(role: SurfaceTypes.Role, key: String, found: Maybe<&2, Element>, viewport: Geometry.Rect) -> +List<Violation>:
  match role:
    case SurfaceTypes.GlobalNavigation{compact}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.GlobalNavigationEntry{selected, compact}: Nil{}
    case SurfaceTypes.CompactHeader{}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.CompactWorkScope{title, count}: Nil{}
    case SurfaceTypes.CompactNavigationMenu{}: Nil{}
    case SurfaceTypes.CompactNavigationEntry{selected}: Nil{}
    case SurfaceTypes.WorkTabs{}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.WorkTab{selected}: Nil{}
    case SurfaceTypes.Navigation{}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.NavigationEntry{selected}: Nil{}
    case SurfaceTypes.NavigationCollection{}: Nil{}
    case SurfaceTypes.NavigationSection{}: Nil{}
    case SurfaceTypes.NavigationHeader{}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.Main{}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.Composer{}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.DialogActions{}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.Toolbar{}: reachable_toolbar(key, found)
    case SurfaceTypes.ApprovalQueue{}: bounded_dialog(key, found, viewport)
    case other: dialog_geometry(other, key, found, viewport)

def overlaps(first: Geometry.Rect, second: Geometry.Rect) -> Bool:
  Geometry.Rect{left, top, right, bottom} = first
  Geometry.Rect{other_left, other_top, other_right, other_bottom} = second
  F32.is_lt(left, other_right) && F32.is_lt(other_left, right) && F32.is_lt(top, other_bottom) && F32.is_lt(other_top, bottom)

def code_in_view(role: SurfaceTypes.Role, found: Maybe<&2, Element>, viewport: Geometry.Rect) -> Bool:
  match role found:
    case SurfaceTypes.CodeBlock{} Some{Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}}: visible && overlaps(paint_bounds, viewport)
    case _ _: False{}

def node_geometry_with(found: Maybe<&2, Element>, +meaning: SurfaceTypes.Meaning, role: SurfaceTypes.Role, +key: String, persistent: Bool, +viewport: Geometry.Rect, controls: +List<ControlExposure>) -> +List<Violation>:
  match found:
    case None{}: [MissingElement{key}]
    case Some{+element}:
      List.append(&2, Violation, node_controls_with(interactive(meaning), meaning, key, Some{element}, persistent, viewport, controls), region_geometry(role, key, Some{element}, viewport))

def tab_stop(found: Maybe<&2, Element>) -> Bool:
  match found:
    case None{}: False{}
    case Some{Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}: enabled && tab && (visible || scroll)

def tab_entry(included: Bool, key: String, rest: +List<String>) -> +List<String>:
  match included:
    case True{}: key <> rest
    case False{}: rest

def native_member(entries: +List<NativeFocus>, +identity: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{NativeFocus{key, owner}, rest}: SafeText.string_equal(key, identity) || native_member(rest, identity)

def read_only(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, binding, original}}, children}}: SafeText.string_equal(tag, "markdown")
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InformationText{role_name}, children}}: True{}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ReadOnly{text}, children}}: True{}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.RichText{source, value}, children}}: True{}
    case _: False{}

def native_element(found: Maybe<&2, Element>) -> Bool:
  match found:
    case Some{Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}: enabled && tab && keyboard && (visible || scroll)
    case None{}: False{}

def exists(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case None{}: False{}
    case Some{node}: True{}

def native_valid(entries: +List<NativeFocus>, +active: +List<SurfaceTypes.Node>, +elements: +List<Element>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{NativeFocus{+identity, owner}, +rest}:
      read_only(InterfaceView.find_node(active, owner)) && Bool.not(exists(InterfaceView.find_node(active, identity))) &&
      native_element(find_element(elements, identity)) && Bool.not(native_member(rest, identity)) && native_valid(rest, active, elements)

def native_owned(+entries: +List<NativeFocus>, +active: +List<SurfaceTypes.Node>, +elements: +List<Element>, +key: String) -> Bool:
  native_valid(entries, active, elements) && native_member(entries, key)

def owner_tabs(entries: +List<NativeFocus>, +owner: String) -> +List<String>:
  match entries:
    case Nil{}: Nil{}
    case Con{NativeFocus{identity, parent}, rest}: tab_entry(SafeText.string_equal(parent, owner), identity, owner_tabs(rest, owner))

# Only native Markdown content contributes its declared descendants to the
# tab sequence. Rejected tags do not scan unrelated native-focus ownership.
def content_tabs_admitted(admitted: Bool, entries: +List<NativeFocus>, key: String) -> +List<String>:
  match admitted:
    case False{}: Nil{}
    case True{}: owner_tabs(entries, key)

def content_tabs(meaning: SurfaceTypes.Meaning, entries: +List<NativeFocus>, key: String) -> +List<String>:
  match meaning:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, binding, children}}: content_tabs_admitted(SafeText.string_equal(tag, "markdown"), entries, key)
    case SurfaceTypes.InformationText{role}: owner_tabs(entries, key)
    case SurfaceTypes.ReadOnly{text}: owner_tabs(entries, key)
    case SurfaceTypes.RichText{source, value}: owner_tabs(entries, key)
    case _: Nil{}

def own_tab_stop(eligible: Bool, elements: +List<Element>, identity: String) -> Bool:
  match eligible:
    case False{}: False{}
    case True{}: tab_stop(find_element(elements, identity))

def expected_tabs(nodes: +List<SurfaceTypes.Node>, +elements: +List<Element>, +native_focus: +List<NativeFocus>) -> +List<String>:
  match nodes:
    case Nil{}: Nil{}
    case Con{+node, rest}:
      SurfaceTypes.Node{key, semantic, label, role, +meaning, children} = node
      +identity = InterfaceView.node_key(node)
      tab_entry(own_tab_stop(interactive(meaning) && required_enabled(meaning), elements, identity), identity,
        List.append(&2, String, content_tabs(meaning, native_focus, identity),
          List.append(&2, String, expected_tabs(children, elements, native_focus), expected_tabs(rest, elements, native_focus))))

def same_order(expected: +List<String>, actual: +List<String>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case Con{left, ls} Con{right, rs}: SafeText.string_equal(left, right) && same_order(ls, rs)
    case _ _: False{}

def focus_visible(found: Maybe<&2, Element>, viewport: Geometry.Rect) -> Bool:
  match found:
    case None{}: False{}
    case Some{Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}: visible && Geometry.contains(viewport, bounds)

def focus_owned(+nodes: +List<SurfaceTypes.Node>, +elements: +List<Element>, +native_focus: +List<NativeFocus>, +key: String) -> Bool:
  exists(InterfaceView.find_node(nodes, key)) || native_owned(native_focus, nodes, elements, key)

def focus_checks(focus: Maybe<&2, String>, nodes: +List<SurfaceTypes.Node>, +elements: +List<Element>, viewport: Geometry.Rect, +native_focus: +List<NativeFocus>) -> +List<Violation>:
  match focus:
    case None{}: Nil{}
    case Some{+key}: List.append(&2, Violation, issue(Bool.not(focus_visible(find_element(elements, key), viewport)), InvisibleFocus{}),
      issue(Bool.not(focus_owned(nodes, elements, native_focus, key)), FocusOutsideScope{}))

def required_focus(scope: Maybe<&2, String>, focused: Maybe<&2, String>) -> +List<Violation>:
  match scope:
    case None{}: Nil{}
    case Some{scope}:
      match focused:
        case None{}: [MissingModalFocus{}]
        case Some{key}: Nil{}

def include_element(included: Bool, found: Maybe<&2, Element>, rest: +List<Element>) -> +List<Element>:
  match included found:
    case True{} Some{Element{key, True{}, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}: Element{key, True{}, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds} <> rest
    case _ _: rest

def resolve_nodes(nodes: +List<SurfaceTypes.Node>, +elements: +List<Element>) -> +List<ResolvedNode>:
  match nodes:
    case Nil{}: Nil{}
    case Con{+node, rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      +identity: String = UIIdentity.encode(key)
      ResolvedNode{node, identity, find_element(elements, identity), resolve_nodes(children, elements)} <>
        resolve_nodes(rest, elements)

def frame_forest_nonempty(nodes: +List<SurfaceTypes.Node>) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{node, rest}: True{}

def frame_nodes_many(nodes: +List<SurfaceTypes.Node>) -> Bool:
  match nodes:
    case Nil{}: False{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}:
      frame_forest_nonempty(children) || frame_forest_nonempty(rest)

def frame_elements_many(elements: +List<Element>) -> Bool:
  match elements:
    case Nil{}: False{}
    case Con{element, rest}:
      match rest:
        case Nil{}: False{}
        case Con{next, remaining}: True{}

def resolve_prepared_nodes(nodes: +List<SurfaceTypes.Node>, +elements: +List<PreparedElement>) -> +List<ResolvedNode>:
  match nodes:
    case Nil{}: Nil{}
    case Con{+node, rest}:
      SurfaceTypes.Node{key, semantic, label, role, meaning, children} = node
      +identity: String = UIIdentity.encode(key)
      ResolvedNode{node, identity, find_prepared_element(elements, key_fingerprint(identity), identity), resolve_prepared_nodes(children, elements)} <>
        resolve_prepared_nodes(rest, elements)

def resolve_frame_admitted(prepared: Bool, +nodes: +List<SurfaceTypes.Node>, +elements: +List<Element>) -> +List<ResolvedNode>:
  match prepared:
    case False{}: resolve_nodes(nodes, elements)
    case True{}: resolve_prepared_nodes(nodes, prepare_elements(elements))

def resolve_frame_nodes(+nodes: +List<SurfaceTypes.Node>, +elements: +List<Element>) -> +List<ResolvedNode>:
  resolve_frame_admitted(frame_nodes_many(nodes) && frame_elements_many(elements), nodes, elements)

def resolved_diagnostics(entries: +List<ResolvedNode>, +inherited: Bool,
  +viewport: Geometry.Rect, +controls: +List<ControlExposure>) -> +List<Violation>:
  match entries:
    case Nil{}: Nil{}
    case Con{ResolvedNode{SurfaceTypes.Node{key, semantic, label, +role, meaning, original_children}, identity, +found, children}, rest}:
      List.append(&2, Violation,
        node_geometry_with(found, meaning, role, identity, inherited || persistent(role), viewport, controls),
        List.append(&2, Violation,
          resolved_diagnostics(children, inherited || persistent(role) || code_in_view(role, found, viewport), viewport, controls),
          resolved_diagnostics(rest, inherited, viewport, controls)))

def resolved_actionable_elements(nodes: +List<ResolvedNode>) -> +List<Element>:
  match nodes:
    case Nil{}: Nil{}
    case Con{ResolvedNode{SurfaceTypes.Node{key, semantic, label, role, +meaning, original_children}, identity, found, children}, rest}:
      include_element(interactive(meaning) && required_enabled(meaning), found,
        List.append(&2, Element, resolved_actionable_elements(children), resolved_actionable_elements(rest)))

def resolved_tabs(nodes: +List<ResolvedNode>, +native_focus: +List<NativeFocus>) -> +List<String>:
  match nodes:
    case Nil{}: Nil{}
    case Con{ResolvedNode{SurfaceTypes.Node{key, semantic, label, role, +meaning, original_children}, +identity, found, children}, rest}:
      tab_entry(interactive(meaning) && required_enabled(meaning) && tab_stop(found), identity,
        List.append(&2, String, content_tabs(meaning, native_focus, identity),
          List.append(&2, String, resolved_tabs(children, native_focus), resolved_tabs(rest, native_focus))))

def against(first: Element, rest: +List<Element>) -> +List<Violation>:
  Element{+key, visible, enabled, tab, keyboard, scroll, +bounds, hit, +paint_bounds} = first
  match rest:
    case Nil{}: Nil{}
    case Con{Element{other, v, e, t, k, s, other_bounds, h, +other_paint_bounds}, tail}:
      List.append(&2, Violation, issue(overlaps(paint_bounds, other_paint_bounds), OverlappingControls{key, other}),
        against(Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail))

def independent_targets(elements: +List<Element>) -> +List<Violation>:
  match elements:
    case Nil{}: Nil{}
    case Con{first, +rest}: List.append(&2, Violation, against(first, rest), independent_targets(rest))

def layout_check_with(+active: +List<SurfaceTypes.Node>, frame: Frame, controls: +List<ControlExposure>) -> +List<Violation>:
  Frame{+viewport, +elements, focused, tab_order, +native_focus} = frame
  +resolved: +List<ResolvedNode> = resolve_frame_nodes(active, elements)
  List.append(&2, Violation, resolved_diagnostics(resolved, False{}, viewport, controls),
    List.append(&2, Violation, focus_checks(focused, active, elements, viewport, native_focus),
      List.append(&2, Violation,
        issue(Bool.not(native_valid(native_focus, active, elements) && same_order(resolved_tabs(resolved, native_focus), tab_order)), WrongTabOrder{}),
        independent_targets(resolved_actionable_elements(resolved)))))

def layout_check(active: +List<SurfaceTypes.Node>, frame: Frame) -> +List<Violation>:
  layout_check_with(active, frame, Nil{})

# Visible paint must be a positive region inside both the layout and viewport.
# The DOM adapter owns correspondence with actual ancestor clipping.

def paint_geometry_valid(visible: Bool, +bounds: Geometry.Rect, +paint_bounds: Geometry.Rect, +viewport: Geometry.Rect) -> Bool:
  match visible:
    case False{}: True{}
    case True{}: Geometry.contains(bounds, paint_bounds) && Geometry.contains(viewport, paint_bounds)

def paint_geometry(elements: +List<Element>, +viewport: Geometry.Rect) -> +List<Violation>:
  match elements:
    case Nil{}: Nil{}
    case Con{Element{+key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, rest}:
      List.append(&2, Violation,
        issue(Bool.not(paint_geometry_valid(visible, bounds, paint_bounds, viewport)), InvalidPaintGeometry{key}),
        paint_geometry(rest, viewport))

def check(+active: +List<SurfaceTypes.Node>, +frame: Frame) -> +List<Violation>:
  Frame{+viewport, +elements, focused, tab_order, native_focus} = frame
  List.append(&2, Violation, paint_geometry(elements, viewport), layout_check(active, frame))

def violations(+surface: SurfaceTypes.Surface, +frame: Frame) -> +List<Violation>:
  SurfaceTypes.Surface{content, base, overlays, +scope} = surface
  Frame{viewport, elements, +focused, tab_order, +native_focus} = frame
  List.append(&2, Violation, check(InterfaceView.active_nodes(surface), frame), required_focus(scope, focused))

def accepted(violations: +List<Violation>, generation: Nat, frame: Frame) -> State:
  match violations:
    case Nil{}: Realized{generation, frame}
    case other: Unmet{generation, frame, other}

type FrameReceipt is Data:
  FrameReceipt{current: Nat, received: Nat, surface: SurfaceTypes.Surface, frame: Frame}

def frame_correlated(receipt: FrameReceipt) -> Bool:
  FrameReceipt{current, received, surface, frame} = receipt
  Nat.is_eq(current, received)

def correlated_receipt() -> FrameReceipt -> Type:
  Categories.holds(FrameReceipt, frame_correlated)

def received_calculation(generation: Nat, +surface: SurfaceTypes.Surface, +frame: Frame) -> State:
  accepted(violations(surface, frame), generation, frame)

def receive(member: Categories.Membership<FrameReceipt, correlated_receipt()>) -> State:
  Categories.Membership{FrameReceipt{current, received, surface, frame}, evidence} = member
  received_calculation(current, surface, frame)

def received(result: Maybe<&1, Categories.Membership<FrameReceipt, correlated_receipt()>>, previous: State) -> State:
  match result:
    # DEFENSE: A native animation-frame observation may arrive after its display generation has been replaced.
    case None{}: previous
    case Some{member}: receive(member)

def observe(+current: Nat, received_generation: Nat, surface: SurfaceTypes.Surface, frame: Frame, previous: State) -> State:
  received(Categories.admit(FrameReceipt, frame_correlated, FrameReceipt{current, received_generation, surface, frame}), previous)


def enabled_expectation(expected: Maybe<&2, Bool>, +actual: Bool) -> Bool:
  match expected:
    case None{}: True{}
    case Some{+value}: (value && actual) || (Bool.not(value) && Bool.not(actual))

def source_concealment(exposure: Source.Exposure, +key: String, command_enabled: Maybe<&2, Bool>, found: Maybe<&2, Element>) -> +List<Violation>:
  match exposure found:
    case Source.Exposed{} _: Nil{}
    case Source.Concealed{} None{}: [MissingElement{key}]
    case Source.Concealed{} Some{Element{observed, visible, enabled, tab, keyboard, scroll, bounds, hit, paint}}:
      List.append(&2, Violation, issue(Bool.not(enabled_expectation(command_enabled, enabled)), DisabledAppearance{key}),
        issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), UnreachableControl{key}))

def source_exposure_checks(controls: +List<ControlExposure>, +elements: +List<Element>) -> +List<Violation>:
  match controls:
    case Nil{}: Nil{}
    case Con{ControlExposure{+key, exposure, enabled}, rest}:
      List.append(&2, Violation, source_concealment(exposure, key, enabled, find_element(elements, key)), source_exposure_checks(rest, elements))

def violations_with(+surface: SurfaceTypes.Surface, +frame: Frame, expectations: FrameExpectations) -> +List<Violation>:
  SurfaceTypes.Surface{content, base, overlays, +scope} = surface
  Frame{+viewport, +elements, +focused, tab_order, +native_focus} = frame
  FrameExpectations{+controls} = expectations
  List.append(&2, Violation, source_exposure_checks(controls, elements),
    List.append(&2, Violation, paint_geometry(elements, viewport),
      List.append(&2, Violation, layout_check_with(InterfaceView.active_nodes(surface), frame, controls), required_focus(scope, focused))))

def observed_with(correlated: Bool, current: Nat, surface: SurfaceTypes.Surface, +frame: Frame, previous: State, expectations: FrameExpectations) -> State:
  match correlated:
    # DEFENSE: A queued frame observation for an older display cannot establish the current source exposure or focus.
    case False{}: previous
    case True{}: accepted(violations_with(surface, frame, expectations), current, frame)

def observe_with(+current: Nat, received: Nat, surface: SurfaceTypes.Surface, frame: Frame, previous: State, expectations: FrameExpectations) -> State:
  observed_with(Nat.is_eq(current, received), current, surface, frame, previous, expectations)
