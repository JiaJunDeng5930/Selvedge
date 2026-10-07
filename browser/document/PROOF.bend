import Base
import ../../bendlib/logic-proof.bend as Logic
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../controls/GEOMETRY.bend as Geometry
import ./SPEC.bend as Spec
import ./RENDERED.bend as Rendered
import ./CONTRACT.bend as Rule
import ../../interaction/conversation/CODE.bend as Code
import ./MODEL.bend as Observation
import ./code-observation-rules.bend as RuleCodeObservationRules
import ../runtime/MODEL.bend as Browser
import ../layout/CONTENT.bend as Content
import ../runtime/SEMANTICS.bend as Legacy
import ../MODEL.bend as Web
import ./SOURCE.bend as Source
import ./code-surface-rules.bend as RuleCodeSurfaceRules
import ../appearance/DESIGN.bend as Design
import ../../bendlib/algebra-proof.bend as Alg
import ./presentation-order-laws.bend as RulePresentationOrderLaws
import ../controls/PROGRAM.bend as Controls
import ./presentation-order.bend as Order
import ../../bendlib/stdlib.bend as Std
import ./project-presentation-laws.bend as RuleProjectPresentationLaws
import ../controls/MODEL.bend as Authored
import ../layout/physical-space.bend as Model
import ../layout/enclosure.bend as Enclosure
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/MODEL.bend as View
import ./rendered-rules.bend as RuleRenderedRules
import ./source-frame-rules.bend as RuleSourceFrameRules
import ./task-details-laws.bend as RuleTaskDetailsLaws
import ../appearance/TYPOGRAPHY.bend as T
import ../../interaction/presentation/COMPOSITION.bend as Composition
import ../../features/board/MODEL.bend as Board
import ./source-rules.bend as RuleSourceRules
import ../controls/authored-primitives.bend as Factory
import ../layout/PROOF.bend as Arithmetic

def clear_append(left: +List<Rendered.Violation>, right: +List<Rendered.Violation>) ->
  {Rule.clear(List.append(&2, Rendered.Violation, left, right)) == (Rule.clear(left) && Rule.clear(right)) : Bool}:
  match left:
    case Nil{}: {==}
    case Con{fault, rest}: {==}

def clear_issue(violated: Bool, fault: Rendered.Violation) ->
  {Rule.clear(Rendered.issue(violated, fault)) == Bool.not(violated) : Bool}:
  match violated:
    case True{}: {==}
    case False{}: {==}

def clear_issue_positive(positive: Bool, fault: Rendered.Violation) ->
  {Rule.clear(Rendered.issue(Bool.not(positive), fault)) == positive : Bool}:
  match positive:
    case True{}: {==}
    case False{}: {==}

def clear_issue_pair(+first: Bool, +second: Bool, +first_fault: Rendered.Violation, +second_fault: Rendered.Violation) ->
  {Rule.clear(List.append(&2, Rendered.Violation, Rendered.issue(first, first_fault), Rendered.issue(second, second_fault))) ==
    (Bool.not(first) && Bool.not(second)) : Bool}:
  Equal.trans(Bool,
    Rule.clear(List.append(&2, Rendered.Violation, Rendered.issue(first, first_fault), Rendered.issue(second, second_fault))),
    Rule.clear(Rendered.issue(first, first_fault)) && Rule.clear(Rendered.issue(second, second_fault)),
    Bool.not(first) && Bool.not(second),
    clear_append(Rendered.issue(first, first_fault), Rendered.issue(second, second_fault)),
    Equal.trans(Bool,
      Rule.clear(Rendered.issue(first, first_fault)) && Rule.clear(Rendered.issue(second, second_fault)),
      Bool.not(first) && Rule.clear(Rendered.issue(second, second_fault)),
      Bool.not(first) && Bool.not(second),
      Equal.cong(Bool, Bool,
        (head => head && Rule.clear(Rendered.issue(second, second_fault))),
        Rule.clear(Rendered.issue(first, first_fault)), Bool.not(first),
        clear_issue(first, first_fault)),
      Equal.cong(Bool, Bool,
        (tail => Bool.not(first) && tail),
        Rule.clear(Rendered.issue(second, second_fault)), Bool.not(second),
        clear_issue(second, second_fault))))

def clear_enabled_geometry(required: Bool, +key: String, +visible: Bool,
  keyboard: Bool, scroll: Bool, bounds: Geometry.Rect, hit: String,
  must_be_visible: Bool, viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)) ==
    Spec.enabled_geometry_valid(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport) : Bool}:
  match required:
    case False{}: {==}
    case True{}:
      clear_issue_pair(
        Bool.not(keyboard && (visible || scroll)) ||
          (must_be_visible && Bool.not(visible && Geometry.contains(viewport, bounds))),
        visible && Bool.not(String.eq(key, hit)),
        Rendered.UnreachableControl{key}, Rendered.OccludedControl{key})

def clear_control_geometry(+required: Bool, +key: String, found: Maybe<&2, Rendered.Element>,
  +must_be_visible: Bool, +viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.control_geometry(required, key, found, must_be_visible, viewport)) ==
    Spec.control_geometry_valid(required, key, found, must_be_visible, viewport) : Bool}:
  match found:
    case None{}: {==}
    case Some{Rendered.Element{observed_key, +visible, +enabled, tab, +keyboard, +scroll, +bounds, +hit, +paint_bounds}}:
      Equal.trans(Bool,
        Rule.clear(Rendered.control_geometry(required, key,
          Some{Rendered.Element{observed_key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}},
          must_be_visible, viewport)),
        Rule.clear(Rendered.issue(Bool.not((required && enabled) || (Bool.not(required) && Bool.not(enabled))), Rendered.DisabledAppearance{key})) &&
          Rule.clear(Rendered.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)),
        Spec.control_geometry_valid(required, key,
          Some{Rendered.Element{observed_key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}},
          must_be_visible, viewport),
        clear_append(
          Rendered.issue(Bool.not((required && enabled) || (Bool.not(required) && Bool.not(enabled))), Rendered.DisabledAppearance{key}),
          Rendered.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)),
        Equal.trans(Bool,
          Rule.clear(Rendered.issue(Bool.not((required && enabled) || (Bool.not(required) && Bool.not(enabled))), Rendered.DisabledAppearance{key})) &&
            Rule.clear(Rendered.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)),
          Spec.same_bool(required, enabled) &&
            Rule.clear(Rendered.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)),
          Spec.control_geometry_valid(required, key,
            Some{Rendered.Element{observed_key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}},
            must_be_visible, viewport),
          Equal.cong(Bool, Bool,
            (head => head && Rule.clear(Rendered.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport))),
            Rule.clear(Rendered.issue(Bool.not((required && enabled) || (Bool.not(required) && Bool.not(enabled))), Rendered.DisabledAppearance{key})),
            Spec.same_bool(required, enabled),
            clear_issue_positive((required && enabled) || (Bool.not(required) && Bool.not(enabled)), Rendered.DisabledAppearance{key})),
          Equal.cong(Bool, Bool,
            (tail => Spec.same_bool(required, enabled) && tail),
            Rule.clear(Rendered.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)),
            Spec.enabled_geometry_valid(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport),
            clear_enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport))))

def clear_node_controls(is_control: Bool, meaning: InterfaceView.Meaning, key: String,
  found: Maybe<&2, Rendered.Element>, must_be_visible: Bool, viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.node_controls(is_control, meaning, key, found, must_be_visible, viewport)) ==
    Spec.node_controls_valid(is_control, meaning, key, found, must_be_visible, viewport) : Bool}:
  match is_control:
    case False{}: {==}
    case True{}:
      clear_control_geometry(Rendered.required_enabled(meaning), key, found, must_be_visible, viewport)

def clear_bounded_dialog(key: String, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.bounded_dialog(key, found, viewport)) == Spec.bounded_region(found, viewport) : Bool}:
  match found:
    case None{}: {==}
    case Some{Rendered.Element{observed_key, +visible, enabled, tab, keyboard, scroll, +bounds, hit, +paint_bounds}}:
      clear_issue_positive(visible && Geometry.contains(viewport, bounds), Rendered.EscapedDialog{key})

def clear_reachable_toolbar(key: String, found: Maybe<&2, Rendered.Element>) ->
  {Rule.clear(Rendered.reachable_toolbar(key, found)) == Spec.reachable_toolbar(found) : Bool}:
  match found:
    case None{}: {==}
    case Some{Rendered.Element{observed_key, +visible, enabled, tab, keyboard, +scroll, bounds, hit, +paint_bounds}}:
      clear_issue_positive(visible || scroll, Rendered.EscapedDialog{key})

def clear_region_geometry(role: InterfaceView.Role, key: String, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.region_geometry(role, key, found, viewport)) == Spec.region_geometry_valid(role, found, viewport) : Bool}:
  match role:
    case InterfaceView.Navigation{}: clear_bounded_dialog(key, found, viewport)
    case InterfaceView.NavigationHeader{}: clear_bounded_dialog(key, found, viewport)
    case InterfaceView.Main{}: clear_bounded_dialog(key, found, viewport)
    case InterfaceView.Heading{}: {==}
    case InterfaceView.Timeline{}: {==}
    case InterfaceView.Activity{}: {==}
    case InterfaceView.Composer{}: clear_bounded_dialog(key, found, viewport)
    case InterfaceView.Approval{}: {==}
    case InterfaceView.Toolbar{}: clear_reachable_toolbar(key, found)
    case InterfaceView.CodeBlock{}: {==}
    case InterfaceView.ApprovalQueue{}: clear_bounded_dialog(key, found, viewport)
    case InterfaceView.Section{}: {==}
    case InterfaceView.DialogActions{}: clear_bounded_dialog(key, found, viewport)
    case InterfaceView.Dialog{}: clear_bounded_dialog(key, found, viewport)
    case InterfaceView.Menu{}: clear_bounded_dialog(key, found, viewport)
    case InterfaceView.Details{}: {==}
    case InterfaceView.Card{}: {==}
    case InterfaceView.Button{}: {==}
    case InterfaceView.PrimaryButton{}: {==}
    case InterfaceView.DestructiveButton{}: {==}
    case InterfaceView.SelectedButton{}: {==}
    case InterfaceView.Field{}: {==}
    case InterfaceView.Content{}: {==}
    case InterfaceView.Alert{}: {==}
    case InterfaceView.UserMessage{}: {==}
    case InterfaceView.AssistantMessage{}: {==}
    case InterfaceView.ComposerActions{}: {==}

def clear_node_geometry(found: Maybe<&2, Rendered.Element>, +meaning: InterfaceView.Meaning,
  +role: InterfaceView.Role, +key: String, +must_be_visible: Bool, +viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.node_geometry(found, meaning, role, key, must_be_visible, viewport)) ==
    Spec.node_geometry_valid(found, Rendered.interactive(meaning), meaning, role, key, must_be_visible, viewport) : Bool}:
  match found:
    case None{}: {==}
    case Some{+element}:
      +control_faults = Rendered.node_controls(Rendered.interactive(meaning), meaning, key, Some{element}, must_be_visible, viewport)
      +region_faults = Rendered.region_geometry(role, key, Some{element}, viewport)
      +control_clear = Rule.clear(control_faults)
      +region_clear = Rule.clear(region_faults)
      +spec_control = Spec.node_controls_valid(Rendered.interactive(meaning), meaning, key, Some{element}, must_be_visible, viewport)
      +spec_region = Spec.region_geometry_valid(role, Some{element}, viewport)
      +after_control = spec_control && region_clear
      Equal.trans(Bool,
        Rule.clear(Rendered.node_geometry(Some{element}, meaning, role, key, must_be_visible, viewport)),
        control_clear && region_clear,
        spec_control && spec_region,
        clear_append(control_faults, region_faults),
        Equal.trans(Bool,
          control_clear && region_clear,
          after_control,
          spec_control && spec_region,
          Equal.cong(Bool, Bool, (checked => checked && region_clear),
            control_clear, spec_control,
            clear_node_controls(Rendered.interactive(meaning), meaning, key, Some{element}, must_be_visible, viewport)),
          Equal.cong(Bool, Bool, (checked => spec_control && checked),
            region_clear, spec_region,
            clear_region_geometry(role, key, Some{element}, viewport))))

def clear_nodes(entries: +List<InterfaceView.Node>, +inherited: Bool,
  +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.nodes(entries, inherited, elements, viewport)) == Spec.all_nodes(entries, inherited, elements, viewport) : Bool}:
  match entries:
    case Nil{}: {==}
    case Con{InterfaceView.Node{+key, semantic, label, +role, +meaning, +children}, +rest}:
      +parent_required = inherited || Rendered.persistent(role)
      +child_required = parent_required || Rendered.code_in_view(role, Rendered.find_element(elements, UIIdentity.encode(key)), viewport)
      +head_faults = Rendered.node_geometry(Rendered.find_element(elements, UIIdentity.encode(key)), meaning, role, UIIdentity.encode(key), parent_required, viewport)
      +child_faults = Rendered.nodes(children, child_required, elements, viewport)
      +rest_faults = Rendered.nodes(rest, inherited, elements, viewport)
      +tail_faults = List.append(&2, Rendered.Violation, child_faults, rest_faults)
      +head_clear = Rule.clear(head_faults)
      +children_clear = Rule.clear(child_faults)
      +rest_clear = Rule.clear(rest_faults)
      +actual_tail = children_clear && rest_clear
      +actual_all = head_clear && actual_tail
      +head_spec = Spec.node_valid(InterfaceView.Node{key, semantic, label, role, meaning, children}, inherited, elements, viewport)
      +children_spec = Spec.all_nodes(children, child_required, elements, viewport)
      +rest_spec = Spec.all_nodes(rest, inherited, elements, viewport)
      +spec_tail = children_spec && rest_spec
      +after_head = head_spec && actual_tail
      +after_children = head_spec && (children_spec && rest_clear)
      +expected_all = head_spec && spec_tail
      +list_expansion = Equal.trans(Bool,
        Rule.clear(Rendered.nodes(Con{InterfaceView.Node{key, semantic, label, role, meaning, children}, rest}, inherited, elements, viewport)),
        head_clear && Rule.clear(tail_faults),
        actual_all,
        clear_append(head_faults, tail_faults),
        Equal.cong(Bool, Bool, (tail_clear => head_clear && tail_clear),
          Rule.clear(tail_faults), actual_tail,
          clear_append(child_faults, rest_faults)))
      +head_step = Equal.cong(Bool, Bool, (head_clear_value => head_clear_value && actual_tail),
        head_clear, head_spec,
        clear_node_geometry(Rendered.find_element(elements, UIIdentity.encode(key)), meaning, role, UIIdentity.encode(key), parent_required, viewport))
      +children_step = Equal.cong(Bool, Bool, (children_clear_value => head_spec && (children_clear_value && rest_clear)),
        children_clear, children_spec,
        clear_nodes(children, child_required, elements, viewport))
      +rest_step = Equal.cong(Bool, Bool, (rest_clear_value => head_spec && (children_spec && rest_clear_value)),
        rest_clear, rest_spec,
        clear_nodes(rest, inherited, elements, viewport))
      +semantic_steps = Equal.trans(Bool, actual_all, after_head, expected_all,
        head_step,
        Equal.trans(Bool, after_head, after_children, expected_all, children_step, rest_step))
      Equal.trans(Bool,
        Rule.clear(Rendered.nodes(Con{InterfaceView.Node{key, semantic, label, role, meaning, children}, rest}, inherited, elements, viewport)),
        actual_all, expected_all, list_expansion, semantic_steps)

def node_exists_matches(found: Maybe<&2, InterfaceView.Node>) ->
  {Rendered.exists(found) == Spec.node_exists(found) : Bool}:
  match found:
    case None{}: {==}
    case Some{node}: {==}

def clear_focus_checks(focused: Maybe<&2, String>, +active: +List<InterfaceView.Node>,
  +elements: +List<Rendered.Element>, +viewport: Geometry.Rect, +native_focus: +List<Rendered.NativeFocus>) ->
  {Rule.clear(Rendered.focus_checks(focused, active, elements, viewport, native_focus)) == Spec.focus(focused, active, elements, viewport, native_focus) : Bool}:
  match focused:
    case None{}: {==}
    case Some{+key}:
      Equal.trans(Bool,
        Rule.clear(Rendered.focus_checks(Some{key}, active, elements, viewport, native_focus)),
        Rule.clear(Rendered.issue(Bool.not(Rendered.focus_visible(Rendered.find_element(elements, key), viewport)), Rendered.InvisibleFocus{})) &&
          Rule.clear(Rendered.issue(Bool.not(Rendered.focus_owned(active, elements, native_focus, key)), Rendered.FocusOutsideScope{})),
        Spec.focus(Some{key}, active, elements, viewport, native_focus),
        clear_append(
          Rendered.issue(Bool.not(Rendered.focus_visible(Rendered.find_element(elements, key), viewport)), Rendered.InvisibleFocus{}),
          Rendered.issue(Bool.not(Rendered.focus_owned(active, elements, native_focus, key)), Rendered.FocusOutsideScope{})),
        Equal.trans(Bool,
          Rule.clear(Rendered.issue(Bool.not(Rendered.focus_visible(Rendered.find_element(elements, key), viewport)), Rendered.InvisibleFocus{})) &&
            Rule.clear(Rendered.issue(Bool.not(Rendered.focus_owned(active, elements, native_focus, key)), Rendered.FocusOutsideScope{})),
          Rendered.focus_visible(Rendered.find_element(elements, key), viewport) &&
            Rule.clear(Rendered.issue(Bool.not(Rendered.focus_owned(active, elements, native_focus, key)), Rendered.FocusOutsideScope{})),
          Rendered.focus_visible(Rendered.find_element(elements, key), viewport) &&
            Rendered.focus_owned(active, elements, native_focus, key),
          Equal.cong(Bool, Bool,
            (focus_clear => focus_clear && Rule.clear(Rendered.issue(Bool.not(Rendered.focus_owned(active, elements, native_focus, key)), Rendered.FocusOutsideScope{}))),
            Rule.clear(Rendered.issue(Bool.not(Rendered.focus_visible(Rendered.find_element(elements, key), viewport)), Rendered.InvisibleFocus{})),
            Rendered.focus_visible(Rendered.find_element(elements, key), viewport),
            clear_issue_positive(Rendered.focus_visible(Rendered.find_element(elements, key), viewport), Rendered.InvisibleFocus{})),
          Equal.cong(Bool, Bool,
            (scope_clear => Rendered.focus_visible(Rendered.find_element(elements, key), viewport) && scope_clear),
            Rule.clear(Rendered.issue(Bool.not(Rendered.focus_owned(active, elements, native_focus, key)), Rendered.FocusOutsideScope{})),
            Rendered.focus_owned(active, elements, native_focus, key),
            Equal.trans(Bool,
              Rule.clear(Rendered.issue(Bool.not(Rendered.focus_owned(active, elements, native_focus, key)), Rendered.FocusOutsideScope{})),
              Rendered.focus_owned(active, elements, native_focus, key),
              Rendered.focus_owned(active, elements, native_focus, key),
              clear_issue_positive(Rendered.focus_owned(active, elements, native_focus, key), Rendered.FocusOutsideScope{}),
              {==}))))

def clear_required_focus(scope: Maybe<&2, String>, focused: Maybe<&2, String>) ->
  {Rule.clear(Rendered.required_focus(scope, focused)) == Spec.required_focus(scope, focused) : Bool}:
  match scope:
    case None{}: {==}
    case Some{key}:
      match focused:
        case None{}: {==}
        case Some{focus_key}: {==}

def clear_tab_order(expected: +List<String>, actual: +List<String>) ->
  {Rule.clear(Rendered.issue(Bool.not(Rendered.same_order(expected, actual)), Rendered.WrongTabOrder{})) ==
    Rendered.same_order(expected, actual) : Bool}:
  clear_issue_positive(Rendered.same_order(expected, actual), Rendered.WrongTabOrder{})

def clear_against(+first: Rendered.Element, rest: +List<Rendered.Element>) ->
  {Rule.clear(Rendered.against(first, rest)) == Spec.disjoint_from(first, rest) : Bool}:
  Rendered.Element{key, visible, enabled, tab, keyboard, scroll, +bounds, hit, +paint_bounds} = first
  match rest:
    case Nil{}: {==}
    case Con{Rendered.Element{+other, v, e, t, k, s, +other_bounds, h, +other_paint_bounds}, +tail}:
      Equal.trans(Bool,
        Rule.clear(Rendered.against(first, rest)),
        Rule.clear(Rendered.issue(Rendered.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other})) &&
          Rule.clear(Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)),
        Spec.disjoint_from(first, rest),
        clear_append(
          Rendered.issue(Rendered.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other}),
          Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)),
        Equal.trans(Bool,
          Rule.clear(Rendered.issue(Rendered.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other})) &&
            Rule.clear(Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)),
          Bool.not(Rendered.overlaps(paint_bounds, other_paint_bounds)) &&
            Rule.clear(Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)),
          Bool.not(Rendered.overlaps(paint_bounds, other_paint_bounds)) &&
            Spec.disjoint_from(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail),
          Equal.cong(Bool, Bool,
            (head_clear => head_clear && Rule.clear(Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail))),
            Rule.clear(Rendered.issue(Rendered.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other})),
            Bool.not(Rendered.overlaps(paint_bounds, other_paint_bounds)),
            clear_issue(Rendered.overlaps(paint_bounds, other_paint_bounds), Rendered.OverlappingControls{key, other})),
          Equal.cong(Bool, Bool,
            (tail_clear => Bool.not(Rendered.overlaps(paint_bounds, other_paint_bounds)) && tail_clear),
            Rule.clear(Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail)),
            Spec.disjoint_from(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail),
            clear_against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit, paint_bounds}, tail))))

def clear_independent_targets(elements: +List<Rendered.Element>) ->
  {Rule.clear(Rendered.independent_targets(elements)) == Spec.non_overlapping(elements) : Bool}:
  match elements:
    case Nil{}: {==}
    case Con{+first, +rest}:
      Equal.trans(Bool,
        Rule.clear(Rendered.independent_targets(Con{first, rest})),
        Rule.clear(Rendered.against(first, rest)) && Rule.clear(Rendered.independent_targets(rest)),
        Spec.non_overlapping(Con{first, rest}),
        clear_append(Rendered.against(first, rest), Rendered.independent_targets(rest)),
        Equal.trans(Bool,
          Rule.clear(Rendered.against(first, rest)) && Rule.clear(Rendered.independent_targets(rest)),
          Spec.disjoint_from(first, rest) && Rule.clear(Rendered.independent_targets(rest)),
          Spec.disjoint_from(first, rest) && Spec.non_overlapping(rest),
          Equal.cong(Bool, Bool,
            (head_clear => head_clear && Rule.clear(Rendered.independent_targets(rest))),
            Rule.clear(Rendered.against(first, rest)), Spec.disjoint_from(first, rest),
            clear_against(first, rest)),
          Equal.cong(Bool, Bool,
            (tail_clear => Spec.disjoint_from(first, rest) && tail_clear),
            Rule.clear(Rendered.independent_targets(rest)), Spec.non_overlapping(rest),
            clear_independent_targets(rest))))

def clear_layout_check(+active: +List<InterfaceView.Node>, +frame: Rendered.Frame) ->
  {Rule.clear(Rendered.layout_check(active, frame)) == Spec.layout_valid_parts(active, frame) : Bool}:
  Rendered.Frame{+viewport, +elements, +focused, +tab_order, +native_focus} = frame
  +node_faults = Rendered.nodes(active, False{}, elements, viewport)
  +focus_faults = Rendered.focus_checks(focused, active, elements, viewport, native_focus)
  +tab_faults = Rendered.issue(Bool.not(Rendered.tabs_valid(active, elements, native_focus, tab_order)), Rendered.WrongTabOrder{})
  +target_faults = Rendered.independent_targets(Rendered.actionable_elements(active, elements))
  +tab_and_target_faults = List.append(&2, Rendered.Violation, tab_faults, target_faults)
  +focus_and_tail_faults = List.append(&2, Rendered.Violation, focus_faults, tab_and_target_faults)
  +nodes_clear = Rule.clear(node_faults)
  +focus_clear = Rule.clear(focus_faults)
  +tab_clear = Rule.clear(tab_faults)
  +targets_clear = Rule.clear(target_faults)
  +middle_clear = tab_clear && targets_clear
  +tail_clear = focus_clear && middle_clear
  +actual_clear = nodes_clear && tail_clear
  +after_nodes = Spec.all_nodes(active, False{}, elements, viewport) && (focus_clear && middle_clear)
  +after_focus = Spec.all_nodes(active, False{}, elements, viewport) &&
    (Spec.focus(focused, active, elements, viewport, native_focus) && middle_clear)
  +after_tabs = Spec.all_nodes(active, False{}, elements, viewport) &&
    (Spec.focus(focused, active, elements, viewport, native_focus) &&
      (Rendered.tabs_valid(active, elements, native_focus, tab_order) && targets_clear))
  +target = Spec.layout_valid_parts(active, frame)
  +pair_clear = clear_append(tab_faults, target_faults)
  +focus_tail_clear = Equal.trans(Bool,
    Rule.clear(focus_and_tail_faults),
    focus_clear && Rule.clear(tab_and_target_faults),
    tail_clear,
    clear_append(focus_faults, tab_and_target_faults),
    Equal.cong(Bool, Bool, (tail_value => focus_clear && tail_value),
      Rule.clear(tab_and_target_faults), middle_clear, pair_clear))
  +body_clear = Equal.trans(Bool,
    Rule.clear(Rendered.layout_check(active, frame)),
    nodes_clear && Rule.clear(focus_and_tail_faults),
    actual_clear,
    clear_append(node_faults, focus_and_tail_faults),
    Equal.cong(Bool, Bool, (tail_value => nodes_clear && tail_value),
      Rule.clear(focus_and_tail_faults), tail_clear, focus_tail_clear))
  +node_step = Equal.cong(Bool, Bool, (node_value => node_value && tail_clear),
    nodes_clear, Spec.all_nodes(active, False{}, elements, viewport),
    clear_nodes(active, False{}, elements, viewport))
  +focus_step = Equal.cong(Bool, Bool, (focus_value => Spec.all_nodes(active, False{}, elements, viewport) && (focus_value && middle_clear)),
    focus_clear, Spec.focus(focused, active, elements, viewport, native_focus),
    clear_focus_checks(focused, active, elements, viewport, native_focus))
  +tab_step = Equal.cong(Bool, Bool, (tab_value => tab_value && targets_clear),
    tab_clear, Rendered.tabs_valid(active, elements, native_focus, tab_order),
    clear_issue_positive(Rendered.tabs_valid(active, elements, native_focus, tab_order), Rendered.WrongTabOrder{}))
  +middle_step = Equal.cong(Bool, Bool,
    (middle_value => Spec.all_nodes(active, False{}, elements, viewport) &&
      (Spec.focus(focused, active, elements, viewport, native_focus) && middle_value)),
    middle_clear, Rendered.tabs_valid(active, elements, native_focus, tab_order) && targets_clear,
    tab_step)
  +target_step = Equal.cong(Bool, Bool,
    (target_value => Spec.all_nodes(active, False{}, elements, viewport) &&
      (Spec.focus(focused, active, elements, viewport, native_focus) &&
        (Rendered.tabs_valid(active, elements, native_focus, tab_order) && target_value))),
    targets_clear, Spec.non_overlapping(Rendered.actionable_elements(active, elements)),
    clear_independent_targets(Rendered.actionable_elements(active, elements)))
  +nodes_focus_step = Equal.trans(Bool, actual_clear, after_nodes, after_focus, node_step, focus_step)
  +semantic_step = Equal.trans(Bool, after_focus, after_tabs, target, middle_step, target_step)
  Equal.trans(Bool, Rule.clear(Rendered.layout_check(active, frame)), actual_clear, target, body_clear,
    Equal.trans(Bool, actual_clear, after_focus, target, nodes_focus_step, semantic_step))

def clear_paint_geometry(+elements: +List<Rendered.Element>, +viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.paint_geometry(elements, viewport)) == Spec.paint_geometry_valid(elements, viewport) : Bool}:
  match elements:
    case Nil{}: {==}
    case Con{Rendered.Element{+key, +visible, enabled, tab, keyboard, scroll, +bounds, hit, +paint_bounds}, +rest}:
      +valid = Rendered.paint_geometry_valid(visible, bounds, paint_bounds, viewport)
      +fault = Rendered.issue(Bool.not(valid), Rendered.InvalidPaintGeometry{key})
      +tail = Rendered.paint_geometry(rest, viewport)
      Equal.trans(Bool,
        Rule.clear(List.append(&2, Rendered.Violation, fault, tail)),
        Rule.clear(fault) && Rule.clear(tail),
        valid && Spec.paint_geometry_valid(rest, viewport),
        clear_append(fault, tail),
        Equal.trans(Bool,
          Rule.clear(fault) && Rule.clear(tail), valid && Rule.clear(tail),
          valid && Spec.paint_geometry_valid(rest, viewport),
          Equal.cong(Bool, Bool, (head => head && Rule.clear(tail)),
            Rule.clear(fault), valid, clear_issue_positive(valid, Rendered.InvalidPaintGeometry{key})),
          Equal.cong(Bool, Bool, (tail_valid => valid && tail_valid),
            Rule.clear(tail), Spec.paint_geometry_valid(rest, viewport), clear_paint_geometry(rest, viewport))))

def clear_check(+active: +List<InterfaceView.Node>, +frame: Rendered.Frame) ->
  {Rule.clear(Rendered.check(active, frame)) == Spec.valid_parts(active, frame) : Bool}:
  Rendered.Frame{+viewport, +elements, focused, tab_order, native_focus} = frame
  +paint = Rendered.paint_geometry(elements, viewport)
  +layout = Rendered.layout_check(active, frame)
  Equal.trans(Bool,
    Rule.clear(Rendered.check(active, frame)), Rule.clear(paint) && Rule.clear(layout),
    Spec.valid_parts(active, frame), clear_append(paint, layout),
    Equal.trans(Bool,
      Rule.clear(paint) && Rule.clear(layout),
      Spec.paint_geometry_valid(elements, viewport) && Rule.clear(layout),
      Spec.valid_parts(active, frame),
      Equal.cong(Bool, Bool, (paint_valid => paint_valid && Rule.clear(layout)),
        Rule.clear(paint), Spec.paint_geometry_valid(elements, viewport), clear_paint_geometry(elements, viewport)),
      Equal.cong(Bool, Bool, (layout_valid => Spec.paint_geometry_valid(elements, viewport) && layout_valid),
        Rule.clear(layout), Spec.layout_valid_parts(active, frame), clear_layout_check(active, frame))))

def reflected(+surface: InterfaceView.Surface, +frame: Rendered.Frame) ->
  {Rule.clear(Rendered.violations(surface, frame)) == Spec.valid(surface, frame) : Bool}:
  InterfaceView.Surface{content, base, overlays, +scope} = surface
  Rendered.Frame{viewport, elements, +focused, tab_order, +native_focus} = frame
  Equal.trans(Bool,
    Rule.clear(Rendered.violations(surface, frame)),
    Rule.clear(Rendered.check(InterfaceView.active_nodes(surface), frame)) && Rule.clear(Rendered.required_focus(scope, focused)),
    Spec.valid(surface, frame),
    clear_append(Rendered.check(InterfaceView.active_nodes(surface), frame), Rendered.required_focus(scope, focused)),
    Equal.trans(Bool,
      Rule.clear(Rendered.check(InterfaceView.active_nodes(surface), frame)) && Rule.clear(Rendered.required_focus(scope, focused)),
      Spec.valid_parts(InterfaceView.active_nodes(surface), frame) && Rule.clear(Rendered.required_focus(scope, focused)),
      Spec.valid(surface, frame),
      Equal.cong(Bool, Bool,
        (check_clear => check_clear && Rule.clear(Rendered.required_focus(scope, focused))),
        Rule.clear(Rendered.check(InterfaceView.active_nodes(surface), frame)),
        Spec.valid_parts(InterfaceView.active_nodes(surface), frame),
        clear_check(InterfaceView.active_nodes(surface), frame)),
      Equal.cong(Bool, Bool,
        (focus_clear => Spec.valid_parts(InterfaceView.active_nodes(surface), frame) && focus_clear),
        Rule.clear(Rendered.required_focus(scope, focused)),
        Spec.required_focus(scope, focused),
        clear_required_focus(scope, focused))))

def realized_faults_imply_valid(+faults: +List<Rendered.Violation>, +surface: InterfaceView.Surface,
  +frame: Rendered.Frame, generation: Nat,
  matching: {faults == Rendered.violations(surface, frame) : +List<Rendered.Violation>},
  realized: {Rendered.accepted(faults, generation, frame) == Rendered.Realized{generation, frame} : Rendered.State}) ->
  {Spec.valid(surface, frame) == True{} : Bool}:
  match faults:
    case Nil{}:
      Equal.trans(Bool,
        Spec.valid(surface, frame),
        Rule.clear(Rendered.violations(surface, frame)),
        True{},
        Equal.sym(Bool, Rule.clear(Rendered.violations(surface, frame)), Spec.valid(surface, frame), reflected(surface, frame)),
        Equal.trans(Bool,
          Rule.clear(Rendered.violations(surface, frame)),
          Rule.clear(faults),
          True{},
          Equal.sym(Bool, Rule.clear(faults), Rule.clear(Rendered.violations(surface, frame)),
            Equal.cong(+List<Rendered.Violation>, Bool, Rule.clear, faults, Rendered.violations(surface, frame), matching)),
          {==}))
    case Con{fault, rest}:
      Logic.impossible({Spec.valid(surface, frame) == True{} : Bool},
        Equal.cong(Rendered.State, Bool, Rule.realized_tag,
          Rendered.accepted(faults, generation, frame),
          Rendered.Realized{generation, frame}, realized))


def Rule.evidence():
  Rule.Requirements{reflected, +current => +received => +surface => +frame => +previous => owned => realized =>
      observed_owner = Equal.cong(Bool, Rendered.State,
        (ownership => Rendered.receive(ownership, current, surface, frame, previous)),
        Nat.is_eq(current, received), True{}, owned)
      accepted_realized = Equal.trans(Rendered.State,
        Rendered.receive(True{}, current, surface, frame, previous),
        Rendered.receive(Nat.is_eq(current, received), current, surface, frame, previous),
        Rendered.Realized{current, frame},
        Equal.sym(Rendered.State,
          Rendered.receive(Nat.is_eq(current, received), current, surface, frame, previous),
          Rendered.receive(True{}, current, surface, frame, previous), observed_owner),
        realized)
      realized_faults_imply_valid(Rendered.violations(surface, frame), surface, frame, current, {==}, accepted_realized)
    }

def Rule.dialog_actions_region_geometry(found, viewport): {==}

def Rule.dialog_actions_children_visible(inherited, found, viewport):
  match inherited:
    case False{}: {==}
    case True{}: {==}

def RuleCodeObservationRules.published_qualification(generation, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def RuleCodeObservationRules.rejected_batch(generation, observations, state, rejected):
  Equal.cong(Bool, Browser.Decision,
    (qualified => Browser.code_sources_if_qualified(qualified, observations, state)),
    Browser.code_batch_qualified(generation, observations, state), False{}, rejected)

def RuleCodeObservationRules.qualified_batch(generation, observations, state, qualified):
  Equal.cong(Bool, Browser.Decision,
    (admitted => Browser.code_sources_if_qualified(admitted, observations, state)),
    Browser.code_batch_qualified(generation, observations, state), True{}, qualified)

def RuleCodeObservationRules.empty_batch(generation, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def RuleCodeObservationRules.invalid_published_batch(generation, observations, state, invalid):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}:
              Equal.cong(Bool, Browser.Decision,
                (owned => Browser.code_sources_if_qualified(owned, observations, state)),
                Browser.code_batch_owned(observations, source), False{}, invalid)

def RuleCodeObservationRules.stale_batch(generation, observations, state, stale):
  RuleCodeObservationRules.invalid_published_batch(generation, observations, state, stale)

def RuleCodeObservationRules.unowned_entry(identity, text, source_value, rest, source, unowned):
  Equal.cong(Bool, Bool,
    (owned => owned && Browser.code_observations_owned(rest, source)),
    Browser.code_source_owned(source, identity, source_value), False{}, unowned)

def unowned_tail_result(+owned: Bool, +rest: +List<Observation.Observation>, +source: Source.Node,
    invalid: {Browser.code_observations_owned(rest, source) == False{} : Bool}) ->
    {owned && Browser.code_observations_owned(rest, source) == False{} : Bool}:
  match owned:
    case False{}: {==}
    case True{}: invalid

def RuleCodeObservationRules.unowned_tail(observation, rest, source, invalid):
  match observation:
    case Observation.Observation{identity, text, source_value}:
      unowned_tail_result(Browser.code_source_owned(source, identity, source_value), rest, source, invalid)

def RuleCodeObservationRules.fold_empty(decision): {==}
def RuleCodeObservationRules.fold_order(source, ordinal, text, source_value, rest, state, effects): {==}
def RuleCodeObservationRules.native_batch(generation, observations, state): {==}
def RuleCodeObservationRules.raw_source_rejected(identity, text, state): {==}
def RuleCodeObservationRules.raw_content_rejected(identity, text, state): {==}
def RuleCodeObservationRules.direct_web_rejected(generation, observations, state):
  match state:
    case Web.State{application, serial, realization, environment, font}: {==}

def RuleCodeObservationRules.missing_publication(generation, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}: {==}
def RuleCodeObservationRules.all_entries(identity, text, source_value, rest, source): {==}

def RuleCodeObservationRules.declared_content(owner, identity, value, source_value, policy):
  match identity:
    case Code.Identity{source, ordinal}: {==}
def RuleCodeObservationRules.undeclared_content(identity, value, source_value, policy):
  match identity:
    case Code.Identity{source, ordinal}: {==}
def RuleCodeObservationRules.generation_independent(first, second, observations, state):
  match state:
    case Browser.State{legacy, serial, anchors, lifecycle, displayed}:
      match displayed:
        case None{}: {==}
        case Some{Browser.Published{world, semantic, scope, basis, frame}}:
          match world:
            case Content.AllocatedWorld{Content.Snapshot{published, source, font}, tree, roots, policies}: {==}

def RuleCodeObservationRules.authored_source(key, value, visual, code_visual, owner, attachments, native_owner, identity, source_value):
  match identity:
    case Code.Identity{source, ordinal}: {==}
def RuleCodeObservationRules.stream_source(task, operation, index, text, parent, state): {==}

def canonical_frame(+visual: Design.Style) -> RuleCodeSurfaceRules.frame_is_canonical(visual):
  match visual:
    case Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

def canonical_chrome(+visual: Design.Style) -> RuleCodeSurfaceRules.chrome_is_canonical(visual):
  match visual:
    case Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}: {==}

def policy_projection(visual: Design.Style, +code_visual: Design.Style, reserve: Nat) -> RuleCodeSurfaceRules.policy_uses_code_surface(visual, code_visual, reserve):
  {==}

def RuleCodeSurfaceRules.evidence():
  RuleCodeSurfaceRules.Requirements{canonical_frame, canonical_chrome, policy_projection}

def panel_header_matches_specification(representation: Controls.Representation) ->
  {Controls.panel_header(representation) == RulePresentationOrderLaws.specified_header_representation(representation) : Bool}:
  match representation:
    case Controls.NoControl{}: {==}
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      match placement:
        case Controls.InFlow{}: {==}
        case Controls.ComposerEnd{}: {==}
        case Controls.PanelHeaderEnd{}: {==}
        case Controls.CodeToolbar{}: {==}
        case Controls.BesideValue{}: {==}
        case Controls.GroupHeadingEnd{}: {==}
    case Controls.Input{binding, name, widget, label, availability}: {==}
    case Controls.Movable{destinations, face, name, handle, geometry, help}: {==}

def header_classifier_matches_specification(value: InterfaceView.Node, +context: Controls.Context) ->
  {Order.header_child(value, context) == RulePresentationOrderLaws.specified_header_child(value, context) : Bool}:
  match value:
    case InterfaceView.Node{+key, semantic, +label, +role, +meaning, children}:
      panel_header_matches_specification(Controls.represent(key, meaning, label, role,
        Controls.enter(value, context)))

def partition_header_step_matches(value: InterfaceView.Node, include: Bool, parts: Order.DialogParts) ->
  {Order.partition_header(Order.partition_child(value, include, parts)) ==
    RulePresentationOrderLaws.header_step(value, include, Order.partition_header(parts)) : +List<InterfaceView.Node>}:
  match include:
    case True{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}
    case False{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}

def partition_body_step_matches(value: InterfaceView.Node, include: Bool, parts: Order.DialogParts) ->
  {Order.partition_body(Order.partition_child(value, include, parts)) ==
    RulePresentationOrderLaws.body_step(value, include, Order.partition_body(parts)) : +List<InterfaceView.Node>}:
  match include:
    case True{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}
    case False{}:
      match parts:
        case Order.DialogParts{+header, +body}: {==}

def partition_header_matches_specification(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Order.partition_header(Order.partition_dialog_children(values, context)) == RulePresentationOrderLaws.specified_header(values, context) : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_header_matches_specification(rest, context)
      +actual_include = Order.header_child(value, context)
      +specified_include = RulePresentationOrderLaws.specified_header_child(value, context)
      Equal.trans(+List<InterfaceView.Node>,
        Order.partition_header(Order.partition_child(value, actual_include, tail_parts)),
        RulePresentationOrderLaws.header_step(value, actual_include, Order.partition_header(tail_parts)),
        RulePresentationOrderLaws.header_step(value, specified_include, RulePresentationOrderLaws.specified_header(rest, context)),
        partition_header_step_matches(value, actual_include, tail_parts),
        Equal.trans(+List<InterfaceView.Node>,
          RulePresentationOrderLaws.header_step(value, actual_include, Order.partition_header(tail_parts)),
          RulePresentationOrderLaws.header_step(value, specified_include, Order.partition_header(tail_parts)),
          RulePresentationOrderLaws.header_step(value, specified_include, RulePresentationOrderLaws.specified_header(rest, context)),
          Equal.cong(Bool, +List<InterfaceView.Node>, (include => RulePresentationOrderLaws.header_step(value, include, Order.partition_header(tail_parts))),
            actual_include, specified_include, header_classifier_matches_specification(value, context)),
          Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => RulePresentationOrderLaws.header_step(value, specified_include, tail)),
            Order.partition_header(tail_parts), RulePresentationOrderLaws.specified_header(rest, context), tail_evidence)))

def partition_body_matches_specification(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Order.partition_body(Order.partition_dialog_children(values, context)) == RulePresentationOrderLaws.specified_body(values, context) : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_body_matches_specification(rest, context)
      +actual_include = Order.header_child(value, context)
      +specified_include = RulePresentationOrderLaws.specified_header_child(value, context)
      Equal.trans(+List<InterfaceView.Node>,
        Order.partition_body(Order.partition_child(value, actual_include, tail_parts)),
        RulePresentationOrderLaws.body_step(value, actual_include, Order.partition_body(tail_parts)),
        RulePresentationOrderLaws.body_step(value, specified_include, RulePresentationOrderLaws.specified_body(rest, context)),
        partition_body_step_matches(value, actual_include, tail_parts),
        Equal.trans(+List<InterfaceView.Node>,
          RulePresentationOrderLaws.body_step(value, actual_include, Order.partition_body(tail_parts)),
          RulePresentationOrderLaws.body_step(value, specified_include, Order.partition_body(tail_parts)),
          RulePresentationOrderLaws.body_step(value, specified_include, RulePresentationOrderLaws.specified_body(rest, context)),
          Equal.cong(Bool, +List<InterfaceView.Node>, (include => RulePresentationOrderLaws.body_step(value, include, Order.partition_body(tail_parts))),
            actual_include, specified_include, header_classifier_matches_specification(value, context)),
          Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => RulePresentationOrderLaws.body_step(value, specified_include, tail)),
            Order.partition_body(tail_parts), RulePresentationOrderLaws.specified_body(rest, context), tail_evidence)))

def parts_match_filters(parts: Order.DialogParts, expected_header: +List<InterfaceView.Node>,
  expected_body: +List<InterfaceView.Node>,
  header_evidence: {Order.partition_header(parts) == expected_header : +List<InterfaceView.Node>},
  body_evidence: {Order.partition_body(parts) == expected_body : +List<InterfaceView.Node>}) ->
  {parts == Order.DialogParts{expected_header, expected_body} : Order.DialogParts}:
  match parts:
    case Order.DialogParts{+header, +body}:
      Equal.trans(Order.DialogParts, Order.DialogParts{header, body},
        Order.DialogParts{expected_header, body}, Order.DialogParts{expected_header, expected_body},
        Equal.cong(+List<InterfaceView.Node>, Order.DialogParts,
          (value => Order.DialogParts{value, body}), header, expected_header, header_evidence),
        Equal.cong(+List<InterfaceView.Node>, Order.DialogParts,
          (value => Order.DialogParts{expected_header, value}), body, expected_body, body_evidence))

def partition_matches_specification(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Order.partition_dialog_children(values, context) == RulePresentationOrderLaws.specified_parts(values, context) : Order.DialogParts}:
  parts_match_filters(Order.partition_dialog_children(values, context),
    RulePresentationOrderLaws.specified_header(values, context), RulePresentationOrderLaws.specified_body(values, context),
    partition_header_matches_specification(values, context),
    partition_body_matches_specification(values, context))

def ordered_children_matches_specification(+values: +List<InterfaceView.Node>, role: InterfaceView.Role, +context: Controls.Context) ->
  {Order.ordered_children(role, values, context) == RulePresentationOrderLaws.specified_children(role, values, context) : +List<InterfaceView.Node>}:
  match role:
    case InterfaceView.Dialog{}:
      +parts_evidence = partition_matches_specification(values, context)
      Equal.cong(Order.DialogParts, +List<InterfaceView.Node>, (parts => Order.ordered_dialog_children(parts)),
        Order.partition_dialog_children(values, context), RulePresentationOrderLaws.specified_parts(values, context), parts_evidence)
    case InterfaceView.Navigation{}: {==}
    case InterfaceView.NavigationHeader{}: {==}
    case InterfaceView.Main{}: {==}
    case InterfaceView.Heading{}: {==}
    case InterfaceView.PrimaryButton{}: {==}
    case InterfaceView.DestructiveButton{}: {==}
    case InterfaceView.SelectedButton{}: {==}
    case InterfaceView.ComposerActions{}: {==}
    case InterfaceView.DialogActions{}: {==}
    case InterfaceView.Timeline{}: {==}
    case InterfaceView.Activity{}: {==}
    case InterfaceView.UserMessage{}: {==}
    case InterfaceView.AssistantMessage{}: {==}
    case InterfaceView.Composer{}: {==}
    case InterfaceView.Approval{}: {==}
    case InterfaceView.Toolbar{}: {==}
    case InterfaceView.CodeBlock{}: {==}
    case InterfaceView.ApprovalQueue{}: {==}
    case InterfaceView.Section{}: {==}
    case InterfaceView.Menu{}: {==}
    case InterfaceView.Details{}: {==}
    case InterfaceView.Card{}: {==}
    case InterfaceView.Button{}: {==}
    case InterfaceView.Field{}: {==}
    case InterfaceView.Content{}: {==}
    case InterfaceView.Alert{}: {==}

def non_dialog_order(role: InterfaceView.Role, +values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {RulePresentationOrderLaws.non_dialog_order_observation(role, values, context) == values : +List<InterfaceView.Node>}:
  match role:
    case InterfaceView.Dialog{}: {==}
    case InterfaceView.Navigation{}: {==}
    case InterfaceView.NavigationHeader{}: {==}
    case InterfaceView.Main{}: {==}
    case InterfaceView.Heading{}: {==}
    case InterfaceView.PrimaryButton{}: {==}
    case InterfaceView.DestructiveButton{}: {==}
    case InterfaceView.SelectedButton{}: {==}
    case InterfaceView.ComposerActions{}: {==}
    case InterfaceView.DialogActions{}: {==}
    case InterfaceView.Timeline{}: {==}
    case InterfaceView.Activity{}: {==}
    case InterfaceView.UserMessage{}: {==}
    case InterfaceView.AssistantMessage{}: {==}
    case InterfaceView.Composer{}: {==}
    case InterfaceView.Approval{}: {==}
    case InterfaceView.Toolbar{}: {==}
    case InterfaceView.CodeBlock{}: {==}
    case InterfaceView.ApprovalQueue{}: {==}
    case InterfaceView.Section{}: {==}
    case InterfaceView.Menu{}: {==}
    case InterfaceView.Details{}: {==}
    case InterfaceView.Card{}: {==}
    case InterfaceView.Button{}: {==}
    case InterfaceView.Field{}: {==}
    case InterfaceView.Content{}: {==}
    case InterfaceView.Alert{}: {==}

def specified_header_append_step(value: InterfaceView.Node, rest: +List<InterfaceView.Node>, right: +List<InterfaceView.Node>, include: Bool,
  +context: Controls.Context,
  tail_evidence: {RulePresentationOrderLaws.specified_header(List.append(&2, InterfaceView.Node, rest, right), context) ==
    List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_header(rest, context), RulePresentationOrderLaws.specified_header(right, context)) : +List<InterfaceView.Node>}) ->
  {RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(List.append(&2, InterfaceView.Node, rest, right), context)) ==
    List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(rest, context)), RulePresentationOrderLaws.specified_header(right, context)) : +List<InterfaceView.Node>}:
  match include:
    case True{}:
      Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => value <> tail),
        RulePresentationOrderLaws.specified_header(List.append(&2, InterfaceView.Node, rest, right), context),
        List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_header(rest, context), RulePresentationOrderLaws.specified_header(right, context)),
        tail_evidence)
    case False{}: tail_evidence

def specified_body_append_step(value: InterfaceView.Node, rest: +List<InterfaceView.Node>, right: +List<InterfaceView.Node>, include: Bool,
  +context: Controls.Context,
  tail_evidence: {RulePresentationOrderLaws.specified_body(List.append(&2, InterfaceView.Node, rest, right), context) ==
    List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_body(rest, context), RulePresentationOrderLaws.specified_body(right, context)) : +List<InterfaceView.Node>}) ->
  {RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(List.append(&2, InterfaceView.Node, rest, right), context)) ==
    List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(rest, context)), RulePresentationOrderLaws.specified_body(right, context)) : +List<InterfaceView.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => value <> tail),
        RulePresentationOrderLaws.specified_body(List.append(&2, InterfaceView.Node, rest, right), context),
        List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_body(rest, context), RulePresentationOrderLaws.specified_body(right, context)),
        tail_evidence)

def specified_header_append(+left: +List<InterfaceView.Node>, +right: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {RulePresentationOrderLaws.specified_header(List.append(&2, InterfaceView.Node, left, right), context) ==
    List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_header(left, context), RulePresentationOrderLaws.specified_header(right, context)) : +List<InterfaceView.Node>}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_append(rest, right, context)
      specified_header_append_step(value, rest, right, RulePresentationOrderLaws.specified_header_child(value, context), context,
        tail_evidence)

def specified_body_append(+left: +List<InterfaceView.Node>, +right: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {RulePresentationOrderLaws.specified_body(List.append(&2, InterfaceView.Node, left, right), context) ==
    List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_body(left, context), RulePresentationOrderLaws.specified_body(right, context)) : +List<InterfaceView.Node>}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_append(rest, right, context)
      specified_body_append_step(value, rest, right, RulePresentationOrderLaws.specified_header_child(value, context), context,
        tail_evidence)

def specified_header_idempotent_step(+value: InterfaceView.Node, +rest: +List<InterfaceView.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == RulePresentationOrderLaws.specified_header_child(value, context) : Bool},
  tail_evidence: {RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_header(rest, context), context) == RulePresentationOrderLaws.specified_header(rest, context) : +List<InterfaceView.Node>}) ->
  {RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(rest, context)), context) ==
    RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(rest, context)) : +List<InterfaceView.Node>}:
  match include:
    case True{}:
      +same_include = Equal.sym(Bool, include, RulePresentationOrderLaws.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<InterfaceView.Node>,
        (flag => RulePresentationOrderLaws.header_step(value, flag, RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_header(rest, context), context))),
        RulePresentationOrderLaws.specified_header_child(value, context), include, same_include)
      +tail_step = Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>,
        (tail => RulePresentationOrderLaws.header_step(value, include, tail)),
        RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_header(rest, context), context), RulePresentationOrderLaws.specified_header(rest, context), tail_evidence)
      Equal.trans(+List<InterfaceView.Node>,
        RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(rest, context)), context),
        RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_header(rest, context), context)),
        RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(rest, context)),
        Equal.trans(+List<InterfaceView.Node>,
          RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(rest, context)), context),
          RulePresentationOrderLaws.header_step(value, RulePresentationOrderLaws.specified_header_child(value, context), RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_header(rest, context), context)),
          RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_header(rest, context), context)),
          {==}, classifier_step),
        tail_step)
    case False{}: tail_evidence

def specified_body_idempotent_step(+value: InterfaceView.Node, +rest: +List<InterfaceView.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == RulePresentationOrderLaws.specified_header_child(value, context) : Bool},
  tail_evidence: {RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_body(rest, context), context) == RulePresentationOrderLaws.specified_body(rest, context) : +List<InterfaceView.Node>}) ->
  {RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(rest, context)), context) ==
    RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(rest, context)) : +List<InterfaceView.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      +same_include = Equal.sym(Bool, include, RulePresentationOrderLaws.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<InterfaceView.Node>,
        (flag => RulePresentationOrderLaws.body_step(value, flag, RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_body(rest, context), context))),
        RulePresentationOrderLaws.specified_header_child(value, context), include, same_include)
      +tail_step = Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>,
        (tail => RulePresentationOrderLaws.body_step(value, include, tail)),
        RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_body(rest, context), context), RulePresentationOrderLaws.specified_body(rest, context), tail_evidence)
      Equal.trans(+List<InterfaceView.Node>,
        RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(rest, context)), context),
        RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_body(rest, context), context)),
        RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(rest, context)),
        Equal.trans(+List<InterfaceView.Node>,
          RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(rest, context)), context),
          RulePresentationOrderLaws.body_step(value, RulePresentationOrderLaws.specified_header_child(value, context), RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_body(rest, context), context)),
          RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_body(rest, context), context)),
          {==}, classifier_step),
        tail_step)

def specified_header_after_body_step(+value: InterfaceView.Node, +rest: +List<InterfaceView.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == RulePresentationOrderLaws.specified_header_child(value, context) : Bool},
  tail_evidence: {RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_body(rest, context), context) == Nil{} : +List<InterfaceView.Node>}) ->
  {RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(rest, context)), context) == Nil{} : +List<InterfaceView.Node>}:
  match include:
    case True{}: tail_evidence
    case False{}:
      +same_include = Equal.sym(Bool, include, RulePresentationOrderLaws.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<InterfaceView.Node>,
        (flag => RulePresentationOrderLaws.header_step(value, flag, RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_body(rest, context), context))),
        RulePresentationOrderLaws.specified_header_child(value, context), include, same_include)
      Equal.trans(+List<InterfaceView.Node>,
        RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(rest, context)), context),
        RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_body(rest, context), context)),
        Nil{},
        Equal.trans(+List<InterfaceView.Node>,
          RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(rest, context)), context),
          RulePresentationOrderLaws.header_step(value, RulePresentationOrderLaws.specified_header_child(value, context), RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_body(rest, context), context)),
          RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_body(rest, context), context)),
          {==}, classifier_step),
        tail_evidence)

def specified_body_after_header_step(+value: InterfaceView.Node, +rest: +List<InterfaceView.Node>, +include: Bool,
  +context: Controls.Context,
  classifier: {include == RulePresentationOrderLaws.specified_header_child(value, context) : Bool},
  tail_evidence: {RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_header(rest, context), context) == Nil{} : +List<InterfaceView.Node>}) ->
  {RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(rest, context)), context) == Nil{} : +List<InterfaceView.Node>}:
  match include:
    case True{}:
      +same_include = Equal.sym(Bool, include, RulePresentationOrderLaws.specified_header_child(value, context), classifier)
      +classifier_step = Equal.cong(Bool, +List<InterfaceView.Node>,
        (flag => RulePresentationOrderLaws.body_step(value, flag, RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_header(rest, context), context))),
        RulePresentationOrderLaws.specified_header_child(value, context), include, same_include)
      Equal.trans(+List<InterfaceView.Node>,
        RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(rest, context)), context),
        RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_header(rest, context), context)),
        Nil{},
        Equal.trans(+List<InterfaceView.Node>,
          RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.header_step(value, include, RulePresentationOrderLaws.specified_header(rest, context)), context),
          RulePresentationOrderLaws.body_step(value, RulePresentationOrderLaws.specified_header_child(value, context), RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_header(rest, context), context)),
          RulePresentationOrderLaws.body_step(value, include, RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_header(rest, context), context)),
          {==}, classifier_step),
        tail_evidence)
    case False{}: tail_evidence

def specified_header_idempotent(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_header(values, context), context) == RulePresentationOrderLaws.specified_header(values, context) : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_idempotent(rest, context)
      specified_header_idempotent_step(value, rest, RulePresentationOrderLaws.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_body_idempotent(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_body(values, context), context) == RulePresentationOrderLaws.specified_body(values, context) : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_idempotent(rest, context)
      specified_body_idempotent_step(value, rest, RulePresentationOrderLaws.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_header_after_body(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_body(values, context), context) == Nil{} : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_header_after_body(rest, context)
      specified_header_after_body_step(value, rest, RulePresentationOrderLaws.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_body_after_header(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_header(values, context), context) == Nil{} : +List<InterfaceView.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = specified_body_after_header(rest, context)
      specified_body_after_header_step(value, rest, RulePresentationOrderLaws.specified_header_child(value, context), context, {==}, tail_evidence)

def specified_header_of_order(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_order(values, context), context) == RulePresentationOrderLaws.specified_header(values, context) : +List<InterfaceView.Node>}:
  +headers = RulePresentationOrderLaws.specified_header(values, context)
  +bodies = RulePresentationOrderLaws.specified_body(values, context)
  +split = specified_header_append(headers, bodies, context)
  +headers_repeat = specified_header_idempotent(values, context)
  +body_empty = specified_header_after_body(values, context)
  +filtered_headers = RulePresentationOrderLaws.specified_header(headers, context)
  +filtered_bodies = RulePresentationOrderLaws.specified_header(bodies, context)
  Equal.trans(+List<InterfaceView.Node>,
    RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_order(values, context), context),
    List.append(&2, InterfaceView.Node, filtered_headers, filtered_bodies),
    headers, split,
    Equal.trans(+List<InterfaceView.Node>,
      List.append(&2, InterfaceView.Node, filtered_headers, filtered_bodies),
      List.append(&2, InterfaceView.Node, headers, Nil{}),
      headers,
      Equal.trans(+List<InterfaceView.Node>,
        List.append(&2, InterfaceView.Node, filtered_headers, filtered_bodies),
        List.append(&2, InterfaceView.Node, headers, filtered_bodies),
        List.append(&2, InterfaceView.Node, headers, Nil{}),
        Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (head => List.append(&2, InterfaceView.Node, head, filtered_bodies)),
          filtered_headers, headers, headers_repeat),
        Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => List.append(&2, InterfaceView.Node, headers, tail)),
          filtered_bodies, Nil{}, body_empty)),
      Std.app_nil_r(InterfaceView.Node, headers)))

def specified_body_of_order(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_order(values, context), context) == RulePresentationOrderLaws.specified_body(values, context) : +List<InterfaceView.Node>}:
  +headers = RulePresentationOrderLaws.specified_header(values, context)
  +bodies = RulePresentationOrderLaws.specified_body(values, context)
  +split = specified_body_append(headers, bodies, context)
  +header_empty = specified_body_after_header(values, context)
  +bodies_repeat = specified_body_idempotent(values, context)
  Equal.trans(+List<InterfaceView.Node>,
    RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_order(values, context), context),
    List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_body(headers, context), RulePresentationOrderLaws.specified_body(bodies, context)),
    bodies, split,
    Equal.trans(+List<InterfaceView.Node>,
      List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_body(headers, context), RulePresentationOrderLaws.specified_body(bodies, context)),
      List.append(&2, InterfaceView.Node, Nil{}, bodies),
      bodies,
      Equal.trans(+List<InterfaceView.Node>,
        List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_body(headers, context), RulePresentationOrderLaws.specified_body(bodies, context)),
        List.append(&2, InterfaceView.Node, Nil{}, RulePresentationOrderLaws.specified_body(bodies, context)),
        List.append(&2, InterfaceView.Node, Nil{}, bodies),
        Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (head => List.append(&2, InterfaceView.Node, head, RulePresentationOrderLaws.specified_body(bodies, context))),
          RulePresentationOrderLaws.specified_body(headers, context), Nil{}, header_empty),
        Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => List.append(&2, InterfaceView.Node, Nil{}, tail)),
          RulePresentationOrderLaws.specified_body(bodies, context), bodies, bodies_repeat)),
      {==}))

def specified_order_idempotent(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {RulePresentationOrderLaws.specified_order(RulePresentationOrderLaws.specified_order(values, context), context) == RulePresentationOrderLaws.specified_order(values, context) : +List<InterfaceView.Node>}:
  +headers = RulePresentationOrderLaws.specified_header(values, context)
  +bodies = RulePresentationOrderLaws.specified_body(values, context)
  Equal.trans(+List<InterfaceView.Node>,
    RulePresentationOrderLaws.specified_order(RulePresentationOrderLaws.specified_order(values, context), context),
    List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_order(values, context), context),
      RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_order(values, context), context)),
    List.append(&2, InterfaceView.Node, headers, bodies),
    {==},
    Equal.trans(+List<InterfaceView.Node>,
      List.append(&2, InterfaceView.Node, RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_order(values, context), context),
        RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_order(values, context), context)),
      List.append(&2, InterfaceView.Node, headers, RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_order(values, context), context)),
      List.append(&2, InterfaceView.Node, headers, bodies),
      Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (head => List.append(&2, InterfaceView.Node, head,
        RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_order(values, context), context))),
        RulePresentationOrderLaws.specified_header(RulePresentationOrderLaws.specified_order(values, context), context), headers,
        specified_header_of_order(values, context)),
    Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>, (tail => List.append(&2, InterfaceView.Node, headers, tail)),
        RulePresentationOrderLaws.specified_body(RulePresentationOrderLaws.specified_order(values, context), context), bodies,
        specified_body_of_order(values, context))))

def dialog_order_idempotent(+values: +List<InterfaceView.Node>, +context: Controls.Context) ->
  {Order.ordered_children(InterfaceView.Dialog{}, Order.ordered_children(InterfaceView.Dialog{}, values, context), context) ==
    Order.ordered_children(InterfaceView.Dialog{}, values, context) : +List<InterfaceView.Node>}:
  +first_order = Order.ordered_children(InterfaceView.Dialog{}, values, context)
  +first_evidence = ordered_children_matches_specification(values, InterfaceView.Dialog{}, context)
  +second_evidence = ordered_children_matches_specification(first_order, InterfaceView.Dialog{}, context)
  +lifted_first = Equal.cong(+List<InterfaceView.Node>, +List<InterfaceView.Node>,
    (children => RulePresentationOrderLaws.specified_order(children, context)), first_order, RulePresentationOrderLaws.specified_order(values, context), first_evidence)
  Equal.trans(+List<InterfaceView.Node>,
    Order.ordered_children(InterfaceView.Dialog{}, first_order, context),
    RulePresentationOrderLaws.specified_order(first_order, context),
    Order.ordered_children(InterfaceView.Dialog{}, values, context),
    second_evidence,
    Equal.trans(+List<InterfaceView.Node>,
      RulePresentationOrderLaws.specified_order(first_order, context), RulePresentationOrderLaws.specified_order(RulePresentationOrderLaws.specified_order(values, context), context),
      Order.ordered_children(InterfaceView.Dialog{}, values, context),
      lifted_first,
      Equal.trans(+List<InterfaceView.Node>,
        RulePresentationOrderLaws.specified_order(RulePresentationOrderLaws.specified_order(values, context), context), RulePresentationOrderLaws.specified_order(values, context),
        Order.ordered_children(InterfaceView.Dialog{}, values, context),
        specified_order_idempotent(values, context),
        Equal.sym(+List<InterfaceView.Node>, Order.ordered_children(InterfaceView.Dialog{}, values, context),
          RulePresentationOrderLaws.specified_order(values, context), first_evidence))))

def node_with_children_preserves_payload(+value: InterfaceView.Node, +children: +List<InterfaceView.Node>) ->
  {RulePresentationOrderLaws.node_payload(Order.node_with_children(value, children)) == RulePresentationOrderLaws.node_payload(value) : RulePresentationOrderLaws.NodePayload}:
  match value:
    case InterfaceView.Node{key, semantic, label, role, meaning, original_children}: {==}

def ordered_surface_preserves_content_scope(surface: InterfaceView.Surface) ->
  {RulePresentationOrderLaws.surface_payload(Order.ordered_surface(surface)) == RulePresentationOrderLaws.surface_payload(surface) : RulePresentationOrderLaws.SurfacePayload}:
  match surface:
    case InterfaceView.Surface{content, base, overlays, active_scope}: {==}

def count_append_step(+predicate: RulePresentationOrderLaws.CountPredicate, +value: InterfaceView.Node, +rest: +List<InterfaceView.Node>,
  +right: +List<InterfaceView.Node>, included: Bool,
  tail_evidence: {RulePresentationOrderLaws.count_by(predicate, List.append(&2, InterfaceView.Node, rest, right)) ==
    Nat.add(RulePresentationOrderLaws.count_by(predicate, rest), RulePresentationOrderLaws.count_by(predicate, right)) : Nat}) ->
  {RulePresentationOrderLaws.occurrence_step(included, RulePresentationOrderLaws.count_by(predicate, List.append(&2, InterfaceView.Node, rest, right))) ==
    Nat.add(RulePresentationOrderLaws.occurrence_step(included, RulePresentationOrderLaws.count_by(predicate, rest)), RulePresentationOrderLaws.count_by(predicate, right)) : Nat}:
  match included:
    case True{}:
      Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
        RulePresentationOrderLaws.count_by(predicate, List.append(&2, InterfaceView.Node, rest, right)),
        Nat.add(RulePresentationOrderLaws.count_by(predicate, rest), RulePresentationOrderLaws.count_by(predicate, right)), tail_evidence)
    case False{}: tail_evidence

def count_append(+predicate: RulePresentationOrderLaws.CountPredicate, +left: +List<InterfaceView.Node>, +right: +List<InterfaceView.Node>) ->
  {RulePresentationOrderLaws.count_by(predicate, List.append(&2, InterfaceView.Node, left, right)) ==
    Nat.add(RulePresentationOrderLaws.count_by(predicate, left), RulePresentationOrderLaws.count_by(predicate, right)) : Nat}:
  match left:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_evidence = count_append(predicate, rest, right)
      count_append_step(predicate, value, rest, right, RulePresentationOrderLaws.count_matches(predicate, value), tail_evidence)

def body_count_step(included: Bool, prefix: Nat, suffix: Nat) ->
  {Nat.add(prefix, RulePresentationOrderLaws.occurrence_step(included, suffix)) ==
    RulePresentationOrderLaws.occurrence_step(included, Nat.add(prefix, suffix)) : Nat}:
  match included:
    case True{}: Alg.nat_add_succ(prefix, suffix)
    case False{}: {==}

def partition_count_step(+predicate: RulePresentationOrderLaws.CountPredicate, +value: InterfaceView.Node, +rest: +List<InterfaceView.Node>,
  include: Bool, tail_parts: Order.DialogParts, +context: Controls.Context,
  tail_evidence: {RulePresentationOrderLaws.count_by(predicate, Order.ordered_dialog_children(tail_parts)) ==
    RulePresentationOrderLaws.count_by(predicate, rest) : Nat}) ->
  {RulePresentationOrderLaws.count_by(predicate,
      Order.ordered_dialog_children(Order.partition_child(value, include, tail_parts))) ==
    RulePresentationOrderLaws.count_by(predicate, value <> rest) : Nat}:
  match include:
    case True{}:
      match tail_parts:
        case Order.DialogParts{+headers, +bodies}:
          Equal.cong(Nat, Nat, (count => RulePresentationOrderLaws.occurrence_step(RulePresentationOrderLaws.count_matches(predicate, value), count)),
            RulePresentationOrderLaws.count_by(predicate, Order.ordered_dialog_children(tail_parts)),
            RulePresentationOrderLaws.count_by(predicate, rest), tail_evidence)
    case False{}:
      match tail_parts:
        case Order.DialogParts{+headers, +bodies}:
          +join_evidence = count_append(predicate, headers, bodies)
          +tail_relation = Equal.trans(Nat,
            Nat.add(RulePresentationOrderLaws.count_by(predicate, headers), RulePresentationOrderLaws.count_by(predicate, bodies)),
            RulePresentationOrderLaws.count_by(predicate, List.append(&2, InterfaceView.Node, headers, bodies)),
            RulePresentationOrderLaws.count_by(predicate, rest),
            Equal.sym(Nat, RulePresentationOrderLaws.count_by(predicate, List.append(&2, InterfaceView.Node, headers, bodies)),
              Nat.add(RulePresentationOrderLaws.count_by(predicate, headers), RulePresentationOrderLaws.count_by(predicate, bodies)), join_evidence),
            tail_evidence)
          Equal.trans(Nat,
            RulePresentationOrderLaws.count_by(predicate, Order.ordered_dialog_children(Order.partition_child(value, False{}, tail_parts))),
            Nat.add(RulePresentationOrderLaws.count_by(predicate, headers), RulePresentationOrderLaws.occurrence_step(RulePresentationOrderLaws.count_matches(predicate, value), RulePresentationOrderLaws.count_by(predicate, bodies))),
            RulePresentationOrderLaws.occurrence_step(RulePresentationOrderLaws.count_matches(predicate, value), RulePresentationOrderLaws.count_by(predicate, rest)),
            Equal.trans(Nat,
              RulePresentationOrderLaws.count_by(predicate, Order.ordered_dialog_children(Order.partition_child(value, False{}, tail_parts))),
              Nat.add(RulePresentationOrderLaws.count_by(predicate, headers), RulePresentationOrderLaws.count_by(predicate, value <> bodies)),
              Nat.add(RulePresentationOrderLaws.count_by(predicate, headers), RulePresentationOrderLaws.occurrence_step(RulePresentationOrderLaws.count_matches(predicate, value), RulePresentationOrderLaws.count_by(predicate, bodies))),
              count_append(predicate, headers, value <> bodies),
              Equal.cong(Nat, Nat, (count => Nat.add(RulePresentationOrderLaws.count_by(predicate, headers), count)),
                RulePresentationOrderLaws.count_by(predicate, value <> bodies), RulePresentationOrderLaws.occurrence_step(RulePresentationOrderLaws.count_matches(predicate, value), RulePresentationOrderLaws.count_by(predicate, bodies)), {==})),
            Equal.trans(Nat,
              Nat.add(RulePresentationOrderLaws.count_by(predicate, headers), RulePresentationOrderLaws.occurrence_step(RulePresentationOrderLaws.count_matches(predicate, value), RulePresentationOrderLaws.count_by(predicate, bodies))),
              RulePresentationOrderLaws.occurrence_step(RulePresentationOrderLaws.count_matches(predicate, value), Nat.add(RulePresentationOrderLaws.count_by(predicate, headers), RulePresentationOrderLaws.count_by(predicate, bodies))),
              RulePresentationOrderLaws.occurrence_step(RulePresentationOrderLaws.count_matches(predicate, value), RulePresentationOrderLaws.count_by(predicate, rest)),
              body_count_step(RulePresentationOrderLaws.count_matches(predicate, value), RulePresentationOrderLaws.count_by(predicate, headers), RulePresentationOrderLaws.count_by(predicate, bodies)),
              Equal.cong(Nat, Nat, (count => RulePresentationOrderLaws.occurrence_step(RulePresentationOrderLaws.count_matches(predicate, value), count)),
                Nat.add(RulePresentationOrderLaws.count_by(predicate, headers), RulePresentationOrderLaws.count_by(predicate, bodies)), RulePresentationOrderLaws.count_by(predicate, rest), tail_relation)))

def partition_count_preserved(+predicate: RulePresentationOrderLaws.CountPredicate, +values: +List<InterfaceView.Node>,
  +context: Controls.Context) ->
  {RulePresentationOrderLaws.count_by(predicate, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))) ==
    RulePresentationOrderLaws.count_by(predicate, values) : Nat}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      +tail_parts = Order.partition_dialog_children(rest, context)
      +tail_evidence = partition_count_preserved(predicate, rest, context)
      partition_count_step(predicate, value, rest, Order.header_child(value, context), tail_parts,
        context, tail_evidence)

def count_all_is_length(values: +List<InterfaceView.Node>) ->
  {RulePresentationOrderLaws.count_by(RulePresentationOrderLaws.CountAll{}, values) == List.length(&2, InterfaceView.Node, values) : Nat}:
  match values:
    case Nil{}: {==}
    case Con{+value, rest}:
      Equal.cong(Nat, Nat, (count => Nat.add(1n, count)),
        RulePresentationOrderLaws.count_by(RulePresentationOrderLaws.CountAll{}, rest), List.length(&2, InterfaceView.Node, rest), count_all_is_length(rest))

def state_model_observes_ordered_surface_evidence(+model_state: Web.State) ->
  {Web.observed_surface(model_state) ==
        Order.ordered_surface(Web.surface(Web.application(model_state))) : InterfaceView.Surface}:
  Web.State{+application, +generation, +realization, +environment, +font} = model_state
  {==}

def RulePresentationOrderLaws.evidence():
  RulePresentationOrderLaws.Requirements{
    role => values => context => non_dialog_order(role, values, context),
    values => context => partition_matches_specification(values, context),
    +values => +context =>
      Equal.trans(Nat,
        List.length(&2, InterfaceView.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
        RulePresentationOrderLaws.count_by(RulePresentationOrderLaws.CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
        List.length(&2, InterfaceView.Node, values),
        Equal.sym(Nat,
          RulePresentationOrderLaws.count_by(RulePresentationOrderLaws.CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          List.length(&2, InterfaceView.Node, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          count_all_is_length(Order.ordered_dialog_children(Order.partition_dialog_children(values, context)))),
        Equal.trans(Nat,
          RulePresentationOrderLaws.count_by(RulePresentationOrderLaws.CountAll{}, Order.ordered_dialog_children(Order.partition_dialog_children(values, context))),
          RulePresentationOrderLaws.count_by(RulePresentationOrderLaws.CountAll{}, values), List.length(&2, InterfaceView.Node, values),
          partition_count_preserved(RulePresentationOrderLaws.CountAll{}, values, context), count_all_is_length(values))),
    +target => +values => +context => partition_count_preserved(RulePresentationOrderLaws.CountKey{RulePresentationOrderLaws.count_key(target)}, values, context),
    values => role => context => ordered_children_matches_specification(values, role, context),
    values => context => dialog_order_idempotent(values, context),
    value => children => node_with_children_preserves_payload(value, children),
    surface => ordered_surface_preserves_content_scope(surface),
    state_model_observes_ordered_surface_evidence}

def RulePresentationOrderLaws.base_classifier(key, role): {==}

def RulePresentationOrderLaws.navigation_role(key): {==}

def RulePresentationOrderLaws.navigation_precedence(key, role): {==}

def RulePresentationOrderLaws.remaining_region(key, role): {==}

def RulePresentationOrderLaws.main_precedence(key): {==}

def RulePresentationOrderLaws.footer_region(): {==}

def RulePresentationOrderLaws.other_region(): {==}

def RulePresentationOrderLaws.base_partition_navigation(node, navigation, footer, main, other): {==}

def RulePresentationOrderLaws.base_partition_footer(node, navigation, footer, main, other): {==}

def RulePresentationOrderLaws.base_partition_main(node, navigation, footer, main, other): {==}

def RulePresentationOrderLaws.base_partition_other(node, navigation, footer, main, other): {==}

def RulePresentationOrderLaws.base_partition_empty(): {==}

def RulePresentationOrderLaws.base_partition_step(key, semantic, label, role, meaning, children, rest): {==}

def RulePresentationOrderLaws.base_region_order(navigation, footer, main, other): {==}

def RulePresentationOrderLaws.ordered_base_partition(values): {==}

def RulePresentationOrderLaws.ordered_surface_base(content, base, overlays, scope): {==}

def RulePresentationOrderLaws.remaining_role_classification(key, role, belongs):
  match role:
    case InterfaceView.Navigation{}: {==}
    case InterfaceView.NavigationHeader{}: {==}
    case InterfaceView.Main{}: Logic.impossible({Order.base_region_role(key, InterfaceView.Main{}) == Order.footer_region(UIIdentity.same(key, UIIdentity.part(UIIdentity.place(""), "settings/open"))) : Order.BaseRegion}, belongs)
    case InterfaceView.Heading{}: {==}
    case InterfaceView.PrimaryButton{}: {==}
    case InterfaceView.DestructiveButton{}: {==}
    case InterfaceView.SelectedButton{}: {==}
    case InterfaceView.ComposerActions{}: {==}
    case InterfaceView.DialogActions{}: {==}
    case InterfaceView.Timeline{}: {==}
    case InterfaceView.Activity{}: {==}
    case InterfaceView.UserMessage{}: {==}
    case InterfaceView.AssistantMessage{}: {==}
    case InterfaceView.Composer{}: {==}
    case InterfaceView.Approval{}: {==}
    case InterfaceView.Toolbar{}: {==}
    case InterfaceView.CodeBlock{}: {==}
    case InterfaceView.ApprovalQueue{}: {==}
    case InterfaceView.Section{}: {==}
    case InterfaceView.Dialog{}: {==}
    case InterfaceView.Menu{}: {==}
    case InterfaceView.Details{}: {==}
    case InterfaceView.Card{}: {==}
    case InterfaceView.Button{}: {==}
    case InterfaceView.Field{}: {==}
    case InterfaceView.Content{}: {==}
    case InterfaceView.Alert{}: {==}

def projection_construction(input: Core.Input, availability: View.Availability, name: String, projection: Controls.ActionPresentation, placement: Controls.Placement, help: Controls.Help, feedback: Controls.Feedback) ->
  {Controls.presented_action(input, availability, name, projection, placement, help, feedback) == RuleProjectPresentationLaws.projected_action(input, availability, name, projection, placement, help, feedback) : Controls.Representation}:
  match projection:
    case Controls.ActionPresentation{face, behavior, geometry}: {==}

def name_geometry(+visual: Design.Style) -> RuleProjectPresentationLaws.name_geometry_law(visual):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border, width, radius, shadow} = chrome
  {==}

def chooser_draft_observation(+id: Nat, +fallback: Design.Style) -> RuleProjectPresentationLaws.chooser_draft_observation_law(id, fallback):
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = fallback
  {==}

def project_reference(+key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +children: +List<InterfaceView.Node>, +context: Controls.Context, +project: Nat, +selected: Bool, +expanded: Bool) -> RuleProjectPresentationLaws.project_reference_law(key, semantic, label, role, children, context, project, selected, expanded):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def task_reference(+key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +children: +List<InterfaceView.Node>, +context: Controls.Context, +task: Nat, +status: View.TaskStatus, +selected: Bool) -> RuleProjectPresentationLaws.task_reference_law(key, semantic, label, role, children, context, task, status, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def chooser_reference(+key: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +children: +List<InterfaceView.Node>, +context: Controls.Context, +selected: Maybe<&2, Nat>) -> RuleProjectPresentationLaws.chooser_reference_law(key, semantic, label, role, children, context, selected):
  Controls.Context{area, selection, code, appearance, access, open, layers, execution, family} = context
  {==}

def project_family_projection(+area: Controls.Area, +owner: UIIdentity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +project: Nat, +selected: Bool, +expanded: Bool, +children: +List<InterfaceView.Node>, +input: Core.Input, +name: String, +face: Controls.Face, +behavior: Controls.Behavior, +geometry: Controls.Geometry) ->
  {Controls.contextual_source_presentation(area, Controls.SourceFamily{InterfaceView.Node{owner, semantic, label, role, InterfaceView.ProjectGroup{project, selected, expanded}, children}}, input, name, face, behavior, geometry) ==
    Controls.project_presentation(Controls.project_control_matches(input, project), Controls.project_control_input(input), expanded, name, face, behavior, geometry) : Controls.ActionPresentation}:
  match area:
    case Controls.PageArea{}: {==}
    case Controls.NavigationArea{}: {==}
    case Controls.ComposerArea{}: {==}
    case Controls.ToolbarArea{}: {==}
    case Controls.CodeArea{}: {==}
    case Controls.ActivityArea{}: {==}
    case Controls.ApprovalArea{}: {==}
    case Controls.MenuArea{}: {==}
    case Controls.DialogArea{}: {==}
    case Controls.CollectionArea{}: {==}
    case Controls.CardArea{}: {==}
    case Controls.BoardViewArea{}: {==}
    case Controls.BoardLaneArea{}: {==}

def unscoped_projection(+area: Controls.Area, +input: Core.Input, +name: String, +face: Controls.Face, +behavior: Controls.Behavior, +geometry: Controls.Geometry) ->
  {Controls.contextual_source_presentation(area, Controls.Unscoped{}, input, name, face, behavior, geometry) == Controls.ActionPresentation{face, behavior, geometry} : Controls.ActionPresentation}:
  match area:
    case Controls.PageArea{}: {==}
    case Controls.NavigationArea{}: {==}
    case Controls.ComposerArea{}: {==}
    case Controls.ToolbarArea{}: {==}
    case Controls.CodeArea{}: {==}
    case Controls.ActivityArea{}: {==}
    case Controls.ApprovalArea{}: {==}
    case Controls.MenuArea{}: {==}
    case Controls.DialogArea{}: {==}
    case Controls.CollectionArea{}: {==}
    case Controls.CardArea{}: {==}
    case Controls.BoardViewArea{}: {==}
    case Controls.BoardLaneArea{}: {==}

def status_indicator_extent(+key: UIIdentity.Key, status: View.TaskStatus, visual: Design.Style) ->
  {RuleProjectPresentationLaws.status_extent(Authored.task_status_indicator(key, status, visual)) == (Model.ExactSize{16n}, (Model.ExactSize{16n}, Enclosure.Extent{16n, 16n})) : Model.AxisSize & (Model.AxisSize & Enclosure.Extent)}:
  Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  {==}

def RuleProjectPresentationLaws.evidence():
  RuleProjectPresentationLaws.Requirements{
    +project => {==},
    +project => {==},
    +project => {==},
    +project => +trigger => {==},
    +name => +expanded => +fallback => {==},
    project_family_projection,
    unscoped_projection,
    +area => +family => +input => +availability => +name => +face => +behavior => +geometry => +placement => +help => +feedback => projection_construction(input, availability, name, Controls.source_presentation(area, family, input, name, face, behavior, geometry), placement, help, feedback),
    +width => +height => +preferred => +icon => +radius => +leading => {==},
    +width => +height => +preferred => +icon => +radius => +leading => {==},
    +width => +height => +preferred => +icon => +radius => +leading => {==},
    name_geometry,
    {==},
    +trigger => +name => +face => +behavior => +geometry => {==},
    +name => +expanded => +fallback => {==},
    +name => +expanded => +fallback => {==},
    chooser_draft_observation,
    +typography => +key => +context => +representation => +fallback => +project => +selected => +expanded => {==},
    +typography => +key => +context => +representation => +fallback => +task => +status => +selected => {==},
    project_reference,
    task_reference,
    chooser_reference,
    +typography => +in_main => +start => +key => +semantic => +label => +role => +meaning => +children => +context => {==},
    +typography => +key => +owner => +owner_semantic => +owner_label => +owner_role => +owner_children => +project => +selected => +expanded => +area => +selection => +code => +appearance => +access => +open => +layers => +execution => +representation => +fallback => {==},
    {==},
    {==},
    working => {==},
    working => {==},
    working => {==},
    +key => +status => +visual => {==},
    status_indicator_extent,
    +key => role => meaning => nodes => +rest => +status => +visual => {==}}

def RuleRenderedRules.stale_frame_retains_state(current, received, surface, frame, previous, different):
  Equal.cong(Bool, Rendered.State, (owned => Rendered.receive(owned, current, surface, frame, previous)), Nat.is_eq(current, received), False{}, different)

def RuleRenderedRules.native_ownership_is_complete(identity, owner, rest, active, elements): {==}
def RuleRenderedRules.native_order_is_owned(owner, identity, parent, rest): {==}
def RuleRenderedRules.native_tab_contract(active, elements, native_focus, order): {==}

def RuleRenderedRules.absent_control_is_not_tab_stop(): {==}
def RuleRenderedRules.observed_tab_participation(key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds): {==}

def RuleRenderedRules.dialog_actions_persistent(): {==}
def RuleRenderedRules.dialog_actions_bounded(key, found, viewport): {==}

def RuleRenderedRules.disjoint_paint_controls_do_not_overlap(first, second, disjoint):
  match first second:
    case Rendered.Element{+key, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds} Rendered.Element{+other, v, e, t, k, s, other_bounds, h, +other_paint_bounds}:
      Equal.cong(Bool, +List<Rendered.Violation>,
        (overlapping => List.append(&2, Rendered.Violation,
          Rendered.issue(overlapping, Rendered.OverlappingControls{key, other}), Nil{})),
        Rendered.overlaps(paint_bounds, other_paint_bounds), False{}, disjoint)

def RuleRenderedRules.observed_visible_paint_is_bounded(bounds, paint_bounds, viewport): {==}
def RuleRenderedRules.observed_hidden_paint_is_inactive(bounds, paint_bounds, viewport): {==}


def RuleRenderedRules.observed_code_in_view(key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds,viewport): {==}
def RuleRenderedRules.unpainted_code_is_not_in_view(key,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds,viewport): {==}
def RuleRenderedRules.cropped_disjoint_code_is_not_in_view(key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds,viewport,disjoint):
  match visible:
    case False{}: {==}
    case True{}: disjoint

def RuleRenderedRules.movement_is_interactive(destinations, face): {==}
def RuleRenderedRules.movement_enabled_by_offered_input(destinations, face): {==}

def RuleSourceFrameRules.evidence():
  RuleSourceFrameRules.Requirements{
    +snapshot => +tree => +roots => +policies => {==},
    +key => +bounds => +interaction => +rest => +elements => +viewport => {==},
    +key => +bounds => +interaction => +rest => {==},
    +physical => +value => +interaction => +rule => +demand => +height => +bounds => +canvas => +rest => {==},
    +physical => +value => +interaction => +rule => +bounds => +canvas => +direction => +children => +rest => {==},
    +world => +viewport => +elements => +focused => +tab_order => +native_focus => {==},
    +left => +top => +width => +height => {==},
    +key => +bounds => +interaction => +viewport => +observed => +visible => +enabled => +tab => +keyboard => +scroll => +measured => +hit => +paint => {==},
    +focused => +entries => +elements => +viewport => {==},
    +key => +element => +viewport => {==}}

def instructions_same(empty: Bool, +value: String) -> {Authored.project_instructions(empty, value) == RuleTaskDetailsLaws.instructions_text_when(empty, value) : String}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def frozen_project(+owner: UIIdentity.Key, +label: String, +directory: String, +revision: String, +instructions: String, +visual: Design.Style) -> RuleTaskDetailsLaws.project_law(owner, label, directory, revision, instructions, visual):
  Equal.cong(String, +List<Source.Node>,
    supplied_text => [Authored.group(owner, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.text(UIIdentity.part(owner, "title"), label, visual, T.Body{}, T.Strong{}), Authored.fact(UIIdentity.part(owner, "directory"), "Directory", directory, visual), Authored.fact(UIIdentity.part(owner, "revision"), "Revision", revision, visual), Authored.fact(UIIdentity.part(owner, "instructions"), "Instructions", supplied_text, visual)])],
    Authored.project_instructions(String.eq(instructions, ""), instructions),
    RuleTaskDetailsLaws.instructions_text_when(String.eq(instructions, ""), instructions),
    instructions_same(String.eq(instructions, ""), instructions))

def RuleTaskDetailsLaws.evidence():
  RuleTaskDetailsLaws.Requirements{
    +owner => +label => +visual => {==},
    frozen_project,
    +owner => +visual => {==},
    +owner => +name => +description => +schema => +source => +rest => +visual => {==},
    {==},
    +ancestor => +rest => {==},
    +owner => +task => +roots => +primary => +mode => +network => +approval => +project => +guidance => +access => +id => +provider => +name => +policy => +options => +reasoning => +model_guidance => +tools => +lineage => +queued => +status => +phase => +visual => {==}}

def native_field_footprint(+kind: Source.NativeFieldKind, +style: Source.ResolvedStyle) -> RuleSourceRules.native_field_footprint(kind, style):
  match kind:
    case Source.ToggleField{}:
      Source.ResolvedStyle{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font,
        Design.Chrome{foreground, background, border, border_width, radius, shadow}, states} = style
      {==}
    case Source.TextField{}: {==}
    case Source.MessageField{}: {==}
    case Source.TextAreaField{}: {==}
    case Source.SelectField{}: {==}
    case Source.MultiSelectField{}: {==}
    case Source.NumberField{minimum}: {==}
    case Source.FileField{multiple}: {==}
    case Source.DirectoryField{}: {==}
    case Source.SearchField{}: {==}
    case Source.SecretField{}: {==}

def position_of_actual_rule(+style: Source.Style, parent: T.Presentation) -> RuleSourceRules.position_is_authored(style, parent):
  match style:
    case Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font,
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, states}:
      {==}

def border_of_actual_rule(+style: Source.Style, parent: T.Presentation) -> RuleSourceRules.border_is_chrome(style, parent):
  match style:
    case Source.Style{Source.Layout{direction, main_alignment, cross_alignment, frame, width, height, minimum, scroll, position}, font,
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, states}:
      {==}

def font_resolution(choice: Source.FontChoice, +parent: T.Presentation) -> RuleSourceRules.inherited_font(choice, parent):
  match choice:
    case Source.InheritFont{}: {==}
    case Source.ExplicitFont{presentation}: {==}

def event_ownership(+node: Source.Node) -> RuleSourceRules.operation_is_structurally_present(node):
  match node:
    case Source.Box{key, tag, style, attributes, children}: {==}
    case Source.Control{key, tag, style, attributes, accessible_name, enabled, first_event, remaining_events, children}: {==}
    case Source.Text{key, value, font, wrapping}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.Field{key, kind, style, attributes, value, placeholder, options, policy, accessible_name, enabled, first_event, remaining_events}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.NativeAttachment{key, target, attributes, style, children}: {==}

def bounded_policy_factory(columns_extra: Nat, +lines_extra: Nat, additional_lines: Nat) ->
  RuleSourceRules.field_policy_is_bounded(Source.field_policy(columns_extra, lines_extra, additional_lines)):
  %Equal.sym(Bool, Nat.is_le(0n, columns_extra), True{}, Arithmetic.zero_le(columns_extra)) :
    {_ && Nat.is_le(1n, 1n+lines_extra) && Nat.is_le(1n+lines_extra, Nat.add(1n+lines_extra, additional_lines)) == True{} : Bool}
  %Equal.sym(Bool, Nat.is_le(0n, lines_extra), True{}, Arithmetic.zero_le(lines_extra)) :
    {True{} && _ && Nat.is_le(1n+lines_extra, Nat.add(1n+lines_extra, additional_lines)) == True{} : Bool}
  %Equal.sym(Bool, Nat.is_le(1n+lines_extra, Nat.add(1n+lines_extra, additional_lines)), True{},
    Arithmetic.le_add(1n+lines_extra, additional_lines)) :
    {True{} && True{} && _ == True{} : Bool}
  {==}

def board_controls(visual: Design.Style, position: Composition.Position) -> RuleSourceRules.board_controls(visual, position): {==}
def board_stages(visual: Design.Style, position: Composition.Position) -> RuleSourceRules.board_stages(visual, position): {==}
def heading_caption(key: UIIdentity.Key, label: String, visual: Design.Style) -> RuleSourceRules.heading_caption(key, label, visual): {==}
def lane_style(key: UIIdentity.Key, label: String, stage: Board.Stage, count: Nat, visual: Design.Style, children: +List<Authored.Child>, parameters: Design.LayoutParameters) -> RuleSourceRules.lane_style(key, label, stage, count, visual, children, parameters): {==}
def parameter_source(+capacity: Nat, scale: T.Scale, key: String, minimum: Nat, preferred: Nat, height: Nat, advance: Nat) -> RuleSourceRules.parameter_source(capacity, scale, key, minimum, preferred, height, advance): {==}

def parameter_calculations(+capacity: Nat, +scale: T.Scale, height: Nat, +advance: Nat) -> RuleSourceRules.parameter_calculations(capacity, scale, height, advance): {==}

def page_region(key: UIIdentity.Key, region: Composition.Region, position: Composition.Position, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.page_region(key, region, position, visual, control, children, parameters, content): {==}

def board_group(key: UIIdentity.Key, label: String, grouping: InterfaceView.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.board_group(key, label, grouping, visual, control, children, parameters, content): {==}

def confined_content_minimum(width: Nat, height: Nat) -> RuleSourceRules.confined_content_minimum(width, height): {==}

def board_group_content_minimum(key: UIIdentity.Key, label: String, grouping: InterfaceView.BoardGrouping, visual: Design.Style, control: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>, width: Nat, height: Nat) -> RuleSourceRules.board_group_content_minimum(key, label, grouping, visual, control, children, parameters, content, width, height):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  {==}

def card_regions(+key: UIIdentity.Key, +face: View.CardFace, +visual: Design.Style, +children: +List<Authored.Child>, +representation: Controls.Representation, +parameters: Design.LayoutParameters, +movable: Bool) -> RuleSourceRules.card_regions(key, face, visual, children, representation, parameters, movable):
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  {==}


def fact_display_choice(empty: Bool, +value: String) -> {Authored.fact_display_choice(empty, value) == RuleSourceRules.expected_fact_value(empty, value) : String}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def fact_display_value(+value: String) -> RuleSourceRules.fact_display_value(value):
  fact_display_choice(String.eq(value, ""), value)

def fact_content(+key: UIIdentity.Key, +label: String, +value: String, +visual: Design.Style) -> RuleSourceRules.fact_content(key, label, value, visual):
  Equal.cong(String, Source.Node,
    (displayed => Authored.group(key, visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, [Authored.text(UIIdentity.part(key, "label"), label, visual, T.Body{}, T.Strong{}), Authored.text(UIIdentity.part(key, "value"), displayed, visual, T.Body{}, T.Regular{})])),
    Authored.fact_display_value(value), RuleSourceRules.expected_fact_value(String.eq(value, ""), value), fact_display_value(value))

def fact_source_dispatch(key: UIIdentity.Key, label: String, role: InterfaceView.Role, value: String, visual: Design.Style, representation: Controls.Representation, children: +List<Authored.Child>, parameters: Design.LayoutParameters, content: +List<Source.Node>) -> RuleSourceRules.fact_source_dispatch(key, label, role, value, visual, representation, children, parameters, content): {==}


def user_width_choice(+full_width: Bool, +percent: Nat) -> {Factory.adaptive_width_cap(full_width, percent) == RuleSourceRules.adaptive_user_width_choice(full_width, percent) : Model.AxisSize}:
  match full_width:
    case True{}: {==}
    case False{}: {==}

def user_width_policy(+visual: Design.Style) -> {Factory.adaptive_natural_width(visual) == RuleSourceRules.adaptive_user_width(visual) : Model.AxisSize}:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, +percent, states} = visual
  user_width_choice(Nat.is_eq(percent, 100n), percent)

def user_message_width(+visual: Design.Style) -> RuleSourceRules.user_message_width(visual):
  Equal.cong(Model.AxisSize, Source.Style,
    width => Factory.style(visual, width, Model.NaturalSize{}, Model.Confined{}),
    Factory.adaptive_natural_width(visual), RuleSourceRules.adaptive_user_width(visual), user_width_policy(visual))

def RuleSourceRules.evidence():
  RuleSourceRules.Requirements{user_width_policy, user_message_width, fact_display_value, fact_content, fact_source_dispatch, native_field_footprint, card_regions, board_group_content_minimum, board_group, confined_content_minimum, page_region, parameter_calculations, board_controls, board_stages, heading_caption, lane_style, parameter_source, position_of_actual_rule, border_of_actual_rule, font_resolution, event_ownership, bounded_policy_factory}

def RuleSourceRules.movement_field_has_own_identity(key, destinations, face, name, handle, geometry, help, visual, parameters): {==}
def RuleSourceRules.movement_child_is_authored(key, role, destinations, face, control, nodes, rest): {==}

def RuleSourceRules.card_source_dispatch(key, label, role, face, visual, representation, children, parameters, content): {==}
def RuleSourceRules.movement_source_dispatch(key, label, role, destinations, face, visual, representation, children, parameters, content): {==}
