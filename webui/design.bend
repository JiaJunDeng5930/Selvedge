import Base
import ./spatial.bend as SpatialModel
import ./enclosure.bend as Enclosure
import ./surfaces.bend as Surfaces
import ../core/composition.bend as Composition
import ./controls.bend as Controls
import ./typography.bend as T
import ../core/interface.bend as UI
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
  CreationStructure{}
  ConversationStructure{}
  OverviewStructure{organization: Composition.Body}
  BoardStructure{}
  UnavailableStructure{}

def main_structure(recipe: Composition.Recipe) -> MainStructure:
  Composition.Recipe{measure, heading, body, composer, decisions, latest} = recipe
  match body:
    case Composition.CenteredCreation{}: CreationStructure{}
    case Composition.ChronologicalReading{}: ConversationStructure{}
    case Composition.ProjectSections{}: OverviewStructure{Composition.ProjectSections{}}
    case Composition.ProjectRows{}: OverviewStructure{Composition.ProjectRows{}}
    case Composition.AgentRows{}: OverviewStructure{Composition.AgentRows{}}
    case Composition.StageColumns{}: BoardStructure{}
    case Composition.UnavailableNotice{}: UnavailableStructure{}

type LayoutParameters is Data:
  LayoutParameters{navigation_width: Nat, main_minimum_width: Nat, details_width: Nat,
    reading_maximum_width: Nat, overview_maximum_width: Nat, toolbar_height: Nat,
    input_minimum_height: Nat, input_maximum_height: Nat, input_line_height: Nat,
    creation_balanced_minimum_height: Nat}

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

type ControlStates is Data:
  Passive{}
  SurfaceFeedback{hover: PhasePaint, pressed: PhasePaint}
  Interactive{hover: PhasePaint, pressed: PhasePaint, disabled_opacity_percent: Nat,
    focus_ring: Paint, focus_ring_width: Nat, focus_ring_offset: Nat}

type Style is Data:
  Style{text: T.Presentation, chrome: Chrome, alignment: SpatialModel.Alignment, flow: SpatialModel.Flow,
    overflow: SpatialModel.Overflow, frame: Enclosure.Frame,
    minimum_height: Nat, maximum_width_percent: Nat, states: ControlStates}

type Node is Data:
  Node{key: String, semantic: String, label: String, role: UI.Role,
    meaning: UI.Meaning, style: Style, control: Controls.Representation,
    children: +List<Node>}

type Surface is Data:
  Surface{content: Core.Scene, theme: Theme, base: +List<Node>,
    overlays: +List<Node>, active_scope: Maybe<&2, String>}

def semantic_nodes(nodes: +List<Node>) -> +List<UI.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Node{key, semantic, label, role, meaning, style, control, children}, rest}:
      UI.Node{key, semantic, label, role, meaning, semantic_nodes(children)} <> semantic_nodes(rest)

def semantic_surface(surface: Surface) -> UI.Surface:
  Surface{content, theme, base, overlays, active_scope} = surface
  UI.Surface{content, semantic_nodes(base), semantic_nodes(overlays), active_scope}

def navigation_width(value: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  navigation

def main_minimum_width(value: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  main

def reading_maximum_width(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  reading

def overview_maximum_width(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  overview

def input_maximum_height(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
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

def parameters(+scale: T.Scale, body: T.Metric) -> LayoutParameters:
  T.Metric{key, minimum, preferred, height, +advance} = body
  +leading = Nat.max(T.resolved_line_height(T.resolve(T.Body{}, T.Regular{}, scale)), height)
  +toolbar = Nat.max(T.scaled(46n, scale), Nat.add(leading, T.scaled(26n, scale)))
  +input_minimum = Nat.max(T.scaled(44n, scale), Nat.add(leading, Nat.mul(2n, T.scaled(12n, scale))))
  balanced = Nat.add(toolbar, Nat.mul(2n, Nat.add(T.resolved_line_height(T.resolve(T.Display{}, T.Regular{}, scale)),
    Nat.add(input_minimum, Nat.add(T.scaled(32n, scale), Nat.mul(3n, T.scaled(16n, scale)))))))
  LayoutParameters{T.scaled(275n, scale), Nat.add(T.reading_width(advance, 64n), Nat.mul(2n, T.scaled(16n, scale))),
    T.scaled(360n, scale), T.reading_width(advance, 96n), T.reading_width(advance, 144n), toolbar,
    input_minimum, Nat.max(T.scaled(240n, scale), input_minimum), leading, balanced}
