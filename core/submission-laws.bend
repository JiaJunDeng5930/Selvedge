import Base
import ../MODEL.bend as M
import ../BOARD.bend as B
import ../bendlib/domain.bend as D
import ../bendlib/json.bend as J
import ../bendlib/association-map.bend as Finite
import ./user-experience.bend as E
import ./user-experience-program.bend as ExperienceProgram
import ./user-input.bend as U
import ./user-context.bend as Context
import ./code-block.bend as Content
import ./live-output.bend as Live

def pending_entries(application: E.Application) -> +List<E.Pending>:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, +pending, previews, code_blocks, next_layer}} = application
  pending

def session_drafts(+session: E.Session) -> +List<U.Draft>:
  E.Session{route, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  drafts

def application_drafts(+application: E.Application) -> +List<U.Draft>:
  E.Application{program, +session} = application
  session_drafts(session)

def decision_drafts(+decision: E.Decision) -> +List<U.Draft>:
  E.Decision{+application, reply, runtime, interaction, durable} = decision
  application_drafts(application)

type Requirements is Type:
  Requirements{
    stale_settlement: @+submitted:U.Draft -> @+result:J.Json -> @+session:E.Session ->
      @absent:{E.owns_submission(submitted, session) == False{} : Bool} ->
      {E.settle(submitted, result, session) == session : E.Session},
    stale_native: @+submitted:U.Draft -> @+program:M.World() -> @+result:J.Json ->
      @+effects:+List<M.Effect()> -> @+session:E.Session -> @durable:Bool ->
      @absent:{E.owns_submission(submitted, session) == False{} : Bool} ->
      {E.native_session(Some{submitted}, program, result, effects, session, durable) ==
        E.Decision{E.Application{program, session}, result, effects, Nil{}, durable} : E.Decision},
    failed_native: @+submitted:U.Draft -> @+program:M.World() -> @+result:J.Json ->
      @+effects:+List<M.Effect()> -> @+session:E.Session -> @durable:Bool ->
      @failed:{J.boolean(J.get(result, "ok")) == False{} : Bool} ->
      {E.native_session(Some{submitted}, program, result, effects, session, durable) ==
        E.Decision{E.Application{program, E.settle(submitted, result, session)}, result, effects, Nil{}, durable} : E.Decision},
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
    preparation_snapshot: @+program:M.World() -> @route:U.Route -> @+drafts:+List<U.Draft> ->
      @+readers:+List<Finite.Entry(E.Reader)> -> @+layers:+List<E.Layer> -> @attention:String ->
      @navigation:E.NavigationState -> @filter:B.Filter -> @now:U32 -> @next:Nat ->
      @+pending:+List<E.Pending> -> @+previews:+List<Live.Output> -> @+code_blocks:+List<Content.Block> -> @next_layer:Nat ->
      @+workspace:D.Workspace -> @+draft:U.Draft ->
      {E.prepare(E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter,
          now, next, pending, previews, code_blocks, next_layer}}, Some{workspace}, draft) ==
        E.Decision{E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter,
          now, (next + 1n : Nat), E.Pending{next, draft, now} <> pending, previews, code_blocks, next_layer}},
          D.success(J.Null{}), Nil{}, [E.ObserveDirectories{next, workspace}], False{}} : E.Decision}
  }

law evidence:
  Requirements

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
