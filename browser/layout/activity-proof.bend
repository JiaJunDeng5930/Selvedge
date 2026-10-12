import ../controls/PROGRAM.bend as Controls
import ../../interaction/experience/MODEL.bend as UX
import ../appearance/DESIGN.bend as Design
import Base
import ../editor/MODEL.bend as EditorLayout
import ./ACTIVITY.bend as A
import ./enclosure.bend as E
import ./activity-contract.bend as Rule
import ../../bendlib/algebra-proof.bend as Algebra

# Successor cancellation makes the positive increment explicit.
def positive_extension(+base: Nat, +extra: Nat) ->
  {Nat.is_lt(base, Nat.add(Nat.add(base, extra), 1n)) == True{} : Bool}:
  match base:
    case 0n:
      match extra:
        case 0n: {==}
        case 1n+rest: {==}
    case 1n+rest: positive_extension(rest, extra)

def primary_separation(+grammar: A.Grammar) ->
  {Nat.is_lt(A.supporting_minimum(grammar), A.primary_minimum(grammar)) == True{} : Bool}:
  A.Grammar{+extra, clearance} = grammar
  +support = A.supporting_minimum(grammar)
  +equation = Algebra.nat_add_assoc(support, extra, 1n)
  +proof = positive_extension(support, extra)
  %equation : {Nat.is_lt(support, _) == True{} : Bool}
  proof

def positive_clearance(grammar: A.Grammar) ->
  {Nat.is_lt(0n, A.clearance(grammar)) == True{} : Bool}:
  A.Grammar{support, clearance} = grammar
  positive_extension(0n, clearance)

def production_frame(+visual: Design.Style) -> Rule.action_frame(visual):
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  {==}

def production_message(capacity: Nat, +visual: Design.Style) -> Rule.message_minimum(capacity, visual):
  Design.Style{text, +chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Design.Chrome{foreground, background, border_paint, border, radius, shadow} = chrome
  {==}

def production_message_selection(capacity: Nat, kind: EditorLayout.FieldKind, +visual: Design.Style) -> Rule.message_selection(capacity, kind, visual):
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
  Rule.Requirements{primary_separation,
    +grammar => Nat.ge_refl(A.primary_minimum(grammar)),
    positive_clearance, +grammar => {==},
    production_frame, production_message, production_message_selection, +visual => selection => code => appearance => access => open => layers => execution => family => {==}, composer_footer, property_minimum}
