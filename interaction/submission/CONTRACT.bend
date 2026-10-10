import Base
import ../IDENTITY.bend as Identity
import ./MODEL.bend as Receipt
import ../presentation/PROGRAM.bend as InterfaceView
import ../conversation/MODEL.bend as Conversation
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../TYPES.bend as InteractionTypes
import ../presentation/SURFACE.bend as SurfaceTypes
import ../../harness/MODEL.bend as M
import ../session/MODEL.bend as E
import ../session/PROGRAM.bend as ExperienceProgram
import ../INPUT.bend as U
import ../services/CONTEXT.bend as Context
import ../presentation/MODEL.bend as View
import ./FIELDS.bend as Forms
import ./field-options.bend as Options

def pending_entries(application: E.Application) -> +List<E.Pending>:
  E.pending(E.session(application))

def session_drafts(+session: E.Session) -> +List<U.Draft>:
  +drafts = E.drafts(session)
  drafts

def application_drafts(+application: E.Application) -> +List<U.Draft>:
  +session = E.session(application)
  session_drafts(session)

def decision_drafts(+decision: E.Decision) -> +List<U.Draft>:
  E.Decision{+application, reply, runtime, interaction, durable} = decision
  application_drafts(application)

type SubmissionRequirements is Type:
  SubmissionRequirements{
    stale_settlement: @+submitted:U.Draft -> @+result:J.Json -> @+session:E.Session ->
      @absent:{E.owns_submission(submitted, session) == False{} : Bool} ->
      {E.settle(submitted, result, session) == session : E.Session},
    stale_native: @+submitted:U.Draft -> @+program:M.World() -> @+result:J.Json ->
      @+effects:+List<M.Effect()> -> @+session:E.Session -> @durable:Bool ->
      @absent:{E.owns_submission(submitted, session) == False{} : Bool} ->
      {E.native_session(Some{submitted}, program, result, effects, session, durable) ==
        E.Decision{E.from_program(program, session), result, effects, Nil{}, durable} : E.Decision},
    failed_native: @+submitted:U.Draft -> @+program:M.World() -> @+result:J.Json ->
      @+effects:+List<M.Effect()> -> @+session:E.Session -> @durable:Bool ->
      @failed:{J.boolean(J.get(result, "ok")) == False{} : Bool} ->
      {E.native_session(Some{submitted}, program, result, effects, session, durable) ==
        E.Decision{E.from_program(program, E.settle(submitted, result, session)), result, effects, Nil{}, durable} : E.Decision},
    accepted_message: @+directory_entry:String -> @+revision:Nat -> @+task:Nat -> @+message:U.Text -> @+delivery:U.Delivery ->
      @+feedback:U.Feedback -> @+program:M.World() -> @+result:J.Json -> @+effects:+List<M.Effect()> ->
      @+session:E.Session -> @durable:Bool ->
      @lookup:{E.find_draft(session_drafts(session), U.MessageEditor{task}) ==
        Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}} : Maybe<&2, U.Draft>} ->
      @current:{E.owns_submission(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, session) == True{} : Bool} ->
      @accepted:{J.boolean(J.get(result, "ok")) == True{} : Bool} ->
      {decision_drafts(E.native_session(Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}},
          program, result, effects, session, durable)) ==
        E.put_draft(U.Draft{(revision + 1n : Nat), U.Message{task, U.Text{""}, delivery}, U.Accepted{revision, result}, directory_entry},
          session_drafts(session)) : +List<U.Draft>},
    unowned_directory: @+ticket:Nat -> @+result:Result<&2, &2, String, Context.DirectoryObservation> ->
      @+application:E.Application ->
      @absent:{E.find_pending(pending_entries(application), ticket) == None{} : Maybe<&2, E.Pending>} ->
      {ExperienceProgram.step(E.DirectoriesObserved{ticket, result}, application) ==
        E.Decision{application, D.failure("interaction_refused", "The directory observation has no pending request"), Nil{}, Nil{}, False{}} : E.Decision},
    preparation_snapshot: @+session:E.Session -> @+program:M.World() -> @+workspace:D.Workspace -> @+draft:U.Draft ->
      {E.prepare(E.from_program(program, session), Some{workspace}, draft) ==
        E.Decision{E.from_program(program, E.with_pending(E.Pending{E.next_ticket(session), draft, E.now(session)} <> E.pending(session), E.with_next_ticket((E.next_ticket(session) + 1n : Nat), session))),
          D.success(J.Null{}), Nil{}, [E.ObserveDirectories{E.next_ticket(session), workspace}], False{}} : E.Decision}
  }

law submission_evidence:
  SubmissionRequirements

type ReopenRequirements is Type:
  ReopenRequirements{
    revision: @directory_entry:String -> @previous:Nat -> @body:U.Body -> @submitted:Nat -> @reply:J.Json -> @fallback:U.Body -> @session:E.Session ->
      {E.ensure(Some{U.Draft{previous, body, U.Accepted{submitted, reply}, directory_entry}}, fallback, session) ==
        E.with_draft(session, U.Draft{(previous + 1n : Nat), fallback, U.Editing{}, ""}) : E.Session},
    older: @directory_entry:String -> @old_entry:String -> @+previous:Nat -> @body:U.Body -> @submitted:Nat -> @reply:J.Json -> @+fallback:U.Body ->
      @+old:Nat -> @+old_body:U.Body -> @feedback:U.Feedback -> @session:E.Session ->
      @same:{U.same_editor(U.owner(fallback), U.owner(old_body)) == True{} : Bool} ->
      @before:{Nat.cmp((previous + 1n : Nat), old) == GT{} : Cmp} ->
      {E.owns_submission(U.Draft{old, old_body, feedback, old_entry},
        E.ensure(Some{U.Draft{previous, body, U.Accepted{submitted, reply}, directory_entry}}, fallback, session)) == False{} : Bool}
  }

def expected_choices(entry: Forms.Entry, field: Forms.Field, value: Forms.Observed, groups: +List<View.InputGroup>) -> +List<Forms.ChoiceValue>:
  match entry:
    case Forms.Choice{}: Options.choices(field, value, groups)
    case Forms.MultipleChoices{}: Options.choices(field, value, groups)
    case _: Nil{}

type FeedbackRequirements is Type:
  FeedbackRequirements{
    field_payload: @+field:Forms.Field -> @label:String -> @+entry:Forms.Entry -> @+editor:U.Editor -> @+parent: Identity.Key -> @+state:InteractionTypes.State -> @+groups:+List<View.InputGroup> ->
      {InterfaceView.field_node(Forms.FieldScene{field, label, entry}, editor, parent, state, groups) ==
        SurfaceTypes.Node{Identity.Part{parent, Forms.key(field)}, Forms.key(field), label, SurfaceTypes.Field{},
          SurfaceTypes.Edit{editor, field, InterfaceView.actual_entry(field, entry, InterfaceView.field_value(state, editor, field), state), InterfaceView.field_value(state, editor, field),
            expected_choices(InterfaceView.actual_entry(field, entry, InterfaceView.field_value(state, editor, field), state), field, InterfaceView.field_value(state, editor, field), groups)},
          InterfaceView.field_children(field, editor, Identity.Part{parent, Forms.key(field)}, state)} : SurfaceTypes.Node},
    rejected_feedback: @+parent: Identity.Key -> @revision:Nat -> @+reason:String ->
      {InterfaceView.feedback_nodes(parent, U.Rejected{revision, reason}) ==
    [SurfaceTypes.Node{Identity.Part{parent, "feedback"}, "submission-feedback", "Submission failed", SurfaceTypes.Alert{}, SurfaceTypes.ReadOnly{reason}, Nil{}}] : +List<SurfaceTypes.Node>},
    editing_no_stale: @parent: Identity.Key ->
      {InterfaceView.feedback_nodes(parent, U.Editing{}) == Nil{} : +List<SurfaceTypes.Node>},
    accepted_no_stale: @parent: Identity.Key -> @revision:Nat -> @reply:J.Json ->
      {InterfaceView.feedback_nodes(parent, U.Accepted{revision, reply}) == Nil{} : +List<SurfaceTypes.Node>},
    editor_rejected_visible: @+identity:U.Editor -> @revision:Nat -> @groups:+List<View.InputGroup> -> @+structure:+List<Forms.Section> -> @+submit:View.ControlDeclaration -> @submitted:Nat -> @+reason:String -> @pending:Bool -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {InterfaceView.editor(Some{View.EditorScene{identity, revision, groups, structure, submit, U.Rejected{submitted, reason}, pending}}, parent, state) ==
        List.append(&2, SurfaceTypes.Node, InterfaceView.sections(structure, identity, parent, 0n, state, groups),
          [SurfaceTypes.Node{Identity.Part{parent, "feedback"}, "submission-feedback", "Submission failed", SurfaceTypes.Alert{}, SurfaceTypes.ReadOnly{reason}, Nil{}}, InterfaceView.dialog_actions(parent, [InterfaceView.declared(parent, submit, state)])]) : +List<SurfaceTypes.Node>},
    composer_rejected_visible: @+identity:U.Editor -> @revision:Nat -> @message:U.Text -> @+footer:+List<View.ComposerControl> -> @context:Maybe<&2, Context.Observation> -> @+submit:View.ControlDeclaration -> @submitted:Nat -> @+reason:String -> @pending:Bool -> @+parent: Identity.Key -> @+state:InteractionTypes.State ->
      {InterfaceView.composer(Some{View.ComposerScene{identity, revision, message, footer, context, submit, U.Rejected{submitted, reason}, pending}}, parent, state) ==
        [SurfaceTypes.Node{Identity.Entity{parent, "composer", U.editor_key(identity)}, "composer/" ++ U.editor_key(identity), "Message", SurfaceTypes.Composer{}, SurfaceTypes.Region{},
          InterfaceView.field_node(Forms.FieldScene{Forms.MessageText{}, "Message", Forms.Multiline{}}, identity, Identity.Entity{parent, "composer", U.editor_key(identity)}, state, Nil{}) <>
            [SurfaceTypes.Node{Identity.Part{Identity.Entity{parent, "composer", U.editor_key(identity)}, "feedback"}, "submission-feedback", "Submission failed", SurfaceTypes.Alert{}, SurfaceTypes.ReadOnly{reason}, Nil{}},
             InterfaceView.composer_actions(footer, submit, Identity.Entity{parent, "composer", U.editor_key(identity)}, state)]}] : +List<SurfaceTypes.Node>}}

law feedback_evidence:
  FeedbackRequirements

def notice_claim(+ticket: Nat, +origin: String, +code: String, +message: String, +content: InteractionTypes.Scene,
  +key: Identity.Key, +semantic: String, +label: String, +role: SurfaceTypes.Role,
  +conversation: Maybe<&2, Conversation.Identity>, +children: +List<SurfaceTypes.Node>,
  +rest: +List<SurfaceTypes.Node>, +overlays: +List<SurfaceTypes.Node>, +scope: Maybe<&2, String>) -> Type:
  {InterfaceView.with_receipt(SurfaceTypes.Surface{content, SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageContext{conversation}, children} <> rest, overlays, scope},
    Some{Receipt.Receipt{ticket, origin, code, message}}) ==
    SurfaceTypes.Surface{content, SurfaceTypes.Node{key, semantic, label, role, SurfaceTypes.PageContext{conversation},
      SurfaceTypes.Node{Identity.Entity{Identity.Place{"@browser"}, "receipt", Nat.show(ticket)}, "operation-receipt", "Operation failed", SurfaceTypes.Alert{}, SurfaceTypes.ReadOnly{code ++ ": " ++ message}, Nil{}} <> children} <> rest,
      overlays, scope} : SurfaceTypes.Surface}

type Requirements is Type:
  Requirements{
    failure: @+ticket:Nat -> @+origin:String -> @+code:String -> @+message:String ->
      {Receipt.from_reply(ticket, origin, D.failure(code, message)) == Some{Receipt.Receipt{ticket, origin, code, message}} : Maybe<&2, Receipt.Receipt>},
    unknown: @ticket:Nat -> @origin:String -> {Receipt.from_reply(ticket, origin, J.Null{}) == None{} : Maybe<&2, Receipt.Receipt>},
    success: @ticket:Nat -> @origin:String -> {Receipt.from_reply(ticket, origin, J.Object{[J.Field{"ok", J.Boolean{True{}}}]}) == None{} : Maybe<&2, Receipt.Receipt>},
    absent: @+surface:SurfaceTypes.Surface -> {InterfaceView.with_receipt(surface, None{}) == surface : SurfaceTypes.Surface},
    notice: @+ticket:Nat -> @+origin:String -> @+code:String -> @+message:String -> @+content:InteractionTypes.Scene ->
      @+key: Identity.Key -> @+semantic:String -> @+label:String -> @+role:SurfaceTypes.Role -> @+conversation:Maybe<&2, Conversation.Identity> ->
      @+children:+List<SurfaceTypes.Node> -> @+rest:+List<SurfaceTypes.Node> -> @+overlays:+List<SurfaceTypes.Node> -> @+scope:Maybe<&2, String> ->
      notice_claim(ticket, origin, code, message, content, key, semantic, label, role, conversation, children, rest, overlays, scope)}

law evidence:
  Requirements
