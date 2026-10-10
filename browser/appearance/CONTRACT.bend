import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../layout/GEOMETRY.bend as SpatialModel
import ./TYPOGRAPHY.bend as T
import ../layout/enclosure.bend as Enclosure
import ../../interaction/services/MODEL.bend as Services
import ./DESIGN.bend as Design
import ../controls/SURFACES.bend as Surfaces
import ./MODEL.bend as Appearance
import ../controls/PROGRAM.bend as Controls
import ../../interaction/INPUT.bend as U
import ../../interaction/submission/FIELDS.bend as Forms
import ../../features/board/MODEL.bend as Board
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/TYPES.bend as InteractionTypes
import ./FONT.bend as F
import ./PROGRAM.bend as Paint
import ../document/MODEL.bend as Doc

law stale:
  for +state: F.State
  for +received: Nat
  for +metrics: +List<T.Metric>
  for different: {Nat.is_eq(F.generation(state), received) == False{} : Bool}
  {F.accept(state, Nil{}, F.Observation{received, metrics}) == state : F.State}

law ready_duplicate:
  for +generation: Nat
  for +scale: T.Scale
  for +body: T.Metric
  for received: Nat
  for metrics: +List<T.Metric>
  {F.accept(F.Ready{generation, scale, body, Nil{}}, Nil{}, F.Observation{received, metrics}) ==
    F.Ready{generation, scale, body, Nil{}} : F.State}

law failed_duplicate:
  for +generation: Nat
  for +scale: T.Scale
  for received: Nat
  for metrics: +List<T.Metric>
  {F.accept(F.Failed{generation, scale}, Nil{}, F.Observation{received, metrics}) ==
    F.Failed{generation, scale} : F.State}

law current_pending:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for +metrics: +List<T.Metric>
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics}) ==
    F.admit(generation, scale, metrics) : F.State}

def ready_valid(state: F.State) -> Bool:
  match state:
    case F.Ready{generation, scale, body, +content_cache}: T.valid_body(body)
    case _: True{}

law retag_scale:
  for state: F.State
  for generation: Nat
  {F.scale(F.retag(state, generation)) == F.scale(state) : T.Scale}

law retag_body:
  for state: F.State
  for generation: Nat
  {F.body(F.retag(state, generation)) == F.body(state) : Maybe<&2, T.Metric>}

law retag_pending:
  for state: F.State
  for generation: Nat
  {F.pending(F.retag(state, generation)) == F.pending(state) : Bool}

law retag_generation:
  for state: F.State
  for generation: Nat
  {F.generation(F.retag(state, generation)) == generation : Nat}

law pending_request:
  for capacity: Nat
  for generation: Nat
  for scale: T.Scale
  {F.request_at(capacity, F.Pending{generation, scale}, Nil{}) == F.Plan{generation,
    [T.body_spec_at(capacity, scale)]} : F.Plan}

law ready_request:
  for capacity: Nat
  for generation: Nat
  for scale: T.Scale
  for metric: T.Metric
  {F.request_at(capacity, F.Ready{generation, scale, metric, Nil{}}, Nil{}) == F.Plan{generation, Nil{}} : F.Plan}

law failed_request:
  for capacity: Nat
  for generation: Nat
  for scale: T.Scale
  {F.request_at(capacity, F.Failed{generation, scale}, Nil{}) == F.Plan{generation, Nil{}} : F.Plan}

law begin_scale:
  for generation: Nat
  for root: Nat
  {F.begin(generation, root) == F.Pending{generation,
    T.Scale{Nat.sub(Nat.max(1000n, Nat.div(root, 16n)), 1000n)}} : F.State}

law received_success:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for +metric: T.Metric
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  for valid: {T.valid_body(metric) == True{} : Bool}
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}) ==
    F.Ready{generation, scale, metric, Nil{}} : F.State}

law received_invalid:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for +metric: T.Metric
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  for bad: {T.valid_body(metric) == False{} : Bool}
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}) ==
    F.Failed{generation, scale} : F.State}

law received_empty:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, Nil{}}) ==
    F.Failed{generation, scale} : F.State}

law received_multiple:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for +first: T.Metric
  for +second: T.Metric
  for +rest: +List<T.Metric>
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  {F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, Con{first, Con{second, rest}}}) ==
    F.Failed{generation, scale} : F.State}

law received_valid:
  for +generation: Nat
  for +scale: T.Scale
  for +received: Nat
  for +metrics: +List<T.Metric>
  for owned: {Nat.is_eq(generation, received) == True{} : Bool}
  {ready_valid(F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics})) == True{} : Bool}

law retag_pending_variant:
  for old: Nat
  for generation: Nat
  for scale: T.Scale
  {F.retag(F.Pending{old, scale}, generation) == F.Pending{generation, scale} : F.State}

law retag_ready_variant:
  for old: Nat
  for generation: Nat
  for scale: T.Scale
  for body: T.Metric
  {F.retag(F.Ready{old, scale, body, Nil{}}, generation) == F.Ready{generation, scale, body, Nil{}} : F.State}

law retag_failed_variant:
  for old: Nat
  for generation: Nat
  for scale: T.Scale
  {F.retag(F.Failed{old, scale}, generation) == F.Failed{generation, scale} : F.State}

def spec_content(value: T.MeasurementSpec) -> (String & (String & (Maybe<&2, Nat> & String))):
  T.MeasurementSpec{key, text, family, size, leading, weight, white_space, overflow, word_break, available, reference} = value
  (key, (text, (available, reference)))

def spec_style(value: T.MeasurementSpec) -> (String & (Nat & (Nat & Nat))):
  T.MeasurementSpec{key, text, family, size, leading, weight, white_space, overflow, word_break, available, reference} = value
  (family, (size, (leading, weight)))

def spec_wrapping(value: T.MeasurementSpec) -> (String & (String & String)):
  T.MeasurementSpec{key, text, family, size, leading, weight, white_space, overflow, word_break, available, reference} = value
  (white_space, (overflow, word_break))

def presentation_tier(value: T.Presentation) -> T.Tier:
  T.Presentation{tier, emphasis, scale} = value
  tier

def presentation_emphasis(value: T.Presentation) -> T.Emphasis:
  T.Presentation{tier, emphasis, scale} = value
  emphasis

def presentation_fields(value: T.Presentation) -> (T.Tier & (T.Emphasis & T.Scale)):
  T.Presentation{tier, emphasis, scale} = value
  (tier, (emphasis, scale))

def specification_key(value: T.MeasurementSpec) -> String:
  T.MeasurementSpec{key, text, family, size, height, weight, space, wrap, word_break, width, reference} = value
  key

def metric_key(value: T.Metric) -> String:
  T.Metric{key, minimum, preferred, height, advance} = value
  key

def metric_widths(value: T.Metric) -> Bool:
  T.Metric{key, minimum, preferred, height, advance} = value
  Nat.is_le(minimum, preferred)

def metric_height(value: T.Metric) -> Bool:
  T.Metric{key, minimum, preferred, height, advance} = value
  Nat.is_gt(height, 0n)

type TypographyRequirements is Type:
  TypographyRequirements{
    metric_admission: @+specification:T.MeasurementSpec -> @+metric:T.Metric -> @accepted:{T.valid_metric(specification, metric) == True{} : Bool} ->
      {String.eq(specification_key(specification), metric_key(metric)) == True{} : Bool} & ({metric_widths(metric) == True{} : Bool} & {metric_height(metric) == True{} : Bool}),
    normal_anywhere: {(T.white_space(T.NormalAnywhere{}), (T.overflow_wrap(T.NormalAnywhere{}), T.word_break(T.NormalAnywhere{}))) == ("normal", ("anywhere", "normal")) : (String & (String & String))},
    normal_words: {(T.white_space(T.NormalWords{}), (T.overflow_wrap(T.NormalWords{}), T.word_break(T.NormalWords{}))) == ("normal", ("normal", "normal")) : (String & (String & String))},
    presentation_parameters: @+capacity:Nat -> @+presentation:T.Presentation -> @+new_tier:T.Tier -> @+new_emphasis:T.Emphasis -> @+new_scale:T.Scale ->
      {presentation_fields(T.with_tier(presentation, new_tier)) == (new_tier, (presentation_emphasis(presentation), T.presentation_scale(presentation))) : (T.Tier & (T.Emphasis & T.Scale))} &
      {presentation_fields(T.with_emphasis(presentation, new_emphasis)) == (presentation_tier(presentation), (new_emphasis, T.presentation_scale(presentation))) : (T.Tier & (T.Emphasis & T.Scale))} &
      {presentation_fields(T.with_scale(presentation, new_scale)) == (presentation_tier(presentation), (presentation_emphasis(presentation), new_scale)) : (T.Tier & (T.Emphasis & T.Scale))} &
      {T.resolve_presentation(capacity, presentation) == T.resolve(capacity, presentation_tier(presentation), presentation_emphasis(presentation), T.presentation_scale(presentation)) : T.TextStyle},
    positive_clamp: @+value:Nat ->
      {T.positive(value) == Nat.max(1n, value) : Nat},
    support_is_positive: @+capacity:Nat -> @+scale:T.Scale ->
      {Nat.is_ge(T.support_size(capacity, scale), 1n) == True{} : Bool},
    body_separation: @+capacity:Nat -> @scale:T.Scale -> @emphasis:T.Emphasis ->
      {Nat.is_gt(T.resolved_size(T.resolve(capacity, T.Body{}, emphasis, scale)), T.support_size(capacity, scale)) == True{} : Bool},
    section_separation: @+capacity:Nat -> @scale:T.Scale -> @emphasis:T.Emphasis ->
      {Nat.is_gt(T.resolved_size(T.resolve(capacity, T.Section{}, emphasis, scale)), T.body_size(capacity, scale)) == True{} : Bool},
    title_separation: @+capacity:Nat -> @scale:T.Scale -> @emphasis:T.Emphasis ->
      {Nat.is_gt(T.resolved_size(T.resolve(capacity, T.Title{}, emphasis, scale)), T.section_size(capacity, scale)) == True{} : Bool},
    display_separation: @+capacity:Nat -> @scale:T.Scale -> @emphasis:T.Emphasis ->
      {Nat.is_gt(T.resolved_size(T.resolve(capacity, T.Display{}, emphasis, scale)), T.title_size(capacity, scale)) == True{} : Bool},
    readable_leading: @+capacity:Nat -> @tier:T.Tier -> @emphasis:T.Emphasis -> @scale:T.Scale ->
      {Nat.is_ge(T.resolved_line_height(T.resolve(capacity, tier, emphasis, scale)), 1n+T.resolved_size(T.resolve(capacity, tier, emphasis, scale))) == True{} : Bool},
    prominence_is_independent: @+capacity:Nat -> @tier:T.Tier -> @emphasis:T.Emphasis -> @scale:T.Scale ->
      {T.resolved_weight(T.resolve(capacity, tier, emphasis, scale)) == T.weight(emphasis) : Nat},
    family_is_tier_owned: @+capacity:Nat -> @tier:T.Tier -> @emphasis:T.Emphasis -> @scale:T.Scale ->
      {T.resolved_font(T.resolve(capacity, tier, emphasis, scale)) == T.font(tier) : T.Font},
    emphasis_preserves_size: @+capacity:Nat -> @+tier:T.Tier -> @first:T.Emphasis -> @second:T.Emphasis -> @+scale:T.Scale ->
      {T.resolved_size(T.resolve(capacity, tier, first, scale)) == T.resolved_size(T.resolve(capacity, tier, second, scale)) : Nat},
    emphasis_preserves_leading: @+capacity:Nat -> @+tier:T.Tier -> @first:T.Emphasis -> @second:T.Emphasis -> @+scale:T.Scale ->
      {T.resolved_line_height(T.resolve(capacity, tier, first, scale)) == T.resolved_line_height(T.resolve(capacity, tier, second, scale)) : Nat},
    regular_prominence: @+capacity:Nat -> @tier:T.Tier -> @scale:T.Scale ->
      {T.resolved_weight(T.resolve(capacity, tier, T.Regular{}, scale)) == 400n : Nat},
    medium_prominence: @+capacity:Nat -> @tier:T.Tier -> @scale:T.Scale ->
      {T.resolved_weight(T.resolve(capacity, tier, T.Medium{}, scale)) == 500n : Nat},
    strong_prominence: @+capacity:Nat -> @tier:T.Tier -> @scale:T.Scale ->
      {T.resolved_weight(T.resolve(capacity, tier, T.Strong{}, scale)) == 600n : Nat},
    code_body_font: @+capacity:Nat -> @scale:T.Scale -> @emphasis:T.Emphasis ->
      {T.resolved_font(T.resolve(capacity, T.CodeBody{}, emphasis, scale)) == T.MonospaceFont{} : T.Font},
    code_support_font: @+capacity:Nat -> @scale:T.Scale -> @emphasis:T.Emphasis ->
      {T.resolved_font(T.resolve(capacity, T.CodeSupport{}, emphasis, scale)) == T.MonospaceFont{} : T.Font},
    code_body_size: @+capacity:Nat -> @scale:T.Scale -> @emphasis:T.Emphasis ->
      {T.resolved_size(T.resolve(capacity, T.CodeBody{}, emphasis, scale)) == T.resolved_size(T.resolve(capacity, T.Body{}, emphasis, scale)) : Nat},
    code_body_leading: @+capacity:Nat -> @scale:T.Scale -> @emphasis:T.Emphasis ->
      {T.resolved_line_height(T.resolve(capacity, T.CodeBody{}, emphasis, scale)) == T.resolved_line_height(T.resolve(capacity, T.Body{}, emphasis, scale)) : Nat},
    code_support_size: @+capacity:Nat -> @scale:T.Scale -> @emphasis:T.Emphasis ->
      {T.resolved_size(T.resolve(capacity, T.CodeSupport{}, emphasis, scale)) == T.resolved_size(T.resolve(capacity, T.Support{}, emphasis, scale)) : Nat},
    code_support_leading: @+capacity:Nat -> @scale:T.Scale -> @emphasis:T.Emphasis ->
      {T.resolved_line_height(T.resolve(capacity, T.CodeSupport{}, emphasis, scale)) == T.resolved_line_height(T.resolve(capacity, T.Support{}, emphasis, scale)) : Nat},
    interface_family: {T.font_family(T.InterfaceFont{}) == "var(--font-sans, system-ui)" : String},
    code_family: {T.font_family(T.MonospaceFont{}) == "var(--font-mono, monospace)" : String},
    measurement_content: @key:String -> @text:String -> @style:T.TextStyle -> @wrapping:T.Wrapping -> @available:Maybe<&2,Nat> -> @reference:String ->
      {spec_content(T.spec(T.Probe{key,text,style,wrapping,available,reference})) == (key,(text,(available,reference))) : (String & (String & (Maybe<&2,Nat> & String)))},
    measurement_style: @key:String -> @text:String -> @family:T.Font -> @size:Nat -> @leading:Nat -> @weight:Nat -> @wrapping:T.Wrapping -> @available:Maybe<&2,Nat> -> @reference:String ->
      {spec_style(T.spec(T.Probe{key,text,T.TextStyle{family,size,leading,weight},wrapping,available,reference})) == (T.font_family(family),(size,(leading,weight))) : (String & (Nat & (Nat & Nat)))},
    measurement_wrapping: @key:String -> @text:String -> @style:T.TextStyle -> @+wrapping:T.Wrapping -> @available:Maybe<&2,Nat> -> @reference:String ->
      {spec_wrapping(T.spec(T.Probe{key,text,style,wrapping,available,reference})) == (T.white_space(wrapping),(T.overflow_wrap(wrapping),T.word_break(wrapping))) : (String & (String & String))},
    reading_uses_observed_advance: @advance:Nat -> @columns:Nat ->
      {T.reading_width(advance, columns) == Nat.mul(advance, columns) : Nat},
    body_probe_specification: @+capacity:Nat -> @scale:T.Scale ->
      {T.body_probe_at(capacity, scale) == T.Probe{"@font/body", "0",
        T.resolve_presentation(capacity, T.Presentation{T.Body{}, T.Regular{}, scale}),
        T.WrapWords{}, None{}, "0"} : T.Probe}
  }

law typography_evidence:
  TypographyRequirements

law unbroken_wrapping:
  {(T.white_space(T.UnbrokenLine{}),(T.overflow_wrap(T.UnbrokenLine{}),T.word_break(T.UnbrokenLine{}))) ==
    ("nowrap",("normal","normal")) : (String & (String & String))}

def selected_property(matches: Bool, value: String, fallback: String) -> String:
  match matches:
    case True{}: value
    case False{}: fallback

def property_value(values: +List<Doc.Property>, +name: String) -> String:
  match values:
    case Nil{}: ""
    case Con{Doc.Property{current, value}, rest}:
      selected_property(String.eq(current, name), value, property_value(rest, name))

def rich_body(+values: +List<Doc.Property>) -> (String & (String & (String & String))):
  (property_value(values, "--rich-body-font"), (property_value(values, "--rich-body-size"),
    (property_value(values, "--rich-body-line"), property_value(values, "--rich-body-weight"))))

def rich_strong(+values: +List<Doc.Property>) -> (String & (String & (String & String))):
  (property_value(values, "--rich-body-strong-font"), (property_value(values, "--rich-body-strong-size"),
    (property_value(values, "--rich-body-strong-line"), property_value(values, "--rich-body-strong-weight"))))

def text_style(+style: T.TextStyle) -> (String & (String & (String & String))):
  (T.font_family(T.resolved_font(style)), (Paint.px(T.resolved_size(style)),
    (Paint.px(T.resolved_line_height(style)), Nat.show(T.resolved_weight(style)))))

def presentation_context(value: T.Presentation) -> (T.Tier & T.Scale):
  T.Presentation{tier, emphasis, scale} = value
  (tier, scale)

def resolved_context(value: T.TextStyle) -> (T.Font & (Nat & Nat)):
  T.TextStyle{font, size, line_height, weight} = value
  (font, (size, line_height))

type PaintRequirements is Type:
  PaintRequirements{
    focus_projection: @+paint:Design.Paint -> @+width:Nat -> @+inset:Nat ->
      {Paint.focus_indicator_style(Design.FocusIndicator{paint, width, inset}) ==
        [Doc.Property{"--native-focus-ring", Paint.paint(paint)},
         Doc.Property{"--native-focus-width", Paint.px(width)},
         Doc.Property{"--native-focus-offset", "-" ++ Paint.px(Nat.add(inset, width))}] : +List<Doc.Property>},
    focus_outer_edge: @paint:Design.Paint -> @width:Nat -> @inset:Nat ->
      {Design.focus_indicator_outer_inset(Design.FocusIndicator{paint, width, inset}) == inset : Nat},
    focus_inner_edge: @paint:Design.Paint -> @+width:Nat -> @+inset:Nat ->
      {Design.focus_indicator_inner_inset(Design.FocusIndicator{paint, width, inset}) == Nat.add(inset, width) : Nat},
    parent_body: @+capacity:Nat -> @+parent:T.Presentation ->
      {rich_body(Paint.rich_properties_at(capacity, parent)) == text_style(T.resolve_presentation(capacity, parent)) : (String & (String & (String & String)))},
    parent_strong: @+capacity:Nat -> @+parent:T.Presentation ->
      {rich_strong(Paint.rich_properties_at(capacity, parent)) == text_style(T.resolve_presentation(capacity, T.with_emphasis(parent, T.Strong{}))) : (String & (String & (String & String)))},
    strong_emphasis_projection: @+capacity:Nat -> @+parent:T.Presentation ->
      {Paint.strong_emphasis_at(capacity, parent) ==
        [Doc.Property{"--rich-strong-weight", Nat.show(T.resolved_weight(T.resolve_presentation(capacity, T.with_emphasis(parent, T.Strong{}))))}] : +List<Doc.Property>},
    rich_emphasis_binding: @+capacity:Nat -> @+parent:T.Presentation ->
      {property_value(Paint.rich_properties_at(capacity, parent), "--rich-strong-weight") ==
        property_value(Paint.strong_emphasis_at(capacity, parent), "--rich-strong-weight") : String},
    emphasis_preserves_context: @+parent:T.Presentation -> @emphasis:T.Emphasis ->
      {presentation_context(T.with_emphasis(parent, emphasis)) == presentation_context(parent) : (T.Tier & T.Scale)},
    emphasis_preserves_resolved_context: @+capacity:Nat -> @+parent:T.Presentation -> @emphasis:T.Emphasis ->
      {resolved_context(T.resolve_presentation(capacity, T.with_emphasis(parent, emphasis))) ==
        resolved_context(T.resolve_presentation(capacity, parent)) : (T.Font & (Nat & Nat))},
    code_family: @+capacity:Nat -> @+parent:T.Presentation ->
      {property_value(Paint.rich_properties_at(capacity, parent), "--rich-code-font") == "var(--font-mono, monospace)" : String}}

law paint_evidence:
  PaintRequirements

def configured_appearance(surface: SurfaceTypes.Surface) -> Services.Appearance:
  SurfaceTypes.Surface{content, base, overlays, active_scope} = surface
  InteractionTypes.Scene{view, settings, transfers, preview, code, directory_picker} = content
  InteractionTypes.Settings{open, access, credential_entered, appearance, open_action,
    close_action, connect_action} = settings
  appearance

def theme_of_visuals(visuals: Design.Surface) -> Design.Theme:
  Design.Surface{content, theme, base, overlays, active_scope} = visuals
  theme

def presented_theme(surface: SurfaceTypes.Surface, system_dark: Bool, +scale: T.Scale) -> Design.Theme:
  theme_of_visuals(Appearance.present(surface, system_dark, scale))

def system_theme(system_dark: Bool) -> Design.Theme:
  match system_dark:
    case True{}: Design.Dark{}
    case False{}: Design.Light{}

def style_border(value: Design.Style) -> Nat:
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, +content_frame, minimum, maximum, states} = value
  width

def first_text(values: +List<Design.Node>) -> Maybe<&2, T.Presentation>:
  match values:
    case Nil{}: None{}
    case Con{Design.Node{key, semantic, label, role, meaning, style, representation, children}, rest}: Some{Design.style_text(style)}

def primary_heading_tier(in_main: Bool) -> T.Tier:
  match in_main:
    case True{}: T.Title{}
    case False{}: T.Section{}

def heading_tier(in_main: Bool, start: Bool) -> T.Tier:
  match in_main start:
    case True{} True{}: T.Display{}
    case True{} False{}: T.Title{}
    case False{} _: T.Section{}

def lane_output(value: Design.Style) -> Design.Style:
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, Enclosure.Frame{content, arrangement}, minimum, maximum, states} = value
  Design.Style{text, Design.Chrome{foreground, Design.SurfacePaint{Surfaces.Lane{Surfaces.Neutral{}}, Surfaces.Rest{}}, border, width, radius, shadow}, alignment, flow, overflow, Enclosure.Frame{Enclosure.Inset{Enclosure.Lane{}}, arrangement}, minimum, maximum, states}

type Requirements is Type:
  Requirements{
    action_geometry_minimum: @+value:Design.Style -> @+face:Controls.Face -> @+geometry:Controls.Geometry ->
      {Nat.is_ge(Design.style_minimum_height(Appearance.action_style(value, face, geometry)), Controls.geometry_minimum_height(geometry)) == True{} : Bool},
    action_content_minimum: @+value:Design.Style -> @+face:Controls.Face -> @+geometry:Controls.Geometry ->
      {Nat.is_ge(Design.style_minimum_height(Appearance.action_style(value, face, geometry)), Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.intrinsic_content_height(face, Design.style_text(value), geometry), Appearance.style_border_width(value), Controls.layout_content_area(Controls.content_layout(face))))) == True{} : Bool},
    field_content_minimum: @+capacity:Nat -> @+value:Design.Style -> @+border:Nat -> @minimum:Nat -> @radius:Nat ->
      {Nat.is_ge(Design.style_minimum_height(Appearance.field_values(capacity, value, border, minimum, radius)), Enclosure.extent_height(Appearance.field_required_extent(capacity, value, border))) == True{} : Bool},
    actual_information_assignment: @+key:UIIdentity.Key -> @+semantic:String -> @+label:String -> @+role:SurfaceTypes.Role -> @+meaning:SurfaceTypes.Meaning -> @+context:Controls.Context -> @+inherited:T.Presentation -> @+in_main:Bool -> @+start:Bool ->
      {first_text(Appearance.nodes_at([SurfaceTypes.Node{key,semantic,label,role,meaning,Nil{}}], context, inherited, in_main, start)) ==
        Some{Design.style_text(Appearance.prepared_style(key,semantic,role,meaning,Controls.enter(SurfaceTypes.Node{key,semantic,label,role,meaning,Nil{}},context),
          Controls.represent(key,meaning,label,role,Controls.enter(SurfaceTypes.Node{key,semantic,label,role,meaning,Nil{}},context)),
          Appearance.information_role(role,meaning,inherited,Appearance.enters_main(role,in_main),start)))} : Maybe<&2,T.Presentation>},
    multiline_field_role: @editor:U.Editor -> @field:Forms.Field -> @value:Forms.Observed -> @choices:+List<Forms.ChoiceValue> -> @inherited:T.Presentation -> @in_main:Bool -> @start:Bool ->
      {Appearance.information_role(SurfaceTypes.Field{}, SurfaceTypes.Edit{editor, field, Forms.Multiline{}, value, choices}, inherited, in_main, start) == T.Presentation{T.Body{}, T.Regular{}, T.presentation_scale(inherited)} : T.Presentation},
    code_surface_role: @text:String -> @inherited:T.Presentation -> @in_main:Bool -> @start:Bool ->
      {Appearance.information_role(SurfaceTypes.CodeBlock{}, SurfaceTypes.ReadOnly{text}, inherited, in_main, start) == T.Presentation{T.CodeBody{}, T.Regular{}, T.presentation_scale(inherited)} : T.Presentation},
    start_heading_role: @inherited:T.Presentation -> @text:String ->
      {Appearance.information_role(SurfaceTypes.Heading{},SurfaceTypes.ReadOnly{text},inherited,True{},True{}) == T.Presentation{T.Display{},T.Medium{},T.presentation_scale(inherited)} : T.Presentation},
    regular_heading_role: @inherited:T.Presentation -> @text:String -> @in_main:Bool ->
      {Appearance.information_role(SurfaceTypes.Heading{},SurfaceTypes.ReadOnly{text},inherited,in_main,False{}) == T.Presentation{primary_heading_tier(in_main),T.Medium{},T.presentation_scale(inherited)} : T.Presentation},
    heading_tier_total: @in_main:Bool -> @start:Bool ->
      {Appearance.heading_tier(in_main,start) == heading_tier(in_main,start) : T.Tier},
    secondary_heading_role: @inherited:T.Presentation -> @text:String -> @start:Bool ->
      {Appearance.information_role(SurfaceTypes.Heading{},SurfaceTypes.ReadOnly{text},inherited,False{},start) == T.Presentation{T.Section{},T.Medium{},T.presentation_scale(inherited)} : T.Presentation},
    lane_style_output: @value:Design.Style ->
      {Appearance.lane_style(value) == lane_output(value) : Design.Style},
    board_lane_production: @key:UIIdentity.Key -> @stage:Board.Stage -> @count:Nat -> @context:Controls.Context -> @representation:Controls.Representation -> @value:Design.Style -> @typography:T.Presentation ->
      {Appearance.final_style(key,SurfaceTypes.BoardLane{stage,count},context,representation,value,typography) == lane_output(value) : Design.Style},
    content_inherits: @inherited:T.Presentation -> @text:String -> @in_main:Bool -> @start:Bool ->
      {Appearance.information_role(SurfaceTypes.Content{},SurfaceTypes.ReadOnly{text},inherited,in_main,start) == inherited : T.Presentation},
    nodes_preserve_semantics: @+typography:T.Presentation -> @+in_main:Bool -> @+start:Bool -> @values:+List<SurfaceTypes.Node> -> @context:Controls.Context ->
      {Design.semantic_nodes(Appearance.nodes_at(values, context, typography, in_main, start)) == values : +List<SurfaceTypes.Node>},
    present_uses_configured_appearance: @+scale:T.Scale -> @surface:SurfaceTypes.Surface -> @system_dark:Bool ->
      {presented_theme(surface, system_dark, scale) ==
        Appearance.theme(configured_appearance(surface), system_dark) : Design.Theme},
    light_appearance_wins: @system_dark:Bool ->
      {Appearance.theme(Services.LightAppearance{}, system_dark) == Design.Light{} : Design.Theme},
    dark_appearance_wins: @system_dark:Bool ->
      {Appearance.theme(Services.DarkAppearance{}, system_dark) == Design.Dark{} : Design.Theme},
    system_appearance_follows_os: @system_dark:Bool ->
      {Appearance.theme(Services.SystemAppearance{}, system_dark) == system_theme(system_dark) : Design.Theme},
    user_message_style_is_exact: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning ->
      {Appearance.style(SurfaceTypes.UserMessage{}, meaning, typography) == Design.Style{typography, Design.Chrome{Design.TextForeground{Surfaces.PrimaryText{}},
            Design.SurfacePaint{Surfaces.Inset{}, Surfaces.Rest{}}, Design.Transparent{}, 0n, 16n, False{}}, SpatialModel.Trailing{}, SpatialModel.BlockFlow{}, SpatialModel.ContentFlow{}, Enclosure.Frame{Enclosure.area(Enclosure.UserMessage{}), Enclosure.EmbeddedContent{0n}}, 0n, 70n, Design.Passive{}} : Design.Style},
    assistant_message_style_is_exact: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning ->
      {Appearance.style(SurfaceTypes.AssistantMessage{}, meaning, typography) == Design.Style{typography, Design.Chrome{Design.TextForeground{Surfaces.PrimaryText{}},
            Design.SurfacePaint{Surfaces.EmbeddedAction{}, Surfaces.Rest{}}, Design.Transparent{}, 0n, 0n, False{}}, SpatialModel.Leading{}, SpatialModel.BlockFlow{}, SpatialModel.ContentFlow{}, Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}, 0n, 100n, Design.Passive{}} : Design.Style},
    composer_actions_style_is_exact: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning ->
      {Appearance.style(SurfaceTypes.ComposerActions{}, meaning, typography) == Design.Style{typography, Design.Chrome{Design.TextForeground{Surfaces.PrimaryText{}},
            Design.SurfacePaint{Surfaces.EmbeddedAction{}, Surfaces.Rest{}}, Design.Transparent{}, 0n, 0n, False{}}, SpatialModel.Stretch{}, SpatialModel.SplitRowFlow{}, SpatialModel.ContentFlow{}, Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{4n}}, 32n, 100n, Design.Passive{}} : Design.Style},
    primary_button_keeps_interaction_states: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning ->
      {Appearance.style(SurfaceTypes.PrimaryButton{}, meaning, typography) == Design.Style{T.with_emphasis(typography, T.Medium{}), Design.Chrome{Design.SurfaceForeground{Surfaces.PrimaryAction{}},
            Design.SurfacePaint{Surfaces.PrimaryAction{}, Surfaces.Rest{}},
            Design.Transparent{}, 0n, 8n, False{}}, SpatialModel.Stretch{}, SpatialModel.RowFlow{}, SpatialModel.ContentFlow{}, Enclosure.Frame{Enclosure.area(Enclosure.TextControl{}), Enclosure.EmbeddedContent{4n}}, 32n, 100n, Design.Interactive{
            Design.PhasePaint{Design.SurfaceForeground{Surfaces.PrimaryAction{}},
              Design.SurfacePaint{Surfaces.PrimaryAction{}, Surfaces.Hovered{}}},
            Design.PhasePaint{Design.SurfaceForeground{Surfaces.PrimaryAction{}},
              Design.SurfacePaint{Surfaces.PrimaryAction{}, Surfaces.Pressed{}}},
            40n, Design.FocusIndicator{Design.ThemeToken{"--color-token-focus-border"}, 2n, 2n}
          }} : Design.Style},
    main_omits_outer_border: @+typography:T.Presentation -> @meaning:SurfaceTypes.Meaning -> {style_border(Appearance.style(SurfaceTypes.Main{}, meaning, typography)) == 0n : Nat}}

law evidence:
  Requirements
