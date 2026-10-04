import Base
import ./document.bend as Doc
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

def fact_content_frame(value: FactContentLayout) -> Enclosure.Frame:
  FactContentLayout{content, facts} = value
  content

def fact_collection_frame(value: FactContentLayout) -> Enclosure.Frame:
  FactContentLayout{content, facts} = value
  facts

def fact_frame() -> Enclosure.Frame:
  fact_content_frame(fact_content_layout())

def facts_frame() -> Enclosure.Frame:
  fact_collection_frame(fact_content_layout())

# CSS pixels describe the Web viewport; product composition remains unit-free.
type Viewport is Data:
  Viewport{width: Nat, height: Nat}

type Environment is Data:
  Environment{viewport: Viewport, system_dark: Bool, root_font_size_milli: Nat}

type Box is Data:
  Box{left: Nat, top: Nat, width: Nat, height: Nat}

type Band is Data:
  Band{left: Nat, width: Nat}

type Navigation is Data:
  HiddenNavigation{}
  BesideNavigation{bounds: Box}
  OverlayNavigation{bounds: Box}

type Shell is Data:
  Shell{navigation: Navigation, main: Box, details: Maybe<&2, Box>}

type DockRegion is Data:
  LatestControl{}
  PendingApprovals{}
  MessageInput{}

type InputMetrics is Data:
  InputMetrics{minimum_input_height: Nat, maximum_input_height: Nat,
    input_line_height: Nat, inline_padding: Nat, footer_gap: Nat, footer_padding: Nat}

type Reservation is Data:
  # Reserve the measured total dock height plus its bottom inset in the timeline.
  # Approval growth participates in the same reading-anchor protocol as input growth.
  MeasuredDock{}

type Dock is Data:
  Dock{band: Band, bottom_inset: Nat, maximum_height: Nat,
    regions: +List<DockRegion>, input: Maybe<&2, InputMetrics>, reservation: Reservation}

type CreationFlow is Data:
  Balanced{}
  Compact{}

type BlockMargin is Data:
  AutomaticMargin{}
  NoMargin{}

type CreationArrangement is Data:
  CreationArrangement{canvas_inset: Nat, region_gap: Nat, footer_gap: Nat,
    introduction_alignment: Alignment, block_margin: BlockMargin}

type MainFrame is Data:
  # Center the intrinsic input group in this canvas, subject to its height bound.
  CreationFrame{heading: Box, canvas: Box, band: Band, input: Maybe<&2, InputMetrics>, flow: CreationFlow}
  ConversationFrame{heading: Box, viewport: Box, reading: Band, dock: Maybe<&2, Dock>}
  OverviewFrame{canvas: Box, band: Band, organization: Composition.Body}
  BoardFrame{canvas: Box, column_width: Nat, column_gap: Nat, inset: Nat}
  UnavailableFrame{heading: Box, canvas: Box, band: Band}

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

def frame_structure(frame: MainFrame) -> MainStructure:
  match frame:
    case CreationFrame{heading, canvas, band, input, flow}: CreationStructure{}
    case ConversationFrame{heading, viewport, reading, dock}: ConversationStructure{}
    case OverviewFrame{canvas, band, organization}: OverviewStructure{organization}
    case BoardFrame{canvas, column_width, column_gap, inset}: BoardStructure{}
    case UnavailableFrame{heading, canvas, band}: UnavailableStructure{}

type OverlayPlacement is Data:
  CenteredDialog{available: Box, maximum_width: Nat}
  # Prefer below/end of the anchor; flip vertically and clamp both axes to available.
  AnchoredPopover{anchor: String, available: Box, maximum_width: Nat, maximum_height: Nat, gap: Nat}
  TrailingPane{bounds: Box}
  NavigationDrawer{bounds: Box}

type Overlay is Data:
  Overlay{key: String, level: Nat, placement: OverlayPlacement}

type LayoutParameters is Data:
  LayoutParameters{navigation_width: Nat, main_minimum_width: Nat, details_width: Nat,
    reading_maximum_width: Nat, overview_maximum_width: Nat, toolbar_height: Nat,
    input_minimum_height: Nat, input_maximum_height: Nat, input_line_height: Nat,
    creation_balanced_minimum_height: Nat}

type NodePlacement is Data:
  NodePlacement{key: String, bounds: Box}

type Layout is Data:
  Layout{viewport: Viewport, shell: Shell, main: MainFrame, overlays: +List<Overlay>, parameters: LayoutParameters, controls: +List<NodePlacement>}

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

type Alignment is Data:
  Stretch{}
  Leading{}
  Trailing{}
  Centered{}

type Flow is Data:
  BlockFlow{}
  ColumnFlow{}
  RowFlow{}
  SplitRowFlow{}
  WrapFlow{}
  InlineControlFlow{alignment: Controls.ContentAlignment}
  ChoiceFlow{}

type Overflow is Data:
  ContentFlow{}
  TextFlow{wrapping: T.Wrapping}
  ScrollFlow{}
  # The toolbar remains reachable while the code body uses its modeled wrap mode.
  CodeOverflow{}
  SingleLineOverflow{}

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
  Style{text: T.Presentation, chrome: Chrome, alignment: Alignment, flow: Flow,
    overflow: Overflow, frame: Enclosure.Frame,
    minimum_height: Nat, maximum_width_percent: Nat, states: ControlStates}

type Node is Data:
  Node{key: String, semantic: String, label: String, role: UI.Role,
    meaning: UI.Meaning, style: Style, control: Controls.Representation,
    children: +List<Node>}

type Surface is Data:
  Surface{content: Core.Scene, theme: Theme, base: +List<Node>,
    overlays: +List<Node>, active_scope: Maybe<&2, String>}

# The document is derived once from the original surface by Renderer.prepare.
type PreparedSurface is Data:
  PreparedSurface{surface: Surface, base: +List<Doc.Node>, overlays: +List<Doc.Node>}

def semantic_nodes(nodes: +List<Node>) -> +List<UI.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Node{key, semantic, label, role, meaning, style, control, children}, rest}:
      UI.Node{key, semantic, label, role, meaning, semantic_nodes(children)} <> semantic_nodes(rest)

def semantic_surface(surface: Surface) -> UI.Surface:
  Surface{content, theme, base, overlays, active_scope} = surface
  UI.Surface{content, semantic_nodes(base), semantic_nodes(overlays), active_scope}

def viewport_height(viewport: Viewport) -> Nat:
  Viewport{width, height} = viewport
  height

def navigation_width(value: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  navigation

def main_minimum_width(value: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  main

def details_width(value: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = value
  details

def toolbar_height(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  toolbar

def reading_maximum_width(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  reading

def overview_maximum_width(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  overview

def input_minimum_height(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  minimum

def input_maximum_height(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  maximum

def input_line_height(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  leading

def creation_balanced_minimum_height(+parameters: LayoutParameters) -> Nat:
  LayoutParameters{navigation, main, details, reading, overview, toolbar, minimum, maximum, leading, creation} = parameters
  creation

def style_text(style: Style) -> T.Presentation:
  Style{text, chrome, alignment, flow, overflow, frame, height, maximum, states} = style
  text

def style_minimum_height(value: Style) -> Nat:
  Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  height

def style_frame(value: Style) -> Enclosure.Frame:
  Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  frame
