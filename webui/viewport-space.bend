import Base
import ./typography.bend as T
import ./space.bend as Space
import ./design.bend as Design
import ../core/user-experience.bend as E
import ../core/ui-world.bend as V

def parameters(+scale: T.Scale, body: T.Metric) -> Design.LayoutParameters:
  T.Metric{key, minimum, preferred, height, +advance} = body
  +leading = Nat.max(T.resolved_line_height(T.resolve(T.Body{}, T.Regular{}, scale)), height)
  +toolbar = Nat.max(T.scaled(46n, scale), Nat.add(leading, T.scaled(26n, scale)))
  +input_minimum = Nat.max(T.scaled(44n, scale), Nat.add(leading, Nat.mul(2n, T.scaled(12n, scale))))
  balanced = Nat.add(toolbar, Nat.mul(2n, Nat.add(T.resolved_line_height(T.resolve(T.Display{}, T.Regular{}, scale)),
    Nat.add(input_minimum, Nat.add(T.scaled(32n, scale), Nat.mul(3n, T.scaled(16n, scale)))))))
  Design.LayoutParameters{T.scaled(275n, scale), Nat.add(T.reading_width(advance, 64n), Nat.mul(2n, T.scaled(16n, scale))),
    T.scaled(360n, scale), T.reading_width(advance, 96n), T.reading_width(advance, 144n), toolbar,
    input_minimum, Nat.max(T.scaled(240n, scale), input_minimum), leading, balanced}

# These tags address shell fields; navigation intent remains a Core concept.
type ShellPart is Data:
  NavigationPart{}
  MainPart{}
  DetailsPart{}

type Result is Data:
  Allocated{shell: Design.Shell}
  Unsupported{required: Nat, available: Nat}

def width(viewport: Design.Viewport) -> Nat:
  Design.Viewport{width, height} = viewport
  width

def navigation_slot(value: Design.LayoutParameters) -> Space.Slot<ShellPart>:
  Space.Slot{NavigationPart{}, Space.Rigid{Design.navigation_width(value)}}

def main_slot(minimum: Nat) -> Space.Slot<ShellPart>:
  Space.Slot{MainPart{}, Space.Fill{minimum}}

def details_slot(value: Design.LayoutParameters) -> Space.Slot<ShellPart>:
  Space.Slot{DetailsPart{}, Space.Rigid{Design.details_width(value)}}

def packed(value: Space.Packing<ShellPart>) -> Bool:
  match value:
    case Space.Packed{placements, unused}: True{}
    case Space.Insufficient{required, available}: False{}

def navigation_slots(+value: Design.LayoutParameters) -> +List<Space.Slot<ShellPart>>:
  [navigation_slot(value), main_slot(Design.main_minimum_width(value))]

def include_navigation(placement: V.NavigationPlacement, value: Design.LayoutParameters,
  rest: +List<Space.Slot<ShellPart>>) -> +List<Space.Slot<ShellPart>>:
  match placement:
    case V.LeadingNavigation{}: navigation_slot(value) <> rest
    case _: rest

def include_details(requested: Bool, value: Design.LayoutParameters) -> +List<Space.Slot<ShellPart>>:
  match requested:
    case True{}: [details_slot(value)]
    case False{}: Nil{}

def regular_slots(+value: Design.LayoutParameters, placement: V.NavigationPlacement, details: Bool) -> +List<Space.Slot<ShellPart>>:
  include_navigation(placement, value, main_slot(Design.main_minimum_width(value)) <> include_details(details, value))

def navigation_capacity(viewport: Design.Viewport, value: Design.LayoutParameters) -> Bool:
  packed(Space.pack(~ShellPart, navigation_slots(value), 0n, width(viewport)))

def placement(+viewport: Design.Viewport, +value: Design.LayoutParameters, intent: E.NavigationIntent) -> V.NavigationPlacement:
  +beside = navigation_capacity(viewport, value)
  V.navigation_placement(beside, V.navigation_visible(intent, beside))

def capacity(+viewport: Design.Viewport, +value: Design.LayoutParameters, intent: E.NavigationIntent) -> V.Capacity:
  V.Capacity{navigation_capacity(viewport, value),
    packed(Space.pack(~ShellPart, regular_slots(value, placement(viewport, value, intent), True{}), 0n, width(viewport)))}

def compact_main(placement: V.NavigationPlacement, details: Bool, available: Nat, minimum: Nat) -> Bool:
  match placement details:
    case V.LeadingNavigation{} _: False{}
    case _ True{}: False{}
    case _ False{}: Nat.is_lt(available, minimum)

def actual_main_minimum(compact: Bool, minimum: Nat) -> Nat:
  match compact:
    case True{}: 0n
    case False{}: minimum

def shell_slots(+viewport: Design.Viewport, +value: Design.LayoutParameters, +placement: V.NavigationPlacement,
  +details: Bool) -> +List<Space.Slot<ShellPart>>:
  +minimum = Design.main_minimum_width(value)
  include_navigation(placement, value,
    main_slot(actual_main_minimum(compact_main(placement, details, width(viewport), minimum), minimum)) <>
      include_details(details, value))

def shell_packing(+viewport: Design.Viewport, value: Design.LayoutParameters,
  placement: V.NavigationPlacement, details: Bool) -> Space.Packing<ShellPart>:
  Space.pack(~ShellPart, shell_slots(viewport, value, placement, details), 0n, width(viewport))

def initial_navigation(+viewport: Design.Viewport, value: Design.LayoutParameters,
  placement: V.NavigationPlacement) -> Design.Navigation:
  match placement:
    case V.ModalNavigation{}:
      Design.OverlayNavigation{Design.Box{0n, 0n, Nat.min(Design.navigation_width(value), width(viewport)), Design.viewport_height(viewport)}}
    case _: Design.HiddenNavigation{}

def empty_shell(+viewport: Design.Viewport, value: Design.LayoutParameters, placement: V.NavigationPlacement) -> Design.Shell:
  Design.Shell{initial_navigation(viewport, value, placement), Design.Box{0n, 0n, 0n, Design.viewport_height(viewport)}, None{}}

def install(part: ShellPart, box: Design.Box, shell: Design.Shell) -> Design.Shell:
  match part shell:
    case NavigationPart{} Design.Shell{navigation, main, details}: Design.Shell{Design.BesideNavigation{box}, main, details}
    case MainPart{} Design.Shell{navigation, main, details}: Design.Shell{navigation, box, details}
    case DetailsPart{} Design.Shell{navigation, main, details}: Design.Shell{navigation, main, Some{box}}

def placed_shell(values: +List<Space.Placement<ShellPart>>, +height: Nat, shell: Design.Shell) -> Design.Shell:
  match values:
    case Nil{}: shell
    case Con{Space.Placement{part, offset, extent}, rest}:
      placed_shell(rest, height, install(part, Design.Box{offset, 0n, extent, height}, shell))

def from_packing(+viewport: Design.Viewport, value: Design.LayoutParameters, placement: V.NavigationPlacement,
  packing: Space.Packing<ShellPart>) -> Result:
  match packing:
    case Space.Insufficient{required, available}: Unsupported{required, available}
    case Space.Packed{placements, unused}:
      Allocated{placed_shell(placements, Design.viewport_height(viewport), empty_shell(viewport, value, placement))}

def shell(+viewport: Design.Viewport, +value: Design.LayoutParameters, +placement: V.NavigationPlacement, details: Bool) -> Result:
  from_packing(viewport, value, placement, shell_packing(viewport, value, placement, details))
