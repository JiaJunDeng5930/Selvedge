import ../../core/interface.bend as Interface
import Base
import ../typography.bend as T
import ../../bendlib/stdlib.bend as Std
import ../document.bend as Doc
import ../renderer.bend as Render
import ../dialog-spatial-laws.bend as DialogSpatial
import ../editor-layout.bend as EditorLayout
import ../design.bend as Design
import ../surfaces.bend as Surfaces
import ../controls.bend as Controls
import ../../core/SYSTEM.bend as Core
import ../../core/ui-world.bend as View
import ../../core/user-conversation.bend as Conversation
import ../../BOARD.bend as Board

# These observations read the actual browser primitives, independently of the
# renderer's construction functions. Missing geometry is the empty observation.
import ../renderer-laws.bend as Rule
import ./dialog-spatial.bend as Proof_dialog_spatial
import ./shell-spatial.bend as Proof_shell_spatial

def bounds_refinement(box: Design.Box) ->
  {Rule.css_box(Render.bounds(box)) == Rule.specified_box(box) : (String & (String & (String & String)))}:
  Design.Box{left, top, width, height} = box
  {==}

def region_bounds(+key: String, +region: String, +box: Design.Box, +children: +List<Doc.Node>) ->
  {Rule.observed_box(Render.replace_styles(Doc.Element{key, "div", [Doc.Property{"data-region", region}], Nil{}, Nil{}, children}, Render.bounds(box))) == Rule.specified_box(box) : (String & (String & (String & String)))}:
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







def creation_canvas(+children: +List<Doc.Node>, +heading: Design.Box, +canvas: Design.Box,
  +band: Design.Band, +input: Maybe<&2, Design.InputMetrics>, +flow: Design.CreationFlow) ->
  {Rule.observed_box(Rule.first_node(Render.place_children(Render.prepare_main_children(children, Design.CreationStructure{}, None{}), False{}, Design.CreationFrame{heading, canvas, band, input, flow}))) ==
    Rule.specified_box(canvas) : (String & (String & (String & String)))}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

def unavailable_canvas(+children: +List<Doc.Node>, +heading: Design.Box, +canvas: Design.Box, +band: Design.Band) ->
  {Rule.observed_box(Rule.first_node(Render.place_children(Render.prepare_main_children(children, Design.UnavailableStructure{}, None{}), False{}, Design.UnavailableFrame{heading, canvas, band}))) ==
    Rule.specified_box(canvas) : (String & (String & (String & String)))}:
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














def creation_canvas_retains_regions(+canvas: Design.Box, +band: Design.Band, +flow: Design.CreationFlow, +children: +List<Doc.Node>) ->
  {Doc.element_children(Rule.first_node(Render.prepare_creation(children))) ==
    [Doc.Element{"creation-group", "div", [Doc.Property{"data-region", "creation-group"}], List.append(&2, Doc.Property, Render.intrinsic_creation_band(), [Doc.Property{"flex", "0 0 auto"}]), Nil{}, Render.prepare_creation_regions(Render.creation_partition(children))}] : +List<Doc.Node>}:
  match canvas:
    case Design.Box{left, top, width, height}: {==}

def action_partition_order(+children: +List<Doc.Node>) ->
  {List.append(&2, Doc.Node, Render.action_leading(children), Render.action_trailing(children)) == children : +List<Doc.Node>}:
  match children:
    case Nil{}: {==}
    case Con{last, Nil{}}: {==}
    case Con{+first, Con{+second, +rest}}:
      Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (tail => first <> tail),
        List.append(&2, Doc.Node, Render.action_leading(second <> rest), Render.action_trailing(second <> rest)), second <> rest,
        action_partition_order(second <> rest))





def card_root_face_projection(+key: String, +face: View.CardFace, destinations: +List<Interface.Placement>,
  source: +List<Render.Child>, +visual: Design.Style) -> Rule.card_root_face_projection_law(key, face, destinations, source, visual):
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  {==}

def card_root_excludes_tab_target(+key: String, +face: View.CardFace, destinations: +List<Interface.Placement>,
  source: +List<Render.Child>, +visual: Design.Style, +typography: T.Presentation) ->
  {Render.attr(Doc.element_attributes(Render.card_node(key, face, destinations, source, visual, typography)), "tabindex") == "" : String}:
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  {==}

def card_chip_text_slots(+key: String, +kind: String, +value: String, +tone: Surfaces.Tone, +typography: T.Presentation) ->
  {Rule.direct_text_slots([Render.card_chip(key, kind, value, tone, typography)]) == [value] : +List<String>}:
  {==}

def card_metadata_projection_when(+owner: String, +id: Nat, +title: String, +description: String,
  +priority: Board.Priority, pinned: Bool, +status: String, +project: String,
  +labels: +List<String>, +card_owner: String, +updated: String, status_empty: Bool, +typography: T.Presentation) ->
  {Rule.direct_text_slots(Doc.element_children(Render.card_metadata(owner,
    View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated}, status_empty, typography))) ==
    Rule.card_metadata_expected(View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated}, status_empty) : +List<String>}:
  match pinned status_empty:
    case True{} True{}: {==}
    case True{} False{}: {==}
    case False{} True{}: {==}
    case False{} False{}: {==}

def card_metadata_projection(+owner: String, +face: View.CardFace, +typography: T.Presentation) ->
  {Rule.direct_text_slots(Doc.element_children(Render.card_metadata(owner, face, String.is_empty(Rule.card_face_status(face)), typography))) ==
    Rule.card_metadata_expected(face, String.is_empty(Rule.card_face_status(face))) : +List<String>}:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated} = face
  card_metadata_projection_when(owner, id, title, description, priority, pinned, status, project,
    labels, card_owner, updated, String.is_empty(status), typography)

def card_description_projection_when(empty: Bool, +owner: String, +description: String, +typography: T.Presentation) ->
  {Rule.direct_text_slots(Render.card_description_when(empty, owner, description, typography)) ==
    Rule.optional_text_slots_when(empty, description) : +List<String>}:
  match empty:
    case True{}: {==}
    case False{}: {==}



def card_project_slots_when(empty: Bool, +owner: String, +project: String, +typography: T.Presentation) ->
  {Rule.direct_text_slots(Render.card_project_nodes_when(empty, owner, project, typography)) ==
    Rule.optional_text_slots_when(empty, project) : +List<String>}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def card_project_slots(+owner: String, +project: String, +typography: T.Presentation) ->
  {Rule.direct_text_slots(Render.card_project_nodes(owner, project, typography)) == Rule.optional_text_slots(project) : +List<String>}:
  card_project_slots_when(String.is_empty(project), owner, project, typography)

def card_label_slots(+owner: String, +labels: +List<String>, +index: Nat, +typography: T.Presentation) ->
  {Rule.direct_text_slots(Render.card_label_nodes(owner, labels, index, typography)) == labels : +List<String>}:
  match labels:
    case Nil{}: {==}
    case Con{+value, +rest}:
      +head: +List<Doc.Node> = [Render.card_chip(Render.generated_identity(owner, "label/" ++ Nat.show(index)), "label", value,
        Surfaces.Neutral{}, typography)]
      +tail = Render.card_label_nodes(owner, rest, Nat.add(index, 1n), typography)
      +mapped_append = Std.map_app(~Doc.Node, ~String, ~Rule.direct_text, head, tail)
      +head_slots = card_chip_text_slots(Render.generated_identity(owner, "label/" ++ Nat.show(index)), "label",
        value, Surfaces.Neutral{}, typography)
      +tail_slots = card_label_slots(owner, rest, Nat.add(index, 1n), typography)
      +replace_tail = Equal.cong(+List<String>, +List<String>,
        (slots => List.append(&2, String, Rule.direct_text_slots(head), slots)),
        Rule.direct_text_slots(tail), rest, tail_slots)
      +replace_head = Equal.cong(+List<String>, +List<String>,
        (slots => List.append(&2, String, slots, rest)),
        Rule.direct_text_slots(head), [value], head_slots)
      Equal.trans(+List<String>,
        Rule.direct_text_slots(Render.card_label_nodes(owner, labels, index, typography)),
        List.append(&2, String, Rule.direct_text_slots(head), Rule.direct_text_slots(tail)),
        List.append(&2, String, [value], rest),
        mapped_append, Equal.trans(+List<String>,
          List.append(&2, String, Rule.direct_text_slots(head), Rule.direct_text_slots(tail)),
          List.append(&2, String, Rule.direct_text_slots(head), rest),
          List.append(&2, String, [value], rest),
          replace_tail, replace_head))

def card_context_with_chips_slots(+owner: String, +chips: +List<Doc.Node>) ->
  {Rule.direct_text_slots(Doc.element_children(Rule.first_node(Render.card_context_with_chips(owner, chips)))) ==
    Rule.direct_text_slots(chips) : +List<String>}:
  match chips:
    case Nil{}: {==}
    case Con{+first, +rest}: {==}

def card_context_projection(+owner: String, +project: String, +labels: +List<String>, +typography: T.Presentation) ->
  {Rule.direct_text_slots(Doc.element_children(Rule.first_node(Render.card_context_nodes(owner, project, labels, typography)))) ==
    List.append(&2, String, Rule.optional_text_slots(project), labels) : +List<String>}:
  +project_nodes = Render.card_project_nodes(owner, project, typography)
  +label_nodes = Render.card_label_nodes(owner, labels, 0n, typography)
  +chips = List.append(&2, Doc.Node, project_nodes, label_nodes)
  +context_slots = card_context_with_chips_slots(owner, chips)
  +mapped_append = Std.map_app(~Doc.Node, ~String, ~Rule.direct_text, project_nodes, label_nodes)
  +project_slots = card_project_slots(owner, project, typography)
  +label_slots = card_label_slots(owner, labels, 0n, typography)
  +replace_project = Equal.cong(+List<String>, +List<String>,
    (slots => List.append(&2, String, slots, Rule.direct_text_slots(label_nodes))),
    Rule.direct_text_slots(project_nodes), Rule.optional_text_slots(project), project_slots)
  +replace_labels = Equal.cong(+List<String>, +List<String>,
    (slots => List.append(&2, String, Rule.optional_text_slots(project), slots)),
    Rule.direct_text_slots(label_nodes), labels, label_slots)
  +replace_both = Equal.trans(+List<String>,
    List.append(&2, String, Rule.direct_text_slots(project_nodes), Rule.direct_text_slots(label_nodes)),
    List.append(&2, String, Rule.optional_text_slots(project), Rule.direct_text_slots(label_nodes)),
    List.append(&2, String, Rule.optional_text_slots(project), labels),
    replace_project, replace_labels)
  Equal.trans(+List<String>,
    Rule.direct_text_slots(Doc.element_children(Rule.first_node(Render.card_context_nodes(owner, project, labels, typography)))),
    Rule.direct_text_slots(chips),
    List.append(&2, String, Rule.optional_text_slots(project), labels),
    context_slots, Equal.trans(+List<String>,
      Rule.direct_text_slots(chips),
      List.append(&2, String, Rule.direct_text_slots(project_nodes), Rule.direct_text_slots(label_nodes)),
      List.append(&2, String, Rule.optional_text_slots(project), labels),
      mapped_append, replace_both))

def card_footer_item_slots_when(empty: Bool, +owner: String, +part: String, +kind: String, +value: String) ->
  {Rule.direct_text_slots(Render.card_footer_item_when(empty, owner, part, kind, value)) ==
    Rule.optional_text_slots_when(empty, value) : +List<String>}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def card_footer_item_slots(+owner: String, +part: String, +kind: String, +value: String) ->
  {Rule.direct_text_slots(Render.card_footer_item(owner, part, kind, value)) == Rule.optional_text_slots(value) : +List<String>}:
  card_footer_item_slots_when(String.is_empty(value), owner, part, kind, value)

def card_footer_with_items_slots(+owner: String, +items: +List<Doc.Node>, +typography: T.Presentation) ->
  {Rule.direct_text_slots(Doc.element_children(Rule.first_node(Render.card_footer_with_items(owner, items, typography)))) ==
    Rule.direct_text_slots(items) : +List<String>}:
  match items:
    case Nil{}: {==}
    case Con{+first, +rest}: {==}

def card_timestamp_slots_when(empty: Bool, +owner: String, +value: String) ->
  {Rule.direct_text_slots(Render.card_timestamp_items(Render.card_footer_item_when(empty, owner, "updated", "updated", value))) ==
    Rule.optional_text_slots_when(empty, value) : +List<String>}:
  match empty:
    case True{}: {==}
    case False{}: {==}

def card_timestamp_slots(+owner: String, +value: String) ->
  {Rule.direct_text_slots(Render.card_timestamp_items(Render.card_footer_item(owner, "updated", "updated", value))) ==
    Rule.optional_text_slots(value) : +List<String>}:
  card_timestamp_slots_when(String.is_empty(value), owner, value)

def card_footer_projection(+owner: String, +face: View.CardFace, +typography: T.Presentation) ->
  {Rule.direct_text_slots(Doc.element_children(Rule.first_node(Render.card_footer(owner, face, typography)))) == Rule.card_footer_expected(face) : +List<String>}:
  View.CardFace{id, title, description, priority, pinned, status, project, labels, card_owner, updated} = face
  +owner_items = Render.card_footer_item(owner, "owner", "owner", card_owner)
  +updated_items = Render.card_timestamp_items(Render.card_footer_item(owner, "updated", "updated", updated))
  +items = List.append(&2, Doc.Node, owner_items, updated_items)
  +footer_slots = card_footer_with_items_slots(owner, items, typography)
  +mapped_append = Std.map_app(~Doc.Node, ~String, ~Rule.direct_text, owner_items, updated_items)
  +owner_slots = card_footer_item_slots(owner, "owner", "owner", card_owner)
  +updated_slots = card_timestamp_slots(owner, updated)
  +replace_owner = Equal.cong(+List<String>, +List<String>,
    (slots => List.append(&2, String, slots, Rule.direct_text_slots(updated_items))),
    Rule.direct_text_slots(owner_items), Rule.optional_text_slots(card_owner), owner_slots)
  +replace_updated = Equal.cong(+List<String>, +List<String>,
    (slots => List.append(&2, String, Rule.optional_text_slots(card_owner), slots)),
    Rule.direct_text_slots(updated_items), Rule.optional_text_slots(updated), updated_slots)
  +replace_both = Equal.trans(+List<String>,
    List.append(&2, String, Rule.direct_text_slots(owner_items), Rule.direct_text_slots(updated_items)),
    List.append(&2, String, Rule.optional_text_slots(card_owner), Rule.direct_text_slots(updated_items)),
    List.append(&2, String, Rule.optional_text_slots(card_owner), Rule.optional_text_slots(updated)),
    replace_owner, replace_updated)
  Equal.trans(+List<String>,
    Rule.direct_text_slots(Doc.element_children(Rule.first_node(Render.card_footer(owner, face, typography)))),
    Rule.direct_text_slots(items),
    Rule.card_footer_expected(face),
    footer_slots, Equal.trans(+List<String>,
      Rule.direct_text_slots(items),
      List.append(&2, String, Rule.direct_text_slots(owner_items), Rule.direct_text_slots(updated_items)),
      Rule.card_footer_expected(face),
      mapped_append, replace_both))



def movable_card_events(+key: String, +face: View.CardFace, +destinations: +List<Interface.Placement>,
  source: +List<Render.Child>, +visual: Design.Style, +typography: T.Presentation) ->
  {Doc.element_events(Render.card_node(key, face, destinations, source, visual, typography)) ==
    [Doc.DragCard{key}, Doc.DropCard{key}] : +List<Doc.Event>}:
  View.CardFace{+id, +title, +description, +priority, +pinned, +status, +project, +labels, +owner, +updated} = face
  {==}

def dialog_header_classified(+is_header: Bool, +child: Doc.Node, +header: +List<Doc.Node>, body: +List<Doc.Node>, layouts: +List<EditorLayout.SectionKind>, kind: EditorLayout.SectionKind) ->
  {Render.dialog_header_projection(Render.dialog_partition_child_by_header(child, is_header, header, body, layouts, kind)) == Rule.dialog_header_keep(is_header, child, header) : +List<Doc.Node>}:
  match is_header:
    case True{}: {==}
    case False{}: {==}

def dialog_body_classified(+is_header: Bool, +child: Doc.Node, header: +List<Doc.Node>, +body: +List<Doc.Node>, layouts: +List<EditorLayout.SectionKind>, kind: EditorLayout.SectionKind) ->
  {Render.dialog_body_projection(Render.dialog_partition_child_by_header(child, is_header, header, body, layouts, kind)) == Rule.dialog_body_keep(is_header, child, body) : +List<Doc.Node>}:
  match is_header:
    case True{}: {==}
    case False{}: {==}

def dialog_partition_header_step(+appearance: Render.Child, +parts: Render.DialogParts) ->
  {Render.dialog_header_projection(Render.dialog_partition_prepend(appearance, parts)) == Rule.expected_dialog_header_prepend(appearance, Render.dialog_header_projection(parts)) : +List<Doc.Node>}:
  Render.Child{+source, +document} = appearance
  Design.Node{identity, semantic, label, role, meaning, visual, +representation, children} = source
  Render.DialogParts{header, body, layouts} = parts
  dialog_header_classified(Controls.panel_header(representation) || Render.persistent_details_header(representation), document, header, body, layouts, EditorLayout.appearance_kind(source))

def dialog_partition_body_step(+appearance: Render.Child, +parts: Render.DialogParts) ->
  {Render.dialog_body_projection(Render.dialog_partition_prepend(appearance, parts)) == Rule.expected_dialog_body_prepend(appearance, Render.dialog_body_projection(parts)) : +List<Doc.Node>}:
  Render.Child{+source, +document} = appearance
  Design.Node{identity, semantic, label, role, meaning, visual, +representation, children} = source
  Render.DialogParts{header, body, layouts} = parts
  dialog_body_classified(Controls.panel_header(representation) || Render.persistent_details_header(representation), document, header, body, layouts, EditorLayout.appearance_kind(source))

def dialog_header_partition(children: +List<Render.Child>) ->
  {Render.dialog_header_children(children) == Rule.expected_dialog_header(children) : +List<Doc.Node>}:
  match children:
    case Con{+child, +rest}:
      Equal.trans(+List<Doc.Node>,
        Render.dialog_header_projection(Render.dialog_partition_prepend(child, Render.dialog_partition(rest))),
        Rule.expected_dialog_header_prepend(child, Render.dialog_header_projection(Render.dialog_partition(rest))),
        Rule.expected_dialog_header_prepend(child, Rule.expected_dialog_header(rest)),
        dialog_partition_header_step(child, Render.dialog_partition(rest)),
        Equal.cong(+List<Doc.Node>, +List<Doc.Node>, tail => Rule.expected_dialog_header_prepend(child, tail),
          Render.dialog_header_children(rest), Rule.expected_dialog_header(rest), dialog_header_partition(rest)))
    case Nil{}: {==}

def dialog_body_partition(children: +List<Render.Child>) ->
  {Render.dialog_body_children(children) == Rule.expected_dialog_body(children) : +List<Doc.Node>}:
  match children:
    case Con{+child, +rest}:
      Equal.trans(+List<Doc.Node>,
        Render.dialog_body_projection(Render.dialog_partition_prepend(child, Render.dialog_partition(rest))),
        Rule.expected_dialog_body_prepend(child, Render.dialog_body_projection(Render.dialog_partition(rest))),
        Rule.expected_dialog_body_prepend(child, Rule.expected_dialog_body(rest)),
        dialog_partition_body_step(child, Render.dialog_partition(rest)),
        Equal.cong(+List<Doc.Node>, +List<Doc.Node>, tail => Rule.expected_dialog_body_prepend(child, tail),
          Render.dialog_body_children(rest), Rule.expected_dialog_body(rest), dialog_body_partition(rest)))
    case Nil{}: {==}

def dialog_region_header_projection_suffix(+key: String, +label: String, +visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {Rule.rest_nodes(Doc.element_children(Rule.dialog_header_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual))))) ==
    header : +List<Doc.Node>}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_header_projection(+key: String, +label: String, +visual: Design.Style,
  parts: Render.DialogParts) ->
  {Rule.rest_nodes(Doc.element_children(Rule.dialog_header_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual))))) ==
    Render.dialog_header_projection(parts) : +List<Doc.Node>}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_header_projection_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_region_body_projection(+key: String, +label: String, +visual: Design.Style,
  parts: Render.DialogParts) ->
  {DialogSpatial.original_children(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual))) ==
    Render.dialog_body_projection(parts) : +List<Doc.Node>}:
  Proof_dialog_spatial.region_original_children(key, label, visual, parts, Design.style_text(visual))

def dialog_branch_header_projection(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {Rule.rest_nodes(Doc.element_children(Rule.dialog_header_node(Rule.rendered_dialog(key, semantic, label, source, visual)))) ==
    Render.dialog_header_children(Render.render_children(source)) : +List<Doc.Node>}:
  Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_header_projection(key, label,
    Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))



def dialog_branch_body_projection(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {DialogSpatial.original_children(Rule.rendered_dialog(key, semantic, label, source, visual)) ==
    Render.dialog_body_children(Render.render_children(source)) : +List<Doc.Node>}:
  Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_body_projection(key, label,
    Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))



def dialog_region_wrapper_keys_suffix(+key: String, +label: String, +visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {(Rule.node_key(Rule.dialog_header_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))),
    (Rule.node_key(Rule.dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))),
     Rule.node_key(Rule.dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))))) ==
   (Render.generated_identity(key, "dialog-header"),
    (Render.generated_identity(key, "dialog-body"), Render.generated_identity(key, "dialog-content"))) :
   (String & (String & String))}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_wrapper_keys(+key: String, +label: String, +visual: Design.Style,
  parts: Render.DialogParts) ->
  {(Rule.node_key(Rule.dialog_header_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))),
    (Rule.node_key(Rule.dialog_body_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))),
     Rule.node_key(Rule.dialog_content_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))))) ==
   (Render.generated_identity(key, "dialog-header"),
    (Render.generated_identity(key, "dialog-body"), Render.generated_identity(key, "dialog-content"))) :
   (String & (String & String))}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_wrapper_keys_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_branch_wrapper_keys(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {(Rule.node_key(Rule.dialog_header_node(Rule.rendered_dialog(key, semantic, label, source, visual))),
    (Rule.node_key(Rule.dialog_body_node(Rule.rendered_dialog(key, semantic, label, source, visual))),
     Rule.node_key(Rule.dialog_content_node(Rule.rendered_dialog(key, semantic, label, source, visual))))) ==
   (Render.generated_identity(key, "dialog-header"),
    (Render.generated_identity(key, "dialog-body"), Render.generated_identity(key, "dialog-content"))) :
   (String & (String & String))}:
  Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_wrapper_keys(key, label,
    Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))

def dialog_region_outer_identity_suffix(+key: String, +label: String, +visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {(Rule.node_key(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual))),
    (Render.attr(Doc.element_attributes(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual))), "aria-label"),
     Render.attr(Doc.element_attributes(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual))), "data-native-key"))) ==
   (key, (label, key)) : (String & (String & String))}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_outer_identity(+key: String, +label: String, +visual: Design.Style,
  parts: Render.DialogParts) ->
  {(Rule.node_key(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual))),
    (Render.attr(Doc.element_attributes(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual))), "aria-label"),
     Render.attr(Doc.element_attributes(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual))), "data-native-key"))) ==
   (key, (label, key)) : (String & (String & String))}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_outer_identity_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_region_title_identity_suffix(+key: String, +label: String, +visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {(Rule.node_key(Rule.dialog_title_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))),
    Rule.direct_text(Rule.dialog_title_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual))))) ==
   (Render.generated_identity(key, "title"), label) : (String & String)}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_title_identity(+key: String, +label: String, +visual: Design.Style,
  parts: Render.DialogParts) ->
  {(Rule.node_key(Rule.dialog_title_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))),
    Rule.direct_text(Rule.dialog_title_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual))))) ==
   (Render.generated_identity(key, "title"), label) : (String & String)}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_title_identity_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_branch_outer_identity(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {(Rule.node_key(Rule.rendered_dialog(key, semantic, label, source, visual)),
    (Render.attr(Doc.element_attributes(Rule.rendered_dialog(key, semantic, label, source, visual)), "aria-label"),
     Render.attr(Doc.element_attributes(Rule.rendered_dialog(key, semantic, label, source, visual)), "data-native-key"))) ==
   (key, (label, key)) : (String & (String & String))}:
  Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_outer_identity(key, label,
    Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))

def dialog_branch_title_identity(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {(Rule.node_key(Rule.dialog_title_node(Rule.rendered_dialog(key, semantic, label, source, visual))),
    Rule.direct_text(Rule.dialog_title_node(Rule.rendered_dialog(key, semantic, label, source, visual)))) ==
   (Render.generated_identity(key, "title"), label) : (String & String)}:
  Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_title_identity(key, label,
    Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
    Render.dialog_partition(Render.render_children(source)))

def dialog_region_flow_properties_suffix(+key: String, +label: String, +visual: Design.Style,
  +header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {(Render.attr(Doc.element_styles(Rule.dialog_header_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))), "flex"),
    (Render.attr(Doc.element_styles(Rule.dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))), "flex"),
     (Render.attr(Doc.element_styles(Rule.dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))), "min-height"),
      (Render.attr(Doc.element_styles(Rule.dialog_body_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))), "overflow"),
       (Render.attr(Doc.element_styles(Rule.dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))), "flex"),
        (Render.attr(Doc.element_styles(Rule.dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))), "height"),
         Render.attr(Doc.element_styles(Rule.dialog_content_node(Render.dialog_region_suffix(key, label, visual, header, suffix, Design.style_text(visual)))), "max-height"))))))) ==
   ("0 0 auto", ("1 1 auto", ("0", ("auto", ("0 0 auto", ("", "")))))) :
   (String & (String & (String & (String & (String & (String & String))))))}:
  match suffix:
    case EditorLayout.Suffix{+body, +footer}: {==}

def dialog_region_flow_properties(+key: String, +label: String, +visual: Design.Style,
  parts: Render.DialogParts) ->
  {(Render.attr(Doc.element_styles(Rule.dialog_header_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))), "flex"),
    (Render.attr(Doc.element_styles(Rule.dialog_body_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))), "flex"),
     (Render.attr(Doc.element_styles(Rule.dialog_body_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))), "min-height"),
      (Render.attr(Doc.element_styles(Rule.dialog_body_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))), "overflow"),
       (Render.attr(Doc.element_styles(Rule.dialog_content_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))), "flex"),
        (Render.attr(Doc.element_styles(Rule.dialog_content_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))), "height"),
         Render.attr(Doc.element_styles(Rule.dialog_content_node(Render.dialog_region_parts(key, label, visual, parts, Design.style_text(visual)))), "max-height"))))))) ==
   ("0 0 auto", ("1 1 auto", ("0", ("auto", ("0 0 auto", ("", "")))))) :
   (String & (String & (String & (String & (String & (String & String))))))}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_region_flow_properties_suffix(key, label, visual, header, EditorLayout.split(body, layouts))

def dialog_flow_properties(+key: String, +semantic: String, +label: String, +source: +List<Design.Node>,
  +visual: Design.Style) ->
  {(Render.attr(Doc.element_styles(Rule.dialog_header_node(Rule.rendered_dialog(key, semantic, label, source, visual))), "flex"),
    (Render.attr(Doc.element_styles(Rule.dialog_body_node(Rule.rendered_dialog(key, semantic, label, source, visual))), "flex"),
     (Render.attr(Doc.element_styles(Rule.dialog_body_node(Rule.rendered_dialog(key, semantic, label, source, visual))), "min-height"),
      (Render.attr(Doc.element_styles(Rule.dialog_body_node(Rule.rendered_dialog(key, semantic, label, source, visual))), "overflow"),
       (Render.attr(Doc.element_styles(Rule.dialog_content_node(Rule.rendered_dialog(key, semantic, label, source, visual))), "flex"),
        (Render.attr(Doc.element_styles(Rule.dialog_content_node(Rule.rendered_dialog(key, semantic, label, source, visual))), "height"),
         Render.attr(Doc.element_styles(Rule.dialog_content_node(Rule.rendered_dialog(key, semantic, label, source, visual))), "max-height"))))))) ==
   ("0 0 auto", ("1 1 auto", ("0", ("auto", ("0 0 auto", ("", "")))))) :
   (String & (String & (String & (String & (String & (String & String))))))}:
  Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, +content_frame, minimum, maximum, states} = visual
  dialog_region_flow_properties(key, label,
    Design.Style{typography, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, direction, overflow, content_frame, minimum, maximum, states},
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


def anchored_popover_placement_styles(+anchor: String, +available: Design.Box,
  +maximum_width: Nat, +maximum_height: Nat, +gap: Nat) ->
  {Render.overlay_styles(Design.AnchoredPopover{anchor, available, maximum_width, maximum_height, gap}) ==
    Rule.expected_popover_styles(anchor, available, maximum_width, maximum_height, gap) : +List<Doc.Property>}:
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



def last_override(first: +List<Doc.Property>, +suffix: +List<Doc.Property>, +name: String,
  previous: String, +result: String,
  overrides: @prior:String -> {Render.attr_last(suffix, name, prior) == result : String}) ->
  {Render.attr_last(List.append(&2, Doc.Property, first, suffix), name, previous) == result : String}:
  match first:
    case Nil{}: overrides(previous)
    case Con{Doc.Property{key, value}, rest}:
      last_override(rest, suffix, name, Render.attr_found(String.eq(key, name), value, previous), result, overrides)

def actual_font_bridge(+value: Design.Style) ->
  {Render.attr(Render.style(value), "font-family") == T.font_family(T.resolved_font(T.resolved(Design.style_text(value)))) : String} &
  {Render.attr(Render.style(value), "font-size") == Render.px(T.resolved_size(T.resolved(Design.style_text(value)))) : String} &
  {Render.attr(Render.style(value), "line-height") == Render.px(T.resolved_line_height(T.resolved(Design.style_text(value)))) : String} &
  {Render.attr(Render.style(value), "font-weight") == Nat.show(T.resolved_weight(T.resolved(Design.style_text(value)))) : String}:
  +text = Design.style_text(value)
  (last_override(Render.style_rest(value), Render.text_presentation(text), "font-family", "", T.font_family(T.resolved_font(T.resolved(text))), prior => {==}),
   last_override(Render.style_rest(value), Render.text_presentation(text), "font-size", "", Render.px(T.resolved_size(T.resolved(text))), prior => {==}),
   last_override(Render.style_rest(value), Render.text_presentation(text), "line-height", "", Render.px(T.resolved_line_height(T.resolved(text))), prior => {==}),
   last_override(Render.style_rest(value), Render.text_presentation(text), "font-weight", "", Nat.show(T.resolved_weight(T.resolved(text))), prior => {==}))

# NOTE: Only shallow production placement supplies wrapper styles; descendant
# traversal stays explicit in the complete expected document.
def conversation_children_identity(+children: +List<Doc.Node>, +heading: Design.Box, +viewport: Design.Box, +reading: Design.Band, +dock: Maybe<&2, Design.Dock>, +identity: Maybe<&2, Conversation.Identity>) ->
  {Render.place_children(Render.prepare_conversation(children, identity), False{}, Design.ConversationFrame{heading, viewport, reading, dock}) == Rule.expected_conversation(children, heading, viewport, reading, dock, identity) : +List<Doc.Node>}:
  match identity:
    case None{}: {==}
    case Some{Conversation.Identity{task, generation}}: {==}

def Rule.evidence():
  Rule.Requirements{actual_font_bridge,
    key => {==},
    +key => +value => label => choices => {==},
    +key => semantic => +label => role => expanded => audit => +visual => representation => +source => {==},
    +task => generation => key => tag => attrs => styles => events => children => {==},
    +task => generation => key => tag => attrs => styles => events => children => {==},
    +children => +heading => +viewport => +reading => +dock => +identity => conversation_children_identity(children, heading, viewport, reading, dock, identity),
    +parameters => +key => +semantic => +label => +role => +identity => +visual => +representation => +source => shell => main => controls => {==},
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
    +children => +band => +flow => Proof_shell_spatial.creation_regions_keep_order(children, band, flow),
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
    +key => +semantic => +label => role => owner => +field => value => choices => source => +visual => representation => {==},
    +key => +semantic => +label => role => owner => +field => value => choices => source => +visual => representation =>
        {==}

      # These laws observe the document tree produced by the production renderer.
      # They constrain emitted content and ownership attributes, not browser layout.
    ,
    +typography => +key => +grouping => +children => {==},
    +key => +semantic => +label => role => +grouping => source => +visual => representation => {==},
    +key => +semantic => +label => role => +stage => +count => source => +visual => representation => {==},
    +typography => +key => +label => +stage => +count => source => {==},
    +typography => +owner => +count => {==},
    +typography => +owner => {==},
    +stage => {==},
    +key => +width => {==},
    +key => +width => +gap => +inset => {==},
    key => face => destinations => source => visual =>
      card_root_face_projection(key, face, destinations, source, visual),
    +typography => key => face => destinations => source => visual =>
      card_root_excludes_tab_target(key, face, destinations, source, visual, typography),
    +typography => owner => face => card_metadata_projection(owner, face, typography),
    +typography => +owner => +description => card_description_projection_when(String.is_empty(description), owner, description, typography),
    +typography => owner => project => labels => card_context_projection(owner, project, labels, typography),
    +typography => owner => face => card_footer_projection(owner, face, typography),
    +key => +semantic => +label => role => +destinations => +face => source => +visual => representation => {==},
    +typography => key => face => destinations => source => visual =>
      movable_card_events(key, face, destinations, source, visual, typography),
    +key => +semantic => +label => +source => +visual =>
      Equal.trans(+List<Doc.Node>,
        Rule.rest_nodes(Doc.element_children(Rule.dialog_header_node(Rule.rendered_dialog(key, semantic, label, source, visual)))),
        Render.dialog_header_children(Render.render_children(source)),
        Rule.expected_dialog_header(Render.render_children(source)),
        dialog_branch_header_projection(key, semantic, label, source, visual),
        dialog_header_partition(Render.render_children(source)))
    ,
    +key => +semantic => +label => +source => +visual =>
      Equal.trans(+List<Doc.Node>,
        DialogSpatial.original_children(Rule.rendered_dialog(key, semantic, label, source, visual)),
        Render.dialog_body_children(Render.render_children(source)),
        Rule.expected_dialog_body(Render.render_children(source)),
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
