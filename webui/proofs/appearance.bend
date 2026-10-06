import Base
import ../spatial.bend as SpatialModel
import ../appearance-laws.bend as Rule
import ../space.bend as Space
import ../typography.bend as T
import ../enclosure.bend as Enclosure
import ../../core/client-services.bend as Services
import ../../core/interface.bend as UI
import ../../core/SYSTEM.bend as Core
import ../design.bend as Design
import ../appearance.bend as Appearance
import ../controls.bend as Controls
import ./enclosure.bend as ImportedEnclosure

def nodes_preserve_semantics_at(values: +List<UI.Node>, +context: Controls.Context, +typography: T.Presentation, +in_main: Bool, +start: Bool) ->
  {Design.semantic_nodes(Appearance.nodes_at(values, context, typography, in_main, start)) == values : +List<UI.Node>}:
  match values:
    case Nil{}: {==}
    case Con{UI.Node{+key, ++semantic, +label, +role, +meaning, +children}, +rest}:
      +local = Controls.enter(UI.Node{key, semantic, label, role, meaning, children}, context)
      +inside = Appearance.enters_main(role, in_main)
      +inherited_text = Appearance.information_role(role, meaning, typography, inside, start)
      +child_text = Design.style_text(Appearance.prepared_style(key, semantic, role, meaning, local,
        Controls.represent(key, meaning, label, role, local), inherited_text))
      +children_step = Equal.cong(+List<UI.Node>, +List<UI.Node>,
        (prepared_children => Con{UI.Node{key, semantic, label, role, meaning, prepared_children},
          Design.semantic_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))}),
        Design.semantic_nodes(Appearance.nodes_at(children, local, child_text, inside, start)), children,
        nodes_preserve_semantics_at(children, local, child_text, inside, start))
      +rest_step = Equal.cong(+List<UI.Node>, +List<UI.Node>,
        (prepared_rest => Con{UI.Node{key, semantic, label, role, meaning, children}, prepared_rest}),
        Design.semantic_nodes(Appearance.nodes_at(rest, context, typography, in_main, start)), rest,
        nodes_preserve_semantics_at(rest, context, typography, in_main, start))
      Equal.trans(+List<UI.Node>,
        Con{UI.Node{key, semantic, label, role, meaning,
          Design.semantic_nodes(Appearance.nodes_at(children, local, child_text, inside, start))},
          Design.semantic_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{UI.Node{key, semantic, label, role, meaning, children},
          Design.semantic_nodes(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{UI.Node{key, semantic, label, role, meaning, children}, rest}, children_step, rest_step)

def present_preserves_semantics(+surface: UI.Surface, system_dark: Bool, +scale: T.Scale) ->
  {Design.semantic_surface(Appearance.present(surface, system_dark, scale)) == surface : UI.Surface}:
  match surface:
    case UI.Surface{+content, +base, +overlays, +active_scope}:
      match content:
        case Core.Scene{view, settings, transfers, preview, code, directory_picker}:
          match settings:
            case Core.Settings{open, access, entered, appearance, open_action, close_action, connect}:
              +context = Controls.initial(content)
              +base_step = Equal.cong(+List<UI.Node>, UI.Surface,
                (prepared_base => UI.Surface{content, prepared_base,
                  Design.semantic_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{})), active_scope}),
                Design.semantic_nodes(Appearance.nodes_at(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content))), base,
                nodes_preserve_semantics_at(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content)))
              +overlays_step = Equal.cong(+List<UI.Node>, UI.Surface,
                (prepared_overlays => UI.Surface{content, base, prepared_overlays, active_scope}),
                Design.semantic_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{})), overlays,
                nodes_preserve_semantics_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{}))
              Equal.trans(UI.Surface,
                UI.Surface{content, Design.semantic_nodes(Appearance.nodes_at(base, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, Appearance.start_page(content))),
                  Design.semantic_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{})), active_scope},
                UI.Surface{content, base, Design.semantic_nodes(Appearance.nodes_at(overlays, context, T.Presentation{T.Body{}, T.Regular{}, scale}, False{}, False{})), active_scope},
                UI.Surface{content, base, overlays, active_scope}, base_step, overlays_step)

def present_uses_configured_appearance(surface: UI.Surface, system_dark: Bool, +scale: T.Scale) ->
  {Rule.presented_theme(surface, system_dark, scale) ==
    Appearance.theme(Rule.configured_appearance(surface), system_dark) : Design.Theme}:
  match surface:
    case UI.Surface{content, base, overlays, active_scope}:
      match content:
        case Core.Scene{view, settings, transfers, preview, code, directory_picker}:
          match settings:
            case Core.Settings{open, access, credential_entered, appearance,
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
  {Appearance.information_role(UI.Heading{},UI.ReadOnly{text},inherited,in_main,False{}) == T.Presentation{Rule.primary_heading_tier(in_main),T.Medium{},T.presentation_scale(inherited)} : T.Presentation}:
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
  {Appearance.information_role(UI.Heading{},UI.ReadOnly{text},inherited,False{},start) == T.Presentation{T.Section{},T.Medium{},T.presentation_scale(inherited)} : T.Presentation}:
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
    ImportedEnclosure.minimum_extent(value, geometry, space, gap, height))

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
