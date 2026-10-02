import Base
import ./enclosure.bend as Enclosure
import ./surfaces.bend as Surfaces
import ../core/composition.bend as Composition
import ./controls.bend as Controls

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
  Environment{viewport: Viewport, system_dark: Bool}

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

type OverlayPlacement is Data:
  CenteredDialog{available: Box, maximum_width: Nat}
  # Prefer below/end of the anchor; flip vertically and clamp both axes to available.
  AnchoredPopover{anchor: String, available: Box, maximum_width: Nat, maximum_height: Nat, gap: Nat}
  TrailingPane{bounds: Box}
  NavigationDrawer{bounds: Box}

type Overlay is Data:
  Overlay{key: String, level: Nat, placement: OverlayPlacement}

type Layout is Data:
  Layout{viewport: Viewport, shell: Shell, main: MainFrame, overlays: +List<Overlay>}

type Theme is Data:
  Light{}
  Dark{}

type Font is Data:
  InterfaceFont{}
  MonospaceFont{}

type TextStyle is Data:
  TextStyle{font: Font, size: Nat, line_height: Nat, weight: Nat}

# Paint names refer to the already imported Desktop theme, including its dark
# variant. The browser resolves the tokens rather than inventing another palette.
type Paint is Data:
  Transparent{}
  ThemeToken{name: String}
  SurfacePaint{role: Surfaces.Role, phase: Surfaces.Phase}
  SurfaceForeground{role: Surfaces.Role}

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

type Overflow is Data:
  ContentFlow{}
  ScrollFlow{}
  # The toolbar remains reachable while the code body uses its modeled wrap mode.
  CodeOverflow{}

type Chrome is Data:
  Chrome{foreground: Paint, background: Paint, border: Paint, border_width: Nat,
    radius: Nat, shadow: Bool}

type ControlStates is Data:
  Passive{}
  Interactive{hover: Chrome, pressed: Chrome, disabled_opacity_percent: Nat,
    focus_ring: Paint, focus_ring_width: Nat, focus_ring_offset: Nat}

type Style is Data:
  Style{text: TextStyle, chrome: Chrome, alignment: Alignment, flow: Flow,
    overflow: Overflow, frame: Enclosure.Frame,
    minimum_height: Nat, maximum_width_percent: Nat, states: ControlStates}

type Appearance is Data:
  Appearance{key: String, style: Style, control: Controls.Representation,
    children: +List<Appearance>}

type Rhythm is Data:
  Rhythm{page_inset: Nat, section_gap: Nat, message_gap: Nat, activity_gap: Nat,
    row_height: Nat, board_gap: Nat}

type Visuals is Data:
  Visuals{theme: Theme, rhythm: Rhythm, base: +List<Appearance>, overlays: +List<Appearance>}

type Presentation is Data:
  Presentation{layout: Layout, visuals: Visuals}
