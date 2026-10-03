import Base
import ./viewport-space.bend as P
import ./typography.bend as T
import ./space.bend as Space
import ./space-laws.bend as SpaceLaws
import ./design.bend as Design
import ../core/user-experience.bend as E
import ../core/ui-world.bend as V
import ../bendlib/stdlib.bend as Std

# The witness uses the same placements that construct each actual shell field.
# Space's bounds/order/budget evidence includes all siblings, not a final-box test.
def Construction(+viewport: Design.Viewport, +value: Design.LayoutParameters,
  +navigation: V.NavigationPlacement, +details: Bool, packing: Space.Packing<P.ShellPart>) -> Type:
  match packing:
    case Space.Packed{+placements, unused}:
      ({P.shell(viewport, value, navigation, details) ==
          P.Allocated{P.placed_shell(placements, P.height(viewport), P.empty_shell(viewport, value, navigation))} : P.Result} &
        SpaceLaws.AllocationEvidence<P.ShellPart, P.shell_slots(viewport, value, navigation, details),
          0n, 0n, P.width(viewport), Space.Allocation{placements, unused}>)
    case Space.Insufficient{required, available}: Empty

def bind_construction(+viewport: Design.Viewport, +value: Design.LayoutParameters,
  +navigation: V.NavigationPlacement, +details: Bool, +packing: Space.Packing<P.ShellPart>,
  binding: {P.shell_packing(viewport, value, navigation, details) == packing : Space.Packing<P.ShellPart>},
  proof: SpaceLaws.PackedClaim(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n,
    P.width(viewport), packing)) -> Construction(viewport, value, navigation, details, packing):
  match packing:
    case Space.Packed{placements, unused}:
      (Equal.cong(Space.Packing<P.ShellPart>, P.Result,
        (result => P.from_packing(viewport, value, navigation, result)),
        P.shell_packing(viewport, value, navigation, details), Space.Packed{placements, unused}, binding), proof)
    case Space.Insufficient{required, available}: Empty.absurd(Construction(viewport, value, navigation, details, Space.Insufficient{required, available}), proof)

def feasible_construction(+viewport: Design.Viewport, +value: Design.LayoutParameters,
  +navigation: V.NavigationPlacement, +details: Bool,
  +fits: {Nat.is_le(Space.minimum_sequence(~P.ShellPart,
      P.shell_slots(viewport, value, navigation, details), 0n), P.width(viewport)) == True{} : Bool}) ->
  Construction(viewport, value, navigation, details, P.shell_packing(viewport, value, navigation, details)):
  bind_construction(viewport, value, navigation, details,
    P.shell_packing(viewport, value, navigation, details), {==},
    SpaceLaws.pack_complete(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n, P.width(viewport), fits))

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
    SpaceLaws.feasible_tag(~P.ShellPart, Nat.is_le(Space.minimum_sequence(~P.ShellPart, slots, 0n), P.width(viewport)), slots, 0n, P.width(viewport)))

def nav_capacity(value: V.Capacity) -> Bool:
  V.Capacity{navigation, details} = value
  navigation

def details_capacity(value: V.Capacity) -> Bool:
  V.Capacity{navigation, details} = value
  details

def navigation_feasibility(+viewport: Design.Viewport, +value: Design.LayoutParameters, intent: E.NavigationIntent) ->
  {nav_capacity(P.capacity(viewport, value, intent)) ==
    Nat.is_le(Space.minimum_sequence(~P.ShellPart, P.navigation_slots(value), 0n), P.width(viewport)) : Bool}:
  feasibility(viewport, P.navigation_slots(value))

def details_feasibility(+viewport: Design.Viewport, +value: Design.LayoutParameters, +intent: E.NavigationIntent) ->
  {details_capacity(P.capacity(viewport, value, intent)) ==
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
  {details_capacity(P.capacity(viewport, value, E.ClosedNavigation{})) ==
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
    SpaceLaws.pack_insufficient(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n, P.width(viewport), does_not_fit))

def reading_measure(value: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  reading

def overview_measure(value: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  overview

def leading(value: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  leading

def metric_advance(metric: T.Metric) -> Nat:
  T.Metric{key, minimum, preferred, height, advance} = metric
  advance

def metric_height(metric: T.Metric) -> Nat:
  T.Metric{key, minimum, preferred, height, advance} = metric
  height

def reading_equation(+scale: T.Scale, metric: T.Metric) ->
  {reading_measure(P.parameters(scale, metric)) == T.reading_width(metric_advance(metric), 96n) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}

def overview_equation(+scale: T.Scale, metric: T.Metric) ->
  {overview_measure(P.parameters(scale, metric)) == T.reading_width(metric_advance(metric), 144n) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}

def main_equation(+scale: T.Scale, metric: T.Metric) ->
  {P.main_minimum_width(P.parameters(scale, metric)) ==
    Nat.add(T.reading_width(metric_advance(metric), 64n), Nat.mul(2n, T.scaled(16n, scale))) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}

def leading_equation(+scale: T.Scale, metric: T.Metric) ->
  {leading(P.parameters(scale, metric)) == Nat.max(P.line_height(T.resolve(T.Body{}, T.Regular{}, scale)), metric_height(metric)) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}

def positive_reading(+scale: T.Scale, +metric: T.Metric,
  positive: {Nat.is_gt(metric_advance(metric), 0n) == True{} : Bool}) ->
  {Nat.is_gt(reading_measure(P.parameters(scale, metric)), 0n) == True{} : Bool}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  match advance:
    case 0n: SpaceLaws.impossible({Nat.is_gt(reading_measure(P.parameters(scale, T.Metric{key, minimum, preferred, height, 0n})), 0n) == True{} : Bool}, positive)
    case 1n+rest: {==}

def main_projection(shell: Design.Shell) -> Design.Box:
  Design.Shell{navigation, main, details} = shell
  main

def installed_main(+shell: Design.Shell, +offset: Nat, +extent: Nat, +height: Nat) ->
  {main_projection(P.install(P.MainPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Design.Box{offset, 0n, extent, height} : Design.Box}:
  Design.Shell{navigation, main, details} = shell
  {==}

# The three projections show that placement conversion preserves coordinates;
# the allocation evidence above supplies ordered/disjoint intervals and budget.
def navigation_projection(shell: Design.Shell) -> Design.Navigation:
  Design.Shell{navigation, main, details} = shell
  navigation

def details_projection(shell: Design.Shell) -> Maybe<&2, Design.Box>:
  Design.Shell{navigation, main, details} = shell
  details

def installed_navigation(+shell: Design.Shell, +offset: Nat, +extent: Nat, +height: Nat) ->
  {navigation_projection(P.install(P.NavigationPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Design.BesideNavigation{Design.Box{offset, 0n, extent, height}} : Design.Navigation}:
  Design.Shell{navigation, main, details} = shell
  {==}

def installed_details(+shell: Design.Shell, +offset: Nat, +extent: Nat, +height: Nat) ->
  {details_projection(P.install(P.DetailsPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Some{Design.Box{offset, 0n, extent, height}} : Maybe<&2, Design.Box>}:
  Design.Shell{navigation, main, details} = shell
  {==}

def toolbar(value: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  toolbar

def input_minimum(value: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  minimum

def input_maximum(value: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  maximum

def balanced_minimum(value: Design.LayoutParameters) -> Nat:
  Design.LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  creation

def toolbar_equation(+scale: T.Scale, metric: T.Metric) ->
  {toolbar(P.parameters(scale, metric)) == Nat.max(T.scaled(46n, scale), Nat.add(leading(P.parameters(scale, metric)), T.scaled(26n, scale))) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}

def input_minimum_equation(+scale: T.Scale, metric: T.Metric) ->
  {input_minimum(P.parameters(scale, metric)) == Nat.max(T.scaled(44n, scale), Nat.add(leading(P.parameters(scale, metric)), Nat.mul(2n, T.scaled(12n, scale)))) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}

def input_maximum_equation(+scale: T.Scale, metric: T.Metric) ->
  {input_maximum(P.parameters(scale, metric)) == Nat.max(T.scaled(240n, scale), input_minimum(P.parameters(scale, metric))) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}

def valid_input_bounds(+scale: T.Scale, +metric: T.Metric,
  valid: {T.valid_body(metric) == True{} : Bool}) ->
  {Nat.is_le(input_minimum(P.parameters(scale, metric)), input_maximum(P.parameters(scale, metric))) == True{} : Bool}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  +lower = input_minimum(P.parameters(scale, T.Metric{key, minimum, preferred, height, advance}))
  +maximum = Nat.max(T.scaled(240n, scale), lower)
  Equal.trans(Bool, Nat.is_le(lower, maximum), Nat.is_ge(maximum, lower), True{},
    Equal.sym(Bool, Nat.is_ge(maximum, lower), Nat.is_le(lower, maximum), SpaceLaws.ge_le(maximum, lower)),
    Nat.max_ge_r(T.scaled(240n, scale), lower))

def balanced_equation(+scale: T.Scale, metric: T.Metric) ->
  {balanced_minimum(P.parameters(scale, metric)) == Nat.add(toolbar(P.parameters(scale, metric)),
    Nat.mul(2n, Nat.add(P.line_height(T.resolve(T.Display{}, T.Regular{}, scale)),
      Nat.add(input_minimum(P.parameters(scale, metric)), Nat.add(T.scaled(32n, scale), Nat.mul(3n, T.scaled(16n, scale))))))) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}

def compact_slots(+viewport: Design.Viewport, +value: Design.LayoutParameters, +navigation: V.NavigationPlacement,
  +details: Bool, compact: {P.compact_main(navigation, details, P.width(viewport), P.main_minimum_width(value)) == True{} : Bool}) ->
  {P.shell_slots(viewport, value, navigation, details) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}:
  match navigation details:
    case V.LeadingNavigation{} False{}:
      SpaceLaws.impossible({P.shell_slots(viewport, value, V.LeadingNavigation{}, False{}) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}, compact)
    case V.LeadingNavigation{} True{}:
      SpaceLaws.impossible({P.shell_slots(viewport, value, V.LeadingNavigation{}, True{}) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}, compact)
    case V.ModalNavigation{} True{}:
      SpaceLaws.impossible({P.shell_slots(viewport, value, V.ModalNavigation{}, True{}) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}, compact)
    case V.CollapsedNavigation{} True{}:
      SpaceLaws.impossible({P.shell_slots(viewport, value, V.CollapsedNavigation{}, True{}) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}, compact)
    case V.ModalNavigation{} False{}:
      Std.transport(Bool, True{}, (chosen => {P.include_navigation(V.ModalNavigation{}, value, P.main_slot(P.actual_main_minimum(chosen, P.main_minimum_width(value))) <> P.include_details(False{}, value)) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}),
        {==}, P.compact_main(V.ModalNavigation{}, False{}, P.width(viewport), P.main_minimum_width(value)), compact)
    case V.CollapsedNavigation{} False{}:
      Std.transport(Bool, True{}, (chosen => {P.include_navigation(V.CollapsedNavigation{}, value, P.main_slot(P.actual_main_minimum(chosen, P.main_minimum_width(value))) <> P.include_details(False{}, value)) == [P.main_slot(0n)] : +List<Space.Slot<P.ShellPart>>}),
        {==}, P.compact_main(V.CollapsedNavigation{}, False{}, P.width(viewport), P.main_minimum_width(value)), compact)

def allocated_main_width(result: P.Result) -> Maybe<&2, Nat>:
  match result:
    case P.Allocated{Design.Shell{navigation, Design.Box{left, top, width, height}, details}}: Some{width}
    case P.Unsupported{required, available}: None{}

def compact_pack_width(+viewport: Design.Viewport, +value: Design.LayoutParameters, +navigation: V.NavigationPlacement) ->
  {allocated_main_width(P.from_packing(viewport, value, navigation,
      Space.pack(~P.ShellPart, [P.main_slot(0n)], 0n, P.width(viewport)))) == Some{P.width(viewport)} : Maybe<&2, Nat>}:
  Design.Viewport{width, height} = viewport
  match width:
    case 0n: {==}
    case 1n+rest: {==}

def compact_width(+viewport: Design.Viewport, +value: Design.LayoutParameters, +navigation: V.NavigationPlacement,
  +details: Bool, compact: {P.compact_main(navigation, details, P.width(viewport), P.main_minimum_width(value)) == True{} : Bool}) ->
  {allocated_main_width(P.shell(viewport, value, navigation, details)) == Some{P.width(viewport)} : Maybe<&2, Nat>}:
  Equal.trans(Maybe<&2, Nat>, allocated_main_width(P.shell(viewport, value, navigation, details)),
    allocated_main_width(P.from_packing(viewport, value, navigation, Space.pack(~P.ShellPart, [P.main_slot(0n)], 0n, P.width(viewport)))),
    Some{P.width(viewport)},
    Equal.cong(+List<Space.Slot<P.ShellPart>>, Maybe<&2, Nat>,
      (slots => allocated_main_width(P.from_packing(viewport, value, navigation, Space.pack(~P.ShellPart, slots, 0n, P.width(viewport))))),
      P.shell_slots(viewport, value, navigation, details), [P.main_slot(0n)], compact_slots(viewport, value, navigation, details, compact)),
    compact_pack_width(viewport, value, navigation))

def conjunction_right(+first: Bool, +second: Bool,
  proof: {first && second == True{} : Bool}) -> {second == True{} : Bool}:
  match first:
    case False{}: SpaceLaws.impossible({second == True{} : Bool}, proof)
    case True{}: proof

def valid_advance(+metric: T.Metric, valid: {T.valid_body(metric) == True{} : Bool}) ->
  {Nat.is_gt(metric_advance(metric), 0n) == True{} : Bool}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  conjunction_right(Nat.is_gt(height, 0n), Nat.is_gt(advance, 0n),
    conjunction_right(Nat.is_le(minimum, preferred), Nat.is_gt(height, 0n) && Nat.is_gt(advance, 0n),
      conjunction_right(String.eq(key, "@font/body"), Nat.is_le(minimum, preferred) &&
        (Nat.is_gt(height, 0n) && Nat.is_gt(advance, 0n)), valid)))

def valid_reading(+scale: T.Scale, +metric: T.Metric, valid: {T.valid_body(metric) == True{} : Bool}) ->
  {Nat.is_gt(reading_measure(P.parameters(scale, metric)), 0n) == True{} : Bool}:
  positive_reading(scale, metric, valid_advance(metric, valid))

def navigation_equation(+scale: T.Scale, metric: T.Metric) ->
  {P.navigation_width(P.parameters(scale, metric)) == T.scaled(275n, scale) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}

def details_equation(+scale: T.Scale, metric: T.Metric) ->
  {P.details_width(P.parameters(scale, metric)) == T.scaled(360n, scale) : Nat}:
  T.Metric{key, minimum, preferred, height, advance} = metric
  {==}

type Requirements is Type:
  Requirements{
    space: SpaceLaws.Requirements<P.ShellPart>,
    navigation_equation: @+scale:T.Scale -> @metric:T.Metric ->
      {P.navigation_width(P.parameters(scale, metric)) == T.scaled(275n, scale) : Nat},
    details_equation: @+scale:T.Scale -> @metric:T.Metric ->
      {P.details_width(P.parameters(scale, metric)) == T.scaled(360n, scale) : Nat},
    navigation_feasible: @+viewport:Design.Viewport -> @+value:Design.LayoutParameters -> @intent:E.NavigationIntent ->
      {nav_capacity(P.capacity(viewport, value, intent)) == Nat.is_le(Space.minimum_sequence(~P.ShellPart, P.navigation_slots(value), 0n), P.width(viewport)) : Bool},
    details_feasible: @+viewport:Design.Viewport -> @+value:Design.LayoutParameters -> @+intent:E.NavigationIntent ->
      {details_capacity(P.capacity(viewport, value, intent)) == Nat.is_le(Space.minimum_sequence(~P.ShellPart, P.regular_slots(value, P.placement(viewport, value, intent), True{}), 0n), P.width(viewport)) : Bool},
    complete_shell: @+viewport:Design.Viewport -> @+value:Design.LayoutParameters -> @+navigation:V.NavigationPlacement -> @+details:Bool ->
      @+fits:{Nat.is_le(Space.minimum_sequence(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n), P.width(viewport)) == True{} : Bool} ->
      Construction(viewport, value, navigation, details, P.shell_packing(viewport, value, navigation, details)),
    reading: @+scale:T.Scale -> @metric:T.Metric ->
      {reading_measure(P.parameters(scale, metric)) == T.reading_width(metric_advance(metric), 96n) : Nat},
    positive_reading: @+scale:T.Scale -> @+metric:T.Metric -> @positive:{Nat.is_gt(metric_advance(metric), 0n) == True{} : Bool} ->
      {Nat.is_gt(reading_measure(P.parameters(scale, metric)), 0n) == True{} : Bool},
    placement_ownership: @+viewport: Design.Viewport -> @+value: Design.LayoutParameters -> @intent: E.NavigationIntent ->
      {P.placement(viewport, value, intent) == V.navigation_placement(P.navigation_capacity(viewport, value),
      V.navigation_visible(intent, P.navigation_capacity(viewport, value))) : V.NavigationPlacement},
    closed_placement: @+viewport: Design.Viewport -> @+value: Design.LayoutParameters ->
      {P.placement(viewport, value, E.ClosedNavigation{}) == V.CollapsedNavigation{} : V.NavigationPlacement},
    no_sidebar_reservation: @+value: Design.LayoutParameters ->
      {P.regular_slots(value, V.ModalNavigation{}, True{}) ==
    P.regular_slots(value, V.CollapsedNavigation{}, True{}) : +List<Space.Slot<P.ShellPart>>},
    closed_details_budget: @+viewport: Design.Viewport -> @+value: Design.LayoutParameters ->
      {details_capacity(P.capacity(viewport, value, E.ClosedNavigation{})) ==
      P.packed(Space.pack(~P.ShellPart, P.regular_slots(value, V.CollapsedNavigation{}, True{}), 0n, P.width(viewport))) : Bool},
    unsupported_exact: @+viewport: Design.Viewport -> @+value: Design.LayoutParameters -> @+navigation: V.NavigationPlacement -> @+details: Bool -> @does_not_fit: {Nat.is_le(Space.minimum_sequence(~P.ShellPart,
      P.shell_slots(viewport, value, navigation, details), 0n), P.width(viewport)) == False{} : Bool} ->
      {P.shell(viewport, value, navigation, details) ==
      P.Unsupported{Space.minimum_sequence(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n), P.width(viewport)} : P.Result},
    main_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {P.main_minimum_width(P.parameters(scale, metric)) ==
    Nat.add(T.reading_width(metric_advance(metric), 64n), Nat.mul(2n, T.scaled(16n, scale))) : Nat},
    overview_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {overview_measure(P.parameters(scale, metric)) == T.reading_width(metric_advance(metric), 144n) : Nat},
    leading_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {leading(P.parameters(scale, metric)) == Nat.max(P.line_height(T.resolve(T.Body{}, T.Regular{}, scale)), metric_height(metric)) : Nat},
    toolbar_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {toolbar(P.parameters(scale, metric)) == Nat.max(T.scaled(46n, scale), Nat.add(leading(P.parameters(scale, metric)), T.scaled(26n, scale))) : Nat},
    input_minimum_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {input_minimum(P.parameters(scale, metric)) == Nat.max(T.scaled(44n, scale), Nat.add(leading(P.parameters(scale, metric)), Nat.mul(2n, T.scaled(12n, scale)))) : Nat},
    input_maximum_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {input_maximum(P.parameters(scale, metric)) == Nat.max(T.scaled(240n, scale), input_minimum(P.parameters(scale, metric))) : Nat},
    valid_input_bounds: @+scale: T.Scale -> @+metric: T.Metric -> @valid: {T.valid_body(metric) == True{} : Bool} ->
      {Nat.is_le(input_minimum(P.parameters(scale, metric)), input_maximum(P.parameters(scale, metric))) == True{} : Bool},
    balanced_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {balanced_minimum(P.parameters(scale, metric)) == Nat.add(toolbar(P.parameters(scale, metric)),
    Nat.mul(2n, Nat.add(P.line_height(T.resolve(T.Display{}, T.Regular{}, scale)),
      Nat.add(input_minimum(P.parameters(scale, metric)), Nat.add(T.scaled(32n, scale), Nat.mul(3n, T.scaled(16n, scale))))))) : Nat},
    installed_main: @+shell: Design.Shell -> @+offset: Nat -> @+extent: Nat -> @+height: Nat ->
      {main_projection(P.install(P.MainPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Design.Box{offset, 0n, extent, height} : Design.Box},
    installed_navigation: @+shell: Design.Shell -> @+offset: Nat -> @+extent: Nat -> @+height: Nat ->
      {navigation_projection(P.install(P.NavigationPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Design.BesideNavigation{Design.Box{offset, 0n, extent, height}} : Design.Navigation},
    installed_details: @+shell: Design.Shell -> @+offset: Nat -> @+extent: Nat -> @+height: Nat ->
      {details_projection(P.install(P.DetailsPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Some{Design.Box{offset, 0n, extent, height}} : Maybe<&2, Design.Box>},
    compact_width: @+viewport: Design.Viewport -> @+value: Design.LayoutParameters -> @+navigation: V.NavigationPlacement -> @+details: Bool -> @compact: {P.compact_main(navigation, details, P.width(viewport), P.main_minimum_width(value)) == True{} : Bool} ->
      {allocated_main_width(P.shell(viewport, value, navigation, details)) == Some{P.width(viewport)} : Maybe<&2, Nat>},
    valid_reading: @+scale: T.Scale -> @+metric: T.Metric -> @valid: {T.valid_body(metric) == True{} : Bool} ->
      {Nat.is_gt(reading_measure(P.parameters(scale, metric)), 0n) == True{} : Bool}}

def evidence() -> Requirements:
  Requirements{SpaceLaws.evidence(~P.ShellPart), navigation_equation, details_equation, navigation_feasibility, details_feasibility,
    feasible_construction, reading_equation, positive_reading, placement_ownership, closed_placement, no_sidebar_reservation, closed_details_budget, unsupported_exact, main_equation, overview_equation, leading_equation, toolbar_equation, input_minimum_equation, input_maximum_equation, valid_input_bounds, balanced_equation, installed_main, installed_navigation, installed_details, compact_width, valid_reading}
