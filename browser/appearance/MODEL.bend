import ../controls/NAVIGATION.bend as Navigation
import ../layout/ACTIVITY.bend as Activity
import ../layout/HIERARCHY.bend as Hierarchy
import Base
import ../../interaction/presentation/INFORMATION.bend as Information
import ../../interaction/IDENTITY.bend as UIIdentity
import ../layout/GEOMETRY.bend as SpatialModel
import ../layout/enclosure.bend as Enclosure
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/submission/FIELDS.bend as Forms
import ./DESIGN.bend as Design
import ../controls/SURFACES.bend as Surfaces
import ../controls/PROGRAM.bend as Controls
import ../editor/MODEL.bend as EditorLayout
import ./TYPOGRAPHY.bend as T
import ../layout/natural-size.bend as NaturalSize
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/presentation/COMPOSITION.bend as Composition
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/TYPES.bend as InteractionTypes

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
    case Design.Interactive{Design.PhasePaint{foreground, background}, pressed, opacity, indicator} Surfaces.Hovered{}: background
    case Design.Interactive{hover, Design.PhasePaint{foreground, background}, opacity, indicator} Surfaces.Pressed{}: background
    case Design.SurfaceFeedback{Design.PhasePaint{foreground, background}, pressed} Surfaces.Hovered{}: background
    case Design.SurfaceFeedback{hover, Design.PhasePaint{foreground, background}} Surfaces.Pressed{}: background
    case _ _: chrome_background(chrome)

def phase_background(value: Design.Style, phase: Surfaces.Phase) -> Design.Paint:
  Design.Style{text, +chrome, alignment, flow, overflow, +content_frame, height, maximum, +states} = value
  states_background(chrome, states, phase)

def chrome(foreground: Design.Paint, background: Design.Paint, border: Design.Paint,
  border_width: Nat, radius: Nat, shadow: Bool) -> Design.Chrome:
  Design.Chrome{foreground, background, border, border_width, radius, shadow}

def fields(text: T.Presentation, style_chrome: Design.Chrome, alignment: SpatialModel.Alignment,
  flow: SpatialModel.Flow, overflow: SpatialModel.Overflow, padding_inline: Nat, padding_block: Nat,
  gap: Nat, minimum_height: Nat, maximum_width_percent: Nat,
  states: Design.ControlStates) -> Design.Style:
  Design.Style{text, style_chrome, alignment, flow, overflow, Enclosure.Frame{Enclosure.ambient(padding_inline, padding_block), Enclosure.EmbeddedContent{gap}}, minimum_height, maximum_width_percent, states}

def with_content_area(value: Design.Style, content_area: Enclosure.ContentArea) -> Design.Style:
  Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{old_area, arrangement}, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content_area, arrangement}, minimum, maximum, states}

def with_arrangement(value: Design.Style, arrangement: Enclosure.Arrangement) -> Design.Style:
  Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content, old_arrangement}, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content, arrangement}, minimum, maximum, states}

def transparent() -> Design.Paint:
  Design.Transparent{}

def base_chrome() -> Design.Chrome:
  chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{})

def surface_chrome(radius: Nat, shadow: Bool) -> Design.Chrome:
  chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(Surfaces.Content{}, Surfaces.Rest{}),
    paint("--color-token-border-default"), 1n, radius, shadow)

def passive() -> Design.ControlStates:
  Design.Passive{}

def default_focus_indicator() -> Design.FocusIndicator:
  Design.FocusIndicator{paint("--color-token-focus-border"), 2n, 2n}

def interactive(style_chrome: Design.Chrome, hover_background: Design.Paint,
  pressed_background: Design.Paint) -> Design.ControlStates:
  Design.Chrome{+foreground, background, border, border_width, radius, shadow} = style_chrome
  Design.Interactive{
    Design.PhasePaint{foreground, hover_background},
    Design.PhasePaint{foreground, pressed_background},
    40n,
    default_focus_indicator()
  }

def content_chrome(typography: T.Presentation) -> Design.Chrome:
  T.Presentation{tier, emphasis, scale} = typography
  match tier:
    case T.ActivitySupport{}: chrome(Design.TextForeground{Surfaces.SecondaryText{}}, surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{})
    case _: base_chrome()

def base_style(+typography: T.Presentation) -> Design.Style:
  fields(typography, content_chrome(typography), SpatialModel.Stretch{}, SpatialModel.BlockFlow{},
    SpatialModel.ContentFlow{}, 0n, 0n, 0n, 0n, 100n, passive())

def surface_style(flow: SpatialModel.Flow, overflow: SpatialModel.Overflow, padding_inline: Nat,
  padding_block: Nat, gap: Nat, radius: Nat, shadow: Bool, +typography: T.Presentation) -> Design.Style:
  fields(typography, surface_chrome(radius, shadow), SpatialModel.Stretch{}, flow, overflow,
    padding_inline, padding_block, gap, 0n, 100n, passive())

def toolbar_style(flow: SpatialModel.Flow, +typography: T.Presentation) -> Design.Style:
  fields(typography, base_chrome(), SpatialModel.Stretch{}, flow,
    SpatialModel.ContentFlow{}, 0n, 0n, 4n, 32n, 100n, passive())

def role_interactive(style_chrome: Design.Chrome, +role: Surfaces.Role) -> Design.ControlStates:
  interactive(style_chrome, surface(role, Surfaces.Hovered{}), surface(role, Surfaces.Pressed{}))

def button_style(foreground: Design.Paint, +role: Surfaces.Role, emphasis: T.Emphasis, +typography: T.Presentation) -> Design.Style:
  +style_chrome = chrome(foreground, surface(role, Surfaces.Rest{}), transparent(), 0n, 8n, False{})
  with_content_area(fields(T.with_emphasis(typography, emphasis), style_chrome,
    SpatialModel.Stretch{}, SpatialModel.RowFlow{}, SpatialModel.ContentFlow{}, 8n, 4n, 4n, 32n, 100n,
    role_interactive(style_chrome, role)), Enclosure.area(Enclosure.TextControl{}))

def ordinary_button(+typography: T.Presentation) -> Design.Style:
  button_style(Design.SurfaceForeground{Surfaces.QuietAction{}}, Surfaces.QuietAction{}, T.Medium{}, typography)

def primary_button(+typography: T.Presentation) -> Design.Style:
  button_style(Design.SurfaceForeground{Surfaces.PrimaryAction{}}, Surfaces.PrimaryAction{}, T.Medium{}, typography)

def destructive_button(+typography: T.Presentation) -> Design.Style:
  button_style(Design.SurfaceForeground{Surfaces.DestructiveAction{}}, Surfaces.DestructiveAction{}, T.Medium{}, typography)

def transparent_rest(value: Design.Style) -> Design.Style:
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Design.Style{text, Design.Chrome{foreground, Design.Transparent{}, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states}

def alternative_button(selected: Bool, +typography: T.Presentation) -> Design.Style:
  match selected:
    case True{}: transparent_rest(button_style(Design.SurfaceForeground{Surfaces.Choice{True{}}}, Surfaces.Choice{True{}}, T.Medium{}, typography))
    case False{}: button_style(Design.SurfaceForeground{Surfaces.Choice{False{}}}, Surfaces.Choice{False{}}, T.Medium{}, typography)

def choice_button(selected: Bool, +typography: T.Presentation) -> Design.Style:
  match selected:
    case True{}: button_style(Design.SurfaceForeground{Surfaces.Choice{True{}}}, Surfaces.Choice{True{}}, T.Medium{}, typography)
    case False{}: button_style(Design.SurfaceForeground{Surfaces.Choice{False{}}}, Surfaces.Choice{False{}}, T.Medium{}, typography)

def selected_button(+typography: T.Presentation) -> Design.Style:
  choice_button(True{}, typography)

def display_only_field(+typography: T.Presentation) -> Design.Style:
  +style_chrome = chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, 8n, False{})
  fields(typography, style_chrome, SpatialModel.Stretch{}, SpatialModel.BlockFlow{},
    SpatialModel.ContentFlow{}, 8n, 6n, 0n, 32n, 100n, passive())

def field_surface(+role: Surfaces.Role, +typography: T.Presentation) -> Design.Style:
  +style_chrome = chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(role, Surfaces.Rest{}),
    paint("--color-token-input-border"), 1n, 8n, False{})
  with_content_area(fields(typography, style_chrome, SpatialModel.Stretch{}, SpatialModel.BlockFlow{},
    SpatialModel.ContentFlow{}, 8n, 6n, 0n, 32n, 100n, role_interactive(style_chrome, role)), Enclosure.area(Enclosure.Field{}))

def editable_field(+typography: T.Presentation) -> Design.Style:
  field_surface(Surfaces.Field{}, typography)

def compound_field_style(+typography: T.Presentation) -> Design.Style:
  fields(typography, base_chrome(), SpatialModel.Stretch{}, SpatialModel.ColumnFlow{},
    SpatialModel.ContentFlow{}, 0n, 0n, 8n, 0n, 100n, passive())

def toggle_extent() -> Nat:
  16n

def toggle_chrome() -> Design.Chrome:
  chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(Surfaces.Field{}, Surfaces.Rest{}),
    paint("--color-token-input-border"), 1n, 3n, False{})

def toggle_field(+typography: T.Presentation) -> Design.Style:
  +style_chrome = toggle_chrome()
  fields(typography, style_chrome, SpatialModel.Centered{}, SpatialModel.BlockFlow{},
    SpatialModel.ContentFlow{}, 0n, 0n, 0n, toggle_extent(), 100n,
    role_interactive(style_chrome, Surfaces.EmbeddedField{}))

def ordinary_field_style(entry: Forms.Entry, +typography: T.Presentation) -> Design.Style:
  match entry:
    case Forms.DisplayOnly{}: display_only_field(typography)
    case Forms.FileCollection{}: compound_field_style(typography)
    case Forms.DirectoryCollection{}: compound_field_style(typography)
    case _: editable_field(typography)

def widget_field_style(widget: Controls.Widget, entry: Forms.Entry, +typography: T.Presentation) -> Design.Style:
  match widget:
    case Controls.ToggleInput{}: toggle_field(typography)
    case Controls.MessageInput{}: with_content_area(field_surface(Surfaces.EmbeddedField{}, typography), Enclosure.area(Enclosure.EmbeddedEditor{}))
    case _: ordinary_field_style(entry, typography)

def text_line_height(capacity: Nat, value: T.Presentation) -> Nat:
  T.resolved_line_height(T.resolve_presentation(capacity, value))

def frame_content_area(value: Enclosure.Frame) -> Enclosure.ContentArea:
  Enclosure.Frame{area, arrangement} = value
  area

def style_content_area(value: Design.Style) -> Enclosure.ContentArea:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  frame_content_area(frame)

def field_required_extent(capacity: Nat, +value: Design.Style, border: Nat) -> Enclosure.Extent:
  Enclosure.required_extent(0n, text_line_height(capacity, Design.style_text(value)), border, style_content_area(value))

def field_values(capacity: Nat, +value: Design.Style, +border: Nat, minimum: Nat, radius: Nat) -> Design.Style:
  Design.Style{+text, Design.Chrome{foreground, background, border_paint, old_border, old_radius, shadow}, alignment, flow, overflow, +frame, old_minimum, maximum, states} = value
  required = Enclosure.extent_height(field_required_extent(capacity, value, border))
  Design.Style{text, Design.Chrome{foreground, background, border_paint, border, radius, shadow}, alignment, flow, overflow, frame, Nat.max(minimum, required), maximum, states}

def work_title_field(+value: Design.Style) -> Design.Style:
  Design.Style{text, Design.Chrome{foreground, background, border_paint, border, +radius, shadow}, alignment, flow, overflow, frame, +minimum, maximum, states} = value
  field_values(NaturalSize.limit(), value, 0n, minimum, radius)

def work_description_field(+value: Design.Style) -> Design.Style:
  Design.Style{text, Design.Chrome{foreground, background, border_paint, border, +radius, shadow}, alignment, flow, overflow, frame, +minimum, maximum, states} = value
  field_values(NaturalSize.limit(), value, 0n, 110n, radius)

def message_field(+capacity: Nat, +value: Design.Style) -> Design.Style:
  Design.Style{text, Design.Chrome{foreground, background, border_paint, border, +radius, shadow}, alignment, flow, overflow, frame, +minimum, maximum, states} = value
  field_values(capacity, value, 0n, 0n, radius)

def normalize_text_field(kind: EditorLayout.FieldKind, value: Design.Style) -> Design.Style:
  match kind:
    case EditorLayout.WorkTitle{}: work_title_field(value)
    case _: value

def normalize_text_area(kind: EditorLayout.FieldKind, value: Design.Style) -> Design.Style:
  match kind:
    case EditorLayout.WorkDescription{}: work_description_field(value)
    case _: value

def select_field_constructor(kind: EditorLayout.FieldKind, widget: Controls.Widget) -> Nat -> Design.Style -> Design.Style:
  match widget:
    case Controls.TextInput{}: capacity => value => normalize_text_field(kind, value)
    case Controls.TextArea{}: capacity => value => normalize_text_area(kind, value)
    case Controls.MessageInput{}: capacity => value => message_field(capacity, value)
    case _: capacity => value => value

def normalize_field(kind: EditorLayout.FieldKind, +widget: Controls.Widget, value: Design.Style) -> Design.Style:
  match widget:
    case Controls.MessageInput{}:
      constructor = select_field_constructor(kind, widget)
      constructor(NaturalSize.limit(), value)
    case _:
      constructor = select_field_constructor(kind, widget)
      constructor(0n, value)

def search_field_style(+typography: T.Presentation) -> Design.Style:
  field_values(NaturalSize.limit(), with_content_area(field_surface(Surfaces.Inset{}, typography), Enclosure.area(Enclosure.SearchField{})), 1n, 32n, 6n)

def field_style(meaning: SurfaceTypes.Meaning, +typography: T.Presentation) -> Design.Style:
  match meaning:
    case SurfaceTypes.BoardSearch{filter}: search_field_style(typography)
    case SurfaceTypes.Edit{editor, +field, +entry, +value, choices}:
      normalize_field(EditorLayout.field_kind(meaning), Controls.widget_for(entry, field, value), widget_field_style(Controls.widget_for(entry, field, value), entry, typography))
    case _: editable_field(typography)

def navigation_family_style(selected: Bool, gap: Nat, radius: Nat, +typography: T.Presentation) -> Design.Style:
  +role: Surfaces.Role = Surfaces.Choice{selected}
  +foreground: Design.Paint = Design.TextForeground{Surfaces.PrimaryText{}}
  with_content_area(fields(T.activity(typography), chrome(foreground, surface(role, Surfaces.Rest{}), transparent(), 0n, radius, False{}),
    SpatialModel.Stretch{}, SpatialModel.RowFlow{}, SpatialModel.ContentFlow{}, 8n, 4n, gap, 0n, 100n,
    Design.SurfaceFeedback{Design.PhasePaint{foreground, surface(role, Surfaces.Hovered{})}, Design.PhasePaint{foreground, surface(role, Surfaces.Pressed{})}}), Enclosure.area(Enclosure.NavigationRow{}))

def work_tab_background(selected: Bool) -> Design.Paint:
  match selected:
    case True{}: surface(Surfaces.Canvas{}, Surfaces.Rest{})
    case False{}: transparent()

def work_tab_style(selected: Bool, +typography: T.Presentation) -> Design.Style:
  +fg: Design.Paint = Design.TextForeground{Surfaces.PrimaryText{}}
  +bg: Design.Paint = work_tab_background(selected)
  +chrome: Design.Chrome = chrome(fg, bg, transparent(), 0n, 8n, False{})
  fields(typography, chrome, SpatialModel.Leading{}, SpatialModel.BlockFlow{}, SpatialModel.SingleLineOverflow{}, 12n, 8n, 0n, 40n, 100n,
    Design.Interactive{Design.PhasePaint{fg, bg}, Design.PhasePaint{fg, bg}, 50n, default_focus_indicator()})


def style(role: SurfaceTypes.Role, meaning: SurfaceTypes.Meaning, +typography: T.Presentation) -> Design.Style:
  match role:
    case SurfaceTypes.GlobalNavigation{compact}:
      fields(typography, chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(Surfaces.Navigation{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}), SpatialModel.Stretch{}, SpatialModel.ColumnFlow{}, SpatialModel.ScrollFlow{}, 4n, 8n, 4n, 0n, 100n, passive())
    case SurfaceTypes.GlobalNavigationEntry{selected, compact}: navigation_family_style(selected, 4n, 6n, typography)
    case SurfaceTypes.CompactHeader{}:
      fields(typography, chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(Surfaces.Canvas{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}), SpatialModel.Stretch{}, SpatialModel.RowFlow{}, SpatialModel.ContentFlow{}, 0n, 0n, 0n, Controls.navigation_motor_floor(True{}), 100n, passive())
    case SurfaceTypes.CompactWorkScope{title, count}: ordinary_button(typography)
    case SurfaceTypes.CompactNavigationMenu{}: base_style(typography)
    case SurfaceTypes.CompactNavigationEntry{selected}: navigation_family_style(selected, 6n, 5n, typography)
    case SurfaceTypes.WorkTabs{}:
      fields(typography, chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(Surfaces.Navigation{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}), SpatialModel.Stretch{}, SpatialModel.BlockFlow{}, SpatialModel.ContentFlow{}, 8n, 0n, 0n, 0n, 100n, passive())
    case SurfaceTypes.WorkTabGroup{}: base_style(typography)
    case SurfaceTypes.WorkChoiceRow{}: base_style(typography)
    case SurfaceTypes.WorkOverviewButton{count}: ordinary_button(typography)
    case SurfaceTypes.WorkTab{selected}: work_tab_style(selected, typography)
    case SurfaceTypes.Navigation{}:
      with_arrangement(with_content_area(fields(typography, chrome(Design.TextForeground{Surfaces.PrimaryText{}},
        surface(Surfaces.Navigation{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}),
        SpatialModel.Stretch{}, SpatialModel.ColumnFlow{}, SpatialModel.ScrollFlow{}, 8n, 8n, 4n,
        0n, 100n, passive()), Enclosure.area(Enclosure.Navigation{})), Enclosure.SeparateFrames{Enclosure.NavigationRows{}})
    case SurfaceTypes.NavigationEntry{selected}: navigation_family_style(selected, 6n, 5n, typography)
    case SurfaceTypes.NavigationCollection{}: base_style(typography)
    case SurfaceTypes.NavigationSection{}: base_style(typography)
    case SurfaceTypes.NavigationHeader{}:
      fields(typography, base_chrome(),
        SpatialModel.Stretch{}, SpatialModel.RowFlow{}, SpatialModel.ContentFlow{}, 0n, 4n, 8n,
        36n, 100n, passive())
    case SurfaceTypes.Main{}:
      fields(typography, chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(Surfaces.Canvas{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}), SpatialModel.Stretch{},
        SpatialModel.ColumnFlow{}, SpatialModel.ScrollFlow{}, 0n, 0n, 0n, 0n, 100n, passive())
    case SurfaceTypes.Heading{}:
      fields(typography, base_chrome(),
        SpatialModel.Stretch{}, SpatialModel.SplitRowFlow{}, SpatialModel.ContentFlow{}, 0n, 0n, 8n,
        46n, 100n, passive())
    case SurfaceTypes.Timeline{}:
      with_arrangement(fields(typography, base_chrome(), SpatialModel.Stretch{}, SpatialModel.ColumnFlow{},
        SpatialModel.ContentFlow{}, 0n, 0n, 16n, 0n, 100n, passive()), Enclosure.SeparateFrames{Enclosure.Messages{}})
    case SurfaceTypes.Activity{}:
      fields(typography,
        chrome(Design.TextForeground{Surfaces.SecondaryText{}}, surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}),
        SpatialModel.Stretch{}, SpatialModel.ColumnFlow{}, SpatialModel.ContentFlow{}, 0n, 0n, 4n,
        0n, 100n, passive())
    case SurfaceTypes.UserMessage{}:
      with_content_area(fields(typography, chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(Surfaces.Inset{}, Surfaces.Rest{}),
        transparent(), 0n, 16n, False{}), SpatialModel.Trailing{}, SpatialModel.BlockFlow{},
        SpatialModel.ContentFlow{}, 12n, 8n, 0n, 0n, 70n, passive()), Enclosure.area(Enclosure.UserMessage{}))
    case SurfaceTypes.AssistantMessage{}:
      fields(typography, base_chrome(), SpatialModel.Leading{}, SpatialModel.BlockFlow{},
        SpatialModel.ContentFlow{}, 0n, 0n, 0n, 0n, 100n, passive())
    case SurfaceTypes.Composer{}:
      with_content_area(fields(typography, surface_chrome(16n, True{}), SpatialModel.Stretch{},
        SpatialModel.ColumnFlow{}, SpatialModel.ContentFlow{}, 12n, 0n, 4n, 0n, 100n, passive()), Enclosure.area(Enclosure.Composer{}))
    case SurfaceTypes.DialogActions{}: fields(typography, base_chrome(), SpatialModel.Stretch{}, SpatialModel.RowFlow{}, SpatialModel.ContentFlow{}, 0n, 0n, 8n, 0n, 100n, passive())
    case SurfaceTypes.ComposerActions{}: toolbar_style(SpatialModel.SplitRowFlow{}, typography)
    case SurfaceTypes.Approval{}:
      with_content_area(fields(typography, chrome(Design.TextForeground{Surfaces.PrimaryText{}},
        surface(Surfaces.Content{}, Surfaces.Rest{}),
        paint("--color-token-editor-warning-foreground"), 1n, 12n, False{}),
        SpatialModel.Stretch{}, SpatialModel.ColumnFlow{}, SpatialModel.ContentFlow{}, 12n, 12n, 8n,
        0n, 100n, passive()), Enclosure.area(Enclosure.Approval{}))
    case SurfaceTypes.Toolbar{}: toolbar_style(SpatialModel.RowFlow{}, typography)
    case SurfaceTypes.CodeBlock{}:
      with_content_area(fields(typography,
        chrome(Design.TextForeground{Surfaces.PrimaryText{}}, surface(Surfaces.Inset{}, Surfaces.Rest{}),
          paint("--color-token-border-default"), 1n, 8n, False{}),
        SpatialModel.Stretch{}, SpatialModel.ColumnFlow{}, SpatialModel.CodeOverflow{}, 12n, 12n, 4n,
        0n, 100n, passive()), Enclosure.area(Enclosure.CodeBlock{}))
    case SurfaceTypes.ApprovalQueue{}:
      fields(typography, base_chrome(), SpatialModel.Stretch{}, SpatialModel.ColumnFlow{},
        SpatialModel.ScrollFlow{}, 0n, 0n, 8n, 0n, 100n, passive())
    case SurfaceTypes.Section{}:
      with_arrangement(fields(typography, base_chrome(), SpatialModel.Stretch{}, SpatialModel.ColumnFlow{},
        SpatialModel.ContentFlow{}, 0n, 0n, 12n, 0n, 100n, passive()), Enclosure.SeparateFrames{Enclosure.Sections{}})
    case SurfaceTypes.Dialog{}:
      with_arrangement(with_content_area(surface_style(SpatialModel.ColumnFlow{}, SpatialModel.ContentFlow{}, 0n, 0n, 0n, 16n, True{}, typography), Enclosure.DialogPartitions{}), Enclosure.JoinedPartitions{})
    case SurfaceTypes.Menu{}:
      with_arrangement(with_content_area(fields(typography, chrome(Design.TextForeground{Surfaces.PrimaryText{}},
        surface(Surfaces.Floating{}, Surfaces.Rest{}),
        paint("--color-token-border-default"), 1n, 12n, True{}),
        SpatialModel.Stretch{}, SpatialModel.ColumnFlow{}, SpatialModel.ScrollFlow{}, 0n, 0n, 2n,
        0n, 100n, passive()), Enclosure.area(Enclosure.Menu{})), Enclosure.SeparateFrames{Enclosure.MenuItems{}})
    case SurfaceTypes.Details{}:
      with_arrangement(with_content_area(surface_style(SpatialModel.ColumnFlow{}, SpatialModel.ScrollFlow{}, 16n, 16n, 16n, 0n, False{}, typography), Enclosure.area(Enclosure.Details{})), Enclosure.SeparateFrames{Enclosure.Sections{}})
    case SurfaceTypes.Card{}:
      with_arrangement(with_content_area(surface_style(SpatialModel.ColumnFlow{}, SpatialModel.ContentFlow{}, 12n, 12n, 8n, 9n, True{}, typography), Enclosure.area(Enclosure.Card{})), Enclosure.SeparateFrames{Enclosure.CardSections{}})
    case SurfaceTypes.PrimaryButton{}: primary_button(typography)
    case SurfaceTypes.DestructiveButton{}: destructive_button(typography)
    case SurfaceTypes.SelectedButton{}: selected_button(typography)
    case SurfaceTypes.Button{}: ordinary_button(typography)
    case SurfaceTypes.Field{}: field_style(meaning, typography)
    case SurfaceTypes.Content{}: base_style(typography)
    case SurfaceTypes.Alert{}: base_style(typography)

def navigation_row(style_value: Design.Style) -> Design.Style:
  Design.Style{text, style_chrome, alignment, flow, overflow, +content_frame, minimum_height, maximum_width_percent, states} = style_value
  Design.Style{T.activity(text), style_chrome, alignment, flow, overflow, content_frame, Activity.supporting_minimum(Activity.initial()), maximum_width_percent, states}

def style_in_context(role: SurfaceTypes.Role, meaning: SurfaceTypes.Meaning,
  inside_navigation: Bool, +typography: T.Presentation) -> Design.Style:
  match role inside_navigation:
    case SurfaceTypes.Button{} True{}: navigation_row(style(role, meaning, typography))
    case SurfaceTypes.SelectedButton{} True{}: navigation_row(style(role, meaning, typography))
    case _ _: style(role, meaning, typography)

def navigation_context(context: Controls.Context) -> Bool:
  match context:
    case Controls.Context{Controls.NavigationArea{compact}, selection, code, appearance, access, open, layers, execution, source_family, supporting_form, attention, navigation_depth}: True{}
    case _: False{}

def rounded_chrome(value: Design.Chrome, radius: Nat) -> Design.Chrome:
  Design.Chrome{foreground, background, border, width, old_radius, shadow} = value
  Design.Chrome{foreground, background, border, width, radius, shadow}

def layout_inline_inset(layout: Controls.ContentLayout) -> Nat:
  Controls.ContentLayout{alignment, content_area, gap} = layout
  Enclosure.inline(content_area)

def chrome_border_width(value: Design.Chrome) -> Nat:
  Design.Chrome{foreground, background, border, border_width, radius, shadow} = value
  border_width

def style_border_width(value: Design.Style) -> Nat:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  chrome_border_width(chrome)

def geometry_icon_size(value: Controls.Geometry) -> Nat:
  Controls.Geometry{demand, icon, radius, leading} = value
  icon

def choice_intrinsic_height(description: Maybe<&2, String>, +text: T.Presentation, layout: Controls.ChoiceContentLayout) -> Nat:
  match description layout:
    case None{} Controls.ChoiceContentLayout{text_gap, mark_extent, mark_icon_extent}: Nat.max(mark_icon_extent, text_line_height(NaturalSize.limit(), text))
    case Some{description} Controls.ChoiceContentLayout{text_gap, mark_extent, mark_icon_extent}: Nat.max(mark_icon_extent, (text_line_height(NaturalSize.limit(), text) + text_gap + text_line_height(NaturalSize.limit(), T.supporting(text)) : Nat))

def intrinsic_content_height(face: Controls.Face, +text: T.Presentation, +geometry: Controls.Geometry) -> Nat:
  match face:
    case Controls.IconFace{icon}: geometry_icon_size(geometry)
    case Controls.PermissionFace{filesystem, network, approval}: geometry_icon_size(geometry)
    case Controls.TextFace{label}: text_line_height(NaturalSize.limit(), text)
    case Controls.UnbrokenFace{label}: text_line_height(NaturalSize.limit(), text)
    case Controls.SingleLineFace{label}: text_line_height(NaturalSize.limit(), text)
    case Controls.IconTextFace{icon, label}: Nat.max(text_line_height(NaturalSize.limit(), text), geometry_icon_size(geometry))
    case Controls.UnbrokenIconTextFace{icon, label}: Nat.max(text_line_height(NaturalSize.limit(), text), geometry_icon_size(geometry))
    # Property text demand is measured by layout/SOURCE; this is only the glyph floor.
    case Controls.PropertyFace{property}: geometry_icon_size(geometry)
    case Controls.CompactPropertyFace{property}: geometry_icon_size(geometry)
    case Controls.SettingFace{subject, title, current}: Nat.max(text_line_height(NaturalSize.limit(), text), geometry_icon_size(geometry))
    case Controls.PickerFace{leading, label}: Nat.max(text_line_height(NaturalSize.limit(), text), geometry_icon_size(geometry))
    case Controls.DisclosureFace{label, expanded}: Nat.max(text_line_height(NaturalSize.limit(), text), geometry_icon_size(geometry))
    case Controls.ChoiceFace{label, description, icon, checked}: choice_intrinsic_height(description, text, Controls.choice_content_layout(geometry))

def action_style_insets(value: Design.Style, +geometry: Controls.Geometry, +content_area: Enclosure.ContentArea, content_gap: Nat, content_height: Nat) -> Design.Style:
  Design.Style{+text, +style_chrome, alignment, flow, overflow, +content_frame, old_height, maximum_width_percent, states} = value
  Controls.Geometry{demand, icon_size, +radius, leading_slot} = geometry
  minimum_height = Controls.geometry_minimum_height(geometry)
  required_height = Enclosure.extent_height(Enclosure.required_extent(0n, content_height,
    chrome_border_width(style_chrome), content_area))
  Design.Style{text, rounded_chrome(style_chrome, radius), alignment, SpatialModel.RowFlow{}, overflow, Enclosure.Frame{content_area, Enclosure.EmbeddedContent{content_gap}}, Nat.max(minimum_height, required_height), maximum_width_percent, states}

def action_content_style(value: Design.Style, layout: Controls.ContentLayout, geometry: Controls.Geometry, content_height: Nat) -> Design.Style:
  Controls.ContentLayout{content_alignment, content_area, content_gap} = layout
  action_style_insets(value, geometry, content_area, content_gap, content_height)

def action_flow(face: Controls.Face, layout: Controls.ContentLayout) -> SpatialModel.Flow:
  match face layout:
    case Controls.SingleLineFace{text} _: SpatialModel.BlockFlow{}
    case Controls.ChoiceFace{text, description, icon, checked} _: SpatialModel.ChoiceFlow{}
    case _ Controls.ContentLayout{alignment, content_area, gap}: SpatialModel.InlineControlFlow{alignment}

def with_flow(value: Design.Style, flow: SpatialModel.Flow) -> Design.Style:
  Design.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states}

def action_style(+value: Design.Style, +face: Controls.Face, +geometry: Controls.Geometry) -> Design.Style:
  +layout = Controls.content_layout(face)
  with_flow(action_content_style(value, layout, geometry, intrinsic_content_height(face, Design.style_text(value), geometry)), action_flow(face, layout))

def selection_style(value: Design.Style, behavior: Controls.Behavior, +typography: T.Presentation) -> Design.Style:
  match behavior:
    case Controls.Radio{selected}: choice_button(selected, Design.style_text(value))
    case Controls.ChoiceRadio{selected}: alternative_button(selected, Design.style_text(value))
    case Controls.MenuCheckbox{selected}: choice_button(selected, Design.style_text(value))
    case Controls.ChoiceCheckbox{selected}: alternative_button(selected, Design.style_text(value))
    case Controls.Toggle{selected}: choice_button(selected, Design.style_text(value))
    case _: value

def feedback_style(value: Design.Style, feedback: Controls.Feedback, +typography: T.Presentation) -> Design.Style:
  match feedback:
    case Controls.Failed{message}: destructive_button(Design.style_text(value))
    case _: value

def control_style(value: Design.Style, representation: Controls.Representation, +typography: T.Presentation) -> Design.Style:
  match representation:
    case Controls.Action{Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback}}:
      action_style(feedback_style(selection_style(value, behavior, typography), feedback, typography), face, geometry)
    case _: value

def activity_content_height(face: Controls.Face, +text: T.Presentation, +geometry: Controls.Geometry) -> Nat:
  match face:
    case Controls.ChoiceFace{label, description, icon, checked}:
      choice_intrinsic_height(description, text, Controls.ChoiceContentLayout{Activity.length(NaturalSize.limit(), text, 2n), Activity.slot(NaturalSize.limit(), text), Activity.icon(NaturalSize.limit(), text)})
    case _: intrinsic_content_height(face, text, geometry)

def activity_control_style_when(enabled: Bool, +value: Design.Style, representation: Controls.Representation) -> Design.Style:
  match enabled representation:
    case True{} Controls.Action{Controls.Button{input, availability, name, +face, behavior, +geometry, placement, feedback}}:
      +text = Design.style_text(value)
      +scaled = Controls.geometry_at(text, geometry)
      +layout = Controls.content_layout_at(text, face)
      with_flow(action_content_style(value, layout, scaled, activity_content_height(face, text, scaled)), action_flow(face, layout))
    case True{} Controls.Input{Controls.FormInput{meaning, name, Controls.ToggleInput{}, label, availability}}: value
    case True{} Controls.Input{input}:
      +text = Design.style_text(value)
      field_values(NaturalSize.limit(), with_content_area(value, Enclosure.frame_content(Activity.row_frame(NaturalSize.limit(), text))),
        style_border_width(value), Activity.target(NaturalSize.limit(), text, Design.style_minimum_height(value)), Activity.length(NaturalSize.limit(), text, 6n))
    case _ _: value

def activity_control_style(+value: Design.Style, representation: Controls.Representation) -> Design.Style:
  activity_control_style_when(T.is_activity(Design.style_text(value)), value, representation)

def semantic_style(semantic: String, fallback: Design.Style) -> Design.Style:
  match semantic:
    case "creation/title":
      fields(Design.style_text(fallback), base_chrome(),
        SpatialModel.Centered{}, SpatialModel.BlockFlow{}, SpatialModel.ContentFlow{}, 0n, 0n, 0n,
        0n, 100n, passive())
    case "creation/context":
      fields(Design.style_text(fallback),
        chrome(Design.TextForeground{Surfaces.SecondaryText{}}, surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, 0n, False{}),
        SpatialModel.Centered{}, SpatialModel.ColumnFlow{}, SpatialModel.ContentFlow{}, 0n, 0n, 8n,
        0n, 100n, passive())
    case _: fallback

def modeled_container(value: Design.Style, flow: SpatialModel.Flow, gap: Nat) -> Design.Style:
  Design.Style{text, chrome, alignment, old_flow, overflow, Enclosure.Frame{content, arrangement}, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, flow, overflow, Enclosure.Frame{content, Enclosure.EmbeddedContent{gap}}, minimum, maximum, states}

def embedded_control(value: Design.Style) -> Design.Style:
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
  +chrome = chrome(foreground, surface(Surfaces.EmbeddedAction{}, Surfaces.Rest{}), transparent(), 0n, radius, shadow)
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, role_interactive(chrome, Surfaces.EmbeddedAction{})}

def embedded_label_style(value: Design.Style) -> Design.Style:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, SpatialModel.BlockFlow{}, SpatialModel.SingleLineOverflow{}, Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}, minimum, maximum, states}

def project_label_style(value: Design.Style) -> Design.Style:
  embedded_label_style(embedded_control(value))

def chooser_embedded_style(selected: Maybe<&2, Nat>, value: Design.Style) -> Design.Style:
  Design.Style{old_text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  +text = old_text
  fields(text, chrome, alignment, flow, overflow, 0n, 4n, 4n, Nat.max(minimum, (text_line_height(NaturalSize.limit(), text) + 8n : Nat)), maximum, states)

def chooser_style(selected: Maybe<&2, Nat>, value: Design.Style) -> Design.Style:
  chooser_embedded_style(selected, embedded_control(value))

def work_title_source_style(value: Design.Style) -> Design.Style:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Design.Style{text, chrome, SpatialModel.Leading{}, SpatialModel.BlockFlow{}, SpatialModel.SingleLineOverflow{}, Enclosure.Frame{Enclosure.ambient(12n, 8n), Enclosure.EmbeddedContent{0n}}, Nat.max(minimum, 40n), maximum, states}

def work_choice_border(selected: Bool) -> Design.Paint:
  match selected:
    case True{}: paint("--color-token-focus-border")
    case False{}: paint("--color-token-border-default")

def work_choice_source_style(+selected: Bool, value: Design.Style) -> Design.Style:
  Design.Style{text, old_chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  +bg: Design.Paint = surface(Surfaces.Choice{selected}, Surfaces.Rest{})
  +fg: Design.Paint = Design.TextForeground{Surfaces.PrimaryText{}}
  +border: Design.Paint = work_choice_border(selected)
  +chrome: Design.Chrome = chrome(fg, bg, border, 1n, 10n, False{})
  fields(text, chrome, SpatialModel.Leading{}, SpatialModel.ChoiceFlow{}, SpatialModel.ContentFlow{}, 12n, 12n, 8n, 120n, maximum,
    role_interactive(chrome, Surfaces.Choice{selected}))

def work_control_style(work: Bool, face: Controls.Face, fallback: Design.Style) -> Design.Style:
  match work face:
    case True{} Controls.SingleLineFace{text}: work_title_source_style(fallback)
    case True{} Controls.ChoiceFace{text, description, icon, selected}: work_choice_source_style(selected, fallback)
    case _ Controls.SingleLineFace{text}: project_label_style(fallback)
    case _ _: fallback

def source_control_style(family: Controls.SourceFamily, representation: Controls.Representation, value: Design.Style) -> Design.Style:
  match family representation:
    case Controls.SourceFamily{SurfaceTypes.Node{owner, semantic, label, role, SurfaceTypes.ProjectChooser{selected}, children}} Controls.Action{Controls.Button{input, availability, name, Controls.PickerFace{Some{Controls.Folder{}}, text}, behavior, geometry, placement, feedback}}: chooser_style(selected, value)
    case _ Controls.Action{Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback}}: work_control_style(Controls.work_selection_input(input), face, value)
    case _ _: value

def source_style(header: Bool, family: Controls.SourceFamily, value: Design.Style, +typography: T.Presentation) -> Design.Style:
  match header family:
    case True{} Controls.SourceFamily{SurfaceTypes.Node{owner, semantic, label, role, SurfaceTypes.ProjectGroup{project, selected, expanded}, children}}: navigation_family_style(selected, 2n, 0n, typography)
    case _ _: value

def project_group_style(+typography: T.Presentation) -> Design.Style:
  with_arrangement(fields(typography, base_chrome(), SpatialModel.Stretch{}, SpatialModel.ColumnFlow{}, SpatialModel.ContentFlow{}, 0n, 0n, 4n, 0n, 100n, passive()), Enclosure.SeparateFrames{Enclosure.NavigationRows{}})

def choice_group_style(value: Design.Style) -> Design.Style:
  with_arrangement(with_flow(value, SpatialModel.ColumnFlow{}), Enclosure.SeparateFrames{Enclosure.MenuItems{}})

def source_header_style(+key: UIIdentity.Key, family: Controls.SourceFamily, value: Design.Style, +typography: T.Presentation) -> Design.Style:
  match family:
    case Controls.SourceFamily{+node}:
      SurfaceTypes.Node{+owner, semantic, label, role, source, children} = node
      source_style(UIIdentity.same(key, UIIdentity.part(owner, "actions")), Controls.SourceFamily{node}, value, typography)
    case _: value

def lane_style(value: Design.Style) -> Design.Style:
  Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, Enclosure.Frame{content, arrangement}, minimum, maximum, states} = value
  Design.Style{text, Design.Chrome{foreground, surface(Surfaces.Lane{Surfaces.Neutral{}}, Surfaces.Rest{}), border, width, radius, shadow}, alignment, flow, overflow, Enclosure.Frame{Enclosure.area(Enclosure.Lane{}), arrangement}, minimum, maximum, states}

def action_focus_states(+chrome: Design.Chrome, states: Design.ControlStates) -> Design.ControlStates:
  Design.Chrome{+foreground, +background, +border, width, radius, shadow} = chrome
  match states:
    case Design.Interactive{hover, pressed, opacity, focus}: Design.Interactive{hover, pressed, opacity, Design.FocusIndicator{border, 1n, 0n}}
    case Design.SurfaceFeedback{hover, pressed}: Design.Interactive{hover, pressed, 40n, Design.FocusIndicator{border, 1n, 0n}}
    case Design.Passive{}: Design.Interactive{Design.PhasePaint{foreground, background}, Design.PhasePaint{foreground, background}, 40n, Design.FocusIndicator{border, 1n, 0n}}

def action_unit_style(value: Design.Style) -> Design.Style:
  Design.Style{text, +chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, flow, overflow, Activity.frame(Activity.initial()), minimum, maximum, action_focus_states(chrome, states)}

def activity_action_unit_style_when(enabled: Bool, value: Design.Style) -> Design.Style:
  match enabled:
    case False{}: action_unit_style(value)
    case True{}:
      Design.Style{+text, +chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
      Design.Style{text, chrome, alignment, flow, overflow, Hierarchy.heading_frame(Hierarchy.for_text(NaturalSize.limit(), text)), minimum, maximum, action_focus_states(chrome, states)}

def activity_action_unit_style(+value: Design.Style) -> Design.Style:
  activity_action_unit_style_when(T.is_activity(Design.style_text(value)), value)

def activity_member_style_when(enabled: Bool, +value: Design.Style) -> Design.Style:
  match enabled:
    case False{}: modeled_container(value, SpatialModel.ColumnFlow{}, 8n)
    case True{}:
      Design.Style{+text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
      Design.Style{text, chrome, alignment, SpatialModel.RowFlow{}, overflow, Activity.row_frame(NaturalSize.limit(), text), Nat.max(minimum, Activity.length(NaturalSize.limit(), text, 32n)), maximum, states}

def activity_member_style(+value: Design.Style) -> Design.Style:
  activity_member_style_when(T.is_activity(Design.style_text(value)), value)

def family_style(+key: UIIdentity.Key, meaning: SurfaceTypes.Meaning, family: Controls.SourceFamily, representation: Controls.Representation, +value: Design.Style, +typography: T.Presentation) -> Design.Style:
  match meaning:
    case SurfaceTypes.BoardLane{stage, count}: lane_style(value)
    case SurfaceTypes.ProjectGroup{project, selected, expanded}: project_group_style(typography)
    case SurfaceTypes.TaskRow{task, status, selected}: navigation_family_style(selected, 6n, 0n, typography)
    case SurfaceTypes.InformationText{Information.NavigationCaption{}}: fields(T.information_role(Information.NavigationCaption{}, T.presentation_scale(typography)), chrome(Design.TextForeground{Surfaces.SecondaryText{}}, transparent(), transparent(), 0n, 0n, False{}), SpatialModel.Leading{}, SpatialModel.BlockFlow{}, SpatialModel.ContentFlow{}, T.scaled(NaturalSize.limit(), 8n, T.presentation_scale(typography)), 0n, 0n, 0n, 100n, passive())
    case SurfaceTypes.ProjectChooser{selected}: fields(typography, base_chrome(), SpatialModel.Stretch{}, SpatialModel.InlineControlFlow{SpatialModel.LeadingContents{}}, SpatialModel.ContentFlow{}, 0n, 0n, 0n, 0n, 100n, passive())
    case SurfaceTypes.ContextSummary{observation}: with_content_area(modeled_container(value, SpatialModel.ColumnFlow{}, 4n), Enclosure.ambient(8n, Enclosure.block(Enclosure.frame_content(Design.style_frame(value)))))
    case SurfaceTypes.DirectoryRow{path, primary}: activity_member_style(value)
    case SurfaceTypes.ChoiceGroup{}: choice_group_style(value)
    case SurfaceTypes.DecisionGroup{decision}: choice_group_style(value)
    case SurfaceTypes.WorkspaceMember{collection, path}: activity_member_style(value)
    case SurfaceTypes.ActionUnit{action}: activity_action_unit_style(value)
    case SurfaceTypes.Region{}: source_header_style(key, family, value, typography)
    case SurfaceTypes.PageContext{conversation}: source_header_style(key, family, value, typography)
    case SurfaceTypes.ActivityContent{expanded, audit}: source_header_style(key, family, value, typography)
    case _: source_control_style(family, representation, value)

def source_content_style(content: Controls.SourceContent, geometry: Controls.Geometry, value: Design.Style) -> Design.Style:
  match content:
    case Controls.TitleContent{caption}:
      Design.Style{+text, chrome, alignment, flow, overflow, Enclosure.Frame{area, arrangement}, minimum, maximum, states} = value
      target_height = Controls.geometry_minimum_height(geometry)
      Design.Style{T.with_emphasis(T.with_tier(text, T.Body{}), T.Strong{}), chrome, SpatialModel.Leading{}, SpatialModel.BlockFlow{}, overflow,
        Enclosure.Frame{Enclosure.area(Enclosure.TextControl{}), arrangement}, Nat.max(minimum, target_height), maximum, states}
    case _: value

def resolved_source_style(content: Controls.SourceContent, representation: Controls.Representation, value: Design.Style) -> Design.Style:
  match representation:
    case Controls.Action{Controls.Button{input, availability, name, face, behavior, geometry, placement, feedback}}: source_content_style(content, geometry, value)
    case _: value

def source_action_style(meaning: SurfaceTypes.Meaning, context: Controls.Context, +representation: Controls.Representation, value: Design.Style) -> Design.Style:
  match meaning:
    case SurfaceTypes.SettingEntry{subject, current, input, availability}: resolved_source_style(Controls.representation_content(context, representation), representation, value)
    case SurfaceTypes.Activate{input, availability}: resolved_source_style(Controls.representation_content(context, representation), representation, value)
    case _: value

def feedback_phase(active:Bool) -> Surfaces.Phase:
  match active:
    case True{}: Surfaces.Hovered{}
    case False{}: Surfaces.Rest{}

def resolved_feedback_chrome(value:Design.Style, background:Design.Paint) -> Design.Style:
  Design.Style{text, Design.Chrome{foreground, old_background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states}

# NOTE: Project headers are regions; native-control state channels alone cannot paint their whole row.
def project_row_feedback(meaning:SurfaceTypes.Meaning, representation:Controls.Representation, +value:Design.Style) -> Design.Style:
  match meaning representation:
    case SurfaceTypes.Region{} Controls.NavigationRow{owner, depth, visible, active}: resolved_feedback_chrome(value, phase_background(value, feedback_phase(active)))
    case _ _: value

def final_style(key: UIIdentity.Key, +meaning: SurfaceTypes.Meaning, +context: Controls.Context, +representation: Controls.Representation, value: Design.Style, +typography: T.Presentation) -> Design.Style:
  +family_style_value = family_style(key, meaning, Controls.source_reference(context), representation, value, typography)
  source_action_style(meaning, context, representation, project_row_feedback(meaning, representation, family_style_value))

def start_page(content: InteractionTypes.Scene) -> Bool:
  InteractionTypes.Scene{View.Scene{navigation, main, layers, arrangement, attention}, settings, transfers, preview, code, directory_picker} = content
  match main:
    case View.StartPage{composer}: True{}
    case _: False{}

def enters_main(role: SurfaceTypes.Role, inherited: Bool) -> Bool:
  match role:
    case SurfaceTypes.Main{}: True{}
    case _: inherited

def heading_tier(in_main: Bool, start: Bool) -> T.Tier:
  match in_main start:
    case True{} True{}: T.Display{}
    case True{} False{}: T.Title{}
    case False{} _: T.Section{}

def field_tier(meaning: SurfaceTypes.Meaning) -> T.Tier:
  match meaning:
    case SurfaceTypes.Edit{editor, field, Forms.Multiline{}, value, choices}: T.Body{}
    case _: T.Body{}

def information_role_fields(role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, inherited: T.Presentation, in_main: Bool, start: Bool, +scale: T.Scale) -> T.Presentation:
  match role meaning:
    case SurfaceTypes.GlobalNavigation{compact} _: T.Presentation{T.ActivitySupport{}, T.Regular{}, scale}
    case SurfaceTypes.GlobalNavigationEntry{selected, compact} _: T.Presentation{T.ActivitySupport{}, T.Regular{}, scale}
    case SurfaceTypes.CompactHeader{} _: T.Presentation{T.ActivityPrimary{}, T.Regular{}, scale}
    case SurfaceTypes.CompactWorkScope{title, count} _: T.Presentation{T.ActivityPrimary{}, T.Regular{}, scale}
    case SurfaceTypes.CompactNavigationMenu{} _: T.Presentation{T.ActivityPrimary{}, T.Regular{}, scale}
    case SurfaceTypes.CompactNavigationEntry{selected} _: T.Presentation{T.ActivityPrimary{}, T.Regular{}, scale}
    case SurfaceTypes.Navigation{} _: T.Presentation{T.ActivityPrimary{}, T.Regular{}, scale}
    case SurfaceTypes.NavigationHeader{} _: T.Presentation{T.Body{}, T.Medium{}, scale}
    case SurfaceTypes.WorkTabGroup{} _: T.Presentation{T.ActivityPrimary{}, T.Regular{}, scale}
    case SurfaceTypes.WorkChoiceRow{} _: T.Presentation{T.Body{}, T.Regular{}, scale}
    case SurfaceTypes.WorkOverviewButton{count} _: T.Presentation{T.ActivityPrimary{}, T.Medium{}, scale}
    case SurfaceTypes.WorkTabs{} _: T.Presentation{T.ActivityPrimary{}, T.Regular{}, scale}
    case SurfaceTypes.WorkTab{selected} _: T.Presentation{T.ActivityPrimary{}, T.Medium{}, scale}
    case SurfaceTypes.NavigationEntry{selected} _: T.Presentation{T.ActivityPrimary{}, T.Regular{}, scale}
    case _ SurfaceTypes.InformationText{Information.NavigationCaption{}}: T.Presentation{T.ActivitySupport{}, T.Regular{}, scale}
    case SurfaceTypes.Heading{} _: T.Presentation{heading_tier(in_main, start), T.Medium{}, scale}
    case SurfaceTypes.Activity{} _: T.Presentation{T.Support{}, T.Regular{}, scale}
    case SurfaceTypes.UserMessage{} _: T.Presentation{T.Body{}, T.Regular{}, scale}
    case SurfaceTypes.AssistantMessage{} _: T.Presentation{T.Body{}, T.Regular{}, scale}
    case SurfaceTypes.Composer{} _: T.Presentation{T.Body{}, T.Regular{}, scale}
    case SurfaceTypes.CodeBlock{} _: T.Presentation{T.CodeBody{}, T.Regular{}, scale}
    case SurfaceTypes.Button{} _: T.Presentation{T.Body{}, T.Medium{}, scale}
    case SurfaceTypes.PrimaryButton{} _: T.Presentation{T.Body{}, T.Medium{}, scale}
    case SurfaceTypes.DestructiveButton{} _: T.Presentation{T.Body{}, T.Medium{}, scale}
    case SurfaceTypes.SelectedButton{} _: T.Presentation{T.Body{}, T.Medium{}, scale}
    case SurfaceTypes.Field{} _: T.Presentation{field_tier(meaning), T.Regular{}, scale}
    case SurfaceTypes.Dialog{} _: T.Presentation{T.Body{}, T.Regular{}, scale}
    case SurfaceTypes.Menu{} _: T.Presentation{T.Body{}, T.Regular{}, scale}
    case SurfaceTypes.Details{} _: T.Presentation{T.Body{}, T.Regular{}, scale}
    case SurfaceTypes.Toolbar{} _: T.Presentation{T.Body{}, T.Regular{}, scale}
    case SurfaceTypes.DialogActions{} _: T.Presentation{T.Body{}, T.Regular{}, scale}
    case SurfaceTypes.ComposerActions{} _: T.Presentation{T.Body{}, T.Regular{}, scale}
    case _ _: inherited

def information_activity(meaning: SurfaceTypes.Meaning, inherited: T.Presentation, resolved: T.Presentation) -> T.Presentation:
  match meaning:
    case SurfaceTypes.ActivityGroup{activity, dismiss, outside, escape}: T.activity(resolved)
    case SurfaceTypes.ActivityRow{SurfaceTypes.SupportingRow{}}: T.supporting(T.activity(resolved))
    case SurfaceTypes.ActivityRow{row}: T.activity(resolved)
    case _: T.inherit_activity(inherited, resolved)

def information_role(role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning, +inherited: T.Presentation, in_main: Bool, start: Bool) -> T.Presentation:
  information_activity(meaning, inherited, information_role_fields(role, meaning, inherited, in_main, start, T.presentation_scale(inherited)))

def alert_style(role: SurfaceTypes.Role, value: Design.Style) -> Design.Style:
  match role:
    case SurfaceTypes.Alert{}:
      Design.Style{text, Design.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
      Design.Style{T.with_emphasis(T.with_tier(text, T.Body{}), T.Regular{}),
        Design.Chrome{Design.ThemeToken{"--color-text-danger"}, background, border, width, radius, shadow}, alignment, flow, SpatialModel.TextFlow{T.WrapAnywhere{}}, frame, minimum, maximum, states}
    case _: value

def activity_controls(role: SurfaceTypes.Role, context: Controls.Context, value: Design.Style) -> Design.Style:
  match role context:
    case SurfaceTypes.Toolbar{} Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, execution, family, supporting_form, attention, navigation_depth}:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
      modeled_container(Design.Style{text, chrome, SpatialModel.Leading{}, flow, overflow, frame, minimum, maximum, states}, SpatialModel.RowFlow{}, Activity.clearance(Activity.initial()))
    case SurfaceTypes.ComposerActions{} _:
      Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
      modeled_container(Design.Style{text, chrome, SpatialModel.Trailing{}, flow, overflow, frame, minimum, maximum, states}, SpatialModel.SplitRowFlow{}, Activity.clearance(Activity.initial()))
    case _ _: value

def navigation_heading_style(value: Design.Style) -> Design.Style:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Design.Style{text, chrome, SpatialModel.Leading{}, SpatialModel.BlockFlow{}, overflow, Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}, 0n, maximum, states}

def navigation_role_style(role: SurfaceTypes.Role, family: Controls.SourceFamily, value: Design.Style) -> Design.Style:
  match role family:
    case SurfaceTypes.Heading{} Controls.SourceFamily{SurfaceTypes.Node{key, semantic, label, row_role, SurfaceTypes.ActivityRow{SurfaceTypes.NavigationRow{}}, children}}: navigation_heading_style(value)
    case _ _: value

def touch_navigation_minimum(value: Design.Style) -> Design.Style:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Design.Style{text, chrome, alignment, flow, overflow, frame, Nat.max(Controls.navigation_motor_floor(True{}), minimum), maximum, states}

def touch_navigation_style_when(enabled: Bool, value: Design.Style) -> Design.Style:
  match enabled:
    case True{}: touch_navigation_minimum(value)
    case False{}: value

def touch_navigation_style(enabled: Bool, representation: Controls.Representation, value: Design.Style) -> Design.Style:
  touch_navigation_style_when(enabled && Controls.navigation_motor_target(representation), value)

def prepared_style(+key: UIIdentity.Key, semantic: String, +role: SurfaceTypes.Role, +meaning: SurfaceTypes.Meaning,
  +local: Controls.Context, +control: Controls.Representation, +typography: T.Presentation) -> Design.Style:
  touch_navigation_style(Controls.touch_navigation_area(Controls.context_area(local)), control, activity_control_style(navigation_role_style(role, Controls.source_reference(local), activity_controls(role, local, alert_style(role, final_style(key, meaning, local, control, control_style(semantic_style(semantic, style_in_context(role, meaning, navigation_context(local), typography)), control, typography), typography)))), control))

def nodes_at(values: +List<SurfaceTypes.Node>, +context: Controls.Context, +inherited: T.Presentation, +in_main: Bool, +start: Bool) -> +List<Design.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+source, rest}:
      SurfaceTypes.Node{+key, +semantic, +label, +role, +meaning, children} = source
      +local = Controls.enter(source, context)
      +control = Controls.represent(key, meaning, label, role, local)
      +inside = enters_main(role, in_main)
      +typography = information_role(role, meaning, inherited, inside, start)
      +visual = prepared_style(key, semantic, role, meaning, local, control, typography)
      Con{Design.Node{key, semantic, label, role, meaning, visual,
        control, nodes_at(children, local, Design.style_text(visual), inside, start)}, nodes_at(rest, context, inherited, in_main, start)}

def theme(appearance: Services.Appearance, system_dark: Bool) -> Design.Theme:
  match appearance system_dark:
    case Services.SystemAppearance{} True{}: Design.Dark{}
    case Services.SystemAppearance{} False{}: Design.Light{}
    case Services.LightAppearance{} _: Design.Light{}
    case Services.DarkAppearance{} _: Design.Dark{}

def present_fields(+content: InteractionTypes.Scene, base: +List<SurfaceTypes.Node>, overlays: +List<SurfaceTypes.Node>,
  +context: Controls.Context, system_dark: Bool, active_scope: Maybe<&2, String>, +scale: T.Scale) -> Design.Surface:
  InteractionTypes.Scene{view, settings, transfers, preview, code, directory_picker} = content
  InteractionTypes.Settings{open, access, appearance, open_action,
    close_action, connect_action} = settings
  +initial_text: T.Presentation = T.Presentation{T.Body{}, T.Regular{}, scale}
  Design.Surface{content, theme(appearance, system_dark),
    nodes_at(base, context, initial_text, False{}, start_page(content)), nodes_at(overlays, context, initial_text, False{}, False{}), active_scope}

def present(surface: SurfaceTypes.Surface, system_dark: Bool, scale: T.Scale) -> Design.Surface:
  SurfaceTypes.Surface{+content, base, overlays, active_scope} = surface
  present_fields(content, base, overlays, Controls.initial(content), system_dark, active_scope, scale)


def present_supporting(surface: SurfaceTypes.Surface, system_dark: Bool, scale: T.Scale, form: Controls.SupportingForm) -> Design.Surface:
  SurfaceTypes.Surface{+content, base, overlays, active_scope} = surface
  present_fields(content, base, overlays, Controls.with_supporting_form(Controls.initial(content), form), system_dark, active_scope, scale)

def present_supporting_navigation(surface: SurfaceTypes.Surface, system_dark: Bool, scale: T.Scale, form: Controls.SupportingForm, attention: Navigation.Attention) -> Design.Surface:
  SurfaceTypes.Surface{+content, base, overlays, active_scope} = surface
  present_fields(content, base, overlays, Controls.with_navigation(Controls.with_supporting_form(Controls.initial(content), form), attention), system_dark, active_scope, scale)
