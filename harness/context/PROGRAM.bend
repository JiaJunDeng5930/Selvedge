import Base
import ../DOMAIN.bend as D
import ../conversation/CODEC.bend as Codec
import ../conversation/PROGRAM.bend as Content
import ../../bendlib/json.bend as J
import ../../bendlib/equality.bend as Same
import ./selection.bend as Spec

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

type ReadableItemName is Data:
  ReadableItemNameMessage{}
  ReadableItemNameReasoning{}
  ReadableItemNameOther{}

def readable_item_discriminant(+value: String) -> ReadableItemName:
  Bool.pick(ReadableItemName, String.eq(value, "message"), ReadableItemNameMessage{},
    Bool.pick(ReadableItemName, String.eq(value, "reasoning"), ReadableItemNameReasoning{},
    ReadableItemNameOther{}))

def readable_item_classified(kind: ReadableItemName, +item: J.Json) -> +List<J.Json>:
  match kind:
    case ReadableItemNameMessage{}: [J.Object{[J.Field{"role", J.get(item, "role")},
      J.Field{"content", J.Text{Content.content_parts(J.items(J.get(item, "content")))}}]}]
    case ReadableItemNameReasoning{}: [J.Object{[J.Field{"role", J.Text{"assistant"}},
      J.Field{"content", J.Text{Content.content_parts(J.items(J.get(item, "summary")))}}]}]
    case ReadableItemNameOther{}: Nil{}

def readable_item(kind: String, +item: J.Json) -> +List<J.Json>:
  readable_item_classified(readable_item_discriminant(kind), item)

def readable_context(+value: J.Json) -> +List<J.Json>:
  +item = Content.provider_value(value)
  readable_item(J.text(J.get(item, "type")), item)

type ReadableMessageKindName is Data:
  ReadableMessageKindNameContextReplacement{}
  ReadableMessageKindNameModelContext{}
  ReadableMessageKindNameOther{}

def readable_message_kind_discriminant(+value: String) -> ReadableMessageKindName:
  Bool.pick(ReadableMessageKindName, String.eq(value, "context_replacement"), ReadableMessageKindNameContextReplacement{},
    Bool.pick(ReadableMessageKindName, String.eq(value, "model_context"), ReadableMessageKindNameModelContext{},
    ReadableMessageKindNameOther{}))

def readable_message_kind_classified(kind: ReadableMessageKindName, +message: J.Json) -> +List<J.Json>:
  match kind:
    case ReadableMessageKindNameContextReplacement{}: Nil{}
    case ReadableMessageKindNameModelContext{}: readable_context(J.get(message, "content"))
    case ReadableMessageKindNameOther{}: [message]

def readable_message_kind(kind: String, +message: J.Json) -> +List<J.Json>:
  readable_message_kind_classified(readable_message_kind_discriminant(kind), message)

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

type ScopedMessageKindName is Data:
  ScopedMessageKindNameContextReplacement{}
  ScopedMessageKindNameModelContext{}
  ScopedMessageKindNameOther{}

def scoped_message_kind_discriminant(+value: String) -> ScopedMessageKindName:
  Bool.pick(ScopedMessageKindName, String.eq(value, "context_replacement"), ScopedMessageKindNameContextReplacement{},
    Bool.pick(ScopedMessageKindName, String.eq(value, "model_context"), ScopedMessageKindNameModelContext{},
    ScopedMessageKindNameOther{}))

def scoped_message_kind_classified(kind: ScopedMessageKindName, +message: J.Json, +scope: String) -> +List<J.Json>:
  match kind:
    case ScopedMessageKindNameContextReplacement{}: Nil{}
    case ScopedMessageKindNameModelContext{}: scoped_context(
      String.eq(J.text(J.get(J.get(message, "content"), "type")), "provider_receipt") &&
      Bool.not(String.eq(scope, "")) && String.eq(J.text(J.get(J.get(message, "content"), "scope")), scope), J.get(message, "content"))
    case ScopedMessageKindNameOther{}: [message]

def scoped_message_kind(kind: String, +message: J.Json, +scope: String) -> +List<J.Json>:
  scoped_message_kind_classified(scoped_message_kind_discriminant(kind), message, scope)

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

type FixedKindName is Data:
  FixedKindNameTaskContext{}
  FixedKindNameImage{}
  FixedKindNameOther{}

def fixed_kind_discriminant(+value: String) -> FixedKindName:
  Bool.pick(FixedKindName, String.eq(value, "task_context"), FixedKindNameTaskContext{},
    Bool.pick(FixedKindName, String.eq(value, "user") || String.eq(value, "function_output") || String.eq(value, "operation_result"), FixedKindNameImage{}, FixedKindNameOther{}))

def fixed_kind_classified(kind: FixedKindName, message: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match kind:
    case FixedKindNameTaskContext{}: message <> rest
    case FixedKindNameImage{}: Spec.retained_images(Spec.message_image_parts(J.get(message, "content")), rest)
    case FixedKindNameOther{}: rest

def fixed_kind(kind: String, message: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  fixed_kind_classified(fixed_kind_discriminant(kind), message, rest)

def fixed(messages: +List<J.Json>) -> +List<J.Json>:
  match messages:
    case Nil{}: Nil{}
    case Con{+message, rest}: fixed_kind(J.text(J.get(message, "role")), message, fixed(rest))

type DialogueKindName is Data:
  DialogueKindNameTaskContext{}
  DialogueKindNameOther{}

def dialogue_kind_discriminant(+value: String) -> DialogueKindName:
  Bool.pick(DialogueKindName, String.eq(value, "task_context"), DialogueKindNameTaskContext{},
    Bool.pick(DialogueKindName, String.eq(value, "context_replacement"), DialogueKindNameTaskContext{},
    DialogueKindNameOther{}))

def dialogue_kind_classified(kind: DialogueKindName, message: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match kind:
    case DialogueKindNameTaskContext{}: rest
    case DialogueKindNameOther{}: message <> rest

def dialogue_kind(kind: String, message: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  dialogue_kind_classified(dialogue_kind_discriminant(kind), message, rest)

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

type RetainedKindName is Data:
  RetainedKindNameContextReplacement{}
  RetainedKindNameOther{}

def retained_kind_discriminant(+value: String) -> RetainedKindName:
  Bool.pick(RetainedKindName, String.eq(value, "context_replacement"), RetainedKindNameContextReplacement{},
    RetainedKindNameOther{})

def retained_kind_classified(kind: RetainedKindName, message: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match kind:
    case RetainedKindNameContextReplacement{}: rest
    case RetainedKindNameOther{}: message <> rest

def retained_kind(kind: String, message: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  retained_kind_classified(retained_kind_discriminant(kind), message, rest)

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
