import Base
import ./typography.bend as Text
import ../bendlib/stdlib.bend as Std

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

def support_positive(+scale: Text.Scale) ->
  {Nat.is_ge(Text.support_size(scale), 1n) == True{} : Bool}:
  Text.Scale{additional_milli} = scale
  Nat.max_ge_l(1n, Nat.div(Nat.mul(12n, Nat.add(1000n, additional_milli)), 1000n))

def size(value: Text.TextStyle) -> Nat:
  Text.TextStyle{family, size, leading, weight} = value
  size

def leading(value: Text.TextStyle) -> Nat:
  Text.TextStyle{family, size, leading, weight} = value
  leading

def family(value: Text.TextStyle) -> Text.Font:
  Text.TextStyle{family, size, leading, weight} = value
  family

def weight(value: Text.TextStyle) -> Nat:
  Text.TextStyle{family, size, leading, weight} = value
  weight

def body_separation(+scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Nat.is_gt(size(Text.resolve(Text.Body{}, emphasis, scale)), Text.support_size(scale)) == True{} : Bool}:
  separated(Text.support_size(scale), Text.scaled(13n, scale))

def section_separation(+scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Nat.is_gt(size(Text.resolve(Text.Section{}, emphasis, scale)), Text.body_size(scale)) == True{} : Bool}:
  separated(Text.body_size(scale), Text.scaled(14n, scale))

def title_separation(+scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Nat.is_gt(size(Text.resolve(Text.Title{}, emphasis, scale)), Text.section_size(scale)) == True{} : Bool}:
  separated(Text.section_size(scale), Text.scaled(20n, scale))

def display_separation(+scale: Text.Scale, emphasis: Text.Emphasis) ->
  {Nat.is_gt(size(Text.resolve(Text.Display{}, emphasis, scale)), Text.title_size(scale)) == True{} : Bool}:
  separated(Text.title_size(scale), Text.scaled(28n, scale))

def readable_leading(+tier: Text.Tier, emphasis: Text.Emphasis, +scale: Text.Scale) ->
  {Nat.is_ge(leading(Text.resolve(tier, emphasis, scale)), 1n+size(Text.resolve(tier, emphasis, scale))) == True{} : Bool}:
  Nat.max_ge_l(1n+Text.size(tier, scale), Text.scaled(Text.nominal_leading(tier), scale))

def code_size(scale: Text.Scale, emphasis: Text.Emphasis) ->
  {size(Text.resolve(Text.CodeBody{}, emphasis, scale)) == size(Text.resolve(Text.Body{}, emphasis, scale)) : Nat}:
  {==}

def code_leading(scale: Text.Scale, emphasis: Text.Emphasis) ->
  {leading(Text.resolve(Text.CodeBody{}, emphasis, scale)) == leading(Text.resolve(Text.Body{}, emphasis, scale)) : Nat}:
  {==}

def code_support_size(scale: Text.Scale, emphasis: Text.Emphasis) ->
  {size(Text.resolve(Text.CodeSupport{}, emphasis, scale)) == size(Text.resolve(Text.Support{}, emphasis, scale)) : Nat}:
  {==}

def code_support_leading(scale: Text.Scale, emphasis: Text.Emphasis) ->
  {leading(Text.resolve(Text.CodeSupport{}, emphasis, scale)) == leading(Text.resolve(Text.Support{}, emphasis, scale)) : Nat}:
  {==}

def spec_content(value: Text.MeasurementSpec) -> (String & (String & (Maybe<&2, Nat> & String))):
  Text.MeasurementSpec{key, text, family, size, leading, weight, white_space, overflow, word_break, available, reference} = value
  (key, (text, (available, reference)))

def spec_style(value: Text.MeasurementSpec) -> (String & (Nat & (Nat & Nat))):
  Text.MeasurementSpec{key, text, family, size, leading, weight, white_space, overflow, word_break, available, reference} = value
  (family, (size, (leading, weight)))

def spec_wrapping(value: Text.MeasurementSpec) -> (String & (String & String)):
  Text.MeasurementSpec{key, text, family, size, leading, weight, white_space, overflow, word_break, available, reference} = value
  (white_space, (overflow, word_break))

def measurement_content(key: String, text: String, style: Text.TextStyle, wrapping: Text.Wrapping, available: Maybe<&2,Nat>, reference: String) ->
  {spec_content(Text.spec(Text.Probe{key,text,style,wrapping,available,reference})) == (key,(text,(available,reference))) : (String & (String & (Maybe<&2,Nat> & String)))}:
  Text.TextStyle{family,size,leading,weight} = style
  {==}

def measurement_wrapping(key: String, text: String, style: Text.TextStyle, +wrapping: Text.Wrapping, available: Maybe<&2,Nat>, reference: String) ->
  {spec_wrapping(Text.spec(Text.Probe{key,text,style,wrapping,available,reference})) == (Text.white_space(wrapping),(Text.overflow_wrap(wrapping),Text.word_break(wrapping))) : (String & (String & String))}:
  Text.TextStyle{family,size,leading,weight} = style
  {==}

def presentation_tier(value: Text.Presentation) -> Text.Tier:
  Text.Presentation{tier, emphasis, scale} = value
  tier

def presentation_emphasis(value: Text.Presentation) -> Text.Emphasis:
  Text.Presentation{tier, emphasis, scale} = value
  emphasis

def presentation_fields(value: Text.Presentation) -> (Text.Tier & (Text.Emphasis & Text.Scale)):
  Text.Presentation{tier, emphasis, scale} = value
  (tier, (emphasis, scale))

def presentation_parameters(+presentation: Text.Presentation, +new_tier: Text.Tier, +new_emphasis: Text.Emphasis, +new_scale: Text.Scale) ->
  {presentation_fields(Text.with_tier(presentation, new_tier)) == (new_tier, (presentation_emphasis(presentation), Text.presentation_scale(presentation))) : (Text.Tier & (Text.Emphasis & Text.Scale))} &
  {presentation_fields(Text.with_emphasis(presentation, new_emphasis)) == (presentation_tier(presentation), (new_emphasis, Text.presentation_scale(presentation))) : (Text.Tier & (Text.Emphasis & Text.Scale))} &
  {presentation_fields(Text.with_scale(presentation, new_scale)) == (presentation_tier(presentation), (presentation_emphasis(presentation), new_scale)) : (Text.Tier & (Text.Emphasis & Text.Scale))} &
  {Text.resolved(presentation) == Text.resolve(presentation_tier(presentation), presentation_emphasis(presentation), Text.presentation_scale(presentation)) : Text.TextStyle}:
  Text.Presentation{tier, emphasis, scale} = presentation
  ({==}, {==}, {==}, {==})

def admission_goal(P: Type, value: Bool) -> Type:
  match value:
    case False{}: Unit
    case True{}: P

def admission_impossible(P: Type, evidence: {False{} == True{} : Bool}) -> P:
  Std.transport(Bool, False{}, (value => admission_goal(P, value)), Unit{}, True{}, Equal.sym(Bool, False{}, True{}, evidence))

def admitted_flags(+keys: Bool, +widths: Bool, +height: Bool, reference: Bool,
  accepted: {Bool.and(keys, Bool.and(widths, Bool.and(height, reference))) == True{} : Bool}) ->
  {keys == True{} : Bool} & ({widths == True{} : Bool} & {height == True{} : Bool}):
  match keys widths height:
    case False{} widths height: admission_impossible({False{} == True{} : Bool} & ({widths == True{} : Bool} & {height == True{} : Bool}), accepted)
    case True{} False{} height: admission_impossible({True{} == True{} : Bool} & ({False{} == True{} : Bool} & {height == True{} : Bool}), accepted)
    case True{} True{} False{}: admission_impossible({True{} == True{} : Bool} & ({True{} == True{} : Bool} & {False{} == True{} : Bool}), accepted)
    case True{} True{} True{}: ({==}, ({==}, {==}))

def specification_key(value: Text.MeasurementSpec) -> String:
  Text.MeasurementSpec{key, text, family, size, height, weight, space, wrap, word_break, width, reference} = value
  key

def metric_key(value: Text.Metric) -> String:
  Text.Metric{key, minimum, preferred, height, advance} = value
  key

def metric_widths(value: Text.Metric) -> Bool:
  Text.Metric{key, minimum, preferred, height, advance} = value
  Nat.is_le(minimum, preferred)

def metric_height(value: Text.Metric) -> Bool:
  Text.Metric{key, minimum, preferred, height, advance} = value
  Nat.is_gt(height, 0n)

def admitted_metric_boundaries(+specification: Text.MeasurementSpec, +metric: Text.Metric,
  accepted: {Text.valid_metric(specification, metric) == True{} : Bool}) ->
  {String.eq(specification_key(specification), metric_key(metric)) == True{} : Bool} &
    ({metric_widths(metric) == True{} : Bool} & {metric_height(metric) == True{} : Bool}):
  match specification metric:
    case Text.MeasurementSpec{expected_key, text, family, size, line_height, weight, space, wrap, word_break, width, reference} Text.Metric{actual_key, minimum, preferred, height, advance}:
      admitted_flags(String.eq(expected_key, actual_key), Nat.is_le(minimum, preferred), Nat.is_gt(height, 0n), Bool.or(String.eq(reference, ""), Nat.is_gt(advance, 0n)), accepted)

type Requirements is Type:
  Requirements{
    metric_admission: @+specification:Text.MeasurementSpec -> @+metric:Text.Metric -> @accepted:{Text.valid_metric(specification, metric) == True{} : Bool} ->
      {String.eq(specification_key(specification), metric_key(metric)) == True{} : Bool} & ({metric_widths(metric) == True{} : Bool} & {metric_height(metric) == True{} : Bool}),
    normal_anywhere: {(Text.white_space(Text.NormalAnywhere{}), (Text.overflow_wrap(Text.NormalAnywhere{}), Text.word_break(Text.NormalAnywhere{}))) == ("normal", ("anywhere", "normal")) : (String & (String & String))},
    normal_words: {(Text.white_space(Text.NormalWords{}), (Text.overflow_wrap(Text.NormalWords{}), Text.word_break(Text.NormalWords{}))) == ("normal", ("normal", "normal")) : (String & (String & String))},
    presentation_parameters: @+presentation:Text.Presentation -> @+new_tier:Text.Tier -> @+new_emphasis:Text.Emphasis -> @+new_scale:Text.Scale ->
      {presentation_fields(Text.with_tier(presentation, new_tier)) == (new_tier, (presentation_emphasis(presentation), Text.presentation_scale(presentation))) : (Text.Tier & (Text.Emphasis & Text.Scale))} &
      {presentation_fields(Text.with_emphasis(presentation, new_emphasis)) == (presentation_tier(presentation), (new_emphasis, Text.presentation_scale(presentation))) : (Text.Tier & (Text.Emphasis & Text.Scale))} &
      {presentation_fields(Text.with_scale(presentation, new_scale)) == (presentation_tier(presentation), (presentation_emphasis(presentation), new_scale)) : (Text.Tier & (Text.Emphasis & Text.Scale))} &
      {Text.resolved(presentation) == Text.resolve(presentation_tier(presentation), presentation_emphasis(presentation), Text.presentation_scale(presentation)) : Text.TextStyle},
    support_is_positive: @+scale:Text.Scale ->
      {Nat.is_ge(Text.support_size(scale), 1n) == True{} : Bool},
    body_separation: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Nat.is_gt(size(Text.resolve(Text.Body{}, emphasis, scale)), Text.support_size(scale)) == True{} : Bool},
    section_separation: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Nat.is_gt(size(Text.resolve(Text.Section{}, emphasis, scale)), Text.body_size(scale)) == True{} : Bool},
    title_separation: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Nat.is_gt(size(Text.resolve(Text.Title{}, emphasis, scale)), Text.section_size(scale)) == True{} : Bool},
    display_separation: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Nat.is_gt(size(Text.resolve(Text.Display{}, emphasis, scale)), Text.title_size(scale)) == True{} : Bool},
    readable_leading: @tier:Text.Tier -> @emphasis:Text.Emphasis -> @scale:Text.Scale ->
      {Nat.is_ge(leading(Text.resolve(tier, emphasis, scale)), 1n+size(Text.resolve(tier, emphasis, scale))) == True{} : Bool},
    prominence_is_independent: @tier:Text.Tier -> @emphasis:Text.Emphasis -> @scale:Text.Scale ->
      {weight(Text.resolve(tier, emphasis, scale)) == Text.weight(emphasis) : Nat},
    family_is_tier_owned: @tier:Text.Tier -> @emphasis:Text.Emphasis -> @scale:Text.Scale ->
      {family(Text.resolve(tier, emphasis, scale)) == Text.font(tier) : Text.Font},
    emphasis_preserves_size: @+tier:Text.Tier -> @first:Text.Emphasis -> @second:Text.Emphasis -> @+scale:Text.Scale ->
      {size(Text.resolve(tier, first, scale)) == size(Text.resolve(tier, second, scale)) : Nat},
    emphasis_preserves_leading: @+tier:Text.Tier -> @first:Text.Emphasis -> @second:Text.Emphasis -> @+scale:Text.Scale ->
      {leading(Text.resolve(tier, first, scale)) == leading(Text.resolve(tier, second, scale)) : Nat},
    regular_prominence: @tier:Text.Tier -> @scale:Text.Scale ->
      {weight(Text.resolve(tier, Text.Regular{}, scale)) == 400n : Nat},
    medium_prominence: @tier:Text.Tier -> @scale:Text.Scale ->
      {weight(Text.resolve(tier, Text.Medium{}, scale)) == 500n : Nat},
    strong_prominence: @tier:Text.Tier -> @scale:Text.Scale ->
      {weight(Text.resolve(tier, Text.Strong{}, scale)) == 600n : Nat},
    code_body_font: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {family(Text.resolve(Text.CodeBody{}, emphasis, scale)) == Text.MonospaceFont{} : Text.Font},
    code_support_font: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {family(Text.resolve(Text.CodeSupport{}, emphasis, scale)) == Text.MonospaceFont{} : Text.Font},
    code_body_size: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {size(Text.resolve(Text.CodeBody{}, emphasis, scale)) == size(Text.resolve(Text.Body{}, emphasis, scale)) : Nat},
    code_body_leading: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {leading(Text.resolve(Text.CodeBody{}, emphasis, scale)) == leading(Text.resolve(Text.Body{}, emphasis, scale)) : Nat},
    code_support_size: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {size(Text.resolve(Text.CodeSupport{}, emphasis, scale)) == size(Text.resolve(Text.Support{}, emphasis, scale)) : Nat},
    code_support_leading: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {leading(Text.resolve(Text.CodeSupport{}, emphasis, scale)) == leading(Text.resolve(Text.Support{}, emphasis, scale)) : Nat},
    interface_family: {Text.font_family(Text.InterfaceFont{}) == "var(--font-sans, system-ui)" : String},
    code_family: {Text.font_family(Text.MonospaceFont{}) == "var(--font-mono, monospace)" : String},
    measurement_content: @key:String -> @text:String -> @style:Text.TextStyle -> @wrapping:Text.Wrapping -> @available:Maybe<&2,Nat> -> @reference:String ->
      {spec_content(Text.spec(Text.Probe{key,text,style,wrapping,available,reference})) == (key,(text,(available,reference))) : (String & (String & (Maybe<&2,Nat> & String)))},
    measurement_style: @key:String -> @text:String -> @family:Text.Font -> @size:Nat -> @leading:Nat -> @weight:Nat -> @wrapping:Text.Wrapping -> @available:Maybe<&2,Nat> -> @reference:String ->
      {spec_style(Text.spec(Text.Probe{key,text,Text.TextStyle{family,size,leading,weight},wrapping,available,reference})) == (Text.font_family(family),(size,(leading,weight))) : (String & (Nat & (Nat & Nat)))},
    measurement_wrapping: @key:String -> @text:String -> @style:Text.TextStyle -> @+wrapping:Text.Wrapping -> @available:Maybe<&2,Nat> -> @reference:String ->
      {spec_wrapping(Text.spec(Text.Probe{key,text,style,wrapping,available,reference})) == (Text.white_space(wrapping),(Text.overflow_wrap(wrapping),Text.word_break(wrapping))) : (String & (String & String))},
    reading_uses_observed_advance: @advance:Nat -> @columns:Nat ->
      {Text.reading_width(advance, columns) == Nat.mul(advance, columns) : Nat}
  }

def evidence() -> Requirements:
  Requirements{admitted_metric_boundaries, {==}, {==},
    presentation_parameters,
    support_positive,
    scale => emphasis => body_separation(scale, emphasis),
    scale => emphasis => section_separation(scale, emphasis),
    scale => emphasis => title_separation(scale, emphasis),
    scale => emphasis => display_separation(scale, emphasis),
    tier => emphasis => scale => readable_leading(tier, emphasis, scale),
    tier => emphasis => scale => {==}, tier => emphasis => scale => {==},
    +tier => first => second => +scale => {==},
    +tier => first => second => +scale => {==},
    tier => scale => {==}, tier => scale => {==}, tier => scale => {==},
    scale => emphasis => {==}, scale => emphasis => {==},
    code_size, code_leading, code_support_size, code_support_leading,
    {==}, {==},
    measurement_content,
    key => text => family => size => leading => weight => wrapping => available => reference => {==},
    measurement_wrapping,
    advance => columns => {==}}
