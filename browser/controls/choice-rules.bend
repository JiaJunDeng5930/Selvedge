import Base
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../features/board/filter.bend as Filter
import ./PROGRAM.bend as C
import ./CONTROLS.bend as A
import ../appearance/ICONS.bend as I
import ../document/SOURCE.bend as S
import ../appearance/DESIGN.bend as D
import ../../features/board/MODEL.bend as Board
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/STATE.bend as Core
import ../../interaction/presentation/MODEL.bend as View
import ../../interaction/submission/field-options.bend as Fields

def selection_role(kind: InterfaceView.ChoiceKind, area: C.Area) -> String:
  match kind area:
    case InterfaceView.SingleChoice{} C.MenuArea{}: "menuitemradio"
    case InterfaceView.SingleChoice{} _: "radio"
    case InterfaceView.MultipleChoice{} C.MenuArea{}: "menuitemcheckbox"
    case InterfaceView.MultipleChoice{} _: "checkbox"

def actual_face(value: C.Representation) -> Maybe<&2, C.Face>:
  match value:
    case C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: Some{face}
    case _: None{}

def first_drawing(values: +List<S.Node>) -> Maybe<&2, S.Drawing>:
  match values:
    case Con{S.Glyph{key, drawing, style}, rest}: Some{drawing}
    case _: None{}

def selection_drawing(values: +List<S.Node>) -> Maybe<&2, S.Drawing>:
  match values:
    case Con{S.Box{key, tag, style, attributes, children}, Nil{}}: first_drawing(children)
    case Con{node, rest}: selection_drawing(rest)
    case Nil{}: None{}

def selected_drawing(selected: Bool, size: Nat) -> Maybe<&2, S.Drawing>:
  match selected:
    case True{}: Some{I.drawing(C.Check{}, size)}
    case False{}: None{}

def actual_face_law(-key: UIIdentity.Key, -kind: InterfaceView.ChoiceKind, -classification: Maybe<&2, Filter.Classification>, -selected: Bool, -description: String, -input: Core.Input, -availability: View.Availability, -label: String, -role: InterfaceView.Role, +context: C.Context) -> Type:
  C.Context{area, selection, code, appearance, access, open, layers, execution, source_family} = context
  {actual_face(C.make_choice(key, kind, classification, selected, description, input, availability, label, role, context)) ==
    Some{C.ChoiceFace{C.name_for(C.purpose_fields(key, input, selection, code, appearance, access, open, layers), label), C.choice_description(description), C.classification_icon(classification), selected}} : Maybe<&2, C.Face>}

type GlyphMeaning<-category: Filter.Classification, -icon: C.Icon> is Type:
  TaskStage{-stage: Board.Stage, source: {category == Filter.TaskStage{stage} : Filter.Classification}, glyph: {icon == C.Status{stage} : C.Icon}}
  TaskPriority{-priority: Board.Priority, source: {category == Filter.TaskPriority{priority} : Filter.Classification}, glyph: {icon == C.Priority{priority} : C.Icon}}
  Project{source: {category == Filter.Project{} : Filter.Classification}, glyph: {icon == C.Folder{} : C.Icon}}
  Person{source: {category == Filter.Person{} : Filter.Classification}, glyph: {icon == C.User{} : C.Icon}}
  Agent{source: {category == Filter.Agent{} : Filter.Classification}, glyph: {icon == C.Bot{} : C.Icon}}
  Label{source: {category == Filter.Label{} : Filter.Classification}, glyph: {icon == C.Tag{} : C.Icon}}
  Updated{source: {category == Filter.Updated{} : Filter.Classification}, glyph: {icon == C.Clock{} : C.Icon}}

type Requirements is Type:
  Requirements{
    classification_meaning: @+category:Filter.Classification -> GlyphMeaning<category, C.classification_glyph(category)>,
    selection_roles: @+kind:InterfaceView.ChoiceKind -> @+area:C.Area -> @+selected:Bool ->
      {A.behavior(C.choice_behavior(kind, area, selected)) == [S.RoleAttribute{selection_role(kind, area)}, S.AriaAttribute{"checked", Fields.boolean(selected)}] : +List<S.Attribute>},
    semantic_face: @+key:UIIdentity.Key -> @+kind:InterfaceView.ChoiceKind -> @+classification:Maybe<&2, Filter.Classification> -> @+selected:Bool -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:InterfaceView.Role -> @+context:C.Context -> actual_face_law(key, kind, classification, selected, description, input, availability, label, role, context),
    leading_measured_glyph: @+text:String -> @description:Maybe<&2, String> -> @+icon:C.Icon -> @selected:Bool -> @+key:UIIdentity.Key -> @+parent:D.Style -> @+geometry:C.Geometry ->
      {first_drawing(A.face_members(C.ChoiceFace{text, description, Some{icon}, selected}, key, parent, geometry)) == Some{I.drawing(icon, A.face_icon_size(geometry))} : Maybe<&2, S.Drawing>},
    selected_measured_glyph: @+text:String -> @description:Maybe<&2, String> -> @icon:Maybe<&2, C.Icon> -> @+selected:Bool -> @+key:UIIdentity.Key -> @+parent:D.Style -> @+geometry:C.Geometry ->
      {selection_drawing(A.face_members(C.ChoiceFace{text, description, icon, selected}, key, parent, geometry)) == selected_drawing(selected, A.face_icon_size(geometry)) : Maybe<&2, S.Drawing>}}

law evidence:
  Requirements
