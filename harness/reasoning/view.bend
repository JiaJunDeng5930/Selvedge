import Base
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../conversation/PROGRAM.bend as Content
import ./MODEL.bend as R
import ./context.bend as Context

# This is a transport preview, before host tokenization. The evaluator retains
# its own exact tokenizer budgets; private history and the task are unchanged.
def maximum_bytes() -> Nat:
  16384n

def omission() -> String:
  "\n[Evaluator history preview: material omitted; omissions are unknown.]\n"

def excerpt_checked(short: Bool, +text: String) -> String:
  match short:
    case True{}: text
    case False{}: String.take(text, 768n) ++ omission() ++ String.drop(text, Nat.sub(String.length(text), 256n))

def excerpt(+text: String) -> String:
  excerpt_checked(Nat.is_le(String.length(text), 1024n), text)

def preview_value_checked(short: Bool, original: J.Json, text: String) -> J.Json:
  match short:
    case True{}: original
    case False{}: J.Text{excerpt(text)}

def preview_value_result(result: Result<&2, &2, String, String>, original: J.Json) -> J.Json:
  match result:
    case Done{+text}: preview_value_checked(Nat.is_le(String.length(text), 1024n), original, text)
    case Fail{error}: J.Text{omission()}

def preview_value(+value: J.Json) -> J.Json:
  preview_value_result(J.show(value), value)

def preview_message(+kind: String, +message: J.Json) -> J.Json:
  match kind:
    case "function_call": J.Object{[J.Field{"role", J.Text{kind}}, J.Field{"call_id", J.get(message, "call_id")},
      J.Field{"name", J.get(message, "name")}, J.Field{"arguments", preview_value(J.get(message, "arguments"))}]}
    case "function_output": J.Object{[J.Field{"role", J.Text{kind}}, J.Field{"call_id", J.get(message, "call_id")},
      J.Field{"is_error", J.get(message, "is_error")}, J.Field{"content", preview_value(J.get(message, "content"))}]}
    case _: J.Object{[J.Field{"role", J.Text{kind}}, J.Field{"content", J.Text{excerpt(Content.public_text(J.get(message, "content")))}}]}

def take_names(count: Nat, names: +List<String>) -> +List<String>:
  match count names:
    case 1n+p Con{name, rest}: name <> take_names(p, rest)
    case _ _: Nil{}

def call_names_step(kind: String, +message: J.Json, names: +List<String>) -> +List<String>:
  match kind:
    case "function_call": J.text(J.get(message, "call_id")) <> take_names(5n, names)
    case _: names

def call_names(messages: +List<J.Json>, names: +List<String>) -> +List<String>:
  match messages:
    case Nil{}: names
    case Con{+message, rest}: call_names(rest, call_names_step(J.text(J.get(message, "role")), message, names))

type Selection is Data:
  Selection{users: Nat, notes: Nat, outputs: Nat, items: +List<J.Json>}

def keep(yes: Bool, kind: String, message: J.Json, users: Nat, notes: Nat, outputs: Nat, items: +List<J.Json>) -> Selection:
  match yes:
    case True{}: Selection{users, notes, outputs, preview_message(kind, message) <> items}
    case False{}: Selection{users, notes, outputs, items}

def selected_output(matches: Bool, message: J.Json, users: Nat, notes: Nat, +outputs: Nat, items: +List<J.Json>) -> Selection:
  match matches:
    case True{}: keep(Nat.is_lt(outputs, 12n), "function_output", message, users, notes, 1n+outputs, items)
    case False{}: Selection{users, notes, outputs, items}

def selected_fields(kind: String, +message: J.Json, +names: +List<String>, first_user: Bool, +users: Nat, +notes: Nat, +outputs: Nat, items: +List<J.Json>) -> Selection:
  match kind:
    case "user": keep(first_user || Nat.is_lt(users, 7n), "user", message, 1n+users, notes, outputs, items)
    case "assistant": keep(Nat.is_lt(notes, 8n), "assistant", message, users, 1n+notes, outputs, items)
    case "reasoning_summary": keep(Nat.is_lt(notes, 8n), "reasoning_summary", message, users, 1n+notes, outputs, items)
    case "error": keep(Nat.is_lt(notes, 8n), "error", message, users, 1n+notes, outputs, items)
    case "function_call": keep(R.member(names, J.text(J.get(message, "call_id"))), "function_call", message, users, notes, outputs, items)
    case "function_output": selected_output(R.member(names, J.text(J.get(message, "call_id"))), message, users, notes, outputs, items)
    case _: Selection{users, notes, outputs, items}

def selected(kind: String, message: J.Json, names: +List<String>, first_user: Bool, selection: Selection) -> Selection:
  match selection:
    case Selection{users, notes, outputs, items}: selected_fields(kind, message, names, first_user, users, notes, outputs, items)

def select(messages: +List<J.Json>, +names: +List<String>, +seen_user: Bool) -> Selection:
  match messages:
    case Nil{}: Selection{0n, 0n, 0n, Nil{}}
    case Con{+message, rest}: selected(J.text(J.get(message, "role")), message, names,
      Bool.not(seen_user), select(rest, names, seen_user || String.eq(J.text(J.get(message, "role")), "user")))

def items(selection: Selection) -> +List<J.Json>:
  Selection{users, notes, outputs, items} = selection
  items

def fits_text(result: Result<&2, &2, String, String>) -> Bool:
  match result:
    case Done{text}: Nat.is_le(J.utf8_length(text), maximum_bytes())
    case Fail{error}: False{}

def fits(+messages: +List<J.Json>) -> Bool:
  fits_text(J.show(J.Array{messages}))

def marker() -> J.Json:
  J.Object{[J.Field{"role", J.Text{"error"}}, J.Field{"content", J.Text{omission()}}]}

def admitted(accepted: Bool, messages: +List<J.Json>) -> +List<J.Json>:
  match accepted:
    case True{}: messages
    case False{}: [marker()]

def essential_user(message: J.Json, seen_user: Bool, remaining: Selection) -> Selection:
  match remaining:
    case Selection{+users, notes, outputs, items}:
      keep(Bool.not(seen_user) || Nat.is_lt(users, 1n), "user", message, 1n+users, notes, outputs, items)

def essential_kind(kind: String, message: J.Json, seen_user: Bool, remaining: Selection) -> Selection:
  match kind:
    case "user": essential_user(message, seen_user, remaining)
    case _: remaining

def essential(messages: +List<J.Json>, +seen_user: Bool) -> Selection:
  match messages:
    case Nil{}: Selection{0n, 0n, 0n, Nil{}}
    case Con{+message, rest}: essential_kind(J.text(J.get(message, "role")), message, seen_user,
      essential(rest, seen_user || String.eq(J.text(J.get(message, "role")), "user")))

def prioritized(accepted: Bool, full: +List<J.Json>, +essential: +List<J.Json>) -> +List<J.Json>:
  match accepted:
    case True{}: full
    case False{}: admitted(fits(essential), essential)

def history(+history: D.History) -> +List<J.Json>:
  +public = Context.public_history(history, Nil{})
  +candidate: +List<J.Json> = marker() <> items(select(public, call_names(public, Nil{}), False{}))
  prioritized(fits(candidate), candidate, marker() <> items(essential(public, False{})))
