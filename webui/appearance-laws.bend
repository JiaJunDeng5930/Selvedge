import Base
import ./typography.bend as T
import ./enclosure.bend as Enclosure
import ./enclosure-laws.bend as EnclosureLaws
import ../core/client-services.bend as Services
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ./design.bend as Design
import ./surfaces.bend as Surfaces
import ./appearance.bend as Appearance
import ./controls.bend as Controls

type Keyed is Data:
  Keyed{key: String, children: +List<Keyed>}

def source_keys(values: +List<UI.Node>) -> +List<Keyed>:
  match values:
    case Nil{}: Nil{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      Con{Keyed{key, source_keys(children)}, source_keys(rest)}

def appearance_keys(values: +List<Design.Node>) -> +List<Keyed>:
  match values:
    case Nil{}: Nil{}
    case Con{Design.Node{key, semantic, label, role, meaning, style, control, children}, rest}:
      Con{Keyed{key, appearance_keys(children)}, appearance_keys(rest)}

def nodes_preserve_keys_at(values: +List<UI.Node>, +context: Controls.Context, +typography: T.Presentation, +in_main: Bool, +start: Bool) ->
  {appearance_keys(Appearance.nodes_at(values, context, typography, in_main, start)) == source_keys(values) : +List<Keyed>}:
  match values:
    case Nil{}: {==}
    case Con{UI.Node{+key, +semantic, +label, +role, +meaning, +children}, +rest}:
      +local = Controls.enter(UI.Node{key, semantic, label, role, meaning, children}, context)
      +inside = Appearance.enters_main(role, in_main)
      +inherited_text = Appearance.information_role(role, meaning, typography, inside, start)
      +child_text = Design.style_text(Appearance.prepared_style(key, semantic, role, meaning, local,
        Controls.represent(key, meaning, label, role, local), inherited_text))
      +children_step = Equal.cong(+List<Keyed>, +List<Keyed>,
        (child_keys => Con{Keyed{key, child_keys},
          appearance_keys(Appearance.nodes_at(rest, context, typography, in_main, start))}),
        appearance_keys(Appearance.nodes_at(children, local, child_text, inside, start)), source_keys(children),
        nodes_preserve_keys_at(children, local, child_text, inside, start))
      +rest_step = Equal.cong(+List<Keyed>, +List<Keyed>,
        (rest_keys => Con{Keyed{key, source_keys(children)}, rest_keys}),
        appearance_keys(Appearance.nodes_at(rest, context, typography, in_main, start)), source_keys(rest),
        nodes_preserve_keys_at(rest, context, typography, in_main, start))
      +components = Equal.trans(+List<Keyed>,
        Con{Keyed{key, appearance_keys(Appearance.nodes_at(children, local, child_text, inside, start))},
          appearance_keys(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{Keyed{key, source_keys(children)}, appearance_keys(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{Keyed{key, source_keys(children)}, source_keys(rest)}, children_step, rest_step)
      Equal.trans(+List<Keyed>,
        appearance_keys(Appearance.nodes_at(Con{UI.Node{key, semantic, label, role, meaning, children}, rest}, context, typography, in_main, start)),
        Con{Keyed{key, appearance_keys(Appearance.nodes_at(children, local, child_text, inside, start))},
          appearance_keys(Appearance.nodes_at(rest, context, typography, in_main, start))},
        Con{Keyed{key, source_keys(children)}, source_keys(rest)}, {==}, components)

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

def configured_appearance(surface: UI.Surface) -> Services.Appearance:
  UI.Surface{content, base, overlays, active_scope} = surface
  Core.Scene{view, settings, transfers, preview, code, directory_picker} = content
  Core.Settings{open, access, credential_entered, appearance, open_action,
    close_action, connect_action} = settings
  appearance

def theme_of_visuals(visuals: Design.Surface) -> Design.Theme:
  Design.Surface{content, theme, base, overlays, active_scope} = visuals
  theme

def presented_theme(surface: UI.Surface, system_dark: Bool, +scale: T.Scale) -> Design.Theme:
  theme_of_visuals(Appearance.present(surface, system_dark, scale))

def present_uses_configured_appearance(surface: UI.Surface, system_dark: Bool, +scale: T.Scale) ->
  {presented_theme(surface, system_dark, scale) ==
    Appearance.theme(configured_appearance(surface), system_dark) : Design.Theme}:
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

def system_theme(system_dark: Bool) -> Design.Theme:
  match system_dark:
    case True{}: Design.Dark{}
    case False{}: Design.Light{}

def system_appearance_follows_os(system_dark: Bool) ->
  {Appearance.theme(Services.SystemAppearance{}, system_dark) == system_theme(system_dark) : Design.Theme}:
  match system_dark:
    case True{}: {==}
    case False{}: {==}













def style_border(value: Design.Style) -> Nat:
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, +content_frame, minimum, maximum, states} = value
  width







def first_text(values: +List<Design.Node>) -> Maybe<&2, T.Presentation>:
  match values:
    case Nil{}: None{}
    case Con{Design.Node{key, semantic, label, role, meaning, style, representation, children}, rest}: Some{Design.style_text(style)}

def regular_heading_role(inherited: T.Presentation, text: String, in_main: Bool) ->
  {Appearance.information_role(UI.Heading{},UI.ReadOnly{text},inherited,in_main,False{}) == T.Presentation{T.Section{},T.Medium{},T.presentation_scale(inherited)} : T.Presentation}:
  match in_main:
    case True{}: {==}
    case False{}: {==}

def flow_preserves_minimum(+value: Design.Style, flow: Design.Flow) ->
  {Design.style_minimum_height(Appearance.with_flow(value, flow)) == Design.style_minimum_height(value) : Nat}:
  Design.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  {==}

def action_minimum_from_layout(+layout: Controls.ContentLayout, +value: Design.Style, +face: Controls.Face, +geometry: Controls.Geometry) ->
  {Design.style_minimum_height(Appearance.with_flow(Appearance.action_content_style(value, layout, geometry, Appearance.intrinsic_content_height(face, Design.style_text(value), geometry)), Appearance.action_flow(face, layout))) == Nat.max(Controls.geometry_minimum_height(geometry), Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.intrinsic_content_height(face, Design.style_text(value), geometry), Appearance.style_border_width(value), Controls.layout_content_area(layout)))) : Nat}:
  Controls.ContentLayout{alignment, +space, +gap} = layout
  Design.Style{text, chrome, style_alignment, flow, overflow, frame, minimum, maximum, states} = value
  Controls.Geometry{width, geometry_height, icon, radius, leading} = geometry
  +height = Appearance.intrinsic_content_height(face, Design.style_text(value), geometry)
  +styled = Appearance.action_style_insets(value, geometry, space, gap, height)
  Equal.trans(Nat,
    Design.style_minimum_height(Appearance.with_flow(styled, Appearance.action_flow(face, Controls.ContentLayout{alignment, space, gap}))),
    Design.style_minimum_height(styled),
    Nat.max(Controls.geometry_minimum_height(geometry), Enclosure.extent_height(Enclosure.required_extent(0n, height, Appearance.style_border_width(value), space))),
    flow_preserves_minimum(styled, Appearance.action_flow(face, Controls.ContentLayout{alignment, space, gap})),
    EnclosureLaws.minimum_extent(value, geometry, space, gap, height))

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

def field_minimum_fits_content(+value: Design.Style, +border: Nat, minimum: Nat, radius: Nat) ->
  {Nat.is_ge(Design.style_minimum_height(Appearance.field_values(value, border, minimum, radius)),
    Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.text_line_height(Design.style_text(value)), border, Appearance.style_content_area(value)))) == True{} : Bool}:
  match value:
    case Design.Style{+text, Design.Chrome{foreground, background, paint, old_border, old_radius, shadow}, alignment, flow, overflow, +frame, old_minimum, maximum, states}:
      Nat.max_ge_r(minimum, Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.text_line_height(text), border, Appearance.frame_content_area(frame))))

type Requirements is Type:
  Requirements{
    action_geometry_minimum: @+value:Design.Style -> @+face:Controls.Face -> @+geometry:Controls.Geometry ->
      {Nat.is_ge(Design.style_minimum_height(Appearance.action_style(value, face, geometry)), Controls.geometry_minimum_height(geometry)) == True{} : Bool},
    action_content_minimum: @+value:Design.Style -> @+face:Controls.Face -> @+geometry:Controls.Geometry ->
      {Nat.is_ge(Design.style_minimum_height(Appearance.action_style(value, face, geometry)), Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.intrinsic_content_height(face, Design.style_text(value), geometry), Appearance.style_border_width(value), Controls.layout_content_area(Controls.content_layout(face))))) == True{} : Bool},
    field_content_minimum: @+value:Design.Style -> @+border:Nat -> @minimum:Nat -> @radius:Nat ->
      {Nat.is_ge(Design.style_minimum_height(Appearance.field_values(value, border, minimum, radius)), Enclosure.extent_height(Enclosure.required_extent(0n, Appearance.text_line_height(Design.style_text(value)), border, Appearance.style_content_area(value)))) == True{} : Bool},
    actual_information_assignment: @+key:String -> @+semantic:String -> @+label:String -> @+role:UI.Role -> @+meaning:UI.Meaning -> @+context:Controls.Context -> @+inherited:T.Presentation -> @+in_main:Bool -> @+start:Bool ->
      {first_text(Appearance.nodes_at([UI.Node{key,semantic,label,role,meaning,Nil{}}], context, inherited, in_main, start)) ==
        Some{Design.style_text(Appearance.prepared_style(key,semantic,role,meaning,Controls.enter(UI.Node{key,semantic,label,role,meaning,Nil{}},context),
          Controls.represent(key,meaning,label,role,Controls.enter(UI.Node{key,semantic,label,role,meaning,Nil{}},context)),
          Appearance.information_role(role,meaning,inherited,Appearance.enters_main(role,in_main),start)))} : Maybe<&2,T.Presentation>},
    start_heading_role: @inherited:T.Presentation -> @text:String ->
      {Appearance.information_role(UI.Heading{},UI.ReadOnly{text},inherited,True{},True{}) == T.Presentation{T.Display{},T.Medium{},T.presentation_scale(inherited)} : T.Presentation},
    regular_heading_role: @inherited:T.Presentation -> @text:String -> @in_main:Bool ->
      {Appearance.information_role(UI.Heading{},UI.ReadOnly{text},inherited,in_main,False{}) == T.Presentation{T.Section{},T.Medium{},T.presentation_scale(inherited)} : T.Presentation},
    content_inherits: @inherited:T.Presentation -> @text:String -> @in_main:Bool -> @start:Bool ->
      {Appearance.information_role(UI.Content{},UI.ReadOnly{text},inherited,in_main,start) == inherited : T.Presentation},
    nodes_preserve_semantics: @+typography:T.Presentation -> @+in_main:Bool -> @+start:Bool -> @values:+List<UI.Node> -> @context:Controls.Context ->
      {Design.semantic_nodes(Appearance.nodes_at(values, context, typography, in_main, start)) == values : +List<UI.Node>},
    nodes_preserve_keys_at: @+typography:T.Presentation -> @+in_main:Bool -> @+start:Bool -> @+values:+List<UI.Node> -> @+context:Controls.Context ->
      {appearance_keys(Appearance.nodes_at(values, context, typography, in_main, start)) == source_keys(values) : +List<Keyed>},
    present_uses_configured_appearance: @+scale:T.Scale -> @surface:UI.Surface -> @system_dark:Bool ->
      {presented_theme(surface, system_dark, scale) ==
        Appearance.theme(configured_appearance(surface), system_dark) : Design.Theme},
    light_appearance_wins: @system_dark:Bool ->
      {Appearance.theme(Services.LightAppearance{}, system_dark) == Design.Light{} : Design.Theme},
    dark_appearance_wins: @system_dark:Bool ->
      {Appearance.theme(Services.DarkAppearance{}, system_dark) == Design.Dark{} : Design.Theme},
    system_appearance_follows_os: @system_dark:Bool ->
      {Appearance.theme(Services.SystemAppearance{}, system_dark) == system_theme(system_dark) : Design.Theme},
    user_message_style_is_exact: @+typography:T.Presentation -> @meaning:UI.Meaning ->
      {Appearance.style(UI.UserMessage{}, meaning, typography) == Design.Style{typography, Design.Chrome{Design.ThemeToken{"--color-token-text-primary"},
            Design.SurfacePaint{Surfaces.Inset{}, Surfaces.Rest{}}, Design.Transparent{}, 0n, 16n, False{}}, Design.Trailing{}, Design.BlockFlow{}, Design.ContentFlow{}, Enclosure.Frame{Enclosure.area(Enclosure.UserMessage{}), Enclosure.EmbeddedContent{0n}}, 0n, 70n, Design.Passive{}} : Design.Style},
    assistant_message_style_is_exact: @+typography:T.Presentation -> @meaning:UI.Meaning ->
      {Appearance.style(UI.AssistantMessage{}, meaning, typography) == Design.Style{typography, Design.Chrome{Design.ThemeToken{"--color-token-text-primary"},
            Design.SurfacePaint{Surfaces.EmbeddedAction{}, Surfaces.Rest{}}, Design.Transparent{}, 0n, 0n, False{}}, Design.Leading{}, Design.BlockFlow{}, Design.ContentFlow{}, Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}, 0n, 100n, Design.Passive{}} : Design.Style},
    composer_actions_style_is_exact: @+typography:T.Presentation -> @meaning:UI.Meaning ->
      {Appearance.style(UI.ComposerActions{}, meaning, typography) == Design.Style{typography, Design.Chrome{Design.ThemeToken{"--color-token-text-primary"},
            Design.SurfacePaint{Surfaces.EmbeddedAction{}, Surfaces.Rest{}}, Design.Transparent{}, 0n, 0n, False{}}, Design.Stretch{}, Design.SplitRowFlow{}, Design.ContentFlow{}, Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{4n}}, 32n, 100n, Design.Passive{}} : Design.Style},
    primary_button_keeps_interaction_states: @+typography:T.Presentation -> @meaning:UI.Meaning ->
      {Appearance.style(UI.PrimaryButton{}, meaning, typography) == Design.Style{T.with_emphasis(typography, T.Medium{}), Design.Chrome{Design.SurfaceForeground{Surfaces.PrimaryAction{}},
            Design.SurfacePaint{Surfaces.PrimaryAction{}, Surfaces.Rest{}},
            Design.Transparent{}, 0n, 8n, False{}}, Design.Stretch{}, Design.RowFlow{}, Design.ContentFlow{}, Enclosure.Frame{Enclosure.area(Enclosure.TextControl{}), Enclosure.EmbeddedContent{4n}}, 32n, 100n, Design.Interactive{
            Design.PhasePaint{Design.SurfaceForeground{Surfaces.PrimaryAction{}},
              Design.SurfacePaint{Surfaces.PrimaryAction{}, Surfaces.Hovered{}}},
            Design.PhasePaint{Design.SurfaceForeground{Surfaces.PrimaryAction{}},
              Design.SurfacePaint{Surfaces.PrimaryAction{}, Surfaces.Pressed{}}},
            40n, Design.ThemeToken{"--color-token-focus-border"}, 2n, 2n
          }} : Design.Style},
    main_omits_outer_border: @+typography:T.Presentation -> @meaning:UI.Meaning -> {style_border(Appearance.style(UI.Main{}, meaning, typography)) == 0n : Nat}}

def evidence() -> Requirements:
  Requirements{action_minimum_retains_geometry, action_minimum_fits_content, field_minimum_fits_content,
    +key => +semantic => +label => +role => +meaning => +context => +inherited => +in_main => +start => {==},
    inherited => text => {==}, inherited => text => in_main => regular_heading_role(inherited,text,in_main), inherited => text => in_main => start => {==},
    +typography => +in_main => +start => values => context => nodes_preserve_semantics_at(values, context, typography, in_main, start),
    +typography => +in_main => +start => values => context => nodes_preserve_keys_at(values, context, typography, in_main, start),
    +scale => surface => system_dark => present_uses_configured_appearance(surface, system_dark, scale),
    system_dark => light_appearance_wins(system_dark),
    system_dark => dark_appearance_wins(system_dark),
    system_dark => system_appearance_follows_os(system_dark),
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==}}
