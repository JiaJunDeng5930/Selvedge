import Base
import ./enclosure.bend as Enclosure
import ../core/client-services.bend as Services
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/form-fields.bend as Forms
import ./design.bend as Design
import ./surfaces.bend as Surfaces
import ./controls.bend as Controls
import ./editor-layout.bend as EditorLayout

# Codex Desktop 26.917.71314 supplies the semantic theme tokens, 4px spacing,
# compact 12px text, and 20px/44px composer line/minimum. Selvedge uses 13/20
# for ordinary UI text, 12/18 for secondary text, and 20/28 for headings.
def paint(name: String) -> Design.Paint:
  Design.ThemeToken{name}

def surface(role: Surfaces.Role, phase: Surfaces.Phase) -> Design.Paint:
  Design.SurfacePaint{role, phase}

def chrome_background(value: Design.Chrome) -> Design.Paint:
  Design.Chrome{foreground, background, border, width, radius, shadow} = value
  background

def style_background(value: Design.Style) -> Design.Paint:
  Design.Style{text, chrome, alignment, flow, overflow, +content_frame, height, maximum, states} = value
  chrome_background(chrome)

def states_background(chrome: Design.Chrome, states: Design.ControlStates, phase: Surfaces.Phase) -> Design.Paint:
  match states phase:
    case Design.Interactive{Design.PhasePaint{foreground, background}, pressed, opacity, ring, width, offset} Surfaces.Hovered{}: background
    case Design.Interactive{hover, Design.PhasePaint{foreground, background}, opacity, ring, width, offset} Surfaces.Pressed{}: background
    case Design.SurfaceFeedback{Design.PhasePaint{foreground, background}, pressed} Surfaces.Hovered{}: background
    case Design.SurfaceFeedback{hover, Design.PhasePaint{foreground, background}} Surfaces.Pressed{}: background
    case _ _: chrome_background(chrome)

def phase_background(value: Design.Style, phase: Surfaces.Phase) -> Design.Paint:
  Design.Style{text, +chrome, alignment, flow, overflow, +content_frame, height, maximum, +states} = value
  states_background(chrome, states, phase)

def text_style(font: Design.Font, size: Nat, line_height: Nat, weight: Nat) -> Design.TextStyle:
  Design.TextStyle{font, size, line_height, weight}

def creation_heading_text() -> Design.TextStyle:
  text_style(Design.InterfaceFont{}, 28n, 36n, 500n)

def dialog_inline_inset() -> Nat:
  24n

def popup_content_inset() -> Nat:
  8n

def chrome(foreground: Design.Paint, background: Design.Paint, border: Design.Paint,
  border_width: Nat, radius: Nat, shadow: Bool) -> Design.Chrome:
  Design.Chrome{foreground, background, border, border_width, radius, shadow}

def fields(text: Design.TextStyle, style_chrome: Design.Chrome, alignment: Design.Alignment,
  flow: Design.Flow, overflow: Design.Overflow, padding_inline: Nat, padding_block: Nat,
  gap: Nat, minimum_height: Nat, maximum_width_percent: Nat,
  states: Design.ControlStates) -> Design.Style:
  Design.Style{text, style_chrome, alignment, flow, overflow, Enclosure.Frame{Enclosure.ambient(padding_inline, padding_block), Enclosure.EmbeddedContent{gap}}, minimum_height, maximum_width_percent, states}

def with_content_area(value: Design.Style, content_area: Enclosure.ContentArea) -> Design.Style:
  Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{old_area, arrangement}, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content_area, arrangement}, minimum, maximum, states}

def with_arrangement(value: Design.Style, arrangement: Enclosure.Arrangement) -> Design.Style:
  Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content, old_arrangement}, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content, arrangement}, minimum, maximum, states}

def ordinary_text() -> Design.TextStyle:
  text_style(Design.InterfaceFont{}, 13n, 20n, 400n)

def primary_foreground() -> Design.Paint:
  paint("--color-token-text-primary")

def subdued_foreground() -> Design.Paint:
  paint("--color-token-text-secondary")

def transparent() -> Design.Paint:
  Design.Transparent{}

def base_chrome() -> Design.Chrome:
  chrome(primary_foreground(), surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{})

def surface_chrome(radius: Nat, shadow: Bool) -> Design.Chrome:
  chrome(primary_foreground(), surface(Surfaces.Content{}, Surfaces.Rest{}),
    paint("--color-token-border-default"), 1n, radius, shadow)

def passive() -> Design.ControlStates:
  Design.Passive{}

def interactive(style_chrome: Design.Chrome, hover_background: Design.Paint,
  pressed_background: Design.Paint) -> Design.ControlStates:
  Design.Chrome{+foreground, background, border, border_width, radius, shadow} = style_chrome
  Design.Interactive{
    Design.PhasePaint{foreground, hover_background},
    Design.PhasePaint{foreground, pressed_background},
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

def role_interactive(style_chrome: Design.Chrome, +role: Surfaces.Role) -> Design.ControlStates:
  interactive(style_chrome, surface(role, Surfaces.Hovered{}), surface(role, Surfaces.Pressed{}))

def button_style(foreground: Design.Paint, +role: Surfaces.Role, weight: Nat) -> Design.Style:
  +style_chrome = chrome(foreground, surface(role, Surfaces.Rest{}), transparent(), 0n, 8n, False{})
  with_content_area(fields(text_style(Design.InterfaceFont{}, 13n, 20n, weight), style_chrome,
    Design.Stretch{}, Design.RowFlow{}, Design.ContentFlow{}, 8n, 4n, 4n, 32n, 100n,
    role_interactive(style_chrome, role)), Enclosure.area(Enclosure.TextControl{}))

def ordinary_button() -> Design.Style:
  button_style(Design.SurfaceForeground{Surfaces.QuietAction{}}, Surfaces.QuietAction{}, 400n)

def primary_button() -> Design.Style:
  button_style(Design.SurfaceForeground{Surfaces.PrimaryAction{}}, Surfaces.PrimaryAction{}, 500n)

def destructive_button() -> Design.Style:
  button_style(Design.SurfaceForeground{Surfaces.DestructiveAction{}}, Surfaces.DestructiveAction{}, 400n)

def choice_button(selected: Bool) -> Design.Style:
  match selected:
    case True{}: button_style(Design.SurfaceForeground{Surfaces.Choice{True{}}}, Surfaces.Choice{True{}}, 400n)
    case False{}: button_style(Design.SurfaceForeground{Surfaces.Choice{False{}}}, Surfaces.Choice{False{}}, 400n)

def selected_button() -> Design.Style:
  choice_button(True{})

def display_only_field() -> Design.Style:
  +style_chrome = chrome(primary_foreground(), surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, 8n, False{})
  fields(ordinary_text(), style_chrome, Design.Stretch{}, Design.BlockFlow{},
    Design.ContentFlow{}, 8n, 6n, 0n, 32n, 100n, passive())

def field_surface(+role: Surfaces.Role) -> Design.Style:
  +style_chrome = chrome(primary_foreground(), surface(role, Surfaces.Rest{}),
    paint("--color-token-input-border"), 1n, 8n, False{})
  with_content_area(fields(ordinary_text(), style_chrome, Design.Stretch{}, Design.BlockFlow{},
    Design.ContentFlow{}, 8n, 6n, 0n, 32n, 100n, role_interactive(style_chrome, role)), Enclosure.area(Enclosure.Field{}))

def editable_field() -> Design.Style:
  field_surface(Surfaces.Field{})

def compound_field_style() -> Design.Style:
  fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.ColumnFlow{},
    Design.ContentFlow{}, 0n, 0n, 8n, 0n, 100n, passive())

def toggle_extent() -> Nat:
  16n

def toggle_field() -> Design.Style:
  +style_chrome = base_chrome()
  fields(ordinary_text(), style_chrome, Design.Centered{}, Design.BlockFlow{},
    Design.ContentFlow{}, 0n, 0n, 0n, toggle_extent(), 100n,
    role_interactive(style_chrome, Surfaces.EmbeddedField{}))

def ordinary_field_style(entry: Forms.Entry) -> Design.Style:
  match entry:
    case Forms.DisplayOnly{}: display_only_field()
    case Forms.FileCollection{}: compound_field_style()
    case Forms.DirectoryCollection{}: compound_field_style()
    case _: editable_field()

def widget_field_style(widget: Controls.Widget, entry: Forms.Entry) -> Design.Style:
  match widget:
    case Controls.ToggleInput{}: toggle_field()
    case Controls.MessageInput{}: with_content_area(field_surface(Surfaces.EmbeddedField{}), Enclosure.ambient(8n, 6n))
    case _: ordinary_field_style(entry)

def field_values(value: Design.Style, size: Nat, weight: Nat, border: Nat, minimum: Nat, radius: Nat) -> Design.Style:
  Design.Style{Design.TextStyle{font, old_size, line, old_weight}, Design.Chrome{foreground, background, border_paint, old_border, old_radius, shadow}, alignment, flow, overflow, frame, old_minimum, maximum, states} = value
  Design.Style{Design.TextStyle{font, size, line, weight}, Design.Chrome{foreground, background, border_paint, border, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states}

def work_title_field(+value: Design.Style) -> Design.Style:
  Design.Style{Design.TextStyle{font, size, line, weight}, Design.Chrome{foreground, background, border_paint, border, +radius, shadow}, alignment, flow, overflow, frame, +minimum, maximum, states} = value
  field_values(value, 20n, 550n, 0n, minimum, radius)

def work_description_field(+value: Design.Style) -> Design.Style:
  Design.Style{Design.TextStyle{font, +size, line, +weight}, Design.Chrome{foreground, background, border_paint, border, +radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
  field_values(value, size, weight, 0n, 110n, radius)

def message_field(+value: Design.Style) -> Design.Style:
  Design.Style{Design.TextStyle{font, +size, line, +weight}, Design.Chrome{foreground, background, border_paint, border, +radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
  field_values(value, size, weight, 0n, 44n, radius)

def normalize_text_field(kind: EditorLayout.FieldKind, value: Design.Style) -> Design.Style:
  match kind:
    case EditorLayout.WorkTitle{}: work_title_field(value)
    case _: value

def normalize_text_area(kind: EditorLayout.FieldKind, value: Design.Style) -> Design.Style:
  match kind:
    case EditorLayout.WorkDescription{}: work_description_field(value)
    case _: value

def normalize_field(kind: EditorLayout.FieldKind, widget: Controls.Widget, value: Design.Style) -> Design.Style:
  match widget:
    case Controls.TextInput{}: normalize_text_field(kind, value)
    case Controls.TextArea{}: normalize_text_area(kind, value)
    case Controls.MessageInput{}: message_field(value)
    case _: value

def search_field_style() -> Design.Style:
  field_values(with_content_area(field_surface(Surfaces.Inset{}), Enclosure.area(Enclosure.SearchField{})), 13n, 400n, 1n, 32n, 6n)

def field_style(meaning: UI.Meaning) -> Design.Style:
  match meaning:
    case UI.BoardSearch{filter}: search_field_style()
    case UI.Edit{editor, +field, +entry, +value}:
      normalize_field(EditorLayout.field_kind(meaning), Controls.widget_for(entry, field, value), widget_field_style(Controls.widget_for(entry, field, value), entry))
    case _: editable_field()

def style(role: UI.Role, meaning: UI.Meaning) -> Design.Style:
  match role:
    case UI.Navigation{}:
      with_arrangement(with_content_area(fields(ordinary_text(), chrome(primary_foreground(),
        surface(Surfaces.Navigation{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}),
        Design.Stretch{}, Design.ColumnFlow{}, Design.ScrollFlow{}, 8n, 8n, 4n,
        0n, 100n, passive()), Enclosure.area(Enclosure.Navigation{})), Enclosure.SeparateFrames{Enclosure.NavigationRows{}})
    case UI.NavigationHeader{}:
      fields(text_style(Design.InterfaceFont{}, 13n, 20n, 500n), base_chrome(),
        Design.Stretch{}, Design.RowFlow{}, Design.ContentFlow{}, 0n, 4n, 8n,
        36n, 100n, passive())
    case UI.Main{}:
      fields(ordinary_text(), chrome(primary_foreground(), surface(Surfaces.Canvas{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}), Design.Stretch{},
        Design.ColumnFlow{}, Design.ScrollFlow{}, 0n, 0n, 0n, 0n, 100n, passive())
    case UI.Heading{}:
      fields(text_style(Design.InterfaceFont{}, 14n, 20n, 500n), base_chrome(),
        Design.Stretch{}, Design.SplitRowFlow{}, Design.ContentFlow{}, 0n, 0n, 8n,
        46n, 100n, passive())
    case UI.Timeline{}:
      with_arrangement(fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.ColumnFlow{},
        Design.ContentFlow{}, 0n, 0n, 16n, 0n, 100n, passive()), Enclosure.SeparateFrames{Enclosure.Messages{}})
    case UI.Activity{}:
      fields(text_style(Design.InterfaceFont{}, 12n, 18n, 400n),
        chrome(subdued_foreground(), surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}),
        Design.Stretch{}, Design.ColumnFlow{}, Design.ContentFlow{}, 0n, 0n, 4n,
        0n, 100n, passive())
    case UI.UserMessage{}:
      with_content_area(fields(ordinary_text(), chrome(primary_foreground(), surface(Surfaces.Inset{}, Surfaces.Rest{}),
        transparent(), 0n, 16n, False{}), Design.Trailing{}, Design.BlockFlow{},
        Design.ContentFlow{}, 12n, 8n, 0n, 0n, 70n, passive()), Enclosure.area(Enclosure.UserMessage{}))
    case UI.AssistantMessage{}:
      fields(ordinary_text(), base_chrome(), Design.Leading{}, Design.BlockFlow{},
        Design.ContentFlow{}, 0n, 0n, 0n, 0n, 100n, passive())
    case UI.Composer{}:
      with_content_area(fields(ordinary_text(), surface_chrome(16n, True{}), Design.Stretch{},
        Design.ColumnFlow{}, Design.ContentFlow{}, 12n, 8n, 4n, 0n, 100n, passive()), Enclosure.area(Enclosure.Composer{}))
    case UI.ComposerActions{}: toolbar_style(Design.SplitRowFlow{})
    case UI.Approval{}:
      with_content_area(fields(ordinary_text(), chrome(primary_foreground(),
        surface(Surfaces.Content{}, Surfaces.Rest{}),
        paint("--color-token-editor-warning-foreground"), 1n, 12n, False{}),
        Design.Stretch{}, Design.ColumnFlow{}, Design.ContentFlow{}, 12n, 12n, 8n,
        0n, 100n, passive()), Enclosure.area(Enclosure.Approval{}))
    case UI.Toolbar{}: toolbar_style(Design.RowFlow{})
    case UI.CodeBlock{}:
      with_content_area(fields(text_style(Design.MonospaceFont{}, 12n, 22n, 400n),
        chrome(primary_foreground(), surface(Surfaces.Inset{}, Surfaces.Rest{}),
          paint("--color-token-border-default"), 1n, 8n, False{}),
        Design.Stretch{}, Design.ColumnFlow{}, Design.CodeOverflow{}, 12n, 12n, 4n,
        0n, 100n, passive()), Enclosure.area(Enclosure.CodeBlock{}))
    case UI.ApprovalQueue{}:
      fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.ColumnFlow{},
        Design.ScrollFlow{}, 0n, 0n, 8n, 0n, 100n, passive())
    case UI.Section{}:
      with_arrangement(fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.ColumnFlow{},
        Design.ContentFlow{}, 0n, 0n, 12n, 0n, 100n, passive()), Enclosure.SeparateFrames{Enclosure.Sections{}})
    case UI.Dialog{}:
      with_arrangement(with_content_area(surface_style(Design.ColumnFlow{}, Design.ContentFlow{}, 0n, 0n, 0n, 16n, True{}), Enclosure.DialogPartitions{}), Enclosure.JoinedPartitions{})
    case UI.Menu{}:
      with_arrangement(with_content_area(fields(ordinary_text(), chrome(primary_foreground(),
        surface(Surfaces.Floating{}, Surfaces.Rest{}),
        paint("--color-token-border-default"), 1n, 12n, True{}),
        Design.Stretch{}, Design.ColumnFlow{}, Design.ScrollFlow{}, popup_content_inset(), popup_content_inset(), 2n,
        0n, 100n, passive()), Enclosure.area(Enclosure.Menu{})), Enclosure.SeparateFrames{Enclosure.MenuItems{}})
    case UI.Details{}:
      with_arrangement(with_content_area(surface_style(Design.ColumnFlow{}, Design.ScrollFlow{}, 16n, 16n, 16n, 0n, False{}), Enclosure.area(Enclosure.Details{})), Enclosure.SeparateFrames{Enclosure.Sections{}})
    case UI.Card{}:
      with_arrangement(with_content_area(surface_style(Design.ColumnFlow{}, Design.ContentFlow{}, 12n, 12n, 8n, 9n, True{}), Enclosure.area(Enclosure.Card{})), Enclosure.SeparateFrames{Enclosure.CardSections{}})
    case UI.PrimaryButton{}: primary_button()
    case UI.DestructiveButton{}: destructive_button()
    case UI.SelectedButton{}: selected_button()
    case UI.Button{}: ordinary_button()
    case UI.Field{}: field_style(meaning)
    case UI.Content{}: base_style()
    case UI.Alert{}: base_style()

def navigation_row(style_value: Design.Style) -> Design.Style:
  Design.Style{Design.TextStyle{font, size, line_height, weight}, style_chrome, alignment, flow, overflow, +content_frame, minimum_height, maximum_width_percent, states} = style_value
  Design.Style{text_style(font, 12n, 18n, weight), style_chrome, alignment, flow, overflow, content_frame, 29n, maximum_width_percent, states}

def style_in_context(role: UI.Role, meaning: UI.Meaning,
  inside_navigation: Bool) -> Design.Style:
  match role inside_navigation:
    case UI.Button{} True{}: navigation_row(style(role, meaning))
    case UI.SelectedButton{} True{}: navigation_row(style(role, meaning))
    case _ _: style(role, meaning)

def navigation_context(context: Controls.Context) -> Bool:
  match context:
    case Controls.Context{Controls.NavigationArea{}, selection, code, appearance, access, open, layers, execution, source_family}: True{}
    case _: False{}

def rounded_chrome(value: Design.Chrome, radius: Nat) -> Design.Chrome:
  Design.Chrome{foreground, background, border, width, old_radius, shadow} = value
  Design.Chrome{foreground, background, border, width, radius, shadow}

def layout_inline_inset(layout: Controls.ContentLayout) -> Nat:
  Controls.ContentLayout{alignment, content_area, gap} = layout
  Enclosure.inline(content_area)

def face_padding(face: Controls.Face) -> Nat:
  layout_inline_inset(Controls.content_layout(face))

def text_line_height(value: Design.TextStyle) -> Nat:
  Design.TextStyle{font, size, line_height, weight} = value
  line_height

def chrome_border_width(value: Design.Chrome) -> Nat:
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = value
  border_width

def extent_height(value: Enclosure.Extent) -> Nat:
  Enclosure.Extent{width, height} = value
  height

def action_style_insets(value: Design.Style, geometry: Controls.Geometry, +content_area: Enclosure.ContentArea, content_gap: Nat) -> Design.Style:
  Design.Style{+text, +style_chrome, alignment, flow, overflow, +content_frame, old_height, maximum_width_percent, states} = value
  Controls.Geometry{minimum_width, minimum_height, icon_size, +radius, leading_slot} = geometry
  required_height = extent_height(Enclosure.required_extent(0n, text_line_height(text),
    chrome_border_width(style_chrome), content_area))
  Design.Style{text, rounded_chrome(style_chrome, radius), alignment, Design.RowFlow{}, overflow, Enclosure.Frame{content_area, Enclosure.EmbeddedContent{content_gap}}, Nat.max(minimum_height, required_height), maximum_width_percent, states}

def action_content_style(value: Design.Style, layout: Controls.ContentLayout, geometry: Controls.Geometry) -> Design.Style:
  Controls.ContentLayout{content_alignment, content_area, content_gap} = layout
  action_style_insets(value, geometry, content_area, content_gap)

def action_flow(face: Controls.Face, layout: Controls.ContentLayout) -> Design.Flow:
  match face layout:
    case Controls.SingleLineFace{text} _: Design.BlockFlow{}
    case Controls.ChoiceFace{text, checked} _: Design.ChoiceFlow{}
    case _ Controls.ContentLayout{alignment, content_area, gap}: Design.InlineControlFlow{alignment}

def with_flow(value: Design.Style, flow: Design.Flow) -> Design.Style:
  Design.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}

def icon_text_style(value: Design.Style, geometry: Controls.Geometry) -> Design.Style:
  Design.Style{Design.TextStyle{font, size, line, weight}, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Controls.Geometry{width, height, icon, radius, leading} = geometry
  Design.Style{Design.TextStyle{font, size, icon, weight}, chrome, alignment, flow, overflow, frame, minimum, maximum, states}

def action_text(value: Design.Style, face: Controls.Face, geometry: Controls.Geometry) -> Design.Style:
  match face:
    case Controls.IconFace{glyph}: icon_text_style(value, geometry)
    case _: value

def action_style(value: Design.Style, +face: Controls.Face, +geometry: Controls.Geometry) -> Design.Style:
  +layout = Controls.content_layout(face)
  with_flow(action_content_style(action_text(value, face, geometry), layout, geometry), action_flow(face, layout))

def selection_style(value: Design.Style, behavior: Controls.Behavior) -> Design.Style:
  match behavior:
    case Controls.Radio{selected}: choice_button(selected)
    case Controls.ChoiceRadio{selected}: choice_button(selected)
    case Controls.Toggle{selected}: choice_button(selected)
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
    case "creation/title":
      fields(creation_heading_text(), base_chrome(),
        Design.Centered{}, Design.BlockFlow{}, Design.ContentFlow{}, 0n, 0n, 0n,
        0n, 100n, passive())
    case "creation/context":
      fields(text_style(Design.InterfaceFont{}, 12n, 18n, 400n),
        chrome(subdued_foreground(), surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}),
        Design.Centered{}, Design.ColumnFlow{}, Design.ContentFlow{}, 0n, 0n, 8n,
        0n, 100n, passive())
    case _: fallback

def style_frame(value: Design.Style) -> Enclosure.Frame:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  frame


def modeled_container(value: Design.Style, flow: Design.Flow, gap: Nat) -> Design.Style:
  Design.Style{text, chrome, alignment, old_flow, overflow, Enclosure.Frame{content, arrangement}, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content, Enclosure.EmbeddedContent{gap}}, minimum, maximum, states}

def navigation_family_style(selected: Bool, gap: Nat, radius: Nat) -> Design.Style:
  +role: Surfaces.Role = Surfaces.Choice{selected}
  +foreground = primary_foreground()
  with_content_area(fields(ordinary_text(), chrome(foreground, surface(role, Surfaces.Rest{}), transparent(), 0n, radius, False{}),
    Design.Stretch{}, Design.RowFlow{}, Design.ContentFlow{}, 8n, 4n, gap, 0n, 100n,
    Design.SurfaceFeedback{Design.PhasePaint{foreground, surface(role, Surfaces.Hovered{})}, Design.PhasePaint{foreground, surface(role, Surfaces.Pressed{})}}), Enclosure.area(Enclosure.NavigationRow{}))

def embedded_control(value: Design.Style) -> Design.Style:
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
  +chrome = chrome(foreground, surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, radius, shadow)
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, role_interactive(chrome, Surfaces.EmbeddedAction{})}

def embedded_label_style(value: Design.Style) -> Design.Style:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, Design.BlockFlow{}, Design.SingleLineOverflow{}, Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}, minimum, maximum, states}

def project_label_style(value: Design.Style) -> Design.Style:
  embedded_label_style(embedded_control(value))

def chooser_text(selected: Maybe<&2, Nat>) -> Design.TextStyle:
  match selected:
    case None{}: ordinary_text()
    case Some{id}: creation_heading_text()

def chooser_embedded_style(selected: Maybe<&2, Nat>, value: Design.Style) -> Design.Style:
  Design.Style{old_text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  +text = chooser_text(selected)
  fields(text, chrome, alignment, flow, overflow, 0n, 4n, 4n, Nat.max(minimum, (text_line_height(text) + 8n : Nat)), maximum, states)

def chooser_style(selected: Maybe<&2, Nat>, value: Design.Style) -> Design.Style:
  chooser_embedded_style(selected, embedded_control(value))

def source_control_style(family: Controls.SourceFamily, representation: Controls.Representation, value: Design.Style) -> Design.Style:
  match family representation:
    case _ Controls.Action{input, availability, name, Controls.SingleLineFace{text}, behavior, geometry, placement, help, feedback}: project_label_style(value)
    case Controls.SourceFamily{owner, UI.ProjectChooser{selected}} Controls.Action{input, availability, name, Controls.PickerFace{Some{Controls.Folder{}}, text}, behavior, geometry, placement, help, feedback}: chooser_style(selected, value)
    case _ _: value

def source_style(header: Bool, family: Controls.SourceFamily, value: Design.Style) -> Design.Style:
  match header family:
    case True{} Controls.SourceFamily{owner, UI.ProjectGroup{project, selected, expanded}}: navigation_family_style(selected, 2n, 6n)
    case _ _: value

def project_group_style() -> Design.Style:
  with_arrangement(fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.ColumnFlow{}, Design.ContentFlow{}, 0n, 0n, 4n, 0n, 100n, passive()), Enclosure.SeparateFrames{Enclosure.NavigationRows{}})

def choice_group_style(value: Design.Style) -> Design.Style:
  with_arrangement(with_flow(value, Design.ColumnFlow{}), Enclosure.SeparateFrames{Enclosure.MenuItems{}})

def source_header_style(+key: String, family: Controls.SourceFamily, value: Design.Style) -> Design.Style:
  match family:
    case Controls.SourceFamily{+owner, +source}: source_style(String.eq(key, owner ++ "/actions"), Controls.SourceFamily{owner, source}, value)
    case _: value


def family_style(+key: String, meaning: UI.Meaning, family: Controls.SourceFamily, representation: Controls.Representation, +value: Design.Style) -> Design.Style:
  match meaning:
    case UI.ProjectGroup{project, selected, expanded}: project_group_style()
    case UI.TaskRow{task, status, selected}: navigation_family_style(selected, 6n, 5n)
    case UI.ProjectChooser{selected}: fields(ordinary_text(), base_chrome(), Design.Stretch{}, Design.InlineControlFlow{Controls.LeadingContents{}}, Design.ContentFlow{}, 0n, 0n, 0n, 0n, 100n, passive())
    case UI.ContextSummary{observation}: with_content_area(modeled_container(value, Design.ColumnFlow{}, 4n), Enclosure.ambient(8n, Enclosure.block(Enclosure.frame_content(style_frame(value)))))
    case UI.DirectoryRow{path, primary}: modeled_container(value, Design.ColumnFlow{}, 8n)
    case UI.ChoiceGroup{}: choice_group_style(value)
    case UI.Region{}: source_header_style(key, family, value)
    case _: source_control_style(family, representation, value)

def final_style(key: String, meaning: UI.Meaning, context: Controls.Context, representation: Controls.Representation, value: Design.Style) -> Design.Style:
  family_style(key, meaning, Controls.source_reference(context), representation, value)

def nodes_at(values: +List<UI.Node>, +context: Controls.Context) -> +List<Design.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{UI.Node{+key, +semantic, +label, +role, +meaning, children}, rest}:
      +local = Controls.enter(key, role, meaning, context)
      +control = Controls.represent(key, meaning, label, role, local)
      Con{Design.Node{key, semantic, label, role, meaning,
        final_style(key, meaning, local, control, control_style(semantic_style(semantic, style_in_context(role, meaning, navigation_context(local))), control)),
        control, nodes_at(children, local)}, nodes_at(rest, context)}

def theme(appearance: Services.Appearance, system_dark: Bool) -> Design.Theme:
  match appearance system_dark:
    case Services.SystemAppearance{} True{}: Design.Dark{}
    case Services.SystemAppearance{} False{}: Design.Light{}
    case Services.LightAppearance{} _: Design.Light{}
    case Services.DarkAppearance{} _: Design.Dark{}

def present_fields(+content: Core.Scene, base: +List<UI.Node>, overlays: +List<UI.Node>,
  +context: Controls.Context, system_dark: Bool, active_scope: Maybe<&2, String>) -> Design.Surface:
  Core.Scene{view, settings, transfers, preview, code, directory_picker} = content
  Core.Settings{open, access, credential_entered, appearance, open_action,
    close_action, connect_action} = settings
  Design.Surface{content, theme(appearance, system_dark),
    nodes_at(base, context), nodes_at(overlays, context), active_scope}

def present(surface: UI.Surface, system_dark: Bool) -> Design.Surface:
  UI.Surface{+content, base, overlays, active_scope} = surface
  present_fields(content, base, overlays, Controls.initial(content), system_dark, active_scope)
