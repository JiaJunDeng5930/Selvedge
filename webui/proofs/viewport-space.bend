import Base
import ../viewport-space.bend as P
import ../typography.bend as T
import ../space.bend as Space
import ../space-laws.bend as SpaceLaws
import ../design.bend as Design
import ../../core/user-experience.bend as E
import ../../core/ui-world.bend as V
import ../../bendlib/stdlib.bend as Std
import ../viewport-space-laws.bend as Rule
import ./space.bend as SpaceLawsProof

def bind_construction(+viewport: Design.Viewport, +value: Design.LayoutParameters,
  +navigation: V.NavigationPlacement, +details: Bool, +packing: Space.Packing<P.ShellPart>,
  binding: {P.shell_packing(viewport, value, navigation, details) == packing : Space.Packing<P.ShellPart>},
  proof: SpaceLaws.PackedClaim(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n,
    P.width(viewport), packing)) -> Rule.Construction(viewport, value, navigation, details, packing):
  match packing:
    case Space.Packed{placements, unused}:
      (Equal.cong(Space.Packing<P.ShellPart>, P.Result,
        (result => P.from_packing(viewport, value, navigation, result)),
        P.shell_packing(viewport, value, navigation, details), Space.Packed{placements, unused}, binding), proof)
    case Space.Insufficient{required, available}: Empty.absurd(Rule.Construction(viewport, value, navigation, details, Space.Insufficient{required, available}), proof)


def feasible_construction(+viewport: Design.Viewport, +value: Design.LayoutParameters,
  +navigation: V.NavigationPlacement, +details: Bool,
  +fits: {Nat.is_le(Space.minimum_sequence(~P.ShellPart,
      P.shell_slots(viewport, value, navigation, details), 0n), P.width(viewport)) == True{} : Bool}) ->
  Rule.Construction(viewport, value, navigation, details, P.shell_packing(viewport, value, navigation, details)):
  bind_construction(viewport, value, navigation, details,
    P.shell_packing(viewport, value, navigation, details), {==},
    SpaceLawsProof.pack_complete(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n, P.width(viewport), fits))


def packed_agrees(+result: Space.Packing<P.ShellPart>) ->
  {P.packed(result) == SpaceLaws.packed(~P.ShellPart, result) : Bool}:
  match result:
    case Space.Packed{placements, unused}: {==}
    case Space.Insufficient{required, available}: {==}


def feasibility(+viewport: Design.Viewport, +slots: +List<Space.Slot<P.ShellPart>>) ->
  {P.packed(Space.pack(~P.ShellPart, slots, 0n, P.width(viewport))) ==
    Nat.is_le(Space.minimum_sequence(~P.ShellPart, slots, 0n), P.width(viewport)) : Bool}:
  Equal.trans(Bool, P.packed(Space.pack(~P.ShellPart, slots, 0n, P.width(viewport))),
    SpaceLaws.packed(~P.ShellPart, Space.pack(~P.ShellPart, slots, 0n, P.width(viewport))),
    Nat.is_le(Space.minimum_sequence(~P.ShellPart, slots, 0n), P.width(viewport)),
    packed_agrees(Space.pack(~P.ShellPart, slots, 0n, P.width(viewport))),
    SpaceLawsProof.feasible_tag(~P.ShellPart, Nat.is_le(Space.minimum_sequence(~P.ShellPart, slots, 0n), P.width(viewport)), slots, 0n, P.width(viewport)))


def navigation_feasibility(+viewport: Design.Viewport, +value: Design.LayoutParameters, intent: E.NavigationIntent) ->
  {Rule.nav_capacity(P.capacity(viewport, value, intent)) ==
    Nat.is_le(Space.minimum_sequence(~P.ShellPart, P.navigation_slots(value), 0n), P.width(viewport)) : Bool}:
  feasibility(viewport, P.navigation_slots(value))


def details_feasibility(+viewport: Design.Viewport, +value: Design.LayoutParameters, +intent: E.NavigationIntent) ->
  {Rule.details_capacity(P.capacity(viewport, value, intent)) ==
    Nat.is_le(Space.minimum_sequence(~P.ShellPart,
      P.regular_slots(value, P.placement(viewport, value, intent), True{}), 0n), P.width(viewport)) : Bool}:
  feasibility(viewport, P.regular_slots(value, P.placement(viewport, value, intent), True{}))


def placement_ownership(+viewport: Design.Viewport, +value: Design.LayoutParameters, intent: E.NavigationIntent) ->
  {P.placement(viewport, value, intent) == V.navigation_placement(P.navigation_capacity(viewport, value),
      V.navigation_visible(intent, P.navigation_capacity(viewport, value))) : V.NavigationPlacement}:
  {==}


def closed_capacity(beside: Bool) ->
  {V.navigation_placement(beside, V.navigation_visible(E.ClosedNavigation{}, beside)) == V.CollapsedNavigation{} : V.NavigationPlacement}:
  match beside:
    case False{}: {==}
    case True{}: {==}


def closed_placement(+viewport: Design.Viewport, +value: Design.LayoutParameters) ->
  {P.placement(viewport, value, E.ClosedNavigation{}) == V.CollapsedNavigation{} : V.NavigationPlacement}:
  closed_capacity(P.navigation_capacity(viewport, value))


def no_sidebar_reservation(+value: Design.LayoutParameters) ->
  {P.regular_slots(value, V.ModalNavigation{}, True{}) ==
    P.regular_slots(value, V.CollapsedNavigation{}, True{}) : +List<Space.Slot<P.ShellPart>>}:
  {==}


def closed_details_budget(+viewport: Design.Viewport, +value: Design.LayoutParameters) ->
  {Rule.details_capacity(P.capacity(viewport, value, E.ClosedNavigation{})) ==
      P.packed(Space.pack(~P.ShellPart, P.regular_slots(value, V.CollapsedNavigation{}, True{}), 0n, P.width(viewport))) : Bool}:
  Equal.cong(V.NavigationPlacement, Bool,
    (navigation => P.packed(Space.pack(~P.ShellPart, P.regular_slots(value, navigation, True{}), 0n, P.width(viewport)))),
    P.placement(viewport, value, E.ClosedNavigation{}), V.CollapsedNavigation{}, closed_placement(viewport, value))


def unsupported_exact(+viewport: Design.Viewport, +value: Design.LayoutParameters,
  +navigation: V.NavigationPlacement, +details: Bool,
  does_not_fit: {Nat.is_le(Space.minimum_sequence(~P.ShellPart,
      P.shell_slots(viewport, value, navigation, details), 0n), P.width(viewport)) == False{} : Bool}) ->
  {P.shell(viewport, value, navigation, details) ==
      P.Unsupported{Space.minimum_sequence(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n), P.width(viewport)} : P.Result}:
  Equal.cong(Space.Packing<P.ShellPart>, P.Result,
    (result => P.from_packing(viewport, value, navigation, result)),
    P.shell_packing(viewport, value, navigation, details),
    Space.Insufficient{Space.minimum_sequence(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n), P.width(viewport)},
    SpaceLawsProof.pack_insufficient(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n, P.width(viewport), does_not_fit))


def reading_equation(+scale: T.Scale, metric: T.Metric) ->
  {Design.reading_maximum_width(P.parameters(scale, metric)) == T.reading_width(Rule.metric_advance(metric), 96n) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}


def overview_equation(+scale: T.Scale, metric: T.Metric) ->
  {Design.overview_maximum_width(P.parameters(scale, metric)) == T.reading_width(Rule.metric_advance(metric), 144n) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}


def main_equation(+scale: T.Scale, metric: T.Metric) ->
  {Design.main_minimum_width(P.parameters(scale, metric)) ==
    Nat.add(T.reading_width(Rule.metric_advance(metric), 64n), Nat.mul(2n, T.scaled(16n, scale))) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}


def leading_equation(+scale: T.Scale, metric: T.Metric) ->
  {Design.input_line_height(P.parameters(scale, metric)) == Nat.max(T.resolved_line_height(T.resolve(T.Body{}, T.Regular{}, scale)), Rule.metric_height(metric)) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}


def positive_reading(+scale: T.Scale, +metric: T.Metric,
  positive: {Nat.is_gt(Rule.metric_advance(metric), 0n) == True{} : Bool}) ->
  {Nat.is_gt(Design.reading_maximum_width(P.parameters(scale, metric)), 0n) == True{} : Bool}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  match advance:
    case 0n: SpaceLawsProof.impossible({Nat.is_gt(Design.reading_maximum_width(P.parameters(scale, T.Metric{key, minimum, preferred, height, 0n})), 0n) == True{} : Bool}, positive)
    case 1n+rest: {==}


def installed_main(+shell: Design.Shell, +offset: Nat, +extent: Nat, +height: Nat) ->
  {Rule.main_projection(P.install(P.MainPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Design.Box{offset, 0n, extent, height} : Design.Box}:
  Design.Shell{navigation, main, details} = shell
  {==}

# The three projections show that placement conversion preserves coordinates;
# the allocation evidence above supplies ordered/disjoint intervals and budget.

def installed_navigation(+shell: Design.Shell, +offset: Nat, +extent: Nat, +height: Nat) ->
  {Rule.navigation_projection(P.install(P.NavigationPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Design.BesideNavigation{Design.Box{offset, 0n, extent, height}} : Design.Navigation}:
  Design.Shell{navigation, main, details} = shell
  {==}


def installed_details(+shell: Design.Shell, +offset: Nat, +extent: Nat, +height: Nat) ->
  {Rule.details_projection(P.install(P.DetailsPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Some{Design.Box{offset, 0n, extent, height}} : Maybe<&2, Design.Box>}:
  Design.Shell{navigation, main, details} = shell
  {==}


def toolbar_equation(+scale: T.Scale, metric: T.Metric) ->
  {Design.toolbar_height(P.parameters(scale, metric)) == Nat.max(T.scaled(46n, scale), Nat.add(Design.input_line_height(P.parameters(scale, metric)), T.scaled(26n, scale))) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}


def input_minimum_equation(+scale: T.Scale, metric: T.Metric) ->
  {Design.input_minimum_height(P.parameters(scale, metric)) == Nat.max(T.scaled(44n, scale), Nat.add(Design.input_line_height(P.parameters(scale, metric)), Nat.mul(2n, T.scaled(12n, scale)))) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}


def input_maximum_equation(+scale: T.Scale, metric: T.Metric) ->
  {Design.input_maximum_height(P.parameters(scale, metric)) == Nat.max(T.scaled(240n, scale), Design.input_minimum_height(P.parameters(scale, metric))) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}


def valid_input_bounds(+scale: T.Scale, +metric: T.Metric,
  valid: {T.valid_body(metric) == True{} : Bool}) ->
  {Nat.is_le(Design.input_minimum_height(P.parameters(scale, metric)), Design.input_maximum_height(P.parameters(scale, metric))) == True{} : Bool}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  +lower = Design.input_minimum_height(P.parameters(scale, T.Metric{key, minimum, preferred, height, advance}))
  +maximum = Nat.max(T.scaled(240n, scale), lower)
  Equal.trans(Bool, Nat.is_le(lower, maximum), Nat.is_ge(maximum, lower), True{},
    Equal.sym(Bool, Nat.is_ge(maximum, lower), Nat.is_le(lower, maximum), SpaceLawsProof.ge_le(maximum, lower)),
    Nat.max_ge_r(T.scaled(240n, scale), lower))


def balanced_equation(+scale: T.Scale, metric: T.Metric) ->
  {Design.creation_balanced_minimum_height(P.parameters(scale, metric)) == Nat.add(Design.toolbar_height(P.parameters(scale, metric)),
    Nat.mul(2n, Nat.add(T.resolved_line_height(T.resolve(T.Display{}, T.Regular{}, scale)),
      Nat.add(Design.input_minimum_height(P.parameters(scale, metric)), Nat.add(T.scaled(32n, scale), Nat.mul(3n, T.scaled(16n, scale))))))) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}


def compact_slots(+viewport: Design.Viewport, +value: Design.LayoutParameters, +navigation: V.NavigationPlacement,
  +details: Bool, compact: {P.compact_main(navigation, details, P.width(viewport), Design.main_minimum_width(value)) == True{} : Bool}) ->
  {P.shell_slots(viewport, value, navigation, details) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}:
  match navigation details:
    case V.LeadingNavigation{} False{}:
      SpaceLawsProof.impossible({P.shell_slots(viewport, value, V.LeadingNavigation{}, False{}) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}, compact)
    case V.LeadingNavigation{} True{}:
      SpaceLawsProof.impossible({P.shell_slots(viewport, value, V.LeadingNavigation{}, True{}) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}, compact)
    case V.ModalNavigation{} True{}:
      SpaceLawsProof.impossible({P.shell_slots(viewport, value, V.ModalNavigation{}, True{}) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}, compact)
    case V.CollapsedNavigation{} True{}:
      SpaceLawsProof.impossible({P.shell_slots(viewport, value, V.CollapsedNavigation{}, True{}) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}, compact)
    case V.ModalNavigation{} False{}:
      Std.transport(Bool, True{}, (chosen => {P.include_navigation(V.ModalNavigation{}, value, P.main_slot(P.actual_main_minimum(chosen, Design.main_minimum_width(value))) <> P.include_details(False{}, value)) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}),
        {==}, P.compact_main(V.ModalNavigation{}, False{}, P.width(viewport), Design.main_minimum_width(value)), compact)
    case V.CollapsedNavigation{} False{}:
      Std.transport(Bool, True{}, (chosen => {P.include_navigation(V.CollapsedNavigation{}, value, P.main_slot(P.actual_main_minimum(chosen, Design.main_minimum_width(value))) <> P.include_details(False{}, value)) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}),
        {==}, P.compact_main(V.CollapsedNavigation{}, False{}, P.width(viewport), Design.main_minimum_width(value)), compact)


def compact_pack_width(+viewport: Design.Viewport, +value: Design.LayoutParameters, +navigation: V.NavigationPlacement) ->
  {Rule.allocated_main_width(P.from_packing(viewport, value, navigation,
      Space.pack(~P.ShellPart, [P.main_slot(0n)], 0n, P.width(viewport)))) == Some{P.width(viewport)} : Maybe<&2, Nat>}:
  Design.Viewport{width, height} = viewport
  match width:
    case 0n: {==}
    case 1n+rest: {==}


def compact_width(+viewport: Design.Viewport, +value: Design.LayoutParameters, +navigation: V.NavigationPlacement,
  +details: Bool, compact: {P.compact_main(navigation, details, P.width(viewport), Design.main_minimum_width(value)) == True{} : Bool}) ->
  {Rule.allocated_main_width(P.shell(viewport, value, navigation, details)) == Some{P.width(viewport)} : Maybe<&2, Nat>}:
  Equal.trans(Maybe<&2, Nat>, Rule.allocated_main_width(P.shell(viewport, value, navigation, details)),
    Rule.allocated_main_width(P.from_packing(viewport, value, navigation, Space.pack(~P.ShellPart, [P.main_slot(0n)], 0n, P.width(viewport)))),
    Some{P.width(viewport)},
    Equal.cong(+List<Space.Slot<P.ShellPart>>, Maybe<&2, Nat>,
      (slots => Rule.allocated_main_width(P.from_packing(viewport, value, navigation, Space.pack(~P.ShellPart, slots, 0n, P.width(viewport))))),
      P.shell_slots(viewport, value, navigation, details), [P.main_slot(0n)], compact_slots(viewport, value, navigation, details, compact)),
    compact_pack_width(viewport, value, navigation))


def conjunction_right(+first: Bool, +second: Bool,
  proof: {first && second == True{} : Bool}) -> {second == True{} : Bool}:
  match first:
    case False{}: SpaceLawsProof.impossible({second == True{} : Bool}, proof)
    case True{}: proof


def valid_advance(+metric: T.Metric, valid: {T.valid_body(metric) == True{} : Bool}) ->
  {Nat.is_gt(Rule.metric_advance(metric), 0n) == True{} : Bool}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  conjunction_right(Nat.is_gt(height, 0n), Nat.is_gt(advance, 0n),
    conjunction_right(Nat.is_le(minimum, preferred), Nat.is_gt(height, 0n) && Nat.is_gt(advance, 0n),
      conjunction_right(String.eq("@font/body", key), Nat.is_le(minimum, preferred) &&
        (Nat.is_gt(height, 0n) && Nat.is_gt(advance, 0n)), valid)))


def valid_reading(+scale: T.Scale, +metric: T.Metric, valid: {T.valid_body(metric) == True{} : Bool}) ->
  {Nat.is_gt(Design.reading_maximum_width(P.parameters(scale, metric)), 0n) == True{} : Bool}:
  positive_reading(scale, metric, valid_advance(metric, valid))


def navigation_equation(+scale: T.Scale, metric: T.Metric) ->
  {Design.navigation_width(P.parameters(scale, metric)) == T.scaled(275n, scale) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}


def details_equation(+scale: T.Scale, metric: T.Metric) ->
  {Design.details_width(P.parameters(scale, metric)) == T.scaled(360n, scale) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}


def Rule.evidence():
  Rule.Requirements{SpaceLaws.evidence(~P.ShellPart), navigation_equation, details_equation, navigation_feasibility, details_feasibility,
    feasible_construction, reading_equation, positive_reading, placement_ownership, closed_placement, no_sidebar_reservation, closed_details_budget, unsupported_exact, main_equation, overview_equation, leading_equation, toolbar_equation, input_minimum_equation, input_maximum_equation, valid_input_bounds, balanced_equation, installed_main, installed_navigation, installed_details, compact_width, valid_reading}
