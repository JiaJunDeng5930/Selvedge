import Base
import ../REASONING.bend as Reasoning
import ../MODEL.bend as M
import ../APPROVALS.bend as Approvals
import ./json.bend as J
import ./tasks.bend as T
import ./reasoning-context.bend as ReasoningContext

def model_json(model: M.Model) -> J.Json:
  M.Model{M.Profile{profile, provider, name, policy}, reasoning, project} = model
  J.Object{[J.Field{"profile", J.Text{profile}}, J.Field{"provider", J.Text{provider}},
    J.Field{"name", J.Text{name}}, J.Field{"reasoning", J.Text{reasoning}}, J.Field{"adaptive_reasoning", Reasoning.json(policy)},
    J.Field{"project", M.project_json(project)}]}

def references(values: +List<M.PluginRef>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: M.plugin_json(value) <> references(rest)

def payload(value: Maybe<&2, J.Json>) -> J.Json:
  match value:
    case None{}: J.Null{}
    case Some{value}: value

def omitted(value: Maybe<&2, J.Json>) -> Bool:
  match value:
    case None{}: True{}
    case Some{value}: False{}

def notices(items: +List<M.Notice>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{M.Notice{kind, task_id, cursor, +value, recipients}, rest}:
      J.Object{[J.Field{"type", J.Text{M.event_name(kind)}}, J.Field{"task_id", J.optional_nat(task_id)},
        J.Field{"cursor", J.optional_nat(cursor)}, J.Field{"payload", payload(value)}, J.Field{"payload_omitted", J.Boolean{omitted(value)}},
        J.Field{"recipients", J.Array{references(recipients)}}]} <> notices(rest)

def effect(effect: M.Effect) -> J.Json:
  match effect:
    case M.NotifyPlugins{events}: J.Object{[J.Field{"kind", J.Text{"plugin_events"}}, J.Field{"events", J.Array{notices(events)}}]}
    case M.CheckTool{task_id, ticket, plugin, tool, call}:
      J.Object{[J.Field{"kind", J.Text{"hook"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"plugin", M.plugin_json(plugin)}, J.Field{"tool", M.tool_json(tool)}, J.Field{"call", T.call_json(call)}]}
    case M.CheckResult{task_id, ticket, operation, plugin, call, value, error}:
      J.Object{[J.Field{"kind", J.Text{"after_hook"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"operation_id", J.nat(operation)}, J.Field{"plugin", M.plugin_json(plugin)}, J.Field{"call", T.call_json(call)},
        J.Field{"value", value}, J.Field{"error", J.Boolean{error}}]}
    case M.RequestModel{+task_id, ticket, +model, +history, tools, callable, context}:
      J.Object{[J.Field{"kind", J.Text{"model"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"instructions", J.Text{M.assistant_instructions()}},
        J.Field{"model", model_json(model)}, J.Field{"settings", M.task_context_json(context)},
        J.Field{"sampling", ReasoningContext.sampling(task_id, model, history)},
        J.Field{"history", J.Array{T.messages_json(M.history_messages(history, Nil{}))}},
        J.Field{"tools", J.Array{M.tools_json(tools)}}, J.Field{"callable", J.Array{T.strings_json(callable)}}]}
    case M.RequestReasoning{task_id, ticket, model, history}:
      J.Object{[J.Field{"kind", J.Text{"reasoning"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", model_json(model)}, J.Field{"history", J.Array{ReasoningContext.public_history(history, Nil{})}}]}
    case M.RequestBoardText{card_id, ticket, profile, prompt, retitle}:
      J.Object{[J.Field{"kind", J.Text{"board_text"}}, J.Field{"card_id", J.nat(card_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", model_json(M.Model{profile, "default", M.NoProject{}})}, J.Field{"prompt", J.Text{prompt}}, J.Field{"retitle", J.Boolean{retitle}}]}
    case M.ExecuteTool{task_id, ticket, tool, call, context, access}:
      J.Object{[J.Field{"kind", J.Text{"tool"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"tool", M.tool_json(tool)}, J.Field{"call", T.call_json(call)}, J.Field{"execution", M.execution_json(context, access)}]}
    case M.RequestApproval{task_id, ticket, M.Profile{key, provider, name, policy}, call, context, history}:
      J.Object{[J.Field{"kind", J.Text{"approval"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", J.Object{[J.Field{"profile", J.Text{key}}, J.Field{"provider", J.Text{provider}}, J.Field{"name", J.Text{name}},
          J.Field{"reasoning", J.Text{"medium"}}, J.Field{"project", J.Null{}}]}},
        J.Field{"instructions", J.Text{Approvals.instructions()}}, J.Field{"settings", M.task_context_json(context)},
        J.Field{"call", T.call_json(call)}, J.Field{"user_requests", J.Array{Approvals.user_requests(4n, history)}}]}
    case M.CancelTask{task_id}:
      J.Object{[J.Field{"kind", J.Text{"cancel"}}, J.Field{"task_id", J.nat(task_id)}]}
    case M.CancelTicket{task_id, ticket}:
      J.Object{[J.Field{"kind", J.Text{"cancel_ticket"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)}]}
    case M.RequestSummary{+task_id, ticket, +model, +history, context}:
      J.Object{[J.Field{"kind", J.Text{"summary"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", model_json(model)}, J.Field{"settings", M.task_context_json(context)}, J.Field{"instructions", J.Text{M.summary_instructions()}},
        J.Field{"sampling", ReasoningContext.sampling(task_id, model, history)},
        J.Field{"context_instructions", J.Text{M.assistant_instructions()}},
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
