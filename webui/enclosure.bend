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

def area(profile: Profile) -> ContentArea:
  Inset{profile}

def ambient(inline: Nat, block: Nat) -> ContentArea:
  Ambient{Insets{inline, block}}

# The dialog owns these partitions; the outer shell delegates its allocation.
def partition(part: Part) -> ContentArea:
  match part:
    case Header{}: ambient(24n, 14n)
    case Body{}: ambient(24n, 20n)
    case Footer{}: ambient(24n, 12n)

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
