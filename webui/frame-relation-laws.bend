import Base
import ./surfaces.bend as Surfaces
import ./typography.bend as T
import ./enclosure.bend as E
import ./space.bend as Space
import ./design.bend as D
import ./appearance.bend as A
import ./controls.bend as C
import ./renderer.bend as R
import ./document.bend as Doc
import ../BOARD.bend as Board
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View

def actual_geometry(value: C.Representation) -> C.Geometry:
  match value:
    case C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: geometry
    case _: C.Geometry{Space.fixed_demand(0n, 0n), 0n, 0n, 0n}

def mark_extent(layout: C.ChoiceContentLayout) -> Nat:
  C.ChoiceContentLayout{text_gap, extent, icon_extent} = layout
  extent

def mark_icon_extent(layout: C.ChoiceContentLayout) -> Nat:
  C.ChoiceContentLayout{text_gap, extent, icon_extent} = layout
  icon_extent

def style_flow(value: D.Style) -> D.Flow:
  D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  flow

def card_gap_law(-key: String, -face: View.CardFace, -destinations: +List<UI.Placement>, -source: +List<R.Child>, -visual: D.Style, +typography: T.Presentation) -> Type:
  {R.attr(Doc.element_styles(R.card_node(key, face, destinations, source, visual, typography)), "gap") == R.px(E.frame_gap(D.style_frame(visual))) : String}

def card_properties(+styles: +List<Doc.Property>) -> (String & (String & (String & (String & (String & (String & (String & (String & String)))))))):
  (R.attr(styles, "display"), (R.attr(styles, "flex-direction"), (R.attr(styles, "gap"), (R.attr(styles, "min-width"), (R.attr(styles, "border-color"), (R.attr(styles, "border-width"), (R.attr(styles, "border-style"), (R.attr(styles, "border-radius"), R.attr(styles, "box-shadow")))))))))

def card_production_properties_law(-key: String, -face: View.CardFace, -destinations: +List<UI.Placement>, -source: +List<R.Child>, -meaning: UI.Meaning, +typography: T.Presentation) -> Type:
  {card_properties(Doc.element_styles(R.card_node(key, face, destinations, source, A.style(UI.Card{}, meaning, typography), typography))) ==
    ("flex", ("column", (R.px(E.separation(E.CardSections{})), ("0", ("var(--color-token-border-default)", ("1px", ("solid", ("9px", "var(--shadow-sm)")))))))) : (String & (String & (String & (String & (String & (String & (String & (String & String))))))))}

def action_frame_gap_law(-key: String, -visual: D.Style, -input: Core.Input, -availability: View.Availability, -name: String,
  -face: C.Face, -behavior: C.Behavior, -size: C.Geometry, -placement: C.Placement, -help: C.Help, -feedback: C.Feedback) -> Type:
  {R.attr(Doc.element_styles(R.action(key, visual, C.Action{input, availability, name, face, behavior, size, placement, help, feedback})), "gap") == R.px(E.frame_gap(D.style_frame(visual))) : String}

def choice_frame_gap_law(-key: String, -label: String, -selected: Bool, -description: String, -visual: D.Style,
  -input: Core.Input, -availability: View.Availability, -name: String, -face: C.Face, -behavior: C.Behavior,
  -size: C.Geometry, -placement: C.Placement, -help: C.Help, -feedback: C.Feedback, +typography: T.Presentation) -> Type:
  {R.attr(Doc.element_styles(R.action(key, visual, C.Action{input, availability, name, C.ChoiceFace{label, C.choice_description(description), selected}, behavior, size, placement, help, feedback})), "gap") == R.px(E.frame_gap(D.style_frame(visual))) : String}

def choice_style_metrics(+value: D.Style) -> (Nat & D.Flow):
  (E.frame_gap(D.style_frame(value)), style_flow(value))

def actual_choice_normalization_law(-key: String, -selected: Bool, -description: String, -input: Core.Input, -availability: View.Availability, -label: String,
  -role: UI.Role, -context: C.Context, -fallback: D.Style, +typography: T.Presentation) -> Type:
  {choice_style_metrics(A.control_style(fallback, C.make_choice(key, selected, description, input, availability, label, role, context), typography)) == (8n, D.ChoiceFlow{}) : (Nat & D.Flow)}

type Requirements is Type:
  Requirements{
    card_structure: @+typography:T.Presentation -> @+key:String -> @+id:Nat -> @+title:String -> @+description:String -> @+priority:Board.Priority -> @+pinned:Bool -> @+status:String -> @+project:String -> @+labels:+List<String> -> @+owner:String -> @+updated:String -> @+destinations:+List<UI.Placement> -> @+source:+List<R.Child> -> @+visual:D.Style -> {R.card_node(key, View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}, destinations, source, visual, typography) ==
        Doc.Element{key, "article", [R.property("data-native-key", key), R.property("data-card-id", Nat.show(id)), R.property("data-card-title", title), R.property("aria-label", title), R.property("draggable", "true")], R.style(visual), [Doc.DragCard{key}, Doc.DropCard{key}], R.card_children(key, View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}, source, typography)} : Doc.Node},
    card_production_properties: @+typography:T.Presentation -> @+key:String -> @+face:View.CardFace -> @+destinations:+List<UI.Placement> -> @+source:+List<R.Child> -> @+meaning:UI.Meaning -> card_production_properties_law(key, face, destinations, source, meaning, typography),
    action_frame_gap: @+key:String -> @+visual:D.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:C.Face -> @+behavior:C.Behavior -> @+size:C.Geometry -> @+placement:C.Placement -> @+help:C.Help -> @+feedback:C.Feedback ->
      action_frame_gap_law(key, visual, input, availability, name, face, behavior, size, placement, help, feedback),
    choice_frame_gap: @+typography:T.Presentation -> @+key:String -> @+label:String -> @+selected:Bool -> @+description:String -> @+visual:D.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:C.Face -> @+behavior:C.Behavior -> @+size:C.Geometry -> @+placement:C.Placement -> @+help:C.Help -> @+feedback:C.Feedback ->
      choice_frame_gap_law(key, label, selected, description, visual, input, availability, name, face, behavior, size, placement, help, feedback, typography),
    actual_action_flow: @+value:D.Style -> @+face:C.Face -> @+size:C.Geometry ->
      {style_flow(A.action_style(value, face, size)) == A.action_flow(face, C.content_layout(face)) : D.Flow},
    actual_choice_normalization: @+typography:T.Presentation -> @+key:String -> @+selected:Bool -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> @+fallback:D.Style ->
      actual_choice_normalization_law(key, selected, description, input, availability, label, role, context, fallback, typography),
    embedded_gap: @+content:E.ContentArea -> @+gap:Nat -> {E.frame_gap(E.frame(content, E.EmbeddedContent{gap})) == gap : Nat},
    separate_gap: @+content:E.ContentArea -> @+spacing:E.Separation -> {E.frame_gap(E.frame(content, E.SeparateFrames{spacing})) == E.separation(spacing) : Nat},
    joined_gap: @content:E.ContentArea -> {E.frame_gap(E.frame(content, E.JoinedPartitions{})) == 0n : Nat},
    content_preserves_arrangement: @+value:D.Style -> @content:E.ContentArea -> {E.frame_gap(D.style_frame(A.with_content_area(value, content))) == E.frame_gap(D.style_frame(value)) : Nat},
    role_navigation: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {D.style_frame(A.style(UI.Navigation{}, meaning, typography)) == E.Frame{E.area(E.Navigation{}), E.SeparateFrames{E.NavigationRows{}}} : E.Frame},
    role_menu: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {D.style_frame(A.style(UI.Menu{}, meaning, typography)) == E.Frame{E.area(E.Menu{}), E.SeparateFrames{E.MenuItems{}}} : E.Frame},
    role_card: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {D.style_frame(A.style(UI.Card{}, meaning, typography)) == E.Frame{E.area(E.Card{}), E.SeparateFrames{E.CardSections{}}} : E.Frame},
    role_details: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {D.style_frame(A.style(UI.Details{}, meaning, typography)) == E.Frame{E.area(E.Details{}), E.SeparateFrames{E.Sections{}}} : E.Frame},
    role_dialog: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {D.style_frame(A.style(UI.Dialog{}, meaning, typography)) == E.Frame{E.DialogPartitions{}, E.JoinedPartitions{}} : E.Frame},
    actual_choice_geometry: @+key:String -> @+selected:Bool -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {actual_geometry(C.make_choice(key, selected, description, input, availability, label, role, context)) == C.Geometry{Space.fixed_demand(0n, 28n), 16n, 6n, 20n} : C.Geometry},
    actual_choice_layout: @+key:String -> @+selected:Bool -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {C.choice_layout(C.make_choice(key, selected, description, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 20n, 16n} : C.ChoiceContentLayout},
    actual_choice_mark_contains_icon: @+key:String -> @+selected:Bool -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {Nat.is_le(mark_icon_extent(C.choice_layout(C.make_choice(key, selected, description, input, availability, label, role, context))), mark_extent(C.choice_layout(C.make_choice(key, selected, description, input, availability, label, role, context)))) == True{} : Bool},
    selection_keeps_allocation: @+key:String -> @+description:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {C.choice_layout(C.make_choice(key, True{}, description, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, False{}, description, input, availability, label, role, context)) : C.ChoiceContentLayout},
    production_choice_allocation: @+key:String -> @+label:String -> @+selected:Bool -> @+description:Maybe<&2, String> -> @+visual:D.Style -> @input:Core.Input -> @availability:View.Availability -> @name:String -> @behavior:C.Behavior -> @+geometry:C.Geometry -> @placement:C.Placement -> @help:C.Help -> @feedback:C.Feedback ->
      {Doc.element_children(R.action(key, visual, C.Action{input, availability, name, C.ChoiceFace{label, description, selected}, behavior, geometry, placement, help, feedback})) == R.face(key, C.ChoiceFace{label, description, selected}, D.style_text(visual), geometry) : +List<Doc.Node>},
    mark_reserves_space: @+key:String -> @+selected:Bool -> @+extent:Nat -> @+icon:Nat -> {(R.attr(Doc.element_styles(R.choice_mark(key, selected, extent, icon)), "width"), (R.attr(Doc.element_styles(R.choice_mark(key, selected, extent, icon)), "height"), R.attr(Doc.element_styles(R.choice_mark(key, selected, extent, icon)), "flex-shrink"))) == (R.px(extent), (R.px(icon), "0")) : (String & (String & String))},
    project_siblings: @+typography:T.Presentation -> @+key:String -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @+children:+List<R.Child> -> {R.attr(Doc.element_styles(R.project_group_node(key, project, selected, expanded, A.project_group_style(typography), children)), "gap") == R.px(E.separation(E.NavigationRows{})) : String},
    dialog_content_separation: {R.attr(R.dialog_content_styles(), "gap") == R.px(E.separation(E.DialogSections{})) : String},
    dialog_action_separation: {R.attr(R.dialog_footer_styles(), "gap") == R.px(E.separation(E.DialogActions{})) : String},
    choice_row_structure: @+typography:T.Presentation -> @+key:String -> @label:String -> @+description:Maybe<&2, String> -> @selected:Bool -> @+geometry:C.Geometry ->
      {R.face(key, C.ChoiceFace{label, description, selected}, typography, geometry) == R.choice_content_layout(key, label, description, selected, C.choice_content_layout(geometry), typography) : +List<Doc.Node>},
    choice_without_description: @+typography:T.Presentation -> @+key:String -> @label:String -> @selected:Bool -> @text_gap:Nat -> @extent:Nat -> @icon:Nat ->
      {R.choice_content_layout(key, label, None{}, selected, C.ChoiceContentLayout{text_gap, extent, icon}, typography) ==
        [Doc.Element{key ++ "/content", "span", Nil{}, [R.property("display", "flex"), R.property("flex-direction", "column"), R.property("flex", "1 1 0"), R.property("min-width", "0"), R.property("text-align", "start")], Nil{}, [R.caption_label(key, label, C.caption_wrapping(C.ChoiceFace{label, None{}, selected}))]}, R.choice_mark(key, selected, extent, icon)] : +List<Doc.Node>},
    timeline_gap: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {E.frame_gap(D.style_frame(A.style(UI.Timeline{}, meaning, typography))) == E.separation(E.Messages{}) : Nat},
    section_gap: @+typography:T.Presentation -> @+meaning:UI.Meaning -> {E.frame_gap(D.style_frame(A.style(UI.Section{}, meaning, typography))) == E.separation(E.Sections{}) : Nat},
    choice_group_gap: @+typography:T.Presentation -> @+key:String -> @+label:String -> @+visual:D.Style -> @+children:+List<Doc.Node> -> {R.attr(Doc.element_styles(R.choice_group_node(key, label, A.choice_group_style(visual), children, typography)), "gap") == R.px(E.separation(E.MenuItems{})) : String},
    card_gap: @+typography:T.Presentation -> @+key:String -> @+face:View.CardFace -> @+destinations:+List<UI.Placement> -> @+source:+List<R.Child> -> @+visual:D.Style -> card_gap_law(key, face, destinations, source, visual, typography),
    lane_allocation: @+stage:Board.Stage -> {(R.attr(R.board_lane_styles(stage), "padding-inline"), R.attr(R.board_lane_styles(stage), "padding-block")) == (R.px(E.inline(E.area(E.Lane{}))), R.px(E.block(E.area(E.Lane{})))) : (String & String)},
    archive_allocation: @+key:String -> @+label:String -> @+count:Nat -> @+children:+List<Doc.Node> -> {(R.attr(Doc.element_styles(R.card_archive_node(key, label, count, children)), "padding-inline"), R.attr(Doc.element_styles(R.card_archive_node(key, label, count, children)), "padding-block")) == (R.px(E.inline(E.area(E.ArchiveGroup{}))), R.px(E.block(E.area(E.ArchiveGroup{})))) : (String & String)},
    choice_text_allocation: @+typography:T.Presentation -> @+key:String -> @+label:String -> @+description:String -> @+selected:Bool -> @+text_gap:Nat -> @+region_gap:Nat -> @+extent:Nat -> @+icon:Nat -> {R.choice_content_layout(key, label, Some{description}, selected, C.ChoiceContentLayout{text_gap, extent, icon}, typography) ==
          [Doc.Element{key ++ "/content", "span", Nil{}, [R.property("display", "flex"), R.property("flex-direction", "column"), R.property("flex", "1 1 0"), R.property("min-width", "0"), R.property("text-align", "start"), R.property("gap", R.px(text_gap))], Nil{},
            [R.caption_label(key, label, C.caption_wrapping(C.ChoiceFace{label, Some{description}, selected})), Doc.Element{key ++ "/description", "span", Nil{}, List.append(&2, Doc.Property, R.text_presentation(T.supporting(typography)), R.property("color", R.paint(D.TextForeground{Surfaces.SecondaryText{}})) <> R.wrapping_properties(C.description_wrapping())), Nil{}, [Doc.Text{description}]}]},
            R.choice_mark(key, selected, extent, icon)] : +List<Doc.Node>}}

law evidence:
  Requirements
