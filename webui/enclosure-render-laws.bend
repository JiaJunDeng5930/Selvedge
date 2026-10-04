import Base
import ./typography.bend as T
import ./enclosure.bend as E
import ./space.bend as Space
import ./enclosure-laws.bend as Model
import ./appearance.bend as A
import ./controls.bend as C
import ./design.bend as D
import ./renderer.bend as R
import ./document.bend as Doc
import ./board-spatial-laws.bend as BoardLaws
import ../core/interface.bend as UI
import ../core/form-fields.bend as Forms
import ../core/user-input.bend as User
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../BOARD.bend as Board

type AttributeMode is Data:
  RawBackground{}
  PointerBackground{}

def background_key(mode: AttributeMode) -> String:
  match mode:
    case RawBackground{}: "background"
    case PointerBackground{}: "--native-rest-background"

def property_key(value: Doc.Property) -> String:
  Doc.Property{key, text} = value
  key

def pointer(value: Doc.Property) -> Doc.Property:
  Doc.Property{key, text} = value
  R.pointer_property(key, text)

def queried_property(mode: AttributeMode, value: Doc.Property) -> Doc.Property:
  match mode:
    case RawBackground{}: value
    case PointerBackground{}: pointer(value)

def Excluded(+mode: AttributeMode, values: +List<Doc.Property>) -> Type:
  match values:
    case Nil{}: Unit
    case Con{property, rest}:
      {String.eq(property_key(queried_property(mode, property)), background_key(mode)) == False{} : Bool} & Excluded(mode, rest)

type Axis is Data:
  Inline{}
  Block{}

def axis_name(axis: Axis) -> String:
  match axis:
    case Inline{}: "padding-inline"
    case Block{}: "padding-block"

def axis_space(axis: Axis, area: E.ContentArea) -> Nat:
  match axis:
    case Inline{}: E.inline(area)
    case Block{}: E.block(area)

def option_production(+key: String, +label: String, +selected: Bool, description: String, +geometry: C.Geometry, input: Core.Input, +typography: T.Presentation) -> Doc.Node:
  +representation: C.Representation = C.Action{input, View.Available{}, label, C.ChoiceFace{label, C.choice_description(description), selected}, C.ChoiceRadio{selected}, geometry, C.InFlow{}, C.NoHelp{}, C.Quiet{}}
  R.action(key, A.control_style(A.ordinary_button(typography), representation, typography), representation)

def title_production(+key: String, editor: User.Editor, +name: String, +text: String, choices: +List<Forms.ChoiceValue>, +typography: T.Presentation) -> Doc.Node:
  +meaning: UI.Meaning = UI.Edit{editor, Forms.CardTitle{}, Forms.SingleLine{}, Forms.TextValue{text}, choices}
  R.input(key, meaning, C.Input{meaning, name, C.TextInput{}, C.AccessibleOnly{}, View.Available{}}, A.style(UI.Field{}, meaning, typography))

def description_production(+key: String, editor: User.Editor, +name: String, +text: String, choices: +List<Forms.ChoiceValue>, +typography: T.Presentation) -> Doc.Node:
  +meaning: UI.Meaning = UI.Edit{editor, Forms.CardDescription{}, Forms.Multiline{}, Forms.TextValue{text}, choices}
  R.input(key, meaning, C.Input{meaning, name, C.TextArea{}, C.AccessibleOnly{}, View.Available{}}, A.style(UI.Field{}, meaning, typography))

type ParentProperty is Data:
  FrameGap{}
  MinimumHeight{}
  BorderRadius{}

def parent_name(value: ParentProperty) -> String:
  match value:
    case FrameGap{}: "gap"
    case MinimumHeight{}: "min-height"
    case BorderRadius{}: "border-radius"

def parent_value(value: D.Style, property: ParentProperty) -> String:
  D.Style{text, D.Chrome{fg, bg, border, width, radius, shadow}, alignment, flow, overflow, +frame, minimum, maximum, states} = value
  match property:
    case FrameGap{}: R.px(E.frame_gap(frame))
    case MinimumHeight{}: R.px(minimum)
    case BorderRadius{}: R.px(radius)

def parent_action_law(-property: ParentProperty, -key: String, -visual: D.Style, -input: Core.Input, -availability: View.Availability, -name: String,
  -face: C.Face, -behavior: C.Behavior, -size: C.Geometry, -placement: C.Placement, -help: C.Help, -feedback: C.Feedback) -> Type:
  {R.attr(Doc.element_styles(R.action(key, visual, C.Action{input, availability, name, face, behavior, size, placement, help, feedback})), parent_name(property)) == parent_value(visual, property) : String}

def geometry_complete_law(-width: Nat, -height: Nat, -preferred_width: Nat, -preferred_height: Nat, -icon: Nat, -radius: Nat, -leading: Nat, -visual: D.Style) -> Type:
  {R.action_geometry(C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}, visual) == [R.property("min-width", R.px(width)), R.property("--native-icon-size", R.px(icon)), R.property("--native-leading-slot", R.px(leading))] : +List<Doc.Property>}

def action_minimum_law(-key: String, -visual: D.Style, -input: Core.Input, -availability: View.Availability, -name: String,
  -face: C.Face, -behavior: C.Behavior, -width: Nat, -height: Nat, -preferred_width: Nat, -preferred_height: Nat, -icon: Nat, -radius: Nat, -leading: Nat, -placement: C.Placement, -help: C.Help, -feedback: C.Feedback) -> Type:
  {R.attr(Doc.element_styles(R.action(key, visual, C.Action{input, availability, name, face, behavior, C.Geometry{Space.Demand{E.Extent{width, height}, E.Extent{preferred_width, preferred_height}}, icon, radius, leading}, placement, help, feedback})), "min-width") == R.px(width) : String}

type Requirements is Type:
  Requirements{
    parent_properties: @+property:ParentProperty -> @+key:String -> @+visual:D.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:C.Face -> @+behavior:C.Behavior -> @+size:C.Geometry -> @+placement:C.Placement -> @+help:C.Help -> @+feedback:C.Feedback ->
      parent_action_law(property, key, visual, input, availability, name, face, behavior, size, placement, help, feedback),
    area_properties: @+area:E.ContentArea -> {R.content_area_properties(area) == [R.property("padding-inline", R.px(E.inline(area))), R.property("padding-block", R.px(E.block(area))), R.property("box-sizing", "border-box")] : +List<Doc.Property>},
    style_allocation: @+value:D.Style -> @+axis:Axis -> {R.attr(R.style(value), axis_name(axis)) == R.px(axis_space(axis, Model.area(value))) : String},
    duplicate: @+name:String -> @+old:String -> @+new:String -> {R.attr([R.property(name, old), R.property(name, new)], name) == new : String},
    geometry_height: @+size:C.Geometry -> @+visual:D.Style -> {R.attr(List.append(&2, Doc.Property, R.style(visual), R.action_geometry(size, visual)), "min-height") == R.px(D.style_minimum_height(visual)) : String},
    navigation_header: @+typography:T.Presentation -> @+selected:Bool -> {(R.attr(R.style(A.navigation_family_style(selected, 2n, 6n, typography)), "padding-inline"), R.attr(R.style(A.navigation_family_style(selected, 2n, 6n, typography)), "padding-block")) == ("8px", "4px") : (String & String)},
    navigation_task: @+typography:T.Presentation -> @+selected:Bool -> @+key:String -> @+task:Nat -> @+status:String -> @+children:+List<R.Child> -> {(R.attr(Doc.element_styles(R.task_row_node(key, task, status, selected, A.navigation_family_style(selected, 6n, 5n, typography), children, typography)), "padding-inline"), R.attr(Doc.element_styles(R.task_row_node(key, task, status, selected, A.navigation_family_style(selected, 6n, 5n, typography), children, typography)), "padding-block")) == ("8px", "4px") : (String & String)},
    embedded_name: @+typography:T.Presentation -> {(R.attr(R.style(A.project_label_style(A.ordinary_button(typography))), "padding-inline"), R.attr(R.style(A.project_label_style(A.ordinary_button(typography))), "padding-block")) == ("0px", "0px") : (String & String)},
    icon_control: @+typography:T.Presentation -> @+width:String -> {(R.attr(R.style(A.action_style(A.ordinary_button(typography), C.IconFace{C.Plus{}}, C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 0n})), "padding-inline"), R.attr(R.style(A.action_style(A.ordinary_button(typography), C.IconFace{C.Plus{}}, C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 0n})), "padding-block")) == ("4px", "4px") : (String & String)},
    card_title: @+typography:T.Presentation -> {(R.attr(BoardLaws.title_production_styles(typography), "padding-inline"), R.attr(BoardLaws.title_production_styles(typography), "padding-block")) == ("8px", "4px") : (String & String)},
    search: @+typography:T.Presentation -> @+filter:Board.Filter -> {(R.attr(R.style(A.field_style(UI.BoardSearch{filter}, typography)), "padding-inline"), R.attr(R.style(A.field_style(UI.BoardSearch{filter}, typography)), "padding-block")) == ("8px", "4px") : (String & String)},
    dialog_header: {(R.attr(R.dialog_header_styles(), "padding-inline"), R.attr(R.dialog_header_styles(), "padding-block")) == ("24px", "14px") : (String & String)},
    dialog_body: {(R.attr(R.dialog_body_styles(), "padding-inline"), R.attr(R.dialog_body_styles(), "padding-block")) == ("24px", "20px") : (String & String)},
    dialog_footer: {(R.attr(R.dialog_footer_styles(), "padding-inline"), R.attr(R.dialog_footer_styles(), "padding-block")) == ("24px", "12px") : (String & String)},
    empty_overwrite: @+name:String -> @+old:String -> {R.attr([R.property(name, old), R.property(name, "")], name) == "" : String},
    option_production_insets: @+typography:T.Presentation -> @+key:String -> @+label:String -> @+selected:Bool -> @+description:String -> @+geometry:C.Geometry -> @+input:Core.Input -> {(R.attr(Doc.element_styles(option_production(key, label, selected, description, geometry, input, typography)), "padding-inline"), R.attr(Doc.element_styles(option_production(key, label, selected, description, geometry, input, typography)), "padding-block")) == ("8px", "8px") : (String & String)},
    title_production_insets: @+typography:T.Presentation -> @+key:String -> @+editor:User.Editor -> @+name:String -> @+text:String -> @choices:+List<Forms.ChoiceValue> -> {(R.attr(Doc.element_styles(title_production(key, editor, name, text, choices, typography)), "padding-inline"), R.attr(Doc.element_styles(title_production(key, editor, name, text, choices, typography)), "padding-block")) == ("8px", "6px") : (String & String)},
    description_production_insets: @+typography:T.Presentation -> @+key:String -> @+editor:User.Editor -> @+name:String -> @+text:String -> @choices:+List<Forms.ChoiceValue> -> {(R.attr(Doc.element_styles(description_production(key, editor, name, text, choices, typography)), "padding-inline"), R.attr(Doc.element_styles(description_production(key, editor, name, text, choices, typography)), "padding-block")) == ("8px", "6px") : (String & String)},
    dialog_outer: @+typography:T.Presentation -> {(R.attr(R.style(A.style(UI.Dialog{}, UI.Region{}, typography)), "padding-inline"), R.attr(R.style(A.style(UI.Dialog{}, UI.Region{}, typography)), "padding-block")) == ("0px", "0px") : (String & String)},
    action_minimum: @+key:String -> @+visual:D.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:C.Face -> @+behavior:C.Behavior -> @+width:Nat -> @+height:Nat -> @+preferred_width:Nat -> @+preferred_height:Nat -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> @+placement:C.Placement -> @+help:C.Help -> @+feedback:C.Feedback -> action_minimum_law(key, visual, input, availability, name, face, behavior, width, height, preferred_width, preferred_height, icon, radius, leading, placement, help, feedback),
    geometry_complete: @+width:Nat -> @+height:Nat -> @+preferred_width:Nat -> @+preferred_height:Nat -> @+icon:Nat -> @+radius:Nat -> @+leading:Nat -> @+visual:D.Style -> geometry_complete_law(width, height, preferred_width, preferred_height, icon, radius, leading, visual)}

law evidence:
  Requirements
