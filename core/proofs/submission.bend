import Base
import ../../MODEL.bend as M
import ../../BOARD.bend as B
import ../../bendlib/domain.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite
import ../user-experience.bend as E
import ../user-experience-program.bend as ExperienceProgram
import ../user-input.bend as U
import ../user-context.bend as Context
import ../code-block.bend as Content
import ../live-output.bend as Live
import ../submission-laws.bend as Rule

def with_native_preserves_drafts(+decision: E.Decision, +result: J.Json, +effects: +List<M.Effect()>, durable: Bool) ->
  {Rule.decision_drafts(E.with_native(decision, result, effects, durable)) == Rule.decision_drafts(decision) : +List<U.Draft>}:
  E.Decision{application, ignored_reply, ignored_runtime, interaction, ignored_durable} = decision
  {==}

def close_layers_preserves_drafts(+layers: +List<E.Layer>, program: M.World(), route: U.Route,
  +drafts: +List<U.Draft>, readers: +List<Finite.Entry(E.Reader)>, +session_layers: +List<E.Layer>,
  attention: String, navigation: E.NavigationState, filter: B.Filter, now: U32, next: Nat,
  +pending: +List<E.Pending>, +previews: +List<Live.Output>, +code_blocks: +List<Content.Block>, next_layer: Nat) ->
  {Rule.decision_drafts(E.close_layers(layers, program,
    E.Session{route, drafts, readers, session_layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer})) == drafts : +List<U.Draft>}:
  match layers:
    case Nil{}: {==}
    case Con{E.Layer{panel, trigger, initial, query, layer_occurrence}, rest}: {==}

def close_panel_preserves_drafts(+application: E.Application) ->
  {Rule.decision_drafts(E.close_panel(application)) == Rule.application_drafts(application) : +List<U.Draft>}:
  E.Application{program, E.Session{route, +drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  close_layers_preserves_drafts(layers, program, route, drafts, readers, layers, attention, navigation, filter,
    now, next, pending, previews, code_blocks, next_layer)

def finish_layer_preserves_drafts(same: Bool, +application: E.Application) ->
  {Rule.decision_drafts(E.finish_layer(same, application)) == Rule.application_drafts(application) : +List<U.Draft>}:
  match same:
    case False{}: {==}
    case True{}: close_panel_preserves_drafts(application)

def message_finish_location_preserves_drafts(+task: Nat, +route: U.Route, +layers: +List<E.Layer>,
  +result: J.Json, +application: E.Application) ->
  {Rule.decision_drafts(E.finish_at_location(U.MessageEditor{task}, route, layers, result, application)) ==
    Rule.application_drafts(application) : +List<U.Draft>}:
  match route layers:
    case U.Start{} Nil{}: {==}
    case U.Start{} Con{E.Layer{U.EditObject{current}, trigger, initial, query, layer_occurrence}, rest}:
      finish_layer_preserves_drafts(U.same_editor(U.MessageEditor{task}, current), application)
    case U.Start{} Con{E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.ObjectActions{subject}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.ArchivedCards{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.BoardSettings{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.BoardFilters{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.CardDetails{card}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.TaskDetails{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.WorkspaceConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.PermissionsConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.TaskContext{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.ModelPicker{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.DeliveryPicker{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Start{} Con{E.Layer{U.Confirm{command, title, destination}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Nil{}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.EditObject{current}, trigger, initial, query, layer_occurrence}, rest}:
      finish_layer_preserves_drafts(U.same_editor(U.MessageEditor{task}, current), application)
    case U.Conversation{route_task} Con{E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.ObjectActions{subject}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.ArchivedCards{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.BoardSettings{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.BoardFilters{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.CardDetails{card}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.TaskDetails{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.WorkspaceConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.PermissionsConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.TaskContext{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.ModelPicker{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.DeliveryPicker{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.Conversation{route_task} Con{E.Layer{U.Confirm{command, title, destination}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Nil{}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.EditObject{current}, trigger, initial, query, layer_occurrence}, rest}:
      finish_layer_preserves_drafts(U.same_editor(U.MessageEditor{task}, current), application)
    case U.ProjectHome{project} Con{E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.ObjectActions{subject}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.ArchivedCards{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.BoardSettings{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.BoardFilters{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.CardDetails{card}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.TaskDetails{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.WorkspaceConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.PermissionsConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.TaskContext{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.ModelPicker{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.DeliveryPicker{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectHome{project} Con{E.Layer{U.Confirm{command, title, destination}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Nil{}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.EditObject{current}, trigger, initial, query, layer_occurrence}, rest}:
      finish_layer_preserves_drafts(U.same_editor(U.MessageEditor{task}, current), application)
    case U.ProjectCollection{} Con{E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.ObjectActions{subject}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.ArchivedCards{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.BoardSettings{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.BoardFilters{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.CardDetails{card}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.TaskDetails{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.WorkspaceConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.PermissionsConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.TaskContext{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.ModelPicker{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.DeliveryPicker{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.ProjectCollection{} Con{E.Layer{U.Confirm{command, title, destination}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Nil{}: {==}
    case U.TaskBoard{} Con{E.Layer{U.EditObject{current}, trigger, initial, query, layer_occurrence}, rest}:
      finish_layer_preserves_drafts(U.same_editor(U.MessageEditor{task}, current), application)
    case U.TaskBoard{} Con{E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.ObjectActions{subject}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.ArchivedCards{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.BoardSettings{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.BoardFilters{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.CardDetails{card}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.TaskDetails{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.WorkspaceConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.PermissionsConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.TaskContext{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.ModelPicker{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.DeliveryPicker{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.TaskBoard{} Con{E.Layer{U.Confirm{command, title, destination}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Nil{}: {==}
    case U.AgentCollection{} Con{E.Layer{U.EditObject{current}, trigger, initial, query, layer_occurrence}, rest}:
      finish_layer_preserves_drafts(U.same_editor(U.MessageEditor{task}, current), application)
    case U.AgentCollection{} Con{E.Layer{U.ProjectPicker{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.ObjectActions{subject}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.ArchivedCards{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.BoardSettings{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.BoardFilters{}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.CardDetails{card}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.TaskDetails{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.WorkspaceConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.PermissionsConfiguration{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.TaskContext{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.ModelPicker{editor}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.DeliveryPicker{task}, trigger, initial, query, layer_occurrence}, rest}: {==}
    case U.AgentCollection{} Con{E.Layer{U.Confirm{command, title, destination}, trigger, initial, query, layer_occurrence}, rest}: {==}

def message_finish_submission_preserves_drafts(+directory_entry: String, +task: Nat, +revision: Nat, +message: U.Text,
  +delivery: U.Delivery, feedback: U.Feedback, +result: J.Json, +application: E.Application) ->
  {Rule.decision_drafts(E.finish_submission(True{}, U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry},
      result, application)) == Rule.application_drafts(application) : +List<U.Draft>}:
  E.Application{program, E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer}} = application
  message_finish_location_preserves_drafts(task, route, layers, result, application)

def stale_found(found: Maybe<&2, U.Draft>, revision: Nat, result: J.Json, session: E.Session,
  absent: {E.same_revision(found, revision) == False{} : Bool}) ->
  {E.settle_found(found, revision, result, session) == session : E.Session}:
  match found:
    case None{}: {==}
    case Some{U.Draft{+current, body, feedback, directory_entry}}:
      Equal.cong(Bool, E.Session,
        (owned => E.settle_owned(owned, U.Draft{current, body, feedback, directory_entry}, revision, result, session)),
        Nat.is_eq(current, revision), False{}, absent)

def stale_settlement(+submitted: U.Draft, +result: J.Json, +session: E.Session,
  absent: {E.owns_submission(submitted, session) == False{} : Bool}) ->
  {E.settle(submitted, result, session) == session : E.Session}:
  U.Draft{revision, body, feedback, directory_entry} = submitted
  E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  stale_found(E.find_draft(drafts, U.owner(body)), revision, result, session, absent)

def conjunction_right_false(left: Bool, right: Bool, absent: {right == False{} : Bool}) ->
  {left && right == False{} : Bool}:
  match left:
    case True{}: absent
    case False{}: {==}

def conjunction_left_false(left: Bool, right: Bool, absent: {left == False{} : Bool}) ->
  {left && right == False{} : Bool}:
  Equal.cong(Bool, Bool, (value => value && right), left, False{}, absent)

def native_session_owned(+owned: Bool, submitted: Maybe<&2, U.Draft>, program: M.World(), +result: J.Json,
  +effects: +List<M.Effect()>, +session: E.Session, durable: Bool) -> E.Decision:
  match submitted:
    case None{}: E.with_native(E.unchanged(E.Application{program, session}), result, effects, durable)
    case Some{+draft}:
      E.with_native(E.finish_submission(J.boolean(J.get(result, "ok")) && owned, draft, result,
        E.Application{program, E.settle(draft, result, session)}), result, effects, durable)

def stale_native(+submitted: U.Draft, +program: M.World(), +result: J.Json,
  +effects: +List<M.Effect()>, +session: E.Session, durable: Bool,
  +absent: {E.owns_submission(submitted, session) == False{} : Bool}) ->
  {E.native_session(Some{submitted}, program, result, effects, session, durable) ==
    E.Decision{E.Application{program, session}, result, effects, Nil{}, durable} : E.Decision}:
  after_ownership = Equal.cong(Bool, E.Decision,
    (owned => native_session_owned(owned, Some{submitted}, program, result, effects, session, durable)),
    E.owns_submission(submitted, session), False{}, absent)
  guard_false = conjunction_right_false(J.boolean(J.get(result, "ok")), False{}, {==})
  after_guard = Equal.cong(Bool, E.Decision,
    (accepted => E.with_native(E.finish_submission(accepted, submitted, result,
      E.Application{program, E.settle(submitted, result, session)}), result, effects, durable)),
    J.boolean(J.get(result, "ok")) && False{}, False{}, guard_false)
  after_settlement = Equal.cong(E.Session, E.Decision,
    (settled => E.with_native(E.finish_submission(False{}, submitted, result,
      E.Application{program, settled}), result, effects, durable)),
    E.settle(submitted, result, session), session,
    stale_settlement(submitted, result, session, absent))
  Equal.trans(E.Decision,
    E.native_session(Some{submitted}, program, result, effects, session, durable),
    native_session_owned(E.owns_submission(submitted, session), Some{submitted}, program, result, effects, session, durable),
    E.Decision{E.Application{program, session}, result, effects, Nil{}, durable},
    {==},
    Equal.trans(E.Decision,
      native_session_owned(E.owns_submission(submitted, session), Some{submitted}, program, result, effects, session, durable),
      native_session_owned(False{}, Some{submitted}, program, result, effects, session, durable),
      E.Decision{E.Application{program, session}, result, effects, Nil{}, durable},
      after_ownership,
      Equal.trans(E.Decision,
        native_session_owned(False{}, Some{submitted}, program, result, effects, session, durable),
        E.with_native(E.finish_submission(False{}, submitted, result,
          E.Application{program, E.settle(submitted, result, session)}), result, effects, durable),
        E.Decision{E.Application{program, session}, result, effects, Nil{}, durable},
        after_guard, after_settlement)))

def failed_native(+submitted: U.Draft, +program: M.World(), +result: J.Json,
  +effects: +List<M.Effect()>, +session: E.Session, durable: Bool,
  failed: {J.boolean(J.get(result, "ok")) == False{} : Bool}) ->
  {E.native_session(Some{submitted}, program, result, effects, session, durable) ==
    E.Decision{E.Application{program, E.settle(submitted, result, session)}, result, effects, Nil{}, durable} : E.Decision}:
  accepted_false = conjunction_left_false(J.boolean(J.get(result, "ok")), E.owns_submission(submitted, session), failed)
  Equal.cong(Bool, E.Decision,
    (accepted => E.with_native(E.finish_submission(accepted, submitted, result,
      E.Application{program, E.settle(submitted, result, session)}), result, effects, durable)),
    J.boolean(J.get(result, "ok")) && E.owns_submission(submitted, session), False{}, accepted_false)

def accepted_message_settlement_snapshot(+directory_entry: String, +revision: Nat, +task: Nat, +message: U.Text, +delivery: U.Delivery,
  +feedback: U.Feedback, +result: J.Json, +session: E.Session,
  +lookup: {E.find_draft(Rule.session_drafts(session), U.MessageEditor{task}) ==
    Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}} : Maybe<&2, U.Draft>},
  current: {E.owns_submission(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, session) == True{} : Bool},
  accepted: {J.boolean(J.get(result, "ok")) == True{} : Bool}) ->
  {Rule.session_drafts(E.settle(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, result, session)) ==
    E.put_draft(U.Draft{(revision + 1n : Nat), U.Message{task, U.Text{""}, delivery}, U.Accepted{revision, result}, directory_entry},
      Rule.session_drafts(session)) : +List<U.Draft>}:
  E.Session{route, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  found_owned = Equal.cong(Maybe<&2, U.Draft>, Bool,
    (found => E.same_revision(found, revision)),
    E.find_draft(drafts, U.MessageEditor{task}),
    Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}}, lookup)
  same_owned = Equal.sym(Bool,
    E.owns_submission(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, session),
    E.same_revision(Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}}, revision), found_owned)
  same_revision = Equal.trans(Bool,
    E.same_revision(Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}}, revision),
    E.owns_submission(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, session),
    True{}, same_owned, current)
  revision_true = Equal.trans(Bool,
    Nat.is_eq(revision, revision),
    E.same_revision(Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}}, revision),
    True{}, {==}, same_revision)
  located = E.settle_found(E.find_draft(drafts, U.MessageEditor{task}), revision, result, session)
  found = E.settle_found(Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}}, revision, result, session)
  compared = E.settle_owned(Nat.is_eq(revision, revision), U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, revision, result, session)
  owned = E.settle_owned(True{}, U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, revision, result, session)
  successful = E.with_draft(session,
    E.settled_current(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, True{}, True{}, revision, result))
  target = E.with_draft(session,
    U.Draft{(revision + 1n : Nat), U.Message{task, U.Text{""}, delivery}, U.Accepted{revision, result}, directory_entry})
  settled = Equal.trans(E.Session,
    E.settle(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, result, session),
    located, target,
    {==},
    Equal.trans(E.Session, located, found, target,
      Equal.cong(Maybe<&2, U.Draft>, E.Session,
        (value => E.settle_found(value, revision, result, session)),
        E.find_draft(drafts, U.MessageEditor{task}),
        Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}}, lookup),
      Equal.trans(E.Session, found, compared, target, {==},
        Equal.trans(E.Session, compared, owned, target,
          Equal.cong(Bool, E.Session,
            (same => E.settle_owned(same, U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, revision, result, session)),
            Nat.is_eq(revision, revision), True{}, revision_true),
          Equal.trans(E.Session, owned,
            E.with_draft(session, E.settled_current(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry},
              True{}, J.boolean(J.get(result, "ok")), revision, result)),
            target, {==},
            Equal.trans(E.Session,
              E.with_draft(session, E.settled_current(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry},
                True{}, J.boolean(J.get(result, "ok")), revision, result)),
              successful, target,
              Equal.cong(Bool, E.Session,
                (ok => E.with_draft(session,
                  E.settled_current(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, True{}, ok, revision, result))),
                J.boolean(J.get(result, "ok")), True{}, accepted),
              {==}))))))
  Equal.cong(E.Session, +List<U.Draft>, (updated => Rule.session_drafts(updated)),
    E.settle(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, result, session),
    target, settled)

def accepted_message(+directory_entry: String, +revision: Nat, +task: Nat, +message: U.Text, +delivery: U.Delivery,
  +feedback: U.Feedback, +program: M.World(), +result: J.Json, +effects: +List<M.Effect()>,
  +session: E.Session, durable: Bool,
  +lookup: {E.find_draft(Rule.session_drafts(session), U.MessageEditor{task}) ==
    Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}} : Maybe<&2, U.Draft>},
  +current: {E.owns_submission(U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}, session) == True{} : Bool},
  +accepted: {J.boolean(J.get(result, "ok")) == True{} : Bool}) ->
  {Rule.decision_drafts(E.native_session(Some{U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}},
      program, result, effects, session, durable)) ==
    E.put_draft(U.Draft{(revision + 1n : Nat), U.Message{task, U.Text{""}, delivery}, U.Accepted{revision, result}, directory_entry},
      Rule.session_drafts(session)) : +List<U.Draft>}:
  +submitted: U.Draft = U.Draft{revision, U.Message{task, message, delivery}, feedback, directory_entry}
  +settled: E.Session = E.settle(submitted, result, session)
  target: +List<U.Draft> = E.put_draft(U.Draft{(revision + 1n : Nat), U.Message{task, U.Text{""}, delivery}, U.Accepted{revision, result}, directory_entry},
    Rule.session_drafts(session))
  guard_true = Equal.trans(Bool,
    J.boolean(J.get(result, "ok")) && True{}, True{}, True{},
    Equal.cong(Bool, Bool, (ok => ok && True{}), J.boolean(J.get(result, "ok")), True{}, accepted), {==})
  owner_true = Equal.cong(Bool, +List<U.Draft>,
    (owned => Rule.decision_drafts(native_session_owned(owned, Some{submitted}, program, result, effects, session, durable))),
    E.owns_submission(submitted, session), True{}, current)
  reply_true = Equal.cong(Bool, +List<U.Draft>,
    (guard => Rule.decision_drafts(E.with_native(E.finish_submission(guard, submitted, result,
      E.Application{program, settled}), result, effects, durable))),
    J.boolean(J.get(result, "ok")) && True{}, True{}, guard_true)
  after_message = message_finish_submission_preserves_drafts(directory_entry, task, revision, message, delivery, feedback,
    result, E.Application{program, settled})
  after_settlement = accepted_message_settlement_snapshot(directory_entry, revision, task, message, delivery, feedback,
    result, session, lookup, current, accepted)
  Equal.trans(+List<U.Draft>,
    Rule.decision_drafts(E.native_session(Some{submitted}, program, result, effects, session, durable)),
    Rule.decision_drafts(native_session_owned(E.owns_submission(submitted, session), Some{submitted}, program, result, effects, session, durable)),
    target,
    {==},
    Equal.trans(+List<U.Draft>,
      Rule.decision_drafts(native_session_owned(E.owns_submission(submitted, session), Some{submitted}, program, result, effects, session, durable)),
      Rule.decision_drafts(native_session_owned(True{}, Some{submitted}, program, result, effects, session, durable)),
      target, owner_true,
      Equal.trans(+List<U.Draft>,
        Rule.decision_drafts(native_session_owned(True{}, Some{submitted}, program, result, effects, session, durable)),
        Rule.decision_drafts(E.with_native(E.finish_submission(J.boolean(J.get(result, "ok")) && True{}, submitted, result,
          E.Application{program, settled}), result, effects, durable)),
        target,
        {==},
        Equal.trans(+List<U.Draft>,
          Rule.decision_drafts(E.with_native(E.finish_submission(J.boolean(J.get(result, "ok")) && True{}, submitted, result,
            E.Application{program, settled}), result, effects, durable)),
          Rule.decision_drafts(E.with_native(E.finish_submission(True{}, submitted, result,
            E.Application{program, settled}), result, effects, durable)),
          target, reply_true,
          Equal.trans(+List<U.Draft>,
            Rule.decision_drafts(E.with_native(E.finish_submission(True{}, submitted, result,
              E.Application{program, settled}), result, effects, durable)),
            Rule.application_drafts(E.Application{program, settled}),
            target,
            Equal.trans(+List<U.Draft>,
              Rule.decision_drafts(E.with_native(E.finish_submission(True{}, submitted, result,
                E.Application{program, settled}), result, effects, durable)),
              Rule.decision_drafts(E.finish_submission(True{}, submitted, result, E.Application{program, settled})),
              Rule.application_drafts(E.Application{program, settled}),
              with_native_preserves_drafts(E.finish_submission(True{}, submitted, result,
                E.Application{program, settled}), result, effects, durable),
              after_message),
            Equal.trans(+List<U.Draft>,
              Rule.application_drafts(E.Application{program, settled}),
              Rule.session_drafts(settled),
              target, {==}, after_settlement))))))

def unowned_directory(+ticket: Nat, +result: Result<&2, &2, String, Context.DirectoryObservation>,
  +application: E.Application,
  absent: {E.find_pending(Rule.pending_entries(application), ticket) == None{} : Maybe<&2, E.Pending>}) ->
  {ExperienceProgram.step(E.DirectoriesObserved{ticket, result}, application) ==
    E.Decision{application, D.failure("interaction_refused", "The directory observation has no pending request"), Nil{}, Nil{}, False{}} : E.Decision}:
  E.Application{program, E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, +pending, previews, code_blocks, next_layer}} = application
  Equal.cong(Maybe<&2, E.Pending>, E.Decision,
    (found => E.observed_pending(found, result, application)),
    E.find_pending(Rule.pending_entries(application), ticket), None{}, absent)

def Rule.evidence():
  Rule.Requirements{
    submitted => result => session => absent => stale_settlement(submitted, result, session, absent),
    submitted => program => result => effects => session => durable => absent => stale_native(submitted, program, result, effects, session, durable, absent),
    submitted => program => result => effects => session => durable => failed => failed_native(submitted, program, result, effects, session, durable, failed),
    directory_entry => revision => task => message => delivery => feedback => program => result => effects => session => durable => lookup => current => accepted =>
      accepted_message(directory_entry, revision, task, message, delivery, feedback, program, result, effects, session, durable, lookup, current, accepted),
    ticket => result => application => absent => unowned_directory(ticket, result, application, absent),
    +program => route => +drafts => +readers => +layers => attention => navigation => filter => now => next => +pending => +previews => +code_blocks => next_layer => +workspace => +draft => {==}
  }

# Reopening is a new edit of the same work, never a reuse of an old revision.

def reopened_older_ownership(directory_entry: String, old_entry: String, +previous: Nat, body: U.Body, submitted: Nat, reply: J.Json, +fallback: U.Body,
  +older: Nat, +old_body: U.Body, feedback: U.Feedback, session: E.Session,
  same: {U.same_editor(U.owner(fallback), U.owner(old_body)) == True{} : Bool},
  before: {Nat.cmp((previous + 1n : Nat), older) == GT{} : Cmp}) ->
  {E.owns_submission(U.Draft{older, old_body, feedback, old_entry},
    E.ensure(Some{U.Draft{previous, body, U.Accepted{submitted, reply}, directory_entry}}, fallback, session)) == False{} : Bool}:
  E.Session{route, +drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code_blocks, next_layer} = session
  Equal.trans(Bool,
    E.same_revision(E.select_draft(U.same_editor(U.owner(fallback), U.owner(old_body)),
      U.Draft{(previous + 1n : Nat), fallback, U.Editing{}, ""},
      E.find_draft(E.without_draft(drafts, U.owner(fallback)), U.owner(old_body))), older),
    Nat.is_eq((previous + 1n : Nat), older), False{},
    Equal.cong(Bool, Bool,
      (hit => E.same_revision(E.select_draft(hit, U.Draft{(previous + 1n : Nat), fallback, U.Editing{}, ""},
        E.find_draft(E.without_draft(drafts, U.owner(fallback)), U.owner(old_body))), older)),
      U.same_editor(U.owner(fallback), U.owner(old_body)), True{}, same),
    Equal.cong(Cmp, Bool, Cmp.is_eq, Nat.cmp((previous + 1n : Nat), older), GT{}, before))

def reopen_evidence() -> Rule.ReopenRequirements:
  Rule.ReopenRequirements{directory_entry => previous => body => submitted => reply => fallback => session => {==}, reopened_older_ownership}
