import ../layout/geometry-proof.bend as ProofGeometryProof
import Base
import ./CONTRACT.bend as Rule
import ./FONT.bend as F
import ./TYPOGRAPHY.bend as T
import ./PROGRAM.bend as Paint
import ../../bendlib/logic-proof.bend as Logic
import ../layout/natural-size.bend as NaturalSize
import ../layout/GEOMETRY.bend as SpatialModel
import ../layout/SPACE.bend as Space
import ../layout/enclosure.bend as Enclosure
import ../../interaction/services/MODEL.bend as Services
import ./DESIGN.bend as Design
import ./MODEL.bend as Appearance
import ../controls/PROGRAM.bend as Controls
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/TYPES.bend as InteractionTypes

def Rule.stale(state, received, metrics, different):
  Equal.cong(Bool, F.State, (owned => F.receive(owned, state, Nil{}, metrics)),
    Nat.is_eq(F.generation(state), received), False{}, different)

def ready_receive(owned: Bool, generation: Nat, scale: T.Scale, body: T.Metric, metrics: +List<T.Metric>) ->
  {F.receive(owned, F.Ready{generation, scale, body, Nil{}}, Nil{}, metrics) ==
    F.Ready{generation, scale, body, Nil{}} : F.State}:
  match owned:
    case True{}: {==}
    case False{}: {==}

def Rule.ready_duplicate(generation, scale, body, received, metrics):
  ready_receive(Nat.is_eq(generation, received), generation, scale, body, metrics)

def failed_receive(owned: Bool, generation: Nat, scale: T.Scale, metrics: +List<T.Metric>) ->
  {F.receive(owned, F.Failed{generation, scale}, Nil{}, metrics) == F.Failed{generation, scale} : F.State}:
  match owned:
    case True{}: {==}
    case False{}: {==}

def Rule.failed_duplicate(generation, scale, received, metrics):
  failed_receive(Nat.is_eq(generation, received), generation, scale, metrics)

def success(+generation: Nat, +scale: T.Scale, +metric: T.Metric,
  valid: {T.valid_body(metric) == True{} : Bool}) ->
  {F.admit(generation, scale, [metric]) == F.Ready{generation, scale, metric, Nil{}} : F.State}:
  Equal.cong(Bool, F.State, (checked => F.admit_checked(checked, generation, scale, metric)),
    T.valid_body(metric), True{}, valid)

def invalid(+generation: Nat, +scale: T.Scale, +metric: T.Metric,
  bad: {T.valid_body(metric) == False{} : Bool}) ->
  {F.admit(generation, scale, [metric]) == F.Failed{generation, scale} : F.State}:
  Equal.cong(Bool, F.State, (checked => F.admit_checked(checked, generation, scale, metric)),
    T.valid_body(metric), False{}, bad)

def Rule.current_pending(generation, scale, received, metrics, owned):
  Equal.cong(Bool, F.State, (current => F.receive(current, F.Pending{generation, scale}, Nil{}, metrics)),
    Nat.is_eq(generation, received), True{}, owned)

def checked_valid(generation: Nat, scale: T.Scale, +metric: T.Metric, +checked: Bool,
  correspondence: {T.valid_body(metric) == checked : Bool}) ->
  {Rule.ready_valid(F.admit_checked(checked, generation, scale, metric)) == True{} : Bool}:
  match checked:
    case True{}: correspondence
    case False{}: {==}

def tail_valid(generation: Nat, scale: T.Scale, +metric: T.Metric, rest: +List<T.Metric>) ->
  {Rule.ready_valid(F.admit_tail(generation, scale, metric, rest)) == True{} : Bool}:
  match rest:
    case Nil{}: checked_valid(generation, scale, metric, T.valid_body(metric), {==})
    case Con{other, tail}: {==}

def admitted_valid(generation: Nat, scale: T.Scale, metrics: +List<T.Metric>) ->
  {Rule.ready_valid(F.admit(generation, scale, metrics)) == True{} : Bool}:
  match metrics:
    case Nil{}: {==}
    case Con{metric, rest}: tail_valid(generation, scale, metric, rest)

def Rule.retag_scale(state, generation):
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def Rule.retag_body(state, generation):
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def Rule.retag_pending(state, generation):
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def Rule.retag_generation(state, generation):
  match state:
    case F.Pending{old, scale}: {==}
    case F.Ready{old, scale, body, +content_cache}: {==}
    case F.Failed{old, scale}: {==}

def Rule.pending_request(capacity, generation, scale):
  {==}

def Rule.ready_request(capacity, generation, scale, metric):
  {==}

def Rule.failed_request(capacity, generation, scale):
  {==}

def Rule.begin_scale(generation, root):
  {==}

def Rule.received_success(generation, scale, received, metric, owned, valid):
  Equal.trans(F.State, F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}),
    F.admit(generation, scale, [metric]), F.Ready{generation, scale, metric, Nil{}},
    Rule.current_pending(generation, scale, received, [metric], owned), success(generation, scale, metric, valid))

def Rule.received_invalid(generation, scale, received, metric, owned, bad):
  Equal.trans(F.State, F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, [metric]}),
    F.admit(generation, scale, [metric]), F.Failed{generation, scale},
    Rule.current_pending(generation, scale, received, [metric], owned), invalid(generation, scale, metric, bad))

def Rule.received_empty(generation, scale, received, owned):
  Rule.current_pending(generation, scale, received, Nil{}, owned)

def Rule.received_multiple(generation, scale, received, first, second, rest, owned):
  Rule.current_pending(generation, scale, received, Con{first, Con{second, rest}}, owned)

def Rule.received_valid(generation, scale, received, metrics, owned):
  Equal.trans(Bool, Rule.ready_valid(F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics})),
    Rule.ready_valid(F.admit(generation, scale, metrics)), True{},
    Equal.cong(F.State, Bool, Rule.ready_valid,
      F.accept(F.Pending{generation, scale}, Nil{}, F.Observation{received, metrics}),
      F.admit(generation, scale, metrics), Rule.current_pending(generation, scale, received, metrics, owned)),
    admitted_valid(generation, scale, metrics))

def Rule.retag_pending_variant(old, generation, scale):
  {==}

def Rule.retag_ready_variant(old, generation, scale, body):
  {==}

def Rule.retag_failed_variant(old, generation, scale):
  {==}

# Content stamps authenticate the requested specification; physical accuracy is external.

def ready_no_outstanding(+generation: Nat, +scale: T.Scale, +body: T.Metric, +content: +List<T.Measured>,
  +specifications: +List<T.MeasurementSpec>, +metrics: +List<T.Metric>,
  complete: {F.missing(specifications, content) == Nil{} : +List<T.MeasurementSpec>}) ->
  {F.receive(True{}, F.Ready{generation, scale, body, content}, specifications, metrics) == F.Ready{generation, scale, body, content} : F.State}:
  Equal.cong(+List<T.MeasurementSpec>, F.State,
    (outstanding => F.ready_batch(generation, scale, body, content, specifications, outstanding, metrics)),
    F.missing(specifications, content), Nil{}, complete)

def code_family(+capacity: Nat, +parent: T.Presentation) ->
  {Rule.property_value(Paint.rich_properties_at(capacity, parent), "--rich-code-font") == "var(--font-mono, monospace)" : String}:
  match parent:
    case T.Presentation{tier, emphasis, scale}: {==}

def emphasis_preserves_context(+parent: T.Presentation, emphasis: T.Emphasis) ->
  {Rule.presentation_context(T.with_emphasis(parent, emphasis)) == Rule.presentation_context(parent) : (T.Tier & T.Scale)}:
  match parent:
    case T.Presentation{tier, original, scale}: {==}

def emphasis_preserves_resolved_context(+capacity: Nat, +parent: T.Presentation, emphasis: T.Emphasis) ->
  {Rule.resolved_context(T.resolve_presentation(capacity, T.with_emphasis(parent, emphasis))) ==
    Rule.resolved_context(T.resolve_presentation(capacity, parent)) : (T.Font & (Nat & Nat))}:
  match parent:
    case T.Presentation{tier, original, scale}: {==}

def Rule.paint_evidence():
  Rule.PaintRequirements{+paint => +width => +inset => {==}, paint => width => inset => {==}, paint => +width => +inset => {==}, +capacity => +parent => {==}, +capacity => +parent => {==}, +capacity => +parent => {==}, +capacity => +parent => {==}, emphasis_preserves_context, emphasis_preserves_resolved_context, code_family}

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
  {T.positive(value) == Nat.max(1n, value) : Nat}:
  {==}

def scaled_positive(+capacity: Nat, +nominal: Nat, +scale: T.Scale) ->
  {Nat.is_ge(T.scaled(capacity, nominal, scale), 1n) == True{} : Bool}:
  Nat.max_ge_l(1n, NaturalSize.saturated(capacity, NaturalSize.evaluate(capacity, T.scaling_calculation(nominal, scale))))

def support_positive(+capacity: Nat, +scale: T.Scale) ->
  {Nat.is_ge(T.support_size(capacity, scale), 1n) == True{} : Bool}:
  scaled_positive(capacity, 12n, scale)

def body_separation(+capacity: Nat, +scale: T.Scale, emphasis: T.Emphasis) ->
  {Nat.is_gt(T.resolved_size(T.resolve(capacity, T.Body{}, emphasis, scale)), T.support_size(capacity, scale)) == True{} : Bool}:
  separated(T.support_size(capacity, scale), T.scaled(capacity, 13n, scale))

def section_separation(+capacity: Nat, +scale: T.Scale, emphasis: T.Emphasis) ->
  {Nat.is_gt(T.resolved_size(T.resolve(capacity, T.Section{}, emphasis, scale)), T.body_size(capacity, scale)) == True{} : Bool}:
  separated(T.body_size(capacity, scale), T.scaled(capacity, 14n, scale))

def title_separation(+capacity: Nat, +scale: T.Scale, emphasis: T.Emphasis) ->
  {Nat.is_gt(T.resolved_size(T.resolve(capacity, T.Title{}, emphasis, scale)), T.section_size(capacity, scale)) == True{} : Bool}:
  separated(T.section_size(capacity, scale), T.scaled(capacity, 20n, scale))

def display_separation(+capacity: Nat, +scale: T.Scale, emphasis: T.Emphasis) ->
  {Nat.is_gt(T.resolved_size(T.resolve(capacity, T.Display{}, emphasis, scale)), T.title_size(capacity, scale)) == True{} : Bool}:
  separated(T.title_size(capacity, scale), T.scaled(capacity, 28n, scale))

def readable_leading(+capacity: Nat, +tier: T.Tier, emphasis: T.Emphasis, +scale: T.Scale) ->
  {Nat.is_ge(T.resolved_line_height(T.resolve(capacity, tier, emphasis, scale)), 1n+T.resolved_size(T.resolve(capacity, tier, emphasis, scale))) == True{} : Bool}:
  Nat.max_ge_l(1n+T.size(capacity, tier, scale), T.scaled(capacity, T.nominal_leading(tier), scale))

def code_size(+capacity: Nat, scale: T.Scale, emphasis: T.Emphasis) ->
  {T.resolved_size(T.resolve(capacity, T.CodeBody{}, emphasis, scale)) == T.resolved_size(T.resolve(capacity, T.Body{}, emphasis, scale)) : Nat}:
  {==}

def code_leading(+capacity: Nat, scale: T.Scale, emphasis: T.Emphasis) ->
  {T.resolved_line_height(T.resolve(capacity, T.CodeBody{}, emphasis, scale)) == T.resolved_line_height(T.resolve(capacity, T.Body{}, emphasis, scale)) : Nat}:
  {==}

def code_support_size(+capacity: Nat, scale: T.Scale, emphasis: T.Emphasis) ->
  {T.resolved_size(T.resolve(capacity, T.CodeSupport{}, emphasis, scale)) == T.resolved_size(T.resolve(capacity, T.Support{}, emphasis, scale)) : Nat}:
  {==}

def code_support_leading(+capacity: Nat, scale: T.Scale, emphasis: T.Emphasis) ->
  {T.resolved_line_height(T.resolve(capacity, T.CodeSupport{}, emphasis, scale)) == T.resolved_line_height(T.resolve(capacity, T.Support{}, emphasis, scale)) : Nat}:
  {==}

def measurement_content(key: String, text: String, style: T.TextStyle, wrapping: T.Wrapping, available: Maybe<&2,Nat>, reference: String) ->
  {Rule.spec_content(T.spec(T.Probe{key,text,style,wrapping,available,reference})) == (key,(text,(available,reference))) : (String & (String & (Maybe<&2,Nat> & String)))}:
  T.TextStyle{family,size,leading,weight} = style
  {==}

def measurement_wrapping(key: String, text: String, style: T.TextStyle, +wrapping: T.Wrapping, available: Maybe<&2,Nat>, reference: String) ->
  {Rule.spec_wrapping(T.spec(T.Probe{key,text,style,wrapping,available,reference})) == (T.white_space(wrapping),(T.overflow_wrap(wrapping),T.word_break(wrapping))) : (String & (String & String))}:
  T.TextStyle{family,size,leading,weight} = style
  {==}

def presentation_parameters(+capacity: Nat, +presentation: T.Presentation, +new_tier: T.Tier, +new_emphasis: T.Emphasis, +new_scale: T.Scale) ->
  {Rule.presentation_fields(T.with_tier(presentation, new_tier)) == (new_tier, (Rule.presentation_emphasis(presentation), T.presentation_scale(presentation))) : (T.Tier & (T.Emphasis & T.Scale))} &
  {Rule.presentation_fields(T.with_emphasis(presentation, new_emphasis)) == (Rule.presentation_tier(presentation), (new_emphasis, T.presentation_scale(presentation))) : (T.Tier & (T.Emphasis & T.Scale))} &
  {Rule.presentation_fields(T.with_scale(presentation, new_scale)) == (Rule.presentation_tier(presentation), (Rule.presentation_emphasis(presentation), new_scale)) : (T.Tier & (T.Emphasis & T.Scale))} &
  {T.resolve_presentation(capacity, presentation) == T.resolve(capacity, Rule.presentation_tier(presentation), Rule.presentation_emphasis(presentation), T.presentation_scale(presentation)) : T.TextStyle}:
  T.Presentation{tier, emphasis, scale} = presentation
  ({==}, {==}, {==}, {==})

def admitted_flags(+keys: Bool, +widths: Bool, +height: Bool, reference: Bool,
  accepted: {Bool.and(keys, Bool.and(widths, Bool.and(height, reference))) == True{} : Bool}) ->
  {keys == True{} : Bool} & ({widths == True{} : Bool} & {height == True{} : Bool}):
  match keys widths height:
    case False{} widths height: Logic.impossible({False{} == True{} : Bool} & ({widths == True{} : Bool} & {height == True{} : Bool}), accepted)
    case True{} False{} height: Logic.impossible({True{} == True{} : Bool} & ({False{} == True{} : Bool} & {height == True{} : Bool}), accepted)
    case True{} True{} False{}: Logic.impossible({True{} == True{} : Bool} & ({True{} == True{} : Bool} & {False{} == True{} : Bool}), accepted)
    case True{} True{} True{}: ({==}, ({==}, {==}))

def admitted_metric_boundaries(+specification: T.MeasurementSpec, +metric: T.Metric,
  accepted: {T.valid_metric(specification, metric) == True{} : Bool}) ->
  {String.eq(Rule.specification_key(specification), Rule.metric_key(metric)) == True{} : Bool} &
    ({Rule.metric_widths(metric) == True{} : Bool} & {Rule.metric_height(metric) == True{} : Bool}):
  match specification metric:
    case T.MeasurementSpec{expected_key, text, family, size, line_height, weight, space, wrap, word_break, width, reference} T.Metric{actual_key, minimum, preferred, height, advance}:
      admitted_flags(String.eq(expected_key, actual_key), Nat.is_le(minimum, preferred), Nat.is_gt(height, 0n), Bool.or(String.eq(reference, ""), Nat.is_gt(advance, 0n)), accepted)

def Rule.typography_evidence():
  Rule.TypographyRequirements{admitted_metric_boundaries, {==}, {==},
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

def Rule.unbroken_wrapping(): {==}

def nodes_preserve_semantics_at(values: +List<SurfaceTypes.Node>, +context: Controls.Context, +typography: T.Presentation, +in_main: Bool, +start: Bool) ->
  {Design.semantic_nodes(Appearance.nodes_at(values, context, typography, in_main, start)) == values : +List<SurfaceTypes.Node>}:
  match values:
    case Nil{}: {==}
    case Con{SurfaceTypes.Node{+key, ++semantic, +label, +role, +meaning, +children}, +rest}:
      +local = Controls.enter(SurfaceTypes.Node{key, semantic, label, role, meaning, children}, context)
      +inside = Appearance.enters_main(role, in_main)
      +inherited_text = Appearance.information_role(role, meaning, typography, inside, start)
      +child_text = Design.style_text(Appearance.prepared_style(key, semantic, role, meaning, local,
        Controls.represent(key, meaning, label, role, local), inherited_text))
      +children_step = Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>,
        (prepared_children => Con{SurfaceTypes.Node{key, semantic, label, role, meaning, prepared_children},
          Design.semantic_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))}),
        Design.semantic_nodes(Appearance.nodes_at(children, local, child_text, inside, start)), children,
        nodes_preserve_semantics_at(children, local, child_text, inside, start))
      +rest_step = Equal.cong(+List<SurfaceTypes.Node>, +List<SurfaceTypes.Node>,
        (prepared_rest => Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, prepared_rest}),
        Design.semantic_nodes(Appearance.nodes_at(rest, context, typography, in_main, start)), rest,
        nodes_preserve_semantics_at(rest, context, typography, in_main, start))
      Equal.trans(+List<SurfaceTypes.Node>,
        Con{SurfaceTypes.Node{key, semantic, label, role, meaning,
          Design.semantic_nodes(Appearance.nodes_at(children, local, child_text, inside, start))},
          Design.semantic_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children},
          Design.semantic_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{SurfaceTypes.Node{key, semantic, label, role, meaning, children}, rest}, children_step, rest_step)

def present_preserves_semantics(+surface: SurfaceTypes.Surface, system_dark: Bool, +scale: T.Scale) ->
  {Design.semantic_surface(Appearance.present(surface, system_dark, scale)) == surface : SurfaceTypes.Surface}:
  match surface:
    case SurfaceTypes.Surface{+content, +base, +overlays, +active_scope}:
      match content:
        case InteractionTypes.Scene{view, settings, transfers, preview, code, directory_picker}:
          match settings:
            case InteractionTypes.Settings{open, access, entered, appearance, open_action, close_action, connect}:
              +context = Controls.initial(content)
              +base_step = Equal.cong(+List<SurfaceTypes.Node>, SurfaceTypes.Surface,
                (prepared_base => SurfaceTypes.Surface{content, prepared_base,
                  Design.semantic_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{})), active_scope}),
                Design.semantic_nodes(Appearance.nodes_at(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content))), base,
                nodes_preserve_semantics_at(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content)))
              +overlays_step = Equal.cong(+List<SurfaceTypes.Node>, SurfaceTypes.Surface,
                (prepared_overlays => SurfaceTypes.Surface{content, base, prepared_overlays, active_scope}),
                Design.semantic_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{})), overlays,
                nodes_preserve_semantics_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{}))
              Equal.trans(SurfaceTypes.Surface,
                SurfaceTypes.Surface{content, Design.semantic_nodes(Appearance.nodes_at(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content))),
                  Design.semantic_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{})), active_scope},
                SurfaceTypes.Surface{content, base, Design.semantic_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{})), active_scope},
                SurfaceTypes.Surface{content, base, overlays, active_scope}, base_step, overlays_step)

def present_uses_configured_appearance(surface: SurfaceTypes.Surface, system_dark: Bool, +scale: T.Scale) ->
  {Rule.presented_theme(surface, system_dark, scale) ==
    Appearance.theme(Rule.configured_appearance(surface), system_dark) : Design.Theme}:
  match surface:
    case SurfaceTypes.Surface{content, base, overlays, active_scope}:
      match content:
        case InteractionTypes.Scene{view, settings, transfers, preview, code, directory_picker}:
          match settings:
            case InteractionTypes.Settings{open, access, credential_entered, appearance,
              open_action, close_action, connect_action}: {==}

def light_appearance_wins(system_dark: Bool) ->
  {Appearance.theme(Services.LightAppearance{}, system_dark) == Design.Light{} : Design.Theme}:
  match system_dark:
    case True{}: {==}
    case False{}: {==}

def dark_appearance_wins(system_dark: Bool) ->
  {Appearance.theme(Services.DarkAppearance{}, system_dark) == Design.Dark{} : Design.Theme}:
  match system_dark:
    case True{}: {==}
    case False{}: {==}

def system_appearance_follows_os(system_dark: Bool) ->
  {Appearance.theme(Services.SystemAppearance{}, system_dark) == Rule.system_theme(system_dark) : Design.Theme}:
  match system_dark:
    case True{}: {==}
    case False{}: {==}

def regular_heading_role(inherited: T.Presentation, text: String, in_main: Bool) ->
  {Appearance.information_role(SurfaceTypes.Heading{},SurfaceTypes.ReadOnly{text},inherited,in_main,False{}) == T.Presentation{Rule.primary_heading_tier(in_main),T.Medium{},T.presentation_scale(inherited)} : T.Presentation}:
  match in_main:
    case True{}: {==}
    case False{}: {==}

def heading_tier_total(in_main: Bool, start: Bool) ->
  {Appearance.heading_tier(in_main,start) == Rule.heading_tier(in_main,start) : T.Tier}:
  match in_main start:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def secondary_heading_role(inherited: T.Presentation, text: String, start: Bool) ->
  {Appearance.information_role(SurfaceTypes.Heading{},SurfaceTypes.ReadOnly{text},inherited,False{},start) == T.Presentation{T.Section{},T.Medium{},T.presentation_scale(inherited)} : T.Presentation}:
  match start:
    case True{}: {==}
    case False{}: {==}

def lane_output(value: Design.Style) ->
  {Appearance.lane_style(value) == Rule.lane_output(value) : Design.Style}:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Design.Chrome{foreground, background, border, width, radius, shadow} = chrome
  Enclosure.Frame{content, arrangement} = frame
  {==}

def flow_preserves_minimum(+value: Design.Style, flow: SpatialModel.Flow) ->
  {Design.style_minimum_height(Appearance.with_flow(value, flow)) == Design.style_minimum_height(value) : Nat}:
  Design.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  {==}

def action_minimum_from_layout(+layout: Controls.ContentLayout, +value: Design.Style, +face: Controls.Face, +geometry: Controls.Geometry) ->
  {Design.style_minimum_height(Appearance.with_flow(Appearance.action_content_style(value, layout, geometry, Appearance.intrinsic_content_height(face, Design.style_text(value), geometry)), Appearance.action_flow(face, layout))) == Nat.max(Controls.geometry_minimum_height(geometry), Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.intrinsic_content_height(face, Design.style_text(value), geometry), Appearance.style_border_width(value), Controls.layout_content_area(layout)))) : Nat}:
  Controls.ContentLayout{alignment, +space, +gap} = layout
  Design.Style{text, chrome, style_alignment, flow, overflow, frame, minimum, maximum, states} = value
  Controls.Geometry{Space.Demand{Enclosure.Extent{width, geometry_height}, preferred}, icon, radius, leading} = geometry
  +height = Appearance.intrinsic_content_height(face, Design.style_text(value), geometry)
  +styled = Appearance.action_style_insets(value, geometry, space, gap, height)
  Equal.trans(Nat,
    Design.style_minimum_height(Appearance.with_flow(styled, Appearance.action_flow(face, Controls.ContentLayout{alignment, space, gap}))),
    Design.style_minimum_height(styled),
    Nat.max(Controls.geometry_minimum_height(geometry), Enclosure.extent_height(Enclosure.required_extent(0n, height, Appearance.style_border_width(value), space))),
    flow_preserves_minimum(styled, Appearance.action_flow(face, Controls.ContentLayout{alignment, space, gap})),
    ProofGeometryProof.minimum_extent(value, geometry, space, gap, height))

def action_minimum_formula(+value: Design.Style, +face: Controls.Face, +geometry: Controls.Geometry) ->
  {Design.style_minimum_height(Appearance.action_style(value, face, geometry)) == Nat.max(Controls.geometry_minimum_height(geometry), Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.intrinsic_content_height(face, Design.style_text(value), geometry), Appearance.style_border_width(value), Controls.layout_content_area(Controls.content_layout(face))))) : Nat}:
  action_minimum_from_layout(Controls.content_layout(face), value, face, geometry)

def action_minimum_retains_geometry(+value: Design.Style, +face: Controls.Face, +geometry: Controls.Geometry) ->
  {Nat.is_ge(Design.style_minimum_height(Appearance.action_style(value, face, geometry)), Controls.geometry_minimum_height(geometry)) == True{} : Bool}:
  +required = Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.intrinsic_content_height(face, Design.style_text(value), geometry), Appearance.style_border_width(value), Controls.layout_content_area(Controls.content_layout(face))))
  Equal.trans(Bool, Nat.is_ge(Design.style_minimum_height(Appearance.action_style(value, face, geometry)), Controls.geometry_minimum_height(geometry)), Nat.is_ge(Nat.max(Controls.geometry_minimum_height(geometry), required), Controls.geometry_minimum_height(geometry)), True{},
    Equal.cong(Nat, Bool, (height => Nat.is_ge(height, Controls.geometry_minimum_height(geometry))), Design.style_minimum_height(Appearance.action_style(value, face, geometry)), Nat.max(Controls.geometry_minimum_height(geometry), required), action_minimum_formula(value, face, geometry)), Nat.max_ge_l(Controls.geometry_minimum_height(geometry), required))

def action_minimum_fits_content(+value: Design.Style, +face: Controls.Face, +geometry: Controls.Geometry) ->
  {Nat.is_ge(Design.style_minimum_height(Appearance.action_style(value, face, geometry)), Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.intrinsic_content_height(face, Design.style_text(value), geometry), Appearance.style_border_width(value), Controls.layout_content_area(Controls.content_layout(face))))) == True{} : Bool}:
  +required = Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.intrinsic_content_height(face, Design.style_text(value), geometry), Appearance.style_border_width(value), Controls.layout_content_area(Controls.content_layout(face))))
  Equal.trans(Bool, Nat.is_ge(Design.style_minimum_height(Appearance.action_style(value, face, geometry)), required), Nat.is_ge(Nat.max(Controls.geometry_minimum_height(geometry), required), required), True{},
    Equal.cong(Nat, Bool, (height => Nat.is_ge(height, required)), Design.style_minimum_height(Appearance.action_style(value, face, geometry)), Nat.max(Controls.geometry_minimum_height(geometry), required), action_minimum_formula(value, face, geometry)), Nat.max_ge_r(Controls.geometry_minimum_height(geometry), required))

def field_minimum_fits_content(+capacity: Nat, +value: Design.Style, +border: Nat, minimum: Nat, radius: Nat) ->
  {Nat.is_ge(Design.style_minimum_height(Appearance.field_values(capacity, value, border, minimum, radius)),
    Enclosure.extent_height(Appearance.field_required_extent(capacity, value, border))) == True{} : Bool}:
  match value:
    case Design.Style{+text, Design.Chrome{foreground, background, paint, old_border, old_radius, shadow}, alignment, flow, overflow, +frame, old_minimum, maximum, states}:
      Nat.max_ge_r(minimum, Enclosure.extent_height(Appearance.field_required_extent(capacity, value, border)))

def Rule.evidence():
  Rule.Requirements{action_minimum_retains_geometry, action_minimum_fits_content, field_minimum_fits_content,
    +key => +semantic => +label => +role => +meaning => +context => +inherited => +in_main => +start => {==},
    editor => field => value => choices => inherited => in_main => start => {==},
    text => inherited => in_main => start => {==},
    inherited => text => {==}, inherited => text => in_main => regular_heading_role(inherited,text,in_main), in_main => start => heading_tier_total(in_main,start),
    inherited => text => start => secondary_heading_role(inherited,text,start),
    value => lane_output(value),
    key => stage => count => context => representation => value => typography => lane_output(value),
    inherited => text => in_main => start => {==},
    +typography => +in_main => +start => values => context => nodes_preserve_semantics_at(values, context, typography, in_main, start),
    +scale => surface => system_dark => present_uses_configured_appearance(surface, system_dark, scale),
    system_dark => light_appearance_wins(system_dark),
    system_dark => dark_appearance_wins(system_dark),
    system_dark => system_appearance_follows_os(system_dark),
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==}}
