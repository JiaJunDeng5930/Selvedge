import Base
import ../DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ./view.bend as View
import ./context.bend as Context

def admitted_bound(+accepted: Bool, +messages: +List<J.Json>, checked: {View.fits(messages) == accepted : Bool}) ->
  {View.fits(View.admitted(accepted, messages)) == True{} : Bool}:
  match accepted:
    case True{}: checked
    case False{}: {==}

def prioritized_bound(+accepted: Bool, +full: +List<J.Json>, +essential: +List<J.Json>, checked: {View.fits(full) == accepted : Bool}) ->
  {View.fits(View.prioritized(accepted, full, essential)) == True{} : Bool}:
  match accepted:
    case True{}: checked
    case False{}: admitted_bound(View.fits(essential), essential, {==})

def encoded_public_history_is_bounded(+history: D.History) ->
  {View.fits(View.history(history)) == True{} : Bool}:
  +public = Context.public_history(history, Nil{})
  +candidate: +List<J.Json> = View.marker() <> View.items(View.select(public, View.call_names(public, Nil{}), False{}))
  prioritized_bound(View.fits(candidate), candidate, View.marker() <> View.items(View.essential(public, False{})), {==})

def short_public_text_is_preserved(+text: String) ->
  {View.excerpt_checked(True{}, text) == text : String}:
  {==}

def recent_call_identity_is_unchanged(+message: J.Json, names: +List<String>) ->
  {View.call_names_step("function_call", message, names) == J.text(J.get(message, "call_id")) <> View.take_names(5n, names) : +List<String>}:
  {==}

def public_assistant_parts_remain_text(+text: String) ->
  {View.preview_message("assistant", J.Object{[J.Field{"content", J.Array{[J.Object{[J.Field{"text", J.Text{text}}]}]}}]}) ==
    J.Object{[J.Field{"role", J.Text{"assistant"}}, J.Field{"content", J.Text{View.excerpt(text)}}]} : J.Json}:
  {==}

def public_reasoning_keeps_its_category(+text: String) ->
  {View.preview_message("reasoning_summary", J.Object{[J.Field{"content", J.Array{[J.Object{[J.Field{"text", J.Text{text}}]}]}}]}) ==
    J.Object{[J.Field{"role", J.Text{"reasoning_summary"}}, J.Field{"content", J.Text{View.excerpt(text)}}]} : J.Json}:
  {==}
