import Base
import ../MODEL.bend as M
import ./json.bend as J
import ./tasks.bend as T

def model_json(model: M.Model) -> J.Json:
  M.Model{M.Profile{profile, provider, name}, reasoning, project} = model
  J.Object{[J.Field{"profile", J.Text{profile}}, J.Field{"provider", J.Text{provider}},
    J.Field{"name", J.Text{name}}, J.Field{"reasoning", J.Text{reasoning}}, J.Field{"project", M.project_json(project)}]}

def effect(effect: M.Effect) -> J.Json:
  match effect:
    case M.RequestModel{task_id, ticket, model, history, tools, callable}:
      J.Object{[J.Field{"kind", J.Text{"model"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"instructions", J.Text{M.assistant_instructions()}},
        J.Field{"model", model_json(model)}, J.Field{"history", J.Array{T.messages_json(M.history_messages(history, Nil{}))}},
        J.Field{"tools", J.Array{M.tools_json(tools)}}, J.Field{"callable", J.Array{T.strings_json(callable)}}]}
    case M.ExecuteTool{task_id, ticket, tool, call}:
      J.Object{[J.Field{"kind", J.Text{"tool"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"tool", M.tool_json(tool)}, J.Field{"call", T.call_json(call)}]}
    case M.CancelTask{task_id}:
      J.Object{[J.Field{"kind", J.Text{"cancel"}}, J.Field{"task_id", J.nat(task_id)}]}
    case M.CancelTicket{task_id, ticket}:
      J.Object{[J.Field{"kind", J.Text{"cancel_ticket"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)}]}
    case M.RequestSummary{task_id, ticket, model, history}:
      J.Object{[J.Field{"kind", J.Text{"summary"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", model_json(model)}, J.Field{"instructions", J.Text{M.summary_instructions()}},
        J.Field{"history", J.Array{T.messages_json(M.history_messages(history, Nil{}))}},
        J.Field{"tools", J.Array{Nil{}}}, J.Field{"callable", J.Array{Nil{}}}]}
    case M.ContinueScheduling{}:
      J.Object{[J.Field{"kind", J.Text{"continue"}}]}

def effects(items: +List<M.Effect>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{head, tail}: effect(head) <> effects(tail)

def envelope(durable: Bool, decision: M.Decision) -> J.Json:
  M.Decision{world, reply, outputs} = decision
  J.Object{[J.Field{"durable", J.Boolean{durable}}, J.Field{"reply", reply}, J.Field{"effects", J.Array{effects(outputs)}}]}
