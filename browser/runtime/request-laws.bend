import ../../interaction/submission/MODEL.bend as Receipt
import Base
import ./request.bend as Request
import ./SEMANTICS.bend as Browser
import ../MODEL.bend as Web
import ../../harness/MODEL.bend as M
import ../../interaction/MODEL.bend as Product
import ../../harness/features/MODEL.bend as F
import ../../features/board/MODEL.bend as B
import ../../interaction/session/MODEL.bend as E
import ../../interaction/INPUT.bend as U
import ../../bendlib/json.bend as J
import ../../harness/DOMAIN.bend as D
import ../../features/board/CODEC.bend as BoardCodec
import ../../harness/transport/command-codec.bend as Codec
def decision_world(decision: E.Decision) -> M.World():
  E.Decision{+observed_state_1, reply, runtime, interaction, durable} = decision
  +program = E.program(observed_state_1)
  program

type Requirements is Type:
  Requirements{
    current_world: @+model_state:E.Application ->  @completion:E.Completion -> @reason:String -> {decision_world(E.complete_command(E.program(model_state), D.failure("command_not_submitted", reason), completion, model_state)) == E.program(model_state) : M.World()},
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
    settlement: @+model_state:Browser.State ->  @ticket:Nat -> @completion:E.Completion -> @command:J.Json -> @origin:String -> @status:Browser.RequestStatus ->
      @reason:String -> {Browser.rejected_pending(Some{Browser.Pending{ticket, completion, command, origin, status}}, reason,
          Browser.with_receipt(None{}, model_state)) ==
          Browser.completion_receipt(completion, Receipt.from_reply(ticket, origin, D.failure("command_not_submitted", reason)), Browser.product_input(Product.CommandCompleted{Browser.program(Browser.with_receipt(None{}, model_state)),
            D.failure("command_not_submitted", reason), completion},
            Browser.with_receipt(None{}, Browser.with_pending(Browser.remove(Browser.pending(model_state), ticket), model_state)))) : Browser.Decision},
    stale: @+model_state:Browser.State ->  @+ticket:Nat -> @reason:String ->
      @absent:{Browser.find(Browser.pending(model_state), ticket) == None{} : Maybe<&2, Browser.Pending>} -> {Browser.command_rejected(ticket, reason, Browser.with_receipt(None{}, model_state)) ==
        Browser.Decision{Browser.with_receipt(None{}, model_state), Nil{}} : Browser.Decision},
    consumed: @+pending:+List<Browser.Pending> -> @+ticket:Nat -> {Browser.owns_ticket(Browser.remove(pending, ticket), ticket) == False{} : Bool},
    other_pending: @+entry:Browser.Pending -> @+rest:+List<Browser.Pending> -> @+ticket:Nat ->
      @distinct:{Nat.is_eq(Browser.ticket_of(entry), ticket) == False{} : Bool} ->
      {Browser.remove(entry <> rest, ticket) == entry <> Browser.remove(rest, ticket) : +List<Browser.Pending>},
    rejected_draft: @revision:Nat -> @body:U.Body -> @feedback:U.Feedback -> @directory_entry:String -> @submitted:Nat -> @reason:String ->
      {E.settled_current(U.Draft{revision, body, feedback, directory_entry}, True{}, False{}, submitted,
          D.failure("command_not_submitted", reason)) ==
          U.Draft{revision, body, U.Rejected{submitted, reason}, directory_entry} : U.Draft},
    uncertain: @+model_state:Browser.State ->  @ticket:Nat -> @reason:String -> {Browser.failed_completion(ticket, reason, Browser.with_receipt(None{}, model_state)) ==
        Browser.Decision{Browser.with_receipt(None{}, Browser.with_pending(Browser.uncertain_pending(Browser.pending(model_state), ticket, reason), model_state)), Nil{}} : Browser.Decision},
    other_command: @id:Nat -> @message:String -> {Browser.request_payload(M.Send{id, message}) == Codec.command_json(M.Send{id, message}) : J.Json}}
law evidence:
  Requirements
