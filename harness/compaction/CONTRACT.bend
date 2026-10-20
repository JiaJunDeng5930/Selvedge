import Base
import ../../bendlib/json.bend as J
import ./MODEL.bend as M
import ./PROGRAM.bend as P

law native_start_retains_raw_source:
  @+history:J.Json -> @+raw:J.Json -> @+input:Nat -> @+window:Nat -> @+reserve:Nat ->
  @without_images:{P.source_has_images(history, raw) == False{} : Bool} ->
  @fits:{Nat.is_le(Nat.add(input, reserve), window) == True{} : Bool} ->
  {P.start(history, raw, "chatgpt", "auto", input, window, reserve) ==
    M.State{M.NativeSource{history, raw}, 0n, "", window, window, reserve} : M.State}

law image_source_uses_portable_compaction:
  @+history:J.Json -> @+raw:J.Json -> @+provider:String -> @+method:String -> @+input:Nat -> @+window:Nat -> @+reserve:Nat ->
  @images:{P.source_has_images(history, raw) == True{} : Bool} ->
  {P.start(history, raw, provider, method, input, window, reserve) ==
    M.State{M.PortableSource{J.stringify(raw)}, 0n, "", window, window, reserve} : M.State}

law native_to_portable_preserves_source:
  @history:J.Json -> @+raw:J.Json -> @+cursor:Nat -> @+carry:String -> @+width:Nat -> @+window:Nat -> @+reserve:Nat ->
  {P.to_portable(M.State{M.NativeSource{history, raw}, cursor, carry, width, window, reserve}) ==
    M.State{M.PortableSource{J.stringify(raw)}, cursor, carry, width, window, reserve} : M.State}

law next_chunk_exact:
  @+readable:String -> @cursor:Nat -> @carry:String -> @+width:Nat -> @window:Nat -> @reserve:Nat ->
  {J.get(P.plan_json(M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}), "chunk") == J.Text{String.take(readable, width)} : J.Json}

law portable_plan_omits_full_source:
  @readable:String -> @cursor:Nat -> @carry:String -> @width:Nat -> @window:Nat -> @reserve:Nat ->
  {J.get(P.plan_json(M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}), "history") == J.Null{} : J.Json}

law native_plan_omits_readable_source:
  @history:J.Json -> @raw:J.Json -> @cursor:Nat -> @carry:String -> @width:Nat -> @window:Nat -> @reserve:Nat ->
  {J.get(P.plan_json(M.State{M.NativeSource{history, raw}, cursor, carry, width, window, reserve}), "chunk") == J.Null{} : J.Json}

law portable_replacement:
  @result:J.Json -> @+summary:String -> {J.get(P.portable_candidate(result, summary), "items") == J.Array{[J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Text{summary}}]}]} : J.Json}

law split_preserves_all_characters:
  @+value:String -> @+count:Nat -> {String.take(value, count) ++ String.drop(value, count) == value : String}

law unfinished_summary_keeps_unread_source:
  @+readable:String -> @+cursor:Nat -> @carry:String -> @+width:Nat -> @+window:Nat -> @+reserve:Nat -> @result:J.Json -> @+summary:String ->
  {P.summary_finished(False{}, M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}, result, summary) ==
    M.Next{M.State{M.PortableSource{String.drop(readable, width)}, Nat.add(cursor, String.length(String.take(readable, width))), summary, width, window, reserve}} : M.Step}

law completed_summary_requires_exhausted_source:
  @+readable:String -> @+cursor:Nat -> @+carry:String -> @+width:Nat -> @+window:Nat -> @+reserve:Nat -> @+result:J.Json ->
  {P.summary_checked(True{}, M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}, result) ==
    P.summary_finished(String.is_empty(String.drop(readable, width)), M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}, result, J.text(J.get(result, "summary_text"))) : M.Step}

law native_reply_cannot_finish_portable_work:
  @readable:String -> @cursor:Nat -> @carry:String -> @width:Nat -> @window:Nat -> @reserve:Nat -> @scope:String ->
  {P.receive(M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve},
    J.Object{[J.Field{"action", J.Text{"native"}}, J.Field{"format", J.Text{"native"}}, J.Field{"scope", J.Text{scope}}, J.Field{"items", J.Array{Nil{}}}]}) ==
    M.Failed{"The compactor returned an empty continuation note"} : M.Step}

law rebasing_keeps_the_complete_note_and_unread_history:
  @+readable:String -> @+cursor:Nat -> @+carry:String -> @+width:Nat -> @+window:Nat -> @+reserve:Nat ->
  {P.rebase_note(M.State{M.PortableSource{readable}, cursor, carry, width, window, reserve}) ==
    M.State{M.PortableSource{"Prior continuation note:\n" ++ carry ++ "\nUnread task history:\n" ++ readable},
      cursor, "", width, window, reserve} : M.State}

law an_unread_source_requires_a_nonempty_chunk:
  @head:Char -> @readable:String -> @cursor:Nat -> @carry:String -> @window:Nat -> @reserve:Nat -> @budget:Nat ->
  {P.transport_fits(M.State{M.PortableSource{SCon{head, readable}}, cursor, carry, 0n, window, reserve}, budget) == False{} : Bool}

law unavailable_native_method_preserves_all_rebuild_material:
  @history:J.Json -> @+raw:J.Json -> @+cursor:Nat -> @+carry:String -> @+width:Nat -> @+window:Nat -> @+reserve:Nat ->
  {P.receive(M.State{M.NativeSource{history, raw}, cursor, carry, width, window, reserve},
    J.Object{[J.Field{"action", J.Text{"native_unavailable"}}]}) ==
    M.Next{M.State{M.PortableSource{J.stringify(raw)}, cursor, carry, width, window, reserve}} : M.Step}
