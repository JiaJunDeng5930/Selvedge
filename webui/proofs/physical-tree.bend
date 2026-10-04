import Base
import ../renderer.bend as R
import ../document.bend as Doc
import ../design.bend as D
import ../layout.bend as Layout
import ../../core/composition.bend as Composition
import ../../bendlib/stdlib.bend as Stdlib
import ../../core/interface.bend as UI

# The observation erases styles, retaining attributes, every content payload,
# event, key, portal target, and the complete ordered physical child tree.
import ../physical-tree-laws.bend as Rule

def structures_cons(+head: Doc.Node, +tail: +List<Doc.Node>) ->
  {Doc.structures(head <> tail) == Doc.structure(head) <> Doc.structures(tail) : +List<Doc.Node>}:
  match head:
    case Doc.Element{key, tag, attrs, styles, events, children}: {==}
    case Doc.Portal{key, target, children}: {==}
    case Doc.TargetProperties{key, target, attrs, styles}: {==}
    case Doc.Text{value}: {==}
    case Doc.Markdown{key, source, value}: {==}

def cons_preserved(+before: Doc.Node, +after: Doc.Node, +tail: +List<Doc.Node>, +remaining: +List<Doc.Node>,
  head_claim: {Doc.structure(after) == Doc.structure(before) : Doc.Node},
  tail_claim: {Doc.structures(remaining) == Doc.structures(tail) : +List<Doc.Node>}) ->
  {Doc.structures(after <> remaining) == Doc.structures(before <> tail) : +List<Doc.Node>}:
  Equal.trans(+List<Doc.Node>, Doc.structures(after <> remaining), Doc.structure(after) <> Doc.structures(remaining), Doc.structures(before <> tail),
    structures_cons(after, remaining),
    Equal.trans(+List<Doc.Node>, Doc.structure(after) <> Doc.structures(remaining), Doc.structure(before) <> Doc.structures(tail), Doc.structures(before <> tail),
      Equal.trans(+List<Doc.Node>, Doc.structure(after) <> Doc.structures(remaining), Doc.structure(before) <> Doc.structures(remaining), Doc.structure(before) <> Doc.structures(tail),
        Equal.cong(Doc.Node, +List<Doc.Node>, (head => head <> Doc.structures(remaining)), Doc.structure(after), Doc.structure(before), head_claim),
        Equal.cong(+List<Doc.Node>, +List<Doc.Node>, (rest => Doc.structure(before) <> rest), Doc.structures(remaining), Doc.structures(tail), tail_claim)),
      Equal.sym(+List<Doc.Node>, Doc.structures(before <> tail), Doc.structure(before) <> Doc.structures(tail), structures_cons(before, tail))))

def replace_styles_preserved(+node: Doc.Node, +styles: +List<Doc.Property>) ->
  {Doc.structure(R.replace_styles(node, styles)) == Doc.structure(node) : Doc.Node}:
  match node:
    case Doc.Element{key, tag, attrs, old, events, children}: {==}
    case Doc.Portal{key, target, children}: {==}
    case Doc.TargetProperties{key, target, attrs, old}: {==}
    case Doc.Text{value}: {==}
    case Doc.Markdown{key, source, value}: {==}

def board_column_cons(+head: Doc.Node, +tail: +List<Doc.Node>, +width: Nat,
  premise: {Doc.structures(R.board_columns(tail, width)) == Doc.structures(tail) : +List<Doc.Node>}) ->
  {Doc.structures(R.board_columns(head <> tail, width)) == Doc.structures(head <> tail) : +List<Doc.Node>}:
  +styles: +List<Doc.Property> = [R.property("width", R.px(width)), R.property("min-width", R.px(width)), R.property("flex", "0 0 auto"), R.property("height", "100%"), R.property("max-height", "100%"), R.property("min-height", "0"), R.property("align-self", "stretch")]
  cons_preserved(head, R.replace_styles(head, styles), tail, R.board_columns(tail, width), replace_styles_preserved(head, styles), premise)

def board_columns_preserved(+values: +List<Doc.Node>, +width: Nat) ->
  {Doc.structures(R.board_columns(values, width)) == Doc.structures(values) : +List<Doc.Node>}:
  Stdlib.list_ind(~Doc.Node,
    ~(items => @+width:Nat -> {Doc.structures(R.board_columns(items, width)) == Doc.structures(items) : +List<Doc.Node>}),
    ~(+width => {==}),
    ~(+head => +tail => premise => +width => board_column_cons(head, tail, width, premise(width))), values)(width)

def board_stage_preserved(+node: Doc.Node, +width: Nat, +gap: Nat, +inset: Nat) ->
  {Doc.structure(R.board_stage_region(node, width, gap, inset)) == Doc.structure(node) : Doc.Node}:
  match node:
    case Doc.Element{+key, +tag, +attrs, styles, +events, +children}:
      Equal.cong(+List<Doc.Node>, Doc.Node, (rest => Doc.Element{key, tag, attrs, Nil{}, events, rest}),
        Doc.structures(R.board_columns(children, width)), Doc.structures(children), board_columns_preserved(children, width))
    case Doc.Portal{key, target, children}: {==}
    case Doc.TargetProperties{key, target, attrs, styles}: {==}
    case Doc.Text{value}: {==}
    case Doc.Markdown{key, source, value}: {==}

def board_placement_preserved(+node: Doc.Node, +in_body: Bool, +frame: D.MainFrame) ->
  {Doc.structure(R.place_board_stage(in_body, node, frame)) == Doc.structure(node) : Doc.Node}:
  match in_body frame:
    case True{} D.BoardFrame{canvas, width, gap, inset}: board_stage_preserved(node, width, gap, inset)
    case False{} _: {==}
    case True{} D.CreationFrame{heading, canvas, band, input, flow}: {==}
    case True{} D.ConversationFrame{heading, viewport, reading, dock}: {==}
    case True{} D.OverviewFrame{canvas, band, organization}: {==}
    case True{} D.UnavailableFrame{heading, canvas, band}: {==}

def element_preserved(+key: String, +tag: String, +attrs: +List<Doc.Property>, +styles: +List<Doc.Property>, +events: +List<Doc.Event>,
  +before: +List<Doc.Node>, +after: +List<Doc.Node>, +frame: D.MainFrame,
  claim: {Doc.structures(after) == Doc.structures(before) : +List<Doc.Node>}) ->
  {Doc.structure(R.place_element(key, tag, attrs, styles, events, after, frame)) == Doc.structure(Doc.Element{key, tag, attrs, styles, events, before}) : Doc.Node}:
  Equal.cong(+List<Doc.Node>, Doc.Node, (children => Doc.Element{key, tag, attrs, Nil{}, events, children}), Doc.structures(after), Doc.structures(before), claim)

def children_preserved(+values: +List<Doc.Node>, +in_body: Bool, +frame: D.MainFrame) ->
  {Doc.structures(R.place_children(values, in_body, frame)) == Doc.structures(values) : +List<Doc.Node>}:
  match values:
    case Nil{}: {==}
    case Con{Doc.Element{+key, +tag, +attrs, +styles, +events, +children}, +tail}:
      +placed = R.place_element(key, tag, attrs, styles, events, R.place_children(children, String.eq(key, "board-body"), frame), frame)
      cons_preserved(Doc.Element{key, tag, attrs, styles, events, children}, R.place_board_stage(in_body, placed, frame), tail, R.place_children(tail, in_body, frame),
        Equal.trans(Doc.Node, Doc.structure(R.place_board_stage(in_body, placed, frame)), Doc.structure(placed), Doc.structure(Doc.Element{key, tag, attrs, styles, events, children}),
          board_placement_preserved(placed, in_body, frame),
          element_preserved(key, tag, attrs, styles, events, children, R.place_children(children, String.eq(key, "board-body"), frame), frame, children_preserved(children, String.eq(key, "board-body"), frame))),
        children_preserved(tail, in_body, frame))
    case Con{Doc.Portal{+key, +target, +children}, +tail}:
      cons_preserved(Doc.Portal{key, target, children}, Doc.Portal{key, target, R.place_children(children, False{}, frame)}, tail, R.place_children(tail, in_body, frame),
        Equal.cong(+List<Doc.Node>, Doc.Node, (rest => Doc.Portal{key, target, rest}), Doc.structures(R.place_children(children, False{}, frame)), Doc.structures(children), children_preserved(children, False{}, frame)), children_preserved(tail, in_body, frame))
    case Con{Doc.TargetProperties{+key, +target, +attrs, +styles}, +tail}: cons_preserved(Doc.TargetProperties{key, target, attrs, styles}, Doc.TargetProperties{key, target, attrs, styles}, tail, R.place_children(tail, in_body, frame), {==}, children_preserved(tail, in_body, frame))
    case Con{Doc.Text{+value}, +tail}: cons_preserved(Doc.Text{value}, Doc.Text{value}, tail, R.place_children(tail, in_body, frame), {==}, children_preserved(tail, in_body, frame))
    case Con{Doc.Markdown{+key, +source, +value}, +tail}: cons_preserved(Doc.Markdown{key, source, value}, Doc.Markdown{key, source, value}, tail, R.place_children(tail, in_body, frame), {==}, children_preserved(tail, in_body, frame))

def tree_preserved(+value: Doc.Node, +frame: D.MainFrame) ->
  {Doc.structure(R.place_tree(value, frame)) == Doc.structure(value) : Doc.Node}:
  match value:
    case Doc.Element{+key, +tag, +attrs, +styles, +events, +children}:
      element_preserved(key, tag, attrs, styles, events, children, R.place_children(children, String.eq(key, "board-body"), frame), frame, children_preserved(children, String.eq(key, "board-body"), frame))
    case Doc.Portal{+key, +target, +children}:
      Equal.cong(+List<Doc.Node>, Doc.Node, (rest => Doc.Portal{key, target, rest}), Doc.structures(R.place_children(children, False{}, frame)), Doc.structures(children), children_preserved(children, False{}, frame))
    case Doc.TargetProperties{key, target, attrs, styles}: {==}
    case Doc.Text{value}: {==}
    case Doc.Markdown{key, source, value}: {==}

def placement_children_preserved(+values: +List<Doc.Node>, +placements: +List<D.NodePlacement>) ->
  {Doc.structures(R.apply_placement_children(values, placements)) == Doc.structures(values) : +List<Doc.Node>}:
  match values:
    case Nil{}: {==}
    case Con{Doc.Element{+key, +tag, +attrs, +styles, +events, +children}, +tail}:
      cons_preserved(Doc.Element{key, tag, attrs, styles, events, children},
        Doc.Element{key, tag, attrs, List.append(&2, Doc.Property, styles, R.node_placement_styles(key, placements)), events, R.apply_placement_children(children, placements)},
        tail, R.apply_placement_children(tail, placements),
        Equal.cong(+List<Doc.Node>, Doc.Node, (rest => Doc.Element{key, tag, attrs, Nil{}, events, rest}),
          Doc.structures(R.apply_placement_children(children, placements)), Doc.structures(children), placement_children_preserved(children, placements)),
        placement_children_preserved(tail, placements))
    case Con{Doc.Portal{+key, +target, +children}, +tail}:
      cons_preserved(Doc.Portal{key, target, children}, Doc.Portal{key, target, R.apply_placement_children(children, placements)},
        tail, R.apply_placement_children(tail, placements),
        Equal.cong(+List<Doc.Node>, Doc.Node, (rest => Doc.Portal{key, target, rest}),
          Doc.structures(R.apply_placement_children(children, placements)), Doc.structures(children), placement_children_preserved(children, placements)),
        placement_children_preserved(tail, placements))
    case Con{Doc.TargetProperties{+key, +target, +attrs, +styles}, +tail}:
      cons_preserved(Doc.TargetProperties{key, target, attrs, styles}, Doc.TargetProperties{key, target, attrs, styles}, tail, R.apply_placement_children(tail, placements), {==}, placement_children_preserved(tail, placements))
    case Con{Doc.Text{+value}, +tail}:
      cons_preserved(Doc.Text{value}, Doc.Text{value}, tail, R.apply_placement_children(tail, placements), {==}, placement_children_preserved(tail, placements))
    case Con{Doc.Markdown{+key, +source, +value}, +tail}:
      cons_preserved(Doc.Markdown{key, source, value}, Doc.Markdown{key, source, value}, tail, R.apply_placement_children(tail, placements), {==}, placement_children_preserved(tail, placements))

def placements_preserved(+value: Doc.Node, +placements: +List<D.NodePlacement>) ->
  {Doc.structure(R.apply_placements(value, placements)) == Doc.structure(value) : Doc.Node}:
  match value:
    case Doc.Element{+key, +tag, +attrs, styles, +events, +children}:
      Equal.cong(+List<Doc.Node>, Doc.Node, (rest => Doc.Element{key, tag, attrs, Nil{}, events, rest}),
        Doc.structures(R.apply_placement_children(children, placements)), Doc.structures(children), placement_children_preserved(children, placements))
    case Doc.Portal{+key, +target, +children}:
      Equal.cong(+List<Doc.Node>, Doc.Node, (rest => Doc.Portal{key, target, rest}),
        Doc.structures(R.apply_placement_children(children, placements)), Doc.structures(children), placement_children_preserved(children, placements))
    case Doc.TargetProperties{key, target, attrs, styles}: {==}
    case Doc.Text{value}: {==}
    case Doc.Markdown{key, source, value}: {==}

def shell_preserved(+role: UI.Role, +value: Doc.Node, +shell: D.Shell) ->
  {Doc.structure(R.place_base_shell_node(role, value, shell)) == Doc.structure(value) : Doc.Node}:
  replace_styles_preserved(value, R.base_shell_styles(role, shell))

def base_node_preserved(+value: D.Node, +document: Doc.Node, +layout: D.Layout) ->
  {Doc.structure(R.place_base_node(value, document, layout)) == Doc.structure(document) : Doc.Node}:
  D.Node{key, semantic, label, +role, meaning, visual, representation, children} = value
  D.Layout{viewport, +shell, +frame, placements, parameters, +controls} = layout
  +placed = R.place_base_shell_node(role, R.place_tree(document, frame), shell)
  Equal.trans(Doc.Node, Doc.structure(R.apply_placements(placed, controls)), Doc.structure(placed), Doc.structure(document),
    placements_preserved(placed, controls),
    Equal.trans(Doc.Node, Doc.structure(placed), Doc.structure(R.place_tree(document, frame)), Doc.structure(document),
      shell_preserved(role, R.place_tree(document, frame), shell), tree_preserved(document, frame)))

def base_preserved(+values: +List<D.Node>, +documents: +List<Doc.Node>, +layout: D.Layout) ->
  {Doc.structures(R.place_base(values, documents, layout)) == Doc.structures(documents) : +List<Doc.Node>}:
  match values documents:
    case Con{+value, +rest} Con{+document, +remaining}:
      cons_preserved(document, R.place_base_node(value, document, layout), remaining, R.place_base(rest, remaining, layout), base_node_preserved(value, document, layout), base_preserved(rest, remaining, layout))
    case Nil{} Nil{}: {==}
    case Nil{} Con{document, remaining}: {==}
    case Con{value, rest} Nil{}: {==}

def overlays_preserved(+values: +List<D.Node>, +placements: +List<D.Overlay>, +documents: +List<Doc.Node>) ->
  {Doc.structures(R.place_overlays(values, placements, documents)) == Doc.structures(documents) : +List<Doc.Node>}:
  match values placements documents:
    case Con{value, +rest} Con{D.Overlay{key, +level, +placement}, +remaining} Con{+document, +cached}:
      +styles = List.append(&2, Doc.Property, R.overlay_styles(placement), [R.property("z-index", Nat.show(Nat.add(50n, level)))])
      cons_preserved(document, R.replace_styles(document, styles), cached, R.place_overlays(rest, remaining, cached), replace_styles_preserved(document, styles), overlays_preserved(rest, remaining, cached))
    case Nil{} Nil{} Nil{}: {==}
    case Nil{} Nil{} Con{document, cached}: {==}
    case Nil{} Con{D.Overlay{key, level, placement}, remaining} Nil{}: {==}
    case Nil{} Con{D.Overlay{key, level, placement}, remaining} Con{document, cached}: {==}
    case Con{value, rest} Nil{} Nil{}: {==}
    case Con{value, rest} Nil{} Con{document, cached}: {==}
    case Con{value, rest} Con{D.Overlay{key, level, placement}, remaining} Nil{}: {==}

# The shared application constructor fixes the root, theme target and base scope.
# Its two varying lists are related by the production placement proofs above.
def application_preserved(+theme: D.Theme, +active: Maybe<&2, String>,
  +base: +List<Doc.Node>, +placed_base: +List<Doc.Node>,
  +overlays: +List<Doc.Node>, +placed_overlays: +List<Doc.Node>,
  base_claim: {Doc.structures(placed_base) == Doc.structures(base) : +List<Doc.Node>},
  overlay_claim: {Doc.structures(placed_overlays) == Doc.structures(overlays) : +List<Doc.Node>}) ->
  {Doc.document_structure(R.application_document(theme, active, placed_base, placed_overlays)) == Doc.document_structure(R.application_document(theme, active, base, overlays)) : Doc.Document}:
  +before_scope = R.base_scope(active, base)
  +after_scope = R.base_scope(active, placed_base)
  scope_claim = Equal.cong(+List<Doc.Node>, Doc.Node,
    (children => Doc.Element{"application-base", "div", R.background_properties(active), Nil{}, Nil{}, children}),
    Doc.structures(placed_base), Doc.structures(base), base_claim)
  children_claim = cons_preserved(R.document_theme(theme), R.document_theme(theme),
    before_scope <> overlays, after_scope <> placed_overlays, {==},
    cons_preserved(before_scope, after_scope, overlays, placed_overlays, scope_claim, overlay_claim))
  Equal.cong(+List<Doc.Node>, Doc.Document,
    (children => Doc.Document{Doc.Element{"application", "div", [R.property("data-document", "application"), R.property("class", R.theme_class(theme))], Nil{}, Nil{}, children}, "Selvedge"}),
    Doc.structures(R.document_theme(theme) <> (after_scope <> placed_overlays)),
    Doc.structures(R.document_theme(theme) <> (before_scope <> overlays)), children_claim)

def placed_structure(+prepared: D.PreparedSurface, +layout: D.Layout) ->
  {Doc.document_structure(R.place(prepared, layout)) == Doc.document_structure(R.prepared_document(prepared)) : Doc.Document}:
  D.PreparedSurface{D.Surface{content, +theme, +base, +overlays, +active}, +cached_base, +cached_overlays} = prepared
  D.Layout{viewport, shell, main, +placements, parameters, controls} = layout
  application_preserved(theme, active, cached_base, R.place_base(base, cached_base, layout),
    cached_overlays, R.place_overlays(overlays, placements, cached_overlays),
    base_preserved(base, cached_base, layout), overlays_preserved(overlays, placements, cached_overlays))

# This projection observes the real source field, independently of cached nodes.
def prepared_identity(+surface: D.Surface) -> {Rule.source(R.prepare(surface)) == surface : D.Surface}:
  D.Surface{content, theme, base, overlays, active} = surface
  {==}

def allocated_structure(+structure: D.MainStructure, +parameters: D.LayoutParameters, +recipe: Composition.Recipe, +main: D.Box) ->
  {D.frame_structure(Layout.main_frame_structure(structure, parameters, recipe, main)) == structure : D.MainStructure}:
  match structure recipe:
    case D.CreationStructure{} Composition.Recipe{measure, heading, body, composer, decisions, latest}: {==}
    case D.ConversationStructure{} Composition.Recipe{measure, heading, body, composer, decisions, latest}: {==}
    case D.OverviewStructure{organization} Composition.Recipe{measure, heading, body, composer, decisions, latest}: {==}
    case D.BoardStructure{} Composition.Recipe{measure, heading, body, composer, decisions, latest}: {==}
    case D.UnavailableStructure{} Composition.Recipe{measure, heading, body, composer, decisions, latest}: {==}

def main_structure(+parameters: D.LayoutParameters, +recipe: Composition.Recipe, +main: D.Box) ->
  {D.frame_structure(Layout.main_frame(parameters, recipe, main)) == D.main_structure(recipe) : D.MainStructure}:
  allocated_structure(D.main_structure(recipe), parameters, recipe, main)

def Rule.evidence():
  Rule.Requirements{placements_preserved, placed_structure, prepared_identity, main_structure}
