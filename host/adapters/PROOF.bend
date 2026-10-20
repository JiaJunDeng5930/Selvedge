import Base
import ../../bendlib/json.bend as J
import ./PROGRAM.bend as Program
import ./backends-proof.bend as BackendsProof
import ./compaction-proof.bend as CompactionProof
import ./accounts-proof.bend as AccountsProof
import ./web-proof.bend as WebProof
import ./plugins-proof.bend as PluginsProof
import ./effects-proof.bend as EffectsProof
import ./browser-proof.bend as BrowserProof
import ./rpc-proof.bend as RpcProof
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
import ./configuration-proof.bend as ConfigurationProof
import ./evaluator-proof.bend as EvaluatorProof
import ./http-proof.bend as HttpProof
import ./AUDIO.bend as Audio
import ./audio-proof.bend as AudioProof

def http_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.http_route(accepted, operation, source) == Program.meaning_http_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}:
      evidence = Http.complete_correspondence()
      evidence(operation, source)
    case False{}: {==}

def evaluator_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.evaluator_route(accepted, operation, source) == Program.meaning_evaluator_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}:
      evidence = Evaluator.complete_correspondence()
      evidence(operation, source)
    case False{}: http_route_correspondence(String.starts_with(operation, "http."), operation, source)

def config_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.config_route(accepted, operation, source) == Program.meaning_config_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}: ConfigurationProof.production_correspondence(operation, source)
    case False{}: evaluator_route_correspondence(String.starts_with(operation, "evaluator."), operation, source)

def rpc_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.rpc_route(accepted, operation, source) == Program.meaning_rpc_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}: {==}
    case False{}: config_route_correspondence(String.starts_with(operation, "config."), operation, source)

def browser_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.browser_route(accepted, operation, source) == Program.meaning_browser_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}:
      evidence = Browser.complete_correspondence()
      evidence(operation, source)
    case False{}: rpc_route_correspondence(String.starts_with(operation, "rpc."), operation, source)

def effect_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.effect_route(accepted, operation, source) == Program.meaning_effect_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}:
      evidence = Effects.complete_correspondence()
      evidence(operation, source)
    case False{}: browser_route_correspondence(String.starts_with(operation, "browser."), operation, source)

def plugin_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.plugin_route(accepted, operation, source) == Program.meaning_plugin_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}:
      evidence = Plugins.complete_correspondence()
      evidence(operation, source)
    case False{}: effect_route_correspondence(String.starts_with(operation, "effect."), operation, source)

def web_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.web_route(accepted, operation, source) == Program.meaning_web_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}:
      evidence = Web.complete_correspondence()
      evidence(operation, source)
    case False{}: plugin_route_correspondence(String.starts_with(operation, "plugin."), operation, source)

def account_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.account_route(accepted, operation, source) == Program.meaning_account_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}: AccountsProof.production_correspondence(operation, source)
    case False{}: web_route_correspondence(String.starts_with(operation, "web."), operation, source)

def backend_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.backend_route(accepted, operation, source) == Program.meaning_backend_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}:
      evidence = Backends.complete_correspondence()
      evidence(operation, source)
    case False{}: account_route_correspondence(String.starts_with(operation, "account."), operation, source)

def audio_route_correspondence(+accepted: Bool, +operation: String, +source: J.Json) ->
  {Program.audio_route(accepted, operation, source) == Program.meaning_audio_route(accepted, operation, source) : J.Json}:
  match accepted:
    case True{}: AudioProof.production_correspondence(operation, source)
    case False{}: backend_route_correspondence(String.starts_with(operation, "backend."), operation, source)

def complete_correspondence_at(+operation: String, +source: J.Json) ->
  {Program.run(operation, source) == Program.meaning(operation, source) : J.Json}:
  audio_route_correspondence(String.starts_with(operation, "audio."), operation, source)

def Program.complete_correspondence():
  operation => source => complete_correspondence_at(operation, source)
