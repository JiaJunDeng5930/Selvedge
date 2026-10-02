import Base
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ../core/form-fields.bend as Forms
import ./interaction.bend as Geometry

type Element is Data:
  Element{key: String, visible: Bool, enabled: Bool, tab_stop: Bool,
    keyboard_reachable: Bool, scroll_reachable: Bool, bounds: Geometry.Rect,
    center_hit_owner: String}

type Frame is Data:
  Frame{viewport: Geometry.Rect, elements: +List<Element>, focused: Maybe<&2, String>, tab_order: +List<String>}

type Violation is Data:
  MissingElement{key: String}
  DisabledAppearance{key: String}
  UnreachableControl{key: String}
  OccludedControl{key: String}
  OverlappingControls{first: String, second: String}
  EscapedDialog{key: String}
  InvisibleFocus{}
  FocusOutsideScope{}
  MissingModalFocus{}
  WrongTabOrder{}

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

def interactive(meaning: UI.Meaning) -> Bool:
  match meaning:
    case UI.Activate{input, availability}: True{}
    case UI.Choice{selected, description, input, availability}: True{}
    case UI.Edit{editor, field, entry, value}: field_control(entry)
    case UI.SearchChoices{query}: True{}
    case UI.EnterCredential{entered}: True{}
    case UI.BoardSearch{filter}: True{}
    case UI.ReceiveFile{editor, enabled}: True{}
    case UI.EnterDirectory{editor, text}: True{}
    case UI.BoardProfile{automatic, selected, choices, enabled}: True{}
    case _: False{}

def required_enabled(meaning: UI.Meaning) -> Bool:
  match meaning:
    case UI.Activate{input, availability}: enabled(availability)
    case UI.Choice{selected, description, input, availability}: enabled(availability)
    case UI.ReceiveFile{editor, enabled}: enabled
    case UI.BoardProfile{automatic, selected, choices, enabled}: enabled
    case other: interactive(other)

def choose_element(same: Bool, element: Element, fallback: Maybe<&2, Element>) -> Maybe<&2, Element>:
  match same:
    case True{}: Some{element}
    case False{}: fallback

def find_element(elements: +List<Element>, +key: String) -> Maybe<&2, Element>:
  match elements:
    case Nil{}: None{}
    case Con{Element{+current, visible, enabled, tab, keyboard, scroll, bounds, hit}, rest}:
      choose_element(String.eq(current, key), Element{current, visible, enabled, tab, keyboard, scroll, bounds, hit}, find_element(rest, key))

def persistent(role: UI.Role) -> Bool:
  match role:
    case UI.Composer{}: True{}
    case UI.Approval{}: False{}
    case UI.Toolbar{}: False{}
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
        issue(visible && Bool.not(String.eq(key, hit)), OccludedControl{key}))

def control_geometry(+required: Bool, +key: String, found: Maybe<&2, Element>, must_be_visible: Bool, viewport: Geometry.Rect) -> +List<Violation>:
  match found:
    case None{}: [MissingElement{key}]
    case Some{Element{observed, visible, +enabled, tab, keyboard, scroll, bounds, hit}}:
      List.append(&2, Violation, issue(Bool.not(((required && enabled) || (Bool.not(required) && Bool.not(enabled)))), DisabledAppearance{key}),
        enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport))

def bounded_dialog(key: String, found: Maybe<&2, Element>, viewport: Geometry.Rect) -> +List<Violation>:
  match found:
    case None{}: [MissingElement{key}]
    case Some{Element{id, visible, enabled, tab, keyboard, scroll, bounds, hit}}:
      issue(Bool.not(visible && Geometry.contains(viewport, bounds)), EscapedDialog{key})

def dialog_geometry(role: UI.Role, key: String, found: Maybe<&2, Element>, viewport: Geometry.Rect) -> +List<Violation>:
  match role:
    case UI.Dialog{}: bounded_dialog(key, found, viewport)
    case UI.Menu{}: bounded_dialog(key, found, viewport)
    case _: Nil{}

def node_controls(is_control: Bool, meaning: UI.Meaning, key: String, found: Maybe<&2, Element>, persistent: Bool, viewport: Geometry.Rect) -> +List<Violation>:
  match is_control:
    case False{}: Nil{}
    case True{}: control_geometry(required_enabled(meaning), key, found, persistent, viewport)

def reachable_toolbar(key: String, found: Maybe<&2, Element>) -> +List<Violation>:
  match found:
    case None{}: [MissingElement{key}]
    case Some{Element{id, visible, enabled, tab, keyboard, scroll, bounds, hit}}:
      issue(Bool.not(visible || scroll), EscapedDialog{key})

def region_geometry(role: UI.Role, key: String, found: Maybe<&2, Element>, viewport: Geometry.Rect) -> +List<Violation>:
  match role:
    case UI.Navigation{}: bounded_dialog(key, found, viewport)
    case UI.NavigationHeader{}: bounded_dialog(key, found, viewport)
    case UI.Main{}: bounded_dialog(key, found, viewport)
    case UI.Composer{}: bounded_dialog(key, found, viewport)
    case UI.Toolbar{}: reachable_toolbar(key, found)
    case UI.ApprovalQueue{}: bounded_dialog(key, found, viewport)
    case other: dialog_geometry(other, key, found, viewport)

def overlaps(first: Geometry.Rect, second: Geometry.Rect) -> Bool:
  Geometry.Rect{left, top, right, bottom} = first
  Geometry.Rect{other_left, other_top, other_right, other_bottom} = second
  F32.is_lt(left, other_right) && F32.is_lt(other_left, right) && F32.is_lt(top, other_bottom) && F32.is_lt(other_top, bottom)

def code_in_view(role: UI.Role, found: Maybe<&2, Element>, viewport: Geometry.Rect) -> Bool:
  match role found:
    case UI.CodeBlock{} Some{Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}}: overlaps(bounds, viewport)
    case _ _: False{}
def node_geometry(found: Maybe<&2, Element>, +meaning: UI.Meaning, role: UI.Role, +key: String, persistent: Bool, +viewport: Geometry.Rect) -> +List<Violation>:
  match found:
    case None{}: [MissingElement{key}]
    case Some{+element}:
      List.append(&2, Violation, node_controls(interactive(meaning), meaning, key, Some{element}, persistent, viewport), region_geometry(role, key, Some{element}, viewport))

def nodes(entries: +List<UI.Node>, +inherited: Bool, +elements: +List<Element>, +viewport: Geometry.Rect) -> +List<Violation>:
  match entries:
    case Nil{}: Nil{}
    case Con{UI.Node{+key, semantic, label, +role, meaning, children}, rest}:
      List.append(&2, Violation, node_geometry(find_element(elements, key), meaning, role, key, inherited || persistent(role), viewport),
        List.append(&2, Violation, nodes(children, inherited || persistent(role) || code_in_view(role, find_element(elements, key), viewport), elements, viewport), nodes(rest, inherited, elements, viewport)))

def tab_stop(found: Maybe<&2, Element>) -> Bool:
  match found:
    case None{}: False{}
    case Some{Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}}: enabled && tab

def tab_entry(included: Bool, key: String, rest: +List<String>) -> +List<String>:
  match included:
    case True{}: key <> rest
    case False{}: rest

def expected_tabs(nodes: +List<UI.Node>, +elements: +List<Element>) -> +List<String>:
  match nodes:
    case Nil{}: Nil{}
    case Con{UI.Node{+key, semantic, label, role, +meaning, children}, rest}:
      tab_entry(interactive(meaning) && required_enabled(meaning) && tab_stop(find_element(elements, key)), key,
        List.append(&2, String, expected_tabs(children, elements), expected_tabs(rest, elements)))

def same_order(expected: +List<String>, actual: +List<String>) -> Bool:
  match expected actual:
    case Nil{} Nil{}: True{}
    case Con{left, ls} Con{right, rs}: String.eq(left, right) && same_order(ls, rs)
    case _ _: False{}

def focus_visible(found: Maybe<&2, Element>, viewport: Geometry.Rect) -> Bool:
  match found:
    case None{}: False{}
    case Some{Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}}: visible && Geometry.contains(viewport, bounds)

def exists(found: Maybe<&2, UI.Node>) -> Bool:
  match found:
    case None{}: False{}
    case Some{node}: True{}

def focus_checks(focus: Maybe<&2, String>, nodes: +List<UI.Node>, elements: +List<Element>, viewport: Geometry.Rect) -> +List<Violation>:
  match focus:
    case None{}: Nil{}
    case Some{+key}: List.append(&2, Violation, issue(Bool.not(focus_visible(find_element(elements, key), viewport)), InvisibleFocus{}),
      issue(Bool.not(exists(UI.find_node(nodes, key))), FocusOutsideScope{}))

def required_focus(scope: Maybe<&2, String>, focused: Maybe<&2, String>) -> +List<Violation>:
  match scope:
    case None{}: Nil{}
    case Some{scope}:
      match focused:
        case None{}: [MissingModalFocus{}]
        case Some{key}: Nil{}

def include_element(included: Bool, found: Maybe<&2, Element>, rest: +List<Element>) -> +List<Element>:
  match included found:
    case True{} Some{Element{key, True{}, enabled, tab, keyboard, scroll, bounds, hit}}: Element{key, True{}, enabled, tab, keyboard, scroll, bounds, hit} <> rest
    case _ _: rest

def actionable_elements(nodes: +List<UI.Node>, +elements: +List<Element>) -> +List<Element>:
  match nodes:
    case Nil{}: Nil{}
    case Con{UI.Node{key, semantic, label, role, +meaning, children}, rest}:
      include_element(interactive(meaning) && required_enabled(meaning), find_element(elements, key),
        List.append(&2, Element, actionable_elements(children, elements), actionable_elements(rest, elements)))

def against(first: Element, rest: +List<Element>) -> +List<Violation>:
  Element{+key, visible, enabled, tab, keyboard, scroll, +bounds, hit} = first
  match rest:
    case Nil{}: Nil{}
    case Con{Element{other, v, e, t, k, s, other_bounds, h}, tail}:
      List.append(&2, Violation, issue(overlaps(bounds, other_bounds), OverlappingControls{key, other}),
        against(Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail))

def independent_targets(elements: +List<Element>) -> +List<Violation>:
  match elements:
    case Nil{}: Nil{}
    case Con{first, +rest}: List.append(&2, Violation, against(first, rest), independent_targets(rest))

def check(+active: +List<UI.Node>, frame: Frame) -> +List<Violation>:
  Frame{+viewport, +elements, focused, tab_order} = frame
  List.append(&2, Violation, nodes(active, False{}, elements, viewport),
    List.append(&2, Violation, focus_checks(focused, active, elements, viewport),
      List.append(&2, Violation, issue(Bool.not(same_order(expected_tabs(active, elements), tab_order)), WrongTabOrder{}),
        independent_targets(actionable_elements(active, elements)))))

def violations(+surface: UI.Surface, +frame: Frame) -> +List<Violation>:
  UI.Surface{content, base, overlays, +scope} = surface
  Frame{viewport, elements, +focused, tab_order} = frame
  List.append(&2, Violation, check(UI.active_nodes(surface), frame), required_focus(scope, focused))

def accepted(violations: +List<Violation>, generation: Nat, frame: Frame) -> State:
  match violations:
    case Nil{}: Realized{generation, frame}
    case other: Unmet{generation, frame, other}

def receive(owned: Bool, generation: Nat, surface: UI.Surface, +frame: Frame, previous: State) -> State:
  match owned:
    case False{}: previous
    case True{}: accepted(violations(surface, frame), generation, frame)
def observe(+current: Nat, received: Nat, surface: UI.Surface, frame: Frame, previous: State) -> State:
  receive(Nat.is_eq(current, received), current, surface, frame, previous)



def stale_frame_retains_state(+current: Nat, +received: Nat, +surface: UI.Surface, +frame: Frame, +previous: State,
  different: {Nat.is_eq(current, received) == False{} : Bool}) ->
  {observe(current, received, surface, frame, previous) == previous : State}:
  Equal.cong(Bool, State, (owned => receive(owned, current, surface, frame, previous)), Nat.is_eq(current, received), False{}, different)
