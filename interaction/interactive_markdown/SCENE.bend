import Base
import ../../bendlib/string-equality.bend as SafeText
import ./TYPES.bend as UI
import ./DECIMAL.bend as Decimal
import ./EXPRESSION.bend as Expression
import ../../bendlib/json.bend as J
import ../IDENTITY.bend as Identity
import ../conversation/CODE.bend as Code
import ../presentation/SURFACE.bend as Surface

def key( +identity: UI.Identity) -> Identity.Key:
  UI.Identity{UI.Owner{owner, epoch}, path} = identity
  Identity.Entity{Identity.Entity{Identity.Place{"interactive-markdown"}, "instance", owner}, "component", Nat.show(epoch) ++ "/" ++ path}

def mounted_key(+identity: UI.Identity, +occurrence: Nat) -> Identity.Key:
  Identity.Entity{key(identity), "mount", Nat.show(occurrence)}

def event( +node: UI.ExpandedNode) -> UI.EventIdentity:
  UI.ExpandedNode{identity, occurrence, tag, attributes, binding, children} = node
  UI.EventIdentity{identity, occurrence}

def shallow( +node: UI.ExpandedNode) -> UI.ExpandedNode:
  UI.ExpandedNode{identity, occurrence, tag, attributes, binding, children} = node
  UI.ExpandedNode{identity, occurrence, tag, attributes, binding, Nil{}}

def scalar_text( +value: J.Json) -> String:
  match value:
    case J.Text{text}: text
    case J.Number{text}: text
    case J.Boolean{True{}}: "true"
    case J.Boolean{False{}}: "false"
    case _: ""

def result_text( +value: Result<&2, &2, String, String>) -> String:
  match value:
    case Done{text}: text
    case Fail{error}: "显示错误：" ++ error

def formatted( +value: J.Json, +format: String) -> String:
  match value format:
    case J.Number{number} "": number
    case J.Number{number} style: result_text(Decimal.format(number, style))
    case other _: scalar_text(other)

def label( +node: UI.ExpandedNode) -> String:
  UI.ExpandedNode{identity, occurrence, tag, attributes, binding, children} = node
  J.text(J.get(attributes, "label"))

def role( +binding: UI.Binding) -> Surface.Role:
  match binding:
    case UI.FieldBinding{state_id, schema, raw, canonical, validation, enabled}: Surface.Field{}
    case UI.ActionBinding{kind, enabled, pending}: Surface.Button{}
    case _: Surface.Content{}

def fact( +parent: Identity.Key, +part: String, +value: String) -> Surface.Node:
  Surface.Node{Identity.Part{parent, part}, "interactive-markdown/text", "", Surface.Content{}, Surface.Fact{value}, Nil{}}

def synthetic(+owner: UI.ExpandedNode, +part: String, +tag: String, +attributes: J.Json, +children: +List<Surface.Node>) -> Surface.Node:
  UI.ExpandedNode{UI.Identity{instance, +path}, occurrence, original_tag, original_attributes, binding, original_children} = owner
  +identity: UI.Identity = UI.Identity{instance, path ++ "/@" ++ part}
  Surface.Node{mounted_key(identity, occurrence), "interactive-markdown/" ++ tag, "", Surface.Content{}, Surface.InteractiveNode{UI.ExpandedNode{identity, occurrence, tag, attributes, UI.NoBinding{}, Nil{}}}, children}

def key_of( +node: UI.ExpandedNode) -> Identity.Key:
  UI.ExpandedNode{identity, occurrence, tag, attributes, binding, children} = node
  mounted_key(identity, occurrence)

def binding_enabled( +value: J.Json) -> Bool:
  match value:
    case J.Boolean{enabled}: enabled
    case _: True{}

def controls_enabled( +node: UI.ExpandedNode) -> Bool:
  UI.ExpandedNode{identity, occurrence, tag, attrs, binding, children} = node
  binding_enabled(J.get(attrs, "enabled"))

def view_control(+owner: UI.ExpandedNode, +part: String, +label: String, +command: UI.ViewCommand, +enabled: Bool) -> Surface.Node:
  Surface.Node{Identity.Part{key_of(owner), "@view/" ++ part}, "interactive-markdown/view-control", label, Surface.Button{}, Surface.InteractiveView{event(owner), command, label, enabled && controls_enabled(owner)}, Nil{}}

def attributes( +node: UI.ExpandedNode) -> J.Json:
  UI.ExpandedNode{identity, occurrence, tag, attributes, binding, children} = node
  attributes

def property( +attrs: J.Json, +name: String, +value: J.Json) -> J.Json:
  match attrs:
    case J.Object{fields}: J.Object{J.Field{name, value} <> fields}
    case _: J.Object{[J.Field{name, value}]}

def children( +node: UI.ExpandedNode) -> +List<UI.ExpandedNode>:
  UI.ExpandedNode{identity, occurrence, tag, attributes, binding, children} = node
  children

def take_rows( +count: Nat, +values: +List<J.Json>) -> +List<J.Json>:
  match count values:
    case 0n _: Nil{}
    case 1n+remaining Nil{}: Nil{}
    case 1n+remaining Con{first, rest}: first <> take_rows(remaining, rest)

def drop_rows( +count: Nat, +values: +List<J.Json>) -> +List<J.Json>:
  match count values:
    case 0n remaining: remaining
    case 1n+remaining Nil{}: Nil{}
    case 1n+remaining Con{first, rest}: drop_rows(remaining, rest)

def natural( +value: J.Json, +fallback: Nat) -> Nat:
  J.natural_or(J.natural(value), fallback)

def view( +node: UI.ExpandedNode) -> J.Json:
  J.get(attributes(node), "@view")

def table_page(+owner: UI.ExpandedNode) -> Nat:
  Nat.min(natural(J.get(view(owner), "page"), 0n), Nat.div(Nat.sub(List.length(&2, J.Json, J.items(J.get(attributes(owner), "rows"))), 1n), 100n))

def sorted_direction( +selected: Bool, +direction: String) -> String:
  match selected direction:
    case False{} _: "none"
    case True{} "desc": "descending"
    case True{} _: "ascending"

def column_attributes( +column: UI.ExpandedNode, +owner: UI.ExpandedNode) -> J.Json:
  J.Object{[J.Field{"header", J.Boolean{True{}}}, J.Field{"sort", J.Text{sorted_direction(SafeText.string_equal(J.text(J.get(attributes(column), "field")), J.text(J.get(view(owner), "sort"))), J.text(J.get(view(owner), "direction")))}}]}

def table_header_cell( +sortable: Bool, +column: UI.ExpandedNode, +owner: UI.ExpandedNode) -> Surface.Node:
  match sortable:
    case True{}: synthetic(owner, "column/" ++ J.quote(J.text(J.get(attributes(column), "field"))), "@table-cell", column_attributes(column, owner), [view_control(owner, "sort/" ++ J.text(J.get(attributes(column), "field")), label(column), UI.TableSort{J.text(J.get(attributes(column), "field"))}, True{})])
    case False{}: synthetic(owner, "column/" ++ J.quote(J.text(J.get(attributes(column), "field"))), "@table-cell", column_attributes(column, owner), [fact(key_of(column), "label", label(column))])

def table_header( +columns: +List<UI.ExpandedNode>, +owner: UI.ExpandedNode, +sortable: Bool) -> +List<Surface.Node>:
  match columns:
    case Nil{}: Nil{}
    case Con{+column, rest}:
      table_header_cell(sortable, column, owner) <> table_header(rest, owner, sortable)

def table_cells( +columns: +List<UI.ExpandedNode>, +row: J.Json, +owner: UI.ExpandedNode, +row_key: String) -> +List<Surface.Node>:
  match columns:
    case Nil{}: Nil{}
    case Con{+column, rest}:
      synthetic(owner, "row/" ++ J.quote(row_key) ++ "/cell/" ++ J.quote(J.text(J.get(attributes(column), "field"))), "@table-cell", J.Object{Nil{}},
        [fact(Identity.Entity{key_of(owner), "row", row_key}, J.text(J.get(attributes(column), "field")), formatted(J.get(row, J.text(J.get(attributes(column), "field"))), J.text(J.get(attributes(column), "format"))))]) <> table_cells(rest, row, owner, row_key)

def table_rows( +rows: +List<J.Json>, +owner: UI.ExpandedNode, +row_key: String) -> +List<Surface.Node>:
  match rows:
    case Nil{}: Nil{}
    case Con{+row, rest}:
      synthetic(owner, "row/" ++ J.quote(scalar_text(J.get(row, row_key))), "@table-row", J.Object{Nil{}}, table_cells(children(owner), row, owner, scalar_text(J.get(row, row_key)))) <> table_rows(rest, owner, row_key)

def table_empty( +empty: Bool, +owner: UI.ExpandedNode) -> +List<Surface.Node>:
  match empty:
    case True{}: [fact(key_of(owner), "empty", "暂无数据")]
    case False{}: Nil{}

def table_navigation(+owner: UI.ExpandedNode, +count: Nat, +page: Nat) -> +List<Surface.Node>:
  [synthetic(owner, "pages", "row-layout", J.Object{[J.Field{"gap", J.Text{"sm"}}]},
    [view_control(owner, "previous", "上一页", UI.TablePage{Nat.sub(page, 1n)}, Nat.is_lt(0n, page)),
     fact(key_of(owner), "page-status", "第 " ++ Nat.show(1n+page) ++ " / " ++ Nat.show(Nat.max(1n, Nat.div(Nat.add(count, 99n), 100n))) ++ " 页，共 " ++ Nat.show(count) ++ " 行"),
     view_control(owner, "next", "下一页", UI.TablePage{1n+page}, Nat.is_lt(Nat.mul(1n+page, 100n), count))])]

def table_content(+owner: UI.ExpandedNode) -> +List<Surface.Node>:
  +rows: +List<J.Json> = J.items(J.get(attributes(owner), "rows"))
  +page: Nat = table_page(owner)
  synthetic(owner, "head", "@table-row", J.Object{Nil{}}, table_header(children(owner), owner, J.boolean(J.get(attributes(owner), "sortable")))) <>
    List.append(&2, Surface.Node, table_rows(take_rows(100n, drop_rows(Nat.mul(page, 100n), rows)), owner, J.text(J.get(attributes(owner), "row-key"))),
      List.append(&2, Surface.Node, table_empty(Nat.is_eq(List.length(&2, J.Json, rows), 0n), owner), table_navigation(owner, List.length(&2, J.Json, rows), page)))

def chart_summaries( +rows: +List<J.Json>, +owner: UI.ExpandedNode, +index: Nat) -> +List<Surface.Node>:
  match rows:
    case Nil{}: Nil{}
    case Con{+row, rest}:
      fact(key_of(owner), "summary/" ++ Nat.show(index), scalar_text(Expression.path_field(row, J.text(J.get(attributes(owner), "x")))) ++ ": " ++ scalar_text(Expression.path_field(row, J.text(J.get(attributes(owner), "y"))))) <> chart_summaries(rest, owner, 1n+index)

def chart_truncation( +exceeds: Bool, +owner: UI.ExpandedNode, +count: Nat) -> +List<Surface.Node>:
  match exceeds:
    case True{}: [fact(key_of(owner), "truncation", "共 " ++ Nat.show(count) ++ " 行，图中显示前 512 行。")]
    case False{}: Nil{}

def tag_of( +node: UI.ExpandedNode) -> String:
  UI.ExpandedNode{identity, occurrence, tag, attrs, binding, children} = node
  tag

def chart_axis_caption( +x: String, +y: String, +owner: UI.ExpandedNode) -> +List<Surface.Node>:
  match x y:
    case "" "": Nil{}
    case left right: [fact(key_of(owner), "axis-labels", left ++ " / " ++ right)]

def chart_axis_labels(+owner: UI.ExpandedNode) -> +List<Surface.Node>:
  chart_axis_caption(J.text(J.get(attributes(owner), "x-label")), J.text(J.get(attributes(owner), "y-label")), owner)

def chart_content(+owner: UI.ExpandedNode) -> +List<Surface.Node>:
  +rows: +List<J.Json> = J.items(J.get(attributes(owner), "data"))
  synthetic(owner, "plot", "@chart-plot", property(attributes(owner), "@chart-kind", J.Text{tag_of(owner)}), Nil{}) <>
    List.append(&2, Surface.Node, chart_axis_labels(owner), List.append(&2, Surface.Node, chart_truncation(Nat.is_lt(512n, List.length(&2, J.Json, rows)), owner, List.length(&2, J.Json, rows)),
      List.append(&2, Surface.Node, table_empty(Nat.is_eq(List.length(&2, J.Json, rows), 0n), owner),
        [synthetic(owner, "summary", "@chart-summary", J.Object{[J.Field{"label", J.Text{"图表数据"}}]}, chart_summaries(take_rows(512n, rows), owner, 0n))])))

def graph_controls(+owner: UI.ExpandedNode) -> Surface.Node:
  synthetic(owner, "controls", "row-layout", J.Object{[J.Field{"gap", J.Text{"sm"}}]},
    [view_control(owner, "zoom-in", "放大", UI.GraphZoomIn{}, True{}), view_control(owner, "zoom-out", "缩小", UI.GraphZoomOut{}, True{}),
     view_control(owner, "fit", "适应宽度", UI.GraphFit{}, True{}),
     view_control(owner, "left", "左移", UI.GraphPan{"-40", "0"}, True{}), view_control(owner, "right", "右移", UI.GraphPan{"40", "0"}, True{}),
     view_control(owner, "up", "上移", UI.GraphPan{"0", "-40"}, True{}), view_control(owner, "down", "下移", UI.GraphPan{"0", "40"}, True{})])

def graph_selection( +exists: Bool, +selected: String, +owner: UI.ExpandedNode) -> +List<Surface.Node>:
  match exists selected:
    case False{} "": Nil{}
    case False{} _: [fact(key_of(owner), "removed-selection", "原节点已移除")]
    case True{} _: Nil{}

def contains_node( +values: +List<J.Json>, +selected: String) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{node, rest}: SafeText.string_equal(J.text(J.get(node, "identity")), selected) || contains_node(rest, selected)

def graph_list( +nodes: +List<J.Json>, +owner: UI.ExpandedNode) -> +List<Surface.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{+node, rest}:
      synthetic(owner, "accessible/" ++ J.text(J.get(node, "identity")), "row-layout", J.Object{[J.Field{"gap", J.Text{"sm"}}]},
        [view_control(owner, "select/" ++ J.text(J.get(node, "identity")), J.text(J.get(node, "key")), UI.GraphSelect{J.text(J.get(node, "identity"))}, True{}),
         fact(key_of(owner), "state/" ++ J.text(J.get(node, "identity")), J.text(J.get(J.get(node, "task"), "title")) ++ " · " ++ J.text_or(J.get(J.get(node, "task"), "statusLabel"), "任务不存在") ++ " · " ++ J.text(J.get(J.get(node, "task"), "phase")))]) <> graph_list(rest, owner)

def graph_edge_list( +values: +List<J.Json>, +owner: UI.ExpandedNode) -> +List<Surface.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{+edge, rest}:
      fact(key_of(owner), "edge/" ++ J.text(J.get(edge, "identity")), J.text(J.get(edge, "ruleKey")) ++ ": " ++ J.text(J.get(edge, "sourceIdentity")) ++ " → " ++ J.text(J.get(edge, "targetIdentity")) ++ " (" ++ J.text(J.get(edge, "actionKind")) ++ ")") <> graph_edge_list(rest, owner)

def graph_wrappers( +values: +List<Surface.Node>, +owner: UI.ExpandedNode) -> +List<Surface.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{Surface.Node{key, semantic, label, role, Surface.InteractiveNode{UI.ExpandedNode{identity, occurrence, tag, +attrs, binding, original}}, children}, rest}:
      Surface.Node{key, semantic, label, role, Surface.InteractiveNode{UI.ExpandedNode{identity, occurrence, tag, property(property(attrs, "@view", view(owner)), "@selected", J.Boolean{SafeText.string_equal(J.text(J.get(attrs, "identity")), J.text(J.get(attributes(owner), "@selection")))}), binding, original}},
        view_control(owner, "diagram-select/" ++ J.text(J.get(attrs, "identity")), "选择节点", UI.GraphSelect{J.text(J.get(attrs, "identity"))}, True{}) <> children} <> graph_wrappers(rest, owner)
    case Con{node, rest}: node <> graph_wrappers(rest, owner)

def graph_content(+owner: UI.ExpandedNode, +converted: +List<Surface.Node>) -> +List<Surface.Node>:
  +values: +List<J.Json> = J.items(J.get(attributes(owner), "nodes"))
  List.append(&2, Surface.Node, [graph_controls(owner), synthetic(owner, "viewport", "@graph-viewport", attributes(owner),
    [synthetic(owner, "canvas", "@graph-canvas", attributes(owner),
      synthetic(owner, "edges", "@graph-edges", attributes(owner), Nil{}) <> graph_wrappers(converted, owner))])],
    List.append(&2, Surface.Node, graph_selection(contains_node(values, J.text(J.get(attributes(owner), "@selection"))), J.text(J.get(attributes(owner), "@selection")), owner),
      List.append(&2, Surface.Node, table_empty(Nat.is_eq(List.length(&2, J.Json, values), 0n), owner),
        [synthetic(owner, "accessible", "@graph-list", J.Object{[J.Field{"label", J.Text{"图节点状态"}}]}, graph_list(values, owner)), synthetic(owner, "connections", "@graph-list", J.Object{[J.Field{"label", J.Text{"连接规则"}}]}, graph_edge_list(J.items(J.get(attributes(owner), "edges")), owner))])))

def take_nodes( +count: Nat, +nodes: +List<Surface.Node>) -> +List<Surface.Node>:
  match count nodes:
    case 0n _: Nil{}
    case 1n+remaining Nil{}: Nil{}
    case 1n+remaining Con{first, rest}: first <> take_nodes(remaining, rest)

def drop_nodes( +count: Nat, +nodes: +List<Surface.Node>) -> +List<Surface.Node>:
  match count nodes:
    case 0n rest: rest
    case 1n+remaining Nil{}: Nil{}
    case 1n+remaining Con{first, rest}: drop_nodes(remaining, rest)

def grid_groups( +fuel: Nat, +nodes: +List<Surface.Node>, +owner: UI.ExpandedNode, +columns: Nat, +index: Nat) -> +List<Surface.Node>:
  match fuel nodes:
    case 0n _: Nil{}
    case 1n+remaining Nil{}: Nil{}
    case 1n+remaining Con{+first, +rest}:
      synthetic(owner, "grid-row/" ++ Nat.show(index), "row-layout", J.Object{[J.Field{"gap", J.get(attributes(owner), "gap")}]}, take_nodes(columns, first <> rest)) <> grid_groups(remaining, drop_nodes(columns, first <> rest), owner, columns, 1n+index)

def content( +tag: String, +node: UI.ExpandedNode, +converted: +List<Surface.Node>) -> +List<Surface.Node>:
  match tag:
    case "table": table_content(node)
    case "line-chart": chart_content(node)
    case "bar-chart": chart_content(node)
    case "graph-view": graph_content(node, converted)
    case "grid": grid_groups(List.length(&2, Surface.Node, converted), converted, node, Nat.max(1n, Nat.min(4n, natural(J.get(attributes(node), "columns"), 2n))), 0n)
    case _: converted

def expanded(+node: UI.ExpandedNode, +converted: +List<Surface.Node>) -> Surface.Node:
  UI.ExpandedNode{identity, occurrence, +tag, attrs, +binding, children} = node
  Surface.Node{mounted_key(identity, occurrence), "interactive-markdown/" ++ tag, J.text(J.get(attrs, "label")), role(binding), Surface.InteractiveNode{shallow(node)}, content(tag, node, converted)}

def forest( +nodes: +List<UI.ExpandedNode>) -> +List<Surface.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{UI.ExpandedNode{identity, occurrence, tag, attrs, binding, +children}, rest}:
      expanded(UI.ExpandedNode{identity, occurrence, tag, attrs, binding, children}, forest(children)) <> forest(rest)

def diagnostic_node(+informational: Bool, +owner: UI.Owner, +index: Nat, +path: String, +message: String) -> Surface.Node:
  match informational:
    case True{}: Surface.Node{key(UI.Identity{owner, "@diagnostic/" ++ Nat.show(index)}), "interactive-markdown/status", "操作结果", Surface.Content{}, Surface.Fact{message}, Nil{}}
    case False{}: Surface.Node{key(UI.Identity{owner, "@diagnostic/" ++ Nat.show(index)}), "interactive-markdown/diagnostic", "交互内容错误", Surface.Alert{}, Surface.Fact{path ++ ": " ++ message}, Nil{}}

def diagnostic_nodes( +values: +List<UI.Diagnostic>, +owner: UI.Owner, +index: Nat) -> +List<Surface.Node>:
  match values:
    case Nil{}: Nil{}
    case Con{UI.Diagnostic{+path, message, fatal}, rest}:
      diagnostic_node(String.starts_with(path, "@feedback/") || String.eq(path, "@storage"), owner, index, path, message) <> diagnostic_nodes(rest, owner, 1n+index)

def presentation_cost( +tag: String, +attrs: J.Json, +children: +List<UI.ExpandedNode>) -> Nat:
  match tag:
    case "table": Nat.add(16n, Nat.mul(Nat.add(2n, Nat.mul(2n, Nat.min(100n, List.length(&2, J.Json, J.items(J.get(attrs, "rows")))))), List.length(&2, UI.ExpandedNode, children)))
    case "line-chart": Nat.add(8n, Nat.min(512n, List.length(&2, J.Json, J.items(J.get(attrs, "data")))))
    case "bar-chart": Nat.add(8n, Nat.min(512n, List.length(&2, J.Json, J.items(J.get(attrs, "data")))))
    case "graph-view":
      node_count = List.length(&2, J.Json, J.items(J.get(attrs, "nodes")))
      edge_count = List.length(&2, J.Json, J.items(J.get(attrs, "edges")))
      Nat.add(34n, Nat.add(Nat.mul(4n, node_count), edge_count))
    case "grid": Nat.add(1n, List.length(&2, UI.ExpandedNode, children))
    case _: 1n

def expansion_cost( +values: +List<UI.ExpandedNode>) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{UI.ExpandedNode{identity, occurrence, tag, attrs, binding, +children}, rest}:
      Nat.add(presentation_cost(tag, attrs, children), Nat.add(expansion_cost(children), expansion_cost(rest)))

def admitted_nodes( +allowed: Bool, +owner: UI.Owner, +values: +List<UI.ExpandedNode>, +diagnostics: +List<UI.Diagnostic>) -> +List<Surface.Node>:
  match allowed:
    case True{}: List.append(&2, Surface.Node, forest(values), diagnostic_nodes(diagnostics, owner, 0n))
    case False{}: diagnostic_nodes([UI.Diagnostic{"ui", "交互界面展开超过 4096 个节点；局部输入已保留，请查看源码。", False{}}], owner, 0n)

def nodes( +scene: UI.Scene) -> +List<Surface.Node>:
  UI.Scene{owner, values, diagnostics, complete, failed, revision} = scene
  admitted_nodes(Nat.is_le(Nat.add(expansion_cost(values), List.length(&2, UI.Diagnostic, diagnostics)), 4096n), owner, values, diagnostics)

def scene_region(+identity: Code.Identity, +source_visible: Bool, +scene: UI.Scene) -> Surface.Node:
  Surface.Node{Identity.Part{Code.ui_identity(identity), "interactive"}, "interactive-markdown/region", "交互内容", Surface.Content{}, Surface.InteractiveRegion{identity, source_visible}, nodes(scene)}
