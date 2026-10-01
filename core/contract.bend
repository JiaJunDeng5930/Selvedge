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
import ./surface-laws.bend as SurfaceLaws
import ./session-laws.bend as SessionLaws
import ./submission-laws.bend as SubmissionLaws
import ./boundary-laws.bend as BoundaryLaws
import ./composition-laws.bend as CompositionLaws
import ./conversation-presentation-laws.bend as ConversationPresentationLaws

# Evidence about the public product entry, not a parallel presentation engine.
# Platform realization requirements belong to webui and do not enter this type.
type Requirements is Type:
  Requirements{
    interaction: SurfaceLaws.Requirements,
    sessions: SessionLaws.Requirements,
    submissions: SubmissionLaws.Requirements,
    boundaries: BoundaryLaws.Requirements,
    composition: CompositionLaws.Requirements,
    conversation_presentation: ConversationPresentationLaws.Requirements,
    reopened_submissions: SubmissionLaws.ReopenRequirements,
    runtime: @+input:M.Input -> @+program:M.World() -> @+session:E.Session -> @+services:Services.State ->
      {CoreLaws.runtime(UI.step(UI.Engine{input}, Core.State{E.Application{program, session}, services})) == Program.transition(input, program) : M.Decision()},
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
    failed_draft: @revision:Nat -> @+body:U.Body -> @feedback:U.Feedback -> @submitted:Nat -> @reply:J.Json ->
      {U.contents(E.settled_current(U.Draft{revision, body, feedback}, True{}, False{}, submitted, reply)) == body : U.Body},
    continued_capture: @+revision:Nat -> @title:String -> @description:String -> @+stage:B.Stage -> @+priority:B.Priority ->
      @+owner:B.Owner -> @+project:Maybe<&2, Nat> -> @+labels:+List<String> -> @attachments:+List<B.Attachment> -> @+assist:Bool -> @+profile:String ->
      {U.after_accept(U.Card{None{}, revision, B.Draft{title, description, stage, priority, owner, project, labels, attachments}, assist, profile, True{}}) ==
       U.Card{None{}, revision, B.Draft{"", "", stage, priority, owner, project, labels, Nil{}}, assist, profile, True{}} : U.Body}
  }
