import Base
import ./natural-size.bend as NaturalSize

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

# Splitting the scale avoids an overflowing product before division.
def scaling_calculation(+nominal: Nat, scale: Scale) -> NaturalSize.Calculation:
  Scale{+additional_milli} = scale
  +whole: NaturalSize.Calculation = NaturalSize.Quotient{NaturalSize.Value{additional_milli}, NaturalSize.Value{1000n}}
  +fraction: NaturalSize.Calculation = NaturalSize.Remainder{NaturalSize.Value{additional_milli}, NaturalSize.Value{1000n}}
  NaturalSize.Sum{NaturalSize.Sum{NaturalSize.Value{nominal},
    NaturalSize.Product{NaturalSize.Value{nominal}, whole}},
    NaturalSize.Sum{NaturalSize.Product{NaturalSize.Quotient{NaturalSize.Value{nominal}, NaturalSize.Value{1000n}}, fraction},
      NaturalSize.Quotient{NaturalSize.Product{NaturalSize.Remainder{NaturalSize.Value{nominal}, NaturalSize.Value{1000n}}, fraction}, NaturalSize.Value{1000n}}}}

def positive(value: Nat) -> Nat:
  Nat.max(1n, value)

def scaled(+capacity: Nat, nominal: Nat, scale: Scale) -> Nat:
  positive(NaturalSize.saturated(capacity, NaturalSize.evaluate(capacity, scaling_calculation(nominal, scale))))

def support_size(+capacity: Nat, scale: Scale) -> Nat:
  scaled(capacity, 12n, scale)

def body_size(+capacity: Nat, +scale: Scale) -> Nat:
  Nat.max(1n+support_size(capacity, scale), scaled(capacity, 13n, scale))

def section_size(+capacity: Nat, +scale: Scale) -> Nat:
  Nat.max(1n+body_size(capacity, scale), scaled(capacity, 14n, scale))

def title_size(+capacity: Nat, +scale: Scale) -> Nat:
  Nat.max(1n+section_size(capacity, scale), scaled(capacity, 20n, scale))

def display_size(+capacity: Nat, +scale: Scale) -> Nat:
  Nat.max(1n+title_size(capacity, scale), scaled(capacity, 28n, scale))

def size(+capacity: Nat, tier: Tier, scale: Scale) -> Nat:
  match tier:
    case Display{}: display_size(capacity, scale)
    case Title{}: title_size(capacity, scale)
    case Section{}: section_size(capacity, scale)
    case Body{}: body_size(capacity, scale)
    case Support{}: support_size(capacity, scale)
    case CodeBody{}: body_size(capacity, scale)
    case CodeSupport{}: support_size(capacity, scale)

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

def resolve(+capacity: Nat, +tier: Tier, emphasis: Emphasis, +scale: Scale) -> TextStyle:
  +text_size: Nat = size(capacity, tier, scale)
  TextStyle{font(tier), text_size, Nat.max(1n+text_size, scaled(capacity, nominal_leading(tier), scale)), weight(emphasis)}

# Styles retain semantic intent until rendering and measurement resolve it.
type Presentation is Data:
  Presentation{tier: Tier, emphasis: Emphasis, scale: Scale}

def resolve_presentation(capacity: Nat, value: Presentation) -> TextStyle:
  Presentation{tier, emphasis, scale} = value
  resolve(capacity, tier, emphasis, scale)

def resolved(value: Presentation) -> TextStyle:
  resolve_presentation(NaturalSize.limit(), value)

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

def supporting(value: Presentation) -> Presentation:
  Presentation{tier, emphasis, scale} = value
  Presentation{Support{}, Regular{}, scale}

def font_family(value: Font) -> String:
  match value:
    case InterfaceFont{}: "var(--font-sans, system-ui)"
    case MonospaceFont{}: "var(--font-mono, monospace)"

type Wrapping is Data:
  SingleLine{}
  UnbrokenLine{}
  WrapAnywhere{}
  WrapWords{}
  ScrollableCode{}
  NormalAnywhere{}
  NormalWords{}

def white_space(value: Wrapping) -> String:
  match value:
    case SingleLine{}: "nowrap"
    case UnbrokenLine{}: "nowrap"
    case WrapAnywhere{}: "pre-wrap"
    case WrapWords{}: "pre-wrap"
    case ScrollableCode{}: "pre"
    case NormalAnywhere{}: "normal"
    case NormalWords{}: "normal"

def overflow_wrap(value: Wrapping) -> String:
  match value:
    case WrapAnywhere{}: "anywhere"
    case NormalAnywhere{}: "anywhere"
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

type Measured is Data:
  Measured{specification: MeasurementSpec, metric: Metric}

def same_width(first: Maybe<&2, Nat>, second: Maybe<&2, Nat>) -> Bool:
  match first second:
    case None{} None{}: True{}
    case Some{first} Some{second}: Nat.is_eq(first, second)
    case _ _: False{}

def same_spec(first: MeasurementSpec, second: MeasurementSpec) -> Bool:
  match first second:
    case MeasurementSpec{first_key, first_text, first_family, first_size, first_height, first_weight, first_space, first_wrap, first_break, first_width, first_reference} MeasurementSpec{second_key, second_text, second_family, second_size, second_height, second_weight, second_space, second_wrap, second_break, second_width, second_reference}:
      Bool.and(String.eq(first_key, second_key),
        Bool.and(String.eq(first_text, second_text),
          Bool.and(String.eq(first_family, second_family),
            Bool.and(Nat.is_eq(first_size, second_size),
              Bool.and(Nat.is_eq(first_height, second_height),
                Bool.and(Nat.is_eq(first_weight, second_weight),
                  Bool.and(String.eq(first_space, second_space),
                    Bool.and(String.eq(first_wrap, second_wrap),
                      Bool.and(String.eq(first_break, second_break),
                        Bool.and(same_width(first_width, second_width), String.eq(first_reference, second_reference)))))))))))

# Admission checks external data; they do not establish physical measurement accuracy.
def metric_admission(expected_key: String, reference: String, metric: Metric) -> Bool:
  Metric{actual_key, minimum, preferred, height, advance} = metric
  Bool.and(String.eq(expected_key, actual_key),
    Bool.and(Nat.is_le(minimum, preferred),
      Bool.and(Nat.is_gt(height, 0n), Bool.or(String.eq(reference, ""), Nat.is_gt(advance, 0n)))))

def valid_metric(specification: MeasurementSpec, metric: Metric) -> Bool:
  MeasurementSpec{expected_key, text, family, size, line_height, weight, space, wrap, word_break, width, reference} = specification
  metric_admission(expected_key, reference, metric)

def spec(value: Probe) -> MeasurementSpec:
  Probe{key, text, TextStyle{family, size, line_height, weight}, +wrapping, available_width, reference_text} = value
  MeasurementSpec{key, text, font_family(family), size, line_height, weight,
    white_space(wrapping), overflow_wrap(wrapping), word_break(wrapping), available_width, reference_text}

def body_probe_at(capacity: Nat, scale: Scale) -> Probe:
  Probe{"@font/body", "0", resolve_presentation(capacity, Presentation{Body{}, Regular{}, scale}), WrapWords{}, None{}, "0"}

def body_probe(scale: Scale) -> Probe:
  body_probe_at(NaturalSize.limit(), scale)

def body_spec_at(capacity: Nat, scale: Scale) -> MeasurementSpec:
  spec(body_probe_at(capacity, scale))

def body_spec(scale: Scale) -> MeasurementSpec:
  body_spec_at(NaturalSize.limit(), scale)

def valid_body(metric: Metric) -> Bool:
  metric_admission("@font/body", "0", metric)

def reading_width(reference_advance: Nat, columns: Nat) -> Nat:
  Nat.mul(reference_advance, columns)

def resolved_line_height(style: TextStyle) -> Nat:
  TextStyle{font, size, height, weight} = style
  height

def resolved_size(value: TextStyle) -> Nat:
  TextStyle{family, size, line_height, weight} = value
  size

def resolved_font(value: TextStyle) -> Font:
  TextStyle{family, size, line_height, weight} = value
  family

def resolved_weight(value: TextStyle) -> Nat:
  TextStyle{family, size, line_height, weight} = value
  weight
