import Base
import ../../interaction/IDENTITY.bend as Identity
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../interaction/conversation/MODEL.bend as Conversation
import ./MODEL.bend as Authored
import ../document/SOURCE.bend as Source
import ../reading/reading-binding.bend as Reading
import ../appearance/DESIGN.bend as Design
import ./PROGRAM.bend as Controls
import ../layout/enclosure.bend as Enclosure
import ../layout/physical-space.bend as Model
import ../document/MODEL.bend as Doc
import ../layout/RENDERER.bend as Renderer
import ./authored-primitives.bend as Factory

def reading_encoding(+task: Nat, +generation: Nat, +part: Reading.Part) -> Type:
  {Source.attribute_properties(Source.ReadingAttribute{Reading.Binding{Reading.Context{task, generation}, part}}) ==
    [Doc.Property{"data-reading-task", Nat.show(task)}, Doc.Property{"data-reading-generation", Nat.show(generation)}, Doc.Property{"data-reading-" ++ Reading.part_name(part), ""}] : +List<Doc.Property>}

def encoded_sequence(+attribute: Source.Attribute, +rest: +List<Source.Attribute>) -> Type:
  {Renderer.attributes(attribute <> rest) == List.append(&2, Doc.Property, Source.attribute_properties(attribute), Renderer.attributes(rest)) : +List<Doc.Property>}

def page_context(+previous: Maybe<&2, Reading.Context>, +task: Nat, +generation: Nat) -> Type:
  {Authored.context_from_meaning(previous, InterfaceView.PageContext{Some{Conversation.Identity{task, generation}}}) == Some{Reading.Context{task, generation}} : Maybe<&2, Reading.Context>}

def cleared_context(+previous: Maybe<&2, Reading.Context>) -> Type:
  {Authored.context_from_meaning(previous, InterfaceView.PageContext{None{}}) == None{} : Maybe<&2, Reading.Context>}

# This equation binds the context propagation to the production forest descent.
def scoped_node(+key: Identity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Design.Node>, +rest: +List<Design.Node>, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> Type:
  {Authored.forest_in_context(Design.Node{key, semantic, label, role, meaning, visual, control, children} <> rest, parameters, context) ==
    Authored.combine(Authored.construct_in_context(Authored.forest_in_context(children, parameters, Authored.context_from_meaning(context, meaning)), key, semantic, label, role, meaning, visual, control, parameters, Authored.context_from_meaning(context, meaning)), Authored.forest_in_context(rest, parameters, context)) : Authored.Forest}

def partition_frame(+key: Identity.Key, +tag: Source.BoxTag, +visual: Design.Style, +direction: Model.Direction, +part: Enclosure.Part, +arrangement: Enclosure.Arrangement, +content: +List<Source.Node>) -> Type:
  {Authored.dialog_partition(key, tag, visual, direction, part, arrangement, content) ==
    Source.Box{key, tag, Authored.dialog_partition_style(part, Factory.with_frame(Factory.content_style(visual, direction, Model.StretchSize{}, Model.NaturalSize{}, 0n), Enclosure.Frame{Enclosure.partition(part), arrangement})), Nil{}, content} : Source.Node}

def dialog_construction(+key: Identity.Key, +label: String, +meaning: InterfaceView.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Authored.Child>, +parameters: Design.LayoutParameters) -> Type:
  {Authored.regular(key, label, InterfaceView.Dialog{}, meaning, visual, control, children, parameters) == Authored.regular_content(key, label, InterfaceView.Dialog{}, meaning, visual, control, children, parameters, Authored.dialog_content(key, label, visual, children)) : Source.Node}

def timeline_root(+context: Reading.Context, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +visual: Design.Style) -> Type:
  {Authored.reading_box(context, InterfaceView.Timeline{}, Source.Box{key, tag, style, attributes, children}, visual) ==
    Source.Box{key, tag, style, List.append(&2, Source.Attribute, attributes, [Source.ReadingAttribute{Reading.Binding{context, Reading.ReadingViewport{}}}]),
      [Source.Box{Identity.part(key, "@reading-content"), Source.Div{}, Factory.with_frame(Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}), [Source.ReadingAttribute{Reading.Binding{context, Reading.Content{}}}], children}]} : Source.Node}

def composer_root(+context: Reading.Context, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +visual: Design.Style) -> Type:
  {Authored.reading_box(context, InterfaceView.Composer{}, Source.Box{key, tag, style, attributes, children}, visual) ==
    Source.Box{key, tag, style, List.append(&2, Source.Attribute, attributes, [Source.ReadingAttribute{Reading.Binding{context, Reading.Dock{}}}]), children} : Source.Node}

def bound_construction(+children: +List<Authored.Child>, +key: Identity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning, +visual: Design.Style, +control: Controls.Representation, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> Type:
  {Authored.construct_in_context(Authored.Ready{children}, key, semantic, label, role, meaning, visual, control, parameters, context) ==
    Authored.finish_node(Authored.reading_root(context, key, role, Authored.authored_node(key, label, role, meaning, visual, control, children, parameters), visual), key, semantic, role, meaning, control) : Authored.Forest}

def body_scroll_allocation(value: Source.Style) -> Bool:
  Source.Style{layout, font, chrome, states} = value
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  match height scroll:
    case Model.StretchSize{} Model.ScrollVertically{}: True{}
    case _ _: False{}

def native_attribute_owner(+key: Identity.Key, +previous: String) -> Type:
  {Authored.native_attribute(key, Source.DataAttribute{"native-key", previous}) == Source.DataAttribute{"native-key", Identity.encode(key)} : Source.Attribute}

def native_attribute_data_result(+owned: Bool, +key: Identity.Key, +name: String, +value: String) -> Source.Attribute:
  match owned:
    case True{}: Source.DataAttribute{"native-key", Identity.encode(key)}
    case False{}: Source.DataAttribute{name, value}

def native_attribute_choice(+owned: Bool, +key: Identity.Key, +name: String, +value: String) -> Type:
  {Authored.native_attribute_value(owned, key, name, value) == native_attribute_data_result(owned, key, name, value) : Source.Attribute}

def native_attribute_data(+key: Identity.Key, +name: String, +value: String) -> Type:
  {Authored.native_attribute(key, Source.DataAttribute{name, value}) == native_attribute_data_result(String.eq(name, "native-key"), key, name, value) : Source.Attribute}

def native_attribute_other(+key: Identity.Key, +attribute: Source.Attribute) -> Type:
  match attribute:
    case Source.DataAttribute{name, value}: Bool
    case other: {Authored.native_attribute(key, other) == other : Source.Attribute}

def native_attributes_nil(+key: Identity.Key) -> Type:
  {Authored.native_attributes(key, Nil{}) == Nil{} : +List<Source.Attribute>}

def native_attributes_cons(+key: Identity.Key, +attribute: Source.Attribute, +rest: +List<Source.Attribute>) -> Type:
  {Authored.native_attributes(key, attribute <> rest) == Authored.native_attribute(key, attribute) <> Authored.native_attributes(key, rest) : +List<Source.Attribute>}

def native_decoration_result(+node: Source.Node, +extra: +List<Source.Attribute>) -> Source.Node:
  match node:
    case Source.Box{key, tag, style, attrs, children}: Source.Box{key, tag, style, List.append(&2, Source.Attribute, attrs, Authored.native_attributes(key, extra)), children}
    case Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}: Source.Control{key, tag, style, List.append(&2, Source.Attribute, attrs, Authored.native_attributes(key, extra)), name, enabled, first, remaining, children}
    case Source.Field{key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}: Source.Field{key, kind, style, List.append(&2, Source.Attribute, attrs, Authored.native_attributes(key, extra)), value, placeholder, options, policy, name, enabled, first, remaining}
    case other: other

def native_decoration(+node: Source.Node, +extra: +List<Source.Attribute>) -> Type:
  {Authored.add_attributes(node, extra) == native_decoration_result(node, extra) : Source.Node}

type Requirements is Type:
  Requirements{
    native_attribute_owner: @+key:Identity.Key -> @+previous:String -> native_attribute_owner(key, previous),
    native_attribute_data: @+key:Identity.Key -> @+name:String -> @+value:String -> native_attribute_data(key, name, value),
    native_attribute_other: @+key:Identity.Key -> @+attribute:Source.Attribute -> native_attribute_other(key, attribute),
    native_attributes_nil: @+key:Identity.Key -> native_attributes_nil(key),
    native_attributes_cons: @+key:Identity.Key -> @+attribute:Source.Attribute -> @+rest:+List<Source.Attribute> -> native_attributes_cons(key, attribute, rest),
    native_decoration: @+node:Source.Node -> @+extra:+List<Source.Attribute> -> native_decoration(node, extra),
    body_scroll_allocation: @+value:Source.Style ->
      {body_scroll_allocation(Authored.dialog_partition_style(Enclosure.Body{}, value)) == True{} : Bool}}

law evidence:
  Requirements
