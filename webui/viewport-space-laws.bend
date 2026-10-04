import Base
import ./viewport-space.bend as P
import ./typography.bend as T
import ./space.bend as Space
import ./space-laws.bend as SpaceLaws
import ./design.bend as Design
import ../core/user-experience.bend as E
import ../core/ui-world.bend as V

def Construction(+viewport: Design.Viewport, +value: Design.LayoutParameters,
  +navigation: V.NavigationPlacement, +details: Bool, packing: Space.Packing<P.ShellPart>) -> Type:
  match packing:
    case Space.Packed{+placements, unused}:
      ({P.shell(viewport, value, navigation, details) ==
          P.Allocated{P.placed_shell(placements, Design.viewport_height(viewport), P.empty_shell(viewport, value, navigation))} : P.Result} &
        SpaceLaws.AllocationEvidence<P.ShellPart, P.shell_slots(viewport, value, navigation, details),
          0n, 0n, P.width(viewport), Space.Allocation{placements, unused}>)
    case Space.Insufficient{required, available}: Empty


def nav_capacity(value: V.Capacity) -> Bool:
  V.Capacity{navigation, details} = value
  navigation


def details_capacity(value: V.Capacity) -> Bool:
  V.Capacity{navigation, details} = value
  details


def metric_advance(metric: T.Metric) -> Nat:
  T.Metric{key, minimum, preferred, height, advance} = metric
  advance


def metric_height(metric: T.Metric) -> Nat:
  T.Metric{key, minimum, preferred, height, advance} = metric
  height


def main_projection(shell: Design.Shell) -> Design.Box:
  Design.Shell{navigation, main, details} = shell
  main


def navigation_projection(shell: Design.Shell) -> Design.Navigation:
  Design.Shell{navigation, main, details} = shell
  navigation


def details_projection(shell: Design.Shell) -> Maybe<&2, Design.Box>:
  Design.Shell{navigation, main, details} = shell
  details


def allocated_main_width(result: P.Result) -> Maybe<&2, Nat>:
  match result:
    case P.Allocated{Design.Shell{navigation, Design.Box{left, top, width, height}, details}}: Some{width}
    case P.Unsupported{required, available}: None{}


type Requirements is Type:
  Requirements{
    space: SpaceLaws.Requirements<P.ShellPart>,
    navigation_equation: @+scale:T.Scale -> @metric:T.Metric ->
      {Design.navigation_width(P.parameters(scale, metric)) == T.scaled(275n, scale) : Nat},
    details_equation: @+scale:T.Scale -> @metric:T.Metric ->
      {Design.details_width(P.parameters(scale, metric)) == T.scaled(360n, scale) : Nat},
    navigation_feasible: @+viewport:Design.Viewport -> @+value:Design.LayoutParameters -> @intent:E.NavigationIntent ->
      {nav_capacity(P.capacity(viewport, value, intent)) == Nat.is_le(Space.minimum_sequence(~P.ShellPart, P.navigation_slots(value), 0n), P.width(viewport)) : Bool},
    details_feasible: @+viewport:Design.Viewport -> @+value:Design.LayoutParameters -> @+intent:E.NavigationIntent ->
      {details_capacity(P.capacity(viewport, value, intent)) == Nat.is_le(Space.minimum_sequence(~P.ShellPart, P.regular_slots(value, P.placement(viewport, value, intent), True{}), 0n), P.width(viewport)) : Bool},
    complete_shell: @+viewport:Design.Viewport -> @+value:Design.LayoutParameters -> @+navigation:V.NavigationPlacement -> @+details:Bool ->
      @+fits:{Nat.is_le(Space.minimum_sequence(~P.ShellPart, P.shell_slots(viewport, value, navigation, details), 0n), P.width(viewport)) == True{} : Bool} ->
      Construction(viewport, value, navigation, details, P.shell_packing(viewport, value, navigation, details)),
    reading: @+scale:T.Scale -> @metric:T.Metric ->
      {Design.reading_maximum_width(P.parameters(scale, metric)) == T.reading_width(metric_advance(metric), 96n) : Nat},
    positive_reading: @+scale:T.Scale -> @+metric:T.Metric -> @positive:{Nat.is_gt(metric_advance(metric), 0n) == True{} : Bool} ->
      {Nat.is_gt(Design.reading_maximum_width(P.parameters(scale, metric)), 0n) == True{} : Bool},
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
      {Design.main_minimum_width(P.parameters(scale, metric)) ==
    Nat.add(T.reading_width(metric_advance(metric), 64n), Nat.mul(2n, T.scaled(16n, scale))) : Nat},
    overview_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {Design.overview_maximum_width(P.parameters(scale, metric)) == T.reading_width(metric_advance(metric), 144n) : Nat},
    leading_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {Design.input_line_height(P.parameters(scale, metric)) == Nat.max(T.resolved_line_height(T.resolve(T.Body{}, T.Regular{}, scale)), metric_height(metric)) : Nat},
    toolbar_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {Design.toolbar_height(P.parameters(scale, metric)) == Nat.max(T.scaled(46n, scale), Nat.add(Design.input_line_height(P.parameters(scale, metric)), T.scaled(26n, scale))) : Nat},
    input_minimum_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {Design.input_minimum_height(P.parameters(scale, metric)) == Nat.max(T.scaled(44n, scale), Nat.add(Design.input_line_height(P.parameters(scale, metric)), Nat.mul(2n, T.scaled(12n, scale)))) : Nat},
    input_maximum_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {Design.input_maximum_height(P.parameters(scale, metric)) == Nat.max(T.scaled(240n, scale), Design.input_minimum_height(P.parameters(scale, metric))) : Nat},
    valid_input_bounds: @+scale: T.Scale -> @+metric: T.Metric -> @valid: {T.valid_body(metric) == True{} : Bool} ->
      {Nat.is_le(Design.input_minimum_height(P.parameters(scale, metric)), Design.input_maximum_height(P.parameters(scale, metric))) == True{} : Bool},
    balanced_equation: @+scale: T.Scale -> @metric: T.Metric ->
      {Design.creation_balanced_minimum_height(P.parameters(scale, metric)) == Nat.add(Design.toolbar_height(P.parameters(scale, metric)),
    Nat.mul(2n, Nat.add(T.resolved_line_height(T.resolve(T.Display{}, T.Regular{}, scale)),
      Nat.add(Design.input_minimum_height(P.parameters(scale, metric)), Nat.add(T.scaled(32n, scale), Nat.mul(3n, T.scaled(16n, scale))))))) : Nat},
    installed_main: @+shell: Design.Shell -> @+offset: Nat -> @+extent: Nat -> @+height: Nat ->
      {main_projection(P.install(P.MainPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Design.Box{offset, 0n, extent, height} : Design.Box},
    installed_navigation: @+shell: Design.Shell -> @+offset: Nat -> @+extent: Nat -> @+height: Nat ->
      {navigation_projection(P.install(P.NavigationPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Design.BesideNavigation{Design.Box{offset, 0n, extent, height}} : Design.Navigation},
    installed_details: @+shell: Design.Shell -> @+offset: Nat -> @+extent: Nat -> @+height: Nat ->
      {details_projection(P.install(P.DetailsPart{}, Design.Box{offset, 0n, extent, height}, shell)) ==
    Some{Design.Box{offset, 0n, extent, height}} : Maybe<&2, Design.Box>},
    compact_width: @+viewport: Design.Viewport -> @+value: Design.LayoutParameters -> @+navigation: V.NavigationPlacement -> @+details: Bool -> @compact: {P.compact_main(navigation, details, P.width(viewport), Design.main_minimum_width(value)) == True{} : Bool} ->
      {allocated_main_width(P.shell(viewport, value, navigation, details)) == Some{P.width(viewport)} : Maybe<&2, Nat>},
    valid_reading: @+scale: T.Scale -> @+metric: T.Metric -> @valid: {T.valid_body(metric) == True{} : Bool} ->
      {Nat.is_gt(Design.reading_maximum_width(P.parameters(scale, metric)), 0n) == True{} : Bool}}


law evidence:
  Requirements
