import Base
import ../DOMAIN.bend as D
import ../conversation/CODEC.bend as Codec
import ../conversation/PROGRAM.bend as Content
import ../../bendlib/json.bend as J
import ../../bendlib/equality.bend as Same
import ./MODEL.bend as Spec

def has_output(history: D.History, +id: String) -> Bool:
  match history:
    case D.EmptyHistory{}: False{}
    case D.HistoryNode{previous, D.FunctionOutput{call_id, value, error}}:
      String.eq(call_id, id) || has_output(previous, id)
    case D.HistoryNode{previous, D.ForkResult{owner, call_id, branch}}:
      String.eq(call_id, id) || has_output(previous, id)
    case D.HistoryNode{previous, other}: has_output(previous, id)

def settled_calls(remaining: D.History, +whole: D.History) -> Bool:
  match remaining:
    case D.EmptyHistory{}: True{}
    case D.HistoryNode{previous, D.FunctionCall{D.Call{id, name, arguments}}}:
      has_output(whole, id) && settled_calls(previous, whole)
    case D.HistoryNode{previous, other}: settled_calls(previous, whole)

def portable(summary: String) -> J.Json:
  J.Object{[J.Field{"format", J.Text{"portable"}}, J.Field{"scope", J.Text{""}},
    J.Field{"items", J.Array{[J.Object{[J.Field{"role", J.Text{"user"}},
      J.Field{"content", J.Text{"Task continuation summary (fallible; original records remain available through read_task):\n" ++ summary}}]}]}}]}

def message_json(message: D.Message) -> J.Json:
  Codec.message_json(message)

def history_json(history: D.History) -> +List<J.Json>:
  Codec.messages_json(D.history_messages(history, Nil{}))

def readable_item(kind: String, +item: J.Json) -> +List<J.Json>:
  match kind:
    case "message": [J.Object{[J.Field{"role", J.get(item, "role")},
      J.Field{"content", J.Text{Content.content_parts(J.items(J.get(item, "content")))}}]}]
    case "reasoning": [J.Object{[J.Field{"role", J.Text{"assistant"}},
      J.Field{"content", J.Text{Content.content_parts(J.items(J.get(item, "summary")))}}]}]
    case _: Nil{}

def readable_context(+value: J.Json) -> +List<J.Json>:
  +item = Content.provider_value(value)
  readable_item(J.text(J.get(item, "type")), item)

def readable_message_kind(kind: String, +message: J.Json) -> +List<J.Json>:
  match kind:
    case "context_replacement": Nil{}
    case "model_context": readable_context(J.get(message, "content"))
    case _: [message]

def readable_message(+message: J.Json) -> +List<J.Json>:
  readable_message_kind(J.text(J.get(message, "role")), message)

def raw_messages(messages: +List<J.Json>) -> +List<J.Json>:
  match messages:
    case Nil{}: Nil{}
    case Con{message, rest}: List.append(&2, J.Json, readable_message(message), raw_messages(rest))

def scoped_context(usable: Bool, +value: J.Json) -> +List<J.Json>:
  match usable:
    case True{}: [J.Object{[J.Field{"role", J.Text{"model_context"}}, J.Field{"content", Content.provider_value(value)}]}]
    case False{}: readable_context(value)

def scoped_message_kind(kind: String, +message: J.Json, +scope: String) -> +List<J.Json>:
  match kind:
    case "context_replacement": Nil{}
    case "model_context": scoped_context(
      String.eq(J.text(J.get(J.get(message, "content"), "type")), "provider_receipt") &&
      Bool.not(String.eq(scope, "")) && String.eq(J.text(J.get(J.get(message, "content"), "scope")), scope), J.get(message, "content"))
    case _: [message]

def scoped_message(+message: J.Json, +scope: String) -> +List<J.Json>:
  scoped_message_kind(J.text(J.get(message, "role")), message, scope)

def scoped_messages(messages: +List<J.Json>, +scope: String) -> +List<J.Json>:
  match messages:
    case Nil{}: Nil{}
    case Con{message, rest}: List.append(&2, J.Json, scoped_message(message, scope), scoped_messages(rest, scope))

def latest(messages: +List<J.Json>, +scope: String, +position: Nat, current: Spec.Selection) -> Spec.Selection:
  match messages:
    case Nil{}: current
    case Con{message, rest}: latest(rest, scope, 1n+position, Spec.required_event(message, position, scope, current))

def replacement_source(selection: Spec.Selection) -> Maybe<&2, Nat>:
  match selection:
    case Spec.Original{}: None{}
    case Spec.Replacement{source, items}: Some{source}

def fixed_kind(kind: String, message: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match kind:
    case "task_context": message <> rest
    case _: rest

def fixed(messages: +List<J.Json>) -> +List<J.Json>:
  match messages:
    case Nil{}: Nil{}
    case Con{+message, rest}: fixed_kind(J.text(J.get(message, "role")), message, fixed(rest))

def dialogue_kind(kind: String, message: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match kind:
    case "task_context": rest
    case "context_replacement": rest
    case _: message <> rest

def dialogue(messages: +List<J.Json>) -> +List<J.Json>:
  match messages:
    case Nil{}: Nil{}
    case Con{+message, rest}: dialogue_kind(J.text(J.get(message, "role")), message, dialogue(rest))

def prefix(count: Nat, messages: +List<J.Json>) -> +List<J.Json>:
  match count messages:
    case 1n+p Con{message, rest}: message <> prefix(p, rest)
    case _ _: Nil{}

def suffix(count: Nat, messages: +List<J.Json>) -> +List<J.Json>:
  match count messages:
    case 0n messages: messages
    case 1n+p Con{message, rest}: suffix(p, rest)
    case _ _: Nil{}

def assemble(selection: Spec.Selection, +messages: +List<J.Json>, +scope: String) -> +List<J.Json>:
  match selection:
    case Spec.Original{}: scoped_messages(messages, scope)
    case Spec.Replacement{+source, items}:
      List.append(&2, J.Json, fixed(prefix(source, messages)),
        List.append(&2, J.Json, dialogue(items), scoped_messages(suffix(source, messages), scope)))

def target_messages(+messages: +List<J.Json>, +scope: String) -> +List<J.Json>:
  assemble(latest(messages, scope, 0n, Spec.Original{}), messages, scope)

def retained_kind(kind: String, message: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match kind:
    case "context_replacement": rest
    case _: message <> rest

def retained_messages(messages: +List<J.Json>) -> +List<J.Json>:
  match messages:
    case Nil{}: Nil{}
    case Con{+message, rest}: retained_kind(J.text(J.get(message, "role")), message, retained_messages(rest))

def portable_assemble(selection: Spec.Selection, +messages: +List<J.Json>) -> +List<J.Json>:
  match selection:
    case Spec.Original{}: messages
    case Spec.Replacement{+source, items}:
      List.append(&2, J.Json, fixed(prefix(source, messages)),
        List.append(&2, J.Json, dialogue(items), retained_messages(suffix(source, messages))))

# Before authorization, only portable replacements can be selected. Retain the
# suffix receipts verbatim so the adapter can still check their actual scope.
def portable_messages(+messages: +List<J.Json>) -> +List<J.Json>:
  portable_assemble(latest(messages, "", 0n, Spec.Original{}), messages)

# The equality work list needs a count of nodes, rather than a fixed history or
# byte limit. Deriving it from the captured source also covers large tool values.
def comparison_steps(value: J.Json) -> Nat:
  match value:
    case J.Array{Nil{}}: 2n
    case J.Array{Con{head, tail}}: 3n+Nat.add(comparison_steps(head), comparison_steps(J.Array{tail}))
    case J.Object{Nil{}}: 2n
    case J.Object{Con{J.Field{name, value}, tail}}: 4n+Nat.add(comparison_steps(value), comparison_steps(J.Object{tail}))
    case _: 2n

def adoptable(+snapshot: D.History, +candidate: J.Json, +current: D.History) -> Bool:
  Same.history_extends(comparison_steps(J.Array{history_json(snapshot)}), snapshot, current) && Spec.artifact_valid(candidate)

def commit(accepted: Bool, +snapshot: D.History, +candidate: J.Json, +current: D.History) -> D.History:
  match accepted:
    case False{}: current
    case True{}: D.HistoryNode{current, Spec.record(D.history_length(snapshot), candidate)}

def adopt(+snapshot: D.History, +candidate: J.Json, +current: D.History) -> D.History:
  commit(adoptable(snapshot, candidate, current), snapshot, candidate, current)
