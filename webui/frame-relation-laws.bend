import Base
import ./enclosure.bend as E
import ./design.bend as D
import ./appearance.bend as A
import ./controls.bend as C
import ./renderer.bend as R
import ./renderer-laws.bend as Renderer
import ./document.bend as Doc
import ./enclosure-render-laws.bend as EnclosureRender
import ../BOARD.bend as Board
import ../core/interface.bend as UI
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View

def style_frame(value: D.Style) -> E.Frame:
  D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  frame

def actual_geometry(value: C.Representation) -> C.Geometry:
  match value:
    case C.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}: geometry
    case _: C.Geometry{0n, 0n, 0n, 0n, 0n}

def mark_extent(layout: C.ChoiceContentLayout) -> Nat:
  C.ChoiceContentLayout{text_gap, region_gap, extent, icon_extent} = layout
  extent

def mark_icon_extent(layout: C.ChoiceContentLayout) -> Nat:
  C.ChoiceContentLayout{text_gap, region_gap, extent, icon_extent} = layout
  icon_extent

def embedded_gap(+content: E.ContentArea, +gap: Nat) ->
  {E.frame_gap(E.frame(content, E.EmbeddedContent{gap})) == gap : Nat}:
  {==}

def separate_gap(+content: E.ContentArea, +spacing: E.Separation) ->
  {E.frame_gap(E.frame(content, E.SeparateFrames{spacing})) == E.separation(spacing) : Nat}:
  {==}

def joined_gap(content: E.ContentArea) ->
  {E.frame_gap(E.frame(content, E.JoinedPartitions{})) == 0n : Nat}:
  {==}

def content_preserves_arrangement(+value: D.Style, content: E.ContentArea) ->
  {E.frame_gap(style_frame(A.with_content_area(value, content))) == E.frame_gap(style_frame(value)) : Nat}:
  D.Style{text, chrome, alignment, flow, overflow, E.Frame{old_content, arrangement}, minimum, maximum, states} = value
  {==}

def role_navigation(+meaning: UI.Meaning) ->
  {style_frame(A.style(UI.Navigation{}, meaning)) == E.Frame{E.area(E.Navigation{}), E.SeparateFrames{E.NavigationRows{}}} : E.Frame}:
  {==}

def role_menu(+meaning: UI.Meaning) ->
  {style_frame(A.style(UI.Menu{}, meaning)) == E.Frame{E.area(E.Menu{}), E.SeparateFrames{E.MenuItems{}}} : E.Frame}:
  {==}

def role_card(+meaning: UI.Meaning) ->
  {style_frame(A.style(UI.Card{}, meaning)) == E.Frame{E.area(E.Card{}), E.SeparateFrames{E.CardSections{}}} : E.Frame}:
  {==}

def role_details(+meaning: UI.Meaning) ->
  {style_frame(A.style(UI.Details{}, meaning)) == E.Frame{E.area(E.Details{}), E.SeparateFrames{E.Sections{}}} : E.Frame}:
  {==}

def role_dialog(+meaning: UI.Meaning) ->
  {style_frame(A.style(UI.Dialog{}, meaning)) == E.Frame{E.DialogPartitions{}, E.JoinedPartitions{}} : E.Frame}:
  {==}

def actual_choice_geometry(+key: String, +selected: Bool, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {actual_geometry(C.make_choice(key, selected, input, availability, label, role, context)) == C.Geometry{0n, 28n, 16n, 6n, 20n} : C.Geometry}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution} = context
  {==}

def actual_choice_layout(+key: String, +selected: Bool, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 8n, 20n, 16n} : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution} = context
  {==}

def actual_choice_mark_contains_icon(+key: String, +selected: Bool, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {Nat.is_le(mark_icon_extent(C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context))), mark_extent(C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context)))) == True{} : Bool}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution} = context
  {==}

def selection_keeps_allocation(+key: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, True{}, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, False{}, input, availability, label, role, context)) : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution} = context
  {==}

def production_choice_allocation(+key: String, +label: String, +selected: Bool, +description: String, +visual: D.Style, +representation: C.Representation, +children: +List<D.Appearance>) ->
  {R.choice_node(key, label, selected, description, visual, representation, children) == R.choice_face_layout(R.action(key, D.Appearance{key, visual, representation, children}, representation), label, description, selected, C.choice_layout(representation)) : Doc.Node}:
  {==}

def mark_reserves_space(+key: String, +selected: Bool, +extent: Nat, +icon: Nat) ->
  {(R.attr(Renderer.node_styles(R.choice_mark(key, selected, extent, icon)), "width"), (R.attr(Renderer.node_styles(R.choice_mark(key, selected, extent, icon)), "height"), R.attr(Renderer.node_styles(R.choice_mark(key, selected, extent, icon)), "flex-shrink"))) == (R.px(extent), (R.px(icon), "0")) : (String & (String & String))}:
  {==}

def project_siblings(+key: String, +project: Nat, +selected: Bool, +expanded: Bool, +children: +List<Doc.Node>, +appearances: +List<D.Appearance>) ->
  {R.attr(Renderer.node_styles(R.project_group_node(key, project, selected, expanded, children, appearances)), "gap") == R.px(E.separation(E.NavigationRows{})) : String}:
  {==}

def dialog_content_separation() ->
  {R.attr(R.dialog_content_styles(), "gap") == R.px(E.separation(E.DialogSections{})) : String}:
  {==}

def dialog_action_separation() ->
  {R.attr(R.dialog_footer_styles(), "gap") == R.px(E.separation(E.DialogActions{})) : String}:
  {==}

def choice_row_structure(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>, children: +List<Doc.Node>, +label: String, +description: String, +selected: Bool, +text_gap: Nat, +region_gap: Nat, +extent: Nat, +icon: Nat) ->
  {R.choice_face_layout(Doc.Element{key, tag, attrs, styles, events, children}, label, description, selected, C.ChoiceContentLayout{text_gap, region_gap, extent, icon}) ==
    Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles,
      [R.property("display", "flex"), R.property("flex-direction", "row"), R.property("align-items", "center"), R.property("gap", R.px(region_gap)), R.property("width", "100%"), R.property("min-width", "0"), R.property("height", "auto"), R.property("flex-shrink", "0"), R.property("justify-content", "space-between")]), events,
      R.choice_content_layout(key, label, description, selected, C.ChoiceContentLayout{text_gap, region_gap, extent, icon})} : Doc.Node}:
  {==}

def timeline_gap(+meaning: UI.Meaning) ->
  {E.frame_gap(style_frame(A.style(UI.Timeline{}, meaning))) == E.separation(E.Messages{}) : Nat}:
  {==}

def section_gap(+meaning: UI.Meaning) ->
  {E.frame_gap(style_frame(A.style(UI.Section{}, meaning))) == E.separation(E.Sections{}) : Nat}:
  {==}

def choice_group_gap(+key: String, +label: String, +visual: D.Style, +children: +List<Doc.Node>) ->
  {R.attr(Renderer.node_styles(R.choice_group_node(key, label, visual, children)), "gap") == R.px(E.separation(E.MenuItems{})) : String}:
  EnclosureRender.last_append(R.style(visual), [R.property("display", "flex"), R.property("flex-direction", "column"), R.property("gap", R.px(E.separation(E.MenuItems{}))), R.property("min-width", "0"), R.property("flex-shrink", "0"), R.property("height", "auto")], "gap", "")

def card_gap(+key: String, +face: View.CardFace, +destinations: +List<UI.Placement>, +source: +List<UI.Node>, +rendered: +List<Doc.Node>, +visual: D.Style) ->
  {R.attr(Renderer.node_styles(R.card_node(key, face, destinations, source, rendered, visual)), "gap") == R.px(E.separation(E.CardSections{})) : String}:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  EnclosureRender.last_append(R.style(visual), [R.property("display", "flex"), R.property("flex-direction", "column"), R.property("gap", R.px(E.separation(E.CardSections{}))), R.property("min-width", "0"), R.property("border", "1px solid var(--color-token-border-default)"), R.property("border-radius", "9px"), R.property("box-shadow", "var(--shadow-sm)")], "gap", "")

def lane_allocation(+stage: Board.Stage) ->
  {(R.attr(R.board_lane_styles(stage), "padding-inline"), R.attr(R.board_lane_styles(stage), "padding-block")) == (R.px(E.inline(E.area(E.Lane{}))), R.px(E.block(E.area(E.Lane{})))) : (String & String)}:
  {==}

def archive_allocation(+key: String, +label: String, +count: Nat, +children: +List<Doc.Node>) ->
  {(R.attr(Renderer.node_styles(R.card_archive_node(key, label, count, children)), "padding-inline"), R.attr(Renderer.node_styles(R.card_archive_node(key, label, count, children)), "padding-block")) == (R.px(E.inline(E.area(E.ArchiveGroup{}))), R.px(E.block(E.area(E.ArchiveGroup{})))) : (String & String)}:
  {==}

def choice_text_allocation(+key: String, +label: String, +description: String, +selected: Bool, +text_gap: Nat, +region_gap: Nat, +extent: Nat, +icon: Nat) ->
  {R.choice_content_layout(key, label, description, selected, C.ChoiceContentLayout{text_gap, region_gap, extent, icon}) ==
    [Doc.Element{key ++ "/content", "span", Nil{}, [R.property("display", "flex"), R.property("flex-direction", "column"), R.property("flex", "1 1 0"), R.property("min-width", "0"), R.property("text-align", "start"), R.property("gap", R.px(text_gap))], Nil{},
      [Doc.Text{label}, Doc.Element{key ++ "/description", "span", Nil{}, [R.property("font-size", "12px"), R.property("color", "var(--color-token-text-secondary)"), R.property("white-space", "normal")], Nil{}, [Doc.Text{description}]}]},
      R.choice_mark(key, selected, extent, icon)] : +List<Doc.Node>}:
  {==}

type Requirements is Type:
  Requirements{embedded_gap: @+content:E.ContentArea -> @+gap:Nat -> {E.frame_gap(E.frame(content, E.EmbeddedContent{gap})) == gap : Nat},
    separate_gap: @+content:E.ContentArea -> @+spacing:E.Separation -> {E.frame_gap(E.frame(content, E.SeparateFrames{spacing})) == E.separation(spacing) : Nat},
    joined_gap: @content:E.ContentArea -> {E.frame_gap(E.frame(content, E.JoinedPartitions{})) == 0n : Nat},
    content_preserves_arrangement: @+value:D.Style -> @content:E.ContentArea -> {E.frame_gap(style_frame(A.with_content_area(value, content))) == E.frame_gap(style_frame(value)) : Nat},
    role_navigation: @+meaning:UI.Meaning -> {style_frame(A.style(UI.Navigation{}, meaning)) == E.Frame{E.area(E.Navigation{}), E.SeparateFrames{E.NavigationRows{}}} : E.Frame},
    role_menu: @+meaning:UI.Meaning -> {style_frame(A.style(UI.Menu{}, meaning)) == E.Frame{E.area(E.Menu{}), E.SeparateFrames{E.MenuItems{}}} : E.Frame},
    role_card: @+meaning:UI.Meaning -> {style_frame(A.style(UI.Card{}, meaning)) == E.Frame{E.area(E.Card{}), E.SeparateFrames{E.CardSections{}}} : E.Frame},
    role_details: @+meaning:UI.Meaning -> {style_frame(A.style(UI.Details{}, meaning)) == E.Frame{E.area(E.Details{}), E.SeparateFrames{E.Sections{}}} : E.Frame},
    role_dialog: @+meaning:UI.Meaning -> {style_frame(A.style(UI.Dialog{}, meaning)) == E.Frame{E.DialogPartitions{}, E.JoinedPartitions{}} : E.Frame},
    actual_choice_geometry: @+key:String -> @+selected:Bool -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {actual_geometry(C.make_choice(key, selected, input, availability, label, role, context)) == C.Geometry{0n, 28n, 16n, 6n, 20n} : C.Geometry},
    actual_choice_layout: @+key:String -> @+selected:Bool -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 8n, 20n, 16n} : C.ChoiceContentLayout},
    actual_choice_mark_contains_icon: @+key:String -> @+selected:Bool -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {Nat.is_le(mark_icon_extent(C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context))), mark_extent(C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context)))) == True{} : Bool},
    selection_keeps_allocation: @+key:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {C.choice_layout(C.make_choice(key, True{}, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, False{}, input, availability, label, role, context)) : C.ChoiceContentLayout},
    production_choice_allocation: @+key:String -> @+label:String -> @+selected:Bool -> @+description:String -> @+visual:D.Style -> @+representation:C.Representation -> @+children:+List<D.Appearance> -> {R.choice_node(key, label, selected, description, visual, representation, children) == R.choice_face_layout(R.action(key, D.Appearance{key, visual, representation, children}, representation), label, description, selected, C.choice_layout(representation)) : Doc.Node},
    mark_reserves_space: @+key:String -> @+selected:Bool -> @+extent:Nat -> @+icon:Nat -> {(R.attr(Renderer.node_styles(R.choice_mark(key, selected, extent, icon)), "width"), (R.attr(Renderer.node_styles(R.choice_mark(key, selected, extent, icon)), "height"), R.attr(Renderer.node_styles(R.choice_mark(key, selected, extent, icon)), "flex-shrink"))) == (R.px(extent), (R.px(icon), "0")) : (String & (String & String))},
    project_siblings: @+key:String -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @+children:+List<Doc.Node> -> @+appearances:+List<D.Appearance> -> {R.attr(Renderer.node_styles(R.project_group_node(key, project, selected, expanded, children, appearances)), "gap") == R.px(E.separation(E.NavigationRows{})) : String},
    dialog_content_separation: {R.attr(R.dialog_content_styles(), "gap") == R.px(E.separation(E.DialogSections{})) : String},
    dialog_action_separation: {R.attr(R.dialog_footer_styles(), "gap") == R.px(E.separation(E.DialogActions{})) : String},
    choice_row_structure: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @+label:String -> @+description:String -> @+selected:Bool -> @+text_gap:Nat -> @+region_gap:Nat -> @+extent:Nat -> @+icon:Nat -> {R.choice_face_layout(Doc.Element{key, tag, attrs, styles, events, children}, label, description, selected, C.ChoiceContentLayout{text_gap, region_gap, extent, icon}) ==
    Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles,
      [R.property("display", "flex"), R.property("flex-direction", "row"), R.property("align-items", "center"), R.property("gap", R.px(region_gap)), R.property("width", "100%"), R.property("min-width", "0"), R.property("height", "auto"), R.property("flex-shrink", "0"), R.property("justify-content", "space-between")]), events,
      R.choice_content_layout(key, label, description, selected, C.ChoiceContentLayout{text_gap, region_gap, extent, icon})} : Doc.Node},
    timeline_gap: @+meaning:UI.Meaning -> {E.frame_gap(style_frame(A.style(UI.Timeline{}, meaning))) == E.separation(E.Messages{}) : Nat},
    section_gap: @+meaning:UI.Meaning -> {E.frame_gap(style_frame(A.style(UI.Section{}, meaning))) == E.separation(E.Sections{}) : Nat},
    choice_group_gap: @+key:String -> @+label:String -> @+visual:D.Style -> @+children:+List<Doc.Node> -> {R.attr(Renderer.node_styles(R.choice_group_node(key, label, visual, children)), "gap") == R.px(E.separation(E.MenuItems{})) : String},
    card_gap: @+key:String -> @+face:View.CardFace -> @+destinations:+List<UI.Placement> -> @+source:+List<UI.Node> -> @+rendered:+List<Doc.Node> -> @+visual:D.Style -> {R.attr(Renderer.node_styles(R.card_node(key, face, destinations, source, rendered, visual)), "gap") == R.px(E.separation(E.CardSections{})) : String},
    lane_allocation: @+stage:Board.Stage -> {(R.attr(R.board_lane_styles(stage), "padding-inline"), R.attr(R.board_lane_styles(stage), "padding-block")) == (R.px(E.inline(E.area(E.Lane{}))), R.px(E.block(E.area(E.Lane{})))) : (String & String)},
    archive_allocation: @+key:String -> @+label:String -> @+count:Nat -> @+children:+List<Doc.Node> -> {(R.attr(Renderer.node_styles(R.card_archive_node(key, label, count, children)), "padding-inline"), R.attr(Renderer.node_styles(R.card_archive_node(key, label, count, children)), "padding-block")) == (R.px(E.inline(E.area(E.ArchiveGroup{}))), R.px(E.block(E.area(E.ArchiveGroup{})))) : (String & String)},
    choice_text_allocation: @+key:String -> @+label:String -> @+description:String -> @+selected:Bool -> @+text_gap:Nat -> @+region_gap:Nat -> @+extent:Nat -> @+icon:Nat -> {R.choice_content_layout(key, label, description, selected, C.ChoiceContentLayout{text_gap, region_gap, extent, icon}) ==
    [Doc.Element{key ++ "/content", "span", Nil{}, [R.property("display", "flex"), R.property("flex-direction", "column"), R.property("flex", "1 1 0"), R.property("min-width", "0"), R.property("text-align", "start"), R.property("gap", R.px(text_gap))], Nil{},
      [Doc.Text{label}, Doc.Element{key ++ "/description", "span", Nil{}, [R.property("font-size", "12px"), R.property("color", "var(--color-token-text-secondary)"), R.property("white-space", "normal")], Nil{}, [Doc.Text{description}]}]},
      R.choice_mark(key, selected, extent, icon)] : +List<Doc.Node>}}

def evidence() -> Requirements:
  Requirements{embedded_gap, separate_gap, joined_gap, content_preserves_arrangement, role_navigation, role_menu, role_card, role_details, role_dialog, actual_choice_geometry, actual_choice_layout, actual_choice_mark_contains_icon, selection_keeps_allocation, production_choice_allocation, mark_reserves_space, project_siblings, dialog_content_separation(), dialog_action_separation(), choice_row_structure, timeline_gap, section_gap, choice_group_gap, card_gap, lane_allocation, archive_allocation, choice_text_allocation}
