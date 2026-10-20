import Base
import ../context/MODEL.bend as Context
import ../context/KINDS.bend as ContextKinds
import ../features/CODEC.bend as FeatureCodec
import ../../bendlib/effects.bend as Effects
import ../../bendlib/component.bend as Component
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../approval/MODEL.bend as Approvals
import ../../bendlib/json.bend as J
import ../tasks/PROGRAM.bend as T
import ../reasoning/context.bend as ReasoningContext
import ../reasoning/view.bend as ReasoningView
import ../context/PROGRAM.bend as Selection
import ../context/selection.bend as SelectionModel
import ./model-json.bend as ModelJSON

def model_json(model: D.Model) -> J.Json:
  ModelJSON.encode(model)

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

# A positive reserve comes from a measured target. Otherwise adopt portable
# windows before encoding, while retaining suffix receipts for authorization.
def model_history(selected: Bool, +history: D.History, scope: String) -> +List<J.Json>:
  match selected:
    case True{}: Selection.target_messages(Selection.history_json(history), scope)
    case False{}: Selection.portable_messages(Selection.history_json(history))

def model_replacement_source(selected: Bool, history: D.History, scope: String) -> Maybe<&2, Nat>:
  match selected:
    case True{}: Selection.replacement_source(Selection.latest(Selection.history_json(history), scope, 0n, SelectionModel.Original{}))
    case False{}: Selection.replacement_source(Selection.latest(Selection.history_json(history), "", 0n, SelectionModel.Original{}))

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
    case Effects.ObserveContext{task_id, ticket, history, context}:
      J.Object{[J.Field{"kind", J.Text{"observe_context"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"settings", D.task_context_json(context)}, J.Field{"definitions", Context.definitions_json(ContextKinds.definitions())}, J.Field{"bindings", Context.snapshots_json(D.context_bindings(history))}]}
    case Effects.RequestModel{+task_id, ticket, +model, +history, tools, callable, context, +scope, +reserve}:
      J.Object{[J.Field{"kind", J.Text{"model"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", model_json(model)}, J.Field{"output_mode", J.Text{D.output_mode_name(D.history_output_mode(history))}}, J.Field{"settings", D.task_context_json(context)},
        J.Field{"sampling", ReasoningContext.sampling(task_id, model, history)},
        J.Field{"history", J.Array{model_history(Nat.is_lt(0n, reserve), history, scope)}},
        J.Field{"context_selected", J.Boolean{Nat.is_lt(0n, reserve)}}, J.Field{"context_scope", J.Text{scope}},
        J.Field{"context_replacement_source", J.optional_nat(model_replacement_source(Nat.is_lt(0n, reserve), history, scope))},
        J.Field{"output_reserve_tokens", J.nat(reserve)}, J.Field{"source_length", J.nat(D.history_length(history))},
        J.Field{"tools", J.Array{D.tools_json(tools)}}, J.Field{"callable", J.Array{J.text_items(callable)}}]}
    case Effects.RequestReasoning{task_id, ticket, model, history}:
      J.Object{[J.Field{"kind", J.Text{"reasoning"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", model_json(model)}, J.Field{"history", J.Array{ReasoningView.history(history)}},
        J.Field{"history_preview", J.Boolean{True{}}}, J.Field{"history_preview_bytes", J.nat(ReasoningView.maximum_bytes())}]}
    case Effects.FeatureEffect{effect}: FeatureCodec.effect_json(model_json, effect)
    case Effects.ExecuteTool{task_id, ticket, operation_id, tool, call, context, access}:
      J.Object{[J.Field{"kind", J.Text{"tool"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"operation_id", J.nat(operation_id)},
        J.Field{"tool", D.tool_json(tool)}, J.Field{"call", T.call_json(call)}, J.Field{"execution", D.execution_json(context, access)}]}
    case Effects.RequestApproval{task_id, ticket, D.Profile{+key, +provider, +name, policy, options}, call, context, history}:
      J.Object{[J.Field{"kind", J.Text{"approval"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)},
        J.Field{"model", J.Object{[J.Field{"profile", J.Text{key}}, J.Field{"provider", J.Text{provider}}, J.Field{"name", J.Text{name}},
          J.Field{"reasoning", J.Text{D.profile_default(D.Profile{key, provider, name, policy, options})}}]}},
        J.Field{"instructions", J.Text{Approvals.instructions()}}, J.Field{"settings", D.task_context_json(context)},
        J.Field{"call", T.call_json(call)}, J.Field{"user_requests", J.Array{Approvals.user_requests(4n, history)}}]}
    case Effects.ResetModelSession{task_id}:
      J.Object{[J.Field{"kind", J.Text{"reset_model_session"}}, J.Field{"task_id", J.nat(task_id)}]}
    case Effects.CancelTask{task_id}:
      J.Object{[J.Field{"kind", J.Text{"cancel"}}, J.Field{"task_id", J.nat(task_id)}]}
    case Effects.CancelTicket{task_id, ticket}:
      J.Object{[J.Field{"kind", J.Text{"cancel_ticket"}}, J.Field{"task_id", J.nat(task_id)}, J.Field{"ticket", J.nat(ticket)}]}
    case Effects.ContinueScheduling{}:
      J.Object{[J.Field{"kind", J.Text{"continue"}}]}

def effects(items: +List<M.Effect()>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{head, tail}: effect(head) <> effects(tail)

def envelope(durable: Bool, decision: M.Decision()) -> J.Json:
  Component.Decision{world, reply, outputs} = decision
  J.Object{[J.Field{"durable", J.Boolean{durable}}, J.Field{"reply", reply}, J.Field{"effects", J.Array{effects(outputs)}}]}
