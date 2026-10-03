import Base

# One scale constructs adjacent text sizes; prominence remains independent.
type Font is Data:
  InterfaceFont{}
  MonospaceFont{}

type TextStyle is Data:
  TextStyle{font: Font, size: Nat, line_height: Nat, weight: Nat}

type Scale is Data:
  Scale{additional_milli: Nat}

type Tier is Data:
  Display{}
  Title{}
  Section{}
  Body{}
  Support{}
  CodeBody{}
  CodeSupport{}

type Emphasis is Data:
  Regular{}
  Medium{}
  Strong{}

def default_emphasis(tier: Tier) -> Emphasis:
  match tier:
    case Display{}: Medium{}
    case Title{}: Strong{}
    case Section{}: Medium{}
    case _: Regular{}

def scaled(nominal: Nat, scale: Scale) -> Nat:
  Scale{additional_milli} = scale
  Nat.max(1n, Nat.div(Nat.mul(nominal, Nat.add(1000n, additional_milli)), 1000n))

def support_size(scale: Scale) -> Nat:
  scaled(12n, scale)

def body_size(+scale: Scale) -> Nat:
  Nat.max(1n+support_size(scale), scaled(13n, scale))

def section_size(+scale: Scale) -> Nat:
  Nat.max(1n+body_size(scale), scaled(14n, scale))

def title_size(+scale: Scale) -> Nat:
  Nat.max(1n+section_size(scale), scaled(20n, scale))

def display_size(+scale: Scale) -> Nat:
  Nat.max(1n+title_size(scale), scaled(28n, scale))

def size(tier: Tier, scale: Scale) -> Nat:
  match tier:
    case Display{}: display_size(scale)
    case Title{}: title_size(scale)
    case Section{}: section_size(scale)
    case Body{}: body_size(scale)
    case Support{}: support_size(scale)
    case CodeBody{}: body_size(scale)
    case CodeSupport{}: support_size(scale)

def nominal_leading(tier: Tier) -> Nat:
  match tier:
    case Display{}: 36n
    case Title{}: 28n
    case Section{}: 20n
    case Body{}: 20n
    case Support{}: 18n
    case CodeBody{}: 20n
    case CodeSupport{}: 18n

def font(tier: Tier) -> Font:
  match tier:
    case CodeBody{}: MonospaceFont{}
    case CodeSupport{}: MonospaceFont{}
    case _: InterfaceFont{}

def weight(emphasis: Emphasis) -> Nat:
  match emphasis:
    case Regular{}: 400n
    case Medium{}: 500n
    case Strong{}: 600n

def resolve(+tier: Tier, emphasis: Emphasis, +scale: Scale) -> TextStyle:
  +text_size = size(tier, scale)
  TextStyle{font(tier), text_size, Nat.max(1n+text_size, scaled(nominal_leading(tier), scale)), weight(emphasis)}

# Styles retain semantic intent until rendering and measurement resolve it.
type Presentation is Data:
  Presentation{tier: Tier, emphasis: Emphasis, scale: Scale}

def resolved(value: Presentation) -> TextStyle:
  Presentation{tier, emphasis, scale} = value
  resolve(tier, emphasis, scale)

def with_tier(value: Presentation, tier: Tier) -> Presentation:
  Presentation{old_tier, emphasis, scale} = value
  Presentation{tier, emphasis, scale}

def with_emphasis(value: Presentation, emphasis: Emphasis) -> Presentation:
  Presentation{tier, old_emphasis, scale} = value
  Presentation{tier, emphasis, scale}

def with_scale(value: Presentation, scale: Scale) -> Presentation:
  Presentation{tier, emphasis, old_scale} = value
  Presentation{tier, emphasis, scale}

def presentation_scale(value: Presentation) -> Scale:
  Presentation{tier, emphasis, scale} = value
  scale

def font_family(value: Font) -> String:
  match value:
    case InterfaceFont{}: "var(--font-sans, system-ui)"
    case MonospaceFont{}: "var(--font-mono, monospace)"

type Wrapping is Data:
  SingleLine{}
  WrapAnywhere{}
  WrapWords{}
  ScrollableCode{}

def white_space(value: Wrapping) -> String:
  match value:
    case SingleLine{}: "nowrap"
    case WrapAnywhere{}: "pre-wrap"
    case WrapWords{}: "pre-wrap"
    case ScrollableCode{}: "pre"

def overflow_wrap(value: Wrapping) -> String:
  match value:
    case WrapAnywhere{}: "anywhere"
    case _: "normal"

def word_break(value: Wrapping) -> String:
  "normal"

# A generation batches actual text probes; foreign measurements are observations.
type Probe is Data:
  Probe{key: String, text: String, style: TextStyle, wrapping: Wrapping,
    available_width: Maybe<&2, Nat>, reference_text: String}

type Metric is Data:
  Metric{key: String, minimum_width: Nat, preferred_width: Nat,
    constrained_height: Nat, reference_advance: Nat}

type MeasurementSpec is Data:
  MeasurementSpec{key: String, text: String, font_family: String,
    font_size: Nat, line_height: Nat, font_weight: Nat, white_space: String,
    overflow_wrap: String, word_break: String, available_width: Maybe<&2, Nat>,
    reference_text: String}

def spec(value: Probe) -> MeasurementSpec:
  Probe{key, text, TextStyle{family, size, line_height, weight}, +wrapping, available_width, reference_text} = value
  MeasurementSpec{key, text, font_family(family), size, line_height, weight,
    white_space(wrapping), overflow_wrap(wrapping), word_break(wrapping), available_width, reference_text}

def body_probe(scale: Scale) -> Probe:
  Probe{"@font/body", "0", resolve(Body{}, Regular{}, scale), WrapWords{}, None{}, "0"}

def body_spec(scale: Scale) -> MeasurementSpec:
  spec(body_probe(scale))

def valid_body(metric: Metric) -> Bool:
  Metric{key, minimum, preferred, height, advance} = metric
  String.eq(key, "@font/body") && (Nat.is_le(minimum, preferred) &&
    (Nat.is_gt(height, 0n) && Nat.is_gt(advance, 0n)))

def reading_width(reference_advance: Nat, columns: Nat) -> Nat:
  Nat.mul(reference_advance, columns)
