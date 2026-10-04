import Base
import ./typography.bend as T
import ./enclosure.bend as Enclosure
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
      {Appearance.style(UI.UserMessage{}, meaning, typography) == Design.Style{typography, Design.Chrome{Design.TextForeground{Surfaces.PrimaryText{}},
            Design.SurfacePaint{Surfaces.Inset{}, Surfaces.Rest{}}, Design.Transparent{}, 0n, 16n, False{}}, Design.Trailing{}, Design.BlockFlow{}, Design.ContentFlow{}, Enclosure.Frame{Enclosure.area(Enclosure.UserMessage{}), Enclosure.EmbeddedContent{0n}}, 0n, 70n, Design.Passive{}} : Design.Style},
    assistant_message_style_is_exact: @+typography:T.Presentation -> @meaning:UI.Meaning ->
      {Appearance.style(UI.AssistantMessage{}, meaning, typography) == Design.Style{typography, Design.Chrome{Design.TextForeground{Surfaces.PrimaryText{}},
            Design.SurfacePaint{Surfaces.EmbeddedAction{}, Surfaces.Rest{}}, Design.Transparent{}, 0n, 0n, False{}}, Design.Leading{}, Design.BlockFlow{}, Design.ContentFlow{}, Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}, 0n, 100n, Design.Passive{}} : Design.Style},
    composer_actions_style_is_exact: @+typography:T.Presentation -> @meaning:UI.Meaning ->
      {Appearance.style(UI.ComposerActions{}, meaning, typography) == Design.Style{typography, Design.Chrome{Design.TextForeground{Surfaces.PrimaryText{}},
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

law evidence:
  Requirements
