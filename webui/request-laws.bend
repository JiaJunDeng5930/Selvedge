import Base
import ./request.bend as Request
import ./browser.bend as Browser
import ./browser-laws.bend as Existing
import ./MODEL.bend as Web
import ../MODEL.bend as M
import ../UI.bend as Product
import ../FEATURES.bend as F
import ../BOARD.bend as B
import ../core/user-experience.bend as E
import ../core/user-input.bend as U
import ../bendlib/json.bend as J
import ../bendlib/domain.bend as D
import ../bendlib/board-codec.bend as BoardCodec
import ../bendlib/command-codec.bend as Codec
import ../bendlib/tasks.bend as Tasks

def unrelated_field(+name: String, +value: J.Json, +rest: +List<J.Field>,
  unrelated: {String.eq(name, "guidance") == False{} : Bool}) ->
  {Request.without_guidance(J.Field{name, value} <> rest) ==
    J.Field{name, value} <> Request.without_guidance(rest) : +List<J.Field>}:
  Equal.cong(Bool, +List<J.Field>,
    (owned => Request.kept_field(owned, J.Field{name, value}, Request.without_guidance(rest))),
    String.eq(name, "guidance"), False{}, unrelated)

def create_payload(profile: String, reasoning: String, message: String, fields: +List<J.Field>) ->
  {Browser.request_payload(M.Create{profile, reasoning, message, J.Object{fields}}) ==
    J.Object{[J.Field{"settings", J.Object{Request.without_guidance(fields)}},
      J.Field{"op", J.Text{"create"}}, J.Field{"profile", J.Text{profile}},
      J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", J.Text{message}}]} : J.Json}:
  {==}

def fork_payload(id: Nat, count: Nat, messages: +List<String>, fields: +List<J.Field>) ->
  {Browser.request_payload(M.Fork{id, count, messages, J.Object{fields}}) ==
    J.Object{[J.Field{"settings", J.Object{Request.without_guidance(fields)}}, J.Field{"op", J.Text{"fork"}},
      J.Field{"task_id", J.nat(id)}, J.Field{"child_count", J.nat(count)},
      J.Field{"messages", J.Array{Tasks.strings_json(messages)}}]} : J.Json}:
  {==}

def project_payload(name: String, workspace: J.Json, guidance: +List<J.Field>) ->
  {Browser.request_payload(M.CreateProject{name, workspace, J.Object{guidance}}) ==
    J.Object{[J.Field{"op", J.Text{"create_project"}}, J.Field{"name", J.Text{name}}, J.Field{"workspace", workspace}]} : J.Json}:
  {==}

def update_payload(id: Nat, +selected_name: Maybe<&2, String>, +selected_workspace: J.Json, guidance: +List<J.Field>) ->
  {Browser.request_payload(M.UpdateProject{id, selected_name, selected_workspace, J.Object{guidance}}) ==
    Codec.command_json(M.UpdateProject{id, selected_name, selected_workspace, J.Null{}}) : J.Json}:
  match selected_name:
    case None{}:
      match selected_workspace:
        case J.Null{}: {==}
        case J.Boolean{value}: {==}
        case J.Number{lexeme}: {==}
        case J.Text{text}: {==}
        case J.Array{items}: {==}
        case J.Object{fields}: {==}
    case Some{selected}:
      match selected_workspace:
        case J.Null{}: {==}
        case J.Boolean{value}: {==}
        case J.Number{lexeme}: {==}
        case J.Text{text}: {==}
        case J.Array{items}: {==}
        case J.Object{fields}: {==}

def agent_payload(id: Maybe<&2, Nat>, revision: Nat, name: String, profile: String,
  reasoning: String, instructions: String, fields: +List<J.Field>, concurrency: Nat) ->
  {Browser.request_payload(M.FeatureCommand{F.BoardCommand{B.SaveAgent{id, revision,
    B.AgentProfile{revision, name, profile, reasoning, instructions, J.Object{fields}, concurrency}}}}) ==
    BoardCodec.command("save_board_agent", J.Field{"agent", J.Text{BoardCodec.id_text(id)}} <>
      BoardCodec.agent_fields(B.AgentProfile{revision, name, profile, reasoning, instructions,
        J.Object{Request.without_guidance(fields)}, concurrency})) : J.Json}:
  {==}

def rejected_settlement(ticket: Nat, completion: E.Completion, command: J.Json, origin: String,
  status: Browser.RequestStatus, reason: String, web: Web.State, sequence: Nat, next: Nat, pending: +List<Browser.Pending>) ->
  {Browser.rejected_pending(Some{Browser.Pending{ticket, completion, command, origin, status}}, reason,
    Browser.State{web, sequence, next, pending}) ==
    Browser.product_input(Product.CommandCompleted{Browser.program(Browser.State{web, sequence, next, pending}),
      D.failure("command_not_submitted", reason), completion},
      Browser.State{web, sequence, next, Browser.remove(pending, ticket)}) : Browser.Decision}:
  {==}

def stale_rejection(+ticket: Nat, reason: String, +pending: +List<Browser.Pending>, web: Web.State, sequence: Nat, next: Nat,
  stale: {Browser.find(pending, ticket) == None{} : Maybe<&2, Browser.Pending>}) ->
  {Browser.command_rejected(ticket, reason, Browser.State{web, sequence, next, pending}) ==
    Browser.Decision{Browser.State{web, sequence, next, pending}, Nil{}} : Browser.Decision}:
  Equal.cong(Maybe<&2, Browser.Pending>, Browser.Decision,
    (found => Browser.rejected_pending(found, reason, Browser.State{web, sequence, next, pending})),
    Browser.find(pending, ticket), None{}, stale)

def uncertain_still_pending(ticket: Nat, reason: String, web: Web.State, sequence: Nat, next: Nat, pending: +List<Browser.Pending>) ->
  {Browser.failed_completion(ticket, reason, Browser.State{web, sequence, next, pending}) ==
    Browser.Decision{Browser.State{web, sequence, next, Browser.uncertain_pending(pending, ticket, reason)}, Nil{}} : Browser.Decision}:
  {==}

def matching_consumed(+pending: +List<Browser.Pending>, +ticket: Nat) ->
  {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool}:
  Existing.consumed_ticket(pending, ticket)

def unrelated_pending(+entry: Browser.Pending, +rest: +List<Browser.Pending>, +ticket: Nat,
  distinct: {Nat.is_eq(Browser.ticket_of(entry), ticket) == False{} : Bool}) ->
  {Browser.remove(entry <> rest, ticket) == entry <> Browser.remove(rest, ticket) : +List<Browser.Pending>}:
  Browser.Pending{current, completion, command, origin, status} = entry
  Equal.cong(Bool, +List<Browser.Pending>,
    (hit => Browser.choose_removed(hit, Browser.Pending{current, completion, command, origin, status}, Browser.remove(rest, ticket))),
    Nat.is_eq(current, ticket), False{}, distinct)

def draft_rejected(revision: Nat, body: U.Body, feedback: U.Feedback, directory_entry: String, submitted: Nat, reason: String) ->
  {E.settled_current(U.Draft{revision, body, feedback, directory_entry}, True{}, False{}, submitted,
    D.failure("command_not_submitted", reason)) ==
    U.Draft{revision, body, U.Rejected{submitted, reason}, directory_entry} : U.Draft}:
  {==}

def unrelated_command(id: Nat, message: String) ->
  {Browser.request_payload(M.Send{id, message}) == Codec.command_json(M.Send{id, message}) : J.Json}:
  {==}

def decision_world(decision: E.Decision) -> M.World():
  E.Decision{E.Application{program, session}, reply, runtime, interaction, durable} = decision
  program

def confirmation_failed_world(owned: Bool, reason: String, destination: U.Route, +program: M.World(), session: E.Session) ->
  {decision_world(E.complete_confirmation(owned, D.failure("command_not_submitted", reason), destination,
    E.Application{program, session})) == program : M.World()}:
  match owned:
    case False{}: {==}
    case True{}: {==}

def rejected_world(completion: E.Completion, reason: String, +program: M.World(), +session: E.Session) ->
  {decision_world(E.complete_command(program, D.failure("command_not_submitted", reason), completion,
    E.Application{program, session})) == program : M.World()}:
  match completion:
    case E.DirectCompletion{}: {==}
    case E.DraftCompletion{draft}: {==}
    case E.ConfirmationCompletion{command, trigger, destination}:
      E.Session{route, drafts, readers, +layers, attention, navigation, filter, now, next, pending, +previews, code} = session
      confirmation_failed_world(E.confirmation_owned(layers, command, trigger), reason, destination, program,
        E.retain_previews(E.Session{route, drafts, readers, layers, attention, navigation, filter, now, next, pending, previews, code}, program))

def omission_step(+same: Bool, +name: String, +value: J.Json, +rest: +List<J.Field>,
  matching: {String.eq(name, "guidance") == same : Bool},
  absent: {J.find(rest, "guidance") == J.Null{} : J.Json}) ->
  {J.find(Request.kept_field(same, J.Field{name, value}, rest), "guidance") == J.Null{} : J.Json}:
  match same:
    case True{}: absent
    case False{}:
      Equal.trans(J.Json,
        J.choose_field(String.eq(name, "guidance"), value, J.find(rest, "guidance")),
        J.choose_field(False{}, value, J.find(rest, "guidance")), J.Null{},
        Equal.cong(Bool, J.Json, (hit => J.choose_field(hit, value, J.find(rest, "guidance"))),
          String.eq(name, "guidance"), False{}, matching), absent)

def owned_field_absent(+fields: +List<J.Field>) ->
  {J.find(Request.without_guidance(fields), "guidance") == J.Null{} : J.Json}:
  match fields:
    case Nil{}: {==}
    case Con{J.Field{+name, +value}, +rest}:
      omission_step(String.eq(name, "guidance"), name, value, Request.without_guidance(rest), {==}, owned_field_absent(rest))

type Requirements is Type:
  Requirements{
    current_world: @completion:E.Completion -> @reason:String -> @+program:M.World() -> @+session:E.Session ->
      {decision_world(E.complete_command(program, D.failure("command_not_submitted", reason), completion, E.Application{program, session})) == program : M.World()},
    owned_field_absent: @+fields:+List<J.Field> -> {J.find(Request.without_guidance(fields), "guidance") == J.Null{} : J.Json},
    create: @profile:String -> @reasoning:String -> @message:String -> @fields:+List<J.Field> ->
      {Browser.request_payload(M.Create{profile, reasoning, message, J.Object{fields}}) ==
        J.Object{[J.Field{"settings", J.Object{Request.without_guidance(fields)}}, J.Field{"op", J.Text{"create"}},
          J.Field{"profile", J.Text{profile}}, J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", J.Text{message}}]} : J.Json},
    fork: @id:Nat -> @count:Nat -> @messages:+List<String> -> @fields:+List<J.Field> ->
      {Browser.request_payload(M.Fork{id, count, messages, J.Object{fields}}) ==
        J.Object{[J.Field{"settings", J.Object{Request.without_guidance(fields)}}, J.Field{"op", J.Text{"fork"}},
          J.Field{"task_id", J.nat(id)}, J.Field{"child_count", J.nat(count)}, J.Field{"messages", J.Array{Tasks.strings_json(messages)}}]} : J.Json},
    project: @name:String -> @workspace:J.Json -> @guidance:+List<J.Field> ->
      {Browser.request_payload(M.CreateProject{name, workspace, J.Object{guidance}}) ==
        J.Object{[J.Field{"op", J.Text{"create_project"}}, J.Field{"name", J.Text{name}}, J.Field{"workspace", workspace}]} : J.Json},
    update: @id:Nat -> @+name:Maybe<&2, String> -> @+workspace:J.Json -> @guidance:+List<J.Field> ->
      {Browser.request_payload(M.UpdateProject{id, name, workspace, J.Object{guidance}}) ==
        Codec.command_json(M.UpdateProject{id, name, workspace, J.Null{}}) : J.Json},
    agent: @id:Maybe<&2, Nat> -> @revision:Nat -> @name:String -> @profile:String -> @reasoning:String ->
      @instructions:String -> @fields:+List<J.Field> -> @concurrency:Nat ->
      {Browser.request_payload(M.FeatureCommand{F.BoardCommand{B.SaveAgent{id, revision,
        B.AgentProfile{revision, name, profile, reasoning, instructions, J.Object{fields}, concurrency}}}}) ==
        BoardCodec.command("save_board_agent", J.Field{"agent", J.Text{BoardCodec.id_text(id)}} <>
          BoardCodec.agent_fields(B.AgentProfile{revision, name, profile, reasoning, instructions,
            J.Object{Request.without_guidance(fields)}, concurrency})) : J.Json},
    preserve_field: @+name:String -> @+value:J.Json -> @+rest:+List<J.Field> ->
      @unrelated:{String.eq(name, "guidance") == False{} : Bool} ->
      {Request.without_guidance(J.Field{name, value} <> rest) == J.Field{name, value} <> Request.without_guidance(rest) : +List<J.Field>},
    settlement: @ticket:Nat -> @completion:E.Completion -> @command:J.Json -> @origin:String -> @status:Browser.RequestStatus ->
      @reason:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @pending:+List<Browser.Pending> ->
      {Browser.rejected_pending(Some{Browser.Pending{ticket, completion, command, origin, status}}, reason,
        Browser.State{web, sequence, next, pending}) ==
        Browser.product_input(Product.CommandCompleted{Browser.program(Browser.State{web, sequence, next, pending}),
          D.failure("command_not_submitted", reason), completion},
          Browser.State{web, sequence, next, Browser.remove(pending, ticket)}) : Browser.Decision},
    stale: @+ticket:Nat -> @reason:String -> @+pending:+List<Browser.Pending> -> @web:Web.State -> @sequence:Nat -> @next:Nat ->
      @absent:{Browser.find(pending, ticket) == None{} : Maybe<&2, Browser.Pending>} ->
      {Browser.command_rejected(ticket, reason, Browser.State{web, sequence, next, pending}) ==
        Browser.Decision{Browser.State{web, sequence, next, pending}, Nil{}} : Browser.Decision},
    consumed: @+pending:+List<Browser.Pending> -> @+ticket:Nat -> {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool},
    other_pending: @+entry:Browser.Pending -> @+rest:+List<Browser.Pending> -> @+ticket:Nat ->
      @distinct:{Nat.is_eq(Browser.ticket_of(entry), ticket) == False{} : Bool} ->
      {Browser.remove(entry <> rest, ticket) == entry <> Browser.remove(rest, ticket) : +List<Browser.Pending>},
    rejected_draft: @revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @directory_entry:String -> @submitted:Nat -> @reason:String ->
      {E.settled_current(U.Draft{revision, body, feedback, directory_entry}, True{}, False{}, submitted, D.failure("command_not_submitted", reason)) ==
        U.Draft{revision, body, U.Rejected{submitted, reason}, directory_entry} : U.Draft},
    uncertain: @ticket:Nat -> @reason:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @pending:+List<Browser.Pending> ->
      {Browser.failed_completion(ticket, reason, Browser.State{web, sequence, next, pending}) ==
        Browser.Decision{Browser.State{web, sequence, next, Browser.uncertain_pending(pending, ticket, reason)}, Nil{}} : Browser.Decision},
    other_command: @id:Nat -> @message:String -> {Browser.request_payload(M.Send{id, message}) == Codec.command_json(M.Send{id, message}) : J.Json}}

def evidence() -> Requirements:
  Requirements{rejected_world, owned_field_absent, create_payload, fork_payload, project_payload, update_payload, agent_payload, unrelated_field,
    rejected_settlement, stale_rejection, matching_consumed, unrelated_pending, draft_rejected, uncertain_still_pending, unrelated_command}
