import Base
import ./controls.bend as C
import ./authored-controls.bend as A
import ./iconography.bend as I
import ./source.bend as S
import ./design.bend as D
import ../BOARD.bend as Board
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../core/field-options.bend as Fields

def selection_role(kind: UI.ChoiceKind, area: C.Area) -> String:
  match kind area:
    case UI.SingleChoice{} C.MenuArea{}: "menuitemradio"
    case UI.SingleChoice{} _: "radio"
    case UI.MultipleChoice{} C.MenuArea{}: "menuitemcheckbox"
    case UI.MultipleChoice{} _: "checkbox"

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

def actual_face_law(-key: String, -kind: UI.ChoiceKind, -icon: Maybe<&2, String>, -selected: Bool, -description: String, -input: Core.Input, -availability: View.Availability, -label: String, -role: UI.Role, +context: C.Context) -> Type:
  C.Context{area, selection, code, appearance, access, open, layers, execution, source_family} = context
  {actual_face(C.make_choice(key, kind, icon, selected, description, input, availability, label, role, context)) ==
    Some{C.ChoiceFace{C.name_for(C.purpose_fields(key, input, selection, code, appearance, access, open, layers), label), C.choice_description(description), C.classification_icon(icon), selected}} : Maybe<&2, C.Face>}

type Requirements is Type:
  Requirements{
    stage_classification: @+stage:Board.Stage -> {C.classification_icon(Some{"status/" ++ Board.stage_name(stage)}) == Some{C.Status{stage}} : Maybe<&2, C.Icon>},
    priority_classification: @+priority:Board.Priority -> {C.classification_icon(Some{"priority/" ++ Board.priority_name(priority)}) == Some{C.Priority{priority}} : Maybe<&2, C.Icon>},
    folder_classification: {C.classification_icon(Some{"folder"}) == Some{C.Folder{}} : Maybe<&2, C.Icon>},
    user_classification: {C.classification_icon(Some{"user"}) == Some{C.User{}} : Maybe<&2, C.Icon>},
    bot_classification: {C.classification_icon(Some{"bot"}) == Some{C.Bot{}} : Maybe<&2, C.Icon>},
    tag_classification: {C.classification_icon(Some{"tag"}) == Some{C.Tag{}} : Maybe<&2, C.Icon>},
    selection_roles: @+kind:UI.ChoiceKind -> @+area:C.Area -> @+selected:Bool ->
      {A.behavior(C.choice_behavior(kind, area, selected)) == [S.RoleAttribute{selection_role(kind, area)}, S.AriaAttribute{"checked", Fields.boolean(selected)}] : +List<S.Attribute>},
    semantic_face: @+key:String -> @+kind:UI.ChoiceKind -> @+icon:Maybe<&2, String> -> @+selected:Bool -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> actual_face_law(key, kind, icon, selected, description, input, availability, label, role, context),
    leading_measured_glyph: @+text:String -> @description:Maybe<&2, String> -> @+icon:C.Icon -> @selected:Bool -> @+key:String -> @+parent:D.Style -> @+geometry:C.Geometry ->
      {first_drawing(A.face_members(C.ChoiceFace{text, description, Some{icon}, selected}, key, parent, geometry)) == Some{I.drawing(icon, A.face_icon_size(geometry))} : Maybe<&2, S.Drawing>},
    selected_measured_glyph: @+text:String -> @description:Maybe<&2, String> -> @icon:Maybe<&2, C.Icon> -> @+selected:Bool -> @+key:String -> @+parent:D.Style -> @+geometry:C.Geometry ->
      {selection_drawing(A.face_members(C.ChoiceFace{text, description, icon, selected}, key, parent, geometry)) == selected_drawing(selected, A.face_icon_size(geometry)) : Maybe<&2, S.Drawing>}}

law evidence:
  Requirements
