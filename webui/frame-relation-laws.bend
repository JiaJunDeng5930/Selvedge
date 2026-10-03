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
  C.ChoiceContentLayout{text_gap, extent, icon_extent} = layout
  extent

def mark_icon_extent(layout: C.ChoiceContentLayout) -> Nat:
  C.ChoiceContentLayout{text_gap, extent, icon_extent} = layout
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
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def actual_choice_layout(+key: String, +selected: Bool, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 20n, 16n} : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def actual_choice_mark_contains_icon(+key: String, +selected: Bool, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {Nat.is_le(mark_icon_extent(C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context))), mark_extent(C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context)))) == True{} : Bool}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def selection_keeps_allocation(+key: String, +input: Core.Input, +availability: View.Availability, +label: String, +role: UI.Role, +context: C.Context) ->
  {C.choice_layout(C.make_choice(key, True{}, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, False{}, input, availability, label, role, context)) : C.ChoiceContentLayout}:
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  {==}

def production_choice_allocation(+key: String, +label: String, +selected: Bool, +description: String, +visual: D.Style, +representation: C.Representation, +children: +List<D.Appearance>) ->
  {R.choice_node(key, label, selected, description, visual, representation, children) == R.choice_face_layout(R.action(key, D.Appearance{key, visual, representation, children}, representation), label, description, selected, C.choice_layout(representation)) : Doc.Node}:
  {==}

def mark_reserves_space_law(-key: String, -selected: Bool, -extent: Nat, -icon: Nat) -> Type:
  {(R.attr(Doc.element_styles(R.choice_mark(key, selected, extent, icon)), "width"), (R.attr(Doc.element_styles(R.choice_mark(key, selected, extent, icon)), "height"), R.attr(Doc.element_styles(R.choice_mark(key, selected, extent, icon)), "flex-shrink"))) == (R.px(extent), (R.px(icon), "0")) : (String & (String & String))}

def mark_reserves_space(+key: String, +selected: Bool, +extent: Nat, +icon: Nat) -> mark_reserves_space_law(key, selected, extent, icon):
  {==}

def project_siblings(+key: String, +project: Nat, +selected: Bool, +expanded: Bool, +children: +List<Doc.Node>, +appearances: +List<D.Appearance>) ->
  {R.attr(Doc.element_styles(R.project_group_node(key, project, selected, expanded, A.project_group_style(), children, appearances)), "gap") == R.px(E.separation(E.NavigationRows{})) : String}:
  {==}

def dialog_content_separation() ->
  {R.attr(R.dialog_content_styles(), "gap") == R.px(E.separation(E.DialogSections{})) : String}:
  {==}

def dialog_action_separation() ->
  {R.attr(R.dialog_footer_styles(), "gap") == R.px(E.separation(E.DialogActions{})) : String}:
  {==}

def choice_row_structure_law(-key: String, -tag: String, -attrs: +List<Doc.Property>, -styles: +List<Doc.Property>, -events: +List<Doc.Event>, -children: +List<Doc.Node>, -label: String, -description: String, -selected: Bool, -text_gap: Nat, -region_gap: Nat, -extent: Nat, -icon: Nat) -> Type:
  {R.choice_face_layout(Doc.Element{key, tag, attrs, styles, events, children}, label, description, selected, C.ChoiceContentLayout{text_gap, extent, icon}) ==
      Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles,
        [R.property("width", "100%"), R.property("min-width", "0"), R.property("height", "auto"), R.property("flex-shrink", "0")]), events,
        R.choice_content_layout(key, label, description, selected, C.ChoiceContentLayout{text_gap, extent, icon})} : Doc.Node}

def choice_row_structure(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>, children: +List<Doc.Node>, +label: String, +description: String, +selected: Bool, +text_gap: Nat, +region_gap: Nat, +extent: Nat, +icon: Nat) -> choice_row_structure_law(key, tag, attrs, styles, events, children, label, description, selected, text_gap, region_gap, extent, icon):
  {==}

def timeline_gap(+meaning: UI.Meaning) ->
  {E.frame_gap(style_frame(A.style(UI.Timeline{}, meaning))) == E.separation(E.Messages{}) : Nat}:
  {==}

def section_gap(+meaning: UI.Meaning) ->
  {E.frame_gap(style_frame(A.style(UI.Section{}, meaning))) == E.separation(E.Sections{}) : Nat}:
  {==}

def choice_group_gap(+key: String, +label: String, +visual: D.Style, +children: +List<Doc.Node>) ->
  {R.attr(Doc.element_styles(R.choice_group_node(key, label, A.choice_group_style(visual), children)), "gap") == R.px(E.separation(E.MenuItems{})) : String}:
  D.Style{text, D.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  E.Frame{content, arrangement} = frame
  +normalized = A.choice_group_style(D.Style{text, D.Chrome{foreground, background, border, width, radius, shadow}, alignment, flow, overflow,
    E.Frame{content, arrangement}, minimum, maximum, states})
  Equal.trans(String,
    R.attr(Doc.element_styles(R.choice_group_node(key, label, normalized, children)), "gap"),
    R.attr(R.style(normalized), "gap"), R.px(E.separation(E.MenuItems{})),
    EnclosureRender.last_append(R.style(normalized), [R.property("flex-shrink", "0"), R.property("height", "auto")], "gap", ""),
    EnclosureRender.parent_style(False{}, EnclosureRender.FrameGap{}, normalized))

def lane_allocation(+stage: Board.Stage) ->
  {(R.attr(R.board_lane_styles(stage), "padding-inline"), R.attr(R.board_lane_styles(stage), "padding-block")) == (R.px(E.inline(E.area(E.Lane{}))), R.px(E.block(E.area(E.Lane{})))) : (String & String)}:
  {==}

def archive_allocation_law(-key: String, -label: String, -count: Nat, -children: +List<Doc.Node>) -> Type:
  {(R.attr(Doc.element_styles(R.card_archive_node(key, label, count, children)), "padding-inline"), R.attr(Doc.element_styles(R.card_archive_node(key, label, count, children)), "padding-block")) == (R.px(E.inline(E.area(E.ArchiveGroup{}))), R.px(E.block(E.area(E.ArchiveGroup{})))) : (String & String)}

def archive_allocation(+key: String, +label: String, +count: Nat, +children: +List<Doc.Node>) -> archive_allocation_law(key, label, count, children):
  {==}

def choice_text_allocation_law(-key: String, -label: String, -description: String, -selected: Bool, -text_gap: Nat, -region_gap: Nat, -extent: Nat, -icon: Nat) -> Type:
  {R.choice_content_layout(key, label, description, selected, C.ChoiceContentLayout{text_gap, extent, icon}) ==
      [Doc.Element{key ++ "/content", "span", Nil{}, [R.property("display", "flex"), R.property("flex-direction", "column"), R.property("flex", "1 1 0"), R.property("min-width", "0"), R.property("text-align", "start"), R.property("gap", R.px(text_gap))], Nil{},
        [Doc.Text{label}, Doc.Element{key ++ "/description", "span", Nil{}, [R.property("font-size", "12px"), R.property("color", "var(--color-token-text-secondary)"), R.property("white-space", "normal")], Nil{}, [Doc.Text{description}]}]},
        R.choice_mark(key, selected, extent, icon)] : +List<Doc.Node>}

def choice_text_allocation(+key: String, +label: String, +description: String, +selected: Bool, +text_gap: Nat, +region_gap: Nat, +extent: Nat, +icon: Nat) -> choice_text_allocation_law(key, label, description, selected, text_gap, region_gap, extent, icon):
  {==}

def style_flow(value: D.Style) -> D.Flow:
  D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  flow

def frame_value(+value: D.Style) ->
  {EnclosureRender.parent_value(value, EnclosureRender.FrameGap{}) == R.px(E.frame_gap(style_frame(value))) : String}:
  D.Style{text, D.Chrome{fg, bg, border, width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = value
  {==}

def card_structure_law(-key: String, -id: Nat, -title: String, -description: String, -priority: Board.Priority, -pinned: Bool, -status: String, -project: String, -labels: +List<String>, -owner: String, -updated: String, -destinations: +List<UI.Placement>, -source: +List<UI.Node>, -rendered: +List<Doc.Node>, -visual: D.Style) -> Type:
  {R.card_node(key, View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}, destinations, source, rendered, visual) ==
    Doc.Element{key, "article", [R.property("data-native-key", key), R.property("data-card-id", Nat.show(id)), R.property("data-card-title", title), R.property("aria-label", title), R.property("draggable", "true")], R.style(visual), [Doc.DragCard{key}, Doc.DropCard{key}], R.card_children(key, View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated}, source, rendered)} : Doc.Node}

def card_structure(+key: String, +id: Nat, +title: String, +description: String, +priority: Board.Priority, +pinned: Bool, +status: String, +project: String, +labels: +List<String>, +owner: String, +updated: String, +destinations: +List<UI.Placement>, +source: +List<UI.Node>, +rendered: +List<Doc.Node>, +visual: D.Style) -> card_structure_law(key, id, title, description, priority, pinned, status, project, labels, owner, updated, destinations, source, rendered, visual):
  {==}

def card_gap_law(-key: String, -face: View.CardFace, -destinations: +List<UI.Placement>, -source: +List<UI.Node>, -rendered: +List<Doc.Node>, -visual: D.Style) -> Type:
  {R.attr(Doc.element_styles(R.card_node(key, face, destinations, source, rendered, visual)), "gap") == R.px(E.frame_gap(style_frame(visual))) : String}

def card_gap(+key: String, +face: View.CardFace, +destinations: +List<UI.Placement>, +source: +List<UI.Node>, +rendered: +List<Doc.Node>, +visual: D.Style) -> card_gap_law(key, face, destinations, source, rendered, visual):
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  Equal.trans(String, R.attr(R.style(visual), "gap"), EnclosureRender.parent_value(visual, EnclosureRender.FrameGap{}), R.px(E.frame_gap(style_frame(visual))), EnclosureRender.parent_style(False{}, EnclosureRender.FrameGap{}, visual), frame_value(visual))

def card_properties(+styles: +List<Doc.Property>) -> (String & (String & (String & (String & (String & (String & (String & (String & String)))))))):
  (R.attr(styles, "display"), (R.attr(styles, "flex-direction"), (R.attr(styles, "gap"), (R.attr(styles, "min-width"), (R.attr(styles, "border-color"), (R.attr(styles, "border-width"), (R.attr(styles, "border-style"), (R.attr(styles, "border-radius"), R.attr(styles, "box-shadow")))))))))

def card_production_properties_law(-key: String, -face: View.CardFace, -destinations: +List<UI.Placement>, -source: +List<UI.Node>, -rendered: +List<Doc.Node>, -meaning: UI.Meaning) -> Type:
  {card_properties(Doc.element_styles(R.card_node(key, face, destinations, source, rendered, A.style(UI.Card{}, meaning)))) ==
    ("flex", ("column", (R.px(E.separation(E.CardSections{})), ("0", ("var(--color-token-border-default)", ("1px", ("solid", ("9px", "var(--shadow-sm)")))))))) : (String & (String & (String & (String & (String & (String & (String & (String & String))))))))}

def card_production_properties(+key: String, +face: View.CardFace, +destinations: +List<UI.Placement>, +source: +List<UI.Node>, +rendered: +List<Doc.Node>, +meaning: UI.Meaning) -> card_production_properties_law(key, face, destinations, source, rendered, meaning):
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  {==}

def action_frame_gap_law(-key: String, -visual: D.Style, -input: Core.Input, -availability: View.Availability, -name: String,
  -face: C.Face, -behavior: C.Behavior, -size: C.Geometry, -placement: C.Placement, -help: C.Help, -feedback: C.Feedback) -> Type:
  {R.attr(Doc.element_styles(R.action(key, D.Appearance{key, visual, C.NoControl{}, Nil{}}, C.Action{input, availability, name, face, behavior, size, placement, help, feedback})), "gap") == R.px(E.frame_gap(style_frame(visual))) : String}

def action_frame_gap(+key: String, +visual: D.Style, +input: Core.Input, +availability: View.Availability, +name: String,
  +face: C.Face, +behavior: C.Behavior, +size: C.Geometry, +placement: C.Placement, +help: C.Help, +feedback: C.Feedback) -> action_frame_gap_law(key, visual, input, availability, name, face, behavior, size, placement, help, feedback):
  Equal.trans(String,
    R.attr(Doc.element_styles(R.action(key, D.Appearance{key, visual, C.NoControl{}, Nil{}}, C.Action{input, availability, name, face, behavior, size, placement, help, feedback})), "gap"),
    EnclosureRender.parent_value(visual, EnclosureRender.FrameGap{}), R.px(E.frame_gap(style_frame(visual))),
    EnclosureRender.parent_action(EnclosureRender.FrameGap{}, key, visual, input, availability, name, face, behavior, size, placement, help, feedback), frame_value(visual))

def choice_frame_gap_law(-key: String, -label: String, -selected: Bool, -description: String, -visual: D.Style,
  -input: Core.Input, -availability: View.Availability, -name: String, -face: C.Face, -behavior: C.Behavior,
  -size: C.Geometry, -placement: C.Placement, -help: C.Help, -feedback: C.Feedback) -> Type:
  {R.attr(Doc.element_styles(R.choice_node(key, label, selected, description, visual, C.Action{input, availability, name, face, behavior, size, placement, help, feedback}, Nil{})), "gap") == R.px(E.frame_gap(style_frame(visual))) : String}

def choice_frame_gap(+key: String, +label: String, +selected: Bool, +description: String, +visual: D.Style,
  +input: Core.Input, +availability: View.Availability, +name: String, +face: C.Face, +behavior: C.Behavior,
  +size: C.Geometry, +placement: C.Placement, +help: C.Help, +feedback: C.Feedback) -> choice_frame_gap_law(key, label, selected, description, visual, input, availability, name, face, behavior, size, placement, help, feedback):
  C.Geometry{+width, +height, +icon, +radius, +leading} = size
  +actual_size: C.Geometry = C.Geometry{width, height, icon, radius, leading}
  Equal.trans(String,
    R.attr(Doc.element_styles(R.choice_node(key, label, selected, description, visual, C.Action{input, availability, name, face, behavior, actual_size, placement, help, feedback}, Nil{})), "gap"),
    R.attr(Doc.element_styles(R.action(key, D.Appearance{key, visual, C.NoControl{}, Nil{}}, C.Action{input, availability, name, face, behavior, actual_size, placement, help, feedback})), "gap"), R.px(E.frame_gap(style_frame(visual))),
    EnclosureRender.last_append(Doc.element_styles(R.action(key, D.Appearance{key, visual, C.NoControl{}, Nil{}}, C.Action{input, availability, name, face, behavior, actual_size, placement, help, feedback})),
      [R.property("width", "100%"), R.property("min-width", "0"), R.property("height", "auto"), R.property("flex-shrink", "0")], "gap", ""),
    action_frame_gap(key, visual, input, availability, name, face, behavior, actual_size, placement, help, feedback))

def flow_assigned(+value: D.Style, +flow: D.Flow) ->
  {style_flow(A.with_flow(value, flow)) == flow : D.Flow}:
  D.Style{text, chrome, alignment, old_flow, overflow, frame, minimum, maximum, states} = value
  {==}

def actual_action_flow(+value: D.Style, +face: C.Face, +size: C.Geometry) ->
  {style_flow(A.action_style(value, face, size)) == A.action_flow(face, C.content_layout(face)) : D.Flow}:
  flow_assigned(A.action_content_style(A.action_text(value, face, size), C.content_layout(face), size), A.action_flow(face, C.content_layout(face)))

def choice_style_metrics(+value: D.Style) -> (Nat & D.Flow):
  (E.frame_gap(style_frame(value)), style_flow(value))

def choice_style_normalization(+value: D.Style, +size: C.Geometry, label: String, selected: Bool) ->
  {choice_style_metrics(A.action_style(value, C.ChoiceFace{label, selected}, size)) == (8n, D.ChoiceFlow{}) : (Nat & D.Flow)}:
  D.Style{text, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = value
  C.Geometry{width, height, icon, radius, leading} = size
  {==}

def actual_choice_normalization_law(-key: String, -selected: Bool, -input: Core.Input, -availability: View.Availability, -label: String,
  -role: UI.Role, -context: C.Context, -fallback: D.Style) -> Type:
  {choice_style_metrics(A.control_style(fallback, C.make_choice(key, selected, input, availability, label, role, context))) == (8n, D.ChoiceFlow{}) : (Nat & D.Flow)}

def actual_choice_normalization(+key: String, +selected: Bool, +input: Core.Input, +availability: View.Availability, +label: String,
  +role: UI.Role, +context: C.Context, +fallback: D.Style) -> actual_choice_normalization_law(key, selected, input, availability, label, role, context, fallback):
  C.Context{area, selection, code, appearance, access, settings_open, layers, execution, source_family} = context
  +intent = C.purpose_fields(key, input, selection, code, appearance, access, settings_open, layers)
  choice_style_normalization(A.feedback_style(A.choice_button(selected), C.feedback_for(intent)), C.Geometry{0n, 28n, 16n, 6n, 20n}, C.name_for(intent, label), selected)

type Requirements is Type:
  Requirements{
    card_structure: @+key:String -> @+id:Nat -> @+title:String -> @+description:String -> @+priority:Board.Priority -> @+pinned:Bool -> @+status:String -> @+project:String -> @+labels:+List<String> -> @+owner:String -> @+updated:String -> @+destinations:+List<UI.Placement> -> @+source:+List<UI.Node> -> @+rendered:+List<Doc.Node> -> @+visual:D.Style -> card_structure_law(key, id, title, description, priority, pinned, status, project, labels, owner, updated, destinations, source, rendered, visual),
    card_production_properties: @+key:String -> @+face:View.CardFace -> @+destinations:+List<UI.Placement> -> @+source:+List<UI.Node> -> @+rendered:+List<Doc.Node> -> @+meaning:UI.Meaning -> card_production_properties_law(key, face, destinations, source, rendered, meaning),
    action_frame_gap: @+key:String -> @+visual:D.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:C.Face -> @+behavior:C.Behavior -> @+size:C.Geometry -> @+placement:C.Placement -> @+help:C.Help -> @+feedback:C.Feedback ->
      action_frame_gap_law(key, visual, input, availability, name, face, behavior, size, placement, help, feedback),
    choice_frame_gap: @+key:String -> @+label:String -> @+selected:Bool -> @+description:String -> @+visual:D.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:C.Face -> @+behavior:C.Behavior -> @+size:C.Geometry -> @+placement:C.Placement -> @+help:C.Help -> @+feedback:C.Feedback ->
      choice_frame_gap_law(key, label, selected, description, visual, input, availability, name, face, behavior, size, placement, help, feedback),
    actual_action_flow: @+value:D.Style -> @+face:C.Face -> @+size:C.Geometry ->
      {style_flow(A.action_style(value, face, size)) == A.action_flow(face, C.content_layout(face)) : D.Flow},
    actual_choice_normalization: @+key:String -> @+selected:Bool -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> @+fallback:D.Style ->
      actual_choice_normalization_law(key, selected, input, availability, label, role, context, fallback),
    embedded_gap: @+content:E.ContentArea -> @+gap:Nat -> {E.frame_gap(E.frame(content, E.EmbeddedContent{gap})) == gap : Nat},
    separate_gap: @+content:E.ContentArea -> @+spacing:E.Separation -> {E.frame_gap(E.frame(content, E.SeparateFrames{spacing})) == E.separation(spacing) : Nat},
    joined_gap: @content:E.ContentArea -> {E.frame_gap(E.frame(content, E.JoinedPartitions{})) == 0n : Nat},
    content_preserves_arrangement: @+value:D.Style -> @content:E.ContentArea -> {E.frame_gap(style_frame(A.with_content_area(value, content))) == E.frame_gap(style_frame(value)) : Nat},
    role_navigation: @+meaning:UI.Meaning -> {style_frame(A.style(UI.Navigation{}, meaning)) == E.Frame{E.area(E.Navigation{}), E.SeparateFrames{E.NavigationRows{}}} : E.Frame},
    role_menu: @+meaning:UI.Meaning -> {style_frame(A.style(UI.Menu{}, meaning)) == E.Frame{E.area(E.Menu{}), E.SeparateFrames{E.MenuItems{}}} : E.Frame},
    role_card: @+meaning:UI.Meaning -> {style_frame(A.style(UI.Card{}, meaning)) == E.Frame{E.area(E.Card{}), E.SeparateFrames{E.CardSections{}}} : E.Frame},
    role_details: @+meaning:UI.Meaning -> {style_frame(A.style(UI.Details{}, meaning)) == E.Frame{E.area(E.Details{}), E.SeparateFrames{E.Sections{}}} : E.Frame},
    role_dialog: @+meaning:UI.Meaning -> {style_frame(A.style(UI.Dialog{}, meaning)) == E.Frame{E.DialogPartitions{}, E.JoinedPartitions{}} : E.Frame},
    actual_choice_geometry: @+key:String -> @+selected:Bool -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {actual_geometry(C.make_choice(key, selected, input, availability, label, role, context)) == C.Geometry{0n, 28n, 16n, 6n, 20n} : C.Geometry},
    actual_choice_layout: @+key:String -> @+selected:Bool -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context)) == C.ChoiceContentLayout{2n, 20n, 16n} : C.ChoiceContentLayout},
    actual_choice_mark_contains_icon: @+key:String -> @+selected:Bool -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {Nat.is_le(mark_icon_extent(C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context))), mark_extent(C.choice_layout(C.make_choice(key, selected, input, availability, label, role, context)))) == True{} : Bool},
    selection_keeps_allocation: @+key:String -> @+input:Core.Input -> @+availability:View.Availability -> @+label:String -> @+role:UI.Role -> @+context:C.Context -> {C.choice_layout(C.make_choice(key, True{}, input, availability, label, role, context)) == C.choice_layout(C.make_choice(key, False{}, input, availability, label, role, context)) : C.ChoiceContentLayout},
    production_choice_allocation: @+key:String -> @+label:String -> @+selected:Bool -> @+description:String -> @+visual:D.Style -> @+representation:C.Representation -> @+children:+List<D.Appearance> -> {R.choice_node(key, label, selected, description, visual, representation, children) == R.choice_face_layout(R.action(key, D.Appearance{key, visual, representation, children}, representation), label, description, selected, C.choice_layout(representation)) : Doc.Node},
    mark_reserves_space: @+key:String -> @+selected:Bool -> @+extent:Nat -> @+icon:Nat -> mark_reserves_space_law(key, selected, extent, icon),
    project_siblings: @+key:String -> @+project:Nat -> @+selected:Bool -> @+expanded:Bool -> @+children:+List<Doc.Node> -> @+appearances:+List<D.Appearance> -> {R.attr(Doc.element_styles(R.project_group_node(key, project, selected, expanded, A.project_group_style(), children, appearances)), "gap") == R.px(E.separation(E.NavigationRows{})) : String},
    dialog_content_separation: {R.attr(R.dialog_content_styles(), "gap") == R.px(E.separation(E.DialogSections{})) : String},
    dialog_action_separation: {R.attr(R.dialog_footer_styles(), "gap") == R.px(E.separation(E.DialogActions{})) : String},
    choice_row_structure: @+key:String -> @+tag:String -> @+attrs:+List<Doc.Property> -> @+styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @children:+List<Doc.Node> -> @+label:String -> @+description:String -> @+selected:Bool -> @+text_gap:Nat -> @+region_gap:Nat -> @+extent:Nat -> @+icon:Nat -> choice_row_structure_law(key, tag, attrs, styles, events, children, label, description, selected, text_gap, region_gap, extent, icon),
    timeline_gap: @+meaning:UI.Meaning -> {E.frame_gap(style_frame(A.style(UI.Timeline{}, meaning))) == E.separation(E.Messages{}) : Nat},
    section_gap: @+meaning:UI.Meaning -> {E.frame_gap(style_frame(A.style(UI.Section{}, meaning))) == E.separation(E.Sections{}) : Nat},
    choice_group_gap: @+key:String -> @+label:String -> @+visual:D.Style -> @+children:+List<Doc.Node> -> {R.attr(Doc.element_styles(R.choice_group_node(key, label, A.choice_group_style(visual), children)), "gap") == R.px(E.separation(E.MenuItems{})) : String},
    card_gap: @+key:String -> @+face:View.CardFace -> @+destinations:+List<UI.Placement> -> @+source:+List<UI.Node> -> @+rendered:+List<Doc.Node> -> @+visual:D.Style -> card_gap_law(key, face, destinations, source, rendered, visual),
    lane_allocation: @+stage:Board.Stage -> {(R.attr(R.board_lane_styles(stage), "padding-inline"), R.attr(R.board_lane_styles(stage), "padding-block")) == (R.px(E.inline(E.area(E.Lane{}))), R.px(E.block(E.area(E.Lane{})))) : (String & String)},
    archive_allocation: @+key:String -> @+label:String -> @+count:Nat -> @+children:+List<Doc.Node> -> archive_allocation_law(key, label, count, children),
    choice_text_allocation: @+key:String -> @+label:String -> @+description:String -> @+selected:Bool -> @+text_gap:Nat -> @+region_gap:Nat -> @+extent:Nat -> @+icon:Nat -> choice_text_allocation_law(key, label, description, selected, text_gap, region_gap, extent, icon)}

def evidence() -> Requirements:
  Requirements{card_structure, card_production_properties, action_frame_gap, choice_frame_gap, actual_action_flow, actual_choice_normalization, embedded_gap, separate_gap, joined_gap, content_preserves_arrangement, role_navigation, role_menu, role_card, role_details, role_dialog, actual_choice_geometry, actual_choice_layout, actual_choice_mark_contains_icon, selection_keeps_allocation, production_choice_allocation, mark_reserves_space, project_siblings, dialog_content_separation(), dialog_action_separation(), choice_row_structure, timeline_gap, section_gap, choice_group_gap, card_gap, lane_allocation, archive_allocation, choice_text_allocation}
