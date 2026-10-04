import Base
import ../../core/interface.bend as UI
import ../interaction.bend as Geometry
import ../render-contract.bend as Spec
import ../rendered.bend as Rendered
import ../../bendlib/stdlib.bend as Std

import ../render-laws.bend as Rule

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
    case Some{Rendered.Element{observed_key, +visible, +enabled, tab, +keyboard, +scroll, +bounds, +hit}}:
      Equal.trans(Bool,
        Rule.clear(Rendered.control_geometry(required, key,
          Some{Rendered.Element{observed_key, visible, enabled, tab, keyboard, scroll, bounds, hit}},
          must_be_visible, viewport)),
        Rule.clear(Rendered.issue(Bool.not((required && enabled) || (Bool.not(required) && Bool.not(enabled))), Rendered.DisabledAppearance{key})) &&
          Rule.clear(Rendered.enabled_geometry(required, key, visible, keyboard, scroll, bounds, hit, must_be_visible, viewport)),
        Spec.control_geometry_valid(required, key,
          Some{Rendered.Element{observed_key, visible, enabled, tab, keyboard, scroll, bounds, hit}},
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
            Some{Rendered.Element{observed_key, visible, enabled, tab, keyboard, scroll, bounds, hit}},
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

def clear_node_controls(is_control: Bool, meaning: UI.Meaning, key: String,
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
    case Some{Rendered.Element{observed_key, +visible, enabled, tab, keyboard, scroll, +bounds, hit}}:
      clear_issue_positive(visible && Geometry.contains(viewport, bounds), Rendered.EscapedDialog{key})

def clear_reachable_toolbar(key: String, found: Maybe<&2, Rendered.Element>) ->
  {Rule.clear(Rendered.reachable_toolbar(key, found)) == Spec.reachable_toolbar(found) : Bool}:
  match found:
    case None{}: {==}
    case Some{Rendered.Element{observed_key, +visible, enabled, tab, keyboard, +scroll, bounds, hit}}:
      clear_issue_positive(visible || scroll, Rendered.EscapedDialog{key})

def clear_region_geometry(role: UI.Role, key: String, found: Maybe<&2, Rendered.Element>, viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.region_geometry(role, key, found, viewport)) == Spec.region_geometry_valid(role, found, viewport) : Bool}:
  match role:
    case UI.Navigation{}: clear_bounded_dialog(key, found, viewport)
    case UI.NavigationHeader{}: clear_bounded_dialog(key, found, viewport)
    case UI.Main{}: clear_bounded_dialog(key, found, viewport)
    case UI.Heading{}: {==}
    case UI.Timeline{}: {==}
    case UI.Activity{}: {==}
    case UI.Composer{}: clear_bounded_dialog(key, found, viewport)
    case UI.Approval{}: {==}
    case UI.Toolbar{}: clear_reachable_toolbar(key, found)
    case UI.CodeBlock{}: {==}
    case UI.ApprovalQueue{}: clear_bounded_dialog(key, found, viewport)
    case UI.Section{}: {==}
    case UI.Dialog{}: clear_bounded_dialog(key, found, viewport)
    case UI.Menu{}: clear_bounded_dialog(key, found, viewport)
    case UI.Details{}: {==}
    case UI.Card{}: {==}
    case UI.Button{}: {==}
    case UI.PrimaryButton{}: {==}
    case UI.DestructiveButton{}: {==}
    case UI.SelectedButton{}: {==}
    case UI.Field{}: {==}
    case UI.Content{}: {==}
    case UI.Alert{}: {==}
    case UI.UserMessage{}: {==}
    case UI.AssistantMessage{}: {==}
    case UI.ComposerActions{}: {==}

def clear_node_geometry(found: Maybe<&2, Rendered.Element>, +meaning: UI.Meaning,
  +role: UI.Role, +key: String, +must_be_visible: Bool, +viewport: Geometry.Rect) ->
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

def clear_nodes(entries: +List<UI.Node>, +inherited: Bool,
  +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.nodes(entries, inherited, elements, viewport)) == Spec.all_nodes(entries, inherited, elements, viewport) : Bool}:
  match entries:
    case Nil{}: {==}
    case Con{UI.Node{+key, semantic, label, +role, +meaning, +children}, +rest}:
      +parent_required = inherited || Rendered.persistent(role)
      +child_required = parent_required || Rendered.code_in_view(role, Rendered.find_element(elements, key), viewport)
      +head_faults = Rendered.node_geometry(Rendered.find_element(elements, key), meaning, role, key, parent_required, viewport)
      +child_faults = Rendered.nodes(children, child_required, elements, viewport)
      +rest_faults = Rendered.nodes(rest, inherited, elements, viewport)
      +tail_faults = List.append(&2, Rendered.Violation, child_faults, rest_faults)
      +head_clear = Rule.clear(head_faults)
      +children_clear = Rule.clear(child_faults)
      +rest_clear = Rule.clear(rest_faults)
      +actual_tail = children_clear && rest_clear
      +actual_all = head_clear && actual_tail
      +head_spec = Spec.node_valid(UI.Node{key, semantic, label, role, meaning, children}, inherited, elements, viewport)
      +children_spec = Spec.all_nodes(children, child_required, elements, viewport)
      +rest_spec = Spec.all_nodes(rest, inherited, elements, viewport)
      +spec_tail = children_spec && rest_spec
      +after_head = head_spec && actual_tail
      +after_children = head_spec && (children_spec && rest_clear)
      +expected_all = head_spec && spec_tail
      +list_expansion = Equal.trans(Bool,
        Rule.clear(Rendered.nodes(Con{UI.Node{key, semantic, label, role, meaning, children}, rest}, inherited, elements, viewport)),
        head_clear && Rule.clear(tail_faults),
        actual_all,
        clear_append(head_faults, tail_faults),
        Equal.cong(Bool, Bool, (tail_clear => head_clear && tail_clear),
          Rule.clear(tail_faults), actual_tail,
          clear_append(child_faults, rest_faults)))
      +head_step = Equal.cong(Bool, Bool, (head_clear_value => head_clear_value && actual_tail),
        head_clear, head_spec,
        clear_node_geometry(Rendered.find_element(elements, key), meaning, role, key, parent_required, viewport))
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
        Rule.clear(Rendered.nodes(Con{UI.Node{key, semantic, label, role, meaning, children}, rest}, inherited, elements, viewport)),
        actual_all, expected_all, list_expansion, semantic_steps)

def node_exists_matches(found: Maybe<&2, UI.Node>) ->
  {Rendered.exists(found) == Spec.node_exists(found) : Bool}:
  match found:
    case None{}: {==}
    case Some{node}: {==}

def clear_focus_checks(focused: Maybe<&2, String>, +active: +List<UI.Node>,
  +elements: +List<Rendered.Element>, +viewport: Geometry.Rect) ->
  {Rule.clear(Rendered.focus_checks(focused, active, elements, viewport)) == Spec.focus(focused, active, elements, viewport) : Bool}:
  match focused:
    case None{}: {==}
    case Some{+key}:
      Equal.trans(Bool,
        Rule.clear(Rendered.focus_checks(Some{key}, active, elements, viewport)),
        Rule.clear(Rendered.issue(Bool.not(Rendered.focus_visible(Rendered.find_element(elements, key), viewport)), Rendered.InvisibleFocus{})) &&
          Rule.clear(Rendered.issue(Bool.not(Rendered.exists(UI.find_node(active, key))), Rendered.FocusOutsideScope{})),
        Spec.focus(Some{key}, active, elements, viewport),
        clear_append(
          Rendered.issue(Bool.not(Rendered.focus_visible(Rendered.find_element(elements, key), viewport)), Rendered.InvisibleFocus{}),
          Rendered.issue(Bool.not(Rendered.exists(UI.find_node(active, key))), Rendered.FocusOutsideScope{})),
        Equal.trans(Bool,
          Rule.clear(Rendered.issue(Bool.not(Rendered.focus_visible(Rendered.find_element(elements, key), viewport)), Rendered.InvisibleFocus{})) &&
            Rule.clear(Rendered.issue(Bool.not(Rendered.exists(UI.find_node(active, key))), Rendered.FocusOutsideScope{})),
          Rendered.focus_visible(Rendered.find_element(elements, key), viewport) &&
            Rule.clear(Rendered.issue(Bool.not(Rendered.exists(UI.find_node(active, key))), Rendered.FocusOutsideScope{})),
          Rendered.focus_visible(Rendered.find_element(elements, key), viewport) &&
            Spec.node_exists(UI.find_node(active, key)),
          Equal.cong(Bool, Bool,
            (focus_clear => focus_clear && Rule.clear(Rendered.issue(Bool.not(Rendered.exists(UI.find_node(active, key))), Rendered.FocusOutsideScope{}))),
            Rule.clear(Rendered.issue(Bool.not(Rendered.focus_visible(Rendered.find_element(elements, key), viewport)), Rendered.InvisibleFocus{})),
            Rendered.focus_visible(Rendered.find_element(elements, key), viewport),
            clear_issue_positive(Rendered.focus_visible(Rendered.find_element(elements, key), viewport), Rendered.InvisibleFocus{})),
          Equal.cong(Bool, Bool,
            (scope_clear => Rendered.focus_visible(Rendered.find_element(elements, key), viewport) && scope_clear),
            Rule.clear(Rendered.issue(Bool.not(Rendered.exists(UI.find_node(active, key))), Rendered.FocusOutsideScope{})),
            Spec.node_exists(UI.find_node(active, key)),
            Equal.trans(Bool,
              Rule.clear(Rendered.issue(Bool.not(Rendered.exists(UI.find_node(active, key))), Rendered.FocusOutsideScope{})),
              Rendered.exists(UI.find_node(active, key)),
              Spec.node_exists(UI.find_node(active, key)),
              clear_issue_positive(Rendered.exists(UI.find_node(active, key)), Rendered.FocusOutsideScope{}),
              node_exists_matches(UI.find_node(active, key))))))

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
  Rendered.Element{key, visible, enabled, tab, keyboard, scroll, +bounds, hit} = first
  match rest:
    case Nil{}: {==}
    case Con{Rendered.Element{+other, v, e, t, k, s, +other_bounds, h}, +tail}:
      Equal.trans(Bool,
        Rule.clear(Rendered.against(first, rest)),
        Rule.clear(Rendered.issue(Rendered.overlaps(bounds, other_bounds), Rendered.OverlappingControls{key, other})) &&
          Rule.clear(Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail)),
        Spec.disjoint_from(first, rest),
        clear_append(
          Rendered.issue(Rendered.overlaps(bounds, other_bounds), Rendered.OverlappingControls{key, other}),
          Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail)),
        Equal.trans(Bool,
          Rule.clear(Rendered.issue(Rendered.overlaps(bounds, other_bounds), Rendered.OverlappingControls{key, other})) &&
            Rule.clear(Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail)),
          Bool.not(Rendered.overlaps(bounds, other_bounds)) &&
            Rule.clear(Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail)),
          Bool.not(Rendered.overlaps(bounds, other_bounds)) &&
            Spec.disjoint_from(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail),
          Equal.cong(Bool, Bool,
            (head_clear => head_clear && Rule.clear(Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail))),
            Rule.clear(Rendered.issue(Rendered.overlaps(bounds, other_bounds), Rendered.OverlappingControls{key, other})),
            Bool.not(Rendered.overlaps(bounds, other_bounds)),
            clear_issue(Rendered.overlaps(bounds, other_bounds), Rendered.OverlappingControls{key, other})),
          Equal.cong(Bool, Bool,
            (tail_clear => Bool.not(Rendered.overlaps(bounds, other_bounds)) && tail_clear),
            Rule.clear(Rendered.against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail)),
            Spec.disjoint_from(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail),
            clear_against(Rendered.Element{key, visible, enabled, tab, keyboard, scroll, bounds, hit}, tail))))

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

def clear_check(+active: +List<UI.Node>, +frame: Rendered.Frame) ->
  {Rule.clear(Rendered.check(active, frame)) == Spec.valid_parts(active, frame) : Bool}:
  Rendered.Frame{+viewport, +elements, +focused, +tab_order} = frame
  +node_faults = Rendered.nodes(active, False{}, elements, viewport)
  +focus_faults = Rendered.focus_checks(focused, active, elements, viewport)
  +tab_faults = Rendered.issue(Bool.not(Rendered.same_order(Rendered.expected_tabs(active, elements), tab_order)), Rendered.WrongTabOrder{})
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
    (Spec.focus(focused, active, elements, viewport) && middle_clear)
  +after_tabs = Spec.all_nodes(active, False{}, elements, viewport) &&
    (Spec.focus(focused, active, elements, viewport) &&
      (Rendered.same_order(Rendered.expected_tabs(active, elements), tab_order) && targets_clear))
  +target = Spec.valid_parts(active, frame)
  +pair_clear = clear_append(tab_faults, target_faults)
  +focus_tail_clear = Equal.trans(Bool,
    Rule.clear(focus_and_tail_faults),
    focus_clear && Rule.clear(tab_and_target_faults),
    tail_clear,
    clear_append(focus_faults, tab_and_target_faults),
    Equal.cong(Bool, Bool, (tail_value => focus_clear && tail_value),
      Rule.clear(tab_and_target_faults), middle_clear, pair_clear))
  +body_clear = Equal.trans(Bool,
    Rule.clear(Rendered.check(active, frame)),
    nodes_clear && Rule.clear(focus_and_tail_faults),
    actual_clear,
    clear_append(node_faults, focus_and_tail_faults),
    Equal.cong(Bool, Bool, (tail_value => nodes_clear && tail_value),
      Rule.clear(focus_and_tail_faults), tail_clear, focus_tail_clear))
  +node_step = Equal.cong(Bool, Bool, (node_value => node_value && tail_clear),
    nodes_clear, Spec.all_nodes(active, False{}, elements, viewport),
    clear_nodes(active, False{}, elements, viewport))
  +focus_step = Equal.cong(Bool, Bool, (focus_value => Spec.all_nodes(active, False{}, elements, viewport) && (focus_value && middle_clear)),
    focus_clear, Spec.focus(focused, active, elements, viewport),
    clear_focus_checks(focused, active, elements, viewport))
  +tab_step = Equal.cong(Bool, Bool, (tab_value => tab_value && targets_clear),
    tab_clear, Rendered.same_order(Rendered.expected_tabs(active, elements), tab_order),
    clear_tab_order(Rendered.expected_tabs(active, elements), tab_order))
  +middle_step = Equal.cong(Bool, Bool,
    (middle_value => Spec.all_nodes(active, False{}, elements, viewport) &&
      (Spec.focus(focused, active, elements, viewport) && middle_value)),
    middle_clear, Rendered.same_order(Rendered.expected_tabs(active, elements), tab_order) && targets_clear,
    tab_step)
  +target_step = Equal.cong(Bool, Bool,
    (target_value => Spec.all_nodes(active, False{}, elements, viewport) &&
      (Spec.focus(focused, active, elements, viewport) &&
        (Rendered.same_order(Rendered.expected_tabs(active, elements), tab_order) && target_value))),
    targets_clear, Spec.non_overlapping(Rendered.actionable_elements(active, elements)),
    clear_independent_targets(Rendered.actionable_elements(active, elements)))
  +nodes_focus_step = Equal.trans(Bool, actual_clear, after_nodes, after_focus, node_step, focus_step)
  +semantic_step = Equal.trans(Bool, after_focus, after_tabs, target, middle_step, target_step)
  Equal.trans(Bool, Rule.clear(Rendered.check(active, frame)), actual_clear, target, body_clear,
    Equal.trans(Bool, actual_clear, after_focus, target, nodes_focus_step, semantic_step))

def reflected(+surface: UI.Surface, +frame: Rendered.Frame) ->
  {Rule.clear(Rendered.violations(surface, frame)) == Spec.valid(surface, frame) : Bool}:
  UI.Surface{content, base, overlays, +scope} = surface
  Rendered.Frame{viewport, elements, +focused, tab_order} = frame
  Equal.trans(Bool,
    Rule.clear(Rendered.violations(surface, frame)),
    Rule.clear(Rendered.check(UI.active_nodes(surface), frame)) && Rule.clear(Rendered.required_focus(scope, focused)),
    Spec.valid(surface, frame),
    clear_append(Rendered.check(UI.active_nodes(surface), frame), Rendered.required_focus(scope, focused)),
    Equal.trans(Bool,
      Rule.clear(Rendered.check(UI.active_nodes(surface), frame)) && Rule.clear(Rendered.required_focus(scope, focused)),
      Spec.valid_parts(UI.active_nodes(surface), frame) && Rule.clear(Rendered.required_focus(scope, focused)),
      Spec.valid(surface, frame),
      Equal.cong(Bool, Bool,
        (check_clear => check_clear && Rule.clear(Rendered.required_focus(scope, focused))),
        Rule.clear(Rendered.check(UI.active_nodes(surface), frame)),
        Spec.valid_parts(UI.active_nodes(surface), frame),
        clear_check(UI.active_nodes(surface), frame)),
      Equal.cong(Bool, Bool,
        (focus_clear => Spec.valid_parts(UI.active_nodes(surface), frame) && focus_clear),
        Rule.clear(Rendered.required_focus(scope, focused)),
        Spec.required_focus(scope, focused),
        clear_required_focus(scope, focused))))

def false_true_elim(P: Type, impossible: {False{} == True{} : Bool}) -> P:
  Std.transport(Bool, False{}, (value => Rule.bool_goal(P, value)), Unit{}, True{},
    Equal.sym(Bool, False{}, True{}, impossible))

def realized_faults_imply_valid(+faults: +List<Rendered.Violation>, +surface: UI.Surface,
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
      false_true_elim({Spec.valid(surface, frame) == True{} : Bool},
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
