import Base
import ../../bendlib/json.bend as J
import ./MODEL.bend as M

def rendered(result: Result<&2, &2, String, String>) -> String:
  match result:
    case Done{text}: text
    case Fail{error}: ""

def native_choice(allowed: Bool) -> M.Method:
  match allowed:
    case True{}: M.NativeCompaction{}
    case False{}: M.PortableSummary{}

def method_text(method: M.Method) -> String:
  match method:
    case M.NativeCompaction{}: "native"
    case M.PortableSummary{}: "portable"

def is_native(method: M.Method) -> Bool:
  match method:
    case M.NativeCompaction{}: True{}
    case M.PortableSummary{}: False{}

def start(history: J.Json, +raw: J.Json, provider: String, method: String, input_tokens: Nat, +window: Nat, +reserve: Nat) -> M.State:
  M.State{history, rendered(J.show(raw)), 0n, "", window,
    native_choice(String.eq(provider, "chatgpt") && String.eq(method, "auto") && Nat.is_le(Nat.add(input_tokens, reserve), window)), window, reserve}

# Base String.take builds a recursive result. These chunks can span hundreds of
# thousands of Unicode characters, so collect the prefix before reversing it.
def collect_chunk(value: String, count: Nat, reversed: String) -> String:
  match value count:
    case SNil{} _: String.reverse(reversed)
    case SCon{head, tail} 0n: String.reverse(reversed)
    case SCon{head, tail} 1n+left: collect_chunk(tail, left, SCon{head, reversed})

def chunk(+state: M.State) -> String:
  M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
  collect_chunk(readable, chunk_chars, "")

def end(+state: M.State) -> Nat:
  M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
  Nat.add(cursor, String.length(chunk(state)))

def call_fields(native: Bool, +state: M.State) -> +List<J.Field>:
  match native:
    case True{}:
      M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
      [J.Field{"history", source}]
    case False{}:
      M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
      [J.Field{"chunk", J.Text{chunk(state)}}, J.Field{"carry", J.Text{carry}}, J.Field{"prompt", J.Text{M.summary_prompt()}}]

def plan_json(+state: M.State) -> J.Json:
  M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
  J.Object{List.append(&2, J.Field, [J.Field{"method", J.Text{method_text(method)}},
    J.Field{"window_tokens", J.nat(window)}, J.Field{"output_reserve_tokens", J.nat(reserve)}],
    call_fields(is_native(method), state))}

def with_width(+state: M.State, width: Nat) -> M.State:
  M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
  M.State{source, readable, cursor, carry, width, method, window, reserve}

def shown_bytes(result: Result<&2, &2, String, String>, limit: Nat) -> Nat:
  match result:
    case Fail{message}: 1n+limit
    case Done{text}: J.utf8_length(text)

def plan_bytes(+state: M.State, limit: Nat) -> Nat:
  shown_bytes(J.show(plan_json(state)), limit)

def has_transport_work(state: M.State) -> Bool:
  M.State{source, readable, cursor, carry, width, method, window, reserve} = state
  is_native(method) || String.is_empty(readable) || Nat.is_lt(0n, width)

def transport_fits(+state: M.State, +budget: Nat) -> Bool:
  has_transport_work(state) && Nat.is_le(plan_bytes(state, budget), budget)

# A large note stays input data: move it in front of the unread source rather
# than truncate it or send a frame that cannot cross the kernel boundary.
def rebase_note(state: M.State) -> M.State:
  M.State{source, readable, cursor, carry, width, method, window, reserve} = state
  M.State{source, "Prior continuation note:\n" ++ carry ++ "\nUnread task history:\n" ++ readable,
    cursor, "", width, M.PortableSummary{}, window, reserve}

def fitted_width(+state: M.State, +budget: Nat) -> M.State:
  M.State{source, readable, cursor, carry, width, method, window, reserve} = state
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
    case False{}:
      M.State{source, readable, cursor, carry, width, method, window, reserve} = state
      fit_portable(M.State{source, readable, cursor, carry, width, M.PortableSummary{}, window, reserve}, budget)

def fit_transport_kind(method: M.Method, +state: M.State, +budget: Nat) -> M.State:
  match method:
    case M.NativeCompaction{}: native_transport_fits(transport_fits(state, budget), state, budget)
    case M.PortableSummary{}: fit_portable(state, budget)

def fit_transport(+state: M.State, budget: Nat) -> M.State:
  M.State{source, readable, cursor, carry, width, method, window, reserve} = state
  fit_transport_kind(method, state, budget)

def portable_candidate(+result: J.Json, summary: String) -> J.Json:
  J.Object{[J.Field{"format", J.Text{"portable"}}, J.Field{"scope", J.get(result, "scope")},
    J.Field{"items", J.Array{[J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Text{summary}}]}]}},
    J.Field{"usage", J.get(result, "usage")}]}

def summary_finished(finished: Bool, +state: M.State, +result: J.Json, +summary: String) -> M.Step:
  match finished:
    case True{}: M.Compacted{portable_candidate(result, summary)}
    case False{}:
      M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
      M.Next{M.State{source, String.drop(readable, chunk_chars), end(state), summary, chunk_chars, method, window, reserve}}

def state_readable(state: M.State) -> String:
  M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
  readable

def state_chunk_chars(state: M.State) -> Nat:
  M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
  chunk_chars

def summary_checked(valid: Bool, +state: M.State, +result: J.Json) -> M.Step:
  match valid:
    case False{}: M.Failed{"The compactor returned an empty continuation note"}
    case True{}: summary_finished(String.is_empty(String.drop(state_readable(state), state_chunk_chars(state))), state, result, J.text(J.get(result, "summary_text")))

def resize_checked(can_reduce: Bool, state: M.State) -> M.Step:
  match can_reduce:
    case True{}:
      M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
      M.Next{M.State{source, readable, cursor, carry, Nat.div(chunk_chars, 2n), M.PortableSummary{}, window, reserve}}
    case False{}: M.Failed{"Compaction request exceeds the configured model window"}

def resize(+state: M.State) -> M.Step:
  M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
  resize_checked(Nat.is_lt(1n, chunk_chars), state)

def native_finished(valid: Bool, result: J.Json) -> M.Step:
  match valid:
    case True{}: M.Compacted{result}
    case False{}: M.Failed{"The native compactor returned an invalid replacement window"}

def receive_method(method: M.Method, +state: M.State, +result: J.Json) -> M.Step:
  match method:
    case M.NativeCompaction{}: native_finished(String.eq(J.text(J.get(result, "format")), "native"), result)
    case M.PortableSummary{}: summary_checked(J.is_text(J.get(result, "summary_text")) && Bool.not(String.is_empty(J.text(J.get(result, "summary_text")))), state, result)

def native_unavailable(method: M.Method, state: M.State, result: J.Json) -> M.Step:
  match method:
    case M.NativeCompaction{}:
      M.State{source, readable, cursor, carry, width, previous_method, window, reserve} = state
      M.Next{M.State{source, readable, cursor, carry, width, M.PortableSummary{}, window, reserve}}
    case M.PortableSummary{}: receive_method(M.PortableSummary{}, state, result)

def receive_action(action: String, method: M.Method, state: M.State, result: J.Json) -> M.Step:
  match action:
    case "resize": resize(state)
    case "native_unavailable": native_unavailable(method, state, result)
    case _: receive_method(method, state, result)

def receive(+state: M.State, +result: J.Json) -> M.Step:
  M.State{source, readable, cursor, carry, chunk_chars, method, window, reserve} = state
  receive_action(J.text(J.get(result, "action")), method, state, result)
