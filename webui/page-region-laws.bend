import Base
import ./typography.bend as T
import ../core/field-options.bend as FieldOptions
import ../core/user-conversation.bend as Conversation
import ../core/composition.bend as Composition
import ../core/interface.bend as UI
import ../core/ui-world.bend as View
import ../core/user-context.bend as Context
import ../bendlib/domain.bend as Domain
import ./document.bend as Doc
import ./renderer.bend as Render
import ./shell-spatial-laws.bend as ShellSpatial
import ./editor-layout.bend as EditorLayout
import ./design.bend as Design
import ./controls.bend as Controls
def node_key(node: Doc.Node) -> String:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: key
    case _: ""

def partition(+nodes: +List<Doc.Node>) -> (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>)):
  (Render.page_nodes(nodes, "heading"), (Render.page_nodes(nodes, "body"), Render.page_nodes(nodes, "dock")))

# This is the independent membership rule: each populated region belongs to
# exactly one position; the arbitrary suffix is unchanged in all other groups.
def prescribed_cons(position: Composition.Position, +node: Doc.Node, +rest: +List<Doc.Node>) -> (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>)):
  match position:
    case Composition.HeadingPosition{}:
      (node <> Render.page_nodes(rest, "heading"), (Render.page_nodes(rest, "body"), Render.page_nodes(rest, "dock")))
    case Composition.BodyPosition{}:
      (Render.page_nodes(rest, "heading"), (node <> Render.page_nodes(rest, "body"), Render.page_nodes(rest, "dock")))
    case Composition.DockPosition{}:
      (Render.page_nodes(rest, "heading"), (Render.page_nodes(rest, "body"), node <> Render.page_nodes(rest, "dock")))

def groups(nodes: +List<Doc.Node>) -> (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>)):
  match nodes:
    case Con{heading, Con{body, Con{dock, Nil{}}}}: (Doc.element_children(heading), (Doc.element_children(body), Doc.element_children(dock)))
    case _: (Nil{}, (Nil{}, Nil{}))

def conversation_parts(+nodes: +List<Doc.Node>) -> (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>)):
  (Render.conversation_heading_nodes(nodes), (Render.page_nodes(nodes, "body"),
    Render.conversation_dock_regions(Render.page_nodes(nodes, "dock"))))

def specified_organization(organization: Composition.Body) -> String:
  match organization:
    case Composition.ProjectSections{}: "project-sections"
    case Composition.ProjectRows{}: "project-rows"
    case Composition.AgentRows{}: "agent-rows"
    case _: "overview"

def second(nodes: +List<Doc.Node>) -> Doc.Node:
  match nodes:
    case Con{first, Con{second, rest}}: second
    case _: Doc.Text{""}

def first(nodes: +List<Doc.Node>) -> Doc.Node:
  match nodes:
    case Con{node, rest}: node
    case _: Doc.Text{""}

def group_flow(+nodes: +List<Doc.Node>) -> ((String & String) & (String & (String & String))):
  ((Render.attr(Doc.element_styles(first(nodes)), "flex"), Render.attr(Doc.element_styles(first(nodes)), "flex-wrap")),
    (Render.attr(Doc.element_styles(second(nodes)), "flex"), (Render.attr(Doc.element_styles(second(nodes)), "min-height"), Render.attr(Doc.element_styles(second(nodes)), "overflow"))))

type ChildPayload is Data:
  ElementPayload{key: String, tag: String, attrs: +List<Doc.Property>, events: +List<Doc.Event>, children: +List<Doc.Node>}
  OtherPayload{node: Doc.Node}

def payload(node: Doc.Node) -> ChildPayload:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, children}: ElementPayload{key, tag, attrs, events, children}
    case other: OtherPayload{other}

def payloads(nodes: +List<Doc.Node>) -> +List<ChildPayload>:
  match nodes:
    case Nil{}: Nil{}
    case Con{node, rest}: payload(node) <> payloads(rest)

type RegionReceipt is Data:
  RegionReceipt{key: String, region: String, position: String, children: +List<ChildPayload>}

def receipt(node: Doc.Node) -> RegionReceipt:
  match node:
    case Doc.Element{key, tag, +attrs, styles, events, children}:
      RegionReceipt{key, Render.attr(attrs, "data-page-region"), Render.attr(attrs, "data-page-position"), payloads(children)}
    case _: RegionReceipt{"", "", "", Nil{}}

def receipts(nodes: +List<Doc.Node>) -> +List<RegionReceipt>:
  match nodes:
    case Nil{}: Nil{}
    case Con{node, rest}: receipt(node) <> receipts(rest)

def receipt_partition(parts: (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>))) -> (+List<RegionReceipt> & (+List<RegionReceipt> & +List<RegionReceipt>)):
  (heading, (body, dock)) = parts
  (receipts(heading), (receipts(body), receipts(dock)))

def expected_section_children(kind: EditorLayout.SectionKind, owner: String, +label: String,
  rendered: +List<Doc.Node>, +typography: T.Presentation) -> +List<Doc.Node>:
  match kind:
    case EditorLayout.WorkSection{}: rendered
    case EditorLayout.MetadataSection{}: rendered
    case EditorLayout.CaptureSection{}: rendered
    case _: List.append(&2, Doc.Node, Render.section_label(owner, String.is_empty(label), label, typography), rendered)

type FactObservation is Data:
  FactObservation{key: String, label_key: String, label: String, value: String}

def fact_contents(key: String, values: +List<Doc.Node>) -> FactObservation:
  match values:
    case Con{+label, Con{value, Nil{}}}: FactObservation{key, node_key(label), Doc.direct_text(first(Doc.element_children(label))), Doc.direct_text(first(Doc.element_children(value)))}
    case _: FactObservation{key, "", "", ""}

def observed_fact(node: Doc.Node) -> FactObservation:
  match node:
    case Doc.Element{key, tag, attrs, styles, events, values}: fact_contents(key, values)
    case _: FactObservation{"", "", "", ""}

def observed_facts(nodes: +List<Doc.Node>) -> +List<FactObservation>:
  match nodes:
    case Nil{}: Nil{}
    case Con{node, rest}: observed_fact(node) <> observed_facts(rest)

def specified_fact(+owner: String, part: String, label: String, value: String) -> FactObservation:
  +key = Render.generated_identity(owner, part)
  FactObservation{key, key ++ "/label", label, value}

# The source projections and labels are unchanged; only the fact's owning
# node contributes to the generated identity.
def specified_task_facts(+owner: String, value: View.TaskDetails) -> +List<FactObservation>:
  View.TaskDetails{Context.EffectiveContext{task, Domain.TaskContext{Domain.Workspace{roots, primary}, Domain.Sandbox{mode, network}, approval, project}, guidance, access}, Domain.Model{Domain.Profile{id, provider, name, policy}, reasoning, model_guidance}, tools, lineage, queued, status, phase} = value
  [specified_fact(owner, "workspace", "Working directories", FieldOptions.joined(roots)),
    specified_fact(owner, "primary", "Primary directory", FieldOptions.optional_text(primary)),
    specified_fact(owner, "sandbox", "Filesystem access", Domain.sandbox_mode_name(mode)),
    specified_fact(owner, "network", "Network access", FieldOptions.boolean(network)),
    specified_fact(owner, "approval", "Approval policy", Domain.approval_name(approval)),
    specified_fact(owner, "model", "Model", name),
    specified_fact(owner, "reasoning", "Reasoning", reasoning),
    specified_fact(owner, "messages", "Queued messages", FieldOptions.joined(queued))]

type Requirements is Type:
  Requirements{
    generated_identity: @+owner:String -> @+part:String -> {Render.generated_identity(owner, part) == owner ++ "/@" ++ part : String},
    section_title_owner: @+owner:String -> @semantic:String -> @+label:String -> @+source_children:+List<Render.Child> -> @+visual:Design.Style -> @representation:Controls.Representation -> @nonempty:{String.is_empty(label) == False{} : Bool} -> @generic:{EditorLayout.section_kind(Render.sources(source_children)) == EditorLayout.GenericSection{} : EditorLayout.SectionKind} ->
      {node_key(first(Doc.element_children(Render.match_node(Design.Node{owner, semantic, label, UI.Section{}, UI.Region{}, visual, representation, Render.sources(source_children)}, source_children)))) == Render.generated_identity(owner, "title") : String},
    section_layout_contract: @+owner:String -> @semantic:String -> @+label:String -> @+source_children:+List<Render.Child> -> @visual:Design.Style -> @representation:Controls.Representation ->
      {(Doc.element_children(Render.match_node(Design.Node{owner, semantic, label, UI.Section{}, UI.Region{}, visual, representation, Render.sources(source_children)}, source_children)),
          Render.attr(Doc.element_attributes(Render.match_node(Design.Node{owner, semantic, label, UI.Section{}, UI.Region{}, visual, representation, Render.sources(source_children)}, source_children)), "aria-label")) ==
         (expected_section_children(EditorLayout.section_kind(Render.sources(source_children)), owner, label, Render.documents(source_children), Design.style_text(visual)), label) :
         (+List<Doc.Node> & String)},
    dialog_title_owner: @+owner:String -> @semantic:String -> @label:String -> @+source_children:+List<Render.Child> -> @visual:Design.Style -> @representation:Controls.Representation ->
      {node_key(first(Doc.element_children(first(Doc.element_children(Render.match_node(Design.Node{owner, semantic, label, UI.Dialog{}, UI.Region{}, visual, representation, Render.sources(source_children)}, source_children)))))) == Render.generated_identity(owner, "title") : String},
    activity_fallback_owner: @+owner:String -> @semantic:String -> @label:String -> @visual:Design.Style -> @representation:Controls.Representation ->
      {node_key(first(Doc.element_children(Render.match_node(Design.Node{owner, semantic, label, UI.Activity{}, UI.Region{}, visual, representation, Nil{}}, Nil{})))) == Render.generated_identity(owner, "summary") : String},
    activity_label_owner: @+typography:T.Presentation -> @+owner:String -> @label:String -> {node_key(first(Render.region_label(owner, UI.Activity{}, label, typography))) == Render.generated_identity(owner, "summary") : String},
    task_facts_owner: @+owner:String -> @semantic:String -> @+details:View.TaskDetails -> @label:String -> @role:UI.Role -> @+source_children:+List<Render.Child> -> @visual:Design.Style -> @representation:Controls.Representation ->
      {observed_facts(Doc.element_children(first(Doc.element_children(Render.match_node(Design.Node{owner, semantic, label, role, UI.TaskFacts{details}, visual, representation, Render.sources(source_children)}, source_children))))) == specified_task_facts(owner, details) : +List<FactObservation>},
    board_select_bounds: @+key:String -> @+attrs:+List<Doc.Property> -> @+styles_value:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @+children_value:+List<Doc.Node> ->
      {Render.board_input(Doc.Element{key, "select", attrs, styles_value, events, children_value}) ==
          Doc.Element{key, "select", attrs, List.append(&2, Doc.Property, styles_value,
            [Doc.Property{"width", "auto"}, Doc.Property{"max-width", "100%"}, Doc.Property{"min-width", "0"}]), events, children_value} : Doc.Node},
    board_input_bounds: @+key:String -> @+attrs:+List<Doc.Property> -> @+styles_value:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @+children_value:+List<Doc.Node> ->
      {Render.board_input(Doc.Element{key, "input", attrs, styles_value, events, children_value}) ==
          Doc.Element{key, "input", attrs, List.append(&2, Doc.Property, styles_value,
            [Doc.Property{"width", "auto"}, Doc.Property{"max-width", "100%"}, Doc.Property{"min-width", "0"}]), events, children_value} : Doc.Node},
    board_labeled_select: @+key:String -> @+field:String -> @+name:String -> @+attrs:+List<Doc.Property> -> @+styles_value:+List<Doc.Property> -> @+label_styles:+List<Doc.Property> -> @+events:+List<Doc.Event> -> @+children_value:+List<Doc.Node> ->
      {Render.board_control(Doc.Element{key, "label", Nil{}, label_styles, Nil{},
          [Doc.Text{name}, Doc.Element{field, "select", attrs, styles_value, events, children_value}]}) ==
          Doc.Element{key, "label", Nil{}, label_styles, Nil{}, [Doc.Text{name},
            Doc.Element{field, "select", attrs, List.append(&2, Doc.Property, styles_value,
              [Doc.Property{"width", "auto"}, Doc.Property{"max-width", "100%"}, Doc.Property{"min-width", "0"}]), events, children_value}]} : Doc.Node},
    board_control_dispatch: @+nodes:+List<Doc.Node> -> {Render.positioned_page_children(Composition.region_name(Composition.BoardControls{}), nodes) == Render.board_controls(nodes) : +List<Doc.Node>},
    rendered_child_order: @+key:String -> @semantic:String -> @label:String -> @role:UI.Role -> @region:Composition.Region -> @position:Composition.Position -> @+nodes:+List<Design.Node> -> @visual:Design.Style -> @representation:Controls.Representation ->
      {Doc.element_children(first(Render.render_nodes([Design.Node{key, semantic, label, role, UI.PageRegion{region, position}, visual, representation, nodes}]))) == Render.render_nodes(nodes) : +List<Doc.Node>},
    board_regions: @+nodes:+List<Doc.Node> -> @+canvas:Design.Box -> @+width:Nat -> @+gap:Nat -> @+inset:Nat ->
      {receipt_partition(groups(Doc.element_children(first(Render.prepare_main_children(nodes, Design.frame_structure(Design.BoardFrame{canvas, width, gap, inset}), None{}))))) == receipt_partition(partition(nodes)) : (+List<RegionReceipt> & (+List<RegionReceipt> & +List<RegionReceipt>))},
    creation_regions: @+nodes:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band -> @+input:Maybe<&2, Design.InputMetrics> -> @+flow:Design.CreationFlow ->
      {ShellSpatial.creation_canvas_children(first(Render.prepare_main_children(nodes, Design.frame_structure(Design.CreationFrame{heading, canvas, band, input, flow}), None{}))) == nodes : +List<Doc.Node>},
    unavailable_regions: @+nodes:+List<Doc.Node> -> @+heading:Design.Box -> @+canvas:Design.Box -> @+band:Design.Band ->
      {Doc.element_children(first(Render.prepare_main_children(nodes, Design.frame_structure(Design.UnavailableFrame{heading, canvas, band}), None{}))) == nodes : +List<Doc.Node>},
    overview_main: @+nodes:+List<Doc.Node> -> @+canvas:Design.Box -> @+band:Design.Band -> @+organization:Composition.Body ->
      {groups(Doc.element_children(first(Render.prepare_main_children(nodes, Design.frame_structure(Design.OverviewFrame{canvas, band, organization}), None{})))) == partition(nodes) : (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>))},

    overview_flow: @+nodes:+List<Doc.Node> -> @+canvas:Design.Box -> @+band:Design.Band -> @+organization:Composition.Body ->
      {group_flow(Doc.element_children(first(Render.prepare_main_children(nodes, Design.frame_structure(Design.OverviewFrame{canvas, band, organization}), None{})))) == (("none", "wrap"), ("1", ("0", "auto"))) : ((String & String) & (String & (String & String)))},
    board_flow: @+nodes:+List<Doc.Node> -> @+canvas:Design.Box -> @+width:Nat -> @+gap:Nat -> @+inset:Nat ->
      {group_flow(Doc.element_children(first(Render.prepare_main_children(nodes, Design.frame_structure(Design.BoardFrame{canvas, width, gap, inset}), None{})))) == (("none", "wrap"), ("1", ("0", "hidden"))) : ((String & String) & (String & (String & String)))},
    reading_identity: @+key:String -> @+values:+List<Doc.Node> -> @+task:Nat -> @+generation:Nat ->
      {(node_key(Render.reading_element("conversation-body", key, "div", Nil{}, Nil{}, Nil{}, values, Some{Conversation.Identity{task, generation}})),
          (Render.attr(Doc.element_attributes(Render.reading_element("conversation-body", key, "div", Nil{}, Nil{}, Nil{}, values, Some{Conversation.Identity{task, generation}})), "data-reading-task"),
           Render.attr(Doc.element_attributes(Render.reading_element("conversation-body", key, "div", Nil{}, Nil{}, Nil{}, values, Some{Conversation.Identity{task, generation}})), "data-reading-generation"))) ==
          ("conversation/" ++ Nat.show(task) ++ "/body", (Nat.show(task), Nat.show(generation))) : (String & (String & String))},
    region_partition: @+key:String -> @+region:Composition.Region -> @+position:Composition.Position -> @+values:+List<Doc.Node> -> @+rest:+List<Doc.Node> ->
      {partition(Render.page_region(key, region, position, values) <> rest) == prescribed_cons(position, Render.page_region(key, region, position, values), rest) : (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>))},
    child_order: @+key:String -> @semantic:String -> @+region:Composition.Region -> @+position:Composition.Position -> @+values:+List<Render.Child> -> @label:String -> @role:UI.Role -> @visual:Design.Style -> @representation:Controls.Representation ->
      {Doc.element_children(Render.match_node(Design.Node{key, semantic, label, role, UI.PageRegion{region, position}, visual, representation, Render.sources(values)}, values)) == Render.documents(values) : +List<Doc.Node>},
    identity: @+key:String -> @+region:Composition.Region -> @+position:Composition.Position -> @+values:+List<Doc.Node> ->
      {(node_key(Render.page_region(key, region, position, values)),
          (Render.attr(Doc.element_attributes(Render.page_region(key, region, position, values)), "data-page-region"),
            Render.attr(Doc.element_attributes(Render.page_region(key, region, position, values)), "data-page-position"))) ==
          (key, (Composition.region_name(region), Render.page_position(position))) : (String & (String & String))},
    ordinary_heading: @+key:String -> @+nested:+List<Doc.Node> ->
      {partition(Render.decorate("heading", "heading", Doc.Element{key, "h2", Nil{}, Nil{}, Nil{}, nested}) <> Nil{}) == (Nil{}, (Nil{}, Nil{})) : (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>))},
    overview_partition: @+nodes:+List<Doc.Node> -> @+organization:Composition.Body ->
      {groups(Render.overview_children(nodes, organization)) == partition(nodes) : (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>))},
    conversation_heading_preservation: @+nodes:+List<Doc.Node> ->
      {receipts(Render.conversation_heading_nodes(nodes)) == receipts(Render.page_nodes(nodes, "heading")) : +List<RegionReceipt>},
    conversation_partition: @+nodes:+List<Doc.Node> -> @+heading:Design.Box -> @+viewport:Design.Box -> @+reading:Design.Band -> @+dock:Maybe<&2, Design.Dock> ->
      {groups(Render.prepare_main_children(nodes, Design.frame_structure(Design.ConversationFrame{heading, viewport, reading, dock}), None{})) == conversation_parts(nodes) : (+List<Doc.Node> & (+List<Doc.Node> & +List<Doc.Node>))},

    header: {(Render.attr(Render.intrinsic_heading_styles(), "flex"), Render.attr(Render.intrinsic_heading_styles(), "flex-wrap")) == ("none", "wrap") : (String & String)},
    body: {(Render.attr(Render.remaining_body_styles(), "flex"),
          (Render.attr(Render.remaining_body_styles(), "min-height"), Render.attr(Render.remaining_body_styles(), "overflow"))) ==
            ("1", ("0", "auto")) : (String & (String & String))},
    organization: @+nodes:+List<Doc.Node> -> @+organization:Composition.Body ->
      {Render.attr(Doc.element_attributes(second(Render.overview_children(nodes, organization))), "data-overview-organization") == specified_organization(organization) : String},
    timeline: @+key:String -> @+values:+List<Doc.Node> -> @+task:Nat -> @+generation:Nat ->
      {Render.attr(Doc.element_attributes(Render.reading_element("timeline", key, "div", Nil{}, Nil{}, Nil{}, values, Some{Conversation.Identity{task, generation}})), "data-reading-scroll") == "" : String},
    reading_body: @+key:String -> @+values:+List<Doc.Node> -> @+task:Nat -> @+generation:Nat ->
      {Doc.element_children(Render.reading_element("conversation-body", key, "div", Nil{}, Nil{}, Nil{}, values,
          Some{Conversation.Identity{task, generation}})) ==
          [Doc.Element{("conversation/" ++ Nat.show(task) ++ "/body") ++ "/reading-content", "div",
            [Doc.Property{"data-reading-content", ""}, Doc.Property{"data-reading-task", Nat.show(task)}],
            [Doc.Property{"display", "flex"}, Doc.Property{"flex-direction", "column"}, Doc.Property{"gap", "16px"}], Nil{}, values}] : +List<Doc.Node>}
  }

law evidence:
  Requirements
