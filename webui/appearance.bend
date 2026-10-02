import Base
import ../core/client-services.bend as Services
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/form-fields.bend as Forms
import ./design.bend as Design
import ./controls.bend as Controls

# Codex Desktop 26.917.71314 supplies the semantic theme tokens, 4px spacing,
# compact 12px text, and 20px/44px composer line/minimum. Selvedge uses 13/20
# for ordinary UI text, 12/18 for secondary text, and 20/28 for headings.
def paint(name: String) -> Design.Paint:
  Design.ThemeToken{name}

def text_style(font: Design.Font, size: Nat, line_height: Nat, weight: Nat) -> Design.TextStyle:
  Design.TextStyle{font, size, line_height, weight}

def chrome(foreground: Design.Paint, background: Design.Paint, border: Design.Paint,
  border_width: Nat, radius: Nat, shadow: Bool) -> Design.Chrome:
  Design.Chrome{foreground, background, border, border_width, radius, shadow}

def fields(text: Design.TextStyle, style_chrome: Design.Chrome, alignment: Design.Alignment,
  flow: Design.Flow, overflow: Design.Overflow, padding_inline: Nat, padding_block: Nat,
  gap: Nat, minimum_height: Nat, maximum_width_percent: Nat,
  states: Design.ControlStates) -> Design.Style:
  Design.Style{text, style_chrome, alignment, flow, overflow, padding_inline,
    padding_block, gap, minimum_height, maximum_width_percent, states}

def ordinary_text() -> Design.TextStyle:
  text_style(Design.InterfaceFont{}, 13n, 20n, 400n)

def primary_foreground() -> Design.Paint:
  paint("--color-token-text-primary")

def subdued_foreground() -> Design.Paint:
  paint("--color-token-text-secondary")

def transparent() -> Design.Paint:
  Design.Transparent{}

def base_chrome() -> Design.Chrome:
  chrome(primary_foreground(), transparent(), transparent(), 0n, 0n, False{})

def surface_chrome(radius: Nat, shadow: Bool) -> Design.Chrome:
  chrome(primary_foreground(), paint("--color-token-main-surface-primary"),
    paint("--color-token-border-default"), 1n, radius, shadow)

def passive() -> Design.ControlStates:
  Design.Passive{}

def interactive(style_chrome: Design.Chrome, hover_background: Design.Paint,
  pressed_background: Design.Paint) -> Design.ControlStates:
  Design.Chrome{+foreground, background, +border, +border_width, +radius, +shadow} = style_chrome
  Design.Interactive{
    chrome(foreground, hover_background, border, border_width, radius, shadow),
    chrome(foreground, pressed_background, border, border_width, radius, shadow),
    40n,
    paint("--color-token-focus-border"),
    2n,
    2n
  }

def base_style() -> Design.Style:
  fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.BlockFlow{},
    Design.ContentFlow{}, 0n, 0n, 0n, 0n, 100n, passive())

def surface_style(flow: Design.Flow, overflow: Design.Overflow, padding_inline: Nat,
  padding_block: Nat, gap: Nat, radius: Nat, shadow: Bool) -> Design.Style:
  fields(ordinary_text(), surface_chrome(radius, shadow), Design.Stretch{}, flow, overflow,
    padding_inline, padding_block, gap, 0n, 100n, passive())

def toolbar_style(flow: Design.Flow) -> Design.Style:
  fields(ordinary_text(), base_chrome(), Design.Stretch{}, flow,
    Design.ContentFlow{}, 0n, 0n, 4n, 32n, 100n, passive())

def button_style(foreground: Design.Paint, background: Design.Paint,
  hover_background: Design.Paint, pressed_background: Design.Paint,
  weight: Nat) -> Design.Style:
  +style_chrome = chrome(foreground, background, transparent(), 0n, 8n, False{})
  fields(text_style(Design.InterfaceFont{}, 13n, 20n, weight), style_chrome,
    Design.Stretch{}, Design.RowFlow{}, Design.ContentFlow{}, 8n, 4n, 4n, 32n, 100n,
    interactive(style_chrome, hover_background, pressed_background))

def ordinary_button() -> Design.Style:
  button_style(paint("--app-color-text-button-tertiary"),
    paint("--app-color-background-button-tertiary"),
    paint("--app-color-background-button-tertiary-hover"),
    paint("--app-color-background-button-tertiary-active"), 400n)

def primary_button() -> Design.Style:
  button_style(paint("--app-color-text-button-primary"),
    paint("--app-color-background-button-primary"),
    paint("--app-color-background-button-primary-hover"),
    paint("--app-color-background-button-primary-active"), 500n)

def destructive_button() -> Design.Style:
  button_style(paint("--color-text-danger-ghost"), transparent(),
    paint("--color-background-danger-ghost-hover"),
    paint("--color-background-danger-ghost-active"), 400n)

def selected_button() -> Design.Style:
  button_style(paint("--app-color-text-button-tertiary"),
    paint("--color-token-list-hover-background"),
    paint("--app-color-background-button-tertiary-hover"),
    paint("--app-color-background-button-tertiary-active"), 500n)

def display_only_field() -> Design.Style:
  +style_chrome = chrome(primary_foreground(), transparent(), transparent(), 0n, 8n, False{})
  fields(ordinary_text(), style_chrome, Design.Stretch{}, Design.BlockFlow{},
    Design.ContentFlow{}, 8n, 6n, 0n, 32n, 100n, passive())

def editable_field() -> Design.Style:
  +style_chrome = chrome(primary_foreground(), paint("--color-token-main-surface-primary"),
    paint("--color-token-input-border"), 1n, 8n, False{})
  fields(ordinary_text(), style_chrome, Design.Stretch{}, Design.BlockFlow{},
    Design.ContentFlow{}, 8n, 6n, 0n, 32n, 100n,
    interactive(style_chrome, paint("--app-color-background-button-tertiary-hover"),
      paint("--app-color-background-button-tertiary-active")))

def compound_field_style() -> Design.Style:
  fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.ColumnFlow{},
    Design.ContentFlow{}, 0n, 0n, 8n, 0n, 100n, passive())

def toggle_extent() -> Nat:
  16n

def toggle_field() -> Design.Style:
  +style_chrome = base_chrome()
  fields(ordinary_text(), style_chrome, Design.Centered{}, Design.BlockFlow{},
    Design.ContentFlow{}, 0n, 0n, 0n, toggle_extent(), 100n,
    interactive(style_chrome, paint("--app-color-background-button-tertiary-hover"),
      paint("--app-color-background-button-tertiary-active")))

def ordinary_field_style(entry: Forms.Entry) -> Design.Style:
  match entry:
    case Forms.DisplayOnly{}: display_only_field()
    case Forms.FileCollection{}: compound_field_style()
    case Forms.DirectoryCollection{}: compound_field_style()
    case _: editable_field()

def widget_field_style(widget: Controls.Widget, entry: Forms.Entry) -> Design.Style:
  match widget:
    case Controls.ToggleInput{}: toggle_field()
    case _: ordinary_field_style(entry)

def field_style(meaning: UI.Meaning) -> Design.Style:
  match meaning:
    case UI.Edit{editor, +field, +entry, +value}:
      widget_field_style(Controls.widget_for(entry, field, value), entry)
    case _: editable_field()

def style(role: UI.Role, meaning: UI.Meaning) -> Design.Style:
  match role:
    case UI.Navigation{}:
      fields(ordinary_text(), chrome(primary_foreground(),
        paint("--color-token-side-bar-background"), transparent(), 0n, 0n, False{}),
        Design.Stretch{}, Design.ColumnFlow{}, Design.ScrollFlow{}, 8n, 8n, 4n,
        0n, 100n, passive())
    case UI.NavigationHeader{}:
      fields(text_style(Design.InterfaceFont{}, 13n, 20n, 500n), base_chrome(),
        Design.Stretch{}, Design.RowFlow{}, Design.ContentFlow{}, 8n, 4n, 8n,
        36n, 100n, passive())
    case UI.Main{}:
      fields(ordinary_text(), chrome(primary_foreground(), paint("--app-color-background-surface"), transparent(), 0n, 0n, False{}), Design.Stretch{},
        Design.ColumnFlow{}, Design.ScrollFlow{}, 0n, 0n, 0n, 0n, 100n, passive())
    case UI.Heading{}:
      fields(text_style(Design.InterfaceFont{}, 14n, 20n, 500n), base_chrome(),
        Design.Stretch{}, Design.SplitRowFlow{}, Design.ContentFlow{}, 0n, 0n, 8n,
        46n, 100n, passive())
    case UI.Timeline{}:
      fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.ColumnFlow{},
        Design.ContentFlow{}, 0n, 0n, 16n, 0n, 100n, passive())
    case UI.Activity{}:
      fields(text_style(Design.InterfaceFont{}, 12n, 18n, 400n),
        chrome(subdued_foreground(), transparent(), transparent(), 0n, 0n, False{}),
        Design.Stretch{}, Design.ColumnFlow{}, Design.ContentFlow{}, 0n, 0n, 4n,
        0n, 100n, passive())
    case UI.UserMessage{}:
      fields(ordinary_text(), chrome(primary_foreground(), paint("--color-surface-secondary"),
        transparent(), 0n, 16n, False{}), Design.Trailing{}, Design.BlockFlow{},
        Design.ContentFlow{}, 12n, 8n, 0n, 0n, 70n, passive())
    case UI.AssistantMessage{}:
      fields(ordinary_text(), base_chrome(), Design.Leading{}, Design.BlockFlow{},
        Design.ContentFlow{}, 0n, 0n, 0n, 0n, 100n, passive())
    case UI.Composer{}:
      fields(ordinary_text(), surface_chrome(16n, True{}), Design.Stretch{},
        Design.ColumnFlow{}, Design.ContentFlow{}, 12n, 8n, 4n, 0n, 100n, passive())
    case UI.ComposerActions{}: toolbar_style(Design.SplitRowFlow{})
    case UI.Approval{}:
      fields(ordinary_text(), chrome(primary_foreground(),
        paint("--color-token-main-surface-primary"),
        paint("--color-token-editor-warning-foreground"), 1n, 12n, False{}),
        Design.Stretch{}, Design.ColumnFlow{}, Design.ContentFlow{}, 12n, 12n, 8n,
        0n, 100n, passive())
    case UI.Toolbar{}: toolbar_style(Design.RowFlow{})
    case UI.CodeBlock{}:
      fields(text_style(Design.MonospaceFont{}, 12n, 22n, 400n),
        chrome(primary_foreground(), paint("--color-surface-secondary"),
          paint("--color-token-border-default"), 1n, 8n, False{}),
        Design.Stretch{}, Design.ColumnFlow{}, Design.CodeOverflow{}, 12n, 12n, 4n,
        0n, 100n, passive())
    case UI.ApprovalQueue{}:
      fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.ColumnFlow{},
        Design.ScrollFlow{}, 0n, 0n, 8n, 0n, 100n, passive())
    case UI.Section{}:
      fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.ColumnFlow{},
        Design.ContentFlow{}, 0n, 0n, 12n, 0n, 100n, passive())
    case UI.Dialog{}:
      surface_style(Design.ColumnFlow{}, Design.ContentFlow{}, 0n, 0n, 0n, 16n, True{})
    case UI.Menu{}:
      fields(ordinary_text(), chrome(primary_foreground(),
        paint("--color-token-dropdown-background"),
        paint("--color-token-border-default"), 1n, 12n, True{}),
        Design.Stretch{}, Design.ColumnFlow{}, Design.ScrollFlow{}, 4n, 4n, 2n,
        0n, 100n, passive())
    case UI.Details{}:
      surface_style(Design.ColumnFlow{}, Design.ScrollFlow{}, 16n, 16n, 16n, 0n, False{})
    case UI.Card{}:
      surface_style(Design.ColumnFlow{}, Design.ContentFlow{}, 12n, 12n, 8n, 9n, True{})
    case UI.PrimaryButton{}: primary_button()
    case UI.DestructiveButton{}: destructive_button()
    case UI.SelectedButton{}: selected_button()
    case UI.Button{}: ordinary_button()
    case UI.Field{}: field_style(meaning)
    case UI.Content{}: base_style()

def navigation_row(style_value: Design.Style) -> Design.Style:
  Design.Style{Design.TextStyle{font, size, line_height, weight}, style_chrome, alignment, flow, overflow, padding_inline,
    padding_block, gap, minimum_height, maximum_width_percent, states} = style_value
  fields(text_style(font, 12n, 18n, weight), style_chrome,
    alignment, flow, overflow, padding_inline, padding_block, gap, 29n,
    maximum_width_percent, states)

def style_in_context(role: UI.Role, meaning: UI.Meaning,
  inside_navigation: Bool) -> Design.Style:
  match role inside_navigation:
    case UI.Button{} True{}: navigation_row(style(role, meaning))
    case UI.SelectedButton{} True{}: navigation_row(style(role, meaning))
    case _ _: style(role, meaning)

def navigation_context(context: Controls.Context) -> Bool:
  match context:
    case Controls.Context{Controls.NavigationArea{}, selection, code, appearance, access, open, layers}: True{}
    case _: False{}

def rounded_chrome(value: Design.Chrome, radius: Nat) -> Design.Chrome:
  Design.Chrome{foreground, background, border, width, old_radius, shadow} = value
  Design.Chrome{foreground, background, border, width, radius, shadow}

def rounded_states(value: Design.ControlStates, +radius: Nat) -> Design.ControlStates:
  match value:
    case Design.Passive{}: Design.Passive{}
    case Design.Interactive{hover, pressed, opacity, ring, width, offset}:
      Design.Interactive{rounded_chrome(hover, radius), rounded_chrome(pressed, radius),
        opacity, ring, width, offset}

def face_padding(face: Controls.Face) -> Nat:
  match face:
    case Controls.IconFace{icon}: 4n
    case _: 8n

def action_style(value: Design.Style, face: Controls.Face, geometry: Controls.Geometry) -> Design.Style:
  Design.Style{text, style_chrome, alignment, flow, overflow, padding_inline,
    padding_block, gap, old_height, maximum_width_percent, states} = value
  Controls.Geometry{minimum_width, minimum_height, icon_size, +radius, leading_slot} = geometry
  fields(text, rounded_chrome(style_chrome, radius), alignment, Design.RowFlow{},
    overflow, face_padding(face), 4n, gap, minimum_height, maximum_width_percent,
    rounded_states(states, radius))

def selection_style(value: Design.Style, behavior: Controls.Behavior) -> Design.Style:
  match behavior:
    case Controls.Radio{True{}}: selected_button()
    case Controls.Toggle{True{}}: selected_button()
    case _: value

def feedback_style(value: Design.Style, feedback: Controls.Feedback) -> Design.Style:
  match feedback:
    case Controls.Failed{message}: destructive_button()
    case _: value

def control_style(value: Design.Style, representation: Controls.Representation) -> Design.Style:
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      action_style(feedback_style(selection_style(value, behavior), feedback), face, geometry)
    case _: value

def semantic_style(semantic: String, fallback: Design.Style) -> Design.Style:
  match semantic:
    case "creation/introduction":
      fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.ColumnFlow{},
        Design.ContentFlow{}, 0n, 0n, 12n, 0n, 100n, passive())
    case "creation/title":
      fields(text_style(Design.InterfaceFont{}, 28n, 36n, 500n), base_chrome(),
        Design.Centered{}, Design.BlockFlow{}, Design.ContentFlow{}, 0n, 0n, 0n,
        0n, 100n, passive())
    case "creation/context":
      fields(text_style(Design.InterfaceFont{}, 12n, 18n, 400n),
        chrome(subdued_foreground(), transparent(), transparent(), 0n, 0n, False{}),
        Design.Centered{}, Design.ColumnFlow{}, Design.ContentFlow{}, 0n, 0n, 8n,
        0n, 100n, passive())
    case _: fallback

def nodes_at(values: +List<UI.Node>, +context: Controls.Context) -> +List<Design.Appearance>:
  match values:
    case Nil{}: Nil{}
    case Con{UI.Node{+key, semantic, label, +role, +meaning, children}, rest}:
      +local = Controls.enter(key, role, meaning, context)
      +control = Controls.represent(key, meaning, label, role, local)
      Con{Design.Appearance{key,
        control_style(semantic_style(semantic, style_in_context(role, meaning, navigation_context(local))), control),
        control, nodes_at(children, local)}, nodes_at(rest, context)}

def theme(appearance: Services.Appearance, system_dark: Bool) -> Design.Theme:
  match appearance system_dark:
    case Services.SystemAppearance{} True{}: Design.Dark{}
    case Services.SystemAppearance{} False{}: Design.Light{}
    case Services.LightAppearance{} _: Design.Light{}
    case Services.DarkAppearance{} _: Design.Dark{}

def present_fields(content: Core.Scene, base: +List<UI.Node>, overlays: +List<UI.Node>,
  +context: Controls.Context, system_dark: Bool) -> Design.Visuals:
  Core.Scene{view, settings, transfers, preview, code} = content
  Core.Settings{open, access, credential_entered, appearance, open_action,
    close_action, connect_action} = settings
  Design.Visuals{theme(appearance, system_dark),
    Design.Rhythm{16n, 24n, 16n, 4n, 29n, 12n}, nodes_at(base, context), nodes_at(overlays, context)}

def present(surface: UI.Surface, system_dark: Bool) -> Design.Visuals:
  UI.Surface{+content, base, overlays, active_scope} = surface
  present_fields(content, base, overlays, Controls.initial(content), system_dark)
