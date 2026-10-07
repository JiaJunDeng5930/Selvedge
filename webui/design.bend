import Base
import ./natural-size.bend as NaturalSize
import ../core/ui-identity.bend as UIIdentity
import ./spatial.bend as SpatialModel
import ./enclosure.bend as Enclosure
import ./surfaces.bend as Surfaces
import ../core/composition.bend as Composition
import ./controls.bend as Controls
import ./typography.bend as T
import ../core/interface.bend as InterfaceView
import ../core/SYSTEM.bend as Core

type FactContentLayout is Data:
  FactContentLayout{content: Enclosure.Frame, facts: Enclosure.Frame}

def fact_content_layout() -> FactContentLayout:
  FactContentLayout{Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{4n}},
    Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.SeparateFrames{Enclosure.Sections{}}}}

# CSS pixels describe the Web viewport; product composition remains unit-free.
type Viewport is Data:
  Viewport{width: Nat, height: Nat}

type Environment is Data:
  Environment{viewport: Viewport, system_dark: Bool, root_font_size_milli: Nat}

type MainStructure is Data:
  MainStructure{measure: Composition.Measure, heading: Composition.Heading, organization: Composition.Body}

def main_structure(recipe: Composition.Recipe) -> MainStructure:
  Composition.Recipe{measure, heading, body, composer, decisions, latest} = recipe
  MainStructure{measure, heading, body}

type LayoutParameters is Data:
  LayoutParameters{navigation_width: Nat, main_minimum_width: Nat, details_width: Nat,
    reading_maximum_width: Nat, overview_maximum_width: Nat, toolbar_height: Nat,
    input_minimum_height: Nat, input_maximum_height: Nat, input_line_height: Nat,
    creation_balanced_minimum_height: Nat, lane_minimum_width: Nat}

type NodePlacement is Data:
  NodePlacement{key: String, bounds: SpatialModel.Box}

type Theme is Data:
  Light{}
  Dark{}

# Paint names refer to the already imported Desktop theme, including its dark
# variant. The browser resolves the tokens rather than inventing another palette.
type Paint is Data:
  Transparent{}
  ThemeToken{name: String}
  SurfacePaint{role: Surfaces.Role, phase: Surfaces.Phase}
  SurfaceForeground{role: Surfaces.Role}
  TextForeground{tone: Surfaces.TextTone}

type Chrome is Data:
  Chrome{foreground: Paint, background: Paint, border: Paint, border_width: Nat,
    radius: Nat, shadow: Bool}

type PhasePaint is Data:
  PhasePaint{foreground: Paint, background: Paint}

# The ring occupies [inset, inset + width] inside each allocated control edge.
type FocusIndicator is Data:
  FocusIndicator{paint: Paint, width: Nat, inset: Nat}

def focus_indicator_outer_inset(value: FocusIndicator) -> Nat:
  FocusIndicator{paint, width, inset} = value
  inset

def focus_indicator_inner_inset(value: FocusIndicator) -> Nat:
  FocusIndicator{paint, width, inset} = value
  Nat.add(inset, width)

type ControlStates is Data:
  Passive{}
  SurfaceFeedback{hover: PhasePaint, pressed: PhasePaint}
  Interactive{hover: PhasePaint, pressed: PhasePaint, disabled_opacity_percent: Nat,
    focus_indicator: FocusIndicator}

type Style is Data:
  Style{text: T.Presentation, chrome: Chrome, alignment: SpatialModel.Alignment, flow: SpatialModel.Flow,
    overflow: SpatialModel.Overflow, frame: Enclosure.Frame,
    minimum_height: Nat, maximum_width_percent: Nat, states: ControlStates}

type Node is Data:
  Node{key: UIIdentity.Key, semantic: String, label: String, role: InterfaceView.Role,
    meaning: InterfaceView.Meaning, style: Style, control: Controls.Representation,
    children: +List<Node>}

type Surface is Data:
  Surface{content: Core.Scene, theme: Theme, base: +List<Node>,
    overlays: +List<Node>, active_scope: Maybe<&2, String>}

def semantic_nodes(nodes: +List<Node>) -> +List<InterfaceView.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Node{key, semantic, label, role, meaning, style, control, children}, rest}:
      InterfaceView.Node{key, semantic, label, role, meaning, semantic_nodes(children)} <> semantic_nodes(rest)

def semantic_surface(surface: Surface) -> InterfaceView.Surface:
  Surface{content, theme, base, overlays, active_scope} = surface
  InterfaceView.Surface{content, semantic_nodes(base), semantic_nodes(overlays), active_scope}

def navigation_width(value: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation, lane} = value
  navigation

def main_minimum_width(value: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation, lane} = value
  main

def reading_maximum_width(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation, lane} = parameters
  reading

def overview_maximum_width(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation, lane} = parameters
  overview

def input_maximum_height(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation, lane} = parameters
  maximum

def style_text(style: Style) -> T.Presentation:
  Style{text, chrome, alignment, flow, overflow, frame, height, maximum, states} = style
  text

def style_minimum_height(value: Style) -> Nat:
  Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  height

def style_frame(value: Style) -> Enclosure.Frame:
  Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  frame

def parameter_values(values: Maybe<&2, +List<Nat>>) -> Maybe<&2, LayoutParameters>:
  match values:
    case Some{Con{navigation, Con{main, Con{details, Con{reading, Con{overview, Con{toolbar, Con{minimum, Con{maximum, Con{leading, Con{creation, Con{lane, Nil{}}}}}}}}}}}}}:
      Some{LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation, lane}}
    case _: None{}

def parameter_calculations(+capacity: Nat, +scale: T.Scale, height: Nat, +advance: Nat) -> +List<NaturalSize.Calculation>:
  +leading: NaturalSize.Calculation = NaturalSize.Maximum{NaturalSize.Value{T.resolved_line_height(T.resolve(capacity, T.Body{}, T.Regular{}, scale))}, NaturalSize.Value{height}}
  +toolbar: NaturalSize.Calculation = NaturalSize.Maximum{T.scaling_calculation(46n, scale), NaturalSize.Sum{leading, T.scaling_calculation(26n, scale)}}
  +input_minimum: NaturalSize.Calculation = NaturalSize.Maximum{T.scaling_calculation(44n, scale), NaturalSize.Sum{leading, NaturalSize.Product{NaturalSize.Value{2n}, T.scaling_calculation(12n, scale)}}}
  balanced: NaturalSize.Calculation = NaturalSize.Sum{toolbar, NaturalSize.Product{NaturalSize.Value{2n},
    NaturalSize.Sum{NaturalSize.Value{T.resolved_line_height(T.resolve(capacity, T.Display{}, T.Regular{}, scale))},
      NaturalSize.Sum{input_minimum, NaturalSize.Sum{T.scaling_calculation(32n, scale), NaturalSize.Product{NaturalSize.Value{3n}, T.scaling_calculation(16n, scale)}}}}}}
  [
    T.scaling_calculation(275n, scale),
    NaturalSize.Sum{NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{64n}}, NaturalSize.Product{NaturalSize.Value{2n}, T.scaling_calculation(16n, scale)}},
    T.scaling_calculation(360n, scale),
    NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{96n}},
    NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{144n}},
    toolbar, input_minimum, NaturalSize.Maximum{T.scaling_calculation(240n, scale), input_minimum}, leading, balanced, NaturalSize.Sum{NaturalSize.Product{NaturalSize.Value{advance}, NaturalSize.Value{32n}}, NaturalSize.Product{NaturalSize.Value{2n}, T.scaling_calculation(Enclosure.inline(Enclosure.area(Enclosure.Lane{})), scale)}}]


def parameters(+capacity: Nat, scale: T.Scale, body: T.Metric) -> Maybe<&2, LayoutParameters>:
  T.Metric{key, minimum, preferred, height, advance} = body
  parameter_values(NaturalSize.evaluate_all(capacity, parameter_calculations(capacity, scale, height, advance)))

def lane_minimum_width(value: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation, lane} = value
  lane
