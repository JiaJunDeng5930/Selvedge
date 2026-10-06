import Base
import ../../bendlib/proofs/logic.bend as Logic
import ../typography-laws.bend as Rule
import ../typography.bend as Text
import ../natural-size.bend as NaturalSize

def successor_zero(rest: Nat) ->
  {True{} == Nat.is_ge(rest, 0n) : Bool}:
  match rest:
    case 0n: {==}
    case 1n+tail: {==}

# The successor lower bound constructs separation despite integer scale rounding.

def strict_successor(+upper: Nat, +lower: Nat) ->
  {Nat.is_gt(upper, lower) == Nat.is_ge(upper, 1n+lower) : Bool}:
  match upper lower:
    case 0n 0n: {==}
    case 0n 1n+rest: {==}
    case 1n+rest 0n: successor_zero(rest)
    case 1n+left 1n+right: strict_successor(left, right)

def separated(+lower: Nat, +nominal: Nat) ->
  {Nat.is_gt(Nat.max(1n+lower, nominal), lower) == True{} : Bool}:
  Equal.trans(Bool, Nat.is_gt(Nat.max(1n+lower, nominal), lower),
    Nat.is_ge(Nat.max(1n+lower, nominal), 1n+lower), True{},
    strict_successor(Nat.max(1n+lower, nominal), lower), Nat.max_ge_l(1n+lower, nominal))

def positive_clamp(+value: Nat) ->
  {Text.positive(value) == Nat.max(1n, value) : Nat}:
  {==}

def scaled_positive(+capacity: Nat, +nominal: Nat, +scale: Text.Scale) ->
  {Nat.is_ge(Text.scaled(capacity, nominal, scale), 1n) == True{} : Bool}:
  Nat.max_ge_l(1n, NaturalSize.saturated(capacity, NaturalSize.evaluate(capacity, Text.scaling_calculation(nominal, scale))))

def support_positive(+capacity: Nat, +scale: Text.Scale) ->
  {Nat.is_ge(Text.support_size(capacity, scale), 1n) == True{} : Bool}:
  scaled_positive(capacity, 12n, scale)

def body_separation(+capacity: Nat, +scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Nat.is_gt(Text.resolved_size(Text.resolve(capacity, Text.Body{}, emphasis, scale)), Text.support_size(capacity, scale)) == True{} : Bool}:
  separated(Text.support_size(capacity, scale), Text.scaled(capacity, 13n, scale))

def section_separation(+capacity: Nat, +scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Nat.is_gt(Text.resolved_size(Text.resolve(capacity, Text.Section{}, emphasis, scale)), Text.body_size(capacity, scale)) == True{} : Bool}:
  separated(Text.body_size(capacity, scale), Text.scaled(capacity, 14n, scale))

def title_separation(+capacity: Nat, +scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Nat.is_gt(Text.resolved_size(Text.resolve(capacity, Text.Title{}, emphasis, scale)), Text.section_size(capacity, scale)) == True{} : Bool}:
  separated(Text.section_size(capacity, scale), Text.scaled(capacity, 20n, scale))

def display_separation(+capacity: Nat, +scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Nat.is_gt(Text.resolved_size(Text.resolve(capacity, Text.Display{}, emphasis, scale)), Text.title_size(capacity, scale)) == True{} : Bool}:
  separated(Text.title_size(capacity, scale), Text.scaled(capacity, 28n, scale))

def readable_leading(+capacity: Nat, +tier: Text.Tier, emphasis: Text.Emphasis, +scale: Text.Scale) ->
  {Nat.is_ge(Text.resolved_line_height(Text.resolve(capacity, tier, emphasis, scale)), 1n+Text.resolved_size(Text.resolve(capacity, tier, emphasis, scale))) == True{} : Bool}:
  Nat.max_ge_l(1n+Text.size(capacity, tier, scale), Text.scaled(capacity, Text.nominal_leading(tier), scale))

def code_size(+capacity: Nat, scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Text.resolved_size(Text.resolve(capacity, Text.CodeBody{}, emphasis, scale)) == Text.resolved_size(Text.resolve(capacity, Text.Body{}, emphasis, scale)) : Nat}:
  {==}

def code_leading(+capacity: Nat, scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Text.resolved_line_height(Text.resolve(capacity, Text.CodeBody{}, emphasis, scale)) == Text.resolved_line_height(Text.resolve(capacity, Text.Body{}, emphasis, scale)) : Nat}:
  {==}

def code_support_size(+capacity: Nat, scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Text.resolved_size(Text.resolve(capacity, Text.CodeSupport{}, emphasis, scale)) == Text.resolved_size(Text.resolve(capacity, Text.Support{}, emphasis, scale)) : Nat}:
  {==}

def code_support_leading(+capacity: Nat, scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Text.resolved_line_height(Text.resolve(capacity, Text.CodeSupport{}, emphasis, scale)) == Text.resolved_line_height(Text.resolve(capacity, Text.Support{}, emphasis, scale)) : Nat}:
  {==}

def measurement_content(key: String, text: String, style: Text.TextStyle, wrapping: Text.Wrapping, available: Maybe<&2,Nat>, reference: String) ->
  {Rule.spec_content(Text.spec(Text.Probe{key,text,style,wrapping,available,reference})) == (key,(text,(available,reference))) : (String & (String & (Maybe<&2,Nat> & String)))}:
  Text.TextStyle{family,size,leading,weight} = style
  {==}

def measurement_wrapping(key: String, text: String, style: Text.TextStyle, +wrapping: Text.Wrapping, available: Maybe<&2,Nat>, reference: String) ->
  {Rule.spec_wrapping(Text.spec(Text.Probe{key,text,style,wrapping,available,reference})) == (Text.white_space(wrapping),(Text.overflow_wrap(wrapping),Text.word_break(wrapping))) : (String & (String & String))}:
  Text.TextStyle{family,size,leading,weight} = style
  {==}

def presentation_parameters(+capacity: Nat, +presentation: Text.Presentation, +new_tier: Text.Tier, +new_emphasis: Text.Emphasis, +new_scale: Text.Scale) ->
  {Rule.presentation_fields(Text.with_tier(presentation, new_tier)) == (new_tier, (Rule.presentation_emphasis(presentation), Text.presentation_scale(presentation))) : (Text.Tier & (Text.Emphasis & Text.Scale))} &
  {Rule.presentation_fields(Text.with_emphasis(presentation, new_emphasis)) == (Rule.presentation_tier(presentation), (new_emphasis, Text.presentation_scale(presentation))) : (Text.Tier & (Text.Emphasis & Text.Scale))} &
  {Rule.presentation_fields(Text.with_scale(presentation, new_scale)) == (Rule.presentation_tier(presentation), (Rule.presentation_emphasis(presentation), new_scale)) : (Text.Tier & (Text.Emphasis & Text.Scale))} &
  {Text.resolve_presentation(capacity, presentation) == Text.resolve(capacity, Rule.presentation_tier(presentation), Rule.presentation_emphasis(presentation), Text.presentation_scale(presentation)) : Text.TextStyle}:
  Text.Presentation{tier, emphasis, scale} = presentation
  ({==}, {==}, {==}, {==})

def admitted_flags(+keys: Bool, +widths: Bool, +height: Bool, reference: Bool,
  accepted: {Bool.and(keys, Bool.and(widths, Bool.and(height, reference))) == True{} : Bool}) ->
  {keys == True{} : Bool} & ({widths == True{} : Bool} & {height == True{} : Bool}):
  match keys widths height:
    case False{} widths height: Logic.impossible({False{} == True{} : Bool} & ({widths == True{} : Bool} & {height == True{} : Bool}), accepted)
    case True{} False{} height: Logic.impossible({True{} == True{} : Bool} & ({False{} == True{} : Bool} & {height == True{} : Bool}), accepted)
    case True{} True{} False{}: Logic.impossible({True{} == True{} : Bool} & ({True{} == True{} : Bool} & {False{} == True{} : Bool}), accepted)
    case True{} True{} True{}: ({==}, ({==}, {==}))

def admitted_metric_boundaries(+specification: Text.MeasurementSpec, +metric: Text.Metric,
  accepted: {Text.valid_metric(specification, metric) == True{} : Bool}) ->
  {String.eq(Rule.specification_key(specification), Rule.metric_key(metric)) == True{} : Bool} &
    ({Rule.metric_widths(metric) == True{} : Bool} & {Rule.metric_height(metric) == True{} : Bool}):
  match specification metric:
    case Text.MeasurementSpec{expected_key, text, family, size, line_height, weight, space, wrap, word_break, width, reference} Text.Metric{actual_key, minimum, preferred, height, advance}:
      admitted_flags(String.eq(expected_key, actual_key), Nat.is_le(minimum, preferred), Nat.is_gt(height, 0n), Bool.or(String.eq(reference, ""), Nat.is_gt(advance, 0n)), accepted)

def Rule.evidence():
  Rule.Requirements{admitted_metric_boundaries, {==}, {==},
    presentation_parameters,
    positive_clamp,
    support_positive,
    +capacity => scale => emphasis => body_separation(capacity, scale, emphasis),
    +capacity => scale => emphasis => section_separation(capacity, scale, emphasis),
    +capacity => scale => emphasis => title_separation(capacity, scale, emphasis),
    +capacity => scale => emphasis => display_separation(capacity, scale, emphasis),
    +capacity => tier => emphasis => scale => readable_leading(capacity, tier, emphasis, scale),
    +capacity => tier => emphasis => scale => {==}, +capacity => tier => emphasis => scale => {==},
    +capacity => +tier => first => second => +scale => {==},
    +capacity => +tier => first => second => +scale => {==},
    +capacity => tier => scale => {==}, +capacity => tier => scale => {==}, +capacity => tier => scale => {==},
    +capacity => scale => emphasis => {==}, +capacity => scale => emphasis => {==},
    code_size, code_leading, code_support_size, code_support_leading,
    {==}, {==},
    measurement_content,
    key => text => family => size => leading => weight => wrapping => available => reference => {==},
    measurement_wrapping,
    advance => columns => {==},
    +capacity => scale => {==}}
