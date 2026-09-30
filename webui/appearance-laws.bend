import Base
import ../core/client-services.bend as Services
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ./design.bend as Design
import ./appearance.bend as Appearance

type Keyed is Data:
  Keyed{key: String, children: +List<Keyed>}

def source_keys(values: +List<UI.Node>) -> +List<Keyed>:
  match values:
    case Nil{}: Nil{}
    case Con{UI.Node{key, semantic, label, role, meaning, children}, rest}:
      Con{Keyed{key, source_keys(children)}, source_keys(rest)}

def appearance_keys(values: +List<Design.Appearance>) -> +List<Keyed>:
  match values:
    case Nil{}: Nil{}
    case Con{Design.Appearance{key, style, children}, rest}:
      Con{Keyed{key, appearance_keys(children)}, appearance_keys(rest)}

def nodes_preserve_keys_in(values: +List<UI.Node>, +parent_navigation: Bool) ->
  {appearance_keys(Appearance.nodes_in(values, parent_navigation)) == source_keys(values) : +List<Keyed>}:
  match values:
    case Nil{}: {==}
    case Con{UI.Node{+key, semantic, label, +role, +meaning, +children}, +rest}:
      +navigation = parent_navigation || String.eq(semantic, "navigation")
      +children_step = Equal.cong(+List<Keyed>, +List<Keyed>,
        (child_keys => Con{Keyed{key, child_keys},
          appearance_keys(Appearance.nodes_in(rest, parent_navigation))}),
        appearance_keys(Appearance.nodes_in(children, navigation)), source_keys(children),
        nodes_preserve_keys_in(children, navigation))
      +rest_step = Equal.cong(+List<Keyed>, +List<Keyed>,
        (rest_keys => Con{Keyed{key, source_keys(children)}, rest_keys}),
        appearance_keys(Appearance.nodes_in(rest, parent_navigation)), source_keys(rest),
        nodes_preserve_keys_in(rest, parent_navigation))
      +components = Equal.trans(+List<Keyed>,
        Con{Keyed{key, appearance_keys(Appearance.nodes_in(children, navigation))},
          appearance_keys(Appearance.nodes_in(rest, parent_navigation))},
        Con{Keyed{key, source_keys(children)},
          appearance_keys(Appearance.nodes_in(rest, parent_navigation))},
        Con{Keyed{key, source_keys(children)}, source_keys(rest)},
        children_step, rest_step)
      Equal.trans(+List<Keyed>,
        appearance_keys(Appearance.nodes_in(
          Con{UI.Node{key, semantic, label, role, meaning, children}, rest}, parent_navigation)),
        Con{Keyed{key, appearance_keys(Appearance.nodes_in(children, navigation))},
          appearance_keys(Appearance.nodes_in(rest, parent_navigation))},
        Con{Keyed{key, source_keys(children)}, source_keys(rest)},
        {==}, components)

def nodes_preserve_keys(values: +List<UI.Node>) ->
  {appearance_keys(Appearance.nodes(values)) == source_keys(values) : +List<Keyed>}:
  nodes_preserve_keys_in(values, False{})

def configured_appearance(surface: UI.Surface) -> Services.Appearance:
  UI.Surface{content, base, overlays, active_scope} = surface
  Core.Scene{view, settings, transfers, preview, code} = content
  Core.Settings{open, access, credential_entered, appearance, open_action,
    close_action, connect_action} = settings
  appearance

def theme_of_visuals(visuals: Design.Visuals) -> Design.Theme:
  Design.Visuals{theme, rhythm, base, overlays} = visuals
  theme

def presented_theme(surface: UI.Surface, system_dark: Bool) -> Design.Theme:
  theme_of_visuals(Appearance.present(surface, system_dark))

def present_uses_configured_appearance(surface: UI.Surface, system_dark: Bool) ->
  {presented_theme(surface, system_dark) ==
    Appearance.theme(configured_appearance(surface), system_dark) : Design.Theme}:
  match surface:
    case UI.Surface{content, base, overlays, active_scope}:
      match content:
        case Core.Scene{view, settings, transfers, preview, code}:
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

def user_message_style_is_exact(meaning: UI.Meaning) ->
  {Appearance.style(UI.UserMessage{}, meaning) == Design.Style{
    Design.TextStyle{Design.InterfaceFont{}, 13n, 20n, 400n},
    Design.Chrome{Design.ThemeToken{"--color-token-text-primary"},
      Design.ThemeToken{"--color-surface-secondary"}, Design.Transparent{}, 0n, 16n, False{}},
    Design.Trailing{}, Design.BlockFlow{}, Design.ContentFlow{},
    12n, 8n, 0n, 0n, 70n, Design.Passive{}
  } : Design.Style}:
  {==}

def assistant_message_style_is_exact(meaning: UI.Meaning) ->
  {Appearance.style(UI.AssistantMessage{}, meaning) == Design.Style{
    Design.TextStyle{Design.InterfaceFont{}, 13n, 20n, 400n},
    Design.Chrome{Design.ThemeToken{"--color-token-text-primary"},
      Design.Transparent{}, Design.Transparent{}, 0n, 0n, False{}},
    Design.Leading{}, Design.BlockFlow{}, Design.ContentFlow{},
    0n, 0n, 0n, 0n, 100n, Design.Passive{}
  } : Design.Style}:
  {==}

def composer_actions_style_is_exact(meaning: UI.Meaning) ->
  {Appearance.style(UI.ComposerActions{}, meaning) == Design.Style{
    Design.TextStyle{Design.InterfaceFont{}, 13n, 20n, 400n},
    Design.Chrome{Design.ThemeToken{"--color-token-text-primary"},
      Design.Transparent{}, Design.Transparent{}, 0n, 0n, False{}},
    Design.Stretch{}, Design.SplitRowFlow{}, Design.ContentFlow{},
    0n, 0n, 4n, 32n, 100n, Design.Passive{}
  } : Design.Style}:
  {==}

type ButtonMetrics is Data:
  ButtonMetrics{size: Nat, line_height: Nat, weight: Nat, minimum_height: Nat}

def button_metrics(style: Design.Style) -> ButtonMetrics:
  Design.Style{Design.TextStyle{font, size, line_height, weight}, chrome,
    alignment, flow, overflow, padding_inline, padding_block, gap, minimum_height,
    maximum_width_percent, states} = style
  ButtonMetrics{size, line_height, weight, minimum_height}

def navigation_button_metrics(meaning: UI.Meaning) ->
  {button_metrics(Appearance.style_in_context(UI.Button{}, meaning, True{})) ==
    ButtonMetrics{12n, 18n, 400n, 29n} : ButtonMetrics}:
  {==}

def navigation_selected_button_metrics(meaning: UI.Meaning) ->
  {button_metrics(Appearance.style_in_context(UI.SelectedButton{}, meaning, True{})) ==
    ButtonMetrics{12n, 18n, 500n, 29n} : ButtonMetrics}:
  {==}

def ordinary_button_metrics(meaning: UI.Meaning) ->
  {button_metrics(Appearance.style_in_context(UI.Button{}, meaning, False{})) ==
    ButtonMetrics{13n, 20n, 400n, 32n} : ButtonMetrics}:
  {==}

def primary_button_keeps_interaction_states(meaning: UI.Meaning) ->
  {Appearance.style(UI.PrimaryButton{}, meaning) == Design.Style{
    Design.TextStyle{Design.InterfaceFont{}, 13n, 20n, 500n},
    Design.Chrome{Design.ThemeToken{"--app-color-text-button-primary"},
      Design.ThemeToken{"--app-color-background-button-primary"},
      Design.Transparent{}, 0n, 8n, False{}},
    Design.Stretch{}, Design.RowFlow{}, Design.ContentFlow{}, 8n, 4n, 4n, 32n, 100n,
    Design.Interactive{
      Design.Chrome{Design.ThemeToken{"--app-color-text-button-primary"},
        Design.ThemeToken{"--app-color-background-button-primary-hover"},
        Design.Transparent{}, 0n, 8n, False{}},
      Design.Chrome{Design.ThemeToken{"--app-color-text-button-primary"},
        Design.ThemeToken{"--app-color-background-button-primary-active"},
        Design.Transparent{}, 0n, 8n, False{}},
      40n, Design.ThemeToken{"--color-token-focus-border"}, 2n, 2n
    }
  } : Design.Style}:
  {==}

type Requirements is Type:
  Requirements{
    nodes_preserve_keys: @+values:+List<UI.Node> ->
      {appearance_keys(Appearance.nodes(values)) == source_keys(values) : +List<Keyed>},
    present_uses_configured_appearance: @surface:UI.Surface -> @system_dark:Bool ->
      {presented_theme(surface, system_dark) ==
        Appearance.theme(configured_appearance(surface), system_dark) : Design.Theme},
    light_appearance_wins: @system_dark:Bool ->
      {Appearance.theme(Services.LightAppearance{}, system_dark) == Design.Light{} : Design.Theme},
    dark_appearance_wins: @system_dark:Bool ->
      {Appearance.theme(Services.DarkAppearance{}, system_dark) == Design.Dark{} : Design.Theme},
    system_appearance_follows_os: @system_dark:Bool ->
      {Appearance.theme(Services.SystemAppearance{}, system_dark) == system_theme(system_dark) : Design.Theme},
    user_message_style_is_exact: @meaning:UI.Meaning ->
      {Appearance.style(UI.UserMessage{}, meaning) == Design.Style{
        Design.TextStyle{Design.InterfaceFont{}, 13n, 20n, 400n},
        Design.Chrome{Design.ThemeToken{"--color-token-text-primary"},
          Design.ThemeToken{"--color-surface-secondary"}, Design.Transparent{}, 0n, 16n, False{}},
        Design.Trailing{}, Design.BlockFlow{}, Design.ContentFlow{}, 12n, 8n, 0n, 0n, 70n,
        Design.Passive{}} : Design.Style},
    assistant_message_style_is_exact: @meaning:UI.Meaning ->
      {Appearance.style(UI.AssistantMessage{}, meaning) == Design.Style{
        Design.TextStyle{Design.InterfaceFont{}, 13n, 20n, 400n},
        Design.Chrome{Design.ThemeToken{"--color-token-text-primary"},
          Design.Transparent{}, Design.Transparent{}, 0n, 0n, False{}},
        Design.Leading{}, Design.BlockFlow{}, Design.ContentFlow{}, 0n, 0n, 0n, 0n, 100n,
        Design.Passive{}} : Design.Style},
    composer_actions_style_is_exact: @meaning:UI.Meaning ->
      {Appearance.style(UI.ComposerActions{}, meaning) == Design.Style{
        Design.TextStyle{Design.InterfaceFont{}, 13n, 20n, 400n},
        Design.Chrome{Design.ThemeToken{"--color-token-text-primary"},
          Design.Transparent{}, Design.Transparent{}, 0n, 0n, False{}},
        Design.Stretch{}, Design.SplitRowFlow{}, Design.ContentFlow{}, 0n, 0n, 4n, 32n, 100n,
        Design.Passive{}} : Design.Style},
    primary_button_keeps_interaction_states: @meaning:UI.Meaning ->
      {Appearance.style(UI.PrimaryButton{}, meaning) == Design.Style{
        Design.TextStyle{Design.InterfaceFont{}, 13n, 20n, 500n},
        Design.Chrome{Design.ThemeToken{"--app-color-text-button-primary"},
          Design.ThemeToken{"--app-color-background-button-primary"}, Design.Transparent{}, 0n, 8n, False{}},
        Design.Stretch{}, Design.RowFlow{}, Design.ContentFlow{}, 8n, 4n, 4n, 32n, 100n,
        Design.Interactive{
          Design.Chrome{Design.ThemeToken{"--app-color-text-button-primary"},
            Design.ThemeToken{"--app-color-background-button-primary-hover"},
            Design.Transparent{}, 0n, 8n, False{}},
          Design.Chrome{Design.ThemeToken{"--app-color-text-button-primary"},
            Design.ThemeToken{"--app-color-background-button-primary-active"},
            Design.Transparent{}, 0n, 8n, False{}},
          40n, Design.ThemeToken{"--color-token-focus-border"}, 2n, 2n
        }} : Design.Style},
    navigation_button_metrics: @meaning:UI.Meaning ->
      {button_metrics(Appearance.style_in_context(UI.Button{}, meaning, True{})) ==
        ButtonMetrics{12n, 18n, 400n, 29n} : ButtonMetrics},
    navigation_selected_button_metrics: @meaning:UI.Meaning ->
      {button_metrics(Appearance.style_in_context(UI.SelectedButton{}, meaning, True{})) ==
        ButtonMetrics{12n, 18n, 500n, 29n} : ButtonMetrics},
    ordinary_button_metrics: @meaning:UI.Meaning ->
      {button_metrics(Appearance.style_in_context(UI.Button{}, meaning, False{})) ==
        ButtonMetrics{13n, 20n, 400n, 32n} : ButtonMetrics}
  }

def evidence() -> Requirements:
  Requirements{
    values => nodes_preserve_keys(values),
    surface => system_dark => present_uses_configured_appearance(surface, system_dark),
    system_dark => light_appearance_wins(system_dark),
    system_dark => dark_appearance_wins(system_dark),
    system_dark => system_appearance_follows_os(system_dark),
    meaning => user_message_style_is_exact(meaning),
    meaning => assistant_message_style_is_exact(meaning),
    meaning => composer_actions_style_is_exact(meaning),
    meaning => primary_button_keeps_interaction_states(meaning),
    meaning => navigation_button_metrics(meaning),
    meaning => navigation_selected_button_metrics(meaning),
    meaning => ordinary_button_metrics(meaning)
  }
