import ./shell-spatial.bend as ShellSpatialProof
import Base
import ../page-region-laws.bend as Rule
import ../../core/composition.bend as Composition
import ../../core/interface.bend as UI
import ../../core/ui-world.bend as View
import ../../core/user-context.bend as Context
import ../../bendlib/domain.bend as Domain
import ../document.bend as Doc
import ../renderer.bend as Render
import ../shell-spatial-laws.bend as ShellSpatial
import ../editor-layout.bend as EditorLayout
import ../design.bend as Design
import ../controls.bend as Controls
import ../../bendlib/stdlib.bend as Stdlib
def region_partition(+key: String, +region: Composition.Region, +position: Composition.Position,
  +values: +List<Doc.Node>, +rest: +List<Doc.Node>) ->
  {Rule.partition(Render.page_region(key, region, position, values) <> rest) ==
    Rule.prescribed_cons(position, Render.page_region(key, region, position, values), rest) : (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>))}:
  match position:
    case Composition.HeadingPosition{}: {==}
    case Composition.BodyPosition{}: {==}
    case Composition.DockPosition{}: {==}

def overview_organization(+nodes: +List<Doc.Node>, +organization: Composition.Body) ->
  {Render.attr(Doc.element_attributes(Rule.second(Render.overview_children(nodes, organization))), "data-overview-organization") ==
    Rule.specified_organization(organization) : String}:
  match organization:
    case Composition.CenteredCreation{}: {==}
    case Composition.ChronologicalReading{}: {==}
    case Composition.ProjectSections{}: {==}
    case Composition.ProjectRows{}: {==}
    case Composition.StageColumns{}: {==}
    case Composition.AgentRows{}: {==}
    case Composition.UnavailableNotice{}: {==}

# Only the explicit conversation body owns reading observation. A nested old
# timeline element retains its DOM key without acquiring a second scroller.

def overview_main_partition(+nodes: +List<Doc.Node>, +canvas: Design.Box, +band: Design.Band, +organization: Composition.Body) ->
  {Rule.groups(Doc.element_children(Rule.first(Render.prepare_main_children(nodes, Design.frame_structure(Design.OverviewFrame{canvas, band, organization}), None{})))) == Rule.partition(nodes) : (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>))}:
  Design.Box{left, top, width, height} = canvas
  Design.Band{band_left, band_width} = band
  {==}

def overview_main_flow(+nodes: +List<Doc.Node>, +canvas: Design.Box, +band: Design.Band, +organization: Composition.Body) ->
  {Rule.group_flow(Doc.element_children(Rule.first(Render.prepare_main_children(nodes, Design.frame_structure(Design.OverviewFrame{canvas, band, organization}), None{})))) ==
    (("none", "wrap"), ("1", ("0", "auto"))) : ((String & String) & (String & (String & String)))}:
  Design.Box{left, top, width, height} = canvas
  Design.Band{band_left, band_width} = band
  match organization:
    case Composition.CenteredCreation{}: {==}
    case Composition.ChronologicalReading{}: {==}
    case Composition.ProjectSections{}: {==}
    case Composition.ProjectRows{}: {==}
    case Composition.StageColumns{}: {==}
    case Composition.AgentRows{}: {==}
    case Composition.UnavailableNotice{}: {==}

def board_main_flow(+nodes: +List<Doc.Node>, +canvas: Design.Box, +width: Nat, +gap: Nat, +inset: Nat) ->
  {Rule.group_flow(Doc.element_children(Rule.first(Render.prepare_main_children(nodes, Design.frame_structure(Design.BoardFrame{canvas, width, gap, inset}), None{})))) ==
    (("none", "wrap"), ("1", ("0", "hidden"))) : ((String & String) & (String & (String & String)))}:
  Design.Box{left, top, canvas_width, height} = canvas
  {==}

def title_payload_preserved(+node: Doc.Node) ->
  {Rule.payload(Render.conversation_title_node(node)) == Rule.payload(node) : Rule.ChildPayload}:
  match node:
    case Doc.Element{+key, +tag, +attrs, +styles, +events, +children}:
      actual = ShellSpatialProof.title_node_identity(key, tag, attrs, styles, events, children)
      %actual : {Rule.payload(_) == Rule.payload(Doc.Element{key, tag, attrs, styles, events, children}) : Rule.ChildPayload}
      {==}
    case Doc.Text{value}: {==}
    case Doc.Markdown{key, source, value}: {==}
    case Doc.Portal{key, target, children}: {==}
    case Doc.TargetProperties{key, target, attrs, styles}: {==}

def title_payloads_nil() ->
  {Rule.payloads(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_title_node, Nil{})) == Rule.payloads(Nil{}) : +List<Rule.ChildPayload>}:
  {==}

def title_payloads_cons(+node: Doc.Node, +rest: +List<Doc.Node>,
  premise: {Rule.payloads(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_title_node, rest)) == Rule.payloads(rest) : +List<Rule.ChildPayload>}) ->
  {Rule.payloads(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_title_node, node <> rest)) == Rule.payloads(node <> rest) : +List<Rule.ChildPayload>}:
  changed_head = Equal.cong(Rule.ChildPayload, +List<Rule.ChildPayload>,
    (head => head <> Rule.payloads(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_title_node, rest))),
    Rule.payload(Render.conversation_title_node(node)), Rule.payload(node), title_payload_preserved(node))
  changed_tail = Equal.cong(+List<Rule.ChildPayload>, +List<Rule.ChildPayload>, (tail => Rule.payload(node) <> tail),
    Rule.payloads(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_title_node, rest)), Rule.payloads(rest), premise)
  Equal.trans(+List<Rule.ChildPayload>, Rule.payloads(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_title_node, node <> rest)),
    Rule.payload(node) <> Rule.payloads(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_title_node, rest)), Rule.payloads(node <> rest),
    changed_head, changed_tail)

def title_payloads_preserved(nodes: +List<Doc.Node>) ->
  {Rule.payloads(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_title_node, nodes)) == Rule.payloads(nodes) : +List<Rule.ChildPayload>}:
  Stdlib.list_ind(~Doc.Node,
    ~(values => {Rule.payloads(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_title_node, values)) == Rule.payloads(values) : +List<Rule.ChildPayload>}),
    ~title_payloads_nil(), ~(node => rest => premise => title_payloads_cons(node, rest, premise)), nodes)

def heading_receipt_by_title(styled: Bool, +key: String, +tag: String, +attrs: +List<Doc.Property>,
  +styles_value: +List<Doc.Property>, +events: +List<Doc.Event>, +nodes: +List<Doc.Node>) ->
  {Rule.receipt(Render.conversation_heading_region_by_title(styled, key, tag, attrs, styles_value, events, nodes)) ==
    Rule.receipt(Doc.Element{key, tag, attrs, styles_value, events, nodes}) : Rule.RegionReceipt}:
  match styled:
    case False{}: {==}
    case True{}:
      Equal.cong(+List<Rule.ChildPayload>, Rule.RegionReceipt,
        (values => Rule.RegionReceipt{key, Render.attr(attrs, "data-page-region"), Render.attr(attrs, "data-page-position"), values}),
        Rule.payloads(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_title_node, nodes)), Rule.payloads(nodes), title_payloads_preserved(nodes))

def heading_receipt_preserved(+node: Doc.Node) ->
  {Rule.receipt(Render.conversation_heading_region(node)) == Rule.receipt(node) : Rule.RegionReceipt}:
  match node:
    case Doc.Element{+key, +tag, +attrs, +styles_value, +events, +nodes}:
      heading_receipt_by_title(String.eq(Render.attr(attrs, "data-page-region"), Composition.region_name(Composition.ConversationTitle{})),
        key, tag, attrs, styles_value, events, nodes)
    case Doc.Text{value}: {==}
    case Doc.Markdown{key, source, value}: {==}
    case Doc.Portal{key, target, children}: {==}
    case Doc.TargetProperties{key, target, attrs, styles}: {==}

def heading_receipts_nil() ->
  {Rule.receipts(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_heading_region, Nil{})) == Rule.receipts(Nil{}) : +List<Rule.RegionReceipt>}:
  {==}

def heading_receipts_cons(+node: Doc.Node, +rest: +List<Doc.Node>,
  premise: {Rule.receipts(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_heading_region, rest)) == Rule.receipts(rest) : +List<Rule.RegionReceipt>}) ->
  {Rule.receipts(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_heading_region, node <> rest)) == Rule.receipts(node <> rest) : +List<Rule.RegionReceipt>}:
  changed_head = Equal.cong(Rule.RegionReceipt, +List<Rule.RegionReceipt>,
    (head => head <> Rule.receipts(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_heading_region, rest))),
    Rule.receipt(Render.conversation_heading_region(node)), Rule.receipt(node), heading_receipt_preserved(node))
  changed_tail = Equal.cong(+List<Rule.RegionReceipt>, +List<Rule.RegionReceipt>, (tail => Rule.receipt(node) <> tail),
    Rule.receipts(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_heading_region, rest)), Rule.receipts(rest), premise)
  Equal.trans(+List<Rule.RegionReceipt>, Rule.receipts(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_heading_region, node <> rest)),
    Rule.receipt(node) <> Rule.receipts(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_heading_region, rest)), Rule.receipts(node <> rest), changed_head, changed_tail)

def board_region_preservation(+nodes: +List<Doc.Node>, +canvas: Design.Box, +width: Nat, +gap: Nat, +inset: Nat) ->
  {Rule.receipt_partition(Rule.groups(Doc.element_children(Rule.first(Render.prepare_main_children(nodes, Design.frame_structure(Design.BoardFrame{canvas, width, gap, inset}), None{}))))) ==
    Rule.receipt_partition(Rule.partition(nodes)) : (+List<Rule.RegionReceipt> & (+List<Rule.RegionReceipt> & +List<Rule.RegionReceipt>))}:
  Design.Box{left, top, canvas_width, height} = canvas
  {==}

def creation_region_preservation(+nodes: +List<Doc.Node>, +heading: Design.Box, +canvas: Design.Box,
  +band: Design.Band, +input: Maybe<&2, Design.InputMetrics>, +flow: Design.CreationFlow) ->
  {ShellSpatial.creation_canvas_children(Rule.first(Render.prepare_main_children(nodes, Design.frame_structure(Design.CreationFrame{heading, canvas, band, input, flow}), None{}))) == nodes : +List<Doc.Node>}:
  Design.Box{left, top, width, height} = canvas
  ShellSpatialProof.creation_group_order(nodes, band, flow)

def unavailable_region_preservation(+nodes: +List<Doc.Node>, +heading: Design.Box, +canvas: Design.Box, +band: Design.Band) ->
  {Doc.element_children(Rule.first(Render.prepare_main_children(nodes, Design.frame_structure(Design.UnavailableFrame{heading, canvas, band}), None{}))) == nodes : +List<Doc.Node>}:
  Design.Box{left, top, width, height} = canvas
  {==}

def typed_section_content(+owner: String, +label: String, +visual: Design.Style,
  +rendered: +List<Doc.Node>, +kind: EditorLayout.SectionKind) ->
  {(Doc.element_children(Render.editor_section(owner, label, visual, rendered, kind, Design.style_text(visual))),
    Render.attr(Doc.element_attributes(Render.editor_section(owner, label, visual, rendered, kind, Design.style_text(visual))), "aria-label")) ==
   (Rule.expected_section_children(kind, owner, label, rendered, Design.style_text(visual)), label) : (+List<Doc.Node> & String)}:
  match kind:
    case EditorLayout.GenericSection{}: {==}
    case EditorLayout.WorkSection{}: {==}
    case EditorLayout.MetadataSection{}: {==}
    case EditorLayout.CaptureSection{}: {==}
    case EditorLayout.SubmitAction{}: {==}

def dialog_suffix_title_owner(+owner: String, +label: String, +visual: Design.Style,
  header: +List<Doc.Node>, suffix: EditorLayout.Suffix) ->
  {Rule.node_key(Rule.first(Doc.element_children(Rule.first(Doc.element_children(Render.dialog_region_suffix(owner, label, visual, header, suffix, Design.style_text(visual))))))) ==
    Render.generated_identity(owner, "title") : String}:
  match suffix:
    case EditorLayout.Suffix{body, footer}: {==}

def dialog_region_title_owner(+owner: String, +label: String, +visual: Design.Style,
  parts: Render.DialogParts) ->
  {Rule.node_key(Rule.first(Doc.element_children(Rule.first(Doc.element_children(Render.dialog_region_parts(owner, label, visual, parts, Design.style_text(visual))))))) ==
    Render.generated_identity(owner, "title") : String}:
  match parts:
    case Render.DialogParts{+header, +body, +layouts}:
      dialog_suffix_title_owner(owner, label, visual, header, EditorLayout.split(body, layouts))

def task_facts_owner(+owner: String, semantic: String, +details: View.TaskDetails, label: String, role: UI.Role,
  +source_children: +List<Render.Child>, visual: Design.Style,
  representation: Controls.Representation) ->
  {Rule.observed_facts(Doc.element_children(Rule.first(Doc.element_children(Render.match_node(Design.Node{owner, semantic, label, role, UI.TaskFacts{details}, visual, representation, Render.sources(source_children)}, source_children))))) == Rule.specified_task_facts(owner, details) : +List<Rule.FactObservation>}:
  View.TaskDetails{Context.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy}, reasoning, model_guidance}, tools, lineage, queued, status, phase} = details
  {==}

def Rule.evidence():
  Rule.Requirements{+owner => +part => {==}, +owner => semantic => +label => +source_children => +visual => representation => nonempty => generic =>
      Equal.trans(String,
        Rule.node_key(Rule.first(Doc.element_children(Render.editor_section(owner, label, visual, Render.documents(source_children), EditorLayout.section_kind(Render.sources(source_children)), Design.style_text(visual))))),
        Rule.node_key(Rule.first(Doc.element_children(Render.editor_section(owner, label, visual, Render.documents(source_children), EditorLayout.GenericSection{}, Design.style_text(visual))))),
        Render.generated_identity(owner, "title"),
        Equal.cong(EditorLayout.SectionKind, String,
          (kind => Rule.node_key(Rule.first(Doc.element_children(Render.editor_section(owner, label, visual, Render.documents(source_children), kind, Design.style_text(visual)))))),
          EditorLayout.section_kind(Render.sources(source_children)), EditorLayout.GenericSection{}, generic),
        Equal.cong(Bool, String,
          (empty => Rule.node_key(Rule.first(List.append(&2, Doc.Node, Render.section_label(owner, empty, label, Design.style_text(visual)), Render.documents(source_children))))),
          String.is_empty(label), False{}, nonempty))
    , +owner => semantic => +label => +source_children => visual => representation => typed_section_content(owner, label, visual, Render.documents(source_children), EditorLayout.section_kind(Render.sources(source_children))), +owner => semantic => label => +source_children => visual => representation => dialog_region_title_owner(owner, label, visual, Render.dialog_partition(source_children)), +owner => semantic => label => visual => representation => {==},
    +typography => +owner => label => {==}, task_facts_owner, +key => +attrs => +styles_value => +events => +children_value => {==}, +key => +attrs => +styles_value => +events => +children_value => {==}, +key => +field => +name => +attrs => +styles_value => +label_styles => +events => +children_value => {==}, +nodes => {==}, +key => semantic => label => role => region => position => +nodes => visual => representation =>
        {==}

      # These final properties follow the generic input's width:100%. The native
      # renderer applies style properties in order, so the region's width wins.
    , board_region_preservation, creation_region_preservation, unavailable_region_preservation, overview_main_partition, overview_main_flow, board_main_flow, +key => +values => +task => +generation =>
        {==}

      # Column sizing may change a child's CSS. The observation retains its key,
      # browser primitive, attributes, event bindings, and complete descendant tree.
    , region_partition, +key => semantic => +region => +position => +values => label => role => visual => representation => {==}, +key => +region => +position => +values => {==}, +key => +nested => {==},
    +nodes => +organization =>
        {==}

      # Dock regions retain their membership/order while acquiring their own physical
      # overflow owners. Heading regions receive only their typed title presentation;
      # reading membership remains unchanged.
    , +nodes =>
      Stdlib.list_ind(~Doc.Node,
        ~(values => {Rule.receipts(Stdlib.map(~Doc.Node, ~Doc.Node, ~Render.conversation_heading_region, values)) == Rule.receipts(values) : +List<Rule.RegionReceipt>}),
        ~heading_receipts_nil(), ~(node => rest => premise => heading_receipts_cons(node, rest, premise)), Render.page_nodes(nodes, "heading"))
    , +nodes => +heading => +viewport => +reading => +dock => {==},
    {==}, {==}, overview_organization, +key => +values => +task => +generation => {==}, +key => +values => +task => +generation => {==}}
