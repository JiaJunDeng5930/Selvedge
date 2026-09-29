import Base
import ../architecture.bend as Architecture
import ../domain.bend as D
import ../../core/contract.bend as Contract
import ../../core/SYSTEM.bend as Core
import ../../core/laws.bend as CoreLaws
import ../../core/interface.bend as Interface
import ../../core/ui-world.bend as View
import ../../core/user-input.bend as U
import ../../core/user-experience.bend as E
import ../json.bend as J
import ./conversation.bend as Conversation

def absent_input(+surface: Interface.Surface, +key: String, +gesture: Interface.Gesture,
  absent: {Interface.find_node(Interface.active_nodes(surface), key) == None{} : Maybe<&2, Interface.Node>}) ->
  {Interface.resolve(surface, key, gesture) == None{} : Maybe<&2, Core.Input>}:
  Equal.cong(Maybe<&2, Interface.Node>, Maybe<&2, Core.Input>, (node => Interface.resolve_source(node, gesture, surface)),
    Interface.find_node(Interface.active_nodes(surface), key), None{}, absent)

def stale_receipt(+draft: U.Draft, accepted: Bool, submitted: Nat, reply: J.Json) ->
  {E.settled_current(draft, False{}, accepted, submitted, reply) == draft : U.Draft}:
  U.Draft{revision, body, feedback} = draft
  {==}

def Architecture.surface():
  Contract.Requirements{
    input => program => session => services => CoreLaws.runtime_input(input, program, session, services),
    surface => key => gesture => absent => absent_input(surface, key, gesture, absent),
    capacity => state => key => {==},
    capacity => +state => Interface.assembled_content(Core.observe(capacity, state), state),
    reader => task => world => Conversation.timeline_history(reader, task, world),
    messages => offset => Conversation.grouped_history(messages, offset),
    groups => task => disclosures => Conversation.visible_history(groups, task, disclosures),
    messages => offset => task => disclosures => Conversation.observed_text(messages, offset, task, disclosures),
    task => text => previous => selected => world => {==},
    draft => accepted => submitted => reply => stale_receipt(draft, accepted, submitted, reply),
    revision => body => feedback => submitted => reply => {==},
    revision => title => description => stage => priority => owner => project => labels => attachments => assist => profile => {==},
    application => {==},
    input => {==},
    input => reason => {==}}
