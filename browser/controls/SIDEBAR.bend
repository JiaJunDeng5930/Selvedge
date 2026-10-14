import Base
import ../../bendlib/categories.bend as Categories
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/presentation/INFORMATION.bend as Information
import ../document/SOURCE.bend as Source
import ../document/MODEL.bend as Doc
import ../appearance/DESIGN.bend as Design
import ../appearance/TYPOGRAPHY.bend as T
import ../layout/ACTIVITY.bend as Activity
import ../layout/natural-size.bend as NaturalSize
import ../layout/HIERARCHY.bend as Hierarchy
import ../layout/physical-space.bend as Model
import ../layout/GEOMETRY.bend as Spatial
import ../layout/enclosure.bend as Enclosure
import ./PROGRAM.bend as Controls
import ./CONTROLS.bend as AuthoredControls
import ./authored-primitives.bend as Factory
import ./NAVIGATION.bend as Navigation

# Captured command fields come from a real authored native control.
type Command is Data:
  Command{key: UIIdentity.Key, style: Source.Style,
    attributes: +List<Source.Attribute>, name: String, enabled: Bool,
    first: Doc.DOMEvent, remaining: +List<Doc.DOMEvent>, children: +List<Source.Node>}

type Entry is Data:
  SingleAction{primary: Command, status: +List<Source.Node>}
  ProjectActions{toggle: Command, open: Command, create: Command, more: Command, visible: Bool}

def original(command: Command) -> Source.Node:
  Command{key, style, attributes, name, enabled, first, remaining, children} = command
  Source.Control{key, Source.Button{}, style, attributes, name, enabled, first, remaining, children}

def attributes(node: Source.Node, extra: +List<Source.Attribute>) -> Source.Node:
  match node:
    case Source.Box{key, tag, style, attrs, children}: Source.Box{key, tag, style, List.append(&2, Source.Attribute, attrs, extra), children}
    case Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}: Source.Control{key, tag, style, List.append(&2, Source.Attribute, attrs, extra), name, enabled, first, remaining, children}
    case other: other

def navigation_exposure(visible: Bool) -> Source.Exposure:
  match visible:
    case True{}: Source.Exposed{}
    case False{}: Source.Concealed{}



def navigation_length(nominal: Nat, visual: Design.Style) -> Nat:
  Design.Style{T.Presentation{tier, emphasis, scale}, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  T.scaled(NaturalSize.limit(), nominal, scale)

def navigation_target(+visual: Design.Style) -> Nat:
  Nat.max(Activity.supporting_minimum(Activity.initial()), navigation_length(32n, visual))

def navigation_gap(visual: Design.Style) -> Nat:
  navigation_length(8n, visual)

def indentation(depth: Nat, visual: Design.Style) -> Nat:
  Design.Style{T.Presentation{tier, emphasis, scale}, chrome, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  Nat.mul(depth, T.scaled(NaturalSize.limit(), 16n, scale))

def sized_style(value: Source.Style, width: Model.AxisSize) -> Source.Style:
  Source.Style{Source.Layout{direction, main, cross, frame, old_width, height, minimum, scroll, position}, font, chrome, states} = value
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}

def sized(+node: Source.Node, width: Model.AxisSize) -> Source.Node:
  match node:
    case Source.Box{key, tag, style, attrs, children}: Source.Box{key, tag, sized_style(style, width), attrs, children}
    case Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}: Source.Control{key, tag, sized_style(style, width), attrs, name, enabled, first, remaining, children}
    case _: node

def row_style_fields(value: Source.Style, gap: Nat, inset: Nat, vertical: Nat) -> Source.Style:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = value
  Source.Style{Source.Layout{Model.Horizontal{}, Spatial.Leading{}, Spatial.Centered{}, Enclosure.Frame{Enclosure.ambient(inset, vertical), Enclosure.EmbeddedContent{gap}}, width, height, minimum, scroll, position}, font, chrome, states}

def row_style(+visual: Design.Style, depth: Nat) -> Source.Style:
  row_style_fields(Factory.with_minimum(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Enclosure.Extent{0n, navigation_target(visual)}), navigation_gap(visual), navigation_length(8n, visual), 0n)

# Conceal only a slot's paint and exposure; its command fields and allocation stay.
def slot(key: UIIdentity.Key, +name: String, width: Model.AxisSize, visible: Bool, +visual: Design.Style, children: +List<Source.Node>) -> Source.Node:
  Source.Box{UIIdentity.Part{key, "@navigation-slot/" ++ name}, Source.Div{}, Factory.with_alignments(Factory.content_style(visual, Model.Horizontal{}, width, Model.NaturalSize{}, navigation_gap(visual)), Spatial.Leading{}, Spatial.Centered{}),
    [Source.DataAttribute{"navigation-slot", name}, Source.ExposureAttribute{navigation_exposure(visible)}], children}

def leading_requirement(role: Navigation.ContentRole, +visual: Design.Style) -> Nat:
  match role:
    case Navigation.DisclosureSlot{}: navigation_target(visual)
    case _: Activity.slot(NaturalSize.limit(), Design.style_text(visual))

def navigation_leading_fields(+key: UIIdentity.Key, role: Navigation.ContentRole, +offset: Nat, +required: Nat, +target: Nat, +visual: Design.Style, child: Source.Node) -> Source.Node:
  Source.Box{UIIdentity.part(key, "@leading-position"), Source.Div{}, Factory.content_style(visual, Model.Horizontal{}, Model.ExactSize{Nat.add(offset, required)}, Model.ExactSize{target}, 0n), Nil{},
    [Source.Box{UIIdentity.part(key, "@membership-indent"), Source.Div{}, Factory.content_style(visual, Model.Horizontal{}, Model.ExactSize{offset}, Model.ExactSize{target}, 0n), Nil{}, Nil{}},
     Source.Box{UIIdentity.part(key, "@leading-allocation"), Source.Div{}, Factory.with_alignments(Factory.content_style(visual, Model.Horizontal{}, Model.ExactSize{required}, Model.ExactSize{target}, 0n), Spatial.Centered{}, Spatial.Centered{}), Nil{},
       [Source.Box{UIIdentity.part(key, "@leading-target"), Source.Div{}, Factory.with_alignments(Factory.content_style(visual, Model.Horizontal{}, Model.ExactSize{required}, Model.ExactSize{required}, 0n), Spatial.Centered{}, Spatial.Centered{}), [Source.DataAttribute{"navigation-slot", Navigation.role_name(role)}], [child]}]}]}

# The complete sidebar allocates one rail from its actual independent targets.
def exact_width(style: Source.Style) -> Nat:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  match width:
    case Model.ExactSize{extent}: extent
    case _: 0n

def shared_leading_requirement(nodes: +List<Source.Node>) -> Nat:
  match nodes:
    case Nil{}: 0n
    case Con{Source.Box{UIIdentity.Part{key, "@leading-target"}, tag, style, attrs, children}, rest}: Nat.max(exact_width(style), shared_leading_requirement(rest))
    case Con{Source.Box{key, tag, style, attrs, children}, rest}: Nat.max(shared_leading_requirement(children), shared_leading_requirement(rest))
    case Con{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, rest}: Nat.max(shared_leading_requirement(children), shared_leading_requirement(rest))
    case Con{Source.NativeAttachment{key, target, attrs, style, children}, rest}: Nat.max(shared_leading_requirement(children), shared_leading_requirement(rest))
    case Con{other, rest}: shared_leading_requirement(rest)

def leading_position_width(nodes: +List<Source.Node>, rail: Nat) -> Nat:
  match nodes:
    case Con{Source.Box{key, tag, style, attrs, children}, rest}: Nat.add(exact_width(style), rail)
    case _: rail

def align_leading(nodes: +List<Source.Node>, +rail: Nat) -> +List<Source.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Source.Box{UIIdentity.Part{key, "@leading-position"}, tag, style, attrs, +children}, rest}:
      Source.Box{UIIdentity.Part{key, "@leading-position"}, tag, sized_style(style, Model.ExactSize{leading_position_width(children, rail)}), attrs, align_leading(children, rail)} <> align_leading(rest, rail)
    case Con{Source.Box{UIIdentity.Part{key, "@leading-allocation"}, tag, style, attrs, children}, rest}:
      Source.Box{UIIdentity.Part{key, "@leading-allocation"}, tag, sized_style(style, Model.ExactSize{rail}), attrs, children} <> align_leading(rest, rail)
    case Con{Source.Box{key, tag, style, attrs, children}, rest}: Source.Box{key, tag, style, attrs, align_leading(children, rail)} <> align_leading(rest, rail)
    case Con{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, rest}: Source.Control{key, tag, style, attrs, name, enabled, first, remaining, align_leading(children, rail)} <> align_leading(rest, rail)
    case Con{other, rest}: other <> align_leading(rest, rail)

def aligned_sidebar(+nodes: +List<Source.Node>) -> +List<Source.Node>:
  align_leading(nodes, shared_leading_requirement(nodes))

def navigation_caption_frame(frame: Enclosure.Frame) -> Enclosure.Frame:
  Enclosure.Frame{content, arrangement} = frame
  Enclosure.Frame{Enclosure.ambient(0n, Enclosure.block(content)), arrangement}

def navigation_title_style(value: Source.Style) -> Source.Style:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = value
  Source.Style{Source.Layout{direction, Spatial.Leading{}, cross, navigation_caption_frame(frame), Model.StretchSize{}, height, minimum, scroll, position}, font, chrome, states}

def navigation_title(node: Source.Node) -> Source.Node:
  match node:
    case Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}:
      attributes(Source.Control{key, tag, navigation_title_style(style), attrs, name, enabled, first, remaining, children}, [Source.DataAttribute{"navigation-slot", Navigation.role_name(Navigation.TitleSlot{})}])
    case _: attributes(sized(node, Model.StretchSize{}), [Source.DataAttribute{"navigation-slot", Navigation.role_name(Navigation.TitleSlot{})}])

def navigation_row(+key: UIIdentity.Key, +owner: UIIdentity.Key, +depth: Nat, visual: Design.Style, children: +List<Source.Node>) -> Source.Node:
  Source.Box{key, Source.Div{}, row_style(visual, depth), [Source.DataAttribute{"navigation-owner", UIIdentity.encode(owner)}, Source.DataAttribute{"navigation-depth", Nat.show(depth)}], children}


def capture(node: Source.Node) -> Maybe<&2, Command>:
  match node:
    case Source.Control{key, Source.Button{}, style, attrs, name, enabled, first, remaining, children}: Some{Command{key, style, attrs, name, enabled, first, remaining, children}}
    case _: None{}

def caption_nodes(nodes: +List<Source.Node>) -> +List<Source.Node>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Source.Text{key, value, font, wrapping}, rest}: Source.Text{key, value, font, T.SingleLine{}} <> caption_nodes(rest)
    case Con{Source.Box{key, tag, style, attrs, children}, rest}: Source.Box{key, tag, style, attrs, caption_nodes(children)} <> caption_nodes(rest)
    case Con{other, rest}: other <> caption_nodes(rest)

def title(+key: UIIdentity.Key, +visual: Design.Style, content: +List<Source.Node>) -> Source.Node:
  Source.Box{UIIdentity.part(key, "@title-content"), Source.Span{}, navigation_title_style(Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n)), [Source.DataAttribute{"navigation-slot", "title"}], caption_nodes(content)}

def identity_source(+key:UIIdentity.Key, +visual:Design.Style, content:+List<Source.Node>) -> Source.Node:
  match content:
    case Con{identity, Con{caption, Nil{}}}: identity
    case _: AuthoredControls.glyph(UIIdentity.part(key, "identity"), Controls.Conversation{}, visual, navigation_length(16n, visual))

def title_content(content:+List<Source.Node>) -> +List<Source.Node>:
  match content:
    case Con{identity, Con{caption, Nil{}}}: [caption]
    case other: other

def entry_leading_requirement(entry: Entry, visual: Design.Style) -> Nat:
  match entry:
    case SingleAction{primary, status}: leading_requirement(Navigation.IdentitySlot{}, visual)
    case ProjectActions{toggle, open, create, more, visible}: leading_requirement(Navigation.DisclosureSlot{}, visual)

def trailing_width(entry: Entry, +visual: Design.Style) -> Nat:
  match entry:
    case SingleAction{primary, status}: navigation_length(16n, visual)
    case ProjectActions{toggle, open, create, more, visible}: Nat.add(Nat.mul(2n, navigation_target(visual)), navigation_gap(visual))

# Source columns receive calibrated quantities as values at this shared boundary.
def single_source_fields(+key: UIIdentity.Key, +depth: Nat, +visual: Design.Style, command: Command, status: +List<Source.Node>, offset: Nat, leading: Nat, target: Nat, trailing: Nat) -> Source.Node:
  Command{command_key, style, attrs, name, enabled, first, remaining, +children} = command
  Source.Control{command_key, Source.Button{}, row_style(visual, depth), attrs, name, enabled, first, remaining,
    [navigation_leading_fields(key, Navigation.IdentitySlot{}, offset, leading, target, visual, identity_source(key, visual, children)),
     title(key, visual, title_content(children)),
     slot(key, "status", Model.ExactSize{trailing}, True{}, visual, status)]}

def entry_source_fields(+key: UIIdentity.Key, +owner: UIIdentity.Key, +depth: Nat, +visual: Design.Style, entry: Entry, offset: Nat, leading: Nat, +target: Nat, trailing: Nat) -> Source.Node:
  match entry:
    case SingleAction{primary, status}:
      Source.Box{key, Source.Div{}, Factory.with_frame(Factory.content_style(visual, Model.Horizontal{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}), [Source.DataAttribute{"navigation-owner", UIIdentity.encode(owner)}, Source.DataAttribute{"navigation-depth", Nat.show(depth)}], [single_source_fields(key, depth, visual, primary, status, offset, leading, target, trailing)]}
    case ProjectActions{toggle, open, create, more, visible}:
      navigation_row(key, owner, depth, visual,
        [navigation_leading_fields(key, Navigation.DisclosureSlot{}, offset, leading, target, visual, original(toggle)),
         navigation_title(original(open)),
         slot(key, "auxiliary", Model.ExactSize{trailing}, visible, visual, [sized(original(create), Model.ExactSize{target}), sized(original(more), Model.ExactSize{target})])])

def entry_source(+key: UIIdentity.Key, owner: UIIdentity.Key, +depth: Nat, +visual: Design.Style, +entry: Entry) -> Source.Node:
  entry_source_fields(key, owner, depth, visual, entry, indentation(depth, visual), entry_leading_requirement(entry, visual), navigation_target(visual), trailing_width(entry, visual))

type CollectionKind is Data:
  Collection{}
  Section{}
  Members{}

def collection_frame(kind: CollectionKind) -> Enclosure.Frame:
  match kind:
    case Collection{}: Hierarchy.grouped_frame(Hierarchy.initial(), Enclosure.ambient(0n, 0n))
    case Section{}: Hierarchy.heading_frame(Hierarchy.initial())
    case Members{}: Hierarchy.flat_member_frame(Hierarchy.initial())

def collection_source(+key: UIIdentity.Key, +kind: CollectionKind, +visual: Design.Style, +content: +List<Source.Node>) -> Source.Node:
  match kind content:
    case Section{} Con{header, Nil{}}: Source.Box{key, Source.Div{}, Factory.with_frame(Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), collection_frame(Section{})), Nil{}, [header]}
    case Section{} Con{header, members}:
      Source.Box{key, Source.Div{}, Factory.with_frame(Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), collection_frame(Section{})), Nil{},
        [header, Source.Box{UIIdentity.part(key, "children"), Source.Div{}, Factory.with_frame(Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Hierarchy.flat_member_frame(Hierarchy.initial())), [Source.DataAttribute{"navigation-members", UIIdentity.encode(key)}], members}]}
    case _ other: Source.Box{key, Source.Div{}, Factory.with_frame(Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), collection_frame(kind)), Nil{}, other}

type Observation is Data:
  Observation{key: UIIdentity.Key, owner: UIIdentity.Key, depth: Nat, visual: Design.Style, entry: Entry, node: Source.Node}

def source_correspondence(observation: Observation) -> Type:
  Observation{key, owner, depth, visual, entry, node} = observation
  {node == entry_source(key, owner, depth, visual, entry) : Source.Node}

type CommandFields is Data:
  CommandFields{key: UIIdentity.Key, tag: Source.ControlTag, attributes: +List<Source.Attribute>, name: String, enabled: Bool, first: Doc.DOMEvent, remaining: +List<Doc.DOMEvent>}

def forest_commands(nodes: +List<Source.Node>) -> +List<CommandFields>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, rest}: CommandFields{key, tag, attrs, name, enabled, first, remaining} <> forest_commands(rest)
    case Con{Source.Box{key, tag, style, attrs, children}, rest}: List.append(&2, CommandFields, forest_commands(children), forest_commands(rest))
    case Con{other, rest}: forest_commands(rest)

def command_fields(node: Source.Node) -> +List<CommandFields>:
  forest_commands([node])

def expected_commands(entry: Entry) -> +List<CommandFields>:
  match entry:
    case SingleAction{primary, status}: command_fields(original(primary))
    case ProjectActions{toggle, open, create, more, visible}: forest_commands([original(toggle), navigation_title(original(open)), original(create), original(more)])

def style_layout(style: Source.Style) -> Source.Layout:
  Source.Style{layout, font, chrome, states} = style
  layout

def row_children_layout(style: Source.Style, children: +List<Source.Node>) -> Source.Layout:
  match children:
    case Con{Source.Control{key, tag, control_style, attrs, name, enabled, first, remaining, content}, Nil{}}: style_layout(control_style)
    case _: style_layout(style)

def row_layout(node: Source.Node) -> Maybe<&2, Source.Layout>:
  match node:
    case Source.Box{key, tag, style, attrs, children}: Some{row_children_layout(style, children)}
    case _: None{}

def expected_row_layout_fields(value: Source.Style, +visual: Design.Style) -> Source.Layout:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = value
  Source.Layout{Model.Horizontal{}, Spatial.Leading{}, Spatial.Centered{}, Enclosure.Frame{Enclosure.ambient(navigation_length(8n, visual), 0n), Enclosure.EmbeddedContent{navigation_length(8n, visual)}}, Model.StretchSize{}, height, minimum, scroll, position}

def expected_row_layout(+visual: Design.Style) -> Source.Layout:
  expected_row_layout_fields(Factory.with_minimum(Factory.style(visual, Model.StretchSize{}, Model.NaturalSize{}, Model.Confined{}), Enclosure.Extent{0n, navigation_target(visual)}), visual)

def actual_commands(observation: Observation) -> Type:
  Observation{key, owner, depth, visual, entry, node} = observation
  {command_fields(node) == expected_commands(entry) : +List<CommandFields>}

def full_row(observation: Observation) -> Type:
  Observation{key, owner, depth, visual, entry, node} = observation
  {row_layout(node) == Some{expected_row_layout(visual)} : Maybe<&2, Source.Layout>}

def style_width(style:Source.Style) -> Model.AxisSize:
  Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states} = style
  width

def column_widths(nodes:+List<Source.Node>) -> +List<Model.AxisSize>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Source.Box{key, tag, style, attrs, children}, rest}: style_width(style) <> column_widths(rest)
    case Con{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}, rest}: style_width(style) <> column_widths(rest)
    case Con{other, rest}: column_widths(rest)

def row_content(children:+List<Source.Node>) -> +List<Source.Node>:
  match children:
    case Con{Source.Control{key, tag, style, attrs, name, enabled, first, remaining, content}, Nil{}}: content
    case other: other

def columns(node:Source.Node) -> +List<Model.AxisSize>:
  match node:
    case Source.Box{key, tag, style, attrs, children}: column_widths(row_content(children))
    case _: Nil{}

def first_aligned_node(node: Source.Node, +rail: Nat) -> Source.Node:
  match node:
    case Source.Box{key, tag, style, attrs, children}: Source.Box{key, tag, style, attrs, align_leading(children, rail)}
    case other: other

def local_axis(observation: Observation) -> Type:
  Observation{key, owner, depth, visual, entry, node} = observation
  {columns(node) == [Model.ExactSize{Nat.add(indentation(depth, visual), entry_leading_requirement(entry, visual))}, Model.StretchSize{}, Model.ExactSize{trailing_width(entry, visual)}] : +List<Model.AxisSize>}

def shared_axis(observation: Observation, +rail: Nat) -> Type:
  Observation{key, owner, depth, visual, entry, node} = observation
  {columns(first_aligned_node(node, rail)) == [Model.ExactSize{Nat.add(indentation(depth, visual), rail)}, Model.StretchSize{}, Model.ExactSize{trailing_width(entry, visual)}] : +List<Model.AxisSize>}

type Axes<-observation: Observation> is Type:
  Axes{local: local_axis(observation), shared: @+rail:Nat -> shared_axis(observation, rail)}

def common_axis(observation: Observation) -> Type:
  Axes<observation>

def source_style_background(style:Source.Style) -> Design.Paint:
  Source.Style{layout, font, Design.Chrome{foreground, background, border, border_width, radius, shadow}, states} = style
  background

def source_row_background(style:Source.Style, children:+List<Source.Node>) -> Design.Paint:
  match children:
    case Con{Source.Control{key, tag, control_style, attrs, name, enabled, first, remaining, content}, Nil{}}: source_style_background(control_style)
    case _: source_style_background(style)

def row_background(node:Source.Node) -> Maybe<&2, Design.Paint>:
  match node:
    case Source.Box{key, tag, style, attrs, children}: Some{source_row_background(style, children)}
    case _: None{}

def visual_background(visual:Design.Style) -> Design.Paint:
  Design.Style{text, Design.Chrome{foreground, background, border, border_width, radius, shadow}, alignment, flow, overflow, frame, minimum, maximum, states} = visual
  background

def background_preserved(observation:Observation) -> Type:
  Observation{key, owner, depth, visual, entry, node} = observation
  {row_background(node) == Some{visual_background(visual)} : Maybe<&2, Design.Paint>}

type Authored<-observation: Observation> is Type:
  Authored{source: source_correspondence(observation), commands: actual_commands(observation), allocation: full_row(observation), axes: common_axis(observation), background: background_preserved(observation)}

def authored(observation: Observation) -> Type:
  Authored<observation>

law construct:
  @+key:UIIdentity.Key -> @+owner:UIIdentity.Key -> @+depth:Nat -> @+visual:Design.Style -> @+entry:Entry -> Categories.Membership<Observation, authored>

def constructed_node(constructed: Categories.Membership<Observation, authored>) -> Source.Node:
  Categories.Membership{Observation{key, owner, depth, visual, entry, node}, evidence} = constructed
  node

law constructor_correspondence:
  @+key:UIIdentity.Key -> @+owner:UIIdentity.Key -> @+depth:Nat -> @+visual:Design.Style -> @+entry:Entry -> {constructed_node(construct(key, owner, depth, visual, entry)) == entry_source(key, owner, depth, visual, entry) : Source.Node}

type CollectionRequest is Data:
  CollectionRequest{key:UIIdentity.Key, kind:CollectionKind, visual:Design.Style, content:+List<Source.Node>}

def collection_request_source(request:CollectionRequest) -> Source.Node:
  CollectionRequest{key, kind, visual, content} = request
  collection_source(key, kind, visual, content)

type CollectionObservation is Data:
  CollectionObservation{request:CollectionRequest, node:Source.Node}

def source_frame(node:Source.Node) -> Maybe<&2, Enclosure.Frame>:
  match node:
    case Source.Box{key, tag, Source.Style{Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position}, font, chrome, states}, attrs, children}: Some{frame}
    case _: None{}

def collection_correspondence(observation:CollectionObservation) -> Type:
  CollectionObservation{request, node} = observation
  {node == collection_request_source(request) : Source.Node}

def request_frame(request:CollectionRequest) -> Enclosure.Frame:
  CollectionRequest{key, kind, visual, content} = request
  collection_frame(kind)

def hierarchy_allocation(observation:CollectionObservation) -> Type:
  CollectionObservation{request, node} = observation
  {source_frame(node) == Some{request_frame(request)} : Maybe<&2, Enclosure.Frame>}

type CollectionAuthored<-observation:CollectionObservation> is Type:
  CollectionAuthored{source:collection_correspondence(observation), hierarchy:hierarchy_allocation(observation)}

def collection_authored(observation:CollectionObservation) -> Type:
  CollectionAuthored<observation>

law construct_collection:
  @+request:CollectionRequest -> Categories.Membership<CollectionObservation, collection_authored>

def constructed_collection_node(constructed: Categories.Membership<CollectionObservation, collection_authored>) -> Source.Node:
  Categories.Membership{CollectionObservation{request, node}, evidence} = constructed
  node

law collection_constructor_correspondence:
  @+request:CollectionRequest -> {constructed_collection_node(construct_collection(request)) == collection_request_source(request) : Source.Node}
