import Base
import ./enclosure.bend as Enclosure
import ../appearance/TYPOGRAPHY.bend as T

type Box is Data:
  Box{left: Nat, top: Nat, width: Nat, height: Nat}

type Alignment is Data:
  Stretch{}
  Leading{}
  Trailing{}
  Centered{}

# Layer anchors are observed trigger bounds in the same viewport coordinates.
# Outside clearance belongs to the container boundary, independently of frame padding.

type Position is Data:
  InFlow{}
  CenteredLayer{outside: Enclosure.Insets}
  AlignedLayer{outside: Enclosure.Insets, horizontal: Alignment, vertical: Alignment}
  AnchoredLayer{anchor_key: String, anchor: Maybe<&2, Box>, outside: Enclosure.Insets,
    gap: Nat, alignment: Alignment}

type ContentAlignment is Data:
  CenterContents{}
  LeadingContents{}

type Flow is Data:
  BlockFlow{}
  ColumnFlow{}
  RowFlow{}
  SplitRowFlow{}
  WrapFlow{}
  InlineControlFlow{alignment: ContentAlignment}
  ChoiceFlow{}

type Overflow is Data:
  ContentFlow{}
  TextFlow{wrapping: T.Wrapping}
  ScrollFlow{}
  # The toolbar remains reachable while the code body uses its modeled wrap mode.
  CodeOverflow{}
  SingleLineOverflow{}

type Origin is Data:
  Forward{distance: Nat}
  Backward{distance: Nat}

type Axis is Data:
  Axis{start: Nat, extent: Nat}

# Clip before adding coordinates: observed origins may be negative and extents
# may reach Nat's limit, so an origin-plus-extent sum is not an admissible input.

def clip_axis(origin: Origin, +extent: Nat, +limit: Nat) -> Axis:
  match origin:
    case Forward{distance}:
      +start = Nat.min(distance, limit)
      Axis{start, Nat.min(extent, Nat.sub(limit, start))}
    case Backward{distance}:
      Axis{0n, Nat.min(Nat.sub(extent, distance), limit)}

def from_axes(horizontal: Axis, vertical: Axis) -> Box:
  match horizontal:
    case Axis{left, width}:
      match vertical:
        case Axis{top, height}: Box{left, top, width, height}

def visible(left: Origin, top: Origin, width: Nat, height: Nat, viewport_width: Nat, viewport_height: Nat) -> Box:
  from_axes(clip_axis(left, width, viewport_width), clip_axis(top, height, viewport_height))
