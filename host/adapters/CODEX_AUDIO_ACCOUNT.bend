import Base
import ../../bendlib/json.bend as J
import ./MODEL.bend as Model

def object(fields: +List<J.Field>) -> J.Json:
  J.Object{fields}
def nonempty(+value: J.Json) -> Bool:
  J.is_text(value) && Bool.not(String.is_empty(J.text(value)))
def admit(valid: Bool, value: J.Json, message: String) -> J.Json:
  match valid:
    case True{}: Model.success(value)
    case False{}: Model.failure_code("audio_account_unavailable", message)
def request(+method: String, params: J.Json) -> J.Json:
  object([J.Field{"method", J.Text{method}}, J.Field{"params", params}])

# The official component owns OAuth parameters, callbacks, token storage and refresh.
# No thread/start or turn/start operation belongs to this auth-only process plan.
def plan(+source: J.Json) -> J.Json:
  admit(nonempty(J.get(source, "command")), object([
    J.Field{"command", J.get(source, "command")},
    J.Field{"args", J.Array{[J.Text{"app-server"}, J.Text{"--listen"}, J.Text{"stdio://"}, J.Text{"-c"}, J.Text{"cli_auth_credentials_store=\"file\""}]}},
    J.Field{"home_name", J.Text{"codex-audio"}},
    J.Field{"frame_bytes", J.Number{"4194304"}}, J.Field{"tool_output_bytes", J.Number{"65536"}},
    J.Field{"timeout_ms", J.Number{"30000"}},
    J.Field{"initialize", request("initialize", object([J.Field{"clientInfo", object([J.Field{"name", J.Text{"selvedge_audio"}}, J.Field{"title", J.Text{"Selvedge"}}, J.Field{"version", J.Text{"0.1.0"}}])}]))},
    J.Field{"initialized", request("initialized", object(Nil{}))},
    J.Field{"account", request("account/read", object([J.Field{"refreshToken", J.Boolean{False{}}}]))},
    J.Field{"authorize", request("getAuthStatus", object([J.Field{"includeToken", J.Boolean{True{}}}, J.Field{"refreshToken", J.Boolean{False{}}}]))},
    J.Field{"refresh", request("getAuthStatus", object([J.Field{"includeToken", J.Boolean{True{}}}, J.Field{"refreshToken", J.Boolean{True{}}}]))},
    J.Field{"login", request("account/login/start", object([J.Field{"type", J.Text{"chatgpt"}}]))}
  ]), "Install the official Codex CLI or configure SELVEDGE_CODEX_BIN for ChatGPT voice sign-in")

def is_chatgpt(+source: J.Json) -> Bool:
  J.same(J.get(J.get(source, "account"), "type"), J.Text{"chatgpt"})
def connection() -> J.Json:
  object([J.Field{"id", J.Text{"chatgpt-voice"}}, J.Field{"label", J.Text{"ChatGPT"}}, J.Field{"source", J.Text{"codex_audio"}}, J.Field{"authorized", J.Boolean{True{}}}])
def connections_present(present: Bool) -> J.Json:
  match present:
    case True{}: Model.success(J.Array{[connection()]})
    case False{}: Model.success(J.Array{Nil{}})
def connections(+source: J.Json) -> J.Json:
  connections_present(is_chatgpt(source))
def connection_admission(+source: J.Json) -> J.Json:
  admit(J.same(J.get(source, "connection"), J.Text{"chatgpt-voice"}), J.Null{}, "Unknown ChatGPT audio connection")
def account_admission(+source: J.Json) -> J.Json:
  admit(is_chatgpt(source), J.Null{}, "Official Codex ChatGPT audio authorization is required; sign in for voice again")
def authorization(+source: J.Json) -> J.Json:
  admit(is_chatgpt(source) && J.same(J.get(source, "auth_method"), J.Text{"chatgpt"}) && J.boolean(J.get(source, "token_present")) && nonempty(J.get(source, "account_id")) &&
    (J.same(J.get(source, "expected_account_id"), J.Null{}) || J.same(J.get(source, "expected_account_id"), J.get(source, "account_id"))),
    object([J.Field{"account_id", J.get(source, "account_id")}]), "Official Codex ChatGPT audio authorization is required; sign in for voice again")

# URL parsing is the platform observation. Browser navigation and the local
# login response use this same authority rather than repeating a host allowlist.
def login_target_meaning(+source: J.Json) -> J.Json:
  admit(nonempty(J.get(source, "url")) && J.same(J.get(source, "protocol"), J.Text{"https:"}) &&
    J.same(J.get(source, "hostname"), J.Text{"auth.openai.com"}) && J.same(J.get(source, "pathname"), J.Text{"/oauth/authorize"}) &&
    J.same(J.get(source, "username"), J.Text{""}) && J.same(J.get(source, "password"), J.Text{""}) &&
    (J.same(J.get(source, "port"), J.Text{""}) || J.same(J.get(source, "port"), J.Text{"443"})),
    object([J.Field{"url", J.get(source, "url")}]), "Official Codex returned an invalid ChatGPT authorization URL")
def login_result(+source: J.Json) -> J.Json:
  admit(nonempty(J.get(source, "login_id")), object([J.Field{"url", J.get(source, "url")}, J.Field{"login_id", J.get(source, "login_id")}]), "Official Codex returned an invalid ChatGPT login identity")
def notification(+source: J.Json) -> J.Json:
  Model.success(J.Boolean{J.same(J.get(source, "method"), J.Text{"account/login/completed"}) || J.same(J.get(source, "method"), J.Text{"account/updated"})})

def has_field(fields: +List<J.Field>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{J.Field{key, value}, rest}: String.eq(key, name) || has_field(rest, name)
def rpc_fields(versioned: Bool, fields: +List<J.Field>) -> J.Json:
  match versioned:
    case True{}: Model.success(object(fields))
    case False{}: Model.success(object(Con{J.Field{"jsonrpc", J.Text{"2.0"}}, fields}))
# Official app-server's public stdio wire omits jsonrpc. Add only the absent
# protocol marker; StdioRpc still rejects a present unsupported version.
def rpc_value(+message: J.Json) -> J.Json:
  match message:
    case J.Object{+fields}: rpc_fields(has_field(fields, "jsonrpc"), fields)
    case _: Model.failure("Malformed official Codex auth RPC message")
def rpc_message(+source: J.Json) -> J.Json:
  rpc_value(J.get(source, "message"))

def meaning(+operation: String, +source: J.Json) -> J.Json:
  match operation:
    case "codex_audio_account.plan": plan(source)
    case "codex_audio_account.connections": connections(source)
    case "codex_audio_account.connection": connection_admission(source)
    case "codex_audio_account.account": account_admission(source)
    case "codex_audio_account.authorization": authorization(source)
    case "codex_audio_account.login_target": login_target_meaning(source)
    case "codex_audio_account.login_result": login_result(source)
    case "codex_audio_account.notification": notification(source)
    case "codex_audio_account.rpc_message": rpc_message(source)
    case _: Model.failure("Unknown Codex audio account operation")
def factory(+operation: String) -> Model.Adapter((source => meaning(operation, source))):
  Model.adapter((source => meaning(operation, source)), (source => meaning(operation, source)), source => {==})
def run(+operation: String, source: J.Json) -> J.Json:
  Model.execute((candidate => meaning(operation, candidate)), factory(operation), source)
