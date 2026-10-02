import ../core/interface.bend as Interface
import ./appearance.bend as Appearance
import Base
import ../bendlib/stdlib.bend as Std
import ./document.bend as Doc
import ./renderer.bend as Render
import ./dialog-spatial-laws.bend as DialogSpatial
import ./editor-layout.bend as EditorLayout
import ./shell-spatial-laws.bend as ShellSpatial
import ./design.bend as Design
import ./controls.bend as Controls
import ../core/SYSTEM.bend as Core
import ../core/ui-world.bend as View
import ../core/form-fields.bend as Forms
import ../core/user-input.bend as User
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

def bounds_refinement(box: Design.Box) ->
  {css_box(Render.bounds(box)) == specified_box(box) : (String & (String & (String & String)))}:
  Design.Box{left, top, width, height} = box
  {==}

def region_bounds(+key: String, +region: String, +box: Design.Box, +children: +List<Doc.Node>) ->
  {observed_box(Render.frame_region(key, region, box, children)) == specified_box(box) : (String & (String & (String & String)))}:
  match box:
    case Design.Box{left, top, width, height}: {==}

def node_events(node: Doc.Node) -> +List<Doc.Event>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: events
    case _: Nil{}

def node_attributes(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: attrs
    case _: Nil{}

def node_styles(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: styles
    case _: Nil{}

def action_event(+key: String, +style: Design.Style, +input: Core.Input,
  +availability: View.Availability, +name: String, +face: Controls.Face,
  +behavior: Controls.Behavior, +geometry: Controls.Geometry, +placement: Controls.Placement,
  +help: Controls.Help, +feedback: Controls.Feedback) ->
  {node_events(Render.action(key, Design.Appearance{key, style, Controls.NoControl{}, Nil{}},
    Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})) ==
    [Doc.Activate{key}] : +List<Doc.Event>}:
  {==}

def action_accessible_name(+key: String, +style: Design.Style, +input: Core.Input,
  +availability: View.Availability, +name: String, +face: Controls.Face,
  +behavior: Controls.Behavior, +geometry: Controls.Geometry, +placement: Controls.Placement,
  +help: Controls.Help, +feedback: Controls.Feedback) ->
  {Render.attr(node_attributes(Render.action(key, Design.Appearance{key, style, Controls.NoControl{}, Nil{}},
    Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "aria-label") == name : String}:
  {==}

def textarea_event(+key: String) ->
  {Render.input_events(key, Controls.MessageInput{}) == [Doc.EditText{key}] : +List<Doc.Event>}:
  {==}

def toggle_event(+key: String) ->
  {Render.input_events(key, Controls.ToggleInput{}) == [Doc.EditToggle{key}] : +List<Doc.Event>}:
  {==}

def file_event(+key: String, +face: Controls.Face) ->
  {Render.input_events(key, Controls.FileChooser{face}) == [Doc.SelectFiles{key}] : +List<Doc.Event>}:
  {==}

def first_node(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Nil{}: Doc.Text{""}
    case Con{value, rest}: value

def second_node(values: +List<Doc.Node>) -> Doc.Node:
  match values:
    case Con{value, rest}: first_node(rest)
    case Nil{}: Doc.Text{""}

def creation_canvas(+children: +List<Doc.Node>, +heading: Design.Box, +canvas: Design.Box,
  +band: Design.Band, +input: Maybe<&2, Design.InputMetrics>, +flow: Design.CreationFlow) ->
  {observed_box(first_node(Render.main_children(children, Design.CreationFrame{heading, canvas, band, input, flow}))) ==
    specified_box(canvas) : (String & (String & (String & String)))}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

def unavailable_canvas(+children: +List<Doc.Node>, +heading: Design.Box, +canvas: Design.Box, +band: Design.Band) ->
  {observed_box(first_node(Render.main_children(children, Design.UnavailableFrame{heading, canvas, band}))) ==
    specified_box(canvas) : (String & (String & (String & String)))}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

# The appearance traversal is the production traversal, so this statement rules
# out silently truncating a surface merely because the renderer zips two lists.

def rendered_region_count(+values: +List<Interface.Node>, +context: Controls.Context) ->
  {List.length(&2, Doc.Node, Render.render_nodes(values, Appearance.nodes_at(values, context))) ==
    List.length(&2, Interface.Node, values) : Nat}:
  match values:
    case Nil{}: {==}
    case Con{Interface.Node{key, semantic, label, role, meaning, children}, rest}:
      Equal.cong(Nat, Nat, (count => (1n + count : Nat)),
        List.length(&2, Doc.Node, Render.render_nodes(rest, Appearance.nodes_at(rest, context))),
        List.length(&2, Interface.Node, rest), rendered_region_count(rest, context))


# This instance contains the checked production theorems, with their original
# quantifiers and conclusions retained verbatim.
def background_without_modal() ->
  {Render.background_properties(None{}) == Nil{} : +List<Doc.Property>}:
  {==}

def background_with_modal(current: String) ->
  {Render.background_properties(Some{current}) ==
    [Doc.Property{"inert", "true"}, Doc.Property{"aria-hidden", "true"}] : +List<Doc.Property>}:
  {==}

def overlay_without_modal(key: String) ->
  {Render.modal_properties(None{}, key) == Nil{} : +List<Doc.Property>}:
  {==}

def overlay_with_modal(+current: String, +key: String) ->
  {Render.modal_properties(Some{current}, key) ==
    Render.modal_active_properties(String.eq(current, key)) : +List<Doc.Property>}:
  {==}

def active_overlay_properties() ->
  {Render.modal_active_properties(True{}) ==
    [Doc.Property{"role", "dialog"}, Doc.Property{"aria-modal", "true"}] : +List<Doc.Property>}:
  {==}

def inactive_overlay_properties() ->
  {Render.modal_active_properties(False{}) ==
    [Doc.Property{"inert", "true"}, Doc.Property{"aria-hidden", "true"}] : +List<Doc.Property>}:
  {==}

def node_children(node: Doc.Node) -> +List<Doc.Node>:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: children
    case _: Nil{}

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

def creation_regions_keep_order(+children: +List<Doc.Node>, +band: Design.Band, +flow: Design.CreationFlow) ->
  {ShellSpatial.creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(children))) == children : +List<Doc.Node>}:
  ShellSpatial.creation_regions_keep_order(children, band, flow)

def creation_canvas_retains_regions(+canvas: Design.Box, +band: Design.Band, +flow: Design.CreationFlow, +children: +List<Doc.Node>) ->
  {node_children(first_node(Render.creation_canvas_nodes(canvas, band, flow, children))) ==
    [Render.creation_group(band, flow, children)] : +List<Doc.Node>}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

def root_theme_light() -> {Render.theme_name(Design.Light{}) == "light" : String}:
  {==}

def root_theme_dark() -> {Render.theme_name(Design.Dark{}) == "dark" : String}:
  {==}

def creation_composer_flows(heading: Design.Box, canvas: Design.Box, band: Design.Band,
  input: Maybe<&2, Design.InputMetrics>, flow: Design.CreationFlow) ->
  {Render.attr(Render.composer_styles(Design.CreationFrame{heading, canvas, band, input, flow}), "position") == "" : String}:
  {==}

def action_partition_order(+children: +List<Doc.Node>) ->
  {List.append(&2, Doc.Node, Render.action_leading(children), Render.action_trailing(children)) == children : +List<Doc.Node>}:
  match children:
    case Nil{}: {==}
    case Con{last, Nil{}}: {==}
    case Con{+first, Con{+second, +rest}}:
      Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => first <> tail),
        List.append(&2, Doc.Node, Render.action_leading(second <> rest), Render.action_trailing(second <> rest)), second <> rest,
        action_partition_order(second <> rest))

def composer_actions_keep_order(+key: String, +children: +List<Doc.Node>) ->
  {List.append(&2, Doc.Node,
    node_children(first_node(Render.composer_action_groups(key, children))),
    node_children(second_node(Render.composer_action_groups(key, children)))) == children : +List<Doc.Node>}:
  action_partition_order(children)

def target_attributes(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.TargetProperties{key, target, attributes, styles}: attributes
    case _: Nil{}

def target_styles(node: Doc.Node) -> +List<Doc.Property>:
  match node:
    case Doc.TargetProperties{key, target, attributes, styles}: styles
    case _: Nil{}

def light_document_theme() ->
  {Render.document_theme(Design.Light{}) == Doc.TargetProperties{"document-theme", "@document/root",
    [Doc.Property{"data-theme", "light"}], [Doc.Property{"color-scheme", "light"}]} : Doc.Node}:
  {==}

def dark_document_theme() ->
  {Render.document_theme(Design.Dark{}) == Doc.TargetProperties{"document-theme", "@document/root",
    [Doc.Property{"data-theme", "dark"}], [Doc.Property{"color-scheme", "dark"}]} : Doc.Node}:
  {==}

def root_theme_attribute(+theme: Design.Theme) ->
  {Render.attr(target_attributes(Render.document_theme(theme)), "data-theme") == Render.theme_name(theme) : String}:
  {==}

def root_theme_color_scheme(+theme: Design.Theme) ->
  {Render.attr(target_styles(Render.document_theme(theme)), "color-scheme") == Render.theme_name(theme) : String}:
  {==}

def compound_field_preserves_children(+key: String, label: String, field: Forms.Field,
  visual: Design.Style, +children: +List<Doc.Node>) ->
  {node_children(Render.compound_field(key, label, field, visual, children)) == children : +List<Doc.Node>}:
  {==}

def compound_field_has_no_events(key: String, label: String, field: Forms.Field,
  visual: Design.Style, children: +List<Doc.Node>) ->
  {node_events(Render.compound_field(key, label, field, visual, children)) == Nil{} : +List<Doc.Event>}:
  {==}

def compound_field_is_not_tab_stop(key: String, label: String, field: Forms.Field,
  visual: Design.Style, children: +List<Doc.Node>) ->
  {Render.attr(node_attributes(Render.compound_field(key, label, field, visual, children)), "tabindex") == "-1" : String}:
  {==}

def directory_field_uses_compound(+key: String, +label: String, role: Interface.Role,
  owner: User.Editor, +field: Forms.Field, value: Forms.Observed, source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, representation: Controls.Representation,
  appearance: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, Interface.Edit{owner, field, Forms.DirectoryCollection{}, value}, source, children, visual, representation, appearance) ==
    Render.compound_field(key, label, field, visual, children) : Doc.Node}:
  {==}

def file_field_uses_compound(+key: String, +label: String, role: Interface.Role,
  owner: User.Editor, +field: Forms.Field, value: Forms.Observed, source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, representation: Controls.Representation,
  appearance: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, Interface.Edit{owner, field, Forms.FileCollection{}, value}, source, children, visual, representation, appearance) ==
    Render.compound_field(key, label, field, visual, children) : Doc.Node}:
  {==}

# These laws observe the document tree produced by the production renderer.
# They constrain emitted content and ownership attributes, not browser layout.
def board_group_properties(+key: String, +grouping: Interface.BoardGrouping, +children: +List<Doc.Node>) ->
  {(Render.attr(node_attributes(Render.board_group_node(key, grouping, children)), "data-native-key"),
    (Render.attr(node_attributes(Render.board_group_node(key, grouping, children)), "data-board-group"),
     (Render.attr(node_attributes(Render.board_group_node(key, grouping, children)), "role"),
      Render.attr(node_attributes(Render.board_group_node(key, grouping, children)), "aria-label")))) ==
    (key, (Render.board_group_name(grouping), ("group", Render.board_group_label(grouping)))) :
    (String & (String & (String & String)))}:
  {==}

def board_group_dispatch(+key: String, +label: String, role: Interface.Role,
  +grouping: Interface.BoardGrouping, source: +List<Interface.Node>, +children: +List<Doc.Node>,
  +visual: Design.Style, representation: Controls.Representation,
  appearances: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, Interface.BoardGroup{grouping}, source, children, visual,
    representation, appearances) == Render.board_group_node(key, grouping, children) : Doc.Node}:
  {==}

def board_lane_dispatch(+key: String, +label: String, role: Interface.Role,
  +stage: Board.Stage, +count: Nat, source: +List<Interface.Node>, +children: +List<Doc.Node>,
  +visual: Design.Style, representation: Controls.Representation,
  appearances: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, Interface.BoardLane{stage, count}, source, children, visual,
    representation, appearances) == Render.board_lane_node(key, label, stage, count, source, children) : Doc.Node}:
  {==}

def board_lane_projection(+key: String, +label: String, +stage: Board.Stage, +count: Nat,
  source: +List<Interface.Node>, +children: +List<Doc.Node>) ->
  {(Render.attr(node_attributes(Render.board_lane_node(key, label, stage, count, source, children)), "data-native-key"),
    (Render.attr(node_attributes(Render.board_lane_node(key, label, stage, count, source, children)), "data-board-stage"),
     (Render.attr(node_attributes(Render.board_lane_node(key, label, stage, count, source, children)), "data-board-count"),
      Render.attr(node_attributes(Render.board_lane_node(key, label, stage, count, source, children)), "aria-label")))) ==
    (key, (Board.stage_name(stage), (Nat.show(count), label))) : (String & (String & (String & String)))}:
  {==}

def board_lane_count_projection(+owner: String, +count: Nat) ->
  {(Render.attr(node_attributes(Render.lane_count(owner, count)), "data-board-count"),
    direct_text(Render.lane_count(owner, count))) == (Nat.show(count), Nat.show(count)) : (String & String)}:
  {==}

def board_lane_empty_projection(+owner: String) ->
  {(direct_texts(Render.empty_lane(0n, owner)),
    (List.length(&2, Doc.Node, Render.empty_lane(0n, owner)),
     List.length(&2, Doc.Node, Render.empty_lane(1n, owner)))) == ("暂无任务", (1n, 0n)) : (String & (Nat & Nat))}:
  {==}

def board_lane_scroll_ownership(+stage: Board.Stage) ->
  {(Render.attr(Render.board_lane_styles(stage), "min-height"),
    Render.attr(Render.board_lane_styles(stage), "overflow")) == ("0", "hidden") : (String & String)}:
  {==}

def board_column_style_projection(+key: String, +width: Nat) -> (String & (String & String)):
  +column = first_node(Render.board_columns([Doc.Element{key, "section", Nil{}, Nil{}, Nil{}, Nil{}}], width))
  +styles = node_styles(column)
  (Render.attr(styles, "width"), (Render.attr(styles, "flex"), Render.attr(styles, "height")))

def board_column_sizing(+key: String, +width: Nat) ->
  {board_column_style_projection(key, width) == (Render.px(width), ("0 0 auto", "100%")) : (String & (String & String))}:
  {==}

def board_stage_scroll_ownership(+key: String, +width: Nat, +gap: Nat, +inset: Nat) ->
  {(Render.attr(node_styles(Render.board_stage_region(
      Doc.Element{key, "div", Nil{}, Nil{}, Nil{}, Nil{}}, width, gap, inset)), "flex"),
    (Render.attr(node_styles(Render.board_stage_region(
       Doc.Element{key, "div", Nil{}, Nil{}, Nil{}, Nil{}}, width, gap, inset)), "overflow-x"),
     Render.attr(node_styles(Render.board_stage_region(
       Doc.Element{key, "div", Nil{}, Nil{}, Nil{}, Nil{}}, width, gap, inset)), "overflow-y"))) ==
    ("1", ("auto", "hidden")) : (String & (String & String))}:
  {==}

def card_root_face_expected(+key: String, +face: View.CardFace) -> (String & (String & (String & String))):
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  (key, (Nat.show(id), (title, title)))

def card_root_face_projection(+key: String, +face: View.CardFace, destinations: +List<Interface.Placement>,
  source: +List<Interface.Node>, +children: +List<Doc.Node>, +visual: Design.Style) ->
  {(Render.attr(node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "data-native-key"),
    (Render.attr(node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "data-card-id"),
     (Render.attr(node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "data-card-title"),
     Render.attr(node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "aria-label")))) ==
    card_root_face_expected(key, face) : (String & (String & (String & String)))}:
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  {==}

def card_root_excludes_tab_target(+key: String, +face: View.CardFace, destinations: +List<Interface.Placement>,
  source: +List<Interface.Node>, +children: +List<Doc.Node>, +visual: Design.Style) ->
  {Render.attr(node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "tabindex") == "" : String}:
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  {==}

def card_face_status(+face: View.CardFace) -> String:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  status

def card_chip_text_slots(+key: String, +kind: String, +value: String, +tone: String) ->
  {direct_text_slots([Render.card_chip(key, kind, value, tone)]) == [value] : +List<String>}:
  {==}

def card_metadata_expected(+face: View.CardFace, status_empty: Bool) -> +List<String>:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  List.append(&2, String,
    ["SV-" ++ Nat.show(id), Board.priority_label(priority)],
    List.append(&2, String, optional_pin_slots(pinned), optional_text_slots_when(status_empty, status)))

def card_metadata_projection_when(+owner: String, +id: Nat, +title: String, +description: String,
  +priority: Board.Priority, pinned: Bool, +status: String, +project: String,
  +labels: +List<String>, +card_owner: String, +updated: String, status_empty: Bool) ->
  {direct_text_slots(node_children(Render.card_metadata(owner,
    View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated}, status_empty))) ==
    card_metadata_expected(View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated}, status_empty) : +List<String>}:
  match pinned status_empty:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def card_metadata_projection(+owner: String, +face: View.CardFace) ->
  {direct_text_slots(node_children(Render.card_metadata(owner, face, String.is_empty(card_face_status(face))))) ==
    card_metadata_expected(face, String.is_empty(card_face_status(face))) : +List<String>}:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated} = face
  card_metadata_projection_when(owner, id, title, description, priority, pinned, status, project,
    labels, card_owner, updated, String.is_empty(status))

def card_description_projection_when(empty: Bool, +owner: String, +description: String) ->
  {direct_text_slots(Render.card_description_when(empty, owner, description)) ==
    optional_text_slots_when(empty, description) : +List<String>}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def card_description_projection(+owner: String, +description: String) ->
  {direct_text_slots(Render.card_description(owner, description)) == optional_text_slots(description) : +List<String>}:
  card_description_projection_when(String.is_empty(description), owner, description)

def card_project_slots_when(empty: Bool, +owner: String, +project: String) ->
  {direct_text_slots(Render.card_project_nodes_when(empty, owner, project)) ==
    optional_text_slots_when(empty, project) : +List<String>}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def card_project_slots(+owner: String, +project: String) ->
  {direct_text_slots(Render.card_project_nodes(owner, project)) == optional_text_slots(project) : +List<String>}:
  card_project_slots_when(String.is_empty(project), owner, project)

def card_label_slots(+owner: String, +labels: +List<String>, +index: Nat) ->
  {direct_text_slots(Render.card_label_nodes(owner, labels, index)) == labels : +List<String>}:
  match labels:
    case Nil{}: {==}
    case Con{+value, +rest}:
      +head: +List<Doc.Node> = [Render.card_chip(Render.generated_identity(owner, "label/" ++ Nat.show(index)), "label", value,
        "var(--color-token-text-secondary)")]
      +tail = Render.card_label_nodes(owner, rest, Nat.add(index, 1n))
      +mapped_append = Std.map_app(~Doc.Node, ~String, ~direct_text, head, tail)
      +head_slots = card_chip_text_slots(Render.generated_identity(owner, "label/" ++ Nat.show(index)), "label",
        value, "var(--color-token-text-secondary)")
      +tail_slots = card_label_slots(owner, rest, Nat.add(index, 1n))
      +replace_tail = Equal.cong(+List<String>, +List<String>,
        (slots => List.append(&2, String, direct_text_slots(head), slots)),
        direct_text_slots(tail), rest, tail_slots)
      +replace_head = Equal.cong(+List<String>, +List<String>,
        (slots => List.append(&2, String, slots, rest)),
        direct_text_slots(head), [value], head_slots)
      Equal.trans(+List<String>,
        direct_text_slots(Render.card_label_nodes(owner, labels, index)),
        List.append(&2, String, direct_text_slots(head), direct_text_slots(tail)),
        List.append(&2, String, [value], rest),
        mapped_append, Equal.trans(+List<String>,
          List.append(&2, String, direct_text_slots(head), direct_text_slots(tail)),
          List.append(&2, String, direct_text_slots(head), rest),
          List.append(&2, String, [value], rest),
          replace_tail, replace_head))

def card_context_with_chips_slots(+owner: String, +chips: +List<Doc.Node>) ->
  {direct_text_slots(node_children(first_node(Render.card_context_with_chips(owner, chips)))) ==
    direct_text_slots(chips) : +List<String>}:
  match chips:
    case Nil{}: {==}
    case Con{+first, +rest}: {==}

def card_context_projection(+owner: String, +project: String, +labels: +List<String>) ->
  {direct_text_slots(node_children(first_node(Render.card_context_nodes(owner, project, labels)))) ==
    List.append(&2, String, optional_text_slots(project), labels) : +List<String>}:
  +project_nodes = Render.card_project_nodes(owner, project)
  +label_nodes = Render.card_label_nodes(owner, labels, 0n)
  +chips = List.append(&2, Doc.Node, project_nodes, label_nodes)
  +context_slots = card_context_with_chips_slots(owner, chips)
  +mapped_append = Std.map_app(~Doc.Node, ~String, ~direct_text, project_nodes, label_nodes)
  +project_slots = card_project_slots(owner, project)
  +label_slots = card_label_slots(owner, labels, 0n)
  +replace_project = Equal.cong(+List<String>, +List<String>,
    (slots => List.append(&2, String, slots, direct_text_slots(label_nodes))),
    direct_text_slots(project_nodes), optional_text_slots(project), project_slots)
  +replace_labels = Equal.cong(+List<String>, +List<String>,
    (slots => List.append(&2, String, optional_text_slots(project), slots)),
    direct_text_slots(label_nodes), labels, label_slots)
  +replace_both = Equal.trans(+List<String>,
    List.append(&2, String, direct_text_slots(project_nodes), direct_text_slots(label_nodes)),
    List.append(&2, String, optional_text_slots(project), direct_text_slots(label_nodes)),
    List.append(&2, String, optional_text_slots(project), labels),
    replace_project, replace_labels)
  Equal.trans(+List<String>,
    direct_text_slots(node_children(first_node(Render.card_context_nodes(owner, project, labels)))),
    direct_text_slots(chips),
    List.append(&2, String, optional_text_slots(project), labels),
    context_slots, Equal.trans(+List<String>,
      direct_text_slots(chips),
      List.append(&2, String, direct_text_slots(project_nodes), direct_text_slots(label_nodes)),
      List.append(&2, String, optional_text_slots(project), labels),
      mapped_append, replace_both))

def card_footer_item_slots_when(empty: Bool, +owner: String, +part: String, +kind: String, +value: String) ->
  {direct_text_slots(Render.card_footer_item_when(empty, owner, part, kind, value)) ==
    optional_text_slots_when(empty, value) : +List<String>}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def card_footer_item_slots(+owner: String, +part: String, +kind: String, +value: String) ->
  {direct_text_slots(Render.card_footer_item(owner, part, kind, value)) == optional_text_slots(value) : +List<String>}:
  card_footer_item_slots_when(String.is_empty(value), owner, part, kind, value)

def card_footer_with_items_slots(+owner: String, +items: +List<Doc.Node>) ->
  {direct_text_slots(node_children(first_node(Render.card_footer_with_items(owner, items)))) ==
    direct_text_slots(items) : +List<String>}:
  match items:
    case Nil{}: {==}
    case Con{+first, +rest}: {==}

def card_footer_expected(+face: View.CardFace) -> +List<String>:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  List.append(&2, String, optional_text_slots(owner), optional_text_slots(updated))

def card_timestamp_slots_when(empty: Bool, +owner: String, +value: String) ->
  {direct_text_slots(Render.card_timestamp_items(Render.card_footer_item_when(empty, owner, "updated", "updated", value))) ==
    optional_text_slots_when(empty, value) : +List<String>}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def card_timestamp_slots(+owner: String, +value: String) ->
  {direct_text_slots(Render.card_timestamp_items(Render.card_footer_item(owner, "updated", "updated", value))) ==
    optional_text_slots(value) : +List<String>}:
  card_timestamp_slots_when(String.is_empty(value), owner, value)

def card_footer_projection(+owner: String, +face: View.CardFace) ->
  {direct_text_slots(node_children(first_node(Render.card_footer(owner, face)))) == card_footer_expected(face) : +List<String>}:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated} = face
  +owner_items = Render.card_footer_item(owner, "owner", "owner", card_owner)
  +updated_items = Render.card_timestamp_items(Render.card_footer_item(owner, "updated", "updated", updated))
  +items = List.append(&2, Doc.Node, owner_items, updated_items)
  +footer_slots = card_footer_with_items_slots(owner, items)
  +mapped_append = Std.map_app(~Doc.Node, ~String, ~direct_text, owner_items, updated_items)
  +owner_slots = card_footer_item_slots(owner, "owner", "owner", card_owner)
  +updated_slots = card_timestamp_slots(owner, updated)
  +replace_owner = Equal.cong(+List<String>, +List<String>,
    (slots => List.append(&2, String, slots, direct_text_slots(updated_items))),
    direct_text_slots(owner_items), optional_text_slots(card_owner), owner_slots)
  +replace_updated = Equal.cong(+List<String>, +List<String>,
    (slots => List.append(&2, String, optional_text_slots(card_owner), slots)),
    direct_text_slots(updated_items), optional_text_slots(updated), updated_slots)
  +replace_both = Equal.trans(+List<String>,
    List.append(&2, String, direct_text_slots(owner_items), direct_text_slots(updated_items)),
    List.append(&2, String, optional_text_slots(card_owner), direct_text_slots(updated_items)),
    List.append(&2, String, optional_text_slots(card_owner), optional_text_slots(updated)),
    replace_owner, replace_updated)
  Equal.trans(+List<String>,
    direct_text_slots(node_children(first_node(Render.card_footer(owner, face)))),
    direct_text_slots(items),
    card_footer_expected(face),
    footer_slots, Equal.trans(+List<String>,
      direct_text_slots(items),
      List.append(&2, String, direct_text_slots(owner_items), direct_text_slots(updated_items)),
      card_footer_expected(face),
      mapped_append, replace_both))

def movable_card_dispatch(+key: String, +label: String, role: Interface.Role,
  +destinations: +List<Interface.Placement>, +face: View.CardFace,
  source: +List<Interface.Node>, +children: +List<Doc.Node>, +visual: Design.Style,
  representation: Controls.Representation, appearances: +List<Design.Appearance>) ->
  {Render.match_node(key, label, role, Interface.MovableCard{destinations, face}, source, children,
    visual, representation, appearances) == Render.card_node(key, face, destinations, source, children, visual) : Doc.Node}:
  {==}

def movable_card_events(+key: String, +face: View.CardFace, +destinations: +List<Interface.Placement>,
  source: +List<Interface.Node>, +children: +List<Doc.Node>, +visual: Design.Style) ->
  {node_events(Render.card_node(key, face, destinations, source, children, visual)) ==
    [Doc.DragCard{key}, Doc.DropCard{key}] : +List<Doc.Event>}:
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  {==}

def node_key(node: Doc.Node) -> String:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: key
    case _: ""

def rest_nodes(values: +List<Doc.Node>) -> +List<Doc.Node>:
  match values:
    case Con{first, rest}: rest
    case Nil{}: Nil{}

def rendered_dialog(+key: String, +label: String, +source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, appearances: +List<Design.Appearance>) -> Doc.Node:
  Design.Style{Design.TextStyle{family, size, line_height, weight},
    Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
    direction, overflow, inline, block, gap, minimum, maximum, states} = visual
  Render.match_node(key, label, Interface.Dialog{}, Interface.Region{}, source, children,
    Design.Style{Design.TextStyle{family, size, line_height, weight},
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
      direction, overflow, inline, block, gap, minimum, maximum, states},
    Controls.NoControl{}, appearances)

def dialog_header_node(node: Doc.Node) -> Doc.Node:
  first_node(node_children(node))

def dialog_body_node(node: Doc.Node) -> Doc.Node:
  second_node(node_children(node))

def dialog_content_node(node: Doc.Node) -> Doc.Node:
  first_node(node_children(dialog_body_node(node)))

def dialog_title_node(node: Doc.Node) -> Doc.Node:
  first_node(node_children(dialog_header_node(node)))

def expected_dialog_header_prepend(appearance: Design.Appearance, +child: Doc.Node,
  +rest: +List<Doc.Node>) -> +List<Doc.Node>:
  Design.Appearance{identity, visual, representation, children} = appearance
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, Controls.PanelHeaderEnd{}, help, feedback}: child <> rest
    case _: rest

def expected_dialog_body_prepend(appearance: Design.Appearance, +child: Doc.Node,
  +rest: +List<Doc.Node>) -> +List<Doc.Node>:
  Design.Appearance{identity, visual, representation, children} = appearance
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, Controls.PanelHeaderEnd{}, help, feedback}: rest
    case _: child <> rest

def dialog_partition_header_step(+appearance: Design.Appearance, +child: Doc.Node,
  +parts: Render.DialogParts) ->
  {Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, child, parts)) ==
    expected_dialog_header_prepend(appearance, child, Render.dialog_header_projection(parts)) : +List<Doc.Node>}:
  Design.Appearance{identity, visual, representation, children} = appearance
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      match placement:
        case Controls.InFlow{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
        case Controls.ComposerEnd{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
        case Controls.PanelHeaderEnd{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
        case Controls.CodeToolbar{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
        case Controls.BesideValue{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
        case Controls.GroupHeadingEnd{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
    case Controls.NoControl{}:
      match parts:
        case Render.DialogParts{+header, +body, +layouts}: {==}
    case Controls.Input{binding, name, widget, label, availability}:
      match parts:
        case Render.DialogParts{+header, +body, +layouts}: {==}
    case Controls.Movable{destinations, face, name, handle, geometry, help}:
      match parts:
        case Render.DialogParts{+header, +body, +layouts}: {==}

def dialog_partition_body_step(+appearance: Design.Appearance, +child: Doc.Node,
  +parts: Render.DialogParts) ->
  {Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, child, parts)) ==
    expected_dialog_body_prepend(appearance, child, Render.dialog_body_projection(parts)) : +List<Doc.Node>}:
  Design.Appearance{identity, visual, representation, children} = appearance
  match representation:
    case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
      match placement:
        case Controls.InFlow{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
        case Controls.ComposerEnd{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
        case Controls.PanelHeaderEnd{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
        case Controls.CodeToolbar{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
        case Controls.BesideValue{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
        case Controls.GroupHeadingEnd{}:
          match parts:
            case Render.DialogParts{+header, +body, +layouts}: {==}
    case Controls.NoControl{}:
      match parts:
        case Render.DialogParts{+header, +body, +layouts}: {==}
    case Controls.Input{binding, name, widget, label, availability}:
      match parts:
        case Render.DialogParts{+header, +body, +layouts}: {==}
    case Controls.Movable{destinations, face, name, handle, geometry, help}:
      match parts:
        case Render.DialogParts{+header, +body, +layouts}: {==}

def expected_dialog_header(children: +List<Doc.Node>, appearances: +List<Design.Appearance>) -> +List<Doc.Node>:
  match children appearances:
    case Con{+child, rest} Con{+appearance, visual_rest}:
      expected_dialog_header_prepend(appearance, child, expected_dialog_header(rest, visual_rest))
    case _ _: Nil{}

def expected_dialog_body(children: +List<Doc.Node>, appearances: +List<Design.Appearance>) -> +List<Doc.Node>:
  match children appearances:
    case Con{+child, rest} Con{+appearance, visual_rest}:
      expected_dialog_body_prepend(appearance, child, expected_dialog_body(rest, visual_rest))
    case _ _: Nil{}

def dialog_header_partition(children: +List<Doc.Node>, appearances: +List<Design.Appearance>) ->
  {Render.dialog_header_children(children, appearances) == expected_dialog_header(children, appearances) : +List<Doc.Node>}:
  match children appearances:
    case Con{+child, +rest} Con{+appearance, +visual_rest}:
      Design.Appearance{identity, visual, representation, children} = appearance
      match representation:
        case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
          match placement:
            case Controls.PanelHeaderEnd{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                child <> Render.dialog_header_projection(Render.dialog_partition(rest, visual_rest)),
                child <> expected_dialog_header(rest, visual_rest),
                dialog_partition_header_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => child <> tail),
                  Render.dialog_header_projection(Render.dialog_partition(rest, visual_rest)),
                  expected_dialog_header(rest, visual_rest), dialog_header_partition(rest, visual_rest)))
            case Controls.InFlow{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                Render.dialog_header_projection(Render.dialog_partition(rest, visual_rest)),
                expected_dialog_header(rest, visual_rest),
                dialog_partition_header_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                dialog_header_partition(rest, visual_rest))
            case Controls.ComposerEnd{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                Render.dialog_header_projection(Render.dialog_partition(rest, visual_rest)),
                expected_dialog_header(rest, visual_rest),
                dialog_partition_header_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                dialog_header_partition(rest, visual_rest))
            case Controls.CodeToolbar{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                Render.dialog_header_projection(Render.dialog_partition(rest, visual_rest)),
                expected_dialog_header(rest, visual_rest),
                dialog_partition_header_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                dialog_header_partition(rest, visual_rest))
            case Controls.BesideValue{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                Render.dialog_header_projection(Render.dialog_partition(rest, visual_rest)),
                expected_dialog_header(rest, visual_rest),
                dialog_partition_header_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                dialog_header_partition(rest, visual_rest))
            case Controls.GroupHeadingEnd{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                Render.dialog_header_projection(Render.dialog_partition(rest, visual_rest)),
                expected_dialog_header(rest, visual_rest),
                dialog_partition_header_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                dialog_header_partition(rest, visual_rest))
        case Controls.NoControl{}:
          Equal.trans(+List<Doc.Node>,
            Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, child,
              Render.dialog_partition(rest, visual_rest))),
            Render.dialog_header_projection(Render.dialog_partition(rest, visual_rest)),
            expected_dialog_header(rest, visual_rest),
            dialog_partition_header_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
            dialog_header_partition(rest, visual_rest))
        case Controls.Input{binding, name, widget, label, availability}:
          Equal.trans(+List<Doc.Node>,
            Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, child,
              Render.dialog_partition(rest, visual_rest))),
            Render.dialog_header_projection(Render.dialog_partition(rest, visual_rest)),
            expected_dialog_header(rest, visual_rest),
            dialog_partition_header_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
            dialog_header_partition(rest, visual_rest))
        case Controls.Movable{destinations, face, name, handle, geometry, help}:
          Equal.trans(+List<Doc.Node>,
            Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, child,
              Render.dialog_partition(rest, visual_rest))),
            Render.dialog_header_projection(Render.dialog_partition(rest, visual_rest)),
            expected_dialog_header(rest, visual_rest),
            dialog_partition_header_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
            dialog_header_partition(rest, visual_rest))
    case Nil{} Nil{}: {==}
    case Con{first, rest} Nil{}: {==}
    case Nil{} Con{first, rest}: {==}

def dialog_body_partition(children: +List<Doc.Node>, appearances: +List<Design.Appearance>) ->
  {Render.dialog_body_children(children, appearances) == expected_dialog_body(children, appearances) : +List<Doc.Node>}:
  match children appearances:
    case Con{+child, +rest} Con{+appearance, +visual_rest}:
      Design.Appearance{identity, visual, representation, children} = appearance
      match representation:
        case Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback}:
          match placement:
            case Controls.PanelHeaderEnd{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                expected_dialog_body(rest, visual_rest),
                dialog_partition_body_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                dialog_body_partition(rest, visual_rest))
            case Controls.InFlow{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                child <> Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                child <> expected_dialog_body(rest, visual_rest),
                dialog_partition_body_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => child <> tail),
                  Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                  expected_dialog_body(rest, visual_rest), dialog_body_partition(rest, visual_rest)))
            case Controls.ComposerEnd{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                child <> Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                child <> expected_dialog_body(rest, visual_rest),
                dialog_partition_body_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => child <> tail),
                  Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                  expected_dialog_body(rest, visual_rest), dialog_body_partition(rest, visual_rest)))
            case Controls.CodeToolbar{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                child <> Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                child <> expected_dialog_body(rest, visual_rest),
                dialog_partition_body_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => child <> tail),
                  Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                  expected_dialog_body(rest, visual_rest), dialog_body_partition(rest, visual_rest)))
            case Controls.BesideValue{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                child <> Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                child <> expected_dialog_body(rest, visual_rest),
                dialog_partition_body_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => child <> tail),
                  Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                  expected_dialog_body(rest, visual_rest), dialog_body_partition(rest, visual_rest)))
            case Controls.GroupHeadingEnd{}:
              Equal.trans(+List<Doc.Node>,
                Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, child,
                  Render.dialog_partition(rest, visual_rest))),
                child <> Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                child <> expected_dialog_body(rest, visual_rest),
                dialog_partition_body_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
                Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => child <> tail),
                  Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
                  expected_dialog_body(rest, visual_rest), dialog_body_partition(rest, visual_rest)))
        case Controls.NoControl{}:
          Equal.trans(+List<Doc.Node>,
            Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, child,
              Render.dialog_partition(rest, visual_rest))),
            child <> Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
            child <> expected_dialog_body(rest, visual_rest),
            dialog_partition_body_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
            Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => child <> tail),
              Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
              expected_dialog_body(rest, visual_rest), dialog_body_partition(rest, visual_rest)))
        case Controls.Input{binding, name, widget, label, availability}:
          Equal.trans(+List<Doc.Node>,
            Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, child,
              Render.dialog_partition(rest, visual_rest))),
            child <> Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
            child <> expected_dialog_body(rest, visual_rest),
            dialog_partition_body_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
            Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => child <> tail),
              Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
              expected_dialog_body(rest, visual_rest), dialog_body_partition(rest, visual_rest)))
        case Controls.Movable{destinations, face, name, handle, geometry, help}:
          Equal.trans(+List<Doc.Node>,
            Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, child,
              Render.dialog_partition(rest, visual_rest))),
            child <> Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
            child <> expected_dialog_body(rest, visual_rest),
            dialog_partition_body_step(appearance, child, Render.dialog_partition(rest, visual_rest)),
            Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => child <> tail),
              Render.dialog_body_projection(Render.dialog_partition(rest, visual_rest)),
              expected_dialog_body(rest, visual_rest), dialog_body_partition(rest, visual_rest)))
    case Nil{} Nil{}: {==}
    case Con{first, rest} Nil{}: {==}
    case Nil{} Con{first, rest}: {==}

def dialog_region_header_projection_suffix(+key: String, +label: String, visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {rest_nodes(node_children(dialog_header_node(Render.dialog_region_suffix(key, label, visual, header, suffix)))) ==
    header : +List<Doc.Node>}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_header_projection(+key: String, +label: String, visual: Design.Style,
  parts: Render.DialogParts) ->
  {rest_nodes(node_children(dialog_header_node(Render.dialog_region_parts(key, label, visual, parts)))) ==
    Render.dialog_header_projection(parts) : +List<Doc.Node>}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_header_projection_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_region_body_projection(+key: String, +label: String, visual: Design.Style,
  parts: Render.DialogParts) ->
  {DialogSpatial.original_children(Render.dialog_region_parts(key, label, visual, parts)) ==
    Render.dialog_body_projection(parts) : +List<Doc.Node>}:
  DialogSpatial.region_original_children(key, label, visual, parts)

def dialog_branch_header_projection(+key: String, +label: String, +source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, appearances: +List<Design.Appearance>) ->
  {rest_nodes(node_children(dialog_header_node(rendered_dialog(key, label, source, children, visual, appearances)))) ==
    Render.dialog_header_children(children, appearances) : +List<Doc.Node>}:
  Design.Style{Design.TextStyle{family, size, line_height, weight},
    Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
    direction, overflow, inline, block, gap, minimum, maximum, states} = visual
  dialog_region_header_projection(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight},
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
      direction, overflow, inline, block, gap, minimum, maximum, states},
    Render.dialog_partition(children, appearances))

def dialog_branch_header_partition(+key: String, +label: String, +source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, +appearances: +List<Design.Appearance>) ->
  {rest_nodes(node_children(dialog_header_node(rendered_dialog(key, label, source, children, visual, appearances)))) ==
    expected_dialog_header(children, appearances) : +List<Doc.Node>}:
  Equal.trans(+List<Doc.Node>,
    rest_nodes(node_children(dialog_header_node(rendered_dialog(key, label, source, children, visual, appearances)))),
    Render.dialog_header_children(children, appearances),
    expected_dialog_header(children, appearances),
    dialog_branch_header_projection(key, label, source, children, visual, appearances),
    dialog_header_partition(children, appearances))

def dialog_branch_body_projection(+key: String, +label: String, +source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, appearances: +List<Design.Appearance>) ->
  {DialogSpatial.original_children(rendered_dialog(key, label, source, children, visual, appearances)) ==
    Render.dialog_body_children(children, appearances) : +List<Doc.Node>}:
  Design.Style{Design.TextStyle{family, size, line_height, weight},
    Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
    direction, overflow, inline, block, gap, minimum, maximum, states} = visual
  dialog_region_body_projection(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight},
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
      direction, overflow, inline, block, gap, minimum, maximum, states},
    Render.dialog_partition(children, appearances))

def dialog_branch_body_partition(+key: String, +label: String, +source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, +appearances: +List<Design.Appearance>) ->
  {DialogSpatial.original_children(rendered_dialog(key, label, source, children, visual, appearances)) ==
    expected_dialog_body(children, appearances) : +List<Doc.Node>}:
  Equal.trans(+List<Doc.Node>,
    DialogSpatial.original_children(rendered_dialog(key, label, source, children, visual, appearances)),
    Render.dialog_body_children(children, appearances),
    expected_dialog_body(children, appearances),
    dialog_branch_body_projection(key, label, source, children, visual, appearances),
    dialog_body_partition(children, appearances))

def dialog_region_wrapper_keys_suffix(+key: String, +label: String, visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {(node_key(dialog_header_node(Render.dialog_region_suffix(key, label, visual, header, suffix))),
    (node_key(dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix))),
     node_key(dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix))))) ==
   (Render.generated_identity(key, "dialog-header"),
    (Render.generated_identity(key, "dialog-body"), Render.generated_identity(key, "dialog-content"))) :
   (String & (String & String))}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_wrapper_keys(+key: String, +label: String, visual: Design.Style,
  parts: Render.DialogParts) ->
  {(node_key(dialog_header_node(Render.dialog_region_parts(key, label, visual, parts))),
    (node_key(dialog_body_node(Render.dialog_region_parts(key, label, visual, parts))),
     node_key(dialog_content_node(Render.dialog_region_parts(key, label, visual, parts))))) ==
   (Render.generated_identity(key, "dialog-header"),
    (Render.generated_identity(key, "dialog-body"), Render.generated_identity(key, "dialog-content"))) :
   (String & (String & String))}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_wrapper_keys_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_branch_wrapper_keys(+key: String, +label: String, +source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, appearances: +List<Design.Appearance>) ->
  {(node_key(dialog_header_node(rendered_dialog(key, label, source, children, visual, appearances))),
    (node_key(dialog_body_node(rendered_dialog(key, label, source, children, visual, appearances))),
     node_key(dialog_content_node(rendered_dialog(key, label, source, children, visual, appearances))))) ==
   (Render.generated_identity(key, "dialog-header"),
    (Render.generated_identity(key, "dialog-body"), Render.generated_identity(key, "dialog-content"))) :
   (String & (String & String))}:
  Design.Style{Design.TextStyle{family, size, line_height, weight},
    Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
    direction, overflow, inline, block, gap, minimum, maximum, states} = visual
  dialog_region_wrapper_keys(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight},
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
      direction, overflow, inline, block, gap, minimum, maximum, states},
    Render.dialog_partition(children, appearances))

def dialog_region_outer_identity_suffix(+key: String, +label: String, visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {(node_key(Render.dialog_region_suffix(key, label, visual, header, suffix)),
    (Render.attr(node_attributes(Render.dialog_region_suffix(key, label, visual, header, suffix)), "aria-label"),
     Render.attr(node_attributes(Render.dialog_region_suffix(key, label, visual, header, suffix)), "data-native-key"))) ==
   (key, (label, key)) : (String & (String & String))}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_outer_identity(+key: String, +label: String, visual: Design.Style,
  parts: Render.DialogParts) ->
  {(node_key(Render.dialog_region_parts(key, label, visual, parts)),
    (Render.attr(node_attributes(Render.dialog_region_parts(key, label, visual, parts)), "aria-label"),
     Render.attr(node_attributes(Render.dialog_region_parts(key, label, visual, parts)), "data-native-key"))) ==
   (key, (label, key)) : (String & (String & String))}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_outer_identity_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_region_title_identity_suffix(+key: String, +label: String, visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {(node_key(dialog_title_node(Render.dialog_region_suffix(key, label, visual, header, suffix))),
    direct_text(dialog_title_node(Render.dialog_region_suffix(key, label, visual, header, suffix)))) ==
   (Render.generated_identity(key, "title"), label) : (String & String)}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_title_identity(+key: String, +label: String, visual: Design.Style,
  parts: Render.DialogParts) ->
  {(node_key(dialog_title_node(Render.dialog_region_parts(key, label, visual, parts))),
    direct_text(dialog_title_node(Render.dialog_region_parts(key, label, visual, parts)))) ==
   (Render.generated_identity(key, "title"), label) : (String & String)}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_title_identity_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_branch_outer_identity(+key: String, +label: String, +source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, appearances: +List<Design.Appearance>) ->
  {(node_key(rendered_dialog(key, label, source, children, visual, appearances)),
    (Render.attr(node_attributes(rendered_dialog(key, label, source, children, visual, appearances)), "aria-label"),
     Render.attr(node_attributes(rendered_dialog(key, label, source, children, visual, appearances)), "data-native-key"))) ==
   (key, (label, key)) : (String & (String & String))}:
  Design.Style{Design.TextStyle{family, size, line_height, weight},
    Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
    direction, overflow, inline, block, gap, minimum, maximum, states} = visual
  dialog_region_outer_identity(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight},
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
      direction, overflow, inline, block, gap, minimum, maximum, states},
    Render.dialog_partition(children, appearances))

def dialog_branch_title_identity(+key: String, +label: String, +source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, appearances: +List<Design.Appearance>) ->
  {(node_key(dialog_title_node(rendered_dialog(key, label, source, children, visual, appearances))),
    direct_text(dialog_title_node(rendered_dialog(key, label, source, children, visual, appearances)))) ==
   (Render.generated_identity(key, "title"), label) : (String & String)}:
  Design.Style{Design.TextStyle{family, size, line_height, weight},
    Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
    direction, overflow, inline, block, gap, minimum, maximum, states} = visual
  dialog_region_title_identity(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight},
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
      direction, overflow, inline, block, gap, minimum, maximum, states},
    Render.dialog_partition(children, appearances))

def dialog_region_flow_properties_suffix(+key: String, +label: String, visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {(Render.attr(node_styles(dialog_header_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "flex"),
    (Render.attr(node_styles(dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "flex"),
     (Render.attr(node_styles(dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "min-height"),
      (Render.attr(node_styles(dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "overflow"),
       (Render.attr(node_styles(dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "flex"),
        (Render.attr(node_styles(dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "height"),
         Render.attr(node_styles(dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "max-height"))))))) ==
   ("0 0 auto", ("1 1 auto", ("0", ("auto", ("0 0 auto", ("", "")))))) :
   (String & (String & (String & (String & (String & (String & String))))))}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_flow_properties(+key: String, +label: String, visual: Design.Style,
  parts: Render.DialogParts) ->
  {(Render.attr(node_styles(dialog_header_node(Render.dialog_region_parts(key, label, visual, parts))), "flex"),
    (Render.attr(node_styles(dialog_body_node(Render.dialog_region_parts(key, label, visual, parts))), "flex"),
     (Render.attr(node_styles(dialog_body_node(Render.dialog_region_parts(key, label, visual, parts))), "min-height"),
      (Render.attr(node_styles(dialog_body_node(Render.dialog_region_parts(key, label, visual, parts))), "overflow"),
       (Render.attr(node_styles(dialog_content_node(Render.dialog_region_parts(key, label, visual, parts))), "flex"),
        (Render.attr(node_styles(dialog_content_node(Render.dialog_region_parts(key, label, visual, parts))), "height"),
         Render.attr(node_styles(dialog_content_node(Render.dialog_region_parts(key, label, visual, parts))), "max-height"))))))) ==
   ("0 0 auto", ("1 1 auto", ("0", ("auto", ("0 0 auto", ("", "")))))) :
   (String & (String & (String & (String & (String & (String & String))))))}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_flow_properties_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_flow_properties(+key: String, +label: String, +source: +List<Interface.Node>,
  +children: +List<Doc.Node>, +visual: Design.Style, appearances: +List<Design.Appearance>) ->
  {(Render.attr(node_styles(dialog_header_node(rendered_dialog(key, label, source, children, visual, appearances))), "flex"),
    (Render.attr(node_styles(dialog_body_node(rendered_dialog(key, label, source, children, visual, appearances))), "flex"),
     (Render.attr(node_styles(dialog_body_node(rendered_dialog(key, label, source, children, visual, appearances))), "min-height"),
      (Render.attr(node_styles(dialog_body_node(rendered_dialog(key, label, source, children, visual, appearances))), "overflow"),
       (Render.attr(node_styles(dialog_content_node(rendered_dialog(key, label, source, children, visual, appearances))), "flex"),
        (Render.attr(node_styles(dialog_content_node(rendered_dialog(key, label, source, children, visual, appearances))), "height"),
         Render.attr(node_styles(dialog_content_node(rendered_dialog(key, label, source, children, visual, appearances))), "max-height"))))))) ==
   ("0 0 auto", ("1 1 auto", ("0", ("auto", ("0 0 auto", ("", "")))))) :
   (String & (String & (String & (String & (String & (String & String))))))}:
  Design.Style{Design.TextStyle{family, size, line_height, weight},
    Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
    direction, overflow, inline, block, gap, minimum, maximum, states} = visual
  dialog_region_flow_properties(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight},
      Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment,
      direction, overflow, inline, block, gap, minimum, maximum, states},
    Render.dialog_partition(children, appearances))

def centered_dialog_hides_overflow(+available: Design.Box, maximum_width: Nat) ->
  {Render.attr(Render.overlay_styles(Design.CenteredDialog{available, maximum_width}), "overflow") == "hidden" : String}:
  match available:
    case Design.Box{left, top, width, height}: {==}

def anchored_popover_keeps_scroll(+anchor: String, +available: Design.Box,
  maximum_width: Nat, maximum_height: Nat, gap: Nat) ->
  {Render.attr(Render.overlay_styles(Design.AnchoredPopover{anchor, available,
      maximum_width, maximum_height, gap}), "overflow") == "auto" : String}:
  match available:
    case Design.Box{left, top, width, height}: {==}


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

def anchored_popover_placement_styles(+anchor: String, +available: Design.Box,
  +maximum_width: Nat, +maximum_height: Nat, +gap: Nat) ->
  {Render.overlay_styles(Design.AnchoredPopover{anchor, available, maximum_width, maximum_height, gap}) ==
    expected_popover_styles(anchor, available, maximum_width, maximum_height, gap) : +List<Doc.Property>}:
  match available:
    case Design.Box{left, top, width, height}: {==}

def anchored_popover_normal_alignment(+anchor: String, +available: Design.Box,
  maximum_width: Nat, maximum_height: Nat, gap: Nat) ->
  {Render.attr(Render.overlay_styles(Design.AnchoredPopover{anchor, available,
      maximum_width, maximum_height, gap}), "align-self") == "normal" : String}:
  match available:
    case Design.Box{left, top, width, height}: {==}

def anchored_popover_content_height(+anchor: String, +available: Design.Box,
  maximum_width: Nat, maximum_height: Nat, gap: Nat) ->
  {Render.attr(Render.overlay_styles(Design.AnchoredPopover{anchor, available,
      maximum_width, maximum_height, gap}), "height") == "max-content" : String}:
  match available:
    case Design.Box{left, top, width, height}: {==}

def board_search_placeholder(+filter: Board.Filter) ->
  {Render.attr(Render.field_hint(Interface.BoardSearch{filter}), "placeholder") == "搜索任务" : String}:
  {==}

type Requirements is Type:
  Requirements{
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
      {observed_box(Render.frame_region(key, region, box, children)) == specified_box(box) : (String & (String & (String & String)))},
    action_event: @+key:String -> @+style:Design.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback ->
      {node_events(Render.action(key, Design.Appearance{key, style, Controls.NoControl{}, Nil{}},
          Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})) ==
          [Doc.Activate{key}] : +List<Doc.Event>},
    action_accessible_name: @+key:String -> @+style:Design.Style -> @+input:Core.Input -> @+availability:View.Availability -> @+name:String -> @+face:Controls.Face -> @+behavior:Controls.Behavior -> @+geometry:Controls.Geometry -> @+placement:Controls.Placement -> @+help:Controls.Help -> @+feedback:Controls.Feedback ->
      {Render.attr(node_attributes(Render.action(key, Design.Appearance{key, style, Controls.NoControl{}, Nil{}},
          Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "aria-label") == name : String},
    textarea_event: @+key:String ->
      {Render.input_events(key, Controls.MessageInput{}) == [Doc.EditText{key}] : +List<Doc.Event>},
    toggle_event: @+key:String ->
      {Render.input_events(key, Controls.ToggleInput{}) == [Doc.EditToggle{key}] : +List<Doc.Event>},
    file_event: @+key:String -> @+face:Controls.Face ->
      {Render.input_events(key, Controls.FileChooser{face}) == [Doc.SelectFiles{key}] : +List<Doc.Event>},
    creation_canvas: @+children:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band -> @+input:Maybe<&2, Design.InputMetrics> -> @+flow:Design.CreationFlow ->
      {observed_box(first_node(Render.main_children(children, Design.CreationFrame{heading, canvas, band, input, flow}))) ==
          specified_box(canvas) : (String & (String & (String & String)))},
    unavailable_canvas: @+children:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band ->
      {observed_box(first_node(Render.main_children(children, Design.UnavailableFrame{heading, canvas, band}))) ==
          specified_box(canvas) : (String & (String & (String & String)))},
    rendered_region_count: @+values:+List<Interface.Node> -> @+context:Controls.Context ->
      {List.length(&2, Doc.Node, Render.render_nodes(values, Appearance.nodes_at(values, context))) ==
          List.length(&2, Interface.Node, values) : Nat},
    creation_regions_keep_order: @+children:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {ShellSpatial.creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(children))) == children : +List<Doc.Node>},
    creation_canvas_retains_regions: @+canvas:Design.Box -> @+band:Design.Band -> @+flow:Design.CreationFlow -> @+children:+List<Doc.Node> ->
      {node_children(first_node(Render.creation_canvas_nodes(canvas, band, flow, children))) == [Render.creation_group(band, flow, children)] : +List<Doc.Node>},
    creation_composer_flows: @heading:Design.Box -> @canvas:Design.Box -> @band:Design.Band -> @input:Maybe<&2, Design.InputMetrics> -> @flow:Design.CreationFlow ->
      {Render.attr(Render.composer_styles(Design.CreationFrame{heading, canvas, band, input, flow}), "position") == "" : String},
    composer_actions_keep_order: @+key:String -> @+children:+List<Doc.Node> ->
      {List.append(&2, Doc.Node, node_children(first_node(Render.composer_action_groups(key, children))),
        node_children(second_node(Render.composer_action_groups(key, children)))) == children : +List<Doc.Node>},
    light_document_theme: {Render.document_theme(Design.Light{}) == Doc.TargetProperties{"document-theme", "@document/root",
      [Doc.Property{"data-theme", "light"}], [Doc.Property{"color-scheme", "light"}]} : Doc.Node},
    dark_document_theme: {Render.document_theme(Design.Dark{}) == Doc.TargetProperties{"document-theme", "@document/root",
      [Doc.Property{"data-theme", "dark"}], [Doc.Property{"color-scheme", "dark"}]} : Doc.Node},
    root_theme_attribute: @+theme:Design.Theme -> {Render.attr(target_attributes(Render.document_theme(theme)), "data-theme") == Render.theme_name(theme) : String},
    root_theme_color_scheme: @+theme:Design.Theme -> {Render.attr(target_styles(Render.document_theme(theme)), "color-scheme") == Render.theme_name(theme) : String},
    compound_field_preserves_children: @+key:String -> @label:String -> @field:Forms.Field -> @visual:Design.Style -> @+children:+List<Doc.Node> ->
      {node_children(Render.compound_field(key, label, field, visual, children)) == children : +List<Doc.Node>},
    compound_field_has_no_events: @key:String -> @label:String -> @field:Forms.Field -> @visual:Design.Style -> @children:+List<Doc.Node> ->
      {node_events(Render.compound_field(key, label, field, visual, children)) == Nil{} : +List<Doc.Event>},
    compound_field_is_not_tab_stop: @key:String -> @label:String -> @field:Forms.Field -> @visual:Design.Style -> @children:+List<Doc.Node> ->
      {Render.attr(node_attributes(Render.compound_field(key, label, field, visual, children)), "tabindex") == "-1" : String},
    directory_field_uses_compound: @+key:String -> @+label:String -> @role:Interface.Role -> @owner:User.Editor -> @+field:Forms.Field ->
      @value:Forms.Observed -> @source:+List<Interface.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style -> @representation:Controls.Representation -> @appearance:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, Interface.Edit{owner, field, Forms.DirectoryCollection{}, value}, source, children, visual, representation, appearance) == Render.compound_field(key, label, field, visual, children) : Doc.Node},
    file_field_uses_compound: @+key:String -> @+label:String -> @role:Interface.Role -> @owner:User.Editor -> @+field:Forms.Field ->
      @value:Forms.Observed -> @source:+List<Interface.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style -> @representation:Controls.Representation -> @appearance:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, Interface.Edit{owner, field, Forms.FileCollection{}, value}, source, children, visual, representation, appearance) == Render.compound_field(key, label, field, visual, children) : Doc.Node},
    board_group_properties: @+key:String -> @+grouping:Interface.BoardGrouping -> @+children:+List<Doc.Node> ->
      {(Render.attr(node_attributes(Render.board_group_node(key, grouping, children)), "data-native-key"),
        (Render.attr(node_attributes(Render.board_group_node(key, grouping, children)), "data-board-group"),
         (Render.attr(node_attributes(Render.board_group_node(key, grouping, children)), "role"),
          Render.attr(node_attributes(Render.board_group_node(key, grouping, children)), "aria-label")))) ==
        (key, (Render.board_group_name(grouping), ("group", Render.board_group_label(grouping)))) :
        (String & (String & (String & String)))},
    board_group_dispatch: @+key:String -> @+label:String -> @role:Interface.Role -> @+grouping:Interface.BoardGrouping ->
      @source:+List<Interface.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style -> @representation:Controls.Representation -> @appearances:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, Interface.BoardGroup{grouping}, source, children, visual, representation, appearances) ==
        Render.board_group_node(key, grouping, children) : Doc.Node},
    board_lane_dispatch: @+key:String -> @+label:String -> @role:Interface.Role -> @+stage:Board.Stage -> @+count:Nat ->
      @source:+List<Interface.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style -> @representation:Controls.Representation -> @appearances:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, Interface.BoardLane{stage, count}, source, children, visual, representation, appearances) ==
        Render.board_lane_node(key, label, stage, count, source, children) : Doc.Node},
    board_lane_projection: @+key:String -> @+label:String -> @+stage:Board.Stage -> @+count:Nat -> @source:+List<Interface.Node> -> @+children:+List<Doc.Node> ->
      {(Render.attr(node_attributes(Render.board_lane_node(key, label, stage, count, source, children)), "data-native-key"),
        (Render.attr(node_attributes(Render.board_lane_node(key, label, stage, count, source, children)), "data-board-stage"),
         (Render.attr(node_attributes(Render.board_lane_node(key, label, stage, count, source, children)), "data-board-count"),
          Render.attr(node_attributes(Render.board_lane_node(key, label, stage, count, source, children)), "aria-label")))) ==
        (key, (Board.stage_name(stage), (Nat.show(count), label))) : (String & (String & (String & String)))},
    board_lane_count_projection: @+owner:String -> @+count:Nat ->
      {(Render.attr(node_attributes(Render.lane_count(owner, count)), "data-board-count"), direct_text(Render.lane_count(owner, count))) ==
        (Nat.show(count), Nat.show(count)) : (String & String)},
    board_lane_empty_projection: @+owner:String ->
      {(direct_texts(Render.empty_lane(0n, owner)),
        (List.length(&2, Doc.Node, Render.empty_lane(0n, owner)), List.length(&2, Doc.Node, Render.empty_lane(1n, owner)))) ==
        ("暂无任务", (1n, 0n)) : (String & (Nat & Nat))},
    board_lane_scroll_ownership: @+stage:Board.Stage ->
      {(Render.attr(Render.board_lane_styles(stage), "min-height"), Render.attr(Render.board_lane_styles(stage), "overflow")) ==
        ("0", "hidden") : (String & String)},
    board_column_sizing: @+key:String -> @+width:Nat ->
      {board_column_style_projection(key, width) == (Render.px(width), ("0 0 auto", "100%")) : (String & (String & String))},
    board_stage_scroll_ownership: @+key:String -> @+width:Nat -> @+gap:Nat -> @+inset:Nat ->
      {(Render.attr(node_styles(Render.board_stage_region(Doc.Element{key, "div", Nil{}, Nil{}, Nil{}, Nil{}}, width, gap, inset)), "flex"),
        (Render.attr(node_styles(Render.board_stage_region(Doc.Element{key, "div", Nil{}, Nil{}, Nil{}, Nil{}}, width, gap, inset)), "overflow-x"),
         Render.attr(node_styles(Render.board_stage_region(Doc.Element{key, "div", Nil{}, Nil{}, Nil{}, Nil{}}, width, gap, inset)), "overflow-y"))) ==
        ("1", ("auto", "hidden")) : (String & (String & String))},
    card_root_face_projection: @+key:String -> @+face:View.CardFace -> @destinations:+List<Interface.Placement> -> @source:+List<Interface.Node> ->
      @+children:+List<Doc.Node> -> @+visual:Design.Style ->
      {(Render.attr(node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "data-native-key"),
        (Render.attr(node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "data-card-id"),
         (Render.attr(node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "data-card-title"),
          Render.attr(node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "aria-label")))) ==
        card_root_face_expected(key, face) : (String & (String & (String & String)))},
    card_root_excludes_tab_target: @+key:String -> @+face:View.CardFace -> @destinations:+List<Interface.Placement> -> @source:+List<Interface.Node> ->
      @+children:+List<Doc.Node> -> @+visual:Design.Style ->
      {Render.attr(node_attributes(Render.card_node(key, face, destinations, source, children, visual)), "tabindex") == "" : String},
    card_metadata_projection: @+owner:String -> @+face:View.CardFace ->
      {direct_text_slots(node_children(Render.card_metadata(owner, face, String.is_empty(card_face_status(face))))) ==
        card_metadata_expected(face, String.is_empty(card_face_status(face))) : +List<String>},
    card_description_projection: @+owner:String -> @+description:String ->
      {direct_text_slots(Render.card_description(owner, description)) == optional_text_slots(description) : +List<String>},
    card_context_projection: @+owner:String -> @+project:String -> @+labels:+List<String> ->
      {direct_text_slots(node_children(first_node(Render.card_context_nodes(owner, project, labels)))) ==
        List.append(&2, String, optional_text_slots(project), labels) : +List<String>},
    card_footer_projection: @+owner:String -> @+face:View.CardFace ->
      {direct_text_slots(node_children(first_node(Render.card_footer(owner, face)))) == card_footer_expected(face) : +List<String>},
    movable_card_dispatch: @+key:String -> @+label:String -> @role:Interface.Role -> @destinations:+List<Interface.Placement> -> @+face:View.CardFace ->
      @source:+List<Interface.Node> -> @+children:+List<Doc.Node> -> @+visual:Design.Style -> @representation:Controls.Representation -> @appearances:+List<Design.Appearance> ->
      {Render.match_node(key, label, role, Interface.MovableCard{destinations, face}, source, children, visual, representation, appearances) ==
        Render.card_node(key, face, destinations, source, children, visual) : Doc.Node},
    movable_card_events: @+key:String -> @+face:View.CardFace -> @destinations:+List<Interface.Placement> -> @source:+List<Interface.Node> ->
      @+children:+List<Doc.Node> -> @+visual:Design.Style ->
      {node_events(Render.card_node(key, face, destinations, source, children, visual)) == [Doc.DragCard{key}, Doc.DropCard{key}] : +List<Doc.Event>},
    dialog_branch_header_partition: @+key:String -> @+label:String -> @source:+List<Interface.Node> ->
      @+children:+List<Doc.Node> -> @+visual:Design.Style -> @appearances:+List<Design.Appearance> ->
      {rest_nodes(node_children(dialog_header_node(rendered_dialog(key, label, source, children, visual, appearances)))) ==
        expected_dialog_header(children, appearances) : +List<Doc.Node>},
    dialog_branch_body_partition: @+key:String -> @+label:String -> @source:+List<Interface.Node> ->
      @+children:+List<Doc.Node> -> @+visual:Design.Style -> @appearances:+List<Design.Appearance> ->
      {DialogSpatial.original_children(rendered_dialog(key, label, source, children, visual, appearances)) ==
        expected_dialog_body(children, appearances) : +List<Doc.Node>},
    dialog_branch_wrapper_keys: @+key:String -> @+label:String -> @source:+List<Interface.Node> ->
      @+children:+List<Doc.Node> -> @+visual:Design.Style -> @appearances:+List<Design.Appearance> ->
      {(node_key(dialog_header_node(rendered_dialog(key, label, source, children, visual, appearances))),
        (node_key(dialog_body_node(rendered_dialog(key, label, source, children, visual, appearances))),
         node_key(dialog_content_node(rendered_dialog(key, label, source, children, visual, appearances))))) ==
       (Render.generated_identity(key, "dialog-header"),
        (Render.generated_identity(key, "dialog-body"), Render.generated_identity(key, "dialog-content"))) :
       (String & (String & String))},
    dialog_branch_outer_identity: @+key:String -> @+label:String -> @source:+List<Interface.Node> ->
      @+children:+List<Doc.Node> -> @+visual:Design.Style -> @appearances:+List<Design.Appearance> ->
      {(node_key(rendered_dialog(key, label, source, children, visual, appearances)),
        (Render.attr(node_attributes(rendered_dialog(key, label, source, children, visual, appearances)), "aria-label"),
         Render.attr(node_attributes(rendered_dialog(key, label, source, children, visual, appearances)), "data-native-key"))) ==
       (key, (label, key)) : (String & (String & String))},
    dialog_branch_title_identity: @+key:String -> @+label:String -> @source:+List<Interface.Node> ->
      @+children:+List<Doc.Node> -> @+visual:Design.Style -> @appearances:+List<Design.Appearance> ->
      {(node_key(dialog_title_node(rendered_dialog(key, label, source, children, visual, appearances))),
        direct_text(dialog_title_node(rendered_dialog(key, label, source, children, visual, appearances)))) ==
       (Render.generated_identity(key, "title"), label) : (String & String)},
    dialog_flow_properties: @+key:String -> @+label:String -> @source:+List<Interface.Node> ->
      @+children:+List<Doc.Node> -> @+visual:Design.Style -> @appearances:+List<Design.Appearance> ->
      {(Render.attr(node_styles(dialog_header_node(rendered_dialog(key, label, source, children, visual, appearances))), "flex"),
        (Render.attr(node_styles(dialog_body_node(rendered_dialog(key, label, source, children, visual, appearances))), "flex"),
         (Render.attr(node_styles(dialog_body_node(rendered_dialog(key, label, source, children, visual, appearances))), "min-height"),
          (Render.attr(node_styles(dialog_body_node(rendered_dialog(key, label, source, children, visual, appearances))), "overflow"),
           (Render.attr(node_styles(dialog_content_node(rendered_dialog(key, label, source, children, visual, appearances))), "flex"),
            (Render.attr(node_styles(dialog_content_node(rendered_dialog(key, label, source, children, visual, appearances))), "height"),
             Render.attr(node_styles(dialog_content_node(rendered_dialog(key, label, source, children, visual, appearances))), "max-height"))))))) ==
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

def evidence() -> Requirements:
  Requirements{
    background_without_modal(),
    current => background_with_modal(current),
    key => overlay_without_modal(key),
    current => key => overlay_with_modal(current, key),
    active_overlay_properties(),
    inactive_overlay_properties(),
    box => bounds_refinement(box),
    key => region => box => children => region_bounds(key, region, box, children),
    key => style => input => availability => name => face => behavior => geometry => placement => help => feedback => action_event(key, style, input, availability, name, face, behavior, geometry, placement, help, feedback),
    key => style => input => availability => name => face => behavior => geometry => placement => help => feedback => action_accessible_name(key, style, input, availability, name, face, behavior, geometry, placement, help, feedback),
    key => textarea_event(key),
    key => toggle_event(key),
    key => face => file_event(key, face),
    children => heading => canvas => band => input => flow => creation_canvas(children, heading, canvas, band, input, flow),
    children => heading => canvas => band => unavailable_canvas(children, heading, canvas, band),
    values => context => rendered_region_count(values, context),
    children => band => flow => creation_regions_keep_order(children, band, flow),
    canvas => band => flow => children => creation_canvas_retains_regions(canvas, band, flow, children),
    heading => canvas => band => input => flow => creation_composer_flows(heading, canvas, band, input, flow),
    key => children => composer_actions_keep_order(key, children),
    light_document_theme(),
    dark_document_theme(),
    theme => root_theme_attribute(theme),
    theme => root_theme_color_scheme(theme),
    key => label => field => visual => children => compound_field_preserves_children(key, label, field, visual, children),
    key => label => field => visual => children => compound_field_has_no_events(key, label, field, visual, children),
    key => label => field => visual => children => compound_field_is_not_tab_stop(key, label, field, visual, children),
    key => label => role => owner => field => value => source => children => visual => representation => appearance =>
      directory_field_uses_compound(key, label, role, owner, field, value, source, children, visual, representation, appearance),
    key => label => role => owner => field => value => source => children => visual => representation => appearance =>
      file_field_uses_compound(key, label, role, owner, field, value, source, children, visual, representation, appearance),
    key => grouping => children => board_group_properties(key, grouping, children),
    key => label => role => grouping => source => children => visual => representation => appearances =>
      board_group_dispatch(key, label, role, grouping, source, children, visual, representation, appearances),
    key => label => role => stage => count => source => children => visual => representation => appearances =>
      board_lane_dispatch(key, label, role, stage, count, source, children, visual, representation, appearances),
    key => label => stage => count => source => children => board_lane_projection(key, label, stage, count, source, children),
    owner => count => board_lane_count_projection(owner, count),
    owner => board_lane_empty_projection(owner),
    stage => board_lane_scroll_ownership(stage),
    key => width => board_column_sizing(key, width),
    key => width => gap => inset => board_stage_scroll_ownership(key, width, gap, inset),
    key => face => destinations => source => children => visual =>
      card_root_face_projection(key, face, destinations, source, children, visual),
    key => face => destinations => source => children => visual =>
      card_root_excludes_tab_target(key, face, destinations, source, children, visual),
    owner => face => card_metadata_projection(owner, face),
    owner => description => card_description_projection(owner, description),
    owner => project => labels => card_context_projection(owner, project, labels),
    owner => face => card_footer_projection(owner, face),
    key => label => role => destinations => face => source => children => visual => representation => appearances =>
      movable_card_dispatch(key, label, role, destinations, face, source, children, visual, representation, appearances),
    key => face => destinations => source => children => visual =>
      movable_card_events(key, face, destinations, source, children, visual),
    key => label => source => children => visual => appearances =>
      dialog_branch_header_partition(key, label, source, children, visual, appearances),
    key => label => source => children => visual => appearances =>
      dialog_branch_body_partition(key, label, source, children, visual, appearances),
    key => label => source => children => visual => appearances =>
      dialog_branch_wrapper_keys(key, label, source, children, visual, appearances),
    key => label => source => children => visual => appearances =>
      dialog_branch_outer_identity(key, label, source, children, visual, appearances),
    key => label => source => children => visual => appearances =>
      dialog_branch_title_identity(key, label, source, children, visual, appearances),
    key => label => source => children => visual => appearances =>
      dialog_flow_properties(key, label, source, children, visual, appearances),
    available => maximum_width => centered_dialog_hides_overflow(available, maximum_width),
    anchor => available => maximum_width => maximum_height => gap =>
      anchored_popover_keeps_scroll(anchor, available, maximum_width, maximum_height, gap),
    anchor => available => maximum_width => maximum_height => gap =>
      anchored_popover_placement_styles(anchor, available, maximum_width, maximum_height, gap),
    anchor => available => maximum_width => maximum_height => gap =>
      anchored_popover_normal_alignment(anchor, available, maximum_width, maximum_height, gap),
    anchor => available => maximum_width => maximum_height => gap =>
      anchored_popover_content_height(anchor, available, maximum_width, maximum_height, gap),
    filter => board_search_placeholder(filter)
  }
