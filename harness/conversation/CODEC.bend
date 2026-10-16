import Base
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J

def call_json(call: D.Call) -> J.Json:
  D.Call{id, name, arguments} = call
  J.Object{[J.Field{"id", J.Text{id}}, J.Field{"name", J.Text{name}}, J.Field{"arguments", arguments}]}

def message_json(message: D.Message) -> J.Json:
  match message:
    case D.ForkResult{owner, call_id, branch}:
      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{call_id}},
        J.Field{"content", J.nat(branch)}, J.Field{"is_error", J.Boolean{False{}}}]}
    case D.HookRecord{owner, call_id, plugin, outcome}:
      J.Object{[J.Field{"role", J.Text{"hook_record"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"call_id", J.Text{call_id}},
        J.Field{"plugin", D.plugin_json(plugin)}, J.Field{"content", D.hook_json(outcome)}]}
    case D.ToolReceipt{owner, operation, call, value, error}:
      J.Object{[J.Field{"role", J.Text{"tool_receipt"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"operation_id", J.nat(operation)},
        J.Field{"call", call_json(call)}, J.Field{"content", value}, J.Field{"is_error", J.Boolean{error}}]}
    case D.AfterRecord{owner, operation, plugin, outcome}:
      J.Object{[J.Field{"role", J.Text{"after_record"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"operation_id", J.nat(operation)},
        J.Field{"plugin", D.plugin_json(plugin)}, J.Field{"content", D.after_json(outcome)}]}
    case D.ApprovalRecord{owner, operation, call, reviewer, outcome}:
      J.Object{[J.Field{"role", J.Text{"approval_record"}}, J.Field{"task_id", J.nat(owner)}, J.Field{"operation_id", J.nat(operation)},
        J.Field{"call", call_json(call)}, J.Field{"reviewer", D.approval_reviewer_json(reviewer)},
        J.Field{"content", D.approval_outcome_json(outcome)}]}
    case D.UserMessage{text}:
      J.Object{[J.Field{"role", J.Text{"user"}}, J.Field{"content", J.Text{text}}]}
    case D.AssistantMessage{text}:
      J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Text{text}}]}
    case D.FunctionCall{call}:
      J.Object{[J.Field{"role", J.Text{"function_call"}}, J.Field{"content", call_json(call)}]}
    case D.FunctionOutput{call_id, value, error}:
      J.Object{[J.Field{"role", J.Text{"function_output"}}, J.Field{"call_id", J.Text{call_id}},
        J.Field{"content", value}, J.Field{"is_error", J.Boolean{error}}]}
    case D.OperationResult{ticket, call_id, tool, value, error}:
      J.Object{[J.Field{"role", J.Text{"operation_result"}}, J.Field{"operation_id", J.nat(ticket)},
        J.Field{"call_id", J.Text{call_id}}, J.Field{"tool", J.Text{tool}},
        J.Field{"content", value}, J.Field{"is_error", J.Boolean{error}}]}
    case D.FailureMessage{text}:
      J.Object{[J.Field{"role", J.Text{"error"}}, J.Field{"content", J.Text{text}}]}
    case D.ModelContext{value}:
      J.Object{[J.Field{"role", J.Text{"model_context"}}, J.Field{"content", value}]}
    case D.ContextReplacement{value}:
      J.Object{[J.Field{"role", J.Text{"context_replacement"}}, J.Field{"content", value}]}
    case D.ReasoningRecord{owner, effort, remaining, sampling}:
      J.Object{[J.Field{"role", J.Text{"reasoning_record"}}, J.Field{"task_id", J.nat(owner)},
        J.Field{"content", J.Object{[J.Field{"effort", J.Text{effort}}, J.Field{"remaining", J.nat(remaining)},
          J.Field{"sampling", J.Boolean{sampling}}]}}]}
    case D.ContextMessage{context}: D.context_json(context)

def messages_json(messages: +List<D.Message>) -> +List<J.Json>:
  match messages:
    case Nil{}: Nil{}
    case Con{message, rest}: message_json(message) <> messages_json(rest)
