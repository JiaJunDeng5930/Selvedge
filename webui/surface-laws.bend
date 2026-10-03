import Base
import ./typography.bend as T
import ./surfaces.bend as Surfaces
import ./design.bend as Design
import ./appearance.bend as Appearance
import ./controls.bend as Controls
import ../BOARD.bend as Board
import ../core/interface.bend as UI
import ../core/form-fields.bend as Forms

























def input_phase(phase: Surfaces.Phase, +typography: T.Presentation) ->
  {Appearance.phase_background(Appearance.editable_field(typography), phase) == Design.SurfacePaint{Surfaces.Field{}, phase} : Design.Paint}:
  match phase:
    case Surfaces.Rest{}: {==}
    case Surfaces.Hovered{}: {==}
    case Surfaces.Pressed{}: {==}

def message_phase(entry: Forms.Entry, phase: Surfaces.Phase, +typography: T.Presentation) ->
  {Appearance.phase_background(Appearance.widget_field_style(Controls.MessageInput{}, entry, typography), phase) == Design.SurfacePaint{Surfaces.EmbeddedField{}, phase} : Design.Paint}:
  match phase:
    case Surfaces.Rest{}: {==}
    case Surfaces.Hovered{}: {==}
    case Surfaces.Pressed{}: {==}



def selected_control_phase(value: Design.Style, phase: Surfaces.Phase, +typography: T.Presentation) ->
  {Appearance.phase_background(Appearance.selection_style(value, Controls.Radio{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint}:
  match phase:
    case Surfaces.Rest{}: {==}
    case Surfaces.Hovered{}: {==}
    case Surfaces.Pressed{}: {==}

def toggle_control_phase(value: Design.Style, phase: Surfaces.Phase, +typography: T.Presentation) ->
  {Appearance.phase_background(Appearance.selection_style(value, Controls.Toggle{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint}:
  match phase:
    case Surfaces.Rest{}: {==}
    case Surfaces.Hovered{}: {==}
    case Surfaces.Pressed{}: {==}

def menu_choice_phase(value: Design.Style, phase: Surfaces.Phase, +typography: T.Presentation) ->
  {Appearance.phase_background(Appearance.selection_style(value, Controls.ChoiceRadio{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint}:
  match phase:
    case Surfaces.Rest{}: {==}
    case Surfaces.Hovered{}: {==}
    case Surfaces.Pressed{}: {==}















type Requirements is Type:
  Requirements{
    ordinary_foreground: {Surfaces.foreground(Surfaces.QuietAction{}) == Surfaces.Token{"--color-token-text-primary"} : Surfaces.Color},
    primary_foreground: {Surfaces.foreground(Surfaces.PrimaryAction{}) == Surfaces.Token{"--color-text-primary-solid"} : Surfaces.Color},
    destructive_foreground: {Surfaces.foreground(Surfaces.DestructiveAction{}) == Surfaces.Token{"--color-text-danger-ghost"} : Surfaces.Color},
    choice_foreground: @selected:Bool -> {Surfaces.foreground(Surfaces.Choice{selected}) == Surfaces.Token{"--color-token-text-primary"} : Surfaces.Color},
    primary_rest: {Surfaces.background(Surfaces.PrimaryAction{}, Surfaces.Rest{}) == Surfaces.Token{"--color-background-primary-solid"} : Surfaces.Color},
    primary_hover: {Surfaces.background(Surfaces.PrimaryAction{}, Surfaces.Hovered{}) == Surfaces.Token{"--color-background-primary-solid-hover"} : Surfaces.Color},
    primary_pressed: {Surfaces.background(Surfaces.PrimaryAction{}, Surfaces.Pressed{}) == Surfaces.Token{"--color-background-primary-solid-active"} : Surfaces.Color},
    field_phase_stable: @phase:Surfaces.Phase -> {Surfaces.background(Surfaces.Field{}, phase) == Surfaces.Token{"--color-token-main-surface-primary"} : Surfaces.Color},
    embedded_field_phase_stable: @phase:Surfaces.Phase -> {Surfaces.background(Surfaces.EmbeddedField{}, phase) == Surfaces.Clear{} : Surfaces.Color},
    embedded_action_phase_stable: @phase:Surfaces.Phase -> {Surfaces.background(Surfaces.EmbeddedAction{}, phase) == Surfaces.Clear{} : Surfaces.Color},
    selected_rest: {Surfaces.background(Surfaces.Choice{True{}}, Surfaces.Rest{}) == Surfaces.Token{"--color-background-segmented-selected"} : Surfaces.Color},
    selected_hover: {Surfaces.background(Surfaces.Choice{True{}}, Surfaces.Hovered{}) == Surfaces.Token{"--color-background-segmented-selected-hover"} : Surfaces.Color},
    unselected_rest: {Surfaces.background(Surfaces.Choice{False{}}, Surfaces.Rest{}) == Surfaces.Clear{} : Surfaces.Color},
    main_surface: @+typography:T.Presentation -> @meaning:UI.Meaning -> {Appearance.style_background(Appearance.style(UI.Main{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Canvas{}, Surfaces.Rest{}} : Design.Paint},
    navigation_surface: @+typography:T.Presentation -> @meaning:UI.Meaning -> {Appearance.style_background(Appearance.style(UI.Navigation{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Navigation{}, Surfaces.Rest{}} : Design.Paint},
    card_surface: @+typography:T.Presentation -> @meaning:UI.Meaning -> {Appearance.style_background(Appearance.style(UI.Card{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Content{}, Surfaces.Rest{}} : Design.Paint},
    dialog_surface: @+typography:T.Presentation -> @meaning:UI.Meaning -> {Appearance.style_background(Appearance.style(UI.Dialog{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Content{}, Surfaces.Rest{}} : Design.Paint},
    menu_surface: @+typography:T.Presentation -> @meaning:UI.Meaning -> {Appearance.style_background(Appearance.style(UI.Menu{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Floating{}, Surfaces.Rest{}} : Design.Paint},
    composer_surface: @+typography:T.Presentation -> @meaning:UI.Meaning -> {Appearance.style_background(Appearance.style(UI.Composer{}, meaning, typography)) == Design.SurfacePaint{Surfaces.Content{}, Surfaces.Rest{}} : Design.Paint},
    input_phase: @+typography:T.Presentation -> @phase:Surfaces.Phase -> {Appearance.phase_background(Appearance.editable_field(typography), phase) == Design.SurfacePaint{Surfaces.Field{}, phase} : Design.Paint},
    message_phase: @+typography:T.Presentation -> @entry:Forms.Entry -> @phase:Surfaces.Phase -> {Appearance.phase_background(Appearance.widget_field_style(Controls.MessageInput{}, entry, typography), phase) == Design.SurfacePaint{Surfaces.EmbeddedField{}, phase} : Design.Paint},
    board_search_surface: @+typography:T.Presentation -> @filter:Board.Filter -> {Appearance.style_background(Appearance.field_style(UI.BoardSearch{filter}, typography)) == Design.SurfacePaint{Surfaces.Inset{}, Surfaces.Rest{}} : Design.Paint},
    selected_control_phase: @+typography:T.Presentation -> @value:Design.Style -> @phase:Surfaces.Phase -> {Appearance.phase_background(Appearance.selection_style(value, Controls.Radio{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint},
    toggle_control_phase: @+typography:T.Presentation -> @value:Design.Style -> @phase:Surfaces.Phase -> {Appearance.phase_background(Appearance.selection_style(value, Controls.Toggle{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint},
    menu_choice_phase: @+typography:T.Presentation -> @value:Design.Style -> @phase:Surfaces.Phase -> {Appearance.phase_background(Appearance.selection_style(value, Controls.ChoiceRadio{True{}}, typography), phase) == Design.SurfacePaint{Surfaces.Choice{True{}}, phase} : Design.Paint}}

def evidence() -> Requirements:
  Requirements{{==}, {==}, {==}, selected => {==}, {==}, {==}, {==},

    phase => {==},
    phase => {==},
    phase => {==},
    {==},
    {==},
    {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => meaning => {==},
    +typography => phase => input_phase(phase, typography),
    +typography => entry => phase => message_phase(entry, phase, typography),
    +typography => filter => {==},
    +typography => value => phase => selected_control_phase(value, phase, typography),
    +typography => value => phase => toggle_control_phase(value, phase, typography),
    +typography => value => phase => menu_choice_phase(value, phase, typography)}
