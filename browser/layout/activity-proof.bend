import ../controls/PROGRAM.bend as Controls
import ../../interaction/presentation/SURFACE.bend as Surface
import ../../interaction/conversation/CODE.bend as Code
import ../../interaction/services/MODEL.bend as Services
import ../../interaction/services/CONTEXT.bend as Workspace
import ../../interaction/presentation/MODEL.bend as View
import ../appearance/MODEL.bend as Appearance
import ../../interaction/experience/MODEL.bend as UX
import ../appearance/DESIGN.bend as Design
import Base
import ../editor/MODEL.bend as EditorLayout
import ./ACTIVITY.bend as A
import ./enclosure.bend as E
import ./activity-contract.bend as Rule

# Successor cancellation makes the positive increment explicit.
def positive_extension(+base: Nat, +extra: Nat) ->
  {Nat.is_lt(base, Nat.add(Nat.add(base, extra), 1n)) == True{} : Bool}:
  match base:
    case 0n:
      match extra:
        case 0n: {==}
        case 1n+rest: {==}
    case 1n+rest: positive_extension(rest, extra)

def positive_motor_target(grammar: A.Grammar) ->
  {Nat.is_lt(0n, A.supporting_minimum(grammar)) == True{} : Bool}:
  A.Grammar{support, writing, clearance} = grammar
  positive_extension(0n, support)

def positive_writing_lines(grammar: A.Grammar) ->
  {Nat.is_lt(0n, A.writing_lines(grammar)) == True{} : Bool}:
  A.Grammar{support, writing, clearance} = grammar
  positive_extension(0n, writing)

def positive_clearance(grammar: A.Grammar) ->
  {Nat.is_lt(0n, A.clearance(grammar)) == True{} : Bool}:
  A.Grammar{support, writing, clearance} = grammar
  positive_extension(0n, clearance)

def production_frame(+visual: Design.Style) -> Rule.action_frame(visual):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  {==}

def production_message(+capacity: Nat, +visual: Design.Style) -> Rule.message_minimum(capacity, visual):
  Design.Style{text, +chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border_paint, border, radius, shadow} = chrome
  {==}

def production_message_selection(+capacity: Nat, kind: EditorLayout.FieldKind, +visual: Design.Style) -> Rule.message_selection(capacity, kind, visual):
  {==}

def supporting_flow(+visual: Design.Style, selection: Controls.Selection, code: Maybe<&2, Code.Scene>, appearance: Services.Appearance, access: Services.Access, open: Bool, layers: +List<View.Layer>, execution: Maybe<&2, Workspace.Observation>, family: Controls.SourceFamily) ->
  {Appearance.activity_controls(Surface.Toolbar{}, Controls.Context{Controls.ComposerArea{}, selection, code, appearance, access, open, layers, execution, family}, visual) == Rule.supporting_style(visual) : Design.Style}:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  {==}

def composer_footer(+visual: Design.Style, context: Controls.Context) -> Rule.composer_footer(visual, context):
  Design.Style{text, chrome, alignment, flow, overflow, E.Frame{content, arrangement}, minimum, maximum, states} = visual
  {==}

def property_minimum(+property: UX.Property, area: Controls.Area) ->
  {Controls.geometry_minimum_height(Controls.geometry_for(Controls.ChooseValue{False{}}, Controls.PropertyFace{property}, area)) == A.supporting_minimum(A.initial()) : Nat}:
  match area:
    case Controls.PageArea{}: {==}
    case Controls.NavigationArea{}: {==}
    case Controls.ComposerArea{}: {==}
    case Controls.ToolbarArea{}: {==}
    case Controls.CodeArea{}: {==}
    case Controls.ActivityArea{}: {==}
    case Controls.ApprovalArea{}: {==}
    case Controls.MenuArea{}: {==}
    case Controls.ChoiceGroupArea{}: {==}
    case Controls.DialogArea{}: {==}
    case Controls.CollectionArea{}: {==}
    case Controls.CardArea{}: {==}
    case Controls.BoardViewArea{}: {==}
    case Controls.BoardLaneArea{}: {==}

def Rule.evidence():
  Rule.Requirements{positive_motor_target, positive_writing_lines,
    {==}, {==},
    positive_clearance, +grammar => {==},
    production_frame, production_message, production_message_selection, supporting_flow, composer_footer, property_minimum}
