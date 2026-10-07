import Base
import ../rendered-rules.bend as Rule
import ../rendered.bend as Model

def Rule.stale_frame_retains_state(current, received, surface, frame, previous, different):
  Equal.cong(Bool, Model.State, (owned => Model.receive(owned, current, surface, frame, previous)), Nat.is_eq(current, received), False{}, different)

def Rule.native_ownership_is_complete(identity, owner, rest, active, elements): {==}
def Rule.native_order_is_owned(owner, identity, parent, rest): {==}
def Rule.native_tab_contract(active, elements, native_focus, order): {==}

def Rule.absent_control_is_not_tab_stop(): {==}
def Rule.observed_tab_participation(key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds): {==}

def Rule.dialog_actions_persistent(): {==}
def Rule.dialog_actions_bounded(key, found, viewport): {==}

def Rule.disjoint_paint_controls_do_not_overlap(first, second, disjoint):
  match first second:
    case Model.Element{+key, visible, enabled, tab, keyboard, scroll, bounds, hit, +paint_bounds} Model.Element{+other, v, e, t, k, s, other_bounds, h, +other_paint_bounds}:
      Equal.cong(Bool, +List<Model.Violation>,
        (overlapping => List.append(&2, Model.Violation,
          Model.issue(overlapping, Model.OverlappingControls{key, other}), Nil{})),
        Model.overlaps(paint_bounds, other_paint_bounds), False{}, disjoint)

def Rule.observed_visible_paint_is_bounded(bounds, paint_bounds, viewport): {==}
def Rule.observed_hidden_paint_is_inactive(bounds, paint_bounds, viewport): {==}


def Rule.observed_code_in_view(key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds,viewport): {==}
def Rule.unpainted_code_is_not_in_view(key,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds,viewport): {==}
def Rule.cropped_disjoint_code_is_not_in_view(key,visible,enabled,tab,keyboard,scroll,bounds,hit,paint_bounds,viewport,disjoint):
  match visible:
    case False{}: {==}
    case True{}: disjoint

def Rule.movement_is_interactive(destinations, face): {==}
def Rule.movement_enabled_by_offered_input(destinations, face): {==}
