import Base
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ./MODEL.bend as Model

def flag(+source: J.Json, name: String) -> Bool:
  J.boolean(J.get(source, name))

def header(+source: J.Json, name: String) -> J.Json:
  J.get(J.get(source, "headers"), name)

def nonempty(value: J.Json) -> Bool:
  match value:
    case J.Null{}: False{}
    case J.Text{text}: Bool.not(String.eq(text, ""))
    case _: True{}

def starts(text: String, prefix: String) -> Bool:
  match text prefix:
    case _ SNil{}: True{}
    case SCon{Chr{a}, rest} SCon{Chr{b}, tail}: U32.is_eq(a, b) && starts(rest, tail)
    case _ _: False{}

def action(name: String) -> J.Json:
  J.Object{[J.Field{"action", J.Text{name}}]}

def rejection(status: String, code: String, message: String) -> J.Json:
  J.Object{[J.Field{"action", J.Text{"respond"}}, J.Field{"status", J.Number{status}},
    J.Field{"value", J.Object{[J.Field{"ok", J.Boolean{False{}}},
      J.Field{"error", J.Object{[J.Field{"code", J.Text{code}}, J.Field{"message", J.Text{message}}]}}]}}]}

def exception(kind: String, message: String) -> J.Json:
  J.Object{[J.Field{"action", J.Text{"throw"}}, J.Field{"kind", J.Text{kind}}, J.Field{"message", J.Text{message}}]}

def closing_plan(closing: Bool) -> J.Json:
  match closing:
    case True{}: rejection("503", "stopping", "Server is stopping")
    case False{}: action("observe_host")

def host_value_valid(value: J.Json) -> Bool:
  match value:
    case J.Text{text}: Bool.not(String.eq(text, ""))
    case _: False{}

def host_valid(+source: J.Json) -> Bool:
  flag(source, "address_present") && host_value_valid(J.get(source, "expected_host")) && J.same(header(source, "host"), J.get(source, "expected_host"))

def host_plan(valid: Bool) -> J.Json:
  match valid:
    case False{}: rejection("400", "host", "Invalid local host")
    case True{}: action("parse_url")

def classify_connection(connection: Bool) -> J.Json:
  match connection:
    case True{}: action("observe_connection_authorization")
    case False{}: action("observe_local_authorization")

def open_valid(+source: J.Json) -> Bool:
  J.same(J.get(source, "closing"), J.Boolean{False{}})

def Open(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => open_valid(candidate)), candidate)

def Host(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => host_valid(candidate)), candidate)

def OpenHost(source: J.Json) -> Type:
  Categories.intersection(J.Json, Open, Host, source)

def asset_valid(+source: J.Json) -> Bool:
  String.eq(J.text(J.get(source, "method")), "GET") && flag(source, "asset")

def RegisteredAsset(source: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => asset_valid(candidate)), source)

def AssetRequest(source: J.Json) -> Type:
  Categories.intersection(J.Json, OpenHost, RegisteredAsset, source)

def asset_terminal(member: Categories.Membership<J.Json, AssetRequest>) -> J.Json:
  +source = Categories.value(J.Json, AssetRequest, member)
  action("asset")

def unknown_route() -> J.Json:
  rejection("404", "not_found", "Unknown local endpoint")

def asset_checked(+source: J.Json, prior: OpenHost(source), valid: Bool,
  observed: {asset_valid(source) == valid : Bool}) -> J.Json:
  match valid:
    case True{}: asset_terminal(Categories.Membership{source, Categories.Intersection{prior, observed}})
    case False{}: unknown_route()

def asset_admitted(member: Maybe<&1, Categories.Membership<J.Json, OpenHost>>) -> J.Json:
  match member:
    case None{}: host_plan(False{})
    case Some{Categories.Membership{+source, prior}}: asset_checked(source, prior, asset_valid(source), {==})

def admitted_plan(-predicate: J.Json -> Bool, member: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, predicate)>>,
  reject: J.Json, accept: J.Json -> J.Json) -> J.Json:
  match member:
    case None{}: reject
    case Some{member}: accept(Categories.value(J.Json, Categories.holds(J.Json, predicate), member))

def admit_plan(predicate: J.Json -> Bool, +source: J.Json, reject: J.Json, accept: J.Json -> J.Json) -> J.Json:
  admitted_plan(predicate, Categories.admit(J.Json, (candidate => predicate(candidate)), source), reject, accept)

def open_host_guard(+source: J.Json, accept: J.Json -> J.Json) -> J.Json:
  admit_plan((candidate => open_valid(candidate)), source, closing_plan(True{}), candidate =>
    admit_plan((candidate => host_valid(candidate)), candidate, host_plan(False{}), accept))

def asset_admission(+source: J.Json) -> J.Json:
  open_host_guard(source, candidate => asset_admitted(Categories.admit_intersection(J.Json,
    (candidate => open_valid(candidate)), (candidate => host_valid(candidate)), candidate)))

def classify_asset(asset: Bool, +source: J.Json) -> J.Json:
  match asset:
    case True{}: asset_admission(source)
    case False{}: classify_connection(starts(J.text(J.get(source, "pathname")), "/api/chatgpt/"))

def classify_calculation(+source: J.Json) -> J.Json:
  classify_asset(String.eq(J.text(J.get(source, "method")), "GET") && flag(source, "asset"), source)

def local_origin_valid(+source: J.Json) -> Bool:
  Bool.not(nonempty(header(source, "origin"))) || J.same(header(source, "origin"), J.get(source, "address"))

def connection_origin_valid(+source: J.Json) -> Bool:
  Bool.not(nonempty(header(source, "origin"))) && J.same(J.get(source, "search"), J.Text{""})

def connection_method_valid(+source: J.Json) -> Bool:
  String.eq(J.text(J.get(source, "method")), "POST")

def authorization_plan(accepted: Bool, connection: Bool) -> J.Json:
  match accepted connection:
    case True{} True{}: action("connection_method_origin")
    case True{} False{}: action("local_origin")
    case False{} True{}: rejection("401", "unauthorized", "A connection credential is required")
    case False{} False{}: rejection("401", "unauthorized", "A local access token is required")

def content_target(target: String) -> J.Json:
  J.Object{[J.Field{"action", J.Text{"observe_content_type"}}, J.Field{"target", J.Text{target}}]}

def connection_origin_plan(accepted: Bool) -> J.Json:
  match accepted:
    case False{}: rejection("403", "origin", "Browser origins and query parameters are not accepted")
    case True{}: content_target("connection_command")

def path_method(+source: J.Json, method: String, pathname: String) -> Bool:
  String.eq(J.text(J.get(source, "method")), method) && String.eq(J.text(J.get(source, "pathname")), pathname)

def attachment_query_shape(query: J.Json) -> Bool:
  match query:
    case J.Array{Con{J.Array{Con{J.Text{name}, Con{J.Text{value}, Nil{}}}}, Nil{}}}: String.eq(name, "name")
    case _: False{}

def attachment_query_valid(+source: J.Json) -> Bool:
  attachment_query_shape(J.get(source, "query"))

def trim_zero(+text: String) -> String:
  match text:
    case SCon{Chr{48}, rest}: trim_zero(rest)
    case _: text

def attachment_length_shape(length: J.Json) -> Bool:
  match length:
    case J.Null{}: True{}
    case J.Text{+text}: Bool.not(String.eq(text, "")) && Model.decimal_digits(text) && Model.decimal_le(trim_zero(text), "10485760")
    case _: False{}

def attachment_length_valid(+source: J.Json) -> Bool:
  attachment_length_shape(header(source, "content-length"))

def content_type_valid(+source: J.Json) -> Bool:
  starts(J.text(J.get(source, "content_type")), "application/json")

def empty_body(body: J.Json) -> Bool:
  match body:
    case J.Object{Nil{}}: True{}
    case _: False{}

def command_body(body: J.Json) -> Bool:
  match body:
    case J.Object{Con{J.Field{name, value}, Nil{}}}: String.eq(name, "command")
    case _: False{}

# NOTE: Both observations are supplied by the host. The native boundary binds
# the parser-output tokens to the original text; it does not prove JSON.parse.
def body_observation_result(result: Result<&2, &2, String, J.Json>) -> Bool:
  match result:
    case Done{body}: True{}
    case Fail{error}: False{}

def parsed_source(+source: J.Json) -> J.Json:
  J.Object{[J.Field{"text", J.get(source, "text")}, J.Field{"observation", J.get(source, "parsed_observation")}]}

def parsed_body_result(result: Result<&2, &2, String, J.Json>) -> J.Json:
  match result:
    case Done{body}: body
    case Fail{error}: J.Null{}

def parsed_body(+source: J.Json) -> J.Json:
  parsed_body_result(Model.parsed_observation(parsed_source(source)))

def body_text_observed(text: J.Json) -> Bool:
  match text:
    case J.Text{text}: True{}
    case _: False{}

def body_observation_valid(+source: J.Json) -> Bool:
  body_text_observed(J.get(source, "text")) && body_observation_result(Model.parsed_observation(source)) && body_observation_result(Model.parsed_observation(parsed_source(source)))

def body_shape_command(command: Bool, body: J.Json) -> Bool:
  match command:
    case True{}: command_body(body)
    case False{}: True{}

def body_shape_refresh(refresh: Bool, target: String, body: J.Json) -> Bool:
  match refresh:
    case True{}: empty_body(body)
    case False{}: body_shape_command(String.eq(target, "browser_command"), body)

def body_shape(+target: String, body: J.Json) -> Bool:
  body_shape_refresh(String.eq(target, "account_refresh"), target, body)

def connection_path(+source: J.Json) -> Bool:
  starts(J.text(J.get(source, "pathname")), "/api/chatgpt/")

def body_target_4(connection: Bool) -> String:
  match connection:
    case True{}: "connection_command"
    case False{}: ""

def body_target_3(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: "command"
    case False{}: body_target_4(connection_path(source) && connection_method_valid(source))

def body_target_2(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: "browser_observation"
    case False{}: body_target_3(path_method(source, "POST", "/api/commands"), source)

def body_target_1(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: "browser_command"
    case False{}: body_target_2(path_method(source, "POST", "/api/browser/observation"), source)

def body_target_0(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: "account_refresh"
    case False{}: body_target_1(path_method(source, "POST", "/api/browser/command"), source)

def body_target(+source: J.Json) -> String:
  body_target_0(path_method(source, "POST", "/api/accounts/refresh"), source)

def body_valid(+source: J.Json) -> Bool:
  body_observation_valid(source) && body_shape(body_target(source), parsed_body(source))

def body_error(refresh: Bool) -> J.Json:
  match refresh:
    case True{}: exception("TypeError", "Account refresh takes an empty object")
    case False{}: exception("TypeError", "A browser command contains only command")

def reply_status_plan(ok: Bool) -> J.Json:
  match ok:
    case True{}: J.Number{"200"}
    case False{}: J.Number{"400"}

def credential_observed(+source: J.Json, authorization_present: Bool) -> Bool:
  match authorization_present:
    case True{}: String.eq(J.text(J.get(J.get(source, "authorization"), "type")), "string")
    case False{}: Bool.not(connection_path(source)) && flag(J.get(source, "cookie"), "present") &&
      String.eq(J.text(J.get(J.get(source, "cookie"), "type")), "string")

def authorization_valid(+source: J.Json) -> Bool:
  flag(source, "authorized") && credential_observed(source, flag(J.get(source, "authorization"), "present"))

def body_route_valid(+source: J.Json) -> Bool:
  Bool.not(String.eq(body_target(source), "")) && String.eq(J.text(J.get(source, "target")), body_target(source))

def Authorization(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => authorization_valid(candidate)), candidate)

def LocalPath(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => Bool.not(connection_path(candidate))), candidate)

def ConnectionPath(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => connection_path(candidate)), candidate)

def LocalOrigin(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => local_origin_valid(candidate)), candidate)

def ConnectionMethod(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => connection_method_valid(candidate)), candidate)

def ConnectionOrigin(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => connection_origin_valid(candidate)), candidate)

def ContentType(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => content_type_valid(candidate)), candidate)

def UploadQuery(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => attachment_query_valid(candidate)), candidate)

def UploadSize(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => attachment_length_valid(candidate)), candidate)

def UploadRoute(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => path_method(candidate, "POST", "/api/board/attachments")), candidate)

def BodyRoute(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => body_route_valid(candidate)), candidate)

def CurrentBody(candidate: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => body_valid(candidate)), candidate)

def LocalRequest(source: J.Json) -> Type:
  Categories.intersection(J.Json, OpenHost, (candidate => Categories.intersection(J.Json, Authorization,
    (candidate => Categories.intersection(J.Json, LocalPath, LocalOrigin, candidate)), candidate)), source)

def ConnectionRequest(source: J.Json) -> Type:
  Categories.intersection(J.Json, OpenHost, (candidate => Categories.intersection(J.Json, Authorization,
    (candidate => Categories.intersection(J.Json, ConnectionPath,
      (candidate => Categories.intersection(J.Json, ConnectionMethod, ConnectionOrigin, candidate)), candidate)), candidate)), source)

def Upload(source: J.Json) -> Type:
  Categories.intersection(J.Json, UploadQuery, UploadSize, source)

def LocalUpload(source: J.Json) -> Type:
  Categories.intersection(J.Json, LocalRequest, (candidate => Categories.intersection(J.Json, UploadRoute, Upload, candidate)), source)

def ContentRequest(-Request: J.Json -> Type, source: J.Json) -> Type:
  Categories.intersection(J.Json, Request, (candidate => Categories.intersection(J.Json, BodyRoute, ContentType, candidate)), source)

def BodyRequest(-Request: J.Json -> Type, source: J.Json) -> Type:
  Categories.intersection(J.Json, ContentRequest(Request), CurrentBody, source)

def preflight(+source: J.Json) -> J.Json:
  admit_plan((candidate => open_valid(candidate)), source, closing_plan(True{}), candidate =>
    admit_plan((candidate => host_valid(candidate)), candidate, host_plan(False{}), candidate => host_plan(True{})))

def classify(+source: J.Json) -> J.Json:
  open_host_guard(source, candidate => classify_calculation(candidate))

def authorize(+source: J.Json, connection: Bool) -> J.Json:
  open_host_guard(source, +candidate => admit_plan((candidate => authorization_valid(candidate)), candidate,
    authorization_plan(False{}, connection_path(candidate)), candidate => authorization_plan(True{}, connection_path(candidate))))

def local_checked(+source: J.Json, prior: OpenHost(source), authorized: Bool, local: Bool, origin: Bool,
  ea: {authorization_valid(source) == authorized : Bool}, el: {Bool.not(connection_path(source)) == local : Bool},
  eo: {local_origin_valid(source) == origin : Bool}, accept: Categories.Membership<J.Json, LocalRequest> -> J.Json) -> J.Json:
  match authorized local origin:
    case True{} True{} True{}: accept(Categories.Membership{source, Categories.Intersection{prior, Categories.Intersection{ea, Categories.Intersection{el, eo}}}})
    case False{} _ _: authorization_plan(False{}, False{})
    case True{} False{} _: unknown_route()
    case True{} True{} False{}: rejection("403", "origin", "Origin does not match this server")

def connection_checked(+source: J.Json, prior: OpenHost(source), authorized: Bool, connection: Bool, method: Bool, origin: Bool,
  ea: {authorization_valid(source) == authorized : Bool}, ec: {connection_path(source) == connection : Bool},
  em: {connection_method_valid(source) == method : Bool}, eo: {connection_origin_valid(source) == origin : Bool},
  accept: Categories.Membership<J.Json, ConnectionRequest> -> J.Json) -> J.Json:
  match authorized connection method origin:
    case True{} True{} True{} True{}: accept(Categories.Membership{source, Categories.Intersection{prior, Categories.Intersection{ea, Categories.Intersection{ec, Categories.Intersection{em, eo}}}}})
    case False{} _ _ _: authorization_plan(False{}, True{})
    case True{} False{} _ _: unknown_route()
    case True{} True{} False{} _: rejection("405", "method", "Use POST")
    case True{} True{} True{} False{}: connection_origin_plan(False{})

def request_classified(is_connection: Bool, +source: J.Json, prior: OpenHost(source),
  local: Categories.Membership<J.Json, LocalRequest> -> J.Json,
  connection: Categories.Membership<J.Json, ConnectionRequest> -> J.Json) -> J.Json:
  match is_connection:
    case True{}: connection_checked(source, prior, authorization_valid(source), connection_path(source), connection_method_valid(source), connection_origin_valid(source), {==}, {==}, {==}, {==}, connection)
    case False{}: local_checked(source, prior, authorization_valid(source), Bool.not(connection_path(source)), local_origin_valid(source), {==}, {==}, {==}, local)

def request_admitted(member: Maybe<&1, Categories.Membership<J.Json, OpenHost>>,
  local: Categories.Membership<J.Json, LocalRequest> -> J.Json,
  connection: Categories.Membership<J.Json, ConnectionRequest> -> J.Json) -> J.Json:
  match member:
    case None{}: host_plan(False{})
    case Some{Categories.Membership{+source, prior}}:
      request_classified(connection_path(source), source, prior, local, connection)

def request_guard(+source: J.Json, local: Categories.Membership<J.Json, LocalRequest> -> J.Json,
  connection: Categories.Membership<J.Json, ConnectionRequest> -> J.Json) -> J.Json:
  open_host_guard(source, candidate => request_admitted(Categories.admit_intersection(J.Json,
    (candidate => open_valid(candidate)), (candidate => host_valid(candidate)), candidate), local, connection))

def local_target_7(accepted: Bool) -> String:
  match accepted:
    case True{}: "health"
    case False{}: ""

def local_target_6(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: "event_page"
    case False{}: local_target_7(path_method(source, "GET", "/api/health"))

def local_target_5(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: "events"
    case False{}: local_target_6(path_method(source, "GET", "/api/event-page"), source)

def local_target_4(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: "describe"
    case False{}: local_target_5(path_method(source, "GET", "/api/events"), source)

def local_target_3(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: "browser_state"
    case False{}: local_target_4(path_method(source, "GET", "/api/describe"), source)

def local_target_2(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: body_target(source)
    case False{}: local_target_3(path_method(source, "GET", "/api/browser/state"), source)

def local_target_1(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: "attachment_download"
    case False{}: local_target_2(Bool.not(String.eq(body_target(source), "")), source)

def local_target_0(accepted: Bool, +source: J.Json) -> String:
  match accepted:
    case True{}: "attachment_upload"
    case False{}: local_target_1(String.eq(J.text(J.get(source, "method")), "GET") && starts(J.text(J.get(source, "pathname")), "/api/board/attachments/"), source)

def local_target(+source: J.Json) -> String:
  local_target_0(path_method(source, "POST", "/api/board/attachments"), source)

def local_route_valid(+source: J.Json) -> Bool:
  Bool.not(String.eq(local_target(source), ""))

def LocalRoute(source: J.Json) -> Type:
  Categories.holds(J.Json, (candidate => local_route_valid(candidate)), source)

def LocalEndpoint(source: J.Json) -> Type:
  Categories.intersection(J.Json, LocalRequest, LocalRoute, source)

def local_endpoint_body(+source: J.Json, prior: LocalEndpoint(source), body: Bool,
  observed: {Bool.not(String.eq(body_target(source), "")) == body : Bool}) -> J.Json:
  match body:
    case True{}:
      +candidate = Categories.value(J.Json, LocalEndpoint, Categories.Membership{source, prior})
      content_target(body_target(candidate))
    case False{}:
      +candidate = Categories.value(J.Json, LocalEndpoint, Categories.Membership{source, prior})
      action(local_target(candidate))

def upload_stream(member: Categories.Membership<J.Json, LocalUpload>, upload: Maybe<&1, Categories.Membership<J.Json, Upload>>) -> J.Json:
  match upload:
    case None{}: exception("RangeError", "Each board attachment is limited to 10 MiB")
    case Some{upload}:
      +source = Categories.value(J.Json, LocalUpload, member)
      +upload_source = Categories.value(J.Json, Upload, upload)
      action("attachment_upload")

def upload_terminal(member: Categories.Membership<J.Json, LocalUpload>) -> J.Json:
  Categories.Membership{+source, prior} = member
  Categories.Intersection{request, route_upload} = prior
  Categories.Intersection{route, upload} = route_upload
  upload_stream(Categories.Membership{source, Categories.Intersection{request, Categories.Intersection{route, upload}}},
    Categories.admit_intersection(J.Json, (candidate => attachment_query_valid(candidate)), (candidate => attachment_length_valid(candidate)), source))

def upload_checked(+source: J.Json, prior: LocalRequest(source), route: Bool, query: Bool, size: Bool,
  er: {path_method(source, "POST", "/api/board/attachments") == route : Bool},
  eq: {attachment_query_valid(source) == query : Bool}, es: {attachment_length_valid(source) == size : Bool}) -> J.Json:
  match route query size:
    case True{} True{} True{}: upload_terminal(Categories.Membership{source, Categories.Intersection{prior, Categories.Intersection{er, Categories.Intersection{eq, es}}}})
    case False{} _ _: unknown_route()
    case True{} False{} _: exception("TypeError", "An attachment upload needs exactly one filename")
    case True{} True{} False{}: exception("RangeError", "Each board attachment is limited to 10 MiB")

def upload_request(member: Categories.Membership<J.Json, LocalRequest>) -> J.Json:
  Categories.Membership{+source, prior} = member
  upload_checked(source, prior, path_method(source, "POST", "/api/board/attachments"), attachment_query_valid(source), attachment_length_valid(source), {==}, {==}, {==})

def reject_connection_upload(member: Categories.Membership<J.Json, ConnectionRequest>) -> J.Json:
  +source = Categories.value(J.Json, ConnectionRequest, member)
  unknown_route()

def upload_admission(+source: J.Json) -> J.Json:
  request_guard(source, upload_request, reject_connection_upload)

def local_endpoint_kind(+source: J.Json, prior: LocalEndpoint(source), upload: Bool,
  observed: {String.eq(local_target(source), "attachment_upload") == upload : Bool}) -> J.Json:
  match upload:
    case True{}: upload_admission(source)
    case False{}: local_endpoint_body(source, prior, Bool.not(String.eq(body_target(source), "")), {==})

def local_endpoint_terminal(member: Categories.Membership<J.Json, LocalEndpoint>) -> J.Json:
  Categories.Membership{+source, prior} = member
  local_endpoint_kind(source, prior, String.eq(local_target(source), "attachment_upload"), {==})

def local_route_checked(+source: J.Json, prior: LocalRequest(source), accepted: Bool,
  observed: {local_route_valid(source) == accepted : Bool}) -> J.Json:
  match accepted:
    case True{}: local_endpoint_terminal(Categories.Membership{source, Categories.Intersection{prior, observed}})
    case False{}: unknown_route()

def local_terminal(member: Categories.Membership<J.Json, LocalRequest>) -> J.Json:
  Categories.Membership{+source, prior} = member
  local_route_checked(source, prior, local_route_valid(source), {==})

def connection_terminal(member: Categories.Membership<J.Json, ConnectionRequest>) -> J.Json:
  +source = Categories.value(J.Json, ConnectionRequest, member)
  content_target(body_target(source))

def local_route(+source: J.Json) -> J.Json:
  request_guard(source, local_terminal, connection_terminal)

def local_admission(+source: J.Json) -> J.Json:
  local_route(source)

def connection_admission(+source: J.Json) -> J.Json:
  local_route(source)

def connection_origin(+source: J.Json) -> J.Json:
  local_route(source)

def upload_size_admission(+source: J.Json) -> J.Json:
  upload_admission(source)

def content_terminal(-Request: J.Json -> Type, member: Categories.Membership<J.Json, ContentRequest(Request)>) -> J.Json:
  +source = Categories.value(J.Json, ContentRequest(Request), member)
  action(body_target(source))

def body_terminal(-Request: J.Json -> Type, member: Categories.Membership<J.Json, BodyRequest(Request)>) -> J.Json:
  +source = Categories.value(J.Json, BodyRequest(Request), member)
  J.Object{[J.Field{"action", J.Text{body_target(source)}}, J.Field{"body", parsed_body(source)}]}

def body_checked(-Request: J.Json -> Type, +source: J.Json, prior: ContentRequest(Request, source), valid: Bool,
  observed: {body_valid(source) == valid : Bool}) -> J.Json:
  match valid:
    case True{}: body_terminal(Request, Categories.Membership{source, Categories.Intersection{prior, observed}})
    case False{}: body_error(String.eq(body_target(source), "account_refresh"))

def content_body(-Request: J.Json -> Type, member: Categories.Membership<J.Json, ContentRequest(Request)>) -> J.Json:
  Categories.Membership{+source, prior} = member
  body_checked(Request, source, prior, body_valid(source), {==})

def content_continuation(-Request: J.Json -> Type, member: Categories.Membership<J.Json, ContentRequest(Request)>, body: Bool) -> J.Json:
  match body:
    case False{}: content_terminal(Request, member)
    case True{}: content_body(Request, member)

def content_checked(-Request: J.Json -> Type, +source: J.Json, prior: Request(source), route: Bool, content: Bool,
  er: {body_route_valid(source) == route : Bool}, ec: {content_type_valid(source) == content : Bool}, body: Bool) -> J.Json:
  match route content:
    case True{} True{}: content_continuation(Request, Categories.Membership{source, Categories.Intersection{prior, Categories.Intersection{er, ec}}}, body)
    case False{} _: unknown_route()
    case True{} False{}: rejection("415", "content_type", "Send application/json")

def content_request(-Request: J.Json -> Type, member: Categories.Membership<J.Json, Request>, body: Bool) -> J.Json:
  Categories.Membership{+source, prior} = member
  content_checked(Request, source, prior, body_route_valid(source), content_type_valid(source), {==}, {==}, body)

def content_admission(+source: J.Json) -> J.Json:
  request_guard(source, member => content_request(LocalRequest, member, False{}), member => content_request(ConnectionRequest, member, False{}))

def body_admission(+source: J.Json) -> J.Json:
  request_guard(source, member => content_request(LocalRequest, member, True{}), member => content_request(ConnectionRequest, member, True{}))

def local_open_host_inclusion() -> Categories.Inclusion<J.Json, LocalRequest, OpenHost>:
  Categories.intersection_first(J.Json, OpenHost, (candidate => Categories.intersection(J.Json, Authorization,
    (candidate => Categories.intersection(J.Json, LocalPath, LocalOrigin, candidate)), candidate)))

def local_authority_origin_inclusion() -> Categories.Inclusion<J.Json, LocalRequest,
  (candidate => Categories.intersection(J.Json, Authorization, (candidate => Categories.intersection(J.Json, LocalPath, LocalOrigin, candidate)), candidate))>:
  Categories.intersection_second(J.Json, OpenHost, (candidate => Categories.intersection(J.Json, Authorization,
    (candidate => Categories.intersection(J.Json, LocalPath, LocalOrigin, candidate)), candidate)))

def connection_open_host_inclusion() -> Categories.Inclusion<J.Json, ConnectionRequest, OpenHost>:
  Categories.intersection_first(J.Json, OpenHost, (candidate => Categories.intersection(J.Json, Authorization,
    (candidate => Categories.intersection(J.Json, ConnectionPath, (candidate => Categories.intersection(J.Json, ConnectionMethod, ConnectionOrigin, candidate)), candidate)), candidate)))

def connection_authority_method_origin_inclusion() -> Categories.Inclusion<J.Json, ConnectionRequest,
  (candidate => Categories.intersection(J.Json, Authorization, (candidate => Categories.intersection(J.Json, ConnectionPath,
    (candidate => Categories.intersection(J.Json, ConnectionMethod, ConnectionOrigin, candidate)), candidate)), candidate))>:
  Categories.intersection_second(J.Json, OpenHost, (candidate => Categories.intersection(J.Json, Authorization,
    (candidate => Categories.intersection(J.Json, ConnectionPath, (candidate => Categories.intersection(J.Json, ConnectionMethod, ConnectionOrigin, candidate)), candidate)), candidate)))

def upload_query_inclusion() -> Categories.Inclusion<J.Json, Upload, UploadQuery>:
  Categories.intersection_first(J.Json, UploadQuery, UploadSize)

def upload_size_inclusion() -> Categories.Inclusion<J.Json, Upload, UploadSize>:
  Categories.intersection_second(J.Json, UploadQuery, UploadSize)

def meaning_9(accepted: Bool, operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(reply_status_plan(J.boolean(J.get(J.get(source, "reply"), "ok"))))
    case False{}: Model.failure("Unknown HTTP operation")

def meaning_8(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(body_admission(source))
    case False{}: meaning_9(String.eq(operation, "http.reply_status"), operation, source)

def meaning_7(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(content_admission(source))
    case False{}: meaning_8(String.eq(operation, "http.body"), operation, source)

def meaning_6(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(local_admission(source))
    case False{}: meaning_7(String.eq(operation, "http.content_type"), operation, source)

def meaning_5(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(connection_admission(source))
    case False{}: meaning_6(String.eq(operation, "http.local_origin"), operation, source)

def meaning_4(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(authorize(source, False{}))
    case False{}: meaning_5(String.eq(operation, "http.connection_method_origin"), operation, source)

def meaning_3(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(authorize(source, True{}))
    case False{}: meaning_4(String.eq(operation, "http.local_authorization"), operation, source)

def meaning_2(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(classify(source))
    case False{}: meaning_3(String.eq(operation, "http.connection_authorization"), operation, source)

def meaning_1(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(preflight(source))
    case False{}: meaning_2(String.eq(operation, "http.route"), operation, source)

def meaning_0(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(closing_plan(flag(source, "closing")))
    case False{}: meaning_1(String.eq(operation, "http.preflight"), operation, source)

def meaning(+operation: String, +source: J.Json) -> J.Json:
  meaning_0(String.eq(operation, "http.closing"), operation, source)

def family(+operation: String) -> Model.Adapter(source => meaning(operation, source)):
  Model.adapter(source => meaning(operation, source), source => meaning(operation, source), source => {==})

def run(+operation: String, +source: J.Json) -> J.Json:
  Model.execute(source => meaning(operation, source), family(operation), source)

def open_host_inclusion() -> Categories.Inclusion<J.Json, OpenHost, Host>:
  Categories.intersection_second(J.Json, Open, Host)

def local_host_inclusion() -> Categories.Inclusion<J.Json, LocalRequest, Host>:
  Categories.inclusion_compose(J.Json, LocalRequest, OpenHost, Host, local_open_host_inclusion(), open_host_inclusion())

def connection_host_inclusion() -> Categories.Inclusion<J.Json, ConnectionRequest, Host>:
  Categories.inclusion_compose(J.Json, ConnectionRequest, OpenHost, Host, connection_open_host_inclusion(), open_host_inclusion())

law complete_correspondence:
  @operation:String -> @source:J.Json -> {run(operation, source) == meaning(operation, source) : J.Json}

law admitted_original_source:
  @-predicate:(J.Json -> Bool) -> @source:J.Json ->
  @evidence:Categories.holds(J.Json, predicate, source) -> @reject:J.Json -> @accept:(J.Json -> J.Json) ->
  {admitted_plan(predicate, Some{Categories.Membership{source, evidence}}, reject, accept) == accept(source) : J.Json}

law rejected_admission_plan:
  @-predicate:(J.Json -> Bool) -> @reject:J.Json -> @accept:(J.Json -> J.Json) ->
  {admitted_plan(predicate, None{}, reject, accept) == reject : J.Json}

law stopping_precedes_host_observation:
  {closing_plan(True{}) == rejection("503", "stopping", "Server is stopping") : J.Json}

law open_server_requests_host_observation:
  {closing_plan(False{}) == action("observe_host") : J.Json}

law host_rejection_precedes_url:
  {host_plan(False{}) == rejection("400", "host", "Invalid local host") : J.Json}

law admitted_host_requests_url:
  {host_plan(True{}) == action("parse_url") : J.Json}

law asset_precedes_authorization:
  @source:J.Json -> {classify_asset(True{}, source) == asset_admission(source) : J.Json}

law connection_requests_only_connection_secret:
  {classify_connection(True{}) == action("observe_connection_authorization") : J.Json}

law local_requests_only_local_secret:
  {classify_connection(False{}) == action("observe_local_authorization") : J.Json}

law rejected_connection_authorization:
  {authorization_plan(False{}, True{}) == rejection("401", "unauthorized", "A connection credential is required") : J.Json}

law rejected_local_authorization:
  {authorization_plan(False{}, False{}) == rejection("401", "unauthorized", "A local access token is required") : J.Json}

law authorized_connection_requests_method_origin:
  {authorization_plan(True{}, True{}) == action("connection_method_origin") : J.Json}

law authorized_local_requests_origin:
  {authorization_plan(True{}, False{}) == action("local_origin") : J.Json}

law connection_origin_rejection:
  {connection_origin_plan(False{}) == rejection("403", "origin", "Browser origins and query parameters are not accepted") : J.Json}

law admitted_connection_requests_content_type:
  {connection_origin_plan(True{}) == content_target("connection_command") : J.Json}

law preflight_factory_admission:
  @source:J.Json ->
  {preflight(source) == admit_plan((candidate => open_valid(candidate)), source, closing_plan(True{}), candidate =>
    admit_plan((candidate => host_valid(candidate)), candidate, host_plan(False{}), candidate => host_plan(True{}))) : J.Json}

law authorization_factory_admission:
  @source:J.Json -> @connection:Bool ->
  {authorize(source, connection) == open_host_guard(source, +candidate => admit_plan((candidate => authorization_valid(candidate)), candidate,
    authorization_plan(False{}, connection_path(candidate)), candidate => authorization_plan(True{}, connection_path(candidate)))) : J.Json}

law method_precedes_connection_origin:
  @source:J.Json ->
  {connection_admission(source) == request_guard(source, local_terminal, connection_terminal) : J.Json}

law local_origin_precedes_route:
  @source:J.Json ->
  {local_admission(source) == request_guard(source, local_terminal, connection_terminal) : J.Json}

law upload_query_precedes_size:
  @source:J.Json ->
  {upload_admission(source) == request_guard(source, upload_request, reject_connection_upload) : J.Json}

law upload_size_precedes_stream:
  @source:J.Json ->
  {upload_size_admission(source) == request_guard(source, upload_request, reject_connection_upload) : J.Json}

law content_type_precedes_body:
  @source:J.Json ->
  {content_admission(source) == request_guard(source, member => content_request(LocalRequest, member, False{}), member => content_request(ConnectionRequest, member, False{})) : J.Json}

law raw_body_and_current_shape_required:
  @source:J.Json ->
  {body_valid(source) == (body_observation_valid(source) && body_shape(body_target(source), parsed_body(source))) : Bool}

law body_factory_admission:
  @source:J.Json ->
  {body_admission(source) == request_guard(source, member => content_request(LocalRequest, member, True{}), member => content_request(ConnectionRequest, member, True{})) : J.Json}

law admitted_local_original_source:
  @source:J.Json -> @evidence:LocalRequest(source) ->
  {Categories.value(J.Json, LocalRequest, Categories.Membership{source, evidence}) == source : J.Json}

law admitted_connection_original_source:
  @source:J.Json -> @evidence:ConnectionRequest(source) ->
  {Categories.value(J.Json, ConnectionRequest, Categories.Membership{source, evidence}) == source : J.Json}

law admitted_upload_original_source:
  @source:J.Json -> @evidence:LocalUpload(source) ->
  {Categories.value(J.Json, LocalUpload, Categories.Membership{source, evidence}) == source : J.Json}

law admitted_body_payload:
  @-Request:(J.Json -> Type) -> @source:J.Json -> @evidence:BodyRequest(Request, source) ->
  {J.get(body_terminal(Request, Categories.Membership{source, evidence}), "body") == parsed_body(source) : J.Json}

law admitted_body_original_source:
  @-Request:(J.Json -> Type) -> @source:J.Json -> @evidence:BodyRequest(Request, source) ->
  {Categories.value(J.Json, BodyRequest(Request), Categories.Membership{source, evidence}) == source : J.Json}

law successful_reply_status:
  {reply_status_plan(True{}) == J.Number{"200"} : J.Json}

law failed_reply_status:
  {reply_status_plan(False{}) == J.Number{"400"} : J.Json}

law reply_status_full_result:
  @source:J.Json ->
  {run("http.reply_status", source) == Model.success(reply_status_plan(J.boolean(J.get(J.get(source, "reply"), "ok")))) : J.Json}

law admitted_local_open_evidence:
  @source:J.Json -> @evidence:LocalRequest(source) -> Open(source)

law admitted_local_host_evidence:
  @source:J.Json -> @evidence:LocalRequest(source) -> Host(source)

law admitted_local_authorization_evidence:
  @source:J.Json -> @evidence:LocalRequest(source) -> Authorization(source)

law admitted_local_path_evidence:
  @source:J.Json -> @evidence:LocalRequest(source) -> LocalPath(source)

law admitted_local_origin_evidence:
  @source:J.Json -> @evidence:LocalRequest(source) -> LocalOrigin(source)

law admitted_connection_open_evidence:
  @source:J.Json -> @evidence:ConnectionRequest(source) -> Open(source)

law admitted_connection_host_evidence:
  @source:J.Json -> @evidence:ConnectionRequest(source) -> Host(source)

law admitted_connection_authorization_evidence:
  @source:J.Json -> @evidence:ConnectionRequest(source) -> Authorization(source)

law admitted_connection_path_evidence:
  @source:J.Json -> @evidence:ConnectionRequest(source) -> ConnectionPath(source)

law admitted_connection_method_evidence:
  @source:J.Json -> @evidence:ConnectionRequest(source) -> ConnectionMethod(source)

law admitted_connection_origin_evidence:
  @source:J.Json -> @evidence:ConnectionRequest(source) -> ConnectionOrigin(source)

law admitted_upload_request_evidence:
  @source:J.Json -> @evidence:LocalUpload(source) -> LocalRequest(source)

law admitted_upload_route_evidence:
  @source:J.Json -> @evidence:LocalUpload(source) -> UploadRoute(source)

law admitted_upload_requirements_evidence:
  @source:J.Json -> @evidence:LocalUpload(source) -> Upload(source)

law admitted_body_request_evidence:
  @-Request:(J.Json -> Type) -> @source:J.Json -> @evidence:BodyRequest(Request, source) -> Request(source)

law admitted_body_route_evidence:
  @-Request:(J.Json -> Type) -> @source:J.Json -> @evidence:BodyRequest(Request, source) -> BodyRoute(source)

law admitted_body_content_evidence:
  @-Request:(J.Json -> Type) -> @source:J.Json -> @evidence:BodyRequest(Request, source) -> ContentType(source)

law admitted_body_body_evidence:
  @-Request:(J.Json -> Type) -> @source:J.Json -> @evidence:BodyRequest(Request, source) -> CurrentBody(source)

law admitted_content_route_target:
  @-Request:(J.Json -> Type) -> @source:J.Json -> @evidence:ContentRequest(Request, source) ->
  {J.get(content_terminal(Request, Categories.Membership{source, evidence}), "action") == J.Text{body_target(source)} : J.Json}

law admitted_body_route_target:
  @-Request:(J.Json -> Type) -> @source:J.Json -> @evidence:BodyRequest(Request, source) ->
  {J.get(body_terminal(Request, Categories.Membership{source, evidence}), "action") == J.Text{body_target(source)} : J.Json}
