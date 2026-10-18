import Base
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ../../bendlib/stdlib.bend as Std
import ../../harness/DOMAIN.bend as Domain
import ./MODEL.bend as Model

# Observations carry parser results, never a host verdict about account policy.
def select(condition: Bool, yes: J.Json, no: J.Json) -> J.Json:
  match condition:
    case True{}: yes
    case False{}: no

def has_fields(fields: +List<J.Field>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{J.Field{key, value}, rest}: String.eq(key, name) || has_fields(rest, name)
def has(value: J.Json, name: String) -> Bool:
  match value:
    case J.Object{fields}: has_fields(fields, name)
    case _: False{}
def field(+value: J.Json, +name: String, fallback: J.Json) -> J.Json:
  select(has(value, name), J.get(value, name), fallback)
def fields(value: J.Json) -> +List<J.Field>:
  match value:
    case J.Object{fields}: fields
    case _: Nil{}
def space(char: Char) -> Bool:
  Chr{+code} = char
  Char.is_space(Chr{code}) || U32.is_eq(code, 160) || U32.is_eq(code, 5760) ||
    (U32.is_ge(code, 8192) && U32.is_le(code, 8202)) || U32.is_eq(code, 8232) ||
    U32.is_eq(code, 8233) || U32.is_eq(code, 8239) || U32.is_eq(code, 8287) ||
    U32.is_eq(code, 12288) || U32.is_eq(code, 65279)
def content_scan(text: String, valid: Bool) -> Bool:
  match text:
    case SNil{}: valid
    case SCon{head, tail}: content_scan(tail, valid || Bool.not(space(head)))

def content(text: String) -> Bool:
  content_scan(text, False{})
def nonempty(+value: J.Json) -> Bool:
  J.is_text(value) && content(J.text(value))
def nullable(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case _: nonempty(value)

# ECMAScript whitespace, shared by trim and scope tokenization in the source API.
def char_code(char: Char) -> U32:
  Chr{code} = char
  code
def char_width(wide: Bool) -> Nat:
  match wide:
    case True{}: 2n
    case False{}: 1n

def utf16(text: String) -> Nat:
  match text:
    case SNil{}: 0n
    case SCon{head, tail}: Nat.add(char_width(U32.is_gt(char_code(head), 65535)), utf16(tail))
def bounded_text(+value: J.Json) -> Bool:
  nonempty(value) && Nat.is_le(utf16(J.text(value)), 256n)
def word_current(separator: Bool, head: Char, current: String) -> String:
  match separator:
    case True{}: ""
    case False{}: current ++ SCon{head, SNil{}}
def word_step(separator: Bool, current: String, +rest: +List<String>) -> +List<String>:
  match separator:
    case True{}: Con{current, rest}
    case False{}: rest
def words(text: String, +current: String) -> +List<String>:
  match text:
    case SNil{}: Con{current, Nil{}}
    case SCon{+head, tail}: word_step(space(head), current, words(tail, word_current(space(head), head, current)))
def contains(values: +List<String>, +key: String) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{head, tail}: String.eq(head, key) || contains(tail, key)
def scope(+value: J.Json) -> Bool:
  nonempty(value) && contains(words(J.text(value), ""), "chatgpt.tokens.use.direct")
def client(+value: J.Json) -> Bool:
  nonempty(value) && Bool.not(String.eq(J.text(value), "dynamic_agent_client"))

def defaults() -> J.Json:
  J.Object{Con{J.Field{"provider", J.Text{"chatgpt"}}, Con{J.Field{"endpoint", J.Text{"https://api.openai.com/v1/responses"}}, Con{J.Field{"auth_file", J.Text{"auth/chatgpt.json"}}, Con{J.Field{"issuer", J.Text{"https://auth.openai.com"}}, Con{J.Field{"timeout_ms", J.Number{"300000"}}, Nil{}}}}}}}
def contract() -> J.Json:
  J.Object{Con{J.Field{"login_timeout_ms", J.Number{"600000"}}, Con{J.Field{"maximum", J.Number{"1048576"}}, Con{J.Field{"namespace", J.Text{"selvedge"}}, Con{J.Field{"resource", J.Text{"https://api.openai.com/v1"}}, Con{J.Field{"scopes", J.Text{"openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"}}, Con{J.Field{"default", defaults()}, Nil{}}}}}}}}
def connection_keys() -> +List<String>:
  Con{"provider", Con{"endpoint", Con{"auth_file", Con{"issuer", Con{"timeout_ms", Nil{}}}}}}
def drop_slashes(+text: String) -> String:
  match text:
    case SCon{Chr{47}, tail}: drop_slashes(tail)
    case _: text

def trim_slashes(text: String) -> String:
  String.reverse(drop_slashes(String.reverse(text)))
def first_unknown(fields: +List<J.Field>) -> J.Json:
  match fields:
    case Nil{}: J.Null{}
    case Con{J.Field{+name, value}, rest}: select(contains(connection_keys(), name), first_unknown(rest), J.Text{name})
def project_step(include: Bool, name: String, value: J.Json, +rest: +List<J.Field>) -> +List<J.Field>:
  match include:
    case True{}: Con{J.Field{name, value}, rest}
    case False{}: rest

def project(fields: +List<J.Field>, +keys: +List<String>) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{+name, value}, rest}: project_step(contains(keys, name), name, value, project(rest, keys))
def loopback(url: J.Json) -> Bool:
  contains(Con{"localhost", Con{"127.0.0.1", Con{"[::1]", Nil{}}}}, J.text(J.get(url, "hostname")))
def parsed(+url: J.Json) -> Bool:
  J.is_object(url) && nonempty(J.get(url, "href"))
def url_shape(+url: J.Json) -> Bool:
  parsed(url) && contains(Con{"http:", Con{"https:", Nil{}}}, J.text(J.get(url, "protocol"))) &&
    String.is_empty(J.text(J.get(url, "username"))) && String.is_empty(J.text(J.get(url, "password"))) && String.is_empty(J.text(J.get(url, "hash")))
def secure(+url: J.Json) -> Bool:
  String.eq(J.text(J.get(url, "protocol")), "https:") || loopback(url)
def responses_path(+url: J.Json) -> Bool:
  String.ends_with(J.text(J.get(url, "pathname")), "/responses") || String.ends_with(J.text(J.get(url, "pathname")), "/responses/")
def endpoint_binding(+url: J.Json) -> Bool:
  loopback(url) || (String.eq(J.text(J.get(url, "origin")), "https://api.openai.com") && String.eq(J.text(J.get(url, "pathname")), "/v1/responses"))
def issuer_binding(+url: J.Json) -> Bool:
  loopback(url) || String.eq(J.text(J.get(url, "origin")), "https://auth.openai.com")

def number_text(+value: J.Json) -> String:
  match value:
    case J.Number{value}: value
    case _: ""
def number_between(+value: J.Json, minimum: String, maximum: String) -> Bool:
  Model.nonnegative_le(value, maximum) && Model.decimal_le(minimum, number_text(value))
def number_at_least(+value: J.Json, minimum: String) -> Bool:
  Model.nonnegative_le(value, number_text(value)) && Model.decimal_le(minimum, number_text(value))
def timeout_bound(valid: Bool, +value: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT timeout must be in 100..1800000")
    case True{}: Model.success(J.Object{Con{J.Field{"provider", J.Text{"chatgpt"}}, Con{J.Field{"endpoint", field(value, "endpoint", J.get(defaults(), "endpoint"))}, Con{J.Field{"auth_file", field(value, "auth_file", J.get(defaults(), "auth_file"))}, Con{J.Field{"issuer", J.Text{trim_slashes(J.text(field(value, "issuer", J.get(defaults(), "issuer"))))}}, Con{J.Field{"timeout_ms", field(value, "timeout_ms", J.Number{"300000"})}, Nil{}}}}}}})

def timeout(observed: J.Json, value: J.Json) -> J.Json:
  timeout_bound(number_between(observed, "100", "1800000"), value)
def auth_file(valid: Bool, +value: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT auth_file must be a nonempty string")
    case True{}: timeout(field(value, "timeout_ms", J.Number{"300000"}), value)
def issuer_origin(valid: Bool, +value: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT issuer must be an origin")
    case True{}: auth_file(nonempty(field(value, "auth_file", J.get(defaults(), "auth_file"))), value)
def issuer_official(valid: Bool, value: J.Json, +urls: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT requires the official issuer")
    case True{}: issuer_origin(String.eq(J.text(J.get(J.get(urls, "issuer"), "pathname")), "/") && String.is_empty(J.text(J.get(J.get(urls, "issuer"), "search"))), value)
def issuer_secure(valid: Bool, value: J.Json, +urls: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT issuer requires HTTPS except on loopback")
    case True{}: issuer_official(issuer_binding(J.get(urls, "issuer")), value, urls)
def connection_invalid_url(parsed: Bool, message: String) -> J.Json:
  match parsed:
    case True{}: Model.failure(message)
    case False{}: Model.failure("Invalid URL")

# Profiles reuse the same account constructor after selecting its public fields.
def issuer_shape(valid: Bool, value: J.Json, +urls: J.Json) -> J.Json:
  match valid:
    case False{}: connection_invalid_url(parsed(J.get(urls, "issuer")), "Invalid ChatGPT issuer")
    case True{}: issuer_secure(secure(J.get(urls, "issuer")), value, urls)
def issuer_text(valid: Bool, value: J.Json, +urls: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT issuer must be a nonempty string")
    case True{}: issuer_shape(url_shape(J.get(urls, "issuer")), value, urls)
def endpoint_official(valid: Bool, +value: J.Json, urls: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT requires the official public Responses endpoint")
    case True{}: issuer_text(nonempty(field(value, "issuer", J.get(defaults(), "issuer"))), value, urls)
def endpoint_suffix(valid: Bool, value: J.Json, +urls: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT endpoint must end in /responses")
    case True{}: endpoint_official(endpoint_binding(J.get(urls, "endpoint")), value, urls)
def endpoint_secure(valid: Bool, value: J.Json, +urls: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT endpoint requires HTTPS except on loopback")
    case True{}: endpoint_suffix(responses_path(J.get(urls, "endpoint")), value, urls)
def endpoint_shape(valid: Bool, value: J.Json, +urls: J.Json) -> J.Json:
  match valid:
    case False{}: connection_invalid_url(parsed(J.get(urls, "endpoint")), "Invalid ChatGPT endpoint")
    case True{}: endpoint_secure(secure(J.get(urls, "endpoint")), value, urls)
def endpoint_check(text: Bool, value: J.Json, +urls: J.Json) -> J.Json:
  match text:
    case False{}: Model.failure("ChatGPT endpoint must be a nonempty string")
    case True{}: endpoint_shape(url_shape(J.get(urls, "endpoint")), value, urls)
def connection_endpoints(+value: J.Json, urls: J.Json) -> J.Json:
  endpoint_check(nonempty(field(value, "endpoint", J.get(defaults(), "endpoint"))), value, urls)
def connection_provider(provider: J.Json, value: J.Json, urls: J.Json) -> J.Json:
  match provider:
    case J.Text{"chatgpt"}: connection_endpoints(value, urls)
    case _: Model.failure("The account provider must be chatgpt")
def connection_known(unknown: J.Json, +value: J.Json, urls: J.Json) -> J.Json:
  match unknown:
    case J.Text{name}: Model.failure("Unknown ChatGPT account field: " ++ name)
    case _: connection_provider(field(value, "provider", J.Text{"chatgpt"}), value, urls)
def connection_decision(object: Bool, unknown: J.Json, value: J.Json, urls: J.Json) -> J.Json:
  match object:
    case False{}: Model.failure("ChatGPT account must be an object")
    case True{}: connection_known(unknown, value, urls)
def connection_value(+value: J.Json, urls: J.Json) -> J.Json:
  connection_decision(J.is_object(value), first_unknown(fields(value)), value, urls)
def connection(+source: J.Json) -> J.Json:
  connection_value(J.get(source, "value"), J.get(source, "urls"))
def credential_keys() -> +List<String>:
  Con{"format", Con{"issuer", Con{"client_id", Con{"subject", Con{"account_id", Con{"access_token", Con{"refresh_token", Con{"id_token", Con{"scope", Con{"expires_at", Con{"earliest_refresh_at", Con{"last_refresh", Con{"name", Con{"email", Nil{}}}}}}}}}}}}}}}
def has_all(+value: J.Json, keys: +List<String>) -> Bool:
  match keys:
    case Nil{}: True{}
    case Con{key, rest}: has(value, key) && has_all(value, rest)
def date_valid(value: J.Json, +observation: J.Json) -> Bool:
  J.is_text(value) && J.is_object(observation) && J.is_text(J.get(observation, "iso"))
def credential_format(source: J.Json) -> Bool:
  +value = J.get(source, "value")
  J.is_object(value) && J.same(J.get(value, "format"), J.Text{"selvedge-chatgpt-2"}) && Nat.is_eq(List.length(&2, J.Field, fields(value)), 14n) && has_all(value, credential_keys())
def credential_binding(+source: J.Json) -> Bool:
  +value = J.get(source, "value")
  nonempty(J.get(value, "issuer")) && client(J.get(value, "client_id")) && nonempty(J.get(value, "subject")) &&
    nonempty(J.get(value, "account_id")) && J.same(J.get(value, "account_id"), J.get(source, "identity"))
def credential_content(+source: J.Json) -> Bool:
  +value = J.get(source, "value")
  +dates = J.get(source, "dates")
  nonempty(J.get(value, "access_token")) && nonempty(J.get(value, "refresh_token")) && nonempty(J.get(value, "id_token")) && scope(J.get(value, "scope")) &&
    date_valid(J.get(value, "expires_at"), J.get(dates, "expires_at")) && date_valid(J.get(value, "last_refresh"), J.get(dates, "last_refresh")) &&
    (J.same(J.get(value, "earliest_refresh_at"), J.Null{}) || date_valid(J.get(value, "earliest_refresh_at"), J.get(dates, "earliest_refresh_at"))) &&
    nullable(J.get(value, "name")) && nullable(J.get(value, "email"))
def credential_context(+source: J.Json) -> Bool:
  credential_binding(source) && credential_content(source)
def credential_requirements(+source: J.Json) -> Bool:
  credential_format(source) && credential_content(source)
def credential_admitted(member: Maybe<&1, Categories.Membership<J.Json, (source => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => credential_binding(candidate))), Categories.holds(J.Json, (candidate => credential_requirements(candidate))), source))>>) -> J.Json:
  match member:
    case None{}: Model.failure("Invalid current-format ChatGPT credential; sign in again")
    case Some{member}: Model.success(J.get(Categories.value(J.Json, (source => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => credential_binding(candidate))), Categories.holds(J.Json, (candidate => credential_requirements(candidate))), source)), member), "value"))

def credential(source: J.Json) -> J.Json:
  credential_admitted(Categories.admit_intersection(J.Json, (candidate => credential_binding(candidate)), (candidate => credential_requirements(candidate)), source))
def registration_decision(valid: Bool, value: J.Json) -> J.Json:
  match valid:
    case True{}: Model.success(value)
    case False{}: Model.failure("Invalid ChatGPT client registration; sign in again")

def registration_shape(source: J.Json) -> Bool:
  +value = J.get(source, "value")
  J.is_object(value) && J.same(J.get(value, "format"), J.Text{"selvedge-chatgpt-registration-1"}) && Nat.is_eq(List.length(&2, J.Field, fields(value)), 4n) && client(J.get(value, "client_id")) && has(value, "subject") && nullable(J.get(value, "subject"))
def registration_binding(+source: J.Json) -> Bool:
  J.same(J.get(J.get(source, "value"), "issuer"), J.get(source, "issuer"))
def registration_admitted(member: Maybe<&1, Categories.Membership<J.Json, (source => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => registration_binding(candidate))), Categories.holds(J.Json, (candidate => registration_shape(candidate))), source))>>) -> J.Json:
  match member:
    case None{}: Model.failure("Invalid ChatGPT client registration; sign in again")
    case Some{member}: Model.success(J.get(Categories.value(J.Json, (source => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => registration_binding(candidate))), Categories.holds(J.Json, (candidate => registration_shape(candidate))), source)), member), "value"))
def registration(source: J.Json) -> J.Json:
  registration_admitted(Categories.admit_intersection(J.Json, (candidate => registration_binding(candidate)), (candidate => registration_shape(candidate)), source))
def discovery_url(+url: J.Json, +issuer: J.Json) -> Bool:
  url_shape(url) && J.same(J.get(url, "origin"), J.get(issuer, "origin")) &&
    (String.eq(J.text(J.get(url, "protocol")), "https:") || (String.eq(J.text(J.get(issuer, "protocol")), "http:") && loopback(issuer)))
def discovery_decision(valid: Bool, value: J.Json) -> J.Json:
  match valid:
    case True{}: Model.success(value)
    case False{}: Model.failure("Invalid ChatGPT OpenID discovery")

def discovery(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  +issuer = J.get(source, "issuer_url")
  +urls = J.get(source, "urls")
  discovery_decision(J.same(J.get(value, "issuer"), J.get(source, "issuer")) &&
    discovery_url(J.get(urls, "authorization_endpoint"), issuer) && discovery_url(J.get(urls, "token_endpoint"), issuer) && discovery_url(J.get(urls, "jwks_uri"), issuer), value)
def strip_epoch_zeros(+text: String) -> String:
  match text:
    case SNil{}: "0"
    case SCon{Chr{48}, rest}: strip_epoch_zeros(rest)
    case _: text
def epoch_text(valid: Bool, text: String) -> String:
  match valid:
    case False{}: "0"
    case True{}: strip_epoch_zeros(text)
def epoch(value: J.Json) -> String:
  +text = J.text(J.get(value, "ordered_epoch"))
  epoch_text(Model.decimal_digits(text), text)
def epoch_greater(left: J.Json, right: J.Json) -> Bool:
  Bool.not(Model.decimal_le(epoch(left), epoch(right)))
def refresh_identity(valid: Bool, +source: J.Json, +value: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT credential does not match its registered identity")
    case True{}: Model.success(J.Boolean{(epoch_greater(J.get(J.get(source, "dates"), "expires_at"), J.get(source, "threshold")) &&
      (Bool.not(has(source, "rejectedToken")) || Bool.not(J.same(J.get(source, "rejectedToken"), J.get(value, "access_token"))))) ||
      (Bool.not(J.same(J.get(value, "earliest_refresh_at"), J.Null{})) && epoch_greater(J.get(J.get(source, "dates"), "earliest_refresh_at"), J.get(source, "now_date")) && Bool.not(has(source, "rejectedToken")))})


def refresh_registration_decision(valid: Bool) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT credential does not match its registered identity")
    case True{}: Model.success(J.Null{})
def refresh_registration(+source: J.Json) -> J.Json:
  refresh_registration_decision(J.same(J.get(J.get(source, "registered"), "client_id"), J.get(J.get(source, "value"), "client_id")) && J.same(J.get(J.get(source, "registered"), "subject"), J.get(J.get(source, "value"), "subject")))
def refresh_initial_action(keep: Bool, +source: J.Json) -> J.Json:
  match keep:
    case True{}: Model.success(J.Text{"keep"})
    case False{}: Model.success(select(Bool.not(J.same(J.get(J.get(source, "value"), "earliest_refresh_at"), J.Null{})) && Bool.not(has(source, "rejectedToken")), J.Text{"earliest"}, J.Text{"refresh"}))
def refresh_initial_identity(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT credential does not match its registered identity")
    case True{}: refresh_initial_action(epoch_greater(J.get(J.get(source, "dates"), "expires_at"), J.get(source, "threshold")) && (Bool.not(has(source, "rejectedToken")) || Bool.not(J.same(J.get(source, "rejectedToken"), J.get(J.get(source, "value"), "access_token")))), source)
def refresh_initial(+source: J.Json) -> J.Json:
  refresh_initial_identity(J.same(J.get(J.get(source, "registered"), "client_id"), J.get(J.get(source, "value"), "client_id")) && J.same(J.get(J.get(source, "registered"), "subject"), J.get(J.get(source, "value"), "subject")), source)
def refresh_issuer(valid: Bool, +source: J.Json, +value: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT credential belongs to a different issuer; sign in again")
    case True{}: refresh_identity(J.same(J.get(J.get(source, "registered"), "client_id"), J.get(value, "client_id")) && J.same(J.get(J.get(source, "registered"), "subject"), J.get(value, "subject")), source, value)
def refresh(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  refresh_issuer(J.same(J.get(value, "issuer"), J.get(source, "issuer")), source, value)
def number_positive(value: J.Json) -> Bool:
  match value:
    case J.Number{+text}: Bool.not(String.starts_with(text, "-")) && Bool.not(String.eq(text, "0"))
    case _: False{}
def token_grant(+source: J.Json) -> Bool:
  +tokens = J.get(source, "tokens")
  +previous = J.get(source, "previous")
  nonempty(J.get(tokens, "access_token")) && nonempty(J.get(tokens, "refresh_token")) &&
    J.is_text(J.get(tokens, "token_type")) && String.eq(String.to_lower(J.text(J.get(tokens, "token_type"))), "bearer") &&
    number_positive(J.get(tokens, "expires_in")) &&
    (J.is_object(previous) || nonempty(J.get(tokens, "id_token"))) &&
    scope(select(J.same(J.get(tokens, "scope"), J.Null{}), J.get(previous, "scope"), J.get(tokens, "scope")))
def token_identity_field(+claims: J.Json, previous: J.Json, +claim: String, key: String) -> J.Json:
  select(J.is_object(claims), select(nonempty(J.get(claims, claim)), J.get(claims, claim), J.Null{}), J.get(previous, key))
def token_record(+source: J.Json, +tokens: J.Json, +claims: J.Json, +previous: J.Json) -> J.Json:
  J.Object{Con{J.Field{"format", J.Text{"selvedge-chatgpt-2"}}, Con{J.Field{"issuer", J.get(J.get(source, "metadata"), "issuer")}, Con{J.Field{"client_id", J.get(source, "clientId")}, Con{J.Field{"subject", select(J.is_object(claims), J.get(claims, "sub"), J.get(previous, "subject"))}, Con{J.Field{"account_id", J.get(source, "identity")}, Con{J.Field{"name", token_identity_field(claims, previous, "name", "name")}, Con{J.Field{"email", token_identity_field(claims, previous, "email", "email")}, Con{J.Field{"access_token", J.get(tokens, "access_token")}, Con{J.Field{"refresh_token", J.get(tokens, "refresh_token")}, Con{J.Field{"id_token", select(J.same(J.get(tokens, "id_token"), J.Null{}), J.get(previous, "id_token"), J.get(tokens, "id_token"))}, Con{J.Field{"scope", select(J.same(J.get(tokens, "scope"), J.Null{}), J.get(previous, "scope"), J.get(tokens, "scope"))}, Con{J.Field{"expires_at", J.get(J.get(source, "expires"), "iso")}, Con{J.Field{"earliest_refresh_at", J.get(J.get(source, "earliest"), "iso")}, Con{J.Field{"last_refresh", J.get(J.get(source, "now_date"), "iso")}, Nil{}}}}}}}}}}}}}}}}
def token_value(+source: J.Json, +tokens: J.Json, +claims: J.Json, +previous: J.Json) -> J.Json:
  +value = token_record(source, tokens, claims, previous)
  credential(J.Object{Con{J.Field{"value", value}, Con{J.Field{"identity", J.get(source, "identity")}, Con{J.Field{"dates", J.Object{Con{J.Field{"expires_at", J.get(source, "expires")}, Con{J.Field{"last_refresh", J.get(source, "now_date")}, Con{J.Field{"earliest_refresh_at", J.get(source, "earliest")}, Nil{}}}}}}, Nil{}}}}})

def token_earliest(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("Invalid ChatGPT token refresh time")
    case True{}: token_value(source, J.get(source, "tokens"), J.get(source, "claims"), J.get(source, "previous"))
def token_expiry(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure_code("RangeError", "Invalid time value")
    case True{}: token_earliest(J.same(J.get(J.get(source, "tokens"), "earliest_refresh_at"), J.Null{}) || J.is_text(J.get(J.get(source, "earliest"), "iso")), source)
def token_identity(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT identity verification failed; sign in again")
    case True{}: token_expiry(J.is_object(J.get(source, "expires")), source)
def token_claims(+claims: J.Json, +source: J.Json) -> J.Json:
  token_identity((J.is_object(J.get(source, "previous")) || J.is_object(claims)) &&
    (J.same(claims, J.Null{}) || (nonempty(J.get(claims, "sub")) &&
    (Bool.not(has(source, "subject")) || J.same(J.get(claims, "sub"), J.get(source, "subject"))) &&
    (Bool.not(has(claims, "azp")) || J.same(J.get(claims, "azp"), J.get(source, "clientId"))))), source)
def token_phase(phase: String, +source: J.Json) -> J.Json:
  match phase:
    case "grant": Model.success(J.Null{})
    case _: token_claims(J.get(source, "claims"), source)
def token_admit(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT returned an invalid token grant")
    case True{}: token_phase(J.text(J.get(source, "phase")), source)
def token(+source: J.Json) -> J.Json:
  token_admit(token_grant(source), source)
def is_array(value: J.Json) -> Bool:
  match value:
    case J.Array{items}: True{}
    case _: False{}
def ascii_alnum(char: Char) -> Bool:
  Chr{+code} = char
  (U32.is_ge(code, 65) && U32.is_le(code, 90)) || (U32.is_ge(code, 97) && U32.is_le(code, 122)) || (U32.is_ge(code, 48) && U32.is_le(code, 57))
def slug_tail(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{+head, tail}: (ascii_alnum(head) || contains(Con{".", Con{"_", Con{":", Con{"/", Con{"-", Nil{}}}}}}, SCon{head, SNil{}})) && slug_tail(tail)
def slug(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{head, tail}: ascii_alnum(head) && slug_tail(tail)
def strip_sign(+text: String) -> String:
  match text:
    case SCon{Chr{45}, tail}: tail
    case _: text
def integer_digits(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{head, tail}: Char.is_digit(head) && integer_digits(tail)
def integer_bound(text: String) -> Bool:
  Model.decimal_bound(text)
def safe_integer(value: J.Json) -> Bool:
  match value:
    case J.Number{+text}: integer_digits(strip_sign(text)) && integer_bound(strip_sign(text))
    case _: False{}
def effort_items(items: +List<J.Json>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+level, rest}: J.is_object(level) && bounded_text(J.get(level, "effort")) && effort_items(rest)
def descriptor_window(+model: J.Json, +name: String, maximum: String) -> Bool:
  Bool.not(has(model, name)) || (safe_integer(J.get(model, name)) && number_between(J.get(model, name), "1", maximum))
def descriptor_valid(+model: J.Json, seen: +List<String>) -> Bool:
  J.is_object(model) && bounded_text(J.get(model, "slug")) && bounded_text(J.get(model, "display_name")) && slug(J.text(J.get(model, "slug"))) && Bool.not(contains(seen, J.text(J.get(model, "slug")))) &&
    contains(Con{"list", Con{"hide", Con{"none", Nil{}}}}, J.text(J.get(model, "visibility"))) &&
    (Bool.not(has(model, "priority")) || safe_integer(J.get(model, "priority"))) &&
    (Bool.not(has(model, "supported_reasoning_levels")) || (is_array(J.get(model, "supported_reasoning_levels")) && Nat.is_le(List.length(&2, J.Json, J.items(J.get(model, "supported_reasoning_levels"))), 32n) && effort_items(J.items(J.get(model, "supported_reasoning_levels"))))) &&
    (J.same(J.get(model, "default_reasoning_level"), J.Null{}) || bounded_text(J.get(model, "default_reasoning_level"))) &&
    descriptor_window(model, "context_window", "4294967295") && descriptor_window(model, "effective_context_window_percent", "100")
def effort_projection(items: +List<J.Json>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{level, rest}: Con{J.Object{Con{J.Field{"effort", J.get(level, "effort")}, Nil{}}}, effort_projection(rest)}
def optional_field(+model: J.Json, +name: String, rest: +List<J.Field>) -> +List<J.Field>:
  project_step(has(model, name), name, J.get(model, name), rest)
def descriptor_options(+model: J.Json) -> +List<J.Field>:
  optional_field(model, "priority", optional_field(model, "default_reasoning_level",
    project_step(has(model, "supported_reasoning_levels"), "supported_reasoning_levels", J.Array{effort_projection(J.items(J.get(model, "supported_reasoning_levels")))},
      optional_field(model, "context_window", optional_field(model, "effective_context_window_percent", Nil{})))))
def descriptor(+model: J.Json) -> J.Json:
  J.Object{List.append(&2, J.Field, [J.Field{"slug", J.get(model, "slug")}, J.Field{"display_name", J.get(model, "display_name")}, J.Field{"visibility", J.get(model, "visibility")}], descriptor_options(model))}
def catalog_cons_result(valid: Bool, model: J.Json, +rest: J.Json) -> J.Json:
  match valid:
    case False{}: rest
    case True{}: Model.success(J.Array{Con{model, J.items(J.get(rest, "value"))}})

def catalog_cons(model: J.Json, +rest: J.Json) -> J.Json:
  catalog_cons_result(J.boolean(J.get(rest, "ok")), model, rest)
def catalog_descriptor_seen(+seen: +List<String>, member: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (model => descriptor_valid(model, seen)))>>, rest: J.Json) -> J.Json:
  match member:
    case None{}: Model.failure("ChatGPT returned an invalid model descriptor")
    case Some{member}: catalog_cons(descriptor(Categories.value(J.Json, Categories.holds(J.Json, (model => descriptor_valid(model, seen))), member)), rest)
def catalog_models(models: +List<J.Json>, +seen: +List<String>) -> J.Json:
  match models:
    case Nil{}: Model.success(J.Array{Nil{}})
    case Con{+model, rest}: catalog_descriptor_seen(seen, Categories.admit(J.Json, (model => descriptor_valid(model, seen)), model), catalog_models(rest, Con{J.text(J.get(model, "slug")), seen}))
def catalog_shape(valid: Bool, models: +List<J.Json>) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT returned an invalid model catalog")
    case True{}: catalog_models(models, Nil{})
def catalog(source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  catalog_shape(J.is_object(value) && is_array(J.get(value, "models")) && Nat.is_le(List.length(&2, J.Json, J.items(J.get(value, "models"))), 512n), J.items(J.get(value, "models")))
def suffix_length(slash: Bool) -> Nat:
  match slash:
    case True{}: 11n
    case False{}: 10n

def models_url_check(valid: Bool, +url: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT endpoint must end in /responses")
    case True{}: Model.success(J.Text{String.take(J.text(J.get(url, "pathname")), Nat.sub(String.length(J.text(J.get(url, "pathname"))), suffix_length(String.ends_with(J.text(J.get(url, "pathname")), "/responses/")))) ++ "/models"})
def models_url(+source: J.Json) -> J.Json:
  models_url_check(responses_path(J.get(source, "url")), J.get(source, "url"))
def profile_connection_selected(+profile: J.Json) -> J.Json:
  J.Object{project(fields(profile), connection_keys())}
def profile_connection(source: J.Json) -> J.Json:
  +profile = J.get(source, "profile")
  +selected = profile_connection_selected(profile)
  Model.success(J.Object{Con{J.Field{"endpoint", select(J.same(J.get(selected, "endpoint"), J.Null{}), J.get(defaults(), "endpoint"), J.get(selected, "endpoint"))}, Con{J.Field{"auth_file", select(J.same(J.get(selected, "auth_file"), J.Null{}), J.get(defaults(), "auth_file"), J.get(selected, "auth_file"))}, Con{J.Field{"issuer", select(J.same(J.get(selected, "issuer"), J.Null{}), J.get(defaults(), "issuer"), J.get(selected, "issuer"))}, project(fields(selected), Con{"provider", Con{"timeout_ms", Nil{}}})}}}})
def issuer_admission_check(valid: Bool, source: J.Json) -> J.Json:
  match valid:
    case True{}: Model.success(J.get(source, "value"))
    case False{}: Model.failure("ChatGPT credential belongs to a different issuer; sign in again")
def issuer_admission(+source: J.Json) -> J.Json:
  issuer_admission_check(J.same(J.get(J.get(source, "value"), "issuer"), J.get(source, "issuer")), source)
def claims_valid(+source: J.Json) -> Bool:
  +claims = J.get(source, "claims")
  (J.is_object(J.get(source, "previous")) || J.is_object(claims)) &&
    (J.same(claims, J.Null{}) || (nonempty(J.get(claims, "sub")) &&
    (Bool.not(has(source, "subject")) || J.same(J.get(claims, "sub"), J.get(source, "subject"))) &&
    (Bool.not(has(claims, "azp")) || J.same(J.get(claims, "azp"), J.get(source, "clientId")))))
def token_subject_claims(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT identity verification failed; sign in again")
    case True{}: Model.success(select(J.is_object(J.get(source, "claims")), J.get(J.get(source, "claims"), "sub"), J.get(J.get(source, "previous"), "subject")))
def token_subject_grant(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("ChatGPT returned an invalid token grant")
    case True{}: token_subject_claims(claims_valid(source), source)
def token_subject(+source: J.Json) -> J.Json:
  token_subject_grant(token_grant(source), source)
def registration_record(+source: J.Json) -> J.Json:
  Model.success(J.Object{Con{J.Field{"format", J.Text{"selvedge-chatgpt-registration-1"}}, Con{J.Field{"issuer", J.get(source, "issuer")}, Con{J.Field{"client_id", J.get(source, "clientId")}, Con{J.Field{"subject", J.get(J.get(source, "registered"), "subject")}, Nil{}}}}}})
def replace(fields: +List<J.Field>, +name: String, +value: J.Json) -> +List<J.Field>:
  match fields:
    case Nil{}: Nil{}
    case Con{J.Field{+key, item}, rest}: Con{J.Field{key, select(String.eq(key, name), value, item)}, replace(rest, name, value)}
def registration_subject(+source: J.Json) -> J.Json:
  Model.success(J.Object{replace(fields(J.get(source, "registered")), "subject", J.get(J.get(source, "saved"), "subject"))})
def callback_body(action: String) -> String:
  match action:
    case "accept": "ChatGPT authorization received. Return to the terminal."
    case "reject": "ChatGPT authorization failed. Return to the terminal."
    case _: ""
def callback_headers(action: String) -> J.Json:
  match action:
    case "accept": J.Object{Con{J.Field{"content-type", J.Text{"text/plain"}}, Con{J.Field{"cache-control", J.Text{"no-store"}}, Nil{}}}}
    case _: J.Object{Nil{}}
def callback_action(+action: String, status: Nat, received: Bool, message: String, client_id: J.Json) -> J.Json:
  Model.success(J.Object{Con{J.Field{"action", J.Text{action}}, Con{J.Field{"status", J.nat(status)}, Con{J.Field{"received", J.Boolean{received}}, Con{J.Field{"message", J.Text{message}}, Con{J.Field{"clientId", client_id}, Con{J.Field{"body", J.Text{callback_body(action)}}, Con{J.Field{"headers", callback_headers(action)}, Nil{}}}}}}}}})
def first(items: +List<J.Json>) -> J.Json:
  match items:
    case Nil{}: J.Null{}
    case Con{head, tail}: head
def parameter(source: J.Json, key: String) -> +List<J.Json>:
  J.items(J.get(J.get(source, "parameters"), key))
def callback_bound(+source: J.Json) -> Bool:
  J.same(J.get(J.get(source, "request"), "method"), J.Text{"GET"}) &&
  J.same(J.get(J.get(source, "request"), "host"), J.get(J.get(source, "redirect"), "host")) &&
  J.same(J.get(J.get(source, "url"), "origin"), J.get(J.get(source, "redirect"), "origin")) &&
  Nat.is_le(List.length(&2, J.Json, parameter(source, "code")), 1n) && Nat.is_le(List.length(&2, J.Json, parameter(source, "state")), 1n) &&
  Nat.is_le(List.length(&2, J.Json, parameter(source, "client_id")), 1n) && Nat.is_le(List.length(&2, J.Json, parameter(source, "error")), 1n) &&
  J.same(first(parameter(source, "state")), J.get(source, "state"))
def callback_client_check(valid: Bool, id: J.Json) -> J.Json:
  match valid:
    case True{}: callback_action("accept", 200n, True{}, "", id)
    case False{}: callback_action("reject", 400n, True{}, "Invalid ChatGPT issued client", J.Null{})

def callback_client(+source: J.Json, +id: J.Json) -> J.Json:
  callback_client_check(nonempty(first(parameter(source, "code"))) && client(id) &&
    (Bool.not(J.is_object(J.get(source, "registered"))) || J.same(id, J.get(J.get(source, "registered"), "client_id"))), id)
def callback_error(error: Bool, +source: J.Json) -> J.Json:
  match error:
    case True{}: callback_action("reject", 400n, True{}, "ChatGPT authorization was declined or failed", J.Null{})
    case False{}: callback_client(source, select(J.same(first(parameter(source, "client_id")), J.Null{}), J.get(J.get(source, "registered"), "client_id"), first(parameter(source, "client_id"))))
def callback_binding(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: callback_action("reject", 400n, False{}, "Invalid ChatGPT authorization callback", J.Null{})
    case True{}: callback_error(Nat.is_gt(List.length(&2, J.Json, parameter(source, "error")), 0n), source)
def callback_received(received: Bool, +source: J.Json) -> J.Json:
  match received:
    case True{}: callback_action("ignore", 409n, False{}, "", J.Null{})
    case False{}: callback_binding(callback_bound(source), source)
def callback_path(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: callback_action("ignore", 404n, False{}, "", J.Null{})
    case True{}: callback_received(J.boolean(J.get(source, "received")), source)
def callback_parsed(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: callback_action("ignore", 400n, False{}, "", J.Null{})
    case True{}: callback_path(J.same(J.get(J.get(source, "url"), "pathname"), J.Text{"/auth/callback"}), source)
def callback(+source: J.Json) -> J.Json:
  callback_parsed(parsed(J.get(source, "url")), source)
def cache_catalog_result(valid: Bool, result: J.Json, source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.success(J.Null{})
    case True{}: Model.success(J.Object{Con{J.Field{"models", J.get(result, "value")}, Con{J.Field{"age", J.get(J.get(source, "elapsed"), "value")}, Nil{}}}})
def cache_catalog(+result: J.Json, source: J.Json) -> J.Json:
  cache_catalog_result(J.boolean(J.get(result, "ok")), result, source)
def cache_valid(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.success(J.Null{})
    case True{}: cache_catalog(catalog(J.Object{Con{J.Field{"value", J.get(source, "value")}, Nil{}}}), source)
def elapsed_nonnegative(value: J.Json) -> Bool:
  Model.nonnegative_le(value, "86400000")
def cache(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  cache_valid(J.is_object(value) && J.same(J.get(value, "format"), J.Text{"selvedge-siwc-models-1"}) &&
    J.same(J.get(value, "account_id"), J.get(source, "account")) && J.same(J.get(value, "connection"), J.get(source, "connection")) &&
    J.is_object(J.get(source, "fetched")) && J.is_object(J.get(source, "elapsed")) &&
    elapsed_nonnegative(J.get(J.get(source, "elapsed"), "floor")) &&
    Model.nonnegative_le(J.get(J.get(source, "elapsed"), "ceil"), "86400000"), source)
def cache_fresh(+source: J.Json) -> J.Json:
  Model.success(J.Boolean{Bool.not(J.boolean(J.get(source, "force"))) && J.is_object(J.get(source, "cached")) && Model.nonnegative_le(J.get(J.get(source, "age_measurement"), "floor"), "299999")})
def cache_fallback(+source: J.Json) -> J.Json:
  Model.success(J.Boolean{Bool.not(J.boolean(J.get(source, "force"))) && J.is_object(J.get(source, "cached")) &&
    (J.boolean(J.get(source, "type_error")) || J.same(J.get(source, "error_name"), J.Text{"TimeoutError"}) ||
    J.same(J.get(source, "status"), J.nat(429n)) || number_at_least(J.get(source, "status"), "500"))})
def first_chatgpt(items: +List<J.Field>) -> J.Json:
  match items:
    case Nil{}: J.Null{}
    case Con{J.Field{key, +profile}, rest}: select(J.same(J.get(profile, "provider"), J.Text{"chatgpt"}), profile, first_chatgpt(rest))
def login_account_selected_valid(valid: Bool, profile: J.Json) -> J.Json:
  match valid:
    case True{}: Model.success(profile)
    case False{}: Model.failure("Select a ChatGPT profile or omit the profile to sign in")
def login_account_selected(+profile: J.Json) -> J.Json:
  login_account_selected_valid(J.same(J.get(profile, "provider"), J.Text{"chatgpt"}), profile)
def login_account_disabled(disabled: Bool, +profile: J.Json, +config: J.Json) -> J.Json:
  match disabled:
    case True{}: Model.failure("Automatic ChatGPT account discovery is disabled in this configuration")
    case False{}: Model.success(select(J.is_object(profile), profile, select(J.is_object(J.get(config, "chatgpt")), J.get(config, "chatgpt"), defaults())))

def login_account_default(+profile: J.Json, +config: J.Json) -> J.Json:
  login_account_disabled(J.same(profile, J.Null{}) && J.same(J.get(config, "chatgpt"), J.Boolean{False{}}), profile, config)
def login_account_key(explicit: Bool, key: J.Json, +config: J.Json) -> J.Json:
  match explicit:
    case True{}: login_account_selected(J.get(J.get(config, "profiles"), J.text(key)))
    case False{}: login_account_default(first_chatgpt(fields(J.get(config, "profiles"))), config)
def login_account(+source: J.Json) -> J.Json:
  login_account_key(has(source, "key"), J.get(source, "key"), J.get(source, "config"))
def candidate(profile: J.Json, primary: Bool) -> J.Json:
  J.Object{Con{J.Field{"profile", profile}, Con{J.Field{"primary", J.Boolean{primary}}, Nil{}}}}
def configured_account_step(include: Bool, profile: J.Json, +rest: +List<J.Json>) -> +List<J.Json>:
  match include:
    case True{}: Con{candidate(profile, False{}), rest}
    case False{}: rest
def configured_accounts(items: +List<J.Field>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{J.Field{key, +profile}, rest}: configured_account_step(J.same(J.get(profile, "provider"), J.Text{"chatgpt"}), profile, configured_accounts(rest))
def primary_disabled(disabled: Bool, +config: J.Json) -> +List<J.Json>:
  match disabled:
    case True{}: Nil{}
    case False{}: Con{candidate(select(J.same(J.get(config, "chatgpt"), J.Null{}), defaults(), J.get(config, "chatgpt")), True{}), Nil{}}
def primary_account(+config: J.Json) -> +List<J.Json>:
  primary_disabled(J.same(J.get(config, "chatgpt"), J.Boolean{False{}}), config)
def candidates(source: J.Json) -> J.Json:
  +config = J.get(source, "config")
  Model.success(J.Array{List.append(&2, J.Json, configured_accounts(fields(J.get(config, "profiles"))), primary_account(config))})
def configured_path(items: +List<J.Json>, +path: J.Json) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{+head, rest}: (Bool.not(J.boolean(J.get(head, "primary"))) && J.same(J.get(head, "path"), path)) || configured_path(rest, path)
def candidate_seen(skip: Bool, head: J.Json, +seen: +List<String>) -> +List<String>:
  match skip:
    case True{}: seen
    case False{}: Con{J.text(J.get(head, "identity")), seen}
def candidate_paths_step(skip: Bool, head: J.Json, +rest: +List<J.Json>) -> +List<J.Json>:
  match skip:
    case True{}: rest
    case False{}: Con{J.get(head, "profile"), rest}
def candidate_paths_go(items: +List<J.Json>, +all: +List<J.Json>, +seen: +List<String>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+head, rest}:
      +skip = (J.boolean(J.get(head, "primary")) && configured_path(all, J.get(head, "path"))) || contains(seen, J.text(J.get(head, "identity")))
      candidate_paths_step(skip, head, candidate_paths_go(rest, all, candidate_seen(skip, head, seen)))
def candidate_paths(source: J.Json) -> J.Json:
  +items = J.items(J.get(source, "candidates"))
  Model.success(J.Array{candidate_paths_go(items, items, Nil{})})
def effort_seen(known: Bool, effort: String, +seen: +List<String>) -> +List<String>:
  match known:
    case True{}: seen
    case False{}: Con{effort, seen}
def distinct_effort_step(known: Bool, effort: String, +rest: +List<String>) -> +List<String>:
  match known:
    case True{}: rest
    case False{}: Con{effort, rest}
def distinct_efforts(items: +List<J.Json>, +seen: +List<String>) -> +List<String>:
  match items:
    case Nil{}: Nil{}
    case Con{head, rest}:
      +effort = J.text(J.get(head, "effort"))
      +known = contains(seen, effort)
      distinct_effort_step(known, effort, distinct_efforts(rest, effort_seen(known, effort, seen)))
def effort_name(+text: String) -> Bool:
  slug(text) && Nat.is_le(utf16(text), 128n) && Bool.not(String.contains(text, ":")) && Nat.is_le(J.utf8_length(text), 64n)
def effort_names(items: +List<String>) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{head, tail}: effort_name(head) && effort_names(tail)
def auto_valid(valid: Bool, +efforts: +List<String>, profile: J.Json, +model: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("Adaptive reasoning requires an evaluator, distinct actual efforts, a supported baseline, transport, and a lease bound of 1..10")
    case True{}: Model.success(J.Object{List.append(&2, J.Field, fields(profile), Con{J.Field{"adaptive_reasoning", J.Object{Con{J.Field{"evaluator", J.Text{"jev"}}, Con{J.Field{"efforts", J.Array{J.text_items(efforts)}}, Con{J.Field{"baseline", select(contains(efforts, J.text(J.get(model, "default_reasoning_level"))), J.get(model, "default_reasoning_level"), first(J.text_items(efforts)))}, Con{J.Field{"transport", J.Text{"configuration_update"}}, Con{J.Field{"max_lease", J.nat(10n)}, Nil{}}}}}}}}, Nil{}})})
def auto_available(available: Bool, +efforts: +List<String>, profile: J.Json, model: J.Json) -> J.Json:
  match available:
    case False{}: Model.success(J.Null{})
    case True{}: auto_valid(Nat.is_le(List.length(&2, String, efforts), 16n) && effort_names(efforts), efforts, profile, model)
def auto_efforts(+efforts: +List<String>, profile: J.Json, model: J.Json) -> J.Json:
  auto_available(Nat.is_gt(List.length(&2, String, efforts), 0n) && Bool.not(contains(efforts, "auto")), efforts, profile, model)
def auto_candidate(candidate: Bool, profile: J.Json, +model: J.Json) -> J.Json:
  match candidate:
    case False{}: Model.success(J.Null{})
    case True{}: auto_efforts(distinct_efforts(J.items(J.get(model, "supported_reasoning_levels")), Nil{}), profile, model)
def auto_preset(+source: J.Json) -> J.Json:
  +model = J.get(source, "descriptor")
  auto_candidate(J.same(J.get(model, "slug"), J.Text{"gpt-6-astra"}) && is_array(J.get(model, "supported_reasoning_levels")), J.get(source, "profile"), model)
def selectable_step(include: Bool, model: J.Json, +rest: +List<J.Json>) -> +List<J.Json>:
  match include:
    case True{}: Con{model, rest}
    case False{}: rest

def codex_auto_review_descriptor(+model: J.Json) -> Bool:
  J.same(J.get(model, "slug"), J.Text{Domain.codex_auto_review_model()}) &&
    (J.same(J.get(model, "visibility"), J.Text{"list"}) || J.same(J.get(model, "visibility"), J.Text{"hide"}))

def selectable(items: +List<J.Json>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+head, tail}: selectable_step(J.same(J.get(head, "visibility"), J.Text{"list"}) && Bool.not(codex_auto_review_descriptor(head)), head, selectable(tail))

def codex_auto_review_models(items: +List<J.Json>) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+model, rest}: selectable_step(codex_auto_review_descriptor(model), model, codex_auto_review_models(rest))

def codex_auto_review_info(+model: J.Json) -> J.Json:
  +low = contains(distinct_efforts(J.items(J.get(model, "supported_reasoning_levels")), Nil{}), "low")
  select(low,
    J.Object{Con{J.Field{"default_reasoning_level", J.Text{"low"}}, project(fields(model),
      ["slug", "display_name", "visibility", "priority", "supported_reasoning_levels", "context_window", "effective_context_window_percent"])}}, model)
def model_profile(+source: J.Json, +model: J.Json) -> J.Json:
  J.Object{List.append(&2, J.Field, fields(J.get(source, "connection")), Con{J.Field{"model", J.get(model, "slug")}, Con{J.Field{"bound_account_id", J.get(J.get(source, "result"), "account_id")}, Con{J.Field{"model_info", model}, Nil{}}}})}
def auto_field(include: Bool, key: String, profile: J.Json) -> +List<J.Field>:
  match include:
    case True{}: Con{J.Field{key, profile}, Nil{}}
    case False{}: Nil{}
def materialize_auto_valid(valid: Bool, +auto: J.Json, source: J.Json, generated: +List<J.Field>, +key: String) -> J.Json:
  match valid:
    case False{}: auto
    case True{}: Model.success(J.Object{List.append(&2, J.Field, generated, auto_field(J.is_object(J.get(auto, "value")) && Bool.not(has(J.get(J.get(source, "config"), "profiles"), key)), key, J.get(auto, "value")))})
def materialize_auto(+auto: J.Json, source: J.Json, generated: +List<J.Field>, key: String) -> J.Json:
  materialize_auto_valid(J.boolean(J.get(auto, "ok")), auto, source, generated, key)
def materialize_conflict(conflict: Bool, +source: J.Json, +model: J.Json, generated: +List<J.Field>, +key: String) -> J.Json:
  match conflict:
    case True{}: Model.failure("A configured profile conflicts with an account model")
    case False{}: materialize_auto(auto_preset(J.Object{Con{J.Field{"profile", model_profile(source, model)}, Con{J.Field{"descriptor", model}, Nil{}}}}), source, List.append(&2, J.Field, generated, Con{J.Field{key, model_profile(source, model)}, Nil{}}), key ++ "-auto")
def materialize_model(+source: J.Json, model: J.Json, generated: +List<J.Field>, +key: String) -> J.Json:
  materialize_conflict(has(J.get(J.get(source, "config"), "profiles"), key), source, model, generated, key)
def materialize_accumulate_ok(valid: Bool, +accumulated: J.Json, +source: J.Json, +model: J.Json) -> J.Json:
  match valid:
    case False{}: accumulated
    case True{}: materialize_model(source, model, fields(J.get(accumulated, "value")), J.text(J.get(source, "namespace")) ++ "/" ++ J.text(J.get(model, "slug")))
def materialize_accumulate(+accumulated: J.Json, source: J.Json, model: J.Json) -> J.Json:
  materialize_accumulate_ok(J.boolean(J.get(accumulated, "ok")), accumulated, source, model)
def materialize_models(items: +List<J.Json>, +source: J.Json, +accumulated: J.Json) -> J.Json:
  match items:
    case Nil{}: accumulated
    case Con{model, rest}: materialize_models(rest, source, materialize_accumulate(accumulated, source, model))

def same_reviewer_connection(+profile: J.Json, +source: J.Json, +configured_path: J.Json) -> Bool:
  +connection = J.get(profile_connection(J.Object{[J.Field{"profile", profile}]}), "value")
  +selected = J.get(source, "connection")
  +auth_path = J.get(source, "auth_path")
  J.same(J.get(profile, "provider"), J.Text{"chatgpt"}) &&
    J.same(J.get(connection, "endpoint"), J.get(selected, "endpoint")) &&
    J.same(J.get(connection, "issuer"), J.get(selected, "issuer")) &&
    nonempty(auth_path) && nonempty(configured_path) && J.same(auth_path, configured_path) &&
    (Bool.not(has(profile, "bound_account_id")) ||
      J.same(J.get(profile, "bound_account_id"), J.get(J.get(source, "result"), "account_id")))

def configured_reviewer_alias(available: Bool, +source: J.Json, model: J.Json, key: String, +accumulated: J.Json) -> J.Json:
  match available:
    case False{}: accumulated
    case True{}: materialize_model(source, model, fields(J.get(accumulated, "value")),
      key ++ "/" ++ Domain.codex_auto_review_model() ++ "/" ++ String.drop(J.text(J.get(source, "namespace")), 8n))

def configured_reviewer_aliases(items: +List<J.Field>, +source: J.Json, +model: J.Json, +accumulated: J.Json) -> J.Json:
  match items:
    case Nil{}: accumulated
    case Con{J.Field{+key, +profile}, rest}:
      configured_reviewer_aliases(rest, source, model,
        configured_reviewer_alias(J.boolean(J.get(accumulated, "ok")) &&
          same_reviewer_connection(profile, source, J.get(J.get(source, "configured_auth_paths"), key)) &&
          Bool.not(J.same(J.get(profile, "model"), J.Text{Domain.codex_auto_review_model()})), source, model, key, accumulated))

def materialize_reviewers(items: +List<J.Json>, +source: J.Json, accumulated: J.Json) -> J.Json:
  match items:
    case Nil{}: accumulated
    case Con{+model, rest}: materialize_reviewers(rest, source,
      configured_reviewer_aliases(fields(J.get(J.get(source, "config"), "profiles")), source, model,
        materialize_accumulate(accumulated, source, model)))

def configured_namespace_discovered(+key: String, +profile: J.Json, +configured_path: J.Json, items: +List<J.Json>) -> Bool:
  match items:
    case Nil{}: False{}
    case Con{+discovery, rest}:
      (String.starts_with(key, J.text(J.get(discovery, "namespace")) ++ "/") &&
        same_reviewer_connection(profile, discovery, configured_path)) ||
      configured_namespace_discovered(key, profile, configured_path, rest)

def configured_namespace_valid(items: +List<J.Field>, +source: J.Json) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{J.Field{+key, profile}, rest}:
      (Bool.not(Domain.chatgpt_account_profile_key(key)) ||
        configured_namespace_discovered(key, profile, J.get(J.get(source, "configured_auth_paths"), key),
          J.items(J.get(source, "discoveries")))) && configured_namespace_valid(rest, source)

def materialize(+source: J.Json) -> J.Json:
  +models = J.items(J.get(J.get(source, "result"), "models"))
  materialize_reviewers(Std.map(~J.Json, ~J.Json, ~(item => codex_auto_review_info(item)), codex_auto_review_models(models)), source,
    materialize_models(selectable(models), source, Model.success(J.Object{Nil{}})))
def catalog_selectable_nonempty(valid: Bool, models: +List<J.Json>) -> J.Json:
  match valid:
    case True{}: Model.success(J.Array{models})
    case False{}: Model.failure("This ChatGPT account advertised no selectable models")
def catalog_selectable_result(+models: +List<J.Json>) -> J.Json:
  catalog_selectable_nonempty(Nat.is_gt(List.length(&2, J.Json, models), 0n), models)
def catalog_selectable(source: J.Json) -> J.Json:
  catalog_selectable_result(selectable(J.items(J.get(source, "models"))))
def cache_record_value(+source: J.Json) -> J.Json:
  Model.success(J.Object{Con{J.Field{"format", J.Text{"selvedge-siwc-models-1"}}, Con{J.Field{"account_id", J.get(source, "account")}, Con{J.Field{"connection", J.get(source, "connection")}, Con{J.Field{"fetched_at", J.get(J.get(source, "now_date"), "iso")}, Con{J.Field{"models", J.get(source, "models")}, Nil{}}}}}}})
def account_summary(source: J.Json) -> J.Json:
  +result = J.get(source, "result")
  Model.success(J.Object{Con{J.Field{"models", J.nat(List.length(&2, J.Json, selectable(J.items(J.get(result, "models")))))}, Con{J.Field{"cached", J.get(result, "cached")}, Con{J.Field{"stale", J.get(result, "stale")}, Nil{}}}}})

def hex_digit(char: Char) -> Bool:
  Chr{+code} = char
  (U32.is_ge(code, 48) && U32.is_le(code, 57)) || (U32.is_ge(code, 97) && U32.is_le(code, 102))
def uuid_position(separator: Bool, +char: Char, +index: Nat) -> Bool:
  match separator:
    case True{}: U32.is_eq(char_code(char), 45)
    case False{}: hex_digit(char) && (Bool.not(Nat.is_eq(index, 14n)) || U32.is_eq(char_code(char), 52)) &&
      (Bool.not(Nat.is_eq(index, 19n)) || contains(Con{"8", Con{"9", Con{"a", Con{"b", Nil{}}}}}, SCon{char, SNil{}}))
def uuid_char(char: Char, +index: Nat) -> Bool:
  uuid_position(Nat.is_eq(index, 8n) || Nat.is_eq(index, 13n) || Nat.is_eq(index, 18n) || Nat.is_eq(index, 23n), char, index)
def uuid_chars(text: String, +index: Nat) -> Bool:
  match text:
    case SNil{}: Nat.is_eq(index, 36n)
    case SCon{head, tail}: uuid_char(head, index) && uuid_chars(tail, Nat.add(index, 1n))
def host_registration_check(valid: Bool, value: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("Invalid ChatGPT host registration")
    case True{}: Model.success(J.get(value, "ext_agent_host_id"))
def host_registration(source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  host_registration_check(J.is_object(value) && J.same(J.get(value, "format"), J.Text{"selvedge-chatgpt-host-1"}) &&
    Nat.is_eq(List.length(&2, J.Field, fields(value)), 2n) && nonempty(J.get(value, "ext_agent_host_id")) && uuid_chars(String.to_lower(J.text(J.get(value, "ext_agent_host_id"))), 0n), value)
def host_registration_record(source: J.Json) -> J.Json:
  Model.success(J.Object{Con{J.Field{"format", J.Text{"selvedge-chatgpt-host-1"}}, Con{J.Field{"ext_agent_host_id", J.get(source, "ext_agent_host_id")}, Nil{}}}})
def auth_parameters(+source: J.Json) -> J.Json:
  +registered = J.get(source, "registered")
  Model.success(J.Object{Con{J.Field{"response_type", J.Text{"code"}}, Con{J.Field{"resource", J.get(contract(), "resource")}, Con{J.Field{"scope", J.get(contract(), "scopes")}, Con{J.Field{"redirect_uri", J.get(source, "redirectUri")}, Con{J.Field{"state", J.get(source, "state")}, Con{J.Field{"nonce", J.get(source, "nonce")}, Con{J.Field{"code_challenge", J.get(source, "challenge")}, Con{J.Field{"code_challenge_method", J.Text{"S256"}}, Con{J.Field{"ext_agent_host_id", J.get(source, "ext_agent_host_id")}, Con{J.Field{"client_id", select(J.same(J.get(registered, "client_id"), J.Null{}), J.Text{"dynamic_agent_client"}, J.get(registered, "client_id"))}, project_step(Bool.not(J.is_object(registered)), "agent_name_hint", J.Text{"Selvedge"}, Nil{})}}}}}}}}}}})
def unrelated_fields(items: +List<J.Field>, +existing: J.Json) -> +List<J.Field>:
  match items:
    case Nil{}: Nil{}
    case Con{J.Field{+key, value}, rest}: project_step(Bool.not(has(existing, key)), key, value, unrelated_fields(rest, existing))
def overlay_fields(items: +List<J.Field>, +overrides: J.Json) -> +List<J.Field>:
  match items:
    case Nil{}: Nil{}
    case Con{J.Field{+key, value}, rest}: Con{J.Field{key, field(overrides, key, value)}, overlay_fields(rest, overrides)}
def materialized_profiles(+source: J.Json, +config: J.Json) -> J.Json:
  J.Object{List.append(&2, J.Field, overlay_fields(fields(J.get(source, "generated")), J.get(config, "profiles")), unrelated_fields(fields(J.get(config, "profiles")), J.get(source, "generated")))}
def config_materialized_valid(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure_code("account_namespace_mismatch", "A configured ChatGPT account profile could not verify its account connection; use the original account connection or a new profile key")
    case True{}:
      +config = J.get(source, "config")
      +profiles = materialized_profiles(source, config)
      Model.success(J.Object{replace(fields(config), "profiles", profiles)})
def config_materialized(+source: J.Json) -> J.Json:
  config_materialized_valid(configured_namespace_valid(fields(J.get(J.get(source, "config"), "profiles")), source), source)
def catalog_transport_action(unauthorized: Bool, ok: Bool) -> J.Json:
  match unauthorized:
    case True{}: Model.success(J.Text{"refresh"})
    case False{}: Model.success(select(ok, J.Text{"success"}, J.Text{"failure"}))
def catalog_transport(+source: J.Json) -> J.Json:
  catalog_transport_action(J.same(J.get(source, "status"), J.nat(401n)), J.boolean(J.get(source, "ok")))
def cache_size(source: J.Json) -> J.Json:
  Model.success(J.Boolean{Model.nonnegative_le(J.get(source, "size"), "1048576")})
def cache_record_date(valid: Bool, source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure_code("RangeError", "Invalid time value")
    case True{}: cache_record_value(source)
def cache_record(+source: J.Json) -> J.Json:
  cache_record_date(J.is_object(J.get(source, "now_date")), source)
def hash_prefix(source: J.Json) -> J.Json:
  Model.success(J.Text{String.take(J.text(J.get(source, "digest")), 16n)})
def connection_identity(+source: J.Json) -> J.Json:
  Model.success(J.Text{J.text(J.get(source, "models_url")) ++ SCon{Chr{0}, SNil{}} ++ J.text(J.get(J.get(source, "profile"), "issuer"))})
def model_cache_path(+source: J.Json) -> J.Json:
  Model.success(J.Text{J.text(J.get(source, "resolved")) ++ ".models-" ++ J.text(J.get(source, "hash")) ++ ".json"})
def truthy(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: False{}
    case J.Boolean{value}: value
    case J.Number{value}: Bool.not(String.eq(value, "0"))
    case J.Text{value}: Bool.not(String.is_empty(value))
    case _: True{}
def optional_registration_present(present: Bool, source: J.Json) -> J.Json:
  match present:
    case False{}: Model.success(J.Null{})
    case True{}: registration(source)
def optional_registration(+source: J.Json) -> J.Json:
  optional_registration_present(truthy(J.get(source, "value")), source)
def host_saved_present(present: Bool, source: J.Json) -> J.Json:
  match present:
    case False{}: Model.success(J.Null{})
    case True{}: host_registration(source)
def host_saved(+source: J.Json) -> J.Json:
  host_saved_present(truthy(J.get(source, "value")), source)
def sdk_timeout(+source: J.Json) -> J.Json:
  Model.success(select(J.same(J.get(J.get(source, "profile"), "timeout_ms"), J.Null{}), J.Number{"300000"}, J.get(J.get(source, "profile"), "timeout_ms")))
def authorization_view(source: J.Json) -> J.Json:
  +credential = J.get(source, "credential")
  Model.success(J.Object{Con{J.Field{"account_id", J.get(credential, "account_id")}, Con{J.Field{"headers", J.Object{Con{J.Field{"authorization", J.Text{"Bearer " ++ J.text(J.get(credential, "access_token"))}}, Nil{}}}}, Nil{}}}})
def login_result(+source: J.Json) -> J.Json:
  +saved = J.get(source, "saved")
  Model.success(J.Object{Con{J.Field{"account_id", J.get(saved, "account_id")}, Con{J.Field{"filename", J.get(source, "filename")}, Con{J.Field{"name", J.get(saved, "name")}, Con{J.Field{"email", J.get(saved, "email")}, Nil{}}}}}})
def catalog_result(+source: J.Json) -> J.Json:
  Model.success(J.Object{Con{J.Field{"account_id", J.get(J.get(source, "authorization"), "account_id")}, Con{J.Field{"models", select(J.boolean(J.get(source, "cached_result")), J.get(J.get(source, "cached"), "models"), J.get(source, "models"))}, Con{J.Field{"cached", J.get(source, "cached_result")}, Con{J.Field{"stale", J.get(source, "stale")}, Nil{}}}}}})
def catalog_failure(source: J.Json) -> J.Json:
  Model.failure("ChatGPT model discovery failed with HTTP " ++ number_text(J.get(source, "status")))
def materialization_notice(stale: Bool, reviewer_available: Bool) -> J.Json:
  match stale reviewer_available:
    case False{} True{}: J.Null{}
    case True{} True{}: J.Text{"ChatGPT is temporarily unavailable; using this account’s cached model catalog"}
    case False{} False{}: J.Text{"This ChatGPT connection does not advertise codex-auto-review; automatic review defaults to the task model unless a reviewer is selected explicitly"}
    case True{} False{}: J.Text{"ChatGPT is temporarily unavailable; using this account’s cached model catalog. This connection does not advertise codex-auto-review; automatic review defaults to the task model unless a reviewer is selected explicitly"}

def materialization_diagnostic(+source: J.Json) -> J.Json:
  Model.success(materialization_notice(J.boolean(J.get(J.get(source, "result"), "stale")),
    Bool.not(List.is_empty(&2, J.Json, codex_auto_review_models(J.items(J.get(J.get(source, "result"), "models")))))))
def materialization_failure(+source: J.Json) -> J.Json:
  Model.success(J.Object{Con{J.Field{"rethrow", J.get(source, "force")}, Con{J.Field{"message", J.get(source, "message")}, Nil{}}}})
def token_times_earliest(valid: Bool) -> J.Json:
  match valid:
    case False{}: Model.failure("Invalid ChatGPT token refresh time")
    case True{}: Model.success(J.Null{})
def token_times_expiry(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure_code("RangeError", "Invalid time value")
    case True{}: token_times_earliest(J.same(J.get(J.get(source, "tokens"), "earliest_refresh_at"), J.Null{}) || J.is_text(J.get(J.get(source, "earliest"), "iso")))
def token_times(+source: J.Json) -> J.Json:
  token_times_expiry(J.is_object(J.get(source, "expires")), source)
def candidate_identity(+source: J.Json) -> J.Json:
  Model.success(J.Text{J.text(J.get(source, "resolved")) ++ SCon{Chr{0}, SNil{}} ++ J.text(J.get(source, "connection"))})
def account_namespace(source: J.Json) -> J.Json:
  Model.success(J.Text{"chatgpt/" ++ J.text(J.get(source, "hash"))})
def cache_error_fatal(fatal: Bool) -> J.Json:
  match fatal:
    case True{}: Model.failure("Cannot read the ChatGPT model cache")
    case False{}: Model.success(J.Null{})
def cache_error(+source: J.Json) -> J.Json:
  cache_error_fatal(truthy(J.get(source, "code")) && Bool.not(J.same(J.get(source, "code"), J.Text{"ENOENT"})))
def token_expiration_decision(valid: Bool) -> J.Json:
  match valid:
    case False{}: Model.failure_code("RangeError", "Invalid time value")
    case True{}: Model.success(J.Null{})
def token_expiration(source: J.Json) -> J.Json:
  token_expiration_decision(J.is_object(J.get(source, "expires")))
def record_read_failure(+source: J.Json) -> J.Json:
  Model.success(J.Boolean{J.boolean(J.get(source, "optional")) && J.same(J.get(source, "code"), J.Text{"ENOENT"})})
def catalog_fetch_failure(source: J.Json) -> J.Json:
  Model.success(J.Text{"Could not fetch the ChatGPT model catalog"})
def authorize_prompt(+source: J.Json) -> J.Json:
  Model.success(J.Object{Con{J.Field{"url", J.get(source, "url")}, Con{J.Field{"redirect_uri", J.get(source, "redirectUri")}, Nil{}}}})
def code_grant_checks(+source: J.Json) -> J.Json:
  Model.success(J.Object{Con{J.Field{"expectedNonce", J.get(source, "nonce")}, Con{J.Field{"expectedState", J.get(source, "state")}, Con{J.Field{"idTokenExpected", J.Boolean{True{}}}, Con{J.Field{"pkceCodeVerifier", J.get(source, "verifier")}, Nil{}}}}}})
def candidate_read_action(action: String, source: J.Json) -> J.Json:
  Model.success(J.Object{Con{J.Field{"action", J.Text{action}}, Con{J.Field{"candidate", J.get(source, "candidate")}, Nil{}}}})
def candidate_read_error(missing: Bool, +source: J.Json) -> J.Json:
  match missing:
    case True{}: candidate_read_action("skip", source)
    case False{}: candidate_read_action("fail", source)
def candidate_read_observed(ok: Bool, +source: J.Json) -> J.Json:
  match ok:
    case True{}: candidate_read_action("accept", source)
    case False{}: candidate_read_error(J.same(J.get(J.get(J.get(source, "read"), "error"), "code"), J.Text{"ENOENT"}), source)
def candidate_read(+source: J.Json) -> J.Json:
  candidate_read_observed(J.boolean(J.get(J.get(source, "read"), "ok")), source)
# NOTE: Boolean routes avoid the pinned checker expanding long string literal patterns.
def meaning_route_60(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: models_url(source)
    case False{}: Model.failure("Unknown host model operation: " ++ operation)

def meaning_route_59(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: catalog(source)
    case False{}: meaning_route_60(String.eq(operation, "account.models_url"), operation, source)

def meaning_route_58(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: refresh(source)
    case False{}: meaning_route_59(String.eq(operation, "account.catalog"), operation, source)

def meaning_route_57(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: token(source)
    case False{}: meaning_route_58(String.eq(operation, "account.refresh"), operation, source)

def meaning_route_56(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: discovery(source)
    case False{}: meaning_route_57(String.eq(operation, "account.token"), operation, source)

def meaning_route_55(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: registration(source)
    case False{}: meaning_route_56(String.eq(operation, "account.discovery"), operation, source)

def meaning_route_54(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: credential(source)
    case False{}: meaning_route_55(String.eq(operation, "account.registration"), operation, source)

def meaning_route_53(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: connection(source)
    case False{}: meaning_route_54(String.eq(operation, "account.credential"), operation, source)

def meaning_route_52(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(J.Boolean{J.same(J.get(J.get(source, "url"), "protocol"), J.Text{"http:"}) && loopback(J.get(source, "url"))})
    case False{}: meaning_route_53(String.eq(operation, "account.connection"), operation, source)

def meaning_route_51(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(J.Boolean{J.same(J.get(J.get(source, "url"), "protocol"), J.Text{"http:"})})
    case False{}: meaning_route_52(String.eq(operation, "account.insecure"), operation, source)

def meaning_route_50(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: account_summary(source)
    case False{}: meaning_route_51(String.eq(operation, "account.http"), operation, source)

def meaning_route_49(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: cache_record(source)
    case False{}: meaning_route_50(String.eq(operation, "account.account_summary"), operation, source)

def meaning_route_48(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: catalog_selectable(source)
    case False{}: meaning_route_49(String.eq(operation, "account.cache_record"), operation, source)

def meaning_route_47(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: materialize(source)
    case False{}: meaning_route_48(String.eq(operation, "account.catalog_selectable"), operation, source)

def meaning_route_46(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: auto_preset(source)
    case False{}: meaning_route_47(String.eq(operation, "account.materialize"), operation, source)

def meaning_route_45(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: candidate_paths(source)
    case False{}: meaning_route_46(String.eq(operation, "account.auto_preset"), operation, source)

def meaning_route_44(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: candidates(source)
    case False{}: meaning_route_45(String.eq(operation, "account.candidate_paths"), operation, source)

def meaning_route_43(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: login_account(source)
    case False{}: meaning_route_44(String.eq(operation, "account.candidates"), operation, source)

def meaning_route_42(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: cache_fallback(source)
    case False{}: meaning_route_43(String.eq(operation, "account.login_account"), operation, source)

def meaning_route_41(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: cache_fresh(source)
    case False{}: meaning_route_42(String.eq(operation, "account.cache_fallback"), operation, source)

def meaning_route_40(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: cache(source)
    case False{}: meaning_route_41(String.eq(operation, "account.cache_fresh"), operation, source)

def meaning_route_39(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: callback(source)
    case False{}: meaning_route_40(String.eq(operation, "account.cache"), operation, source)

def meaning_route_38(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: registration_subject(source)
    case False{}: meaning_route_39(String.eq(operation, "account.callback"), operation, source)

def meaning_route_37(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: registration_record(source)
    case False{}: meaning_route_38(String.eq(operation, "account.registration_subject"), operation, source)

def meaning_route_36(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: token_subject(source)
    case False{}: meaning_route_37(String.eq(operation, "account.registration_record"), operation, source)

def meaning_route_35(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: issuer_admission(source)
    case False{}: meaning_route_36(String.eq(operation, "account.token_subject"), operation, source)

def meaning_route_34(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: profile_connection(source)
    case False{}: meaning_route_35(String.eq(operation, "account.issuer_admission"), operation, source)

def meaning_route_33(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: cache_size(source)
    case False{}: meaning_route_34(String.eq(operation, "account.profile_connection"), operation, source)

def meaning_route_32(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: catalog_transport(source)
    case False{}: meaning_route_33(String.eq(operation, "account.cache_size"), operation, source)

def meaning_route_31(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: config_materialized(source)
    case False{}: meaning_route_32(String.eq(operation, "account.catalog_transport"), operation, source)

def meaning_route_30(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: auth_parameters(source)
    case False{}: meaning_route_31(String.eq(operation, "account.config_materialized"), operation, source)

def meaning_route_29(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: host_registration_record(source)
    case False{}: meaning_route_30(String.eq(operation, "account.auth_parameters"), operation, source)

def meaning_route_28(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: host_registration(source)
    case False{}: meaning_route_29(String.eq(operation, "account.host_registration_record"), operation, source)

def meaning_route_27(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(contract())
    case False{}: meaning_route_28(String.eq(operation, "account.host_registration"), operation, source)

def meaning_route_26(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: code_grant_checks(source)
    case False{}: meaning_route_27(String.eq(operation, "account.contract"), operation, source)

def meaning_route_25(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: authorize_prompt(source)
    case False{}: meaning_route_26(String.eq(operation, "account.code_grant_checks"), operation, source)

def meaning_route_24(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: catalog_fetch_failure(source)
    case False{}: meaning_route_25(String.eq(operation, "account.authorize_prompt"), operation, source)

def meaning_route_23(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.failure("Invalid ChatGPT OpenID discovery")
    case False{}: meaning_route_24(String.eq(operation, "account.catalog_fetch_failure"), operation, source)

def meaning_route_22(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.failure("ChatGPT token grant or identity verification failed; sign in again")
    case False{}: meaning_route_23(String.eq(operation, "account.discovery_failure"), operation, source)

def meaning_route_21(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.failure("Invalid ChatGPT authentication record; sign in again")
    case False{}: meaning_route_22(String.eq(operation, "account.grant_failure"), operation, source)

def meaning_route_20(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: record_read_failure(source)
    case False{}: meaning_route_21(String.eq(operation, "account.record_parse_failure"), operation, source)

def meaning_route_19(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: refresh_registration(source)
    case False{}: meaning_route_20(String.eq(operation, "account.record_read_failure"), operation, source)

def meaning_route_18(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: refresh_initial(source)
    case False{}: meaning_route_19(String.eq(operation, "account.refresh_registration"), operation, source)

def meaning_route_17(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: cache_error(source)
    case False{}: meaning_route_18(String.eq(operation, "account.refresh_initial"), operation, source)

def meaning_route_16(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: account_namespace(source)
    case False{}: meaning_route_17(String.eq(operation, "account.cache_error"), operation, source)

def meaning_route_15(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: candidate_identity(source)
    case False{}: meaning_route_16(String.eq(operation, "account.account_namespace"), operation, source)

def meaning_route_14(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: model_cache_path(source)
    case False{}: meaning_route_15(String.eq(operation, "account.candidate_identity"), operation, source)

def meaning_route_13(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: connection_identity(source)
    case False{}: meaning_route_14(String.eq(operation, "account.model_cache_path"), operation, source)

def meaning_route_12(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: hash_prefix(source)
    case False{}: meaning_route_13(String.eq(operation, "account.connection_identity"), operation, source)

def meaning_route_11(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: token_expiration(source)
    case False{}: meaning_route_12(String.eq(operation, "account.hash_prefix"), operation, source)

def meaning_route_10(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: token_times(source)
    case False{}: meaning_route_11(String.eq(operation, "account.token_expiration"), operation, source)

def meaning_route_9(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: materialization_failure(source)
    case False{}: meaning_route_10(String.eq(operation, "account.token_times"), operation, source)

def meaning_route_8(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: materialization_diagnostic(source)
    case False{}: meaning_route_9(String.eq(operation, "account.materialization_failure"), operation, source)

def meaning_route_7(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: catalog_failure(source)
    case False{}: meaning_route_8(String.eq(operation, "account.materialization_diagnostic"), operation, source)

def meaning_route_6(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: catalog_result(source)
    case False{}: meaning_route_7(String.eq(operation, "account.catalog_failure"), operation, source)

def meaning_route_5(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: login_result(source)
    case False{}: meaning_route_6(String.eq(operation, "account.catalog_result"), operation, source)

def meaning_route_4(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: authorization_view(source)
    case False{}: meaning_route_5(String.eq(operation, "account.login_result"), operation, source)

def meaning_route_3(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: sdk_timeout(source)
    case False{}: meaning_route_4(String.eq(operation, "account.authorization_view"), operation, source)

def meaning_route_2(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: host_saved(source)
    case False{}: meaning_route_3(String.eq(operation, "account.sdk_timeout"), operation, source)

def meaning_route_1(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: optional_registration(source)
    case False{}: meaning_route_2(String.eq(operation, "account.host_saved"), operation, source)

def meaning_route_0(+accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: candidate_read(source)
    case False{}: meaning_route_1(String.eq(operation, "account.optional_registration"), operation, source)

def meaning(+operation: String, +source: J.Json) -> J.Json:
  meaning_route_0(String.eq(operation, "account.candidate_read"), operation, source)

def factory(+operation: String) -> Model.Adapter((source => meaning(operation, source))):
  Model.adapter((source => meaning(operation, source)), (source => meaning(operation, source)), source => {==})
def run(+operation: String, source: J.Json) -> J.Json:
  Model.execute((candidate => meaning(operation, candidate)), factory(operation), source)
