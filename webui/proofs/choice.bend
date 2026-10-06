import Base
import ../../core/ui-identity.bend as UIIdentity
import ../../bendlib/board-filter.bend as Filter
import ../choice-rules.bend as Rule
import ../controls.bend as C
import ../authored-controls.bend as A
import ../iconography.bend as I
import ../source.bend as S
import ../design.bend as D
import ../../BOARD.bend as Board
import ../../core/interface.bend as UI
import ../../core/SYSTEM.bend as Core
import ../../core/ui-world.bend as View
import ../../core/field-options.bend as Fields

def classification_meaning(+category: Filter.Classification) -> Rule.GlyphMeaning<category, C.classification_glyph(category)>:
  match category:
    case Filter.TaskStage{stage}: Rule.TaskStage{stage, {==}, {==}}
    case Filter.TaskPriority{priority}: Rule.TaskPriority{priority, {==}, {==}}
    case Filter.Project{}: Rule.Project{{==}, {==}}
    case Filter.Person{}: Rule.Person{{==}, {==}}
    case Filter.Agent{}: Rule.Agent{{==}, {==}}
    case Filter.Label{}: Rule.Label{{==}, {==}}
    case Filter.Updated{}: Rule.Updated{{==}, {==}}

def selection_roles(+kind: UI.ChoiceKind, +area: C.Area, +selected: Bool) ->
  {A.behavior(C.choice_behavior(kind, area, selected)) == [S.RoleAttribute{Rule.selection_role(kind, area)}, S.AriaAttribute{"checked", Fields.boolean(selected)}] : +List<S.Attribute>}:
  match kind area:
    case UI.SingleChoice{} C.MenuArea{}: {==}
    case UI.SingleChoice{} C.PageArea{}: {==}
    case UI.SingleChoice{} C.NavigationArea{}: {==}
    case UI.SingleChoice{} C.ComposerArea{}: {==}
    case UI.SingleChoice{} C.ToolbarArea{}: {==}
    case UI.SingleChoice{} C.CodeArea{}: {==}
    case UI.SingleChoice{} C.ActivityArea{}: {==}
    case UI.SingleChoice{} C.ApprovalArea{}: {==}
    case UI.SingleChoice{} C.DialogArea{}: {==}
    case UI.SingleChoice{} C.CollectionArea{}: {==}
    case UI.SingleChoice{} C.CardArea{}: {==}
    case UI.SingleChoice{} C.BoardViewArea{}: {==}
    case UI.SingleChoice{} C.BoardLaneArea{}: {==}
    case UI.MultipleChoice{} C.MenuArea{}: {==}
    case UI.MultipleChoice{} C.PageArea{}: {==}
    case UI.MultipleChoice{} C.NavigationArea{}: {==}
    case UI.MultipleChoice{} C.ComposerArea{}: {==}
    case UI.MultipleChoice{} C.ToolbarArea{}: {==}
    case UI.MultipleChoice{} C.CodeArea{}: {==}
    case UI.MultipleChoice{} C.ActivityArea{}: {==}
    case UI.MultipleChoice{} C.ApprovalArea{}: {==}
    case UI.MultipleChoice{} C.DialogArea{}: {==}
    case UI.MultipleChoice{} C.CollectionArea{}: {==}
    case UI.MultipleChoice{} C.CardArea{}: {==}
    case UI.MultipleChoice{} C.BoardViewArea{}: {==}
    case UI.MultipleChoice{} C.BoardLaneArea{}: {==}

def semantic_face(+key: UIIdentity.Key, +kind: UI.ChoiceKind, +classification: Maybe<&2, Filter.Classification>, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) -> Rule.actual_face_law(key, kind, classification, selected, description, input, availability, label, role, context):
  C.Context{area, selection, code, appearance, access, open, layers, execution, source_family} = context
  {==}

def selected_measured_glyph(+text: String, description: Maybe<&2, String>, icon: Maybe<&2, C.Icon>, +selected: Bool, +key: UIIdentity.Key, +parent: D.Style, +geometry: C.Geometry) ->
  {Rule.selection_drawing(A.face_members(C.ChoiceFace{text, description, icon, selected}, key, parent, geometry)) == Rule.selected_drawing(selected, A.face_icon_size(geometry)) : Maybe<&2, S.Drawing>}:
  match icon selected:
    case None{} True{}: {==}
    case None{} False{}: {==}
    case Some{symbol} True{}: {==}
    case Some{symbol} False{}: {==}

def Rule.evidence():
  Rule.Requirements{
    classification_meaning,
    selection_roles,
    semantic_face,
    +text => description => +icon => selected => +key => +parent => +geometry => {==},
    selected_measured_glyph}
