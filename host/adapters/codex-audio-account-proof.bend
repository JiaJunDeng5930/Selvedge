import Base
import ../../bendlib/json.bend as J
import ./MODEL.bend as Model
import ./CODEX_AUDIO_ACCOUNT.bend as Account

def production_correspondence(+operation: String, +source: J.Json) ->
  {Account.run(operation, source) == Account.meaning(operation, source) : J.Json}:
  {==}

def missing_account_has_no_capability() ->
  {Account.connections(J.Object{Nil{}}) == Model.success(J.Array{Nil{}}) : J.Json}:
  {==}

def api_key_has_no_capability() ->
  {Account.connections(J.Object{[J.Field{"account", J.Object{[J.Field{"type", J.Text{"apiKey"}}]}}]}) == Model.success(J.Array{Nil{}}) : J.Json}:
  {==}
