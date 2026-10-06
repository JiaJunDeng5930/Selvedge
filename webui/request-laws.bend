import ../core/operation-receipt.bend as Receipt
import Base
import ./request.bend as Request
import ./browser.bend as Browser
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














def decision_world(decision: E.Decision) -> M.World():
  E.Decision{E.Application{program, session}, reply, runtime, interaction, durable} = decision
  program

type Requirements is Type:
  Requirements{
    current_world: @completion:E.Completion -> @reason:String -> @+program:M.World() -> @+session:E.Session ->
      {decision_world(E.complete_command(program, D.failure("command_not_submitted", reason), completion, E.Application{program, session})) == program : M.World()},
    owned_field_absent: @+fields:+List<J.Field> -> {J.find(Request.without_guidance(fields), "guidance") == J.Null{} : J.Json},
    create: @profile:String -> @reasoning:String -> @message:String -> @fields:+List<J.Field> ->
      {Browser.request_payload(M.Create{profile, reasoning, message, J.Object{fields}}) ==
          J.Object{[J.Field{"settings", J.Object{Request.without_guidance(fields)}},
            J.Field{"op", J.Text{"create"}}, J.Field{"profile", J.Text{profile}},
            J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", J.Text{message}}]} : J.Json},
    fork: @id:Nat -> @count:Nat -> @messages:+List<String> -> @fields:+List<J.Field> ->
      {Browser.request_payload(M.Fork{id, count, messages, J.Object{fields}}) ==
          J.Object{[J.Field{"settings", J.Object{Request.without_guidance(fields)}}, J.Field{"op", J.Text{"fork"}},
            J.Field{"task_id", J.nat(id)}, J.Field{"child_count", J.nat(count)},
            J.Field{"messages", J.Array{J.text_items(messages)}}]} : J.Json},
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
          Browser.State{web, sequence, next, pending, None{}}) ==
          Browser.completion_receipt(completion, Receipt.from_reply(ticket, origin, D.failure("command_not_submitted", reason)), Browser.product_input(Product.CommandCompleted{Browser.program(Browser.State{web, sequence, next, pending, None{}}),
            D.failure("command_not_submitted", reason), completion},
            Browser.State{web, sequence, next, Browser.remove(pending, ticket), None{}})) : Browser.Decision},
    stale: @+ticket:Nat -> @reason:String -> @+pending:+List<Browser.Pending> -> @web:Web.State -> @sequence:Nat -> @next:Nat ->
      @absent:{Browser.find(pending, ticket) == None{} : Maybe<&2, Browser.Pending>} ->
      {Browser.command_rejected(ticket, reason, Browser.State{web, sequence, next, pending, None{}}) ==
        Browser.Decision{Browser.State{web, sequence, next, pending, None{}}, Nil{}} : Browser.Decision},
    consumed: @+pending:+List<Browser.Pending> -> @+ticket:Nat -> {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool},
    other_pending: @+entry:Browser.Pending -> @+rest:+List<Browser.Pending> -> @+ticket:Nat ->
      @distinct:{Nat.is_eq(Browser.ticket_of(entry), ticket) == False{} : Bool} ->
      {Browser.remove(entry <> rest, ticket) == entry <> Browser.remove(rest, ticket) : +List<Browser.Pending>},
    rejected_draft: @revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @directory_entry:String -> @submitted:Nat -> @reason:String ->
      {E.settled_current(U.Draft{revision, body, feedback, directory_entry}, True{}, False{}, submitted,
          D.failure("command_not_submitted", reason)) ==
          U.Draft{revision, body, U.Rejected{submitted, reason}, directory_entry} : U.Draft},
    uncertain: @ticket:Nat -> @reason:String -> @web:Web.State -> @sequence:Nat -> @next:Nat -> @pending:+List<Browser.Pending> ->
      {Browser.failed_completion(ticket, reason, Browser.State{web, sequence, next, pending, None{}}) ==
        Browser.Decision{Browser.State{web, sequence, next, Browser.uncertain_pending(pending, ticket, reason), None{}}, Nil{}} : Browser.Decision},
    other_command: @id:Nat -> @message:String -> {Browser.request_payload(M.Send{id, message}) == Codec.command_json(M.Send{id, message}) : J.Json}}

law evidence:
  Requirements
