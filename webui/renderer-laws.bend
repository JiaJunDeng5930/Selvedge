import ../core/interface.bend as Interface
import Base
import ./typography.bend as T
import ../bendlib/stdlib.bend as Std
import ./document.bend as Doc
import ./renderer.bend as Render
import ./dialog-spatial-laws.bend as DialogSpatial
import ./shell-spatial-laws.bend as ShellSpatial
import ./design.bend as Design
import ./controls.bend as Controls
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../core/form-fields.bend as Forms
import ../core/user-input.bend as User
import ../core/user-conversation.bend as Conversation
import ../BOARD.bend as Board

# These observations read the actual browser primitives, independently of the
# renderer's construction functions. Missing geometry is the empty observation.

def css_box(+properties: +List<Doc.Property>) -> (String & (String & (String & String))):
  (Render.attr(properties, "left"), (Render.attr(properties, "top"),
    (Render.attr(properties, "width"), Render.attr(properties, "height"))))

def observed_box(node: Doc.Node) -> (String & (String & (String & String))):
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: css_box(styles)
    case _: ("", ("", ("", "")))

def specified_box(box: Design.Box) -> (String & (String & (String & String))):
  Design.Box{left, top, width, height} = box
  (Nat.show(left) ++ "px", (Nat.show(top) ++ "px", (Nat.show(width) ++ "px", Nat.show(height) ++ "px")))

def first_node(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Nil{}: Doc.Text{""}
    case Con{value, rest}: value

def second_node(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Con{value, rest}: first_node(rest)
    case Nil{}: Doc.Text{""}

def direct_text(node: Doc.Node) -> String:
  match node:
    case Doc.Text{value}: value
    case Doc.Element{key, tag, attrs, styles, events, children}:
      match children:
        case Con{Doc.Text{value}, Nil{}}: value
        case _: ""
    case Doc.Markdown{key, source, value}: value
    case _: ""

def direct_text_slots(values: +List<Doc.Node>) -> +List<String>:
  Std.map(~Doc.Node, ~String, ~direct_text, values)

def direct_texts(values: +List<Doc.Node>) -> String:
  match values:
    case Nil{}: ""
    case Con{node, rest}: direct_text(node) ++ direct_texts(rest)

def optional_text_slots_when(empty: Bool, +value: String) -> +List<String>:
  match empty:
    case True{}: Nil{}
    case False{}: [value]

def optional_text_slots(+value: String) -> +List<String>:
  optional_text_slots_when(String.is_empty(value), value)

def optional_pin_slots(pinned: Bool) -> +List<String>:
  match pinned:
    case True{}: ["已置顶"]
    case False{}: Nil{}



def target_attributes(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.TargetProperties{key, target, attributes, styles}: attributes
    case _: Nil{}

def target_styles(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.TargetProperties{key, target, attributes, styles}: styles
    case _: Nil{}






































def board_column_style_projection(+key: String, +width: Nat) -> (String & (String & String)):
  +column = first_node(Render.board_columns([Doc.Element{key, "section", Nil{}, Nil{}, Nil{}, Nil{}}], width))
  +styles = Doc.element_styles(column)
  (Render.attr(styles, "width"), (Render.attr(styles, "flex"), Render.attr(styles, "height")))







def card_root_face_expected(+key: String, +face: View.CardFace) -> (String & (String & (String & String))):
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  (key, (Nat.show(id), (title, title)))

def card_root_face_projection_law(-key: String, -face: View.CardFace, -destinations: +List<Interface.Placement>, -source: +List<Render.Child>, -visual: Design.Style) -> Type:
  {(Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual, Design.style_text(visual))), "data-native-key"),
      (Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual, Design.style_text(visual))), "data-card-id"),
       (Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual, Design.style_text(visual))), "data-card-title"),
       Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual, Design.style_text(visual))), "aria-label")))) ==
      card_root_face_expected(key, face) : (String & (String & (String & String)))}

def card_face_status(+face: View.CardFace) -> String:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  status

def card_metadata_expected(+face: View.CardFace, status_empty: Bool) -> +List<String>:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  List.append(&2, String,
    ["SV-" ++ Nat.show(id), Board.priority_label(priority)],
    List.append(&2, String, optional_pin_slots(pinned), optional_text_slots_when(status_empty, status)))

def card_footer_expected(+face: View.CardFace) -> +List<String>:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  List.append(&2, String, optional_text_slots(owner), optional_text_slots(updated))

def node_key(node: Doc.Node) -> String:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: key
    case _: ""

def rest_nodes(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Con{first, rest}: rest
    case Nil{}: Nil{}

def rendered_dialog(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) -> Doc.Node:
  Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  Render.match_node(Design.Node{key, semantic, label, Interface.Dialog{}, Interface.Region{}, Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states}, Controls.NoControl{}, source}, Render.render_children(source))

def dialog_header_node(node: Doc.Node) -> Doc.Node:
  first_node(Doc.element_children(node))

def dialog_body_node(node: Doc.Node) -> Doc.Node:
  second_node(Doc.element_children(node))

def dialog_content_node(node: Doc.Node) -> Doc.Node:
  first_node(Doc.element_children(dialog_body_node(node)))

def dialog_title_node(node: Doc.Node) -> Doc.Node:
  first_node(Doc.element_children(dialog_header_node(node)))

def dialog_header_keep(is_header: Bool, +child: Doc.Node, rest: +List<Doc.Node>) -> +List<Doc.Node>:
  match is_header:
    case True{}: child <> rest
    case False{}: rest

def dialog_body_keep(is_header: Bool, +child: Doc.Node, rest: +List<Doc.Node>) -> +List<Doc.Node>:
  match is_header:
    case True{}: rest
    case False{}: child <> rest

def expected_dialog_header_prepend(+appearance: Render.Child,
  +rest: +List<Doc.Node>) -> +List<Doc.Node>:
  Render.Child{+source, +document} = appearance
  Design.Node{identity, semantic, label, role, meaning, visual, +representation, children} = source
  dialog_header_keep(Controls.panel_header(representation) || Render.persistent_details_header(representation), document, rest)

def expected_dialog_body_prepend(+appearance: Render.Child,
  +rest: +List<Doc.Node>) -> +List<Doc.Node>:
  Render.Child{+source, +document} = appearance
  Design.Node{identity, semantic, label, role, meaning, visual, +representation, children} = source
  dialog_body_keep(Controls.panel_header(representation) || Render.persistent_details_header(representation), document, rest)

def expected_dialog_header(children: +List<Render.Child>) -> +List<Doc.Node>:
  match children:
    case Con{child, rest}: expected_dialog_header_prepend(child, expected_dialog_header(rest))
    case Nil{}: Nil{}

def expected_dialog_body(children: +List<Render.Child>) -> +List<Doc.Node>:
  match children:
    case Con{child, rest}: expected_dialog_body_prepend(child, expected_dialog_body(rest))
    case Nil{}: Nil{}

def expected_popover_styles(anchor: String, available: Design.Box,
  maximum_width: Nat, maximum_height: Nat, gap: Nat) -> +List<Doc.Property>:
  Design.Box{left, top, width, height} = available
  [Render.property("position", "fixed"), Render.property("position-anchor", Render.css_anchor(anchor)),
   Render.property("position-area", "bottom span-left"),
   Render.property("position-try-fallbacks", "flip-block, flip-inline, flip-block flip-inline"),
   Render.property("position-try-order", "most-block-size"), Render.property("align-self", "normal"),
   Render.property("height", "max-content"), Render.property("margin", Render.px(gap)),
   Render.property("max-width", Render.px(Nat.min(width, maximum_width))),
   Render.property("max-height", Render.px(Nat.min(height, maximum_height))), Render.property("overflow", "auto")]

def font_properties(+value: Design.Style) -> (String & (String & (String & String))):
  (Render.attr(Render.style(value), "font-family"),
    (Render.attr(Render.style(value), "font-size"),
      (Render.attr(Render.style(value), "line-height"), Render.attr(Render.style(value), "font-weight"))))

def owned_font_properties(+presentation: T.Presentation) -> (String & (String & (String & String))):
  +resolved = T.resolved(presentation)
  (T.font_family(T.resolved_font(resolved)),
    (Render.px(T.resolved_size(resolved)),
      (Render.px(T.resolved_line_height(resolved)), Nat.show(T.resolved_weight(resolved)))))

def placed_wrapper_styles(+key: String, +attrs: +List<Doc.Property>, styles: +List<Doc.Property>, frame: Design.MainFrame) -> +List<Doc.Property>:
  Doc.element_styles(Render.place_element(key, "div", attrs, styles, Nil{}, Nil{}, frame))

def expected_reading(+region: String, +key: String, tag: String, +attrs: +List<Doc.Property>, styles: +List<Doc.Property>, events: +List<Doc.Event>, +children: +List<Doc.Node>, identity: Maybe<&2, Conversation.Identity>, +frame: Design.MainFrame) -> Doc.Node:
  match region identity:
    case "conversation-body" Some{Conversation.Identity{+task, +generation}}:
      +body_key = "conversation/" ++ Nat.show(task) ++ "/body"
      Doc.Element{body_key, tag, List.append(&2, Doc.Property, attrs, [Doc.Property{"data-reading-scroll", ""}, Doc.Property{"data-reading-task", Nat.show(task)}, Doc.Property{"data-reading-generation", Nat.show(generation)}]), placed_wrapper_styles(body_key, List.append(&2, Doc.Property, attrs, [Doc.Property{"data-reading-scroll", ""}, Doc.Property{"data-reading-task", Nat.show(task)}, Doc.Property{"data-reading-generation", Nat.show(generation)}]), styles, frame), events, [Doc.Element{body_key ++ "/reading-content", "div", [Doc.Property{"data-reading-content", ""}, Doc.Property{"data-reading-task", Nat.show(task)}], placed_wrapper_styles(body_key ++ "/reading-content", [Doc.Property{"data-reading-content", ""}, Doc.Property{"data-reading-task", Nat.show(task)}], [Doc.Property{"display", "flex"}, Doc.Property{"flex-direction", "column"}, Doc.Property{"gap", "16px"}], frame), Nil{}, Render.place_children(children, False{}, frame)}]}
    case "dock" Some{Conversation.Identity{+task, generation}}:
      Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [Doc.Property{"data-reading-dock", ""}, Doc.Property{"data-reading-task", Nat.show(task)}]), placed_wrapper_styles(key, List.append(&2, Doc.Property, attrs, [Doc.Property{"data-reading-dock", ""}, Doc.Property{"data-reading-task", Nat.show(task)}]), styles, frame), events, Render.place_children(children, String.eq(key, "board-body"), frame)}
    case _ _:
      Doc.Element{key, tag, attrs, placed_wrapper_styles(key, attrs, styles, frame), events, Render.place_children(children, String.eq(key, "board-body"), frame)}

def expected_conversation(+children: +List<Doc.Node>, +heading: Design.Box, +viewport: Design.Box, +reading: Design.Band, +dock: Maybe<&2, Design.Dock>, +identity: Maybe<&2, Conversation.Identity>) -> +List<Doc.Node>:
  +frame: Design.MainFrame = Design.ConversationFrame{heading, viewport, reading, dock}
  [Doc.Element{"conversation-heading", "div", [Doc.Property{"data-page-group", "heading"}], placed_wrapper_styles("conversation-heading", [Doc.Property{"data-page-group", "heading"}], [Render.property("z-index", "5")], frame), Nil{}, Render.place_children(Render.conversation_heading_nodes(children), False{}, frame)},
   expected_reading("conversation-body", "conversation-body", "div", [Render.property("data-region", "conversation-body"), Render.property("data-page-group", "body")],
     [Render.property("display", "flex"), Render.property("flex-direction", "column"), Render.property("gap", "16px"), Render.property("overflow-y", "auto")], Nil{}, Render.page_nodes(children, "body"), identity, frame),
   expected_reading("dock", "conversation-dock", "div", [Render.property("data-region", "dock"), Render.property("data-page-group", "dock")],
     [Render.property("display", "flex"), Render.property("flex-direction", "column"), Render.property("gap", "8px"), Render.property("overflow", "hidden")], Nil{}, Render.conversation_dock_regions(Render.page_nodes(children, "dock")), identity, frame)]


type Requirements is Type:
  Requirements{
    actual_font_bridge: @+value:Design.Style ->
      {Render.attr(Render.style(value), "font-family") == T.font_family(T.resolved_font(T.resolved(Design.style_text(value)))) : String} &
      {Render.attr(Render.style(value), "font-size") == Render.px(T.resolved_size(T.resolved(Design.style_text(value)))) : String} &
      {Render.attr(Render.style(value), "line-height") == Render.px(T.resolved_line_height(T.resolved(Design.style_text(value)))) : String} &
      {Render.attr(Render.style(value), "font-weight") == Nat.show(T.resolved_weight(T.resolved(Design.style_text(value)))) : String},
    field_options_empty: @key:String ->
      {Render.field_options(key, Nil{}) == Nil{} : +List<Doc.Node>},
    field_options_cons: @+key:String -> @+value:String -> @label:String -> @choices:+List<Forms.ChoiceValue> ->
      {Render.field_options(key, Forms.ChoiceValue{value, label} <> choices) ==
        Doc.Element{key ++ "/option/" ++ value, "option", [Doc.Property{"value", value}], Nil{}, Nil{}, [Doc.Text{label}]} <>
          Render.field_options(key, choices) : +List<Doc.Node>},
    activity_content_document: @+key:String -> @semantic:String -> @+label:String -> @role:Interface.Role ->
      @expanded:Bool -> @audit:+List<Conversation.AuditFace> -> @+visual:Design.Style ->
      @representation:Controls.Representation -> @+source:+List<Design.Node> ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.ActivityContent{expanded, audit}, visual, representation, source}, Render.render_children(source)) ==
        Doc.Element{key, "details", List.append(&2, Doc.Property, [Doc.Property{"aria-label", label}, Doc.Property{"data-native-key", key}], Render.opened(expanded)),
          Render.style(visual), Nil{}, List.append(&2, Doc.Node, Render.activity_summary(key, label, Render.render_nodes(source)), Render.audit_nodes(key, audit))} : Doc.Node},
    conversation_body_identity: @+task:Nat -> @generation:Nat -> @key:String -> @tag:String ->
      @attrs:+List<Doc.Property> -> @styles:+List<Doc.Property> -> @events:+List<Doc.Event> -> @children:+List<Doc.Node> ->
      {Render.reading_element("conversation-body", key, tag, attrs, styles, events, children, Some{Conversation.Identity{task, generation}}) ==
        Doc.Element{"conversation/" ++ Nat.show(task) ++ "/body", tag,
          List.append(&2, Doc.Property, attrs, [Doc.Property{"data-reading-scroll", ""}, Doc.Property{"data-reading-task", Nat.show(task)}, Doc.Property{"data-reading-generation", Nat.show(generation)}]),
          styles, events, [Doc.Element{("conversation/" ++ Nat.show(task) ++ "/body") ++ "/reading-content", "div",
            [Doc.Property{"data-reading-content", ""}, Doc.Property{"data-reading-task", Nat.show(task)}],
            [Doc.Property{"display", "flex"}, Doc.Property{"flex-direction", "column"}, Doc.Property{"gap", "16px"}], Nil{}, children}]} : Doc.Node},
    conversation_dock_identity: @+task:Nat -> @generation:Nat -> @key:String -> @tag:String ->
      @attrs:+List<Doc.Property> -> @styles:+List<Doc.Property> -> @events:+List<Doc.Event> -> @children:+List<Doc.Node> ->
      {Render.reading_element("dock", key, tag, attrs, styles, events, children, Some{Conversation.Identity{task, generation}}) ==
        Doc.Element{key, tag, List.append(&2, Doc.Property, attrs, [Doc.Property{"data-reading-dock", ""}, Doc.Property{"data-reading-task", Nat.show(task)}]), styles, events, children} : Doc.Node},
    conversation_children_identity: @+children:+List<Doc.Node> -> @+heading:Design.Box -> @+viewport:Design.Box ->
      @+reading:Design.Band -> @+dock:Maybe<&2, Design.Dock> -> @+identity:Maybe<&2, Conversation.Identity> ->
      {Render.place_children(Render.prepare_conversation(children, identity), False{}, Design.ConversationFrame{heading, viewport, reading, dock}) ==
        expected_conversation(children, heading, viewport, reading, dock, identity) : +List<Doc.Node>},
    page_context_root_identity: @+parameters:Design.LayoutParameters -> @+key:String -> @+semantic:String -> @+label:String -> @+role:Interface.Role ->
      @+identity:Maybe<&2, Conversation.Identity> -> @+visual:Design.Style -> @+representation:Controls.Representation ->
      @+source:+List<Design.Node> -> @shell:Design.Shell -> @main:Design.MainFrame -> @controls:+List<Design.NodePlacement> ->
      {Render.place_base_node(Design.Node{key, semantic, label, role, Interface.PageContext{identity}, visual, representation, source},
        Render.prepare_base_node(Design.Node{key, semantic, label, role, Interface.PageContext{identity}, visual, representation, source}, Design.frame_structure(main)),
        Design.Layout{Design.Viewport{0n, 0n}, shell, main, Nil{}, parameters, controls}) ==
        Render.apply_placements(Render.place_base_shell_node(role,
          Render.place_tree(Render.prepare_tree(Render.render_node(Design.Node{key, semantic, label, role, Interface.PageContext{identity}, visual, representation, source}), Design.frame_structure(main), identity), main), shell), controls) : Doc.Node},
    background_without_modal: {Render.background_properties(None{}) == Nil{} : +List<Doc.Property>},
    background_with_modal: @current:String ->
      {Render.background_properties(Some{current}) ==
        [Doc.Property{"inert", "true"}, Doc.Property{"aria-hidden", "true"}] : +List<Doc.Property>},
    overlay_without_modal: @key:String ->
      {Render.modal_properties(None{}, key) == Nil{} : +List<Doc.Property>},
    overlay_with_modal: @+current:String -> @+key:String ->
      {Render.modal_properties(Some{current}, key) ==
        Render.modal_active_properties(String.eq(current, key)) : +List<Doc.Property>},
    active_overlay_properties: {Render.modal_active_properties(True{}) ==
      [Doc.Property{"role", "dialog"}, Doc.Property{"aria-modal", "true"}] : +List<Doc.Property>},
    inactive_overlay_properties: {Render.modal_active_properties(False{}) ==
      [Doc.Property{"inert", "true"}, Doc.Property{"aria-hidden", "true"}] : +List<Doc.Property>},
    bounds_refinement: @box:Design.Box ->
      {css_box(Render.bounds(box)) == specified_box(box) : (String & (String & (String & String)))},
    region_bounds: @+key:String -> @+region:String -> @+box:Design.Box -> @+children:+List<Doc.Node> ->
      {observed_box(Render.replace_styles(Doc.Element{key, "div", [Doc.Property{"data-region", region}], Nil{}, Nil{}, children}, Render.bounds(box))) == specified_box(box) : (String & (String & (String & String)))},
    action_event: @+key:String -> @+style:Design.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback ->
      {Doc.element_events(Render.action(key, style,
          Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})) ==
          [Doc.Activate{key}] : +List<Doc.Event>},
    action_accessible_name: @+key:String -> @+style:Design.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback ->
      {Render.attr(Doc.element_attributes(Render.action(key, style,
          Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "aria-label") == name : String},
    textarea_event: @+key:String ->
      {Render.input_events(key, Controls.MessageInput{}) == [Doc.EditText{key}] : +List<Doc.Event>},
    toggle_event: @+key:String ->
      {Render.input_events(key, Controls.ToggleInput{}) == [Doc.EditToggle{key}] : +List<Doc.Event>},
    file_event: @+key:String -> @+face:Controls.Face ->
      {Render.input_events(key, Controls.FileChooser{face}) == [Doc.SelectFiles{key}] : +List<Doc.Event>},
    creation_canvas: @+children:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band -> @+input:Maybe<&2, Design.InputMetrics> -> @+flow:Design.CreationFlow ->
      {observed_box(first_node(Render.place_children(Render.prepare_main_children(children, Design.CreationStructure{}, None{}), False{}, Design.CreationFrame{heading, canvas, band, input, flow}))) ==
          specified_box(canvas) : (String & (String & (String & String)))},
    unavailable_canvas: @+children:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band ->
      {observed_box(first_node(Render.place_children(Render.prepare_main_children(children, Design.UnavailableStructure{}, None{}), False{}, Design.UnavailableFrame{heading, canvas, band}))) ==
          specified_box(canvas) : (String & (String & (String & String)))},
    rendered_region_count: @+values:+List<Design.Node> ->
      {List.length(&2, Doc.Node, Render.render_nodes(values)) ==
          List.length(&2, Design.Node, values) : Nat},
    render_children_preserves_sources: @+values:+List<Design.Node> ->
      {Render.sources(Render.render_children(values)) == values : +List<Design.Node>},
    creation_regions_keep_order: @+children:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {ShellSpatial.creation_region_children(Render.prepare_creation_regions(Render.creation_partition(children))) == children : +List<Doc.Node>},
    creation_canvas_retains_regions: @+canvas:Design.Box -> @+band:Design.Band -> @+flow:Design.CreationFlow -> @+children:+List<Doc.Node> ->
      {Doc.element_children(first_node(Render.prepare_creation(children))) == [Doc.Element{"creation-group", "div", [Doc.Property{"data-region", "creation-group"}], List.append(&2, Doc.Property, Render.intrinsic_creation_band(), [Doc.Property{"flex", "0 0 auto"}]), Nil{}, Render.prepare_creation_regions(Render.creation_partition(children))}] : +List<Doc.Node>},
    creation_composer_flows: @heading:Design.Box -> @canvas:Design.Box -> @band:Design.Band -> @input:Maybe<&2, Design.InputMetrics> -> @flow:Design.CreationFlow ->
      {Render.attr(Render.composer_styles(Design.CreationFrame{heading, canvas, band, input, flow}), "position") == "" : String},
    composer_actions_keep_order: @+key:String -> @+children:+List<Doc.Node> ->
      {List.append(&2, Doc.Node,
          Doc.element_children(first_node(Render.composer_action_groups(key, children))),
          Doc.element_children(second_node(Render.composer_action_groups(key, children)))) == children : +List<Doc.Node>},
    light_document_theme: {Render.document_theme(Design.Light{}) == Doc.TargetProperties{"document-theme", "@document/root",
      [Doc.Property{"data-theme", "light"}], [Doc.Property{"color-scheme", "light"}]} : Doc.Node},
    dark_document_theme: {Render.document_theme(Design.Dark{}) == Doc.TargetProperties{"document-theme", "@document/root",
      [Doc.Property{"data-theme", "dark"}], [Doc.Property{"color-scheme", "dark"}]} : Doc.Node},
    root_theme_attribute: @+theme:Design.Theme -> {Render.attr(target_attributes(Render.document_theme(theme)), "data-theme") == Render.theme_name(theme) : String},
    root_theme_color_scheme: @+theme:Design.Theme -> {Render.attr(target_styles(Render.document_theme(theme)), "color-scheme") == Render.theme_name(theme) : String},
    compound_field_preserves_children: @+key:String -> @label:String -> @field:Forms.Field -> @visual:Design.Style -> @+children:+List<Doc.Node> ->
      {Doc.element_children(Render.compound_field(key, label, field, visual, children)) == children : +List<Doc.Node>},
    compound_field_has_no_events: @key:String -> @label:String -> @field:Forms.Field -> @visual:Design.Style -> @children:+List<Doc.Node> ->
      {Doc.element_events(Render.compound_field(key, label, field, visual, children)) == Nil{} : +List<Doc.Event>},
    compound_field_is_not_tab_stop: @key:String -> @label:String -> @field:Forms.Field -> @visual:Design.Style -> @children:+List<Doc.Node> ->
      {Render.attr(Doc.element_attributes(Render.compound_field(key, label, field, visual, children)), "tabindex") == "-1" : String},
    directory_field_uses_compound: @+key:String -> @+semantic:String -> @+label:String -> @role:Interface.Role -> @owner:User.Editor -> @+field:Forms.Field ->
      @value:Forms.Observed -> @choices:+List<Forms.ChoiceValue> -> @source:+List<Design.Node> -> @+visual:Design.Style -> @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.Edit{owner, field, Forms.DirectoryCollection{}, value, choices}, visual, representation, source}, Render.render_children(source)) == Render.compound_field(key, label, field, visual, Render.render_nodes(source)) : Doc.Node},
    file_field_uses_compound: @+key:String -> @+semantic:String -> @+label:String -> @role:Interface.Role -> @owner:User.Editor -> @+field:Forms.Field ->
      @value:Forms.Observed -> @choices:+List<Forms.ChoiceValue> -> @source:+List<Design.Node> -> @+visual:Design.Style -> @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.Edit{owner, field, Forms.FileCollection{}, value, choices}, visual, representation, source}, Render.render_children(source)) == Render.compound_field(key, label, field, visual, Render.render_nodes(source)) : Doc.Node},
    board_group_properties: @+typography:T.Presentation -> @+key:String -> @+grouping:Interface.BoardGrouping -> @+children:+List<Doc.Node> ->
      {(Render.attr(Doc.element_attributes(Render.board_group_node(key, grouping, children, typography)), "data-native-key"),
          (Render.attr(Doc.element_attributes(Render.board_group_node(key, grouping, children, typography)), "data-board-group"),
           (Render.attr(Doc.element_attributes(Render.board_group_node(key, grouping, children, typography)), "role"),
            Render.attr(Doc.element_attributes(Render.board_group_node(key, grouping, children, typography)), "aria-label")))) ==
          (key, (Render.board_group_name(grouping), ("group", Render.board_group_label(grouping)))) :
          (String & (String & (String & String)))},
    board_group_dispatch: @+key:String -> @+semantic:String -> @+label:String -> @role:Interface.Role -> @+grouping:Interface.BoardGrouping ->
      @source:+List<Design.Node> -> @+visual:Design.Style -> @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.BoardGroup{grouping}, visual, representation, source}, Render.render_children(source)) ==
        Render.board_group_node(key, grouping, Render.render_nodes(source), Design.style_text(visual)) : Doc.Node},
    board_lane_dispatch: @+key:String -> @+semantic:String -> @+label:String -> @role:Interface.Role -> @+stage:Board.Stage -> @+count:Nat ->
      @source:+List<Design.Node> -> @+visual:Design.Style -> @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.BoardLane{stage, count}, visual, representation, source}, Render.render_children(source)) ==
        Render.board_lane_node(key, label, stage, count, Render.render_children(source), Design.style_text(visual)) : Doc.Node},
    board_lane_projection: @+typography:T.Presentation -> @+key:String -> @+label:String -> @+stage:Board.Stage -> @+count:Nat -> @source:+List<Render.Child> ->
      {(Render.attr(Doc.element_attributes(Render.board_lane_node(key, label, stage, count, source, typography)), "data-native-key"),
          (Render.attr(Doc.element_attributes(Render.board_lane_node(key, label, stage, count, source, typography)), "data-board-stage"),
           (Render.attr(Doc.element_attributes(Render.board_lane_node(key, label, stage, count, source, typography)), "data-board-count"),
            Render.attr(Doc.element_attributes(Render.board_lane_node(key, label, stage, count, source, typography)), "aria-label")))) ==
          (key, (Board.stage_name(stage), (Nat.show(count), label))) : (String & (String & (String & String)))},
    board_lane_count_projection: @+typography:T.Presentation -> @+owner:String -> @+count:Nat ->
      {(Render.attr(Doc.element_attributes(Render.lane_count(owner, count, typography)), "data-board-count"), direct_text(Render.lane_count(owner, count, typography))) ==
        (Nat.show(count), Nat.show(count)) : (String & String)},
    board_lane_empty_projection: @+typography:T.Presentation -> @+owner:String ->
      {(direct_texts(Render.empty_lane(0n, owner, typography)),
          (List.length(&2, Doc.Node, Render.empty_lane(0n, owner, typography)),
           List.length(&2, Doc.Node, Render.empty_lane(1n, owner, typography)))) == ("暂无任务", (1n, 0n)) : (String & (Nat & Nat))},
    board_lane_scroll_ownership: @+stage:Board.Stage ->
      {(Render.attr(Render.board_lane_styles(stage), "min-height"), Render.attr(Render.board_lane_styles(stage), "overflow")) ==
        ("0", "hidden") : (String & String)},
    board_column_sizing: @+key:String -> @+width:Nat ->
      {board_column_style_projection(key, width) == (Render.px(width), ("0 0 auto", "100%")) : (String & (String & String))},
    board_stage_scroll_ownership: @+key:String -> @+width:Nat -> @+gap:Nat -> @+inset:Nat ->
      {(Render.attr(Doc.element_styles(Render.board_stage_region(
            Doc.Element{key, "div", Nil{}, Nil{}, Nil{}, Nil{}}, width, gap, inset)), "flex"),
          (Render.attr(Doc.element_styles(Render.board_stage_region(
             Doc.Element{key, "div", Nil{}, Nil{}, Nil{}, Nil{}}, width, gap, inset)), "overflow-x"),
           Render.attr(Doc.element_styles(Render.board_stage_region(
             Doc.Element{key, "div", Nil{}, Nil{}, Nil{}, Nil{}}, width, gap, inset)), "overflow-y"))) ==
          ("1", ("auto", "hidden")) : (String & (String & String))},
    card_root_face_projection: @+key:String -> @+face:View.CardFace -> @destinations:+List<Interface.Placement> -> @source:+List<Render.Child> ->
      @+visual:Design.Style ->
      card_root_face_projection_law(key, face, destinations, source, visual),
    card_root_excludes_tab_target: @+typography:T.Presentation -> @+key:String -> @+face:View.CardFace -> @destinations:+List<Interface.Placement> -> @source:+List<Render.Child> ->
      @+visual:Design.Style ->
      {Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual, typography)), "tabindex") == "" : String},
    card_metadata_projection: @+typography:T.Presentation -> @+owner:String -> @+face:View.CardFace ->
      {direct_text_slots(Doc.element_children(Render.card_metadata(owner, face, String.is_empty(card_face_status(face)), typography))) ==
        card_metadata_expected(face, String.is_empty(card_face_status(face))) : +List<String>},
    card_description_projection: @+typography:T.Presentation -> @+owner:String -> @+description:String ->
      {direct_text_slots(Render.card_description(owner, description, typography)) == optional_text_slots(description) : +List<String>},
    card_context_projection: @+typography:T.Presentation -> @+owner:String -> @+project:String -> @+labels:+List<String> ->
      {direct_text_slots(Doc.element_children(first_node(Render.card_context_nodes(owner, project, labels, typography)))) ==
        List.append(&2, String, optional_text_slots(project), labels) : +List<String>},
    card_footer_projection: @+typography:T.Presentation -> @+owner:String -> @+face:View.CardFace ->
      {direct_text_slots(Doc.element_children(first_node(Render.card_footer(owner, face, typography)))) == card_footer_expected(face) : +List<String>},
    movable_card_dispatch: @+key:String -> @+semantic:String -> @+label:String -> @role:Interface.Role -> @destinations:+List<Interface.Placement> -> @+face:View.CardFace ->
      @source:+List<Design.Node> -> @+visual:Design.Style -> @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.MovableCard{destinations, face}, visual, representation, source}, Render.render_children(source)) ==
        Render.card_node(key, face, destinations, Render.render_children(source), visual, Design.style_text(visual)) : Doc.Node},
    movable_card_events: @+typography:T.Presentation -> @+key:String -> @+face:View.CardFace -> @destinations:+List<Interface.Placement> -> @source:+List<Render.Child> ->
      @+visual:Design.Style ->
      {Doc.element_events(Render.card_node(key, face, destinations, source, visual, typography)) == [Doc.DragCard{key}, Doc.DropCard{key}] : +List<Doc.Event>},
    dialog_branch_header_partition: @+key:String -> @+semantic:String -> @+label:String -> @source:+List<Design.Node> ->
      @+visual:Design.Style ->
      {rest_nodes(Doc.element_children(dialog_header_node(rendered_dialog(key, semantic, label, source, visual)))) ==
        expected_dialog_header(Render.render_children(source)) : +List<Doc.Node>},
    dialog_branch_body_partition: @+key:String -> @+semantic:String -> @+label:String -> @source:+List<Design.Node> ->
      @+visual:Design.Style ->
      {DialogSpatial.original_children(rendered_dialog(key, semantic, label, source, visual)) ==
        expected_dialog_body(Render.render_children(source)) : +List<Doc.Node>},
    dialog_branch_wrapper_keys: @+key:String -> @+semantic:String -> @+label:String -> @source:+List<Design.Node> ->
      @+visual:Design.Style ->
      {(node_key(dialog_header_node(rendered_dialog(key, semantic, label, source, visual))),
        (node_key(dialog_body_node(rendered_dialog(key, semantic, label, source, visual))),
         node_key(dialog_content_node(rendered_dialog(key, semantic, label, source, visual))))) ==
       (Render.generated_identity(key, "dialog-header"),
        (Render.generated_identity(key, "dialog-body"), Render.generated_identity(key, "dialog-content"))) :
       (String & (String & String))},
    dialog_branch_outer_identity: @+key:String -> @+semantic:String -> @+label:String -> @source:+List<Design.Node> ->
      @+visual:Design.Style ->
      {(node_key(rendered_dialog(key, semantic, label, source, visual)),
        (Render.attr(Doc.element_attributes(rendered_dialog(key, semantic, label, source, visual)), "aria-label"),
         Render.attr(Doc.element_attributes(rendered_dialog(key, semantic, label, source, visual)), "data-native-key"))) ==
       (key, (label, key)) : (String & (String & String))},
    dialog_branch_title_identity: @+key:String -> @+semantic:String -> @+label:String -> @source:+List<Design.Node> ->
      @+visual:Design.Style ->
      {(node_key(dialog_title_node(rendered_dialog(key, semantic, label, source, visual))),
        direct_text(dialog_title_node(rendered_dialog(key, semantic, label, source, visual)))) ==
       (Render.generated_identity(key, "title"), label) : (String & String)},
    dialog_flow_properties: @+key:String -> @+semantic:String -> @+label:String -> @source:+List<Design.Node> ->
      @+visual:Design.Style ->
      {(Render.attr(Doc.element_styles(dialog_header_node(rendered_dialog(key, semantic, label, source, visual))), "flex"),
        (Render.attr(Doc.element_styles(dialog_body_node(rendered_dialog(key, semantic, label, source, visual))), "flex"),
         (Render.attr(Doc.element_styles(dialog_body_node(rendered_dialog(key, semantic, label, source, visual))), "min-height"),
          (Render.attr(Doc.element_styles(dialog_body_node(rendered_dialog(key, semantic, label, source, visual))), "overflow"),
           (Render.attr(Doc.element_styles(dialog_content_node(rendered_dialog(key, semantic, label, source, visual))), "flex"),
            (Render.attr(Doc.element_styles(dialog_content_node(rendered_dialog(key, semantic, label, source, visual))), "height"),
             Render.attr(Doc.element_styles(dialog_content_node(rendered_dialog(key, semantic, label, source, visual))), "max-height"))))))) ==
       ("0 0 auto", ("1 1 auto", ("0", ("auto", ("0 0 auto", ("", "")))))) :
       (String & (String & (String & (String & (String & (String & String))))))},
    centered_dialog_hides_overflow: @+available:Design.Box -> @maximum_width:Nat ->
      {Render.attr(Render.overlay_styles(Design.CenteredDialog{available, maximum_width}), "overflow") == "hidden" : String},
    anchored_popover_keeps_scroll: @+anchor:String -> @+available:Design.Box ->
      @maximum_width:Nat -> @maximum_height:Nat -> @gap:Nat ->
      {Render.attr(Render.overlay_styles(Design.AnchoredPopover{anchor, available, maximum_width, maximum_height, gap}), "overflow") == "auto" : String},
    anchored_popover_placement_styles: @+anchor:String -> @+available:Design.Box ->
      @+maximum_width:Nat -> @+maximum_height:Nat -> @+gap:Nat ->
      {Render.overlay_styles(Design.AnchoredPopover{anchor, available, maximum_width, maximum_height, gap}) ==
        expected_popover_styles(anchor, available, maximum_width, maximum_height, gap) : +List<Doc.Property>},
    anchored_popover_normal_alignment: @+anchor:String -> @+available:Design.Box ->
      @maximum_width:Nat -> @maximum_height:Nat -> @gap:Nat ->
      {Render.attr(Render.overlay_styles(Design.AnchoredPopover{anchor, available, maximum_width, maximum_height, gap}), "align-self") == "normal" : String},
    anchored_popover_content_height: @+anchor:String -> @+available:Design.Box ->
      @maximum_width:Nat -> @maximum_height:Nat -> @gap:Nat ->
      {Render.attr(Render.overlay_styles(Design.AnchoredPopover{anchor, available, maximum_width, maximum_height, gap}), "height") == "max-content" : String},
    board_search_placeholder: @+filter:Board.Filter ->
      {Render.attr(Render.field_hint(Interface.BoardSearch{filter}), "placeholder") == "搜索任务" : String}
  }

law evidence:
  Requirements
