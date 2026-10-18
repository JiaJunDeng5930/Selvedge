import Base
import ../../interaction/interactive_markdown/TYPES.bend as UI
import ../../interaction/interactive_markdown/SCENE.bend as Scene
import ./chart.bend as Chart
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/conversation/CODE.bend as Code
import ../../bendlib/json.bend as J
import ../document/SOURCE.bend as Source
import ../document/MODEL.bend as Document
import ../appearance/DESIGN.bend as Design
import ../appearance/TYPOGRAPHY.bend as Typography
import ../layout/physical-space.bend as Layout
import ../layout/GEOMETRY.bend as Geometry
import ../layout/enclosure.bend as Enclosure
import ./PROGRAM.bend as Controls
import ./CONTROLS.bend as Authored
import ./BUTTONS.bend as Buttons
import ./button-proof.bend as ButtonProof
import ./authored-proof.bend as InputProof
import ./authored-primitives.bend as Factory

type GraphGeometry is Data:
  GraphGeometry{x: Nat, y: Nat, width: Nat, height: Nat}

def graph_columns( +fit: Bool) -> Nat:
  match fit:
    case True{}: 1n
    case False{}: 4n

def graph_left( +fit: Bool) -> Nat:
  match fit:
    case True{}: 0n
    case False{}: 40n

def prop( +attrs: J.Json, +name: String) -> String:
  J.text(J.get(attrs, name))

def gap( +name: String) -> Nat:
  match name:
    case "none": 0n
    case "sm": 6n
    case "lg": 18n
    case _: 12n

def tone( +name: String, +fallback: Design.Paint) -> Design.Paint:
  match name:
    case "accent": Design.ThemeToken{"--color-token-text-link-foreground"}
    case "success": Design.ThemeToken{"--interactive-tone-success"}
    case "warning": Design.ThemeToken{"--color-token-editor-warning-foreground"}
    case "danger": Design.ThemeToken{"--interactive-tone-danger"}
    case "muted": Design.ThemeToken{"--color-token-text-secondary"}
    case _: fallback

def themed( +style: Source.Style, +attrs: J.Json) -> Source.Style:
  Source.Style{layout, font, Design.Chrome{foreground, background, border, border_width, radius, shadow}, states} = style
  Source.Style{layout, font, Design.Chrome{tone(prop(attrs, "tone"), foreground), background, border, border_width, radius, shadow}, states}

def common(+key: Identity.Key, +attrs: J.Json, +tag: String) -> +List<Source.Attribute>:
  [Source.DataAttribute{"interactive-component", tag}, Source.DataAttribute{"interactive-motion", prop(attrs, "motion")},
   Source.DataAttribute{"interactive-transition", prop(attrs, "transition")}, Source.DataAttribute{"interactive-key", Identity.encode(key)}]

def decorate( +node: Source.Node, +attrs: +List<Source.Attribute>) -> Source.Node:
  match node:
    case Source.Box{key, tag, style, original, children}: Source.Box{key, tag, style, List.append(&2, Source.Attribute, original, attrs), children}
    case Source.Control{key, tag, style, original, name, enabled, first, remaining, children}: Source.Control{key, tag, style, List.append(&2, Source.Attribute, original, attrs), name, enabled, first, remaining, children}
    case Source.Field{key, kind, style, original, value, placeholder, options, policy, name, enabled, first, remaining}: Source.Field{key, kind, style, List.append(&2, Source.Attribute, original, attrs), value, placeholder, options, policy, name, enabled, first, remaining}
    case other: other

def box(+key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>) -> Source.Node:
  Source.constructed_box_node(Source.construct_box(Source.BoxRequest{key, tag, style, attributes, children}))

def text(+key: Identity.Key, +value: String, +visual: Design.Style) -> Source.Node:
  Factory.text(key, value, Source.ExplicitFont{Authored.parent_font(visual)}, Typography.NormalAnywhere{})

def ordinary_style( +visual: Design.Style, +attrs: J.Json) -> Source.Style:
  themed(Factory.content_style(visual, Layout.Vertical{}, Layout.StretchSize{}, Layout.NaturalSize{}, gap(prop(attrs, "gap"))), attrs)

def visual_chrome( +visual: Design.Style) -> Design.Chrome:
  Design.Style{text, chrome, alignment, flow, overflow, frame, minimum_height, maximum_width_percent, states} = visual
  chrome

def chrome( +style: Source.Style) -> Source.Style:
  Source.Style{layout, font, Design.Chrome{foreground, background, border, width, radius, shadow}, states} = style
  Source.Style{layout, font, Design.Chrome{foreground, Design.ThemeToken{"--color-token-bg-primary"}, Design.ThemeToken{"--color-token-border-default"}, 1n, 8n, False{}}, states}

def enclosed( +style: Source.Style) -> Source.Style:
  Factory.with_frame(chrome(style), Enclosure.Frame{Enclosure.ambient(12n, 12n), Enclosure.EmbeddedContent{12n}})

def dimensions( +style: Source.Style, +direction: Layout.Direction, +width: Layout.AxisSize, +height: Layout.AxisSize, +scroll: Layout.Scroll, +position: Geometry.Position) -> Source.Style:
  Source.Style{Source.Layout{original_direction, main, cross, frame, original_width, original_height, minimum, original_scroll, original_position}, font, chrome, states} = style
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}

def validation( +key: Identity.Key, +value: Maybe<&2, String>, +visual: Design.Style) -> +List<Source.Node>:
  match value:
    case None{}: Nil{}
    case Some{message}: [box(Identity.part(key, "validation"), Source.Output{}, ordinary_style(visual, J.Object{[J.Field{"tone", J.Text{"danger"}}]}), [Source.IdAttribute{Identity.encode(Identity.part(key, "validation"))}, Source.RoleAttribute{"status"}], [text(Identity.part(key, "validation-text"), message, visual)])]

def input_validation(+key: Identity.Key, +binding: UI.Binding, +field: Source.Node, +visual: Design.Style) -> Source.Node:
  match binding:
    case UI.FieldBinding{state_id, schema, raw, canonical, validation_value, enabled}:
      box(Identity.part(key, "input-enclosure"), Source.Div{}, ordinary_style(visual, J.Object{[J.Field{"gap", J.Text{"sm"}}]}), Nil{}, field <> validation(key, validation_value, visual))
    case _: field

def input_validation_for(+node: UI.ExpandedNode, +key: Identity.Key, +field: Source.Node, +visual: Design.Style) -> Source.Node:
  UI.ExpandedNode{identity, occurrence, tag, attrs, binding, children} = node
  input_validation(key, binding, field, visual)

def input(+key: Identity.Key, +node: UI.ExpandedNode, +visual: Design.Style, +representation: Controls.Representation, +parameters: Design.LayoutParameters) -> Source.Node:
  match representation:
    case Controls.Input{input}:
      input_validation_for(node, key, Authored.constructed_input_node(Authored.construct_input(key, input, visual, parameters)), visual)
    case _: Authored.invalid(key, visual, "Interactive Markdown input lacks its native representation")

def button( +key: Identity.Key, +visual: Design.Style, +representation: Controls.Representation, +parameters: Design.LayoutParameters) -> Source.Node:
  match representation:
    case Controls.Action{action}: Buttons.constructed_node(Buttons.construct(key, visual, parameters, action))
    case _: Authored.invalid(key, visual, "Interactive Markdown action lacks its native representation")

def plot_path(kind: Chart.ChartKind, +points: +List<Chart.Point>) -> Source.Drawing:
  match kind:
    case Chart.Line{}: Source.Drawing{"0 0 480 240", [Source.DrawingPath{Chart.line_commands(points, True{})}, Source.DrawingPath{Chart.point_commands(points)}], 480n, 240n, Source.StrokedDrawing{20n}}
    case Chart.Bar{}: Source.Drawing{"0 0 480 240", [Source.DrawingPath{Chart.bar_commands(points, Chart.bar_width(points))}], 480n, 240n, Source.FilledDrawing{}}

def layered_style(+style: Source.Style) -> Source.Style:
  Factory.with_frame(style, Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}})

def plot_style(+style: Source.Style) -> Source.Style:
  dimensions(layered_style(style), Layout.Horizontal{}, Layout.StretchSize{}, Layout.ExactSize{240n}, Layout.ScrollHorizontally{}, Geometry.InFlow{})

def plot_canvas_style(+style: Source.Style) -> Source.Style:
  dimensions(layered_style(style), Layout.Layered{}, Layout.ExactSize{480n}, Layout.ExactSize{240n}, Layout.Confined{}, Geometry.InFlow{})

def plot_values(+key: Identity.Key, +attrs: J.Json, +visual: Design.Style, +values: Chart.Values) -> Source.Node:
  Chart.Values{kind, +points, +total, x_magnitude, y_magnitude} = values
  box(key, Source.Div{}, plot_style(ordinary_style(visual, attrs)),
    [Source.RoleAttribute{"img"}, Source.AriaAttribute{"label", "图表；显示 " ++ Nat.show(List.length(&2, Chart.Point, points)) ++ " / " ++ Nat.show(total) ++ " 行；数值见下方数据"}],
    [box(Identity.part(key, "canvas"), Source.Div{}, plot_canvas_style(ordinary_style(visual, attrs)), Nil{},
      [Source.Glyph{Identity.part(key, "axes"), Source.Drawing{"0 0 480 240", [Source.DrawingPath{"M 40 20 V 220 M 40 120 H 460"}], 480n, 240n, Source.StrokedDrawing{10n}}, Factory.glyph_style(visual, 480n, 240n)},
       Source.Glyph{Identity.part(key, "values"), plot_path(kind, points), Factory.glyph_style(visual, 480n, 240n)}])])

def plot_admitted(+key: Identity.Key, +attrs: J.Json, +visual: Design.Style, result: Result<&2, &2, String, Chart.Values>) -> Source.Node:
  match result:
    case Fail{reason}: Authored.invalid(key, visual, reason)
    case Done{values}: plot_values(key, attrs, visual, values)

def plot(+key: Identity.Key, +attrs: J.Json, +visual: Design.Style) -> Source.Node:
  plot_admitted(key, attrs, visual, Chart.read(attrs))

def graph_geometry( +index: Nat, +attrs: J.Json) -> GraphGeometry:
  +view: J.Json = J.get(attrs, "@view")
  +zoom: Nat = Nat.min(200n, Nat.max(25n, Scene.natural(J.get(view, "zoom"), 100n)))
  +columns: Nat = graph_columns(J.boolean(J.get(view, "fitWidth")))
  GraphGeometry{Nat.add(graph_left(J.boolean(J.get(view, "fitWidth"))), Nat.add(Nat.div(Nat.mul(Nat.mod(index, columns), Nat.mul(200n, zoom)), 100n), Nat.min(2000n, Scene.natural(J.get(view, "panX"), 0n)))),
    Nat.add(40n, Nat.add(Nat.div(Nat.mul(Nat.div(index, columns), Nat.mul(160n, zoom)), 100n), Nat.min(2000n, Scene.natural(J.get(view, "panY"), 0n)))),
    Nat.max(80n, Nat.div(Nat.mul(160n, zoom), 100n)), Nat.max(80n, Nat.div(Nat.mul(120n, zoom), 100n))}

def graph_canvas_size( +last: GraphGeometry, +rightmost: GraphGeometry) -> Enclosure.Extent:
  match last rightmost:
    case GraphGeometry{x, y, width, height} GraphGeometry{right, top, right_width, right_height}:
      Enclosure.Extent{Nat.add(80n, Nat.add(Nat.mul(2n, right), right_width)), Nat.add(80n, Nat.add(Nat.mul(2n, y), height))}

def canvas_size(+attrs: J.Json) -> Enclosure.Extent:
  graph_canvas_size(graph_geometry(Nat.sub(List.length(&2, J.Json, J.items(J.get(attrs, "nodes"))), 1n), attrs), graph_geometry(Nat.sub(graph_columns(J.boolean(J.get(J.get(attrs, "@view"), "fitWidth"))), 1n), attrs))

def graph_node_style( +style: Source.Style, +geometry: GraphGeometry) -> Source.Style:
  GraphGeometry{x, y, width, height} = geometry
  dimensions(enclosed(style), Layout.Vertical{}, Layout.ExactSize{width}, Layout.ExactSize{height}, Layout.ScrollVertically{}, Geometry.AlignedLayer{Enclosure.Insets{x, y}, Geometry.Leading{}, Geometry.Leading{}})

def selected_style( +selected: Bool, +style: Source.Style) -> Source.Style:
  match selected:
    case False{}: style
    case True{}:
      Source.Style{layout, font, Design.Chrome{foreground, background, border, width, radius, shadow}, states} = style
      Source.Style{layout, font, Design.Chrome{foreground, background, Design.ThemeToken{"--color-token-text-link-foreground"}, width, radius, shadow}, states}

def found_node_index( +found: Bool, +index: Nat, +remaining: Nat) -> Nat:
  match found:
    case True{}: index
    case False{}: remaining

def node_index( +nodes: +List<J.Json>, +identity: String, +index: Nat) -> Nat:
  match nodes:
    case Nil{}: index
    case Con{node, rest}: found_node_index(String.eq(prop(node, "identity"), identity), index, node_index(rest, identity, 1n+index))

def graph_edge_path( +self: Bool, +x: Nat, +y: Nat, +target_x: Nat, +target_y: Nat) -> String:
  match self:
    case True{}: "M " ++ Nat.show(x) ++ " " ++ Nat.show(y) ++ " C " ++ Nat.show(Nat.add(x, 60n)) ++ " " ++ Nat.show(Nat.sub(y, 60n)) ++ " " ++ Nat.show(Nat.add(x, 60n)) ++ " " ++ Nat.show(Nat.add(y, 60n)) ++ " " ++ Nat.show(x) ++ " " ++ Nat.show(Nat.add(y, 10n))
    case False{}: "M " ++ Nat.show(x) ++ " " ++ Nat.show(y) ++ " C " ++ Nat.show(Nat.add(x, 30n)) ++ " " ++ Nat.show(y) ++ " " ++ Nat.show(Nat.sub(target_x, 30n)) ++ " " ++ Nat.show(target_y) ++ " " ++ Nat.show(target_x) ++ " " ++ Nat.show(target_y) ++ " l -8 -4 m 8 4 l -8 4"

def edge_path( +source: GraphGeometry, +target: GraphGeometry, +self: Bool) -> String:
  match source target:
    case GraphGeometry{x, y, width, height} GraphGeometry{target_x, target_y, target_width, target_height}:
      graph_edge_path(self, Nat.add(x, width), Nat.add(y, Nat.div(height, 2n)), target_x, Nat.add(target_y, Nat.div(target_height, 2n)))

def graph_paths( +edges: +List<J.Json>, +nodes: +List<J.Json>, +attrs: J.Json) -> +List<Source.DrawingPath>:
  match edges:
    case Nil{}: Nil{}
    case Con{+edge, rest}: Source.DrawingPath{edge_path(graph_geometry(node_index(nodes, prop(edge, "sourceIdentity"), 0n), attrs), graph_geometry(node_index(nodes, prop(edge, "targetIdentity"), 0n), attrs), String.eq(prop(edge, "sourceIdentity"), prop(edge, "targetIdentity")))} <> graph_paths(rest, nodes, attrs)

def graph_drawing( +key: Identity.Key, +attrs: J.Json, +visual: Design.Style, +size: Enclosure.Extent) -> Source.Node:
  Enclosure.Extent{+width, +height} = size
  Source.Glyph{key, Source.Drawing{"0 0 " ++ Nat.show(width) ++ " " ++ Nat.show(height), graph_paths(J.items(J.get(attrs, "edges")), J.items(J.get(attrs, "nodes")), attrs), width, height, Source.StrokedDrawing{15n}}, Factory.glyph_style(visual, width, height)}

def canvas_style( +style: Source.Style, +size: Enclosure.Extent) -> Source.Style:
  Enclosure.Extent{width, height} = size
  dimensions(layered_style(style), Layout.Layered{}, Layout.ExactSize{width}, Layout.ExactSize{height}, Layout.Confined{}, Geometry.InFlow{})

def content_style( +tag: String, +attrs: J.Json, +visual: Design.Style) -> Source.Style:
  match tag:
    case "row-layout": dimensions(ordinary_style(visual, attrs), Layout.ResponsiveHorizontal{}, Layout.StretchSize{}, Layout.NaturalSize{}, Layout.Confined{}, Geometry.InFlow{})
    case "grid": dimensions(ordinary_style(visual, attrs), Layout.Vertical{}, Layout.StretchSize{}, Layout.NaturalSize{}, Layout.Confined{}, Geometry.InFlow{})
    case "card": enclosed(ordinary_style(visual, attrs))
    case "badge": enclosed(ordinary_style(visual, attrs))
    case "table": dimensions(ordinary_style(visual, attrs), Layout.Vertical{}, Layout.StretchSize{}, Layout.LimitedSize{40n, 360n, 160n}, Layout.ScrollBoth{}, Geometry.InFlow{})
    case "@table-row": dimensions(ordinary_style(visual, attrs), Layout.Horizontal{}, Layout.StretchSize{}, Layout.NaturalSize{}, Layout.Confined{}, Geometry.InFlow{})
    case "@table-cell": dimensions(ordinary_style(visual, attrs), Layout.Vertical{}, Layout.LimitedSize{100n, 40n, 100n}, Layout.NaturalSize{}, Layout.Confined{}, Geometry.InFlow{})
    case "@graph-viewport": dimensions(ordinary_style(visual, attrs), Layout.Vertical{}, Layout.StretchSize{}, Layout.ExactSize{420n}, Layout.ScrollBoth{}, Geometry.InFlow{})
    case "@graph-canvas": canvas_style(ordinary_style(visual, attrs), canvas_size(attrs))
    case "@graph-node": selected_style(J.boolean(J.get(attrs, "@selected")), graph_node_style(ordinary_style(visual, attrs), graph_geometry(Scene.natural(J.get(attrs, "index"), 0n), attrs)))
    case _: ordinary_style(visual, attrs)

def table_cell_role( +header: Bool) -> +List<Source.Attribute>:
  match header:
    case True{}: [Source.RoleAttribute{"columnheader"}]
    case False{}: [Source.RoleAttribute{"cell"}]

def roles( +tag: String, +attrs: J.Json) -> +List<Source.Attribute>:
  match tag:
    case "table": [Source.RoleAttribute{"table"}]
    case "@table-row": [Source.RoleAttribute{"row"}]
    case "@table-cell": Source.AriaAttribute{"sort", prop(attrs, "sort")} <> table_cell_role(J.boolean(J.get(attrs, "header")))
    case "@graph-list": [Source.RoleAttribute{"list"}, Source.AriaAttribute{"label", "图节点状态"}]
    case "@chart-summary": [Source.RoleAttribute{"list"}, Source.AriaAttribute{"label", "图表数据"}]
    case _: Nil{}

def heading_text( +label: String, +key: Identity.Key, +visual: Design.Style, +children: +List<Source.Node>) -> +List<Source.Node>:
  match label:
    case "": children
    case other: text(Identity.part(key, "label"), other, visual) <> children

def heading(+key: Identity.Key, +attrs: J.Json, +visual: Design.Style, +children: +List<Source.Node>) -> +List<Source.Node>:
  heading_text(prop(attrs, "label"), key, visual, children)

def task_approval( +awaiting: Bool) -> String:
  match awaiting:
    case True{}: " · 等待人工审批"
    case False{}: ""

def task_text( +value: J.Json) -> String:
  match value:
    case J.Null{}: "任务不存在"
    case other: prop(other, "title") ++ " · " ++ prop(other, "statusLabel") ++ " · " ++ prop(other, "phase") ++ task_approval(J.boolean(J.get(other, "awaitingHuman")))

def stale_status(+key: Identity.Key, +visual: Design.Style) -> Source.Node:
  box(Identity.part(key, "stale-status"), Source.Output{}, dimensions(ordinary_style(visual, J.Object{Nil{}}), Layout.Horizontal{}, Layout.StretchSize{}, Layout.ExactSize{Typography.resolved_line_height(Typography.resolved(Authored.parent_font(visual)))}, Layout.ScrollHorizontally{}, Geometry.InFlow{}), [Source.DataAttribute{"interactive-stale", ""}, Source.RoleAttribute{"status"}], [Factory.text(Identity.part(key, "stale-text"), "连接已断开，显示上次同步状态", Source.ExplicitFont{Authored.parent_font(visual)}, Typography.SingleLine{})])

def leaf( +tag: String, +key: Identity.Key, +attrs: J.Json, +visual: Design.Style, +children: +List<Source.Node>) -> Source.Node:
  match tag:
    case "text": box(key, Source.Paragraph{}, ordinary_style(visual, attrs), Nil{}, [text(Identity.part(key, "text"), prop(attrs, "label"), visual)])
    case "badge": box(key, Source.Span{}, content_style(tag, attrs, visual), Nil{}, [text(Identity.part(key, "text"), prop(attrs, "label"), visual)])
    case "metric": box(key, Source.Output{}, ordinary_style(visual, attrs), Nil{}, [text(Identity.part(key, "label"), prop(attrs, "label"), visual), text(Identity.part(key, "value"), Scene.formatted(J.get(attrs, "value"), prop(attrs, "format")), visual)])
    case "markdown": box(key, Source.Div{}, ordinary_style(visual, attrs), Nil{}, [Source.RichText{Identity.part(key, "markdown"), ordinary_style(visual, attrs), Source.RichContent{None{}, prop(attrs, "value"), Source.RichPolicy{Source.CodeSurface{Enclosure.Frame{Enclosure.ambient(8n, 8n), Enclosure.EmbeddedContent{8n}}, visual_chrome(visual)}, 0n, 12n, 24n, Typography.with_tier(Authored.parent_font(visual), Typography.CodeBody{}), False{}}}, Nil{}, Some{Identity.encode(key)}}])
    case "task-node": box(key, Source.Div{}, ordinary_style(visual, attrs), Nil{}, heading(key, attrs, visual, [text(Identity.part(key, "task"), task_text(J.get(attrs, "task")), visual)]))
    case "resource-view": box(key, Source.Div{}, content_style(tag, attrs, visual), roles(tag, attrs), stale_status(key, visual) <> heading(key, attrs, visual, children))
    case "@chart-plot": plot(key, attrs, visual)
    case "@graph-edges": box(key, Source.Div{}, canvas_style(ordinary_style(visual, attrs), canvas_size(attrs)), Nil{}, [graph_drawing(Identity.part(key, "drawing"), attrs, visual, canvas_size(attrs))])
    case _: box(key, Source.Div{}, content_style(tag, attrs, visual), roles(tag, attrs), heading(key, attrs, visual, children))

def render_leaf(+node: UI.ExpandedNode, +key: Identity.Key, +visual: Design.Style, +children: +List<Source.Node>) -> Source.Node:
  UI.ExpandedNode{identity, occurrence, tag, attrs, binding, original_children} = node
  leaf(tag, key, attrs, visual, children)

def render_binding( +binding: UI.Binding, +key: Identity.Key, +node: UI.ExpandedNode, +visual: Design.Style, +representation: Controls.Representation, +children: +List<Source.Node>, +parameters: Design.LayoutParameters) -> Source.Node:
  match binding:
    case UI.FieldBinding{state_id, schema, raw, canonical, validation, enabled}: input(key, node, visual, representation, parameters)
    case UI.ActionBinding{kind, enabled, pending}: button(key, visual, representation, parameters)
    case _: render_leaf(node, key, visual, children)

def semantic_binding(+binding: UI.Binding, +key: Identity.Key, +node: Source.Node) -> Source.Node:
  match binding:
    case UI.FieldBinding{state_id, schema, raw, canonical, validation, enabled}: node
    case _: decorate(node, Factory.binding_attributes(key))

def spin_glyph(+key: Identity.Key, +visual: Design.Style) -> Source.Node:
  box(Identity.part(key, "motion-glyph"), Source.Span{}, dimensions(ordinary_style(visual, J.Object{Nil{}}), Layout.Horizontal{}, Layout.ExactSize{16n}, Layout.ExactSize{16n}, Layout.Confined{}, Geometry.InFlow{}), [Source.DataAttribute{"interactive-motion-glyph", ""}, Source.AriaAttribute{"hidden", "true"}], [Authored.glyph(Identity.part(key, "spinner"), Controls.Spinner{}, visual, 16n)])

def motion_node(+motion: String, +key: Identity.Key, +node: Source.Node, +visual: Design.Style) -> Source.Node:
  match motion:
    case "spin": box(Identity.part(key, "motion-wrapper"), Source.Div{}, dimensions(ordinary_style(visual, J.Object{[J.Field{"gap", J.Text{"sm"}}]}), Layout.Horizontal{}, Layout.StretchSize{}, Layout.NaturalSize{}, Layout.Confined{}, Geometry.InFlow{}), Nil{}, [spin_glyph(key, visual), node])
    case _: node

def render(+key: Identity.Key, +node: UI.ExpandedNode, +visual: Design.Style, +representation: Controls.Representation, +children: +List<Source.Node>, +parameters: Design.LayoutParameters) -> Source.Node:
  UI.ExpandedNode{identity, occurrence, +tag, +attrs, +binding, original_children} = node
  decorate(motion_node(prop(attrs, "motion"), key, semantic_binding(binding, key, render_binding(binding, key, node, visual, representation, children, parameters)), visual), common(key, attrs, tag))

def region(+key: Identity.Key, +identity: Code.Identity, +source_visible: Bool, +visual: Design.Style, +children: +List<Source.Node>) -> +List<Source.Node>:
  [Source.NativeAttachment{key, Source.InteractiveTarget{identity}, Source.DataAttribute{"interactive-region", ""} <> Factory.binding_attributes(key), ordinary_style(visual, J.Object{Nil{}}),
     box(Identity.part(key, "pending-status"), Source.Output{}, dimensions(ordinary_style(visual, J.Object{Nil{}}), Layout.Horizontal{}, Layout.StretchSize{}, Layout.ExactSize{Typography.resolved_line_height(Typography.resolved(Authored.parent_font(visual)))}, Layout.ScrollHorizontally{}, Geometry.InFlow{}), [Source.DataAttribute{"interactive-pending", ""}, Source.RoleAttribute{"status"}], [Factory.text(Identity.part(key, "pending-text"), "正在更新显示", Source.ExplicitFont{Authored.parent_font(visual)}, Typography.SingleLine{})]) <> children},
   Source.NativeAttachment{Identity.part(key, "source"), Source.InteractiveSourceTarget{identity, source_visible}, Nil{}, ordinary_style(visual, J.Object{Nil{}}), Nil{}},
   Source.NativeAttachment{Identity.part(key, "frame"), Source.InteractiveFrameTarget{identity, True{}}, [Source.DataAttribute{"interactive-active", "true"}], ordinary_style(visual, J.Object{Nil{}}), Nil{}}]
