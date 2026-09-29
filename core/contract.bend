import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as Program
import ../UI.bend as UI
import ../bendlib/domain.bend as D
import ../BOARD.bend as B
import ../bendlib/json.bend as J
import ../bendlib/conversation-spec.bend as ConversationSpec
import ./SYSTEM.bend as Core
import ./laws.bend as CoreLaws
import ./interface.bend as Interface
import ./user-input.bend as U
import ./user-experience.bend as E
import ./user-conversation.bend as Conversation
import ./ui-world.bend as View
import ./client-services.bend as Services

# Evidence about the public product entry, not a parallel presentation engine.
# Platform realization requirements belong to webui and do not enter this type.
type Requirements is Type:
  Requirements{
    runtime: @+input:M.Input -> @+program:M.World() -> @+session:E.Session -> @+services:Services.State ->
      {CoreLaws.runtime(UI.step(UI.Engine{input}, Core.State{E.Application{program, session}, services})) == Program.transition(input, program) : M.Decision()},
    absent_input: @+surface:Interface.Surface -> @+key:String -> @+gesture:Interface.Gesture ->
      @absent:{Interface.find_node(Interface.active_nodes(surface), key) == None{} : Maybe<&2, Interface.Node>} ->
      {Interface.resolve(surface, key, gesture) == None{} : Maybe<&2, Core.Input>},
    absent_preserves: @capacity:View.Capacity -> @+state:Core.State -> @key:String ->
      {Interface.perform(capacity, state, key, None{}) == Interface.apply_input(None{}, state) : Core.Decision},
    observation: @+capacity:View.Capacity -> @+state:Core.State ->
      {Interface.content(UI.observe(capacity, state)) == Core.observe(capacity, state) : Core.Scene},
    timeline: @+reader:E.Reader -> @+task:D.Task -> @+world:M.World() ->
      {ConversationSpec.timeline_sources(Conversation.timeline(reader, task, world)) == D.history_messages(D.task_history(task), Nil{}) : +List<D.Message>},
    grouped_history: @+messages:+List<D.Message> -> @+offset:Nat ->
      {ConversationSpec.sources(Conversation.groups(messages, offset)) == messages : +List<D.Message>},
    visible_history: @+groups:+List<Conversation.Group> -> @+task:Nat -> @+disclosures:+List<E.Disclosure> ->
      {ConversationSpec.visible_sources(Conversation.visible(groups, task, disclosures)) == ConversationSpec.sources(groups) : +List<D.Message>},
    displayed_text: @+messages:+List<D.Message> -> @+offset:Nat -> @+task:Nat -> @+disclosures:+List<E.Disclosure> ->
      ConversationSpec.visible_text_agreement(Conversation.visible(Conversation.groups(messages, offset), task, disclosures)),
    draft_identity: @+task:Nat -> @+text:U.Text -> @previous:U.Delivery -> @+selected:U.Delivery -> @world:M.World() ->
      {U.apply_edit(U.ChooseDelivery{selected}, U.Message{task, text, previous}, world) == Done{U.Message{task, text, selected}} : Result<&2, &2, String, U.Body>},
    stale_receipt: @+draft:U.Draft -> @accepted:Bool -> @submitted:Nat -> @reply:J.Json ->
      {E.settled_current(draft, False{}, accepted, submitted, reply) == draft : U.Draft},
    failed_draft: @revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @submitted:Nat -> @reply:J.Json ->
      {U.contents(E.settled_current(U.Draft{revision, body, feedback}, True{}, False{}, submitted, reply)) == body : U.Body},
    continued_capture: @+revision:Nat -> @title:String -> @description:String -> @+stage:B.Stage -> @+priority:B.Priority ->
      @+owner:B.Owner -> @+project:Maybe<&2, Nat> -> @+labels:+List<String> -> @attachments:+List<B.Attachment> -> @+assist:Bool -> @+profile:String ->
      {U.after_accept(U.Card{None{}, revision, B.Draft{title, description, stage, priority, owner, project, labels, attachments}, assist, profile, True{}}) ==
       U.Card{None{}, revision, B.Draft{"", "", stage, priority, owner, project, labels, Nil{}}, assist, profile, True{}} : U.Body},
    capture_focus: @+application:E.Application ->
      {E.capture_attention(False{}, application) == E.unchanged(application) : E.Decision},
    actionable: @+input:Core.Input ->
      {Interface.bind(Interface.Activate{input, View.Available{}}, Interface.Press{}) == Some{input} : Maybe<&2, Core.Input>},
    unavailable: @input:Core.Input -> @reason:String ->
      {Interface.bind(Interface.Activate{input, View.Unavailable{reason}}, Interface.Press{}) == None{} : Maybe<&2, Core.Input>}
  }
