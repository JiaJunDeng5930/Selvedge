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
import ../../core/interface.bend as InterfaceView
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

def selection_roles(+kind: InterfaceView.ChoiceKind, +area: C.Area, +selected: Bool) ->
  {A.behavior(C.choice_behavior(kind, area, selected)) == [S.RoleAttribute{Rule.selection_role(kind, area)}, S.AriaAttribute{"checked", Fields.boolean(selected)}] : +List<S.Attribute>}:
  match kind area:
    case InterfaceView.SingleChoice{} C.MenuArea{}: {==}
    case InterfaceView.SingleChoice{} C.PageArea{}: {==}
    case InterfaceView.SingleChoice{} C.NavigationArea{}: {==}
    case InterfaceView.SingleChoice{} C.ComposerArea{}: {==}
    case InterfaceView.SingleChoice{} C.ToolbarArea{}: {==}
    case InterfaceView.SingleChoice{} C.CodeArea{}: {==}
    case InterfaceView.SingleChoice{} C.ActivityArea{}: {==}
    case InterfaceView.SingleChoice{} C.ApprovalArea{}: {==}
    case InterfaceView.SingleChoice{} C.DialogArea{}: {==}
    case InterfaceView.SingleChoice{} C.CollectionArea{}: {==}
    case InterfaceView.SingleChoice{} C.CardArea{}: {==}
    case InterfaceView.SingleChoice{} C.BoardViewArea{}: {==}
    case InterfaceView.SingleChoice{} C.BoardLaneArea{}: {==}
    case InterfaceView.MultipleChoice{} C.MenuArea{}: {==}
    case InterfaceView.MultipleChoice{} C.PageArea{}: {==}
    case InterfaceView.MultipleChoice{} C.NavigationArea{}: {==}
    case InterfaceView.MultipleChoice{} C.ComposerArea{}: {==}
    case InterfaceView.MultipleChoice{} C.ToolbarArea{}: {==}
    case InterfaceView.MultipleChoice{} C.CodeArea{}: {==}
    case InterfaceView.MultipleChoice{} C.ActivityArea{}: {==}
    case InterfaceView.MultipleChoice{} C.ApprovalArea{}: {==}
    case InterfaceView.MultipleChoice{} C.DialogArea{}: {==}
    case InterfaceView.MultipleChoice{} C.CollectionArea{}: {==}
    case InterfaceView.MultipleChoice{} C.CardArea{}: {==}
    case InterfaceView.MultipleChoice{} C.BoardViewArea{}: {==}
    case InterfaceView.MultipleChoice{} C.BoardLaneArea{}: {==}

def semantic_face(+key: UIIdentity.Key, +kind: InterfaceView.ChoiceKind, +classification: Maybe<&2, Filter.Classification>, +selected: Bool, +description: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: InterfaceView.Role, +context: C.Context) -> Rule.actual_face_law(key, kind, classification, selected, description, input, availability, label, role, context):
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
