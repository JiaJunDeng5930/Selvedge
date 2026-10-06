import Base
import ../core/ui-identity.bend as Identity
import ../core/interface.bend as UI
import ../core/user-conversation.bend as Conversation
import ./authored.bend as Authored
import ./source.bend as Source
import ./reading-binding.bend as Reading
import ./design.bend as Design
import ./controls.bend as Controls
import ./enclosure.bend as Enclosure
import ./physical-space.bend as Model
import ./document.bend as Doc
import ./physical-renderer.bend as Renderer
import ./authored-primitives.bend as Factory

def reading_encoding(+task: Nat, +generation: Nat, +part: Reading.Part) -> Type:
  {Source.attribute_properties(Source.ReadingAttribute{Reading.Binding{Reading.Context{task, generation}, part}}) ==
    [Doc.Property{"data-reading-task", Nat.show(task)}, Doc.Property{"data-reading-generation", Nat.show(generation)}, Doc.Property{"data-reading-" ++ Reading.part_name(part), ""}] : +List<Doc.Property>}

def encoded_sequence(+attribute: Source.Attribute, +rest: +List<Source.Attribute>) -> Type:
  {Renderer.attributes(attribute <> rest) == List.append(&2, Doc.Property, Source.attribute_properties(attribute), Renderer.attributes(rest)) : +List<Doc.Property>}

def page_context(+previous: Maybe<&2, Reading.Context>, +task: Nat, +generation: Nat) -> Type:
  {Authored.context_from_meaning(previous, UI.PageContext{Some{Conversation.Identity{task, generation}}}) == Some{Reading.Context{task, generation}} : Maybe<&2, Reading.Context>}

def cleared_context(+previous: Maybe<&2, Reading.Context>) -> Type:
  {Authored.context_from_meaning(previous, UI.PageContext{None{}}) == None{} : Maybe<&2, Reading.Context>}

# This equation binds the context propagation to the production forest descent.
def scoped_node(+key: Identity.Key, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Design.Node>, +rest: +List<Design.Node>, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> Type:
  {Authored.forest_in_context(Design.Node{key, semantic, label, role, meaning, visual, control, children} <> rest, parameters, context) ==
    Authored.combine(Authored.construct_in_context(Authored.forest_in_context(children, parameters, Authored.context_from_meaning(context, meaning)), key, semantic, label, role, meaning, visual, control, parameters, Authored.context_from_meaning(context, meaning)), Authored.forest_in_context(rest, parameters, context)) : Authored.Forest}

def partition_frame(+key: Identity.Key, +tag: Source.BoxTag, +visual: Design.Style, +direction: Model.Direction, +part: Enclosure.Part, +arrangement: Enclosure.Arrangement, +content: +List<Source.Node>) -> Type:
  {Authored.dialog_partition(key, tag, visual, direction, part, arrangement, content) ==
    Source.Box{key, tag, Factory.with_frame(Factory.content_style(visual, direction, Model.StretchSize{}, Model.NaturalSize{}, 0n), Enclosure.Frame{Enclosure.partition(part), arrangement}), Nil{}, content} : Source.Node}

def dialog_construction(+key: Identity.Key, +label: String, +meaning: UI.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Authored.Child>, +parameters: Design.LayoutParameters) -> Type:
  {Authored.regular(key, label, UI.Dialog{}, meaning, visual, control, children, parameters) == Authored.regular_content(key, label, UI.Dialog{}, meaning, visual, control, children, parameters, Authored.dialog_content(key, label, visual, children)) : Source.Node}

def timeline_root(+context: Reading.Context, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +visual: Design.Style) -> Type:
  {Authored.reading_box(context, UI.Timeline{}, Source.Box{key, tag, style, attributes, children}, visual) ==
    Source.Box{key, tag, style, List.append(&2, Source.Attribute, attributes, [Source.ReadingAttribute{Reading.Binding{context, Reading.Scroll{}}}]),
      [Source.Box{Identity.part(key, "@reading-content"), Source.Div{}, Factory.with_frame(Factory.content_style(visual, Model.Vertical{}, Model.StretchSize{}, Model.NaturalSize{}, 0n), Enclosure.Frame{Enclosure.ambient(0n, 0n), Enclosure.EmbeddedContent{0n}}), [Source.ReadingAttribute{Reading.Binding{context, Reading.Content{}}}], children}]} : Source.Node}

def composer_root(+context: Reading.Context, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +visual: Design.Style) -> Type:
  {Authored.reading_box(context, UI.Composer{}, Source.Box{key, tag, style, attributes, children}, visual) ==
    Source.Box{key, tag, style, List.append(&2, Source.Attribute, attributes, [Source.ReadingAttribute{Reading.Binding{context, Reading.Dock{}}}]), children} : Source.Node}

def bound_construction(+children: +List<Authored.Child>, +key: Identity.Key, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning, +visual: Design.Style, +control: Controls.Representation, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> Type:
  {Authored.construct_in_context(Authored.Ready{children}, key, semantic, label, role, meaning, visual, control, parameters, context) ==
    Authored.finish_node(Authored.reading_root(context, key, role, Authored.authored_node(key, label, role, meaning, visual, control, children, parameters), visual), key, semantic, role, meaning, control) : Authored.Forest}
