import Base
import ../../bendlib/json.bend as J
import ./MODEL.bend as Model
import ./BACKENDS.bend as Backends
import ./ACCOUNTS.bend as Accounts
import ./WEB.bend as Web
import ./PLUGINS.bend as Plugins
import ./EFFECTS.bend as Effects
import ./BROWSER.bend as Browser
import ./RPC.bend as Rpc
import ./CONFIGURATION.bend as Configuration
import ./EVALUATOR.bend as Evaluator
import ./HTTP.bend as Http
import ./AUDIO.bend as Audio

def http_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Http.run(operation, source)
    case False{}: Model.failure("Unknown host model operation: " ++ operation)

def evaluator_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Evaluator.run(operation, source)
    case False{}: http_route(String.starts_with(operation, "http."), operation, source)

def config_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Configuration.run(operation, source)
    case False{}: evaluator_route(String.starts_with(operation, "evaluator."), operation, source)

def rpc_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Rpc.run(operation, source)
    case False{}: config_route(String.starts_with(operation, "config."), operation, source)

def browser_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Browser.run(operation, source)
    case False{}: rpc_route(String.starts_with(operation, "rpc."), operation, source)

def effect_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Effects.run(operation, source)
    case False{}: browser_route(String.starts_with(operation, "browser."), operation, source)

def plugin_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Plugins.run(operation, source)
    case False{}: effect_route(String.starts_with(operation, "effect."), operation, source)

def web_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Web.run(operation, source)
    case False{}: plugin_route(String.starts_with(operation, "plugin."), operation, source)

def account_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Accounts.run(operation, source)
    case False{}: web_route(String.starts_with(operation, "web."), operation, source)

def backend_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Backends.run(operation, source)
    case False{}: account_route(String.starts_with(operation, "account."), operation, source)

def audio_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Audio.run(operation, source)
    case False{}: backend_route(String.starts_with(operation, "backend."), operation, source)

def run(+operation: String, +source: J.Json) -> J.Json:
  audio_route(String.starts_with(operation, "audio."), operation, source)

def meaning_http_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Http.meaning(operation, source)
    case False{}: Model.failure("Unknown host model operation: " ++ operation)

def meaning_evaluator_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Evaluator.meaning(operation, source)
    case False{}: meaning_http_route(String.starts_with(operation, "http."), operation, source)

def meaning_config_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Configuration.meaning(operation, source)
    case False{}: meaning_evaluator_route(String.starts_with(operation, "evaluator."), operation, source)

def meaning_rpc_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Rpc.meaning(operation, source)
    case False{}: meaning_config_route(String.starts_with(operation, "config."), operation, source)

def meaning_browser_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Browser.meaning(operation, source)
    case False{}: meaning_rpc_route(String.starts_with(operation, "rpc."), operation, source)

def meaning_effect_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Effects.meaning(operation, source)
    case False{}: meaning_browser_route(String.starts_with(operation, "browser."), operation, source)

def meaning_plugin_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Plugins.meaning(operation, source)
    case False{}: meaning_effect_route(String.starts_with(operation, "effect."), operation, source)

def meaning_web_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Web.meaning(operation, source)
    case False{}: meaning_plugin_route(String.starts_with(operation, "plugin."), operation, source)

def meaning_account_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Accounts.meaning(operation, source)
    case False{}: meaning_web_route(String.starts_with(operation, "web."), operation, source)

def meaning_backend_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Backends.meaning(operation, source)
    case False{}: meaning_account_route(String.starts_with(operation, "account."), operation, source)

def meaning_audio_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Audio.meaning(operation, source)
    case False{}: meaning_backend_route(String.starts_with(operation, "backend."), operation, source)

def meaning(+operation: String, +source: J.Json) -> J.Json:
  meaning_audio_route(String.starts_with(operation, "audio."), operation, source)

law complete_correspondence:
  @operation:String -> @source:J.Json -> {run(operation, source) == meaning(operation, source) : J.Json}
