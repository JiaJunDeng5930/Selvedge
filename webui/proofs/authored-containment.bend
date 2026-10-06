import Base
import ../../core/ui-identity.bend as Identity
import ../../core/interface.bend as UI
import ../../core/user-conversation.bend as Conversation
import ../authored.bend as Authored
import ../source.bend as Source
import ../reading-binding.bend as Reading
import ../design.bend as Design
import ../controls.bend as Controls
import ../enclosure.bend as Enclosure
import ../physical-space.bend as Model
import ../document.bend as Doc
import ../physical-renderer.bend as Renderer
import ../authored-primitives.bend as Factory

import ../authored-containment-rules.bend as Rule

def reading_encoding(+task: Nat, +generation: Nat, +part: Reading.Part) -> Rule.reading_encoding(task, generation, part):
  {==}

def encoded_sequence(+attribute: Source.Attribute, +rest: +List<Source.Attribute>) -> Rule.encoded_sequence(attribute, rest):
  {==}

def page_context(+previous: Maybe<&2, Reading.Context>, +task: Nat, +generation: Nat) -> Rule.page_context(previous, task, generation):
  {==}

def cleared_context(+previous: Maybe<&2, Reading.Context>) -> Rule.cleared_context(previous):
  {==}

def scoped_node(+key: Identity.Key, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Design.Node>, +rest: +List<Design.Node>, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> Rule.scoped_node(key, semantic, label, role, meaning, visual, control, children, rest, parameters, context):
  {==}

def partition_frame(+key: Identity.Key, +tag: Source.BoxTag, +visual: Design.Style, +direction: Model.Direction, +part: Enclosure.Part, +arrangement: Enclosure.Arrangement, +content: +List<Source.Node>) -> Rule.partition_frame(key, tag, visual, direction, part, arrangement, content):
  {==}

def dialog_construction(+key: Identity.Key, +label: String, +meaning: UI.Meaning, +visual: Design.Style, +control: Controls.Representation, +children: +List<Authored.Child>, +parameters: Design.LayoutParameters) -> Rule.dialog_construction(key, label, meaning, visual, control, children, parameters):
  {==}

def timeline_root(+context: Reading.Context, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +visual: Design.Style) -> Rule.timeline_root(context, key, tag, style, attributes, children, visual):
  {==}

def composer_root(+context: Reading.Context, +key: Identity.Key, +tag: Source.BoxTag, +style: Source.Style, +attributes: +List<Source.Attribute>, +children: +List<Source.Node>, +visual: Design.Style) -> Rule.composer_root(context, key, tag, style, attributes, children, visual):
  {==}

def bound_construction(+children: +List<Authored.Child>, +key: Identity.Key, +semantic: String, +label: String, +role: UI.Role, +meaning: UI.Meaning, +visual: Design.Style, +control: Controls.Representation, +parameters: Design.LayoutParameters, +context: Maybe<&2, Reading.Context>) -> Rule.bound_construction(children, key, semantic, label, role, meaning, visual, control, parameters, context):
  {==}
