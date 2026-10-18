import Base
import ../../bendlib/json.bend as J
import ./MODEL.bend as M

def rendered(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Done{text}: text
    case Fail{error}: ""

# Only this conversion derives portable text. Native calls retain the raw JSON
# until a real transport, capacity or capability fallback needs it.
def portable_source(source: M.Source) -> M.Source:
  match source:
    case M.NativeSource{history, raw}: M.PortableSource{rendered(J.show(raw))}
    case M.PortableSource{readable}: M.PortableSource{readable}

def to_portable(state: M.State) -> M.State:
  M.State{source, cursor, carry, width, window, reserve} = state
  M.State{portable_source(source), cursor, carry, width, window, reserve}

def start_choice(native: Bool, state: M.State) -> M.State:
  match native:
    case True{}: state
    case False{}: to_portable(state)

def start(history: J.Json, raw: J.Json, provider: String, method: String, input_tokens: Nat, +window: Nat, +reserve: Nat) -> M.State:
  start_choice(String.eq(provider, "chatgpt") && String.eq(method, "auto") && Nat.is_le(Nat.add(input_tokens, reserve), window),
    M.State{M.NativeSource{history, raw}, 0n, "", window, window, reserve})

def method_text(source: M.Source) -> String:
  match source:
    case M.NativeSource{history, raw}: "native"
    case M.PortableSource{readable}: "portable"

# Base String.take builds a recursive result. These chunks can span hundreds of
# thousands of Unicode characters, so collect the prefix before reversing it.
def collect_chunk(value: String, count: Nat, reversed: String) -> String:
  match value count:
    case SNil{} _: String.reverse(reversed)
    case SCon{head, tail} 0n: String.reverse(reversed)
    case SCon{head, tail} 1n+left: collect_chunk(tail, left, SCon{head, reversed})

def call_fields(source: M.Source, carry: String, width: Nat) -> +List<J.Field>:
  match source:
    case M.NativeSource{history, raw}: [J.Field{"history", history}]
    case M.PortableSource{readable}:
      [J.Field{"chunk", J.Text{collect_chunk(readable, width, "")}}, J.Field{"carry", J.Text{carry}}, J.Field{"prompt", J.Text{M.summary_prompt()}}]

def plan_json(state: M.State) -> J.Json:
  M.State{+source, cursor, carry, width, window, reserve} = state
  J.Object{List.append(&2, J.Field, [J.Field{"method", J.Text{method_text(source)}},
    J.Field{"window_tokens", J.nat(window)}, J.Field{"output_reserve_tokens", J.nat(reserve)}],
    call_fields(source, carry, width))}

def with_width(state: M.State, width: Nat) -> M.State:
  M.State{source, cursor, carry, previous, window, reserve} = state
  M.State{source, cursor, carry, width, window, reserve}

def shown_bytes(result: Result<&2, &2, String, String>, limit: Nat) -> Nat:
  match result:
    case Fail{message}: 1n+limit
    case Done{text}: J.utf8_length(text)

def plan_bytes(+state: M.State, limit: Nat) -> Nat:
  shown_bytes(J.show(plan_json(state)), limit)

def source_has_work(source: M.Source, width: Nat) -> Bool:
  match source:
    case M.NativeSource{history, raw}: True{}
    case M.PortableSource{readable}: String.is_empty(readable) || Nat.is_lt(0n, width)

def has_transport_work(state: M.State) -> Bool:
  M.State{source, cursor, carry, width, window, reserve} = state
  source_has_work(source, width)

def transport_fits(+state: M.State, +budget: Nat) -> Bool:
  has_transport_work(state) && Nat.is_le(plan_bytes(state, budget), budget)

# A large note stays input data: move it in front of the unread source rather
# than truncate it or send a frame that cannot cross the kernel boundary.
def rebase_portable_note(+state: M.State) -> M.State:
  match state:
    case M.State{M.NativeSource{history, raw}, cursor, carry, width, window, reserve}: state
    case M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}:
      M.State{M.PortableSource{"Prior continuation note:\n" ++ carry ++ "\nUnread task history:\n" ++ readable},
        cursor, "", width, window, reserve}

def rebase_note(state: M.State) -> M.State:
  rebase_portable_note(to_portable(state))

def fitted_width(+state: M.State, +budget: Nat) -> M.State:
  M.State{source, cursor, carry, width, window, reserve} = state
  # JSON escapes consume at most six UTF-8 bytes per Unicode character. Measure
  # the complete carry/prompt/metadata first, then spend only the remainder.
  +base = plan_bytes(with_width(state, 0n), budget)
  with_width(state, Nat.min(width, Nat.div(Nat.sub(budget, base), 6n)))

def fit_portable_base(has_room: Bool, state: M.State, budget: Nat) -> M.State:
  match has_room:
    case True{}: fitted_width(state, budget)
    case False{}: fitted_width(rebase_note(state), budget)

def fit_portable(+state: M.State, +budget: Nat) -> M.State:
  fit_portable_base(Nat.is_le(Nat.add(plan_bytes(with_width(state, 0n), budget), 6n), budget), state, budget)

def native_transport_fits(fits: Bool, state: M.State, budget: Nat) -> M.State:
  match fits:
    case True{}: state
    case False{}: fit_portable(to_portable(state), budget)

def fit_transport(+state: M.State, +budget: Nat) -> M.State:
  match state:
    case M.State{M.NativeSource{history, raw}, cursor, carry, width, window, reserve}:
      native_transport_fits(transport_fits(state, budget), state, budget)
    case M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}: fit_portable(state, budget)

def portable_candidate(+result: J.Json, summary: String) -> J.Json:
  J.Object{[J.Field{"format", J.Text{"portable"}}, J.Field{"scope", J.get(result, "scope")},
    J.Field{"items", J.Array{[J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Text{summary}}]}]}},
    J.Field{"usage", J.get(result, "usage")}]}

def summary_finished(finished: Bool, +state: M.State, +result: J.Json, +summary: String) -> M.Step:
  match finished state:
    case True{} _: M.Compacted{portable_candidate(result, summary)}
    case False{} M.State{M.NativeSource{history, raw}, cursor, carry, width, window, reserve}:
      M.Failed{"The native compactor returned an invalid replacement window"}
    case False{} M.State{M.PortableSource{+readable}, cursor, carry, +width, window, reserve}:
      M.Next{M.State{M.PortableSource{String.drop(readable, width)},
        Nat.add(cursor, String.length(collect_chunk(readable, width, ""))), summary, width, window, reserve}}

def summary_checked(valid: Bool, +state: M.State, +result: J.Json) -> M.Step:
  match valid state:
    case False{} _: M.Failed{"The compactor returned an empty continuation note"}
    case True{} M.State{M.NativeSource{history, raw}, cursor, carry, width, window, reserve}:
      M.Failed{"The native compactor returned an invalid replacement window"}
    case True{} M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}:
      summary_finished(String.is_empty(String.drop(readable, width)), state, result, J.text(J.get(result, "summary_text")))

def reduced_width(state: M.State) -> M.Step:
  M.State{source, cursor, carry, width, window, reserve} = state
  M.Next{M.State{source, cursor, carry, Nat.div(width, 2n), window, reserve}}

def resize_checked(can_reduce: Bool, state: M.State) -> M.Step:
  match can_reduce:
    case True{}: reduced_width(to_portable(state))
    case False{}: M.Failed{"Compaction request exceeds the configured model window"}

def resize(+state: M.State) -> M.Step:
  M.State{source, cursor, carry, width, window, reserve} = state
  resize_checked(Nat.is_lt(1n, width), state)

def native_finished(valid: Bool, result: J.Json) -> M.Step:
  match valid:
    case True{}: M.Compacted{result}
    case False{}: M.Failed{"The native compactor returned an invalid replacement window"}

def receive_source(+state: M.State, +result: J.Json) -> M.Step:
  match state:
    case M.State{M.NativeSource{history, raw}, cursor, carry, width, window, reserve}:
      native_finished(String.eq(J.text(J.get(result, "format")), "native"), result)
    case M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}:
      summary_checked(J.is_text(J.get(result, "summary_text")) && Bool.not(String.is_empty(J.text(J.get(result, "summary_text")))), state, result)

def native_unavailable(+state: M.State, result: J.Json) -> M.Step:
  match state:
    case M.State{M.NativeSource{history, raw}, cursor, carry, width, window, reserve}: M.Next{to_portable(state)}
    case M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}: receive_source(state, result)

type ReceiveActionName is Data:
  ReceiveActionNameResize{}
  ReceiveActionNameNativeUnavailable{}
  ReceiveActionNameOther{}

def receive_action_discriminant(+value: String) -> ReceiveActionName:
  Bool.pick(ReceiveActionName, String.eq(value, "resize"), ReceiveActionNameResize{},
    Bool.pick(ReceiveActionName, String.eq(value, "native_unavailable"), ReceiveActionNameNativeUnavailable{},
    ReceiveActionNameOther{}))

def receive_action_classified(action: ReceiveActionName, state: M.State, result: J.Json) -> M.Step:
  match action:
    case ReceiveActionNameResize{}: resize(state)
    case ReceiveActionNameNativeUnavailable{}: native_unavailable(state, result)
    case ReceiveActionNameOther{}: receive_source(state, result)

def receive_action(action: String, state: M.State, result: J.Json) -> M.Step:
  receive_action_classified(receive_action_discriminant(action), state, result)

def receive(+state: M.State, +result: J.Json) -> M.Step:
  receive_action(J.text(J.get(result, "action")), state, result)
