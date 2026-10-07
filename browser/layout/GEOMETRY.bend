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
