import ../core/interface.bend as Interface
import Base
import ./enclosure.bend as Enclosure
import ../bendlib/stdlib.bend as Std
import ./document.bend as Doc
import ./renderer.bend as Render
import ./dialog-spatial-laws.bend as DialogSpatial
import ./editor-layout.bend as EditorLayout
import ./shell-spatial-laws.bend as ShellSpatial
import ./design.bend as Design
import ./surfaces.bend as Surfaces
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











def action_accessible_name(+key: String, +style: Design.Style, +input: Core.Input,
  +availability: View.Availability, +name: String, +face: Controls.Face,
  +behavior: Controls.Behavior, +geometry: Controls.Geometry, +placement: Controls.Placement,
  +help: Controls.Help, +feedback: Controls.Feedback) ->
  {Render.attr(Doc.element_attributes(Render.action(key, style,
    Controls.Action{input, availability, name, face, behavior, geometry, placement, help, feedback})), "aria-label") == name : String}:
  match availability behavior help:
    case View.Available{} Controls.Push{} Controls.NoHelp{}: {==}
    case View.Available{} Controls.Push{} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Available{} Controls.Toggle{pressed} Controls.NoHelp{}: {==}
    case View.Available{} Controls.Toggle{pressed} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Available{} Controls.Radio{checked} Controls.NoHelp{}: {==}
    case View.Available{} Controls.Radio{checked} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Available{} Controls.ChoiceRadio{checked} Controls.NoHelp{}: {==}
    case View.Available{} Controls.ChoiceRadio{checked} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Available{} Controls.Disclosure{expanded} Controls.NoHelp{}: {==}
    case View.Available{} Controls.Disclosure{expanded} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Available{} Controls.Popup{menu, expanded} Controls.NoHelp{}: {==}
    case View.Available{} Controls.Popup{menu, expanded} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Available{} Controls.Destination{current} Controls.NoHelp{}: {==}
    case View.Available{} Controls.Destination{current} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.NeedsDirectoryObservation{} Controls.Push{} Controls.NoHelp{}: {==}
    case View.NeedsDirectoryObservation{} Controls.Push{} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.NeedsDirectoryObservation{} Controls.Toggle{pressed} Controls.NoHelp{}: {==}
    case View.NeedsDirectoryObservation{} Controls.Toggle{pressed} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.NeedsDirectoryObservation{} Controls.Radio{checked} Controls.NoHelp{}: {==}
    case View.NeedsDirectoryObservation{} Controls.Radio{checked} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.NeedsDirectoryObservation{} Controls.ChoiceRadio{checked} Controls.NoHelp{}: {==}
    case View.NeedsDirectoryObservation{} Controls.ChoiceRadio{checked} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.NeedsDirectoryObservation{} Controls.Disclosure{expanded} Controls.NoHelp{}: {==}
    case View.NeedsDirectoryObservation{} Controls.Disclosure{expanded} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.NeedsDirectoryObservation{} Controls.Popup{menu, expanded} Controls.NoHelp{}: {==}
    case View.NeedsDirectoryObservation{} Controls.Popup{menu, expanded} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.NeedsDirectoryObservation{} Controls.Destination{current} Controls.NoHelp{}: {==}
    case View.NeedsDirectoryObservation{} Controls.Destination{current} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Unavailable{reason} Controls.Push{} Controls.NoHelp{}: {==}
    case View.Unavailable{reason} Controls.Push{} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Unavailable{reason} Controls.Toggle{pressed} Controls.NoHelp{}: {==}
    case View.Unavailable{reason} Controls.Toggle{pressed} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Unavailable{reason} Controls.Radio{checked} Controls.NoHelp{}: {==}
    case View.Unavailable{reason} Controls.Radio{checked} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Unavailable{reason} Controls.ChoiceRadio{checked} Controls.NoHelp{}: {==}
    case View.Unavailable{reason} Controls.ChoiceRadio{checked} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Unavailable{reason} Controls.Disclosure{expanded} Controls.NoHelp{}: {==}
    case View.Unavailable{reason} Controls.Disclosure{expanded} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Unavailable{reason} Controls.Popup{menu, expanded} Controls.NoHelp{}: {==}
    case View.Unavailable{reason} Controls.Popup{menu, expanded} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}
    case View.Unavailable{reason} Controls.Destination{current} Controls.NoHelp{}: {==}
    case View.Unavailable{reason} Controls.Destination{current} Controls.Tooltip{text, delay, pointer, keyboard, takes_focus}: {==}







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

# Rendering traverses every prepared surface node in order without a second list.
def rendered_region_count(+values: +List<Design.Node>) ->
  {List.length(&2, Doc.Node, Render.render_nodes(values)) ==
    List.length(&2, Design.Node, values) : Nat}:
  match values:
    case Nil{}: {==}
    case Con{Design.Node{key, semantic, label, role, meaning, visual, representation, children}, rest}:
      Equal.cong(Nat, Nat, (count => (1n + count : Nat)),
        List.length(&2, Doc.Node, Render.render_nodes(rest)),
        List.length(&2, Design.Node, rest), rendered_region_count(rest))


def render_children_preserves_sources(+values: +List<Design.Node>) ->
  {Render.sources(Render.render_children(values)) == values : +List<Design.Node>}:
  match values:
    case Nil{}: {==}
    case Con{+value, +rest}:
      Design.Node{key, semantic, label, role, meaning, visual, representation, children} = value
      Equal.cong(+List<Design.Node>, +List<Design.Node>, tail => value <> tail,
        Render.sources(Render.render_children(rest)), rest, render_children_preserves_sources(rest))


# This instance retains the complete observable conclusions for prepared inputs.














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



def creation_canvas_retains_regions(+canvas: Design.Box, +band: Design.Band, +flow: Design.CreationFlow, +children: +List<Doc.Node>) ->
  {Doc.element_children(first_node(Render.creation_canvas_nodes(canvas, band, flow, children))) ==
    [Render.creation_group(band, flow, children)] : +List<Doc.Node>}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

def root_theme_light() -> {Render.theme_name(Design.Light{}) == "light" : String}:
  {==}

def root_theme_dark() -> {Render.theme_name(Design.Dark{}) == "dark" : String}:
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
  {(Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual)), "data-native-key"),
      (Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual)), "data-card-id"),
       (Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual)), "data-card-title"),
       Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual)), "aria-label")))) ==
      card_root_face_expected(key, face) : (String & (String & (String & String)))}

def card_root_face_projection(+key: String, +face: View.CardFace, destinations: +List<Interface.Placement>,
  source: +List<Render.Child>, +visual: Design.Style) -> card_root_face_projection_law(key, face, destinations, source, visual):
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  {==}

def card_root_excludes_tab_target(+key: String, +face: View.CardFace, destinations: +List<Interface.Placement>,
  source: +List<Render.Child>, +visual: Design.Style) ->
  {Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual)), "tabindex") == "" : String}:
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  {==}

def card_face_status(+face: View.CardFace) -> String:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, owner, updated} = face
  status

def card_chip_text_slots(+key: String, +kind: String, +value: String, +tone: Surfaces.Tone) ->
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
  {direct_text_slots(Doc.element_children(Render.card_metadata(owner,
    View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated}, status_empty))) ==
    card_metadata_expected(View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated}, status_empty) : +List<String>}:
  match pinned status_empty:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def card_metadata_projection(+owner: String, +face: View.CardFace) ->
  {direct_text_slots(Doc.element_children(Render.card_metadata(owner, face, String.is_empty(card_face_status(face))))) ==
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
        Surfaces.Neutral{})]
      +tail = Render.card_label_nodes(owner, rest, Nat.add(index, 1n))
      +mapped_append = Std.map_app(~Doc.Node, ~String, ~direct_text, head, tail)
      +head_slots = card_chip_text_slots(Render.generated_identity(owner, "label/" ++ Nat.show(index)), "label",
        value, Surfaces.Neutral{})
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
  {direct_text_slots(Doc.element_children(first_node(Render.card_context_with_chips(owner, chips)))) ==
    direct_text_slots(chips) : +List<String>}:
  match chips:
    case Nil{}: {==}
    case Con{+first, +rest}: {==}

def card_context_projection(+owner: String, +project: String, +labels: +List<String>) ->
  {direct_text_slots(Doc.element_children(first_node(Render.card_context_nodes(owner, project, labels)))) ==
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
    direct_text_slots(Doc.element_children(first_node(Render.card_context_nodes(owner, project, labels)))),
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
  {direct_text_slots(Doc.element_children(first_node(Render.card_footer_with_items(owner, items)))) ==
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
  {direct_text_slots(Doc.element_children(first_node(Render.card_footer(owner, face)))) == card_footer_expected(face) : +List<String>}:
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
    direct_text_slots(Doc.element_children(first_node(Render.card_footer(owner, face)))),
    direct_text_slots(items),
    card_footer_expected(face),
    footer_slots, Equal.trans(+List<String>,
      direct_text_slots(items),
      List.append(&2, String, direct_text_slots(owner_items), direct_text_slots(updated_items)),
      card_footer_expected(face),
      mapped_append, replace_both))



def movable_card_events(+key: String, +face: View.CardFace, +destinations: +List<Interface.Placement>,
  source: +List<Render.Child>, +visual: Design.Style) ->
  {Doc.element_events(Render.card_node(key, face, destinations, source, visual)) ==
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

def rendered_dialog(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) -> Doc.Node:
  Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  Render.match_node(Design.Node{key, semantic, label, Interface.Dialog{}, Interface.Region{}, Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states}, Controls.NoControl{}, source}, Render.render_children(source))

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

def dialog_header_classified(+is_header: Bool, +child: Doc.Node, +header: +List<Doc.Node>, body: +List<Doc.Node>, layouts: +List<EditorLayout.SectionKind>, kind: EditorLayout.SectionKind) ->
  {Render.dialog_header_projection(Render.dialog_partition_child_by_header(child, is_header, header, body, layouts, kind)) == dialog_header_keep(is_header, child, header) : +List<Doc.Node>}:
  match is_header:
    case True{}: {==}
    case False{}: {==}

def dialog_body_classified(+is_header: Bool, +child: Doc.Node, header: +List<Doc.Node>, +body: +List<Doc.Node>, layouts: +List<EditorLayout.SectionKind>, kind: EditorLayout.SectionKind) ->
  {Render.dialog_body_projection(Render.dialog_partition_child_by_header(child, is_header, header, body, layouts, kind)) == dialog_body_keep(is_header, child, body) : +List<Doc.Node>}:
  match is_header:
    case True{}: {==}
    case False{}: {==}

def dialog_partition_header_step(+appearance: Render.Child, +parts: Render.DialogParts) ->
  {Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, parts)) == expected_dialog_header_prepend(appearance, Render.dialog_header_projection(parts)) : +List<Doc.Node>}:
  Render.Child{+source, +document} = appearance
  Design.Node{identity, semantic, label, role, meaning, visual, +representation, children} = source
  Render.DialogParts{header, body, layouts} = parts
  dialog_header_classified(Controls.panel_header(representation) || Render.persistent_details_header(representation), document, header, body, layouts, EditorLayout.appearance_kind(source))

def dialog_partition_body_step(+appearance: Render.Child, +parts: Render.DialogParts) ->
  {Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, parts)) == expected_dialog_body_prepend(appearance, Render.dialog_body_projection(parts)) : +List<Doc.Node>}:
  Render.Child{+source, +document} = appearance
  Design.Node{identity, semantic, label, role, meaning, visual, +representation, children} = source
  Render.DialogParts{header, body, layouts} = parts
  dialog_body_classified(Controls.panel_header(representation) || Render.persistent_details_header(representation), document, header, body, layouts, EditorLayout.appearance_kind(source))

def expected_dialog_header(children: +List<Render.Child>) -> +List<Doc.Node>:
  match children:
    case Con{child, rest}: expected_dialog_header_prepend(child, expected_dialog_header(rest))
    case Nil{}: Nil{}

def expected_dialog_body(children: +List<Render.Child>) -> +List<Doc.Node>:
  match children:
    case Con{child, rest}: expected_dialog_body_prepend(child, expected_dialog_body(rest))
    case Nil{}: Nil{}

def dialog_header_partition(children: +List<Render.Child>) ->
  {Render.dialog_header_children(children) == expected_dialog_header(children) : +List<Doc.Node>}:
  match children:
    case Con{+child, +rest}:
      Equal.trans(+List<Doc.Node>,
        Render.dialog_header_projection(Render.dialog_partition_prepend(child, Render.dialog_partition(rest))),
        expected_dialog_header_prepend(child, Render.dialog_header_projection(Render.dialog_partition(rest))),
        expected_dialog_header_prepend(child, expected_dialog_header(rest)),
        dialog_partition_header_step(child, Render.dialog_partition(rest)),
        Equal.cong(+List<Doc.Node>, +List<Doc.Node>, tail => expected_dialog_header_prepend(child, tail),
          Render.dialog_header_children(rest), expected_dialog_header(rest), dialog_header_partition(rest)))
    case Nil{}: {==}

def dialog_body_partition(children: +List<Render.Child>) ->
  {Render.dialog_body_children(children) == expected_dialog_body(children) : +List<Doc.Node>}:
  match children:
    case Con{+child, +rest}:
      Equal.trans(+List<Doc.Node>,
        Render.dialog_body_projection(Render.dialog_partition_prepend(child, Render.dialog_partition(rest))),
        expected_dialog_body_prepend(child, Render.dialog_body_projection(Render.dialog_partition(rest))),
        expected_dialog_body_prepend(child, expected_dialog_body(rest)),
        dialog_partition_body_step(child, Render.dialog_partition(rest)),
        Equal.cong(+List<Doc.Node>, +List<Doc.Node>, tail => expected_dialog_body_prepend(child, tail),
          Render.dialog_body_children(rest), expected_dialog_body(rest), dialog_body_partition(rest)))
    case Nil{}: {==}

def dialog_region_header_projection_suffix(+key: String, +label: String, visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {rest_nodes(Doc.element_children(dialog_header_node(Render.dialog_region_suffix(key, label, visual, header, suffix)))) ==
    header : +List<Doc.Node>}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_header_projection(+key: String, +label: String, visual: Design.Style,
  parts: Render.DialogParts) ->
  {rest_nodes(Doc.element_children(dialog_header_node(Render.dialog_region_parts(key, label, visual, parts)))) ==
    Render.dialog_header_projection(parts) : +List<Doc.Node>}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_header_projection_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_region_body_projection(+key: String, +label: String, visual: Design.Style,
  parts: Render.DialogParts) ->
  {DialogSpatial.original_children(Render.dialog_region_parts(key, label, visual, parts)) ==
    Render.dialog_body_projection(parts) : +List<Doc.Node>}:
  DialogSpatial.region_original_children(key, label, visual, parts)

def dialog_branch_header_projection(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {rest_nodes(Doc.element_children(dialog_header_node(rendered_dialog(key, semantic, label, source, visual)))) ==
    Render.dialog_header_children(Render.render_children(source)) : +List<Doc.Node>}:
  Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_header_projection(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))



def dialog_branch_body_projection(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {DialogSpatial.original_children(rendered_dialog(key, semantic, label, source, visual)) ==
    Render.dialog_body_children(Render.render_children(source)) : +List<Doc.Node>}:
  Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_body_projection(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))



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

def dialog_branch_wrapper_keys(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {(node_key(dialog_header_node(rendered_dialog(key, semantic, label, source, visual))),
    (node_key(dialog_body_node(rendered_dialog(key, semantic, label, source, visual))),
     node_key(dialog_content_node(rendered_dialog(key, semantic, label, source, visual))))) ==
   (Render.generated_identity(key, "dialog-header"),
    (Render.generated_identity(key, "dialog-body"), Render.generated_identity(key, "dialog-content"))) :
   (String & (String & String))}:
  Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_wrapper_keys(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))

def dialog_region_outer_identity_suffix(+key: String, +label: String, visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {(node_key(Render.dialog_region_suffix(key, label, visual, header, suffix)),
    (Render.attr(Doc.element_attributes(Render.dialog_region_suffix(key, label, visual, header, suffix)), "aria-label"),
     Render.attr(Doc.element_attributes(Render.dialog_region_suffix(key, label, visual, header, suffix)), "data-native-key"))) ==
   (key, (label, key)) : (String & (String & String))}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_outer_identity(+key: String, +label: String, visual: Design.Style,
  parts: Render.DialogParts) ->
  {(node_key(Render.dialog_region_parts(key, label, visual, parts)),
    (Render.attr(Doc.element_attributes(Render.dialog_region_parts(key, label, visual, parts)), "aria-label"),
     Render.attr(Doc.element_attributes(Render.dialog_region_parts(key, label, visual, parts)), "data-native-key"))) ==
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

def dialog_branch_outer_identity(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {(node_key(rendered_dialog(key, semantic, label, source, visual)),
    (Render.attr(Doc.element_attributes(rendered_dialog(key, semantic, label, source, visual)), "aria-label"),
     Render.attr(Doc.element_attributes(rendered_dialog(key, semantic, label, source, visual)), "data-native-key"))) ==
   (key, (label, key)) : (String & (String & String))}:
  Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_outer_identity(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))

def dialog_branch_title_identity(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {(node_key(dialog_title_node(rendered_dialog(key, semantic, label, source, visual))),
    direct_text(dialog_title_node(rendered_dialog(key, semantic, label, source, visual)))) ==
   (Render.generated_identity(key, "title"), label) : (String & String)}:
  Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_title_identity(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))

def dialog_region_flow_properties_suffix(+key: String, +label: String, visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {(Render.attr(Doc.element_styles(dialog_header_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "flex"),
    (Render.attr(Doc.element_styles(dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "flex"),
     (Render.attr(Doc.element_styles(dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "min-height"),
      (Render.attr(Doc.element_styles(dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "overflow"),
       (Render.attr(Doc.element_styles(dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "flex"),
        (Render.attr(Doc.element_styles(dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "height"),
         Render.attr(Doc.element_styles(dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix))), "max-height"))))))) ==
   ("0 0 auto", ("1 1 auto", ("0", ("auto", ("0 0 auto", ("", "")))))) :
   (String & (String & (String & (String & (String & (String & String))))))}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_flow_properties(+key: String, +label: String, visual: Design.Style,
  parts: Render.DialogParts) ->
  {(Render.attr(Doc.element_styles(dialog_header_node(Render.dialog_region_parts(key, label, visual, parts))), "flex"),
    (Render.attr(Doc.element_styles(dialog_body_node(Render.dialog_region_parts(key, label, visual, parts))), "flex"),
     (Render.attr(Doc.element_styles(dialog_body_node(Render.dialog_region_parts(key, label, visual, parts))), "min-height"),
      (Render.attr(Doc.element_styles(dialog_body_node(Render.dialog_region_parts(key, label, visual, parts))), "overflow"),
       (Render.attr(Doc.element_styles(dialog_content_node(Render.dialog_region_parts(key, label, visual, parts))), "flex"),
        (Render.attr(Doc.element_styles(dialog_content_node(Render.dialog_region_parts(key, label, visual, parts))), "height"),
         Render.attr(Doc.element_styles(dialog_content_node(Render.dialog_region_parts(key, label, visual, parts))), "max-height"))))))) ==
   ("0 0 auto", ("1 1 auto", ("0", ("auto", ("0 0 auto", ("", "")))))) :
   (String & (String & (String & (String & (String & (String & String))))))}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_flow_properties_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_flow_properties(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {(Render.attr(Doc.element_styles(dialog_header_node(rendered_dialog(key, semantic, label, source, visual))), "flex"),
    (Render.attr(Doc.element_styles(dialog_body_node(rendered_dialog(key, semantic, label, source, visual))), "flex"),
     (Render.attr(Doc.element_styles(dialog_body_node(rendered_dialog(key, semantic, label, source, visual))), "min-height"),
      (Render.attr(Doc.element_styles(dialog_body_node(rendered_dialog(key, semantic, label, source, visual))), "overflow"),
       (Render.attr(Doc.element_styles(dialog_content_node(rendered_dialog(key, semantic, label, source, visual))), "flex"),
        (Render.attr(Doc.element_styles(dialog_content_node(rendered_dialog(key, semantic, label, source, visual))), "height"),
         Render.attr(Doc.element_styles(dialog_content_node(rendered_dialog(key, semantic, label, source, visual))), "max-height"))))))) ==
   ("0 0 auto", ("1 1 auto", ("0", ("auto", ("0 0 auto", ("", "")))))) :
   (String & (String & (String & (String & (String & (String & String))))))}:
  Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_flow_properties(key, label,
    Design.Style{Design.TextStyle{family, size, line_height, weight}, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))

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
      {observed_box(first_node(Render.main_children(children, Design.CreationFrame{heading, canvas, band, input, flow}))) ==
          specified_box(canvas) : (String & (String & (String & String)))},
    unavailable_canvas: @+children:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band ->
      {observed_box(first_node(Render.main_children(children, Design.UnavailableFrame{heading, canvas, band}))) ==
          specified_box(canvas) : (String & (String & (String & String)))},
    rendered_region_count: @+values:+List<Design.Node> ->
      {List.length(&2, Doc.Node, Render.render_nodes(values)) ==
          List.length(&2, Design.Node, values) : Nat},
    render_children_preserves_sources: @+values:+List<Design.Node> ->
      {Render.sources(Render.render_children(values)) == values : +List<Design.Node>},
    creation_regions_keep_order: @+children:+List<Doc.Node> -> @+band:Design.Band -> @+flow:Design.CreationFlow ->
      {ShellSpatial.creation_region_children(Render.creation_regions(band, flow, Render.creation_partition(children))) == children : +List<Doc.Node>},
    creation_canvas_retains_regions: @+canvas:Design.Box -> @+band:Design.Band -> @+flow:Design.CreationFlow -> @+children:+List<Doc.Node> ->
      {Doc.element_children(first_node(Render.creation_canvas_nodes(canvas, band, flow, children))) == [Render.creation_group(band, flow, children)] : +List<Doc.Node>},
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
      @value:Forms.Observed -> @source:+List<Design.Node> -> @+visual:Design.Style -> @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.Edit{owner, field, Forms.DirectoryCollection{}, value}, visual, representation, source}, Render.render_children(source)) == Render.compound_field(key, label, field, visual, Render.render_nodes(source)) : Doc.Node},
    file_field_uses_compound: @+key:String -> @+semantic:String -> @+label:String -> @role:Interface.Role -> @owner:User.Editor -> @+field:Forms.Field ->
      @value:Forms.Observed -> @source:+List<Design.Node> -> @+visual:Design.Style -> @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.Edit{owner, field, Forms.FileCollection{}, value}, visual, representation, source}, Render.render_children(source)) == Render.compound_field(key, label, field, visual, Render.render_nodes(source)) : Doc.Node},
    board_group_properties: @+key:String -> @+grouping:Interface.BoardGrouping -> @+children:+List<Doc.Node> ->
      {(Render.attr(Doc.element_attributes(Render.board_group_node(key, grouping, children)), "data-native-key"),
          (Render.attr(Doc.element_attributes(Render.board_group_node(key, grouping, children)), "data-board-group"),
           (Render.attr(Doc.element_attributes(Render.board_group_node(key, grouping, children)), "role"),
            Render.attr(Doc.element_attributes(Render.board_group_node(key, grouping, children)), "aria-label")))) ==
          (key, (Render.board_group_name(grouping), ("group", Render.board_group_label(grouping)))) :
          (String & (String & (String & String)))},
    board_group_dispatch: @+key:String -> @+semantic:String -> @+label:String -> @role:Interface.Role -> @+grouping:Interface.BoardGrouping ->
      @source:+List<Design.Node> -> @+visual:Design.Style -> @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.BoardGroup{grouping}, visual, representation, source}, Render.render_children(source)) ==
        Render.board_group_node(key, grouping, Render.render_nodes(source)) : Doc.Node},
    board_lane_dispatch: @+key:String -> @+semantic:String -> @+label:String -> @role:Interface.Role -> @+stage:Board.Stage -> @+count:Nat ->
      @source:+List<Design.Node> -> @+visual:Design.Style -> @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.BoardLane{stage, count}, visual, representation, source}, Render.render_children(source)) ==
        Render.board_lane_node(key, label, stage, count, Render.render_children(source)) : Doc.Node},
    board_lane_projection: @+key:String -> @+label:String -> @+stage:Board.Stage -> @+count:Nat -> @source:+List<Render.Child> ->
      {(Render.attr(Doc.element_attributes(Render.board_lane_node(key, label, stage, count, source)), "data-native-key"),
          (Render.attr(Doc.element_attributes(Render.board_lane_node(key, label, stage, count, source)), "data-board-stage"),
           (Render.attr(Doc.element_attributes(Render.board_lane_node(key, label, stage, count, source)), "data-board-count"),
            Render.attr(Doc.element_attributes(Render.board_lane_node(key, label, stage, count, source)), "aria-label")))) ==
          (key, (Board.stage_name(stage), (Nat.show(count), label))) : (String & (String & (String & String)))},
    board_lane_count_projection: @+owner:String -> @+count:Nat ->
      {(Render.attr(Doc.element_attributes(Render.lane_count(owner, count)), "data-board-count"), direct_text(Render.lane_count(owner, count))) ==
        (Nat.show(count), Nat.show(count)) : (String & String)},
    board_lane_empty_projection: @+owner:String ->
      {(direct_texts(Render.empty_lane(0n, owner)),
          (List.length(&2, Doc.Node, Render.empty_lane(0n, owner)),
           List.length(&2, Doc.Node, Render.empty_lane(1n, owner)))) == ("暂无任务", (1n, 0n)) : (String & (Nat & Nat))},
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
    card_root_excludes_tab_target: @+key:String -> @+face:View.CardFace -> @destinations:+List<Interface.Placement> -> @source:+List<Render.Child> ->
      @+visual:Design.Style ->
      {Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual)), "tabindex") == "" : String},
    card_metadata_projection: @+owner:String -> @+face:View.CardFace ->
      {direct_text_slots(Doc.element_children(Render.card_metadata(owner, face, String.is_empty(card_face_status(face))))) ==
        card_metadata_expected(face, String.is_empty(card_face_status(face))) : +List<String>},
    card_description_projection: @+owner:String -> @+description:String ->
      {direct_text_slots(Render.card_description(owner, description)) == optional_text_slots(description) : +List<String>},
    card_context_projection: @+owner:String -> @+project:String -> @+labels:+List<String> ->
      {direct_text_slots(Doc.element_children(first_node(Render.card_context_nodes(owner, project, labels)))) ==
        List.append(&2, String, optional_text_slots(project), labels) : +List<String>},
    card_footer_projection: @+owner:String -> @+face:View.CardFace ->
      {direct_text_slots(Doc.element_children(first_node(Render.card_footer(owner, face)))) == card_footer_expected(face) : +List<String>},
    movable_card_dispatch: @+key:String -> @+semantic:String -> @+label:String -> @role:Interface.Role -> @destinations:+List<Interface.Placement> -> @+face:View.CardFace ->
      @source:+List<Design.Node> -> @+visual:Design.Style -> @representation:Controls.Representation ->
      {Render.match_node(Design.Node{key, semantic, label, role, Interface.MovableCard{destinations, face}, visual, representation, source}, Render.render_children(source)) ==
        Render.card_node(key, face, destinations, Render.render_children(source), visual) : Doc.Node},
    movable_card_events: @+key:String -> @+face:View.CardFace -> @destinations:+List<Interface.Placement> -> @source:+List<Render.Child> ->
      @+visual:Design.Style ->
      {Doc.element_events(Render.card_node(key, face, destinations, source, visual)) == [Doc.DragCard{key}, Doc.DropCard{key}] : +List<Doc.Event>},
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

def evidence() -> Requirements:
  Requirements{
    {==},
    current => {==},
    key => {==},
    +current => +key => {==},
    {==},
    {==},
    box => bounds_refinement(box),
    key => region => box => children => region_bounds(key, region, box, children),
    +key => +style => +input => +availability => +name => +face => +behavior => +geometry => +placement => +help => +feedback => {==},
    key => style => input => availability => name => face => behavior => geometry => placement => help => feedback => action_accessible_name(key, style, input, availability, name, face, behavior, geometry, placement, help, feedback),
    +key => {==},
    +key => {==},
    +key => +face => {==},
    children => heading => canvas => band => input => flow => creation_canvas(children, heading, canvas, band, input, flow),
    children => heading => canvas => band => unavailable_canvas(children, heading, canvas, band),
    values => rendered_region_count(values),
    values => render_children_preserves_sources(values),
    +children => +band => +flow => ShellSpatial.creation_regions_keep_order(children, band, flow),
    canvas => band => flow => children => creation_canvas_retains_regions(canvas, band, flow, children),
    heading => canvas => band => input => flow => {==},
    +key => +children => action_partition_order(children),
    {==},
    {==},
    +theme => {==},
    +theme => {==},
    +key => label => field => visual => +children => {==},
    key => label => field => visual => children => {==},
    key => label => field => visual => children => {==},
    +key => +semantic => +label => role => owner => +field => value => source => +visual => representation => {==},
    +key => +semantic => +label => role => owner => +field => value => source => +visual => representation =>
        {==}

      # These laws observe the document tree produced by the production renderer.
      # They constrain emitted content and ownership attributes, not browser layout.
    ,
    +key => +grouping => +children => {==},
    +key => +semantic => +label => role => +grouping => source => +visual => representation => {==},
    +key => +semantic => +label => role => +stage => +count => source => +visual => representation => {==},
    +key => +label => +stage => +count => source => {==},
    +owner => +count => {==},
    +owner => {==},
    +stage => {==},
    +key => +width => {==},
    +key => +width => +gap => +inset => {==},
    key => face => destinations => source => visual =>
      card_root_face_projection(key, face, destinations, source, visual),
    key => face => destinations => source => visual =>
      card_root_excludes_tab_target(key, face, destinations, source, visual),
    owner => face => card_metadata_projection(owner, face),
    +owner => +description => card_description_projection_when(String.is_empty(description), owner, description),
    owner => project => labels => card_context_projection(owner, project, labels),
    owner => face => card_footer_projection(owner, face),
    +key => +semantic => +label => role => +destinations => +face => source => +visual => representation => {==},
    key => face => destinations => source => visual =>
      movable_card_events(key, face, destinations, source, visual),
    +key => +semantic => +label => +source => +visual =>
      Equal.trans(+List<Doc.Node>,
        rest_nodes(Doc.element_children(dialog_header_node(rendered_dialog(key, semantic, label, source, visual)))),
        Render.dialog_header_children(Render.render_children(source)),
        expected_dialog_header(Render.render_children(source)),
        dialog_branch_header_projection(key, semantic, label, source, visual),
        dialog_header_partition(Render.render_children(source)))
    ,
    +key => +semantic => +label => +source => +visual =>
      Equal.trans(+List<Doc.Node>,
        DialogSpatial.original_children(rendered_dialog(key, semantic, label, source, visual)),
        Render.dialog_body_children(Render.render_children(source)),
        expected_dialog_body(Render.render_children(source)),
        dialog_branch_body_projection(key, semantic, label, source, visual),
        dialog_body_partition(Render.render_children(source)))
    ,
    key => semantic => label => source => visual =>
      dialog_branch_wrapper_keys(key, semantic, label, source, visual),
    key => semantic => label => source => visual =>
      dialog_branch_outer_identity(key, semantic, label, source, visual),
    key => semantic => label => source => visual =>
      dialog_branch_title_identity(key, semantic, label, source, visual),
    key => semantic => label => source => visual =>
      dialog_flow_properties(key, semantic, label, source, visual),
    available => maximum_width => centered_dialog_hides_overflow(available, maximum_width),
    anchor => available => maximum_width => maximum_height => gap =>
      anchored_popover_keeps_scroll(anchor, available, maximum_width, maximum_height, gap),
    anchor => available => maximum_width => maximum_height => gap =>
      anchored_popover_placement_styles(anchor, available, maximum_width, maximum_height, gap),
    anchor => available => maximum_width => maximum_height => gap =>
      anchored_popover_normal_alignment(anchor, available, maximum_width, maximum_height, gap),
    anchor => available => maximum_width => maximum_height => gap =>
      anchored_popover_content_height(anchor, available, maximum_width, maximum_height, gap),
    +filter => {==}
  }
