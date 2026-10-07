import Base
import ../features/CODEC.bend as FeatureCodec
import ../features/MODEL.bend as F
import ../../bendlib/effects.bend as Effects
import ../../bendlib/component.bend as Component
import ../DOMAIN.bend as D
import ../reasoning/MODEL.bend as Reasoning
import ../MODEL.bend as M
import ../approval/MODEL.bend as Approvals
import ../../bendlib/json.bend as J
import ../tasks/PROGRAM.bend as T
import ../reasoning/context.bend as ReasoningContext

def model_json(model: D.Model) -> J.Json:
  D.Model{D.Profile{profile, provider, name, policy, options}, reasoning, project} = model
  J.Object{[J.Field{"profile", J.Text{profile}}, J.Field{"provider", J.Text{provider}},
    J.Field{"name", J.Text{name}}, J.Field{"reasoning", J.Text{reasoning}}, J.Field{"adaptive_reasoning", Reasoning.json(policy)},
    J.Field{"project", D.project_json(project)}]}

def references(values: +List<D.PluginRef>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: D.plugin_json(value) <> references(rest)

def payload(value: Maybe<&2, J.Json>) -> J.Json:
  match value:
    case None{}: J.Null{}
    case Some{value}: value

def omitted(value: Maybe<&2, J.Json>) -> Bool:
  match value:
    case None{}: True{}
    case Some{value}: False{}

def notices(items: +List<D.Notice>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{D.Notice{kind, task_id, cursor, +value, recipients}, rest}:
      J.Object{[J.Field{"type", J.Text{D.event_name(kind)}}, J.Field{"task_id", J.optional_nat(task_id)},
        J.Field{"cursor", J.optional_nat(cursor)}, J.Field{"payload", payload(value)}, J.Field{"payload_omitted", J.Boolean{omitted(value)}},
        J.Field{"recipients", J.Array{references(recipients)}}]} <> notices(rest)

def effect(effect: M.Effect()) -> J.Json:
  match effect:
    case Effects.NotifyPlugins{events}: J.Object{[J.Field{"kind", J.Text{"plugin_events"}}, J.Field{"events", J.Array{notices(events)}}]}
    case Effects.CheckTool{task_id, ticket, plugin, tool, call}:
      J.Object{[J.Field{"kind", J.Text{"hook"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"plugin", D.plugin_json(plugin)}, J.Field{"tool", D.tool_json(tool)}, J.Field{"call", T.call_json(call)}]}
    case Effects.CheckResult{task_id, ticket, operation, plugin, call, value, error}:
      J.Object{[J.Field{"kind", J.Text{"after_hook"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"operation_id", J.nat(operation)}, J.Field{"plugin", D.plugin_json(plugin)}, J.Field{"call", T.call_json(call)},
        J.Field{"value", value}, J.Field{"error", J.Boolean{error}}]}
    case Effects.RequestModel{+task_id, ticket, +model, +history, tools, callable, context}:
      J.Object{[J.Field{"kind", J.Text{"model"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"instructions", J.Text{D.assistant_instructions()}},
        J.Field{"model", model_json(model)}, J.Field{"settings", D.task_context_json(context)},
        J.Field{"sampling", ReasoningContext.sampling(task_id, model, history)},
        J.Field{"history", J.Array{T.messages_json(D.history_messages(history, Nil{}))}},
        J.Field{"tools", J.Array{D.tools_json(tools)}}, J.Field{"callable", J.Array{J.text_items(callable)}}]}
    case Effects.RequestReasoning{task_id, ticket, model, history}:
      J.Object{[J.Field{"kind", J.Text{"reasoning"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", model_json(model)}, J.Field{"history", J.Array{ReasoningContext.public_history(history, Nil{})}}]}
    case Effects.FeatureEffect{effect}: FeatureCodec.effect_json(model_json, effect)
    case Effects.ExecuteTool{task_id, ticket, tool, call, context, access}:
      J.Object{[J.Field{"kind", J.Text{"tool"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"tool", D.tool_json(tool)}, J.Field{"call", T.call_json(call)}, J.Field{"execution", D.execution_json(context, access)}]}
    case Effects.RequestApproval{task_id, ticket, D.Profile{+key, +provider, +name, policy, options}, call, context, history}:
      J.Object{[J.Field{"kind", J.Text{"approval"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", J.Object{[J.Field{"profile", J.Text{key}}, J.Field{"provider", J.Text{provider}}, J.Field{"name", J.Text{name}},
          J.Field{"reasoning", J.Text{D.profile_default(D.Profile{key, provider, name, policy, options})}}, J.Field{"project", J.Null{}}]}},
        J.Field{"instructions", J.Text{Approvals.instructions()}}, J.Field{"settings", D.task_context_json(context)},
        J.Field{"call", T.call_json(call)}, J.Field{"user_requests", J.Array{Approvals.user_requests(4n, history)}}]}
    case Effects.CancelTask{task_id}:
      J.Object{[J.Field{"kind", J.Text{"cancel"}}, J.Field{"task_id", J.nat(task_id)}]}
    case Effects.CancelTicket{task_id, ticket}:
      J.Object{[J.Field{"kind", J.Text{"cancel_ticket"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)}]}
    case Effects.RequestSummary{+task_id, ticket, +model, +history, context}:
      J.Object{[J.Field{"kind", J.Text{"summary"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", model_json(model)}, J.Field{"settings", D.task_context_json(context)}, J.Field{"instructions", J.Text{D.summary_instructions()}},
        J.Field{"sampling", ReasoningContext.sampling(task_id, model, history)},
        J.Field{"context_instructions", J.Text{D.assistant_instructions()}},
        J.Field{"history", J.Array{T.messages_json(D.history_messages(history, Nil{}))}},
        J.Field{"tools", J.Array{Nil{}}}, J.Field{"callable", J.Array{Nil{}}}]}
    case Effects.ContinueScheduling{}:
      J.Object{[J.Field{"kind", J.Text{"continue"}}]}

def effects(items: +List<M.Effect()>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{head, tail}: effect(head) <> effects(tail)

def envelope(durable: Bool, decision: M.Decision()) -> J.Json:
  Component.Decision{world, reply, outputs} = decision
  J.Object{[J.Field{"durable", J.Boolean{durable}}, J.Field{"reply", reply}, J.Field{"effects", J.Array{effects(outputs)}}]}
