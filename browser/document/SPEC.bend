import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/presentation/CONTRACT.bend as PresentationRequirements
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/experience/PROGRAM.bend as UX
import ../../interaction/submission/FIELDS.bend as Forms
import ../../interaction/interactive_markdown/TYPES.bend as Interactive
import ../controls/GEOMETRY.bend as Geometry
import ./RENDERED.bend as Rendered
import ./SOURCE.bend as Source
import ./FRAME.bend as Frame
import ./MODEL.bend as Doc
import ../layout/CONTENT.bend as Content
import ../layout/PROGRAM.bend as Allocation
import ../layout/physical-space.bend as Model
import ../layout/GEOMETRY.bend as Spatial

# A frame is evidence about presentation, not permission to invent controls.
# Exact keys select the first whole observation; duplicate later records cannot
# supply a preferred field or authorize a different semantic owner.
def first_element_step(+key: String, +element: Rendered.Element, tail: Maybe<&2, Rendered.Element>) -> Maybe<&2, Rendered.Element>:
  Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, bounds, hit, paint} = element
  Bool.pick((Maybe<&2, Rendered.Element>), String.eq(observed, key), Some{Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, bounds, hit, paint}}, tail)

def first_observed_element(elements: +List<Rendered.Element>, +key: String) -> Maybe<&2, Rendered.Element>:
  List.foldr(~&2, ~Rendered.Element, ~(@+query:String -> Maybe<&2, Rendered.Element>),
    ~(element => tail => +query => first_element_step(query, element, tail(query))), elements, (+query => None{}))(key)

# Semantic ownership uses the presentation requirement's first complete preorder
# node, independently of the production lookup's index or cache.
def find_node(nodes: +List<SurfaceTypes.Node>, key: String) -> Maybe<&2, SurfaceTypes.Node>:
  PresentationRequirements.first_named_node(nodes, key)

# A modal scope owns only its first declared overlay subtree. Without a scope,
# base content precedes overlays; a missing declared scope exposes no controls.
def scoped_node(found: Maybe<&2, SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match found:
    case None{}: Nil{}
    case Some{node}: [node]

def scoped_nodes(scope: Maybe<&2, String>, base: +List<SurfaceTypes.Node>, overlays: +List<SurfaceTypes.Node>) -> +List<SurfaceTypes.Node>:
  match scope:
    case None{}: List.append(&2, SurfaceTypes.Node, base, overlays)
    case Some{key}: scoped_node(PresentationRequirements.first_named_node(overlays, key))

def active_nodes(surface: SurfaceTypes.Surface) -> +List<SurfaceTypes.Node>:
  SurfaceTypes.Surface{content, base, overlays, scope} = surface
  scoped_nodes(scope, base, overlays)

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

def persistent(role: SurfaceTypes.Role) -> Bool:
  match role:
    case SurfaceTypes.Composer{}: True{}
    case SurfaceTypes.DialogActions{}: True{}
    case SurfaceTypes.Approval{}: False{}
    case SurfaceTypes.Toolbar{}: False{}
    case _: False{}

def issue(violated: Bool, violation: Rendered.Violation) -> +List<Rendered.Violation>:
  match violated:
    case True{}: [violation]
    case False{}: Nil{}

def declared_exposure(controls: +List<Rendered.ControlExposure>, +key: String) -> Source.Exposure:
  match controls:
    case Nil{}: Source.Exposed{}
    case Con{Rendered.ControlExposure{owner, exposure, command_enabled}, rest}:
      Bool.pick(Source.Exposure, String.eq(owner, key), exposure, declared_exposure(rest, key))

def enabled_geometry(required: Bool, +key: String, +visible: Bool, keyboard: Bool, scroll: Bool, bounds: Geometry.Rect, hit: String, must_be_visible: Bool, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match required:
    case False{}: Nil{}
    case True{}:
      List.append(&2, Rendered.Violation,
        issue(Bool.not(keyboard && (visible || scroll)) || (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))), Rendered.UnreachableControl{key}),
        issue(visible && Bool.not(String.eq(key, hit)), Rendered.OccludedControl{key}))

def control_geometry(+required: Bool, +key: String, found: Maybe<&2, Rendered.Element>, must_be_visible: Bool, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match found:
    case None{}: [Rendered.MissingElement{key}]
    case Some{Rendered.Element{observed, visible, +enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}:
      List.append(&2, Rendered.Violation, issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}),
        enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport))

def bounded_dialog(key: String, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match found:
    case None{}: [Rendered.MissingElement{key}]
    case Some{Rendered.Element{id, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}:
      issue(Bool.not(visible && Geometry.contains(viewport, bounds)), Rendered.EscapedDialog{key})

def dialog_geometry(role: SurfaceTypes.Role, key: String, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match role:
    case SurfaceTypes.Dialog{}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.Menu{}: bounded_dialog(key, found, viewport)
    case _: Nil{}

def concealed_control(+required: Bool, +key: String, found: Maybe<&2, Rendered.Element>) -> +List<Rendered.Violation>:
  match found:
    case None{}: [Rendered.MissingElement{key}]
    case Some{Rendered.Element{observed, visible, +enabled, tab, keyboard, scroll, bounds, hit, paint}}:
      List.append(&2, Rendered.Violation, issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), Rendered.DisabledAppearance{key}),
        issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key}))

def exposed_control(exposure: Source.Exposure, meaning: SurfaceTypes.Meaning, key: String, found: Maybe<&2, Rendered.Element>, persistent: Bool, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match exposure:
    case Source.Exposed{}: control_geometry(required_enabled(meaning), key, found, persistent, viewport)
    case Source.Concealed{}: concealed_control(required_enabled(meaning), key, found)

def node_controls_with(is_control: Bool, meaning: SurfaceTypes.Meaning, +key: String, found: Maybe<&2, Rendered.Element>, persistent: Bool, viewport: Geometry.Rect, controls: +List<Rendered.ControlExposure>) -> +List<Rendered.Violation>:
  match is_control:
    case False{}: Nil{}
    case True{}: exposed_control(declared_exposure(controls, key), meaning, key, found, persistent, viewport)

def reachable_toolbar(key: String, found: Maybe<&2, Rendered.Element>) -> +List<Rendered.Violation>:
  match found:
    case None{}: [Rendered.MissingElement{key}]
    case Some{Rendered.Element{id, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}:
      issue(Bool.not(visible || scroll), Rendered.EscapedDialog{key})

def region_geometry(role: SurfaceTypes.Role, key: String, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match role:
    case SurfaceTypes.GlobalNavigation{compact}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.CompactHeader{}: bounded_dialog(key, found, viewport)
    case SurfaceTypes.WorkTabs{}: bounded_dialog(key, found, viewport)
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

def code_in_view(role: SurfaceTypes.Role, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  match role found:
    case SurfaceTypes.CodeBlock{} Some{Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}}: visible && overlaps(paint_bounds, viewport)
    case _ _: False{}

def node_geometry_with(found: Maybe<&2, Rendered.Element>, +meaning: SurfaceTypes.Meaning, role: SurfaceTypes.Role, +key: String, persistent: Bool, +viewport: Geometry.Rect, controls: +List<Rendered.ControlExposure>) -> +List<Rendered.Violation>:
  match found:
    case None{}: [Rendered.MissingElement{key}]
    case Some{+element}:
      List.append(&2, Rendered.Violation, node_controls_with(interactive(meaning), meaning, key, Some{element}, persistent, viewport, controls), region_geometry(role, key, Some{element}, viewport))

def tab_stop(found: Maybe<&2, Rendered.Element>) -> Bool:
  match found:
    case None{}: False{}
    case Some{Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}: enabled && tab && (visible || scroll)

def tab_entry(included: Bool, key: String, rest: +List<String>) -> +List<String>:
  match included:
    case True{}: key <> rest
    case False{}: rest

def native_member(entries: +List<Rendered.NativeFocus>, +identity: String) -> Bool:
  match entries:
    case Nil{}: False{}
    case Con{Rendered.NativeFocus{key, owner}, rest}: String.eq(key, identity) || native_member(rest, identity)

def read_only(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, binding, original}}, children}}: String.eq(tag, "markdown")
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.InformationText{role_name}, children}}: True{}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.ReadOnly{text}, children}}: True{}
    case Some{SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.RichText{source, value}, children}}: True{}
    case _: False{}

def native_element(found: Maybe<&2, Rendered.Element>) -> Bool:
  match found:
    case Some{Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}: enabled && tab && keyboard && (visible || scroll)
    case None{}: False{}

def exists(found: Maybe<&2, SurfaceTypes.Node>) -> Bool:
  match found:
    case None{}: False{}
    case Some{node}: True{}

def native_valid(entries: +List<Rendered.NativeFocus>, +active: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{Rendered.NativeFocus{+identity, owner}, +rest}:
      read_only(find_node(active, owner)) && Bool.not(exists(find_node(active, identity))) &&
      native_element(first_observed_element(elements, identity)) && Bool.not(native_member(rest, identity)) && native_valid(rest, active, elements)

def native_owned(+entries: +List<Rendered.NativeFocus>, +active: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>, +key: String) -> Bool:
  native_valid(entries, active, elements) && native_member(entries, key)

def owner_tabs(entries: +List<Rendered.NativeFocus>, +owner: String) -> +List<String>:
  match entries:
    case Nil{}: Nil{}
    case Con{Rendered.NativeFocus{identity, parent}, rest}: tab_entry(String.eq(parent, owner), identity, owner_tabs(rest, owner))

def content_tabs(meaning: SurfaceTypes.Meaning, entries: +List<Rendered.NativeFocus>, key: String) -> +List<String>:
  match meaning:
    case SurfaceTypes.InteractiveNode{Interactive.ExpandedNode{identity, occurrence, tag, attrs, binding, children}}: Bool.pick((+List<String>), String.eq(tag, "markdown"), owner_tabs(entries, key), Nil{})
    case SurfaceTypes.InformationText{role}: owner_tabs(entries, key)
    case SurfaceTypes.ReadOnly{text}: owner_tabs(entries, key)
    case SurfaceTypes.RichText{source, value}: owner_tabs(entries, key)
    case _: Nil{}

def same_order(expected: +List<String>, actual: +List<String>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case Con{left, ls} Con{right, rs}: String.eq(left, right) && same_order(ls, rs)
    case _ _: False{}

def focus_visible(found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  match found:
    case None{}: False{}
    case Some{Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}: visible && Geometry.contains(viewport, bounds)

def focus_owned(+nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>, +native_focus: +List<Rendered.NativeFocus>, +key: String) -> Bool:
  exists(find_node(nodes, key)) || native_owned(native_focus, nodes, elements, key)

def focus_checks(focus: Maybe<&2, String>, nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>, viewport: Geometry.Rect, +native_focus: +List<Rendered.NativeFocus>) -> +List<Rendered.Violation>:
  match focus:
    case None{}: Nil{}
    case Some{+key}: List.append(&2, Rendered.Violation, issue(Bool.not(focus_visible(first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{}),
      issue(Bool.not(focus_owned(nodes, elements, native_focus, key)), Rendered.FocusOutsideScope{}))

def required_focus(scope: Maybe<&2, String>, focused: Maybe<&2, String>) -> +List<Rendered.Violation>:
  match scope:
    case None{}: Nil{}
    case Some{scope}:
      match focused:
        case None{}: [Rendered.MissingModalFocus{}]
        case Some{key}: Nil{}

def include_element(included: Bool, found: Maybe<&2, Rendered.Element>, rest: +List<Rendered.Element>) -> +List<Rendered.Element>:
  match included found:
    case True{} Some{Rendered.Element{key, True{}, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds}}: Rendered.Element{key, True{}, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds} <> rest
    case _ _: rest

def against(first: Rendered.Element, rest: +List<Rendered.Element>) -> +List<Rendered.Violation>:
  Rendered.Element{+key, visible, enabled, tab, keyboard, scroll, +bounds, hit, +paint_bounds} = first
  match rest:
    case Nil{}: Nil{}
    case Con{Rendered.Element{other, v, e, t, k, s, other_bounds, h, +other_paint_bounds}, tail}:
      List.append(&2, Rendered.Violation, issue(overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other}),
        against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail))

def independent_targets(elements: +List<Rendered.Element>) -> +List<Rendered.Violation>:
  match elements:
    case Nil{}: Nil{}
    case Con{first, +rest}: List.append(&2, Rendered.Violation, against(first, rest), independent_targets(rest))

def paint_geometry_valid(visible: Bool, +bounds: Geometry.Rect, +paint_bounds: Geometry.Rect, +viewport: Geometry.Rect) -> Bool:
  match visible:
    case False{}: True{}
    case True{}: Geometry.contains(bounds, paint_bounds) && Geometry.contains(viewport, paint_bounds)

def paint_geometry(elements: +List<Rendered.Element>, +viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match elements:
    case Nil{}: Nil{}
    case Con{Rendered.Element{+key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, rest}:
      List.append(&2, Rendered.Violation,
        issue(Bool.not(paint_geometry_valid(visible, bounds, paint_bounds, viewport)), Rendered.InvalidPaintGeometry{key}),
        paint_geometry(rest, viewport))

def enabled_expectation(expected: Maybe<&2, Bool>, +actual: Bool) -> Bool:
  match expected:
    case None{}: True{}
    case Some{+value}: (value && actual) || (Bool.not(value) && Bool.not(actual))

def source_concealment(exposure: Source.Exposure, +key: String, command_enabled: Maybe<&2, Bool>, found: Maybe<&2, Rendered.Element>) -> +List<Rendered.Violation>:
  match exposure found:
    case Source.Exposed{} _: Nil{}
    case Source.Concealed{} None{}: [Rendered.MissingElement{key}]
    case Source.Concealed{} Some{Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, bounds, hit, paint}}:
      List.append(&2, Rendered.Violation, issue(Bool.not(enabled_expectation(command_enabled, enabled)), Rendered.DisabledAppearance{key}),
        issue(visible || tab || keyboard || Bool.not(String.eq(hit, "")), Rendered.UnreachableControl{key}))

def source_exposure_checks(controls: +List<Rendered.ControlExposure>, +elements: +List<Rendered.Element>) -> +List<Rendered.Violation>:
  match controls:
    case Nil{}: Nil{}
    case Con{Rendered.ControlExposure{+key, exposure, enabled}, rest}:
      List.append(&2, Rendered.Violation, source_concealment(exposure, key, enabled, first_observed_element(elements, key)), source_exposure_checks(rest, elements))

# Diagnostics are node-before-children-before-siblings. A code block whose paint
# intersects the viewport makes its own descendants persistently reachable.
def node_diagnostics(entries: +List<SurfaceTypes.Node>, +inherited: Bool, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect, +controls: +List<Rendered.ControlExposure>) -> +List<Rendered.Violation>:
  match entries:
    case Nil{}: Nil{}
    case Con{SurfaceTypes.Node{key, semantic, label, +role, meaning, children}, rest}:
      +identity = UIIdentity.encode(key)
      +found = first_observed_element(elements, identity)
      List.append(&2, Rendered.Violation, node_geometry_with(found, meaning, role, identity, inherited || persistent(role), viewport, controls),
        List.append(&2, Rendered.Violation, node_diagnostics(children, inherited || persistent(role) || code_in_view(role, found, viewport), elements, viewport, controls), node_diagnostics(rest, inherited, elements, viewport, controls)))

# The DOM order is local: the product control, its owned native content, its
# children and then its siblings. An ineligible parent never hides child tabs.
def own_tab_stop(eligible: Bool, elements: +List<Rendered.Element>, identity: String) -> Bool:
  eligible && tab_stop(first_observed_element(elements, identity))

def expected_tabs(nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>, +native_focus: +List<Rendered.NativeFocus>) -> +List<String>:
  match nodes:
    case Nil{}: Nil{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, +meaning, children}, rest}:
      +identity = UIIdentity.encode(key)
      tab_entry(interactive(meaning) && required_enabled(meaning) && tab_stop(first_observed_element(elements, identity)), identity,
        List.append(&2, String, content_tabs(meaning, native_focus, identity),
          List.append(&2, String, expected_tabs(children, elements, native_focus), expected_tabs(rest, elements, native_focus))))

def actionable_elements(nodes: +List<SurfaceTypes.Node>, +elements: +List<Rendered.Element>) -> +List<Rendered.Element>:
  match nodes:
    case Nil{}: Nil{}
    case Con{SurfaceTypes.Node{key, semantic, label, role, +meaning, children}, rest}:
      include_element(interactive(meaning) && required_enabled(meaning), first_observed_element(elements, UIIdentity.encode(key)),
        List.append(&2, Rendered.Element, actionable_elements(children, elements), actionable_elements(rest, elements)))

def layout_diagnostics(+active: +List<SurfaceTypes.Node>, frame: Rendered.Frame, controls: +List<Rendered.ControlExposure>) -> +List<Rendered.Violation>:
  Rendered.Frame{+viewport, +elements, focused, tab_order, +native_focus} = frame
  List.append(&2, Rendered.Violation, node_diagnostics(active, False{}, elements, viewport, controls),
    List.append(&2, Rendered.Violation, focus_checks(focused, active, elements, viewport, native_focus),
      List.append(&2, Rendered.Violation, issue(Bool.not(native_valid(native_focus, active, elements) && same_order(expected_tabs(active, elements, native_focus), tab_order)), Rendered.WrongTabOrder{}),
        independent_targets(actionable_elements(active, elements)))))

def check_diagnostics(+active: +List<SurfaceTypes.Node>, +frame: Rendered.Frame) -> +List<Rendered.Violation>:
  Rendered.Frame{+viewport, +elements, focused, tab_order, native_focus} = frame
  List.append(&2, Rendered.Violation, paint_geometry(elements, viewport), layout_diagnostics(active, frame, Nil{}))

def frame_diagnostics(+surface: SurfaceTypes.Surface, +frame: Rendered.Frame, expectations: Rendered.FrameExpectations) -> +List<Rendered.Violation>:
  SurfaceTypes.Surface{content, base, overlays, +scope} = surface
  Rendered.Frame{+viewport, +elements, +focused, tab_order, native_focus} = frame
  Rendered.FrameExpectations{+controls} = expectations
  List.append(&2, Rendered.Violation, source_exposure_checks(controls, elements),
    List.append(&2, Rendered.Violation, paint_geometry(elements, viewport),
      List.append(&2, Rendered.Violation, layout_diagnostics(active_nodes(surface), frame, controls), required_focus(scope, focused))))

def ordinary_frame_diagnostics(+surface: SurfaceTypes.Surface, +frame: Rendered.Frame) -> +List<Rendered.Violation>:
  SurfaceTypes.Surface{content, base, overlays, +scope} = surface
  Rendered.Frame{viewport, elements, +focused, tab_order, native_focus} = frame
  List.append(&2, Rendered.Violation, check_diagnostics(active_nodes(surface), frame), required_focus(scope, focused))

def no_diagnostics(faults: +List<Rendered.Violation>) -> Bool:
  match faults:
    case Nil{}: True{}
    case Con{first, rest}: False{}

def valid(+surface: SurfaceTypes.Surface, +frame: Rendered.Frame) -> Bool:
  no_diagnostics(ordinary_frame_diagnostics(surface, frame))

# Public presentation-role requirements also used by dialog clients.
def bounded_region(found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  match found:
    case None{}: False{}
    case Some{Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint}}: visible && Geometry.contains(viewport, bounds)

def region_geometry_valid(role: SurfaceTypes.Role, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  no_diagnostics(region_geometry(role, "", found, viewport))

def child_persistent(inherited: Bool, +role: SurfaceTypes.Role, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) -> Bool:
  inherited || persistent(role) || code_in_view(role, found, viewport)


# Source declarations have their own meaning: concealed ancestors dominate,
# and an inert declaration removes the entire subtree from active expectations.
def exposed(value: Source.Exposure) -> Bool:
  match value:
    case Source.Exposed{}: True{}
    case Source.Concealed{}: False{}

def combine_exposure(parent: Source.Exposure, own: Source.Exposure) -> Source.Exposure:
  match parent:
    case Source.Exposed{}: own
    case Source.Concealed{}: Source.Concealed{}

def attributes_exposure(values: +List<Source.Attribute>) -> Source.Exposure:
  match values:
    case Nil{}: Source.Exposed{}
    case Con{Source.ExposureAttribute{value}, rest}: combine_exposure(value, attributes_exposure(rest))
    case Con{other, rest}: attributes_exposure(rest)

def attributes_inert(values: +List<Source.Attribute>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{Source.InertAttribute{}, rest}: True{}
    case Con{other, rest}: attributes_inert(rest)

def node_exposure(node: Source.Node) -> Source.Exposure:
  match node:
    case Source.NativeAttachment{key, target, attributes, style, children}: attributes_exposure(attributes)
    case Source.Box{key, tag, style, attributes, children}: attributes_exposure(attributes)
    case Source.Control{key, tag, style, attributes, name, enabled, first, remaining, children}: attributes_exposure(attributes)
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, name, enabled, first, remaining}: attributes_exposure(attributes)
    case _: Source.Exposed{}

def node_inert(node: Source.Node) -> Bool:
  match node:
    case Source.NativeAttachment{key, target, attrs, style, children}: attributes_inert(attrs)
    case Source.Box{key, tag, style, attrs, children}: attributes_inert(attrs)
    case Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}: attributes_inert(attrs)
    case Source.Field{key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}: attributes_inert(attrs)
    case _: False{}

# Allocated-frame evidence must describe the actual allocation exactly. Native
# attachments contribute their separately measured roots, never ordinary boxes.
def allocated_authored_key(values: +List<Source.Attribute>, +fallback: String) -> String:
  match values:
    case Nil{}: fallback
    case Con{Source.DataAttribute{name, key}, rest}:
      Bool.pick(String, String.eq(name, "native-key"), key, allocated_authored_key(rest, fallback))
    case Con{other, rest}: allocated_authored_key(rest, fallback)


def allocated_observation_key(value: Content.Value) -> String:
  match value:
    case Content.Value{Source.Text{key, text, choice, wrap}, font}: UIIdentity.encode(key)
    case Content.Value{Source.Glyph{key, picture, style}, font}: UIIdentity.encode(key)
    case Content.Value{Source.Box{key, tag, style, attrs, children}, font}: allocated_authored_key(attrs, UIIdentity.encode(key))
    case Content.Value{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, font}: allocated_authored_key(attrs, UIIdentity.encode(key))
    case Content.Value{Source.Field{key, kind, style, attrs, text, placeholder, options, policy, name, enabled, first, remaining}, font}: allocated_authored_key(attrs, UIIdentity.encode(key))
    case Content.Value{Source.RichText{key, style, content, attachments, native_owner}, font}: UIIdentity.encode(key)
    case Content.Value{Source.NativeAttachment{key, target, attrs, style, children}, font}: allocated_authored_key(attrs, UIIdentity.encode(key))

def allocated_rectangle(box: Spatial.Box) -> Geometry.Rect:
  Spatial.Box{+left, +top, width, height} = box
  Geometry.Rect{F32.from_nat(left), F32.from_nat(top), F32.from_nat((left + width : Nat)), F32.from_nat((top + height : Nat))}

def allocated_ordinary(value: Content.Value) -> Bool:
  Content.Value{node, font} = value
  match node:
    case Source.NativeAttachment{key, target, attrs, style, children}: False{}
    case _: True{}

def allocated_value_exposure(parent: Source.Exposure, value: Content.Value) -> Source.Exposure:
  Content.Value{node, font} = value
  combine_exposure(parent, node_exposure(node))

def allocated_entry_if(ordinary: Bool, +value: Content.Value, +bounds: Spatial.Box, +interaction: Model.Interaction<Doc.DOMEvent>, exposure: Source.Exposure, rest: +List<Frame.Expected>) -> +List<Frame.Expected>:
  match ordinary:
    case True{}: Frame.Expected{allocated_observation_key(value), bounds, interaction, exposure} <> rest
    case False{}: rest

def allocated_entry(+value: Content.Value, +bounds: Spatial.Box, +interaction: Model.Interaction<Doc.DOMEvent>, rest: +List<Frame.Expected>) -> +List<Frame.Expected>:
  allocated_entry_if(allocated_ordinary(value), value, bounds, interaction, allocated_value_exposure(Source.Exposed{}, value), rest)

def allocated_forest_with(trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>, +parent: Source.Exposure) -> +List<Frame.Expected>:
  match trees:
    case Nil{}: Nil{}
    case Con{Allocation.AllocatedLeaf{physical, +value, interaction, rule, demand, height, bounds, canvas}, rest}:
      allocated_entry_if(allocated_ordinary(value), value, bounds, interaction, allocated_value_exposure(parent, value), allocated_forest_with(rest, parent))
    case Con{Allocation.AllocatedContainer{physical, +value, interaction, rule, bounds, canvas, direction, children}, rest}:
      +exposure = allocated_value_exposure(parent, value)
      allocated_entry_if(allocated_ordinary(value), value, bounds, interaction, exposure, List.append(&2, Frame.Expected, allocated_forest_with(children, exposure), allocated_forest_with(rest, parent)))

def allocated_forest(trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>) -> +List<Frame.Expected>:
  allocated_forest_with(trees, Source.Exposed{})

def allocated_expected(world: Content.AllocatedWorld) -> +List<Frame.Expected>:
  Content.AllocatedWorld{snapshot, tree, roots, policies} = world
  allocated_forest([tree])

def allocated_add_occurrence(same: Bool, count: Nat) -> Nat:
  match same:
    case True{}: (1n + count : Nat)
    case False{}: count

def allocated_occurrences(elements: +List<Rendered.Element>, +key: String) -> Nat:
  match elements:
    case Nil{}: 0n
    case Con{Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, bounds, hit, paint}, rest}:
      allocated_add_occurrence(String.eq(observed, key), allocated_occurrences(rest, key))

def allocated_same_rectangle(first: Geometry.Rect, second: Geometry.Rect) -> Bool:
  Geometry.Rect{left, top, right, bottom} = first
  Geometry.Rect{other_left, other_top, other_right, other_bottom} = second
  F32.is_eq(left, other_left) && F32.is_eq(top, other_top) && F32.is_eq(right, other_right) && F32.is_eq(bottom, other_bottom)

def allocated_interactive(interaction: Model.Interaction<Doc.DOMEvent>) -> Bool:
  match interaction:
    case Model.DisplayOnly{}: False{}
    case Model.Operable{first, remaining, enabled}: enabled

def allocated_operable_exposure(exposure: Source.Exposure, +enabled: Bool, +key: String, +element: Rendered.Element, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match exposure:
    case Source.Concealed{}:
      Rendered.Element{observed, visible, +observed_enabled, tab, keyboard, scroll, bounds, hit, paint} = element
      issue(Bool.not(((enabled && observed_enabled) || (Bool.not(enabled) && Bool.not(observed_enabled)))), Rendered.UnreachableControl{key})
    case Source.Exposed{}:
      Rendered.Element{observed, visible, observed_enabled, +tab, keyboard, scroll, bounds, hit, paint} = element
      List.append(&2, Rendered.Violation, issue(Bool.not(((enabled && tab) || (Bool.not(enabled) && Bool.not(tab)))), Rendered.UnreachableControl{key}),
        control_geometry(enabled, key, Some{Rendered.Element{observed, visible, observed_enabled, tab, keyboard, scroll, bounds, hit, paint}}, True{}, viewport))

def allocated_operable_geometry(exposure: Source.Exposure, interaction: Model.Interaction<Doc.DOMEvent>, key: String, element: Rendered.Element, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match interaction:
    case Model.DisplayOnly{}: Nil{}
    case Model.Operable{first, remaining, enabled}: allocated_operable_exposure(exposure, enabled, key, element, viewport)

def allocated_exposure_geometry(exposure: Source.Exposure, +visible: Bool, tab: Bool, keyboard: Bool, hit: String, bounds: Geometry.Rect, paint: Geometry.Rect, viewport: Geometry.Rect) -> Bool:
  match exposure:
    case Source.Exposed{}: visible && paint_geometry_valid(visible, bounds, paint, viewport)
    case Source.Concealed{}: Bool.not(visible) && Bool.not(tab) && Bool.not(keyboard) && String.eq(hit, "")

def allocated_node_geometry(+exposure: Source.Exposure, +key: String, +bounds: Spatial.Box, interaction: Model.Interaction<Doc.DOMEvent>, found: Maybe<&2, Rendered.Element>, +viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match found:
    case None{}: [Rendered.MissingElement{key}]
    case Some{+element}:
      Rendered.Element{observed, visible, enabled, tab, keyboard, scroll, measured, hit, paint} = element
      List.append(&2, Rendered.Violation,
        issue(Bool.not(allocated_same_rectangle(allocated_rectangle(bounds), measured) && Geometry.contains(viewport, measured) && allocated_exposure_geometry(exposure, visible, tab, keyboard, hit, measured, paint, viewport)), Rendered.InvalidPaintGeometry{key}),
        allocated_operable_geometry(exposure, interaction, key, element, viewport))

def allocated_nodes(entries: +List<Frame.Expected>, +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match entries:
    case Nil{}: Nil{}
    case Con{Frame.Expected{+key, bounds, interaction, exposure}, rest}:
      List.append(&2, Rendered.Violation, issue(Bool.not(Nat.is_eq(allocated_occurrences(elements, key), 1n)), Rendered.MissingElement{key}),
        List.append(&2, Rendered.Violation, allocated_node_geometry(exposure, key, bounds, interaction, first_observed_element(elements, key), viewport), allocated_nodes(rest, elements, viewport)))

def allocated_tabs(entries: +List<Frame.Expected>) -> +List<String>:
  match entries:
    case Nil{}: Nil{}
    case Con{Frame.Expected{key, bounds, interaction, exposure}, rest}: tab_entry(exposed(exposure) && allocated_interactive(interaction), key, allocated_tabs(rest))

def allocated_controls(entries: +List<Frame.Expected>, +elements: +List<Rendered.Element>) -> +List<Rendered.Element>:
  match entries:
    case Nil{}: Nil{}
    case Con{Frame.Expected{key, bounds, interaction, exposure}, rest}:
      include_element(exposed(exposure) && allocated_interactive(interaction), first_observed_element(elements, key), allocated_controls(rest, elements))

def allocated_focused_owned(focused: Maybe<&2, String>, entries: +List<Frame.Expected>) -> Bool:
  match focused:
    case None{}: True{}
    case Some{key}: List.contains(String, (first => second => String.eq(first, second)), allocated_tabs(entries), key)

def allocated_no_native(world: Content.AllocatedWorld) -> Bool:
  Content.AllocatedWorld{snapshot, tree, roots, policies} = world
  match roots policies:
    case Nil{} Nil{}: True{}
    case _ _: False{}

def allocated_focus_geometry(focused: Maybe<&2, String>, +elements: +List<Rendered.Element>, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  match focused:
    case None{}: Nil{}
    case Some{key}: issue(Bool.not(focus_visible(first_observed_element(elements, key), viewport)), Rendered.InvisibleFocus{})

def allocated_native_free(entries: +List<Rendered.NativeFocus>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{first, rest}: False{}

def allocated_focus_checks(+focused: Maybe<&2, String>, +entries: +List<Frame.Expected>, +elements: +List<Rendered.Element>, viewport: Geometry.Rect) -> +List<Rendered.Violation>:
  List.append(&2, Rendered.Violation, issue(Bool.not(allocated_focused_owned(focused, entries)), Rendered.FocusOutsideScope{}), allocated_focus_geometry(focused, elements, viewport))

def allocated_frame_diagnostics(+world: Content.AllocatedWorld, frame: Rendered.Frame) -> +List<Rendered.Violation>:
  Rendered.Frame{+viewport, +elements, +focused, tab_order, native_focus} = frame
  +entries = allocated_expected(world)
  List.append(&2, Rendered.Violation, allocated_nodes(entries, elements, viewport),
    List.append(&2, Rendered.Violation, issue(Bool.not(same_order(allocated_tabs(entries), tab_order)), Rendered.WrongTabOrder{}),
      List.append(&2, Rendered.Violation, issue(Bool.not(allocated_no_native(world) && allocated_native_free(native_focus)), Rendered.FocusOutsideScope{}),
        List.append(&2, Rendered.Violation, allocated_focus_checks(focused, entries, elements, viewport),
          independent_targets(allocated_controls(entries, elements))))))

def allocated_command_enabled(interaction: Model.Interaction<Doc.DOMEvent>) -> Maybe<&2, Bool>:
  match interaction:
    case Model.DisplayOnly{}: None{}
    case Model.Operable{first, remaining, enabled}: Some{enabled}

def allocated_value_inert(value: Content.Value) -> Bool:
  Content.Value{node, font} = value
  node_inert(node)

def allocated_exposure_entry(inert: Bool, ordinary: Bool, +value: Content.Value, interaction: Model.Interaction<Doc.DOMEvent>, exposure: Source.Exposure) -> +List<Rendered.ControlExposure>:
  match inert ordinary:
    case False{} True{}: [Rendered.ControlExposure{allocated_observation_key(value), exposure, allocated_command_enabled(interaction)}]
    case _ _: Nil{}

def allocated_retain_exposure(inert: Bool, own: +List<Rendered.ControlExposure>, rest: +List<Rendered.ControlExposure>) -> +List<Rendered.ControlExposure>:
  match inert:
    case True{}: rest
    case False{}: List.append(&2, Rendered.ControlExposure, own, rest)

def allocated_exposure_forest(trees: +List<Allocation.AllocatedTree<Content.Value, Doc.DOMEvent>>, +parent: Source.Exposure) -> +List<Rendered.ControlExposure>:
  match trees:
    case Nil{}: Nil{}
    case Con{Allocation.AllocatedLeaf{physical, +value, interaction, rule, demand, height, bounds, canvas}, rest}:
      List.append(&2, Rendered.ControlExposure, allocated_exposure_entry(allocated_value_inert(value), allocated_ordinary(value), value, interaction, allocated_value_exposure(parent, value)), allocated_exposure_forest(rest, parent))
    case Con{Allocation.AllocatedContainer{physical, +value, interaction, rule, bounds, canvas, direction, children}, rest}:
      +exposure = allocated_value_exposure(parent, value)
      allocated_retain_exposure(allocated_value_inert(value), List.append(&2, Rendered.ControlExposure, allocated_exposure_entry(False{}, allocated_ordinary(value), value, interaction, exposure), allocated_exposure_forest(children, exposure)), allocated_exposure_forest(rest, parent))

def allocated_expectations(world: Content.AllocatedWorld, frame: Rendered.Frame) -> Rendered.FrameExpectations:
  Content.AllocatedWorld{snapshot, tree, roots, policies} = world
  Rendered.FrameExpectations{allocated_exposure_forest([tree], Source.Exposed{})}

# A receipt from another generation cannot replace any part of the prior state.
def accepted_frame(faults: +List<Rendered.Violation>, generation: Nat, frame: Rendered.Frame) -> Rendered.State:
  match faults:
    case Nil{}: Rendered.Realized{generation, frame}
    case Con{first, rest}: Rendered.Unmet{generation, frame, first <> rest}

def observed_owned(owned: Bool, current: Nat, surface: SurfaceTypes.Surface, +frame: Rendered.Frame,
  previous: Rendered.State, expectations: Rendered.FrameExpectations) -> Rendered.State:
  match owned:
    case False{}: previous
    case True{}: accepted_frame(frame_diagnostics(surface, frame, expectations), current, frame)

def observed_frame(+current: Nat, received: Nat, surface: SurfaceTypes.Surface, frame: Rendered.Frame,
  previous: Rendered.State, expectations: Rendered.FrameExpectations) -> Rendered.State:
  observed_owned(Nat.is_eq(current, received), current, surface, frame, previous, expectations)

def ordinary_observed_owned(owned: Bool, current: Nat, surface: SurfaceTypes.Surface, +frame: Rendered.Frame, previous: Rendered.State) -> Rendered.State:
  match owned:
    case False{}: previous
    case True{}: accepted_frame(ordinary_frame_diagnostics(surface, frame), current, frame)

def ordinary_observed_frame(+current: Nat, received: Nat, surface: SurfaceTypes.Surface, frame: Rendered.Frame, previous: Rendered.State) -> Rendered.State:
  ordinary_observed_owned(Nat.is_eq(current, received), current, surface, frame, previous)
