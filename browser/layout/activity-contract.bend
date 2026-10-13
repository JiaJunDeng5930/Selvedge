import ../../interaction/presentation/SURFACE.bend as Surface
import ./GEOMETRY.bend as Spatial
import ../../interaction/conversation/CODE.bend as Code
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/services/CONTEXT.bend as Workspace
import ../../interaction/presentation/MODEL.bend as View
import ../editor/MODEL.bend as EditorLayout
import Base
import ./ACTIVITY.bend as A
import ./enclosure.bend as E
import ../appearance/MODEL.bend as Appearance
import ../appearance/DESIGN.bend as Design
import ../appearance/TYPOGRAPHY.bend as T
import ../controls/PROGRAM.bend as Controls
import ../../interaction/experience/MODEL.bend as UX

def action_frame(+visual: Design.Style) -> Type:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  {Design.style_frame(Appearance.action_unit_style(visual)) == A.frame(A.initial()) : E.Frame}

def message_minimum(+capacity: Nat, +visual: Design.Style) -> Type:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border_paint, border, radius, shadow} = chrome
  {Appearance.message_field(capacity, visual) == Appearance.field_values(capacity, visual, 0n, 0n, radius) : Design.Style}

def message_selection(+capacity: Nat, kind: EditorLayout.FieldKind, +visual: Design.Style) -> Type:
  {Appearance.select_field_constructor(kind, Controls.MessageInput{})(capacity, visual) == Appearance.message_field(capacity, visual) : Design.Style}

def composer_footer(+visual: Design.Style, context: Controls.Context) -> Type:
  Design.Style{text, chrome, alignment, flow, overflow, E.Frame{content, arrangement}, minimum, maximum, states} = visual
  {Appearance.activity_controls(Surface.ComposerActions{}, context,
    Design.Style{text, chrome, alignment, flow, overflow, E.Frame{content, arrangement}, minimum, maximum, states}) ==
    Design.Style{text, chrome, Spatial.Trailing{}, Spatial.SplitRowFlow{}, overflow,
      E.Frame{content, E.EmbeddedContent{A.clearance(A.initial())}}, minimum, maximum, states} : Design.Style}

def supporting_style(value: Design.Style) -> Design.Style:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  Appearance.modeled_container(Design.Style{text, chrome, Spatial.Leading{}, flow, overflow, frame, minimum, maximum, states}, Spatial.RowFlow{}, A.clearance(A.initial()))

type Requirements is Type:
  Requirements{
    positive_motor_target: @grammar:A.Grammar -> {Nat.is_lt(0n, A.supporting_minimum(grammar)) == True{} : Bool},
    positive_writing_lines: @grammar:A.Grammar -> {Nat.is_lt(0n, A.writing_lines(grammar)) == True{} : Bool},
    production_motor_target: {A.supporting_minimum(A.initial()) == 32n : Nat},
    production_writing_lines: {A.writing_lines(A.initial()) == 2n : Nat},
    positive_clearance: @grammar:A.Grammar -> {Nat.is_lt(0n, A.clearance(grammar)) == True{} : Bool},
    complete_frame: @+grammar:A.Grammar -> {A.frame(grammar) == E.Frame{E.ambient(A.clearance(grammar), A.clearance(grammar)), E.EmbeddedContent{A.clearance(grammar)}} : E.Frame},
    production_frame: @+visual:Design.Style -> action_frame(visual),
    production_message: @+capacity:Nat -> @+visual:Design.Style -> message_minimum(capacity, visual),
    production_message_selection: @+capacity:Nat -> @kind:EditorLayout.FieldKind -> @+visual:Design.Style -> message_selection(capacity, kind, visual),
    supporting_flow: @+visual:Design.Style -> @selection:Controls.Selection -> @code:Maybe<&2, Code.Scene> -> @appearance:Services.Appearance -> @access:Services.Access -> @open:Bool -> @layers:+List<View.Layer> -> @execution:Maybe<&2, Workspace.Observation> -> @family:Controls.SourceFamily ->
      {Appearance.activity_controls(Surface.Toolbar{}, Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, execution, family}, visual) == supporting_style(visual) : Design.Style},
    composer_footer: @+visual:Design.Style -> @context:Controls.Context -> composer_footer(visual, context),
    property_minimum: @+property:UX.Property -> @area:Controls.Area -> {Controls.geometry_minimum_height(Controls.geometry_for(Controls.ChooseValue{False{}}, Controls.PropertyFace{property}, area)) == A.supporting_minimum(A.initial()) : Nat}}

law evidence:
  Requirements
