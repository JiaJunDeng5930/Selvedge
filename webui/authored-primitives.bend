import Base
import ../core/ui-identity.bend as UIIdentity
import ./source.bend as Source
import ./design.bend as Design
import ./physical-space.bend as Model
import ./spatial.bend as Spatial
import ./enclosure.bend as Enclosure
import ./typography.bend as T

def width_cap(full_width: Bool, maximum_width_percent: Nat) -> Model.AxisSize:
  match full_width:
    case True{}: Model.NaturalSize{}
    case False{}: Model.CappedNaturalSize{maximum_width_percent}

def natural_width(visual: Design.Style) -> Model.AxisSize:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, +maximum_width_percent, states} = visual
  width_cap(Nat.is_eq(maximum_width_percent, 100n), maximum_width_percent)

def adaptive_width_cap(full_width: Bool, preferred_maximum_percent: Nat) -> Model.AxisSize:
  match full_width:
    case True{}: Model.NaturalSize{}
    case False{}: Model.AdaptiveNaturalSize{preferred_maximum_percent}

def adaptive_natural_width(visual: Design.Style) -> Model.AxisSize:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, +maximum_width_percent, states} = visual
  adaptive_width_cap(Nat.is_eq(maximum_width_percent, 100n), maximum_width_percent)

def flow_direction(flow: Spatial.Flow) -> Model.Direction:
  match flow:
    case Spatial.BlockFlow{}: Model.Vertical{}
    case Spatial.ColumnFlow{}: Model.Vertical{}
    case Spatial.ChoiceFlow{}: Model.Vertical{}
    case Spatial.RowFlow{}: Model.ResponsiveHorizontal{}
    case Spatial.SplitRowFlow{}: Model.ResponsiveHorizontal{}
    case Spatial.WrapFlow{}: Model.ResponsiveHorizontal{}
    case Spatial.InlineControlFlow{alignment}: Model.Horizontal{}

def main_alignment(flow: Spatial.Flow) -> Spatial.Alignment:
  match flow:
    case Spatial.InlineControlFlow{alignment}:
      match alignment:
        case Spatial.CenterContents{}: Spatial.Centered{}
        case Spatial.LeadingContents{}: Spatial.Leading{}
    case _: Spatial.Leading{}

def cross_alignment(flow: Spatial.Flow, alignment: Spatial.Alignment) -> Spatial.Alignment:
  match flow:
    case Spatial.InlineControlFlow{contents}: Spatial.Centered{}
    case _: alignment

def style(visual: Design.Style, width: Model.AxisSize, height: Model.AxisSize,
  scroll: Model.Scroll) -> Source.Style:
  Design.Style{text, chrome, alignment, +flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  Source.Style{Source.Layout{flow_direction(flow), main_alignment(flow), cross_alignment(flow, alignment),
    frame, width, height, Enclosure.Extent{0n, minimum_height}, scroll, Spatial.InFlow{}}, Source.ExplicitFont{text}, chrome, states}

def with_minimum(value: Source.Style, minimum: Enclosure.Extent) -> Source.Style:
  Source.Style{layout, font, chrome, states} = value
  Source.Layout{direction, main, cross, frame, width, height, existing, scroll, position} = layout
  Source.Style{Source.Layout{direction, main, cross, frame, width, height,
    Model.extent_max(existing, minimum), scroll, position}, font, chrome, states}

def with_font(value: Source.Style, font: Source.FontChoice) -> Source.Style:
  Source.Style{layout, old_font, chrome, states} = value
  Source.Style{layout, font, chrome, states}

def with_direction(value: Source.Style, direction: Model.Direction) -> Source.Style:
  Source.Style{layout, font, chrome, states} = value
  Source.Layout{old_direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}

def with_frame(value: Source.Style, frame: Enclosure.Frame) -> Source.Style:
  Source.Style{layout, font, chrome, states} = value
  Source.Layout{direction, main, cross, old_frame, width, height, minimum, scroll, position} = layout
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}

def with_alignments(value: Source.Style, main: Spatial.Alignment, cross: Spatial.Alignment) -> Source.Style:
  Source.Style{layout, font, chrome, states} = value
  Source.Layout{direction, old_main, old_cross, frame, width, height, minimum, scroll, position} = layout
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}

# The enclosing control owns the interaction floor; the glyph owns only its drawing extent.
def glyph_style(parent: Design.Style, +width: Nat, +height: Nat) -> Source.Style:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = parent
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  Source.Style{Source.Layout{Model.Horizontal{}, Spatial.Centered{}, Spatial.Centered{},
    Enclosure.frame(Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}),
    Model.ExactSize{width}, Model.ExactSize{height}, Enclosure.Extent{width, height}, Model.Confined{}, Spatial.InFlow{}},
    Source.ExplicitFont{text}, Design.Chrome{foreground, Design.Transparent{}, Design.Transparent{}, 0n, 0n, False{}},
    Design.Passive{}}

# Content groups inherit typography and foreground without the parent's enclosure.
def content_style(parent: Design.Style, direction: Model.Direction, width: Model.AxisSize,
  height: Model.AxisSize, gap: Nat) -> Source.Style:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = parent
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = chrome
  Source.Style{Source.Layout{direction, Spatial.Leading{}, Spatial.Stretch{},
    Enclosure.frame(Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{gap}),
    width, height, Enclosure.Extent{0n, 0n}, Model.Confined{}, Spatial.InFlow{}},
    Source.ExplicitFont{text}, Design.Chrome{foreground, Design.Transparent{}, Design.Transparent{}, 0n, 0n, False{}},
    Design.Passive{}}

def text(key: UIIdentity.Key, value: String, font: Source.FontChoice, wrapping: T.Wrapping) -> Source.Node:
  Source.Text{key, value, font, wrapping}

def binding_attributes(key: UIIdentity.Key) -> +List<Source.Attribute>:
  Source.DataAttribute{"native-key", UIIdentity.encode(key)} <> Nil{}

# Placement changes retain the complete authored style and enclosure contract.
