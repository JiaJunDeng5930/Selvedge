import Base
import ../../bendlib/json.bend as J
import ./MODEL.bend as M
import ./PROGRAM.bend as P

law next_chunk_exact:
  @source:J.Json -> @readable:String -> @cursor:Nat -> @carry:String -> @width:Nat -> @window:Nat -> @reserve:Nat ->
  {J.get(P.plan_json(M.State{source, readable, cursor, carry, width, M.PortableSummary{}, window, reserve}), "chunk") == J.Text{String.take(readable, width)} : J.Json}

law portable_plan_omits_full_source:
  @source:J.Json -> @readable:String -> @cursor:Nat -> @carry:String -> @width:Nat -> @window:Nat -> @reserve:Nat ->
  {J.get(P.plan_json(M.State{source, readable, cursor, carry, width, M.PortableSummary{}, window, reserve}), "history") == J.Null{} : J.Json}

law native_plan_omits_readable_source:
  @source:J.Json -> @readable:String -> @cursor:Nat -> @carry:String -> @width:Nat -> @window:Nat -> @reserve:Nat ->
  {J.get(P.plan_json(M.State{source, readable, cursor, carry, width, M.NativeCompaction{}, window, reserve}), "chunk") == J.Null{} : J.Json}

law portable_replacement:
  @result:J.Json -> @summary:String -> {J.get(P.portable_candidate(result, summary), "items") == J.Array{[J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Text{summary}}]}]} : J.Json}

law split_preserves_all_characters:
  @value:String -> @count:Nat -> {String.take(value, count) ++ String.drop(value, count) == value : String}

law unfinished_summary_keeps_unread_source:
  @source:J.Json -> @readable:String -> @cursor:Nat -> @carry:String -> @width:Nat -> @window:Nat -> @reserve:Nat -> @result:J.Json -> @summary:String ->
  {P.summary_finished(False{}, M.State{source, readable, cursor, carry, width, M.PortableSummary{}, window, reserve}, result, summary) ==
    M.Next{M.State{source, String.drop(readable, width), Nat.add(cursor, String.length(String.take(readable, width))), summary, width, M.PortableSummary{}, window, reserve}} : M.Step}

law completed_summary_requires_exhausted_source:
  @source:J.Json -> @readable:String -> @cursor:Nat -> @carry:String -> @width:Nat -> @window:Nat -> @reserve:Nat -> @result:J.Json ->
  {P.summary_checked(True{}, M.State{source, readable, cursor, carry, width, M.PortableSummary{}, window, reserve}, result) ==
    P.summary_finished(String.is_empty(String.drop(readable, width)), M.State{source, readable, cursor, carry, width, M.PortableSummary{}, window, reserve}, result, J.text(J.get(result, "summary_text"))) : M.Step}

law native_reply_cannot_finish_portable_work:
  @source:J.Json -> @readable:String -> @cursor:Nat -> @carry:String -> @width:Nat -> @window:Nat -> @reserve:Nat -> @scope:String ->
  {P.receive(M.State{source, readable, cursor, carry, width, M.PortableSummary{}, window, reserve},
    J.Object{[J.Field{"action", J.Text{"native"}}, J.Field{"format", J.Text{"native"}}, J.Field{"scope", J.Text{scope}}, J.Field{"items", J.Array{Nil{}}}]}) ==
    M.Failed{"The compactor returned an empty continuation note"} : M.Step}

law rebasing_keeps_the_complete_note_and_unread_history:
  @source:J.Json -> @readable:String -> @cursor:Nat -> @carry:String -> @width:Nat -> @method:M.Method -> @window:Nat -> @reserve:Nat ->
  {P.rebase_note(M.State{source, readable, cursor, carry, width, method, window, reserve}) ==
    M.State{source, "Prior continuation note:\n" ++ carry ++ "\nUnread task history:\n" ++ readable,
      cursor, "", width, M.PortableSummary{}, window, reserve} : M.State}

law an_unread_source_requires_a_nonempty_chunk:
  @source:J.Json -> @head:Char -> @readable:String -> @cursor:Nat -> @carry:String -> @window:Nat -> @reserve:Nat -> @budget:Nat ->
  {P.transport_fits(M.State{source, SCon{head, readable}, cursor, carry, 0n, M.PortableSummary{}, window, reserve}, budget) == False{} : Bool}

law unavailable_native_method_preserves_all_rebuild_material:
  @source:J.Json -> @readable:String -> @cursor:Nat -> @carry:String -> @width:Nat -> @window:Nat -> @reserve:Nat ->
  {P.receive(M.State{source, readable, cursor, carry, width, M.NativeCompaction{}, window, reserve},
    J.Object{[J.Field{"action", J.Text{"native_unavailable"}}]}) ==
    M.Next{M.State{source, readable, cursor, carry, width, M.PortableSummary{}, window, reserve}} : M.Step}
