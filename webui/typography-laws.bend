import Base
import ./typography.bend as Text

def spec_content(value: Text.MeasurementSpec) -> (String & (String & (Maybe<&2, Nat> & String))):
  Text.MeasurementSpec{key, text, family, size, leading, weight, white_space, overflow, word_break, available, reference} = value
  (key, (text, (available, reference)))

def spec_style(value: Text.MeasurementSpec) -> (String & (Nat & (Nat & Nat))):
  Text.MeasurementSpec{key, text, family, size, leading, weight, white_space, overflow, word_break, available, reference} = value
  (family, (size, (leading, weight)))

def spec_wrapping(value: Text.MeasurementSpec) -> (String & (String & String)):
  Text.MeasurementSpec{key, text, family, size, leading, weight, white_space, overflow, word_break, available, reference} = value
  (white_space, (overflow, word_break))

def presentation_tier(value: Text.Presentation) -> Text.Tier:
  Text.Presentation{tier, emphasis, scale} = value
  tier

def presentation_emphasis(value: Text.Presentation) -> Text.Emphasis:
  Text.Presentation{tier, emphasis, scale} = value
  emphasis

def presentation_fields(value: Text.Presentation) -> (Text.Tier & (Text.Emphasis & Text.Scale)):
  Text.Presentation{tier, emphasis, scale} = value
  (tier, (emphasis, scale))

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
      {Nat.is_gt(Text.resolved_size(Text.resolve(Text.Body{}, emphasis, scale)), Text.support_size(scale)) == True{} : Bool},
    section_separation: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Nat.is_gt(Text.resolved_size(Text.resolve(Text.Section{}, emphasis, scale)), Text.body_size(scale)) == True{} : Bool},
    title_separation: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Nat.is_gt(Text.resolved_size(Text.resolve(Text.Title{}, emphasis, scale)), Text.section_size(scale)) == True{} : Bool},
    display_separation: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Nat.is_gt(Text.resolved_size(Text.resolve(Text.Display{}, emphasis, scale)), Text.title_size(scale)) == True{} : Bool},
    readable_leading: @tier:Text.Tier -> @emphasis:Text.Emphasis -> @scale:Text.Scale ->
      {Nat.is_ge(Text.resolved_line_height(Text.resolve(tier, emphasis, scale)), 1n+Text.resolved_size(Text.resolve(tier, emphasis, scale))) == True{} : Bool},
    prominence_is_independent: @tier:Text.Tier -> @emphasis:Text.Emphasis -> @scale:Text.Scale ->
      {Text.resolved_weight(Text.resolve(tier, emphasis, scale)) == Text.weight(emphasis) : Nat},
    family_is_tier_owned: @tier:Text.Tier -> @emphasis:Text.Emphasis -> @scale:Text.Scale ->
      {Text.resolved_font(Text.resolve(tier, emphasis, scale)) == Text.font(tier) : Text.Font},
    emphasis_preserves_size: @+tier:Text.Tier -> @first:Text.Emphasis -> @second:Text.Emphasis -> @+scale:Text.Scale ->
      {Text.resolved_size(Text.resolve(tier, first, scale)) == Text.resolved_size(Text.resolve(tier, second, scale)) : Nat},
    emphasis_preserves_leading: @+tier:Text.Tier -> @first:Text.Emphasis -> @second:Text.Emphasis -> @+scale:Text.Scale ->
      {Text.resolved_line_height(Text.resolve(tier, first, scale)) == Text.resolved_line_height(Text.resolve(tier, second, scale)) : Nat},
    regular_prominence: @tier:Text.Tier -> @scale:Text.Scale ->
      {Text.resolved_weight(Text.resolve(tier, Text.Regular{}, scale)) == 400n : Nat},
    medium_prominence: @tier:Text.Tier -> @scale:Text.Scale ->
      {Text.resolved_weight(Text.resolve(tier, Text.Medium{}, scale)) == 500n : Nat},
    strong_prominence: @tier:Text.Tier -> @scale:Text.Scale ->
      {Text.resolved_weight(Text.resolve(tier, Text.Strong{}, scale)) == 600n : Nat},
    code_body_font: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Text.resolved_font(Text.resolve(Text.CodeBody{}, emphasis, scale)) == Text.MonospaceFont{} : Text.Font},
    code_support_font: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Text.resolved_font(Text.resolve(Text.CodeSupport{}, emphasis, scale)) == Text.MonospaceFont{} : Text.Font},
    code_body_size: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Text.resolved_size(Text.resolve(Text.CodeBody{}, emphasis, scale)) == Text.resolved_size(Text.resolve(Text.Body{}, emphasis, scale)) : Nat},
    code_body_leading: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Text.resolved_line_height(Text.resolve(Text.CodeBody{}, emphasis, scale)) == Text.resolved_line_height(Text.resolve(Text.Body{}, emphasis, scale)) : Nat},
    code_support_size: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Text.resolved_size(Text.resolve(Text.CodeSupport{}, emphasis, scale)) == Text.resolved_size(Text.resolve(Text.Support{}, emphasis, scale)) : Nat},
    code_support_leading: @scale:Text.Scale -> @emphasis:Text.Emphasis ->
      {Text.resolved_line_height(Text.resolve(Text.CodeSupport{}, emphasis, scale)) == Text.resolved_line_height(Text.resolve(Text.Support{}, emphasis, scale)) : Nat},
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

law evidence:
  Requirements
