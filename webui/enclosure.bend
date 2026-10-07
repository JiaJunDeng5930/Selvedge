import Base

# Content allocation is independent of border paint and interaction phase.
type Profile is Data:
  IconControl{}
  TextControl{}
  OptionControl{}
  NavigationRow{}
  Field{}
  SearchField{}
  Composer{}
  Card{}
  Menu{}
  UserMessage{}
  Details{}
  Navigation{}
  Approval{}
  CodeBlock{}
  Lane{}
  ArchiveGroup{}
  PageContent{}

type Insets is Data:
  Insets{inline: Nat, block: Nat}

type Part is Data:
  Header{}
  Body{}
  Footer{}

type ContentArea is Data:
  Ambient{space: Insets}
  Inset{profile: Profile}
  DialogPartitions{}

type Extent is Data:
  Extent{width: Nat, height: Nat}

def spacing(profile: Profile) -> Insets:
  match profile:
    case IconControl{}: Insets{4n, 4n}
    case TextControl{}: Insets{8n, 4n}
    case OptionControl{}: Insets{8n, 8n}
    case NavigationRow{}: Insets{8n, 4n}
    case Field{}: Insets{8n, 6n}
    case SearchField{}: Insets{8n, 4n}
    case Composer{}: Insets{12n, 8n}
    case Card{}: Insets{12n, 12n}
    case Menu{}: Insets{8n, 8n}
    case UserMessage{}: Insets{12n, 8n}
    case Details{}: Insets{16n, 16n}
    case Navigation{}: Insets{8n, 8n}
    case Approval{}: Insets{12n, 12n}
    case CodeBlock{}: Insets{12n, 12n}
    case Lane{}: Insets{8n, 8n}
    case ArchiveGroup{}: Insets{2n, 2n}
    case PageContent{}: Insets{24n, 24n}

def area(profile: Profile) -> ContentArea:
  Inset{profile}

def ambient(inline: Nat, block: Nat) -> ContentArea:
  Ambient{Insets{inline, block}}

# The dialog owns these partitions; the outer shell delegates its allocation.
def partition_inline() -> Nat:
  24n

def partition(part: Part) -> ContentArea:
  match part:
    case Header{}: ambient(partition_inline(), 14n)
    case Body{}: ambient(partition_inline(), 20n)
    case Footer{}: ambient(partition_inline(), 12n)

def insets(area: ContentArea) -> Insets:
  match area:
    case Ambient{space}: space
    case Inset{profile}: spacing(profile)
    case DialogPartitions{}: Insets{0n, 0n}

def inset_inline(space: Insets) -> Nat:
  Insets{inline, block} = space
  inline

def inset_block(space: Insets) -> Nat:
  Insets{inline, block} = space
  block

def inline(area: ContentArea) -> Nat:
  inset_inline(insets(area))

def block(area: ContentArea) -> Nat:
  inset_block(insets(area))

def required_extent(content_width: Nat, content_height: Nat, +border: Nat,
  +area: ContentArea) -> Extent:
  Extent{Nat.add(content_width, Nat.mul(2n, Nat.add(border, inline(area)))),
    Nat.add(content_height, Nat.mul(2n, Nat.add(border, block(area))))}

# Child relationships belong to the enclosing frame, independently of its paint.
type Separation is Data:
  NavigationRows{}
  MenuItems{}
  InlineControls{}
  ComposerControls{}
  CardSections{}
  Cards{}
  BoardColumns{}
  DialogSections{}
  DialogActions{}
  Sections{}
  Messages{}

def separation(value: Separation) -> Nat:
  match value:
    case NavigationRows{}: 4n
    case MenuItems{}: 4n
    case InlineControls{}: 4n
    case ComposerControls{}: 8n
    case CardSections{}: 8n
    case Cards{}: 12n
    case BoardColumns{}: 16n
    case DialogSections{}: 16n
    case DialogActions{}: 12n
    case Sections{}: 12n
    case Messages{}: 16n

type Arrangement is Data:
  EmbeddedContent{gap: Nat}
  SeparateFrames{spacing: Separation}
  JoinedPartitions{}

type Frame is Data:
  Frame{content: ContentArea, arrangement: Arrangement}

def frame(content: ContentArea, arrangement: Arrangement) -> Frame:
  Frame{content, arrangement}

def frame_content(value: Frame) -> ContentArea:
  Frame{content, arrangement} = value
  content

def arrangement_gap(value: Arrangement) -> Nat:
  match value:
    case EmbeddedContent{gap}: gap
    case SeparateFrames{spacing}: separation(spacing)
    case JoinedPartitions{}: 0n

def frame_gap(value: Frame) -> Nat:
  Frame{content, arrangement} = value
  arrangement_gap(arrangement)

def extent_height(value: Extent) -> Nat:
  Extent{width, height} = value
  height

def extent_width(value: Extent) -> Nat:
  Extent{width, height} = value
  width
