import Base
import ../appearance/TYPOGRAPHY.bend as T
import ./SURFACES.bend as Surfaces
import ../appearance/DESIGN.bend as Design
import ../appearance/MODEL.bend as Appearance
import ./PROGRAM.bend as Controls
import ../../interaction/submission/FIELDS.bend as Forms
import ./surface-laws.bend as Rule

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

def Rule.evidence():
  Rule.Requirements{{==}, {==}, {==}, selected => {==}, {==}, {==}, {==},

    phase => {==},
    phase => {==},
    phase => {==},
    {==},
    {==},
    {==},
    {==},
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
