import Base
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ./MODEL.bend as Spec
import ./PROGRAM.bend as Actual

def empty_source_has_no_open_calls(history: D.History) ->
  {Actual.settled_calls(D.EmptyHistory{}, history) == True{} : Bool}:
  {==}

def captured_call_requires_its_output(+history: D.History, +whole: D.History, +id: String, name: String, arguments: J.Json) ->
  {Actual.settled_calls(D.HistoryNode{history, D.FunctionCall{D.Call{id, name, arguments}}}, whole) ==
    (Actual.has_output(whole, id) && Actual.settled_calls(history, whole)) : Bool}:
  {==}

def unresolved_call_cannot_enter_source(+history: D.History, +whole: D.History, +id: String, name: String, arguments: J.Json,
  missing: {Actual.has_output(whole, id) == False{} : Bool}) ->
  {Actual.settled_calls(D.HistoryNode{history, D.FunctionCall{D.Call{id, name, arguments}}}, whole) == False{} : Bool}:
  Equal.cong(Bool, Bool, present => present && Actual.settled_calls(history, whole), Actual.has_output(whole, id), False{}, missing)

# A selected complete window replaces one captured prefix. In particular, no
# record retained inside that window is independently appended from the prefix.
def prefix_snapshot(+snapshot: +List<J.Json>, +tail: +List<J.Json>) ->
  {Actual.prefix(List.length(&2, J.Json, snapshot), List.append(&2, J.Json, snapshot, tail)) == snapshot : +List<J.Json>}:
  match snapshot:
    case Nil{}: {==}
    case Con{+item, +rest}:
      Equal.cong(+List<J.Json>, +List<J.Json>, remaining => item <> remaining,
        Actual.prefix(List.length(&2, J.Json, rest), List.append(&2, J.Json, rest, tail)), rest,
        prefix_snapshot(rest, tail))

def suffix_snapshot(+snapshot: +List<J.Json>, +tail: +List<J.Json>) ->
  {Actual.suffix(List.length(&2, J.Json, snapshot), List.append(&2, J.Json, snapshot, tail)) == tail : +List<J.Json>}:
  match snapshot:
    case Nil{}: {==}
    case Con{item, +rest}: suffix_snapshot(rest, tail)

def replacement_keeps_exact_suffix(+snapshot: +List<J.Json>, +tail: +List<J.Json>, +items: +List<J.Json>, +scope: String) ->
  {Actual.assemble(Spec.Replacement{List.length(&2, J.Json, snapshot), items}, List.append(&2, J.Json, snapshot, tail), scope) ==
    List.append(&2, J.Json, Actual.fixed(snapshot), List.append(&2, J.Json, Actual.dialogue(items), Actual.scoped_messages(tail, scope))) : +List<J.Json>}:
  Equal.trans(+List<J.Json>,
    Actual.assemble(Spec.Replacement{List.length(&2, J.Json, snapshot), items}, List.append(&2, J.Json, snapshot, tail), scope),
    List.append(&2, J.Json, Actual.fixed(snapshot), List.append(&2, J.Json, Actual.dialogue(items),
      Actual.scoped_messages(Actual.suffix(List.length(&2, J.Json, snapshot), List.append(&2, J.Json, snapshot, tail)), scope))),
    List.append(&2, J.Json, Actual.fixed(snapshot), List.append(&2, J.Json, Actual.dialogue(items), Actual.scoped_messages(tail, scope))),
    Equal.cong(+List<J.Json>, +List<J.Json>, first => List.append(&2, J.Json, Actual.fixed(first),
      List.append(&2, J.Json, Actual.dialogue(items), Actual.scoped_messages(Actual.suffix(List.length(&2, J.Json, snapshot), List.append(&2, J.Json, snapshot, tail)), scope))),
      Actual.prefix(List.length(&2, J.Json, snapshot), List.append(&2, J.Json, snapshot, tail)), snapshot, prefix_snapshot(snapshot, tail)),
    Equal.cong(+List<J.Json>, +List<J.Json>, last => List.append(&2, J.Json, Actual.fixed(snapshot),
      List.append(&2, J.Json, Actual.dialogue(items), Actual.scoped_messages(last, scope))),
      Actual.suffix(List.length(&2, J.Json, snapshot), List.append(&2, J.Json, snapshot, tail)), tail, suffix_snapshot(snapshot, tail)))

def selected_request_keeps_exact_suffix(+snapshot: +List<J.Json>, +tail: +List<J.Json>, +items: +List<J.Json>, +scope: String,
  selected: {Actual.latest(List.append(&2, J.Json, snapshot, tail), scope, 0n, Spec.Original{}) ==
    Spec.Replacement{List.length(&2, J.Json, snapshot), items} : Spec.Selection}) ->
  {Actual.target_messages(List.append(&2, J.Json, snapshot, tail), scope) ==
    List.append(&2, J.Json, Actual.fixed(snapshot), List.append(&2, J.Json, Actual.dialogue(items), Actual.scoped_messages(tail, scope))) : +List<J.Json>}:
  Equal.trans(+List<J.Json>, Actual.target_messages(List.append(&2, J.Json, snapshot, tail), scope),
    Actual.assemble(Spec.Replacement{List.length(&2, J.Json, snapshot), items}, List.append(&2, J.Json, snapshot, tail), scope),
    List.append(&2, J.Json, Actual.fixed(snapshot), List.append(&2, J.Json, Actual.dialogue(items), Actual.scoped_messages(tail, scope))),
    Equal.cong(Spec.Selection, +List<J.Json>, selection => Actual.assemble(selection, List.append(&2, J.Json, snapshot, tail), scope),
      Actual.latest(List.append(&2, J.Json, snapshot, tail), scope, 0n, Spec.Original{}), Spec.Replacement{List.length(&2, J.Json, snapshot), items}, selected),
    replacement_keeps_exact_suffix(snapshot, tail, items, scope))

def portable_replacement_keeps_exact_suffix(+snapshot: +List<J.Json>, +tail: +List<J.Json>, +items: +List<J.Json>) ->
  {Actual.portable_assemble(Spec.Replacement{List.length(&2, J.Json, snapshot), items}, List.append(&2, J.Json, snapshot, tail)) ==
    List.append(&2, J.Json, Actual.fixed(snapshot), List.append(&2, J.Json, Actual.dialogue(items), Actual.retained_messages(tail))) : +List<J.Json>}:
  Equal.trans(+List<J.Json>,
    Actual.portable_assemble(Spec.Replacement{List.length(&2, J.Json, snapshot), items}, List.append(&2, J.Json, snapshot, tail)),
    List.append(&2, J.Json, Actual.fixed(snapshot), List.append(&2, J.Json, Actual.dialogue(items),
      Actual.retained_messages(Actual.suffix(List.length(&2, J.Json, snapshot), List.append(&2, J.Json, snapshot, tail))))),
    List.append(&2, J.Json, Actual.fixed(snapshot), List.append(&2, J.Json, Actual.dialogue(items), Actual.retained_messages(tail))),
    Equal.cong(+List<J.Json>, +List<J.Json>, first => List.append(&2, J.Json, Actual.fixed(first),
      List.append(&2, J.Json, Actual.dialogue(items), Actual.retained_messages(Actual.suffix(List.length(&2, J.Json, snapshot), List.append(&2, J.Json, snapshot, tail))))),
      Actual.prefix(List.length(&2, J.Json, snapshot), List.append(&2, J.Json, snapshot, tail)), snapshot, prefix_snapshot(snapshot, tail)),
    Equal.cong(+List<J.Json>, +List<J.Json>, last => List.append(&2, J.Json, Actual.fixed(snapshot),
      List.append(&2, J.Json, Actual.dialogue(items), Actual.retained_messages(last))),
      Actual.suffix(List.length(&2, J.Json, snapshot), List.append(&2, J.Json, snapshot, tail)), tail, suffix_snapshot(snapshot, tail)))

def unmeasured_tail_keeps_native_receipt(+value: J.Json, +tail: +List<J.Json>) ->
  {Actual.retained_messages(J.Object{[J.Field{"role", J.Text{"model_context"}}, J.Field{"content", value}]} <> tail) ==
    J.Object{[J.Field{"role", J.Text{"model_context"}}, J.Field{"content", value}]} <> Actual.retained_messages(tail) : +List<J.Json>}:
  {==}

def selected_portable_request_keeps_exact_suffix(+snapshot: +List<J.Json>, +tail: +List<J.Json>, +items: +List<J.Json>,
  selected: {Actual.latest(List.append(&2, J.Json, snapshot, tail), "", 0n, Spec.Original{}) ==
    Spec.Replacement{List.length(&2, J.Json, snapshot), items} : Spec.Selection}) ->
  {Actual.portable_messages(List.append(&2, J.Json, snapshot, tail)) ==
    List.append(&2, J.Json, Actual.fixed(snapshot), List.append(&2, J.Json, Actual.dialogue(items), Actual.retained_messages(tail))) : +List<J.Json>}:
  Equal.trans(+List<J.Json>, Actual.portable_messages(List.append(&2, J.Json, snapshot, tail)),
    Actual.portable_assemble(Spec.Replacement{List.length(&2, J.Json, snapshot), items}, List.append(&2, J.Json, snapshot, tail)),
    List.append(&2, J.Json, Actual.fixed(snapshot), List.append(&2, J.Json, Actual.dialogue(items), Actual.retained_messages(tail))),
    Equal.cong(Spec.Selection, +List<J.Json>, selection => Actual.portable_assemble(selection, List.append(&2, J.Json, snapshot, tail)),
      Actual.latest(List.append(&2, J.Json, snapshot, tail), "", 0n, Spec.Original{}), Spec.Replacement{List.length(&2, J.Json, snapshot), items}, selected),
    portable_replacement_keeps_exact_suffix(snapshot, tail, items))

def raw_history_composes(+first: +List<J.Json>, +second: +List<J.Json>) ->
  {Actual.raw_messages(List.append(&2, J.Json, first, second)) ==
    List.append(&2, J.Json, Actual.raw_messages(first), Actual.raw_messages(second)) : +List<J.Json>}:
  match first:
    case Nil{}: {==}
    case Con{+message, +rest}:
      Equal.trans(+List<J.Json>, Actual.raw_messages(List.append(&2, J.Json, message <> rest, second)),
        List.append(&2, J.Json, Actual.readable_message(message), List.append(&2, J.Json, Actual.raw_messages(rest), Actual.raw_messages(second))),
        List.append(&2, J.Json, Actual.raw_messages(message <> rest), Actual.raw_messages(second)),
        Equal.cong(+List<J.Json>, +List<J.Json>, tail => List.append(&2, J.Json, Actual.readable_message(message), tail),
          Actual.raw_messages(List.append(&2, J.Json, rest, second)), List.append(&2, J.Json, Actual.raw_messages(rest), Actual.raw_messages(second)), raw_history_composes(rest, second)),
        Std.app_assoc(J.Json, Actual.readable_message(message), Actual.raw_messages(rest), Actual.raw_messages(second)))

def raw_user_is_retained(+text: String, +tail: +List<J.Json>) ->
  {Actual.raw_messages(J.Object{[J.Field{"role", J.Text{"user"}}, J.Field{"content", J.Text{text}}]} <> tail) ==
    J.Object{[J.Field{"role", J.Text{"user"}}, J.Field{"content", J.Text{text}}]} <> Actual.raw_messages(tail) : +List<J.Json>}:
  {==}

def raw_replacement_is_not_a_source(+value: J.Json, +tail: +List<J.Json>) ->
  {Actual.raw_messages(J.Object{[J.Field{"role", J.Text{"context_replacement"}}, J.Field{"content", value}]} <> tail) == Actual.raw_messages(tail) : +List<J.Json>}:
  {==}

def rejected_result_preserves_history(snapshot: D.History, candidate: J.Json, +current: D.History) ->
  {Actual.commit(False{}, snapshot, candidate, current) == current : D.History}:
  {==}

def accepted_result_preserves_history(+snapshot: D.History, +candidate: J.Json, +current: D.History) ->
  {Actual.commit(True{}, snapshot, candidate, current) ==
    D.HistoryNode{current, Spec.record(D.history_length(snapshot), candidate)} : D.History}:
  {==}

def adopted_result_preserves_history(+snapshot: D.History, +candidate: J.Json, +current: D.History,
  accepted: {Actual.adoptable(snapshot, candidate, current) == True{} : Bool}) ->
  {Actual.adopt(snapshot, candidate, current) == D.HistoryNode{current, Spec.record(D.history_length(snapshot), candidate)} : D.History}:
  Equal.cong(Bool, D.History, allowed => Actual.commit(allowed, snapshot, candidate, current),
    Actual.adoptable(snapshot, candidate, current), True{}, accepted)

def and_false(+value: Bool) -> {value && False{} == False{} : Bool}:
  match value:
    case True{}: {==}
    case False{}: {==}

def native_scope_is_checked(+scope: String, +other: String,
  different: {String.eq(scope, other) == False{} : Bool}) ->
  {Spec.consumes("native", scope, other) == False{} : Bool}:
  Equal.trans(Bool, Spec.consumes("native", scope, other), Bool.not(String.eq(scope, "")) && False{}, False{},
    Equal.cong(Bool, Bool, same => Bool.not(String.eq(scope, "")) && same, String.eq(scope, other), False{}, different),
    and_false(Bool.not(String.eq(scope, ""))))

def portable_scope_is_independent(producer: String, target: String) ->
  {Spec.consumes("portable", producer, target) == True{} : Bool}:
  {==}

def incompatible_replacement_keeps_selection(+message: J.Json, +position: Nat, +scope: String, +previous: Spec.Selection,
  incompatible: {Spec.compatible(J.get(message, "content"), scope) == False{} : Bool}) ->
  {Spec.event_kind("context_replacement", message, position, scope, previous) == previous : Spec.Selection}:
  Equal.cong(Bool, Spec.Selection, compatible => Spec.selected(compatible && Spec.source_valid(J.get(message, "content"), position), J.get(message, "content"), previous),
    Spec.compatible(J.get(message, "content"), scope), False{}, incompatible)

def actual_scan_skips_incompatible_replacement(+message: J.Json, +tail: +List<J.Json>, +position: Nat, +scope: String, +previous: Spec.Selection,
  role: {J.text(J.get(message, "role")) == "context_replacement" : String},
  incompatible: {Spec.compatible(J.get(message, "content"), scope) == False{} : Bool}) ->
  {Actual.latest(message <> tail, scope, position, previous) == Actual.latest(tail, scope, 1n+position, previous) : Spec.Selection}:
  Equal.trans(Spec.Selection, Actual.latest(message <> tail, scope, position, previous),
    Actual.latest(tail, scope, 1n+position, Spec.event_kind("context_replacement", message, position, scope, previous)),
    Actual.latest(tail, scope, 1n+position, previous),
    Equal.cong(String, Spec.Selection, kind => Actual.latest(tail, scope, 1n+position, Spec.event_kind(kind, message, position, scope, previous)),
      J.text(J.get(message, "role")), "context_replacement", role),
    Equal.cong(Spec.Selection, Spec.Selection, selected => Actual.latest(tail, scope, 1n+position, selected),
      Spec.event_kind("context_replacement", message, position, scope, previous), previous,
      incompatible_replacement_keeps_selection(message, position, scope, previous, incompatible)))
