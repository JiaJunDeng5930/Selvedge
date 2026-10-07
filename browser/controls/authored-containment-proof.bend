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

import ./authored-containment-rules.bend as Rule

def reading_encoding(+task: Nat, +generation: Nat, +part: Reading.Part) -> Rule.reading_encoding(task, generation, part):
  {==}

def encoded_sequence(+attribute: Source.Attribute, +rest: +List<Source.Attribute>) -> Rule.encoded_sequence(attribute, rest):
  {==}

def page_context(+previous: Maybe<&2, Reading.Context>, +task: Nat, +generation: Nat) -> Rule.page_context(previous, task, generation):
  {==}

def cleared_context(+previous: Maybe<&2, Reading.Context>) -> Rule.cleared_context(previous):
  {==}

def scoped_node(+key: Identity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Design.Node>, +rest: +List<Design.Node>, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> Rule.scoped_node(key, semantic, label, role, meaning, visual, control, children, rest, parameters, context):
  {==}

def partition_frame(+key: Identity.Key, +tag: Source.BoxTag, +visual: Design.Style, +direction: Model.Direction, +part: Enclosure.Part, +arrangement: Enclosure.Arrangement, +content: +List<Source.Node>) -> Rule.partition_frame(key, tag, visual, direction, part, arrangement, content):
  {==}

def dialog_construction(+key: Identity.Key, +label: String, +meaning: InterfaceView.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Authored.Child>, +parameters: Design.LayoutParameters) -> Rule.dialog_construction(key, label, meaning, visual, control, children, parameters):
  {==}

def timeline_root(+context: Reading.Context, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +visual: Design.Style) -> Rule.timeline_root(context, key, tag, style, attributes, children, visual):
  {==}

def composer_root(+context: Reading.Context, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +visual: Design.Style) -> Rule.composer_root(context, key, tag, style, attributes, children, visual):
  {==}

def bound_construction(+children: +List<Authored.Child>, +key: Identity.Key, +semantic: String, +label: String, +role: InterfaceView.Role, +meaning: InterfaceView.Meaning, +visual: Design.Style, +control: Controls.Representation, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> Rule.bound_construction(children, key, semantic, label, role, meaning, visual, control, parameters, context):
  {==}

def body_scroll_allocation(+value: Source.Style) ->
  {Rule.body_scroll_allocation(Authored.dialog_partition_style(Enclosure.Body{}, value)) == True{} : Bool}:
  Source.Style{layout, font, chrome, states} = value
  Source.Layout{direction, main, cross, frame, width, height, minimum, scroll, position} = layout
  {==}

def native_attribute_owner(+key: Identity.Key, +previous: String) -> Rule.native_attribute_owner(key, previous):
  {==}

def native_attribute_choice(+owned: Bool, +key: Identity.Key, +name: String, +value: String) -> Rule.native_attribute_choice(owned, key, name, value):
  match owned:
    case True{}: {==}
    case False{}: {==}

def native_attribute_data(+key: Identity.Key, +name: String, +value: String) -> Rule.native_attribute_data(key, name, value):
  native_attribute_choice(String.eq(name, "native-key"), key, name, value)

def native_attribute_other(+key: Identity.Key, +attribute: Source.Attribute) -> Rule.native_attribute_other(key, attribute):
  match attribute:
    case Source.DataAttribute{name, value}: True{}
    case Source.ReadingAttribute{binding}: {==}
    case Source.EditorBindingAttribute{owner}: {==}
    case Source.AriaAttribute{name, value}: {==}
    case Source.RoleAttribute{value}: {==}
    case Source.TitleAttribute{value}: {==}
    case Source.TabIndexAttribute{value}: {==}
    case Source.ValueAttribute{value}: {==}
    case Source.CheckedAttribute{}: {==}
    case Source.OpenAttribute{}: {==}
    case Source.DraggableAttribute{value}: {==}
    case Source.InertAttribute{}: {==}

def native_attributes_nil(+key: Identity.Key) -> Rule.native_attributes_nil(key):
  {==}

def native_attributes_cons(+key: Identity.Key, +attribute: Source.Attribute, +rest: +List<Source.Attribute>) -> Rule.native_attributes_cons(key, attribute, rest):
  {==}

def native_decoration(+node: Source.Node, +extra: +List<Source.Attribute>) -> Rule.native_decoration(node, extra):
  match node:
    case Source.Box{key, tag, style, attrs, children}: {==}
    case Source.Control{key, tag, style, attrs, name, enabled, first, remaining, children}: {==}
    case Source.Field{key, kind, style, attrs, value, placeholder, options, policy, name, enabled, first, remaining}: {==}
    case Source.Text{key, value, font, wrapping}: {==}
    case Source.Glyph{key, drawing, style}: {==}
    case Source.RichText{key, style, content, attachments, native_owner}: {==}
    case Source.NativeAttachment{key, target, attrs, style, children}: {==}

def Rule.evidence():
  Rule.Requirements{native_attribute_owner, native_attribute_data, native_attribute_other, native_attributes_nil, native_attributes_cons, native_decoration, body_scroll_allocation}
