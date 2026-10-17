import Base
import ../../bendlib/json.bend as J
import ./MODEL.bend as M
import ./PROGRAM.bend as P
import ./CONTRACT.bend as Rule

def Rule.native_start_retains_raw_source():
  +history => +raw => +input => +window => +reserve => fits =>
    Equal.cong(Bool, M.State,
      native => P.start_choice(native, M.State{M.NativeSource{history, raw}, 0n, "", window, window, reserve}),
      Nat.is_le(Nat.add(input, reserve), window), True{}, fits)

def Rule.native_to_portable_preserves_source():
  history => raw => cursor => carry => width => window => reserve => {==}

def collected_chunk_refines(+value: String, +count: Nat, +reversed: String) ->
  {P.collect_chunk(value, count, reversed) == String.reverse.go(reversed, String.take(value, count)) : String}:
  match value count:
    case SNil{} _: {==}
    case SCon{head, tail} 0n: {==}
    case SCon{+head, +tail} 1n+left: collected_chunk_refines(tail, left, SCon{head, reversed})

def Rule.next_chunk_exact():
  readable => cursor => carry => width => window => reserve =>
    Equal.cong(String, J.Json, (text => J.Text{text}), P.collect_chunk(readable, width, ""), String.take(readable, width),
      collected_chunk_refines(readable, width, ""))

def Rule.portable_plan_omits_full_source():
  readable => cursor => carry => width => window => reserve => {==}

def Rule.native_plan_omits_readable_source():
  history => raw => cursor => carry => width => window => reserve => {==}

def Rule.portable_replacement():
  result => summary => {==}

def split_evidence(+value: String, +count: Nat) -> {String.take(value, count) ++ String.drop(value, count) == value : String}:
  match value count:
    case SNil{} _: {==}
    case SCon{head, tail} 0n: {==}
    case SCon{+head, +tail} 1n+left:
      Equal.cong(String, String, (rest => SCon{head, rest}), String.take(tail, left) ++ String.drop(tail, left), tail, split_evidence(tail, left))

def Rule.split_preserves_all_characters():
  value => count => split_evidence(value, count)

def Rule.unfinished_summary_keeps_unread_source():
  readable => cursor => carry => width => window => reserve => result => summary =>
    Equal.cong(String, M.Step,
      (text => M.Next{M.State{M.PortableSource{String.drop(readable, width)}, Nat.add(cursor, String.length(text)), summary, width, window, reserve}}),
      P.collect_chunk(readable, width, ""), String.take(readable, width), collected_chunk_refines(readable, width, ""))

def Rule.completed_summary_requires_exhausted_source():
  readable => cursor => carry => width => window => reserve => result => {==}

def Rule.native_reply_cannot_finish_portable_work():
  readable => cursor => carry => width => window => reserve => scope => {==}

def Rule.rebasing_keeps_the_complete_note_and_unread_history():
  readable => cursor => carry => width => window => reserve => {==}

def Rule.an_unread_source_requires_a_nonempty_chunk():
  head => readable => cursor => carry => window => reserve => budget => {==}

def Rule.unavailable_native_method_preserves_all_rebuild_material():
  history => raw => cursor => carry => width => window => reserve => {==}
