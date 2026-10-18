import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/stdlib.bend as Std
import ./MODEL.bend as Model

# Pending coordinates are observed from the live Promise map, never a second
# independently updated transport registry.
def number(+value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)

def coordinate(entry: Finite.Entry(Bool)) -> J.Json:
  (key, value) = entry
  J.nat(key)

def label(+source: J.Json) -> String:
  J.text(J.get(source, "label"))

def name(+source: J.Json) -> String:
  J.text(J.get(source, "name"))

def fields_present(fields: +List<J.Field>, +key: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{J.Field{name, value}, rest}: String.eq(name, key) || fields_present(rest, key)

def is_array(+value: J.Json) -> Bool:
  match value:
    case J.Array{items}: True{}
    case _: False{}

def is_natural(value: Maybe<&2, Nat>) -> Bool:
  match value:
    case Some{value}: True{}
    case None{}: False{}

# Issued identities have the exact canonical numeric lexeme of a safe integer.
# Numeric equivalents such as 1e0 never acquire a pending request's authority.
def occupied(found: Maybe<&2, Bool>) -> Bool:
  match found:
    case Some{value}: True{}
    case None{}: False{}

def retired(entries: +List<Finite.Entry(Bool)>, +id: Nat) -> +List<Finite.Entry(Bool)>:
  Finite.remove(~Bool, entries, id)

def action(+kind: String, entries: +List<Finite.Entry(Bool)>, +next_id: Nat, payload: +List<J.Field>) -> J.Json:
  Model.success(J.Object{Con{J.Field{"action", J.Text{kind}}, Con{J.Field{"nextPending", J.Array{Std.map(~Finite.Entry(Bool), ~J.Json, ~coordinate, entries)}}, Con{J.Field{"nextId", J.nat(next_id)}, payload}}}})

def rejection(+source: J.Json, +message: String) -> J.Json:
  Model.failure(message)

# Local diagnostic rendering operates on admitted JSON observations. Peer error
# messages have a separate string-only admission and never use heap coercion.
def truthy(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: False{}
    case J.Boolean{value}: value
    case J.Text{text}: Bool.not(String.eq(text, ""))
    case J.Number{+text}: Bool.not(String.eq(text, "0")) && Bool.not(String.eq(text, "-0"))
    case _: True{}

def optional_field(+present: Bool, +key: String, +value: J.Json, rest: +List<J.Field>) -> +List<J.Field>:
  match present:
    case True{}: Con{J.Field{key, value}, rest}
    case False{}: rest

def coordinates(items: +List<J.Json>) -> +List<Finite.Entry(Bool)>:
  match items:
    case Nil{}: Nil{}
    case Con{+item, +rest}: (number(item), True{}) <> coordinates(rest)

def next(+source: J.Json) -> Nat:
  number(J.get(J.get(source, "state"), "nextId"))

def field_present(+value: J.Json, +key: String) -> Bool:
  match value:
    case J.Object{fields}: fields_present(fields, key)
    case _: False{}

def issued_identity(+value: J.Json) -> Bool:
  Model.safe_integer(value) && is_natural(J.natural(value)) && J.same(value, J.nat(number(value)))

def available_meaning(+source: J.Json) -> J.Json:
  Model.success(J.Boolean{Bool.not(truthy(J.get(J.get(source, "state"), "failure"))) && Bool.not(J.boolean(J.get(J.get(source, "state"), "closing")))})

def pending(+source: J.Json) -> +List<Finite.Entry(Bool)>:
  coordinates(J.items(J.get(J.get(source, "state"), "pending")))

def coordinate_source(items: +List<J.Json>, +limit: Nat) -> Bool:
  match items:
    case Nil{}: True{}
    case Con{+item, +rest}:
      issued_identity(item) && Nat.is_lt(0n, number(item)) && Nat.is_lt(number(item), limit) && Bool.not(occupied(Finite.find(~Bool, coordinates(rest), number(item)))) && coordinate_source(rest, limit)

def correlation(entries: +List<Finite.Entry(Bool)>, +message: J.Json) -> Bool:
  issued_identity(J.get(message, "id")) && occupied(Finite.find(~Bool, entries, number(J.get(message, "id"))))

def exclusive(+message: J.Json) -> Bool:
  Bool.not(J.same_bool(field_present(message, "result"), field_present(message, "error")))

def notification_message(+source: J.Json) -> J.Json:
  J.Object{Con{J.Field{"jsonrpc", J.Text{"2.0"}}, optional_field(field_present(source, "method"), "method", J.get(source, "method"), optional_field(field_present(source, "params"), "params", J.get(source, "params"), Nil{}))}}

def request_message(+source: J.Json) -> J.Json:
  J.Object{Con{J.Field{"jsonrpc", J.Text{"2.0"}}, Con{J.Field{"id", J.nat(next(source))}, optional_field(field_present(source, "method"), "method", J.get(source, "method"), optional_field(field_present(source, "params"), "params", J.get(source, "params"), Nil{}))}}}

def source_category(+source: J.Json) -> Bool:
  J.is_object(source) && J.is_text(J.get(source, "label")) && J.is_text(J.get(source, "name")) &&
    J.is_object(J.get(source, "state")) && is_array(J.get(J.get(source, "state"), "pending")) &&
    issued_identity(J.get(J.get(source, "state"), "nextId")) && Nat.is_lt(0n, next(source)) &&
    coordinate_source(J.items(J.get(J.get(source, "state"), "pending")), next(source))

def unchanged(+kind: String, +source: J.Json, payload: +List<J.Field>) -> J.Json:
  action(kind, pending(source), next(source), payload)

def settle_rejection(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, +error: String) -> J.Json:
  action("reject", retired(pending(source), number(J.get(message, "id"))), next(source), Con{J.Field{"id", J.get(message, "id")}, Con{J.Field{"error", J.Text{error}}, Nil{}}})

def request_identity(+available: Bool, +source: J.Json) -> J.Json:
  match available:
    case False{}: rejection(source, label(source) ++ " request identity exhausted")
    case True{}: action("request", List.append(&2, Finite.Entry(Bool), pending(source), Con{(next(source), True{}), Nil{}}), Nat.add(next(source), 1n), Con{J.Field{"id", J.nat(next(source))}, Con{J.Field{"message", request_message(source)}, Nil{}}})

def finish_correlated(+source: J.Json, member: Categories.Membership<J.Json, Categories.holds(J.Json, (message => correlation(pending(source), message)))>) -> J.Json:
  Categories.Membership{+message, authority} = member
  action("finish", retired(pending(source), number(J.get(message, "id"))), next(source), Con{J.Field{"id", J.get(message, "id")}, Nil{}})

def retirement(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, +reason: String, +error: String, +external: Bool) -> J.Json:
  action("cancel", retired(pending(source), number(J.get(message, "id"))), next(source), Con{J.Field{"id", J.get(message, "id")}, Con{J.Field{"error", J.Text{error}}, Con{J.Field{"externalReason", J.Boolean{external}}, Con{J.Field{"message", J.Object{Con{J.Field{"jsonrpc", J.Text{"2.0"}}, Con{J.Field{"method", J.Text{"notifications/cancelled"}}, Con{J.Field{"params", J.Object{Con{J.Field{"requestId", J.get(message, "id")}, Con{J.Field{"reason", J.Text{reason}}, Nil{}}}}}, Nil{}}}}}}, Nil{}}}}})

def peer_reply(+ping: Bool, +source: J.Json, +id: J.Json) -> J.Json:
  match ping:
    case True{}: unchanged("write", source, Con{J.Field{"message", J.Object{Con{J.Field{"jsonrpc", J.Text{"2.0"}}, Con{J.Field{"id", id}, Con{J.Field{"result", J.Object{Nil{}}}, Nil{}}}}}}, Nil{}})
    case False{}: unchanged("write", source, Con{J.Field{"message", J.Object{Con{J.Field{"jsonrpc", J.Text{"2.0"}}, Con{J.Field{"id", id}, Con{J.Field{"error", J.Object{Con{J.Field{"code", J.Number{"-32601"}}, Con{J.Field{"message", J.Text{"Client method is not supported"}}, Nil{}}}}}, Nil{}}}}}}, Nil{}})

def response_error_text(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, text: Maybe<&2, String>) -> J.Json:
  match text:
    case None{}: settle_rejection(source, message, authority, "Malformed " ++ label(source) ++ " error response")
    case Some{text}: settle_rejection(source, message, authority, label(source) ++ " " ++ name(source) ++ ": " ++ text)

def response_result(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, outcome: {exclusive(message) == True{} : Bool}, +result: Bool) -> J.Json:
  match result:
    case True{}: action("resolve", retired(pending(source), number(J.get(message, "id"))), next(source), Con{J.Field{"id", J.get(message, "id")}, Con{J.Field{"value", J.get(message, "result")}, Nil{}}})
    case False{}: settle_rejection(source, message, authority, "Malformed " ++ label(source) ++ " error response")

def request_capacity(+available: Bool, +source: J.Json) -> J.Json:
  match available:
    case False{}: rejection(source, label(source) ++ " request queue is full")
    case True{}: request_identity(Model.safe_integer(J.get(J.get(source, "state"), "nextId")) && Bool.not(J.same(J.get(J.get(source, "state"), "nextId"), J.Number{"9007199254740991"})), source)

def notification_meaning(+source: J.Json) -> J.Json:
  unchanged("write", source, Con{J.Field{"message", notification_message(source)}, Nil{}})

def write_capacity(+within: Bool, +source: J.Json) -> J.Json:
  match within:
    case False{}: rejection(source, label(source) ++ " outbound queue is full")
    case True{}: unchanged("write", source, Con{J.Field{"message", J.get(source, "message")}, Nil{}})

def frame_capacity(+within: Bool, +source: J.Json) -> J.Json:
  match within:
    case False{}: rejection(source, label(source) ++ " frame exceeds limit")
    case True{}: unchanged("read", source, Nil{})

def finish_admission(+source: J.Json, member: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (message => correlation(pending(source), message)))>>) -> J.Json:
  match member:
    case None{}: unchanged("ignore", source, Nil{})
    case Some{member}: finish_correlated(source, member)

def lifecycle_once(+already: Bool, +kind: String, +source: J.Json) -> J.Json:
  match already:
    case True{}: unchanged("ignore", source, Nil{})
    case False{}: action(kind, Nil{}, next(source), Con{J.Field{"retired", J.Array{Std.map(~Finite.Entry(Bool), ~J.Json, ~coordinate, pending(source))}}, Con{J.Field{"error", J.Text{label(source) ++ " connection closed"}}, Nil{}}})

def peer_request(+has_id: Bool, +ping: Bool, +source: J.Json, +message: J.Json) -> J.Json:
  match has_id:
    case False{}: unchanged("notify", source, Con{J.Field{"message", message}, Nil{}})
    case True{}: peer_reply(ping, source, J.get(message, "id"))

def response_error_message(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, +present: Bool) -> J.Json:
  match present:
    case False{}: settle_rejection(source, message, authority, label(source) ++ " " ++ name(source) ++ ": request failed")
    case True{}: response_error_text(source, message, authority, J.optional_text(J.get(J.get(message, "error"), "message")))

def request_failure(+failed: Bool, +source: J.Json) -> J.Json:
  match failed:
    case True{}: unchanged("external_failure", source, Nil{})
    case False{}: request_capacity(Nat.is_lt(List.length(&2, Finite.Entry(Bool), pending(source)), number(J.get(source, "maxPending"))), source)

def write_frame(+within: Bool, +source: J.Json) -> J.Json:
  match within:
    case False{}: Model.failure_code("range", label(source) ++ " request exceeds frame limit")
    case True{}: write_capacity(Nat.is_le(Nat.add(number(J.get(source, "queuedBytes")), number(J.get(source, "bytes"))), Nat.add(number(J.get(source, "frameLimit")), number(J.get(source, "frameLimit")))), source)

def frame_meaning(+source: J.Json) -> J.Json:
  frame_capacity(Nat.is_le(number(J.get(source, "bytes")), number(J.get(source, "frameLimit"))), source)

def finish_meaning(+source: J.Json) -> J.Json:
  finish_admission(source, Categories.admit(J.Json, (message => correlation(pending(source), message)), J.Object{Con{J.Field{"id", J.get(source, "id")}, Nil{}}}))

def lifecycle_kind(+failed: Bool, +source: J.Json) -> J.Json:
  match failed:
    case True{}: lifecycle_once(truthy(J.get(J.get(source, "state"), "failure")), "fail", source)
    case False{}: lifecycle_once(J.boolean(J.get(J.get(source, "state"), "closing")), "close", source)

def response_error(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, +object: Bool) -> J.Json:
  match object:
    case False{}: settle_rejection(source, message, authority, "Malformed " ++ label(source) ++ " error response")
    case True{}: response_error_message(source, message, authority, field_present(J.get(message, "error"), "message"))

def request_abort(+aborted: Bool, +source: J.Json) -> J.Json:
  match aborted:
    case True{}: unchanged("abort", source, Nil{})
    case False{}: request_failure(truthy(J.get(J.get(source, "state"), "failure")), source)

def write_closed(+closed: Bool, +source: J.Json) -> J.Json:
  match closed:
    case True{}: rejection(source, label(source) ++ " " ++ name(source) ++ " is closed")
    case False{}: write_frame(Nat.is_le(number(J.get(source, "bytes")), number(J.get(source, "frameLimit"))), source)

def lifecycle_meaning(+source: J.Json) -> J.Json:
  lifecycle_kind(String.eq(J.text(J.get(source, "event")), "failure"), source)

def response_value(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, outcome: {exclusive(message) == True{} : Bool}, +error: Bool, +result: Bool) -> J.Json:
  match error:
    case True{}: response_error(source, message, authority, J.is_object(J.get(message, "error")))
    case False{}: response_result(source, message, authority, outcome, result)

# Only an error object with an absent or string message is admitted. Malformed
# correlated errors retire that request with a native diagnostic action.
def request_meaning(+source: J.Json) -> J.Json:
  request_abort(J.boolean(J.get(source, "aborted")), source)

def write_failure(+failed: Bool, +source: J.Json) -> J.Json:
  match failed:
    case True{}: unchanged("external_failure", source, Nil{})
    case False{}: write_closed(J.boolean(J.get(J.get(source, "state"), "closing")), source)

def exclusive_response(+source: J.Json, member: Categories.Membership<J.Json, (message => Categories.intersection(J.Json, Categories.holds(J.Json, (message => correlation(pending(source), message))), Categories.holds(J.Json, (value => exclusive(value))), message))>) -> J.Json:
  Categories.Membership{+message, evidence} = member
  Categories.Intersection{authority, outcome} = evidence
  response_value(source, message, authority, outcome, field_present(message, "error"), field_present(message, "result"))

def write_meaning(+source: J.Json) -> J.Json:
  write_failure(truthy(J.get(J.get(source, "state"), "failure")), source)

def response_outcome(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, member: Maybe<&1, Categories.Membership<J.Json, (message => Categories.intersection(J.Json, Categories.holds(J.Json, (message => correlation(pending(source), message))), Categories.holds(J.Json, (value => exclusive(value))), message))>>) -> J.Json:
  match member:
    case None{}: settle_rejection(source, message, authority, label(source) ++ " response must have exactly one of result or error")
    case Some{member}: exclusive_response(source, member)

def correlated_response(+source: J.Json, member: Categories.Membership<J.Json, Categories.holds(J.Json, (message => correlation(pending(source), message)))>) -> J.Json:
  Categories.Membership{+message, authority} = member
  response_outcome(source, message, authority, Categories.admit_intersection(J.Json, (message => correlation(pending(source), message)), (value => exclusive(value)), message))

def response_admission(+source: J.Json, member: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (message => correlation(pending(source), message)))>>) -> J.Json:
  match member:
    case None{}: unchanged("ignore", source, Nil{})
    case Some{member}: correlated_response(source, member)

def method_message(method: Maybe<&2, String>, +source: J.Json, +message: J.Json) -> J.Json:
  match method:
    case Some{method}: peer_request(field_present(message, "id"), String.eq(method, "ping"), source, message)
    case None{}: response_admission(source, Categories.admit(J.Json, (message => correlation(pending(source), message)), message))

def message_shape(+accepted: Bool, +source: J.Json, +message: J.Json) -> J.Json:
  match accepted:
    case False{}: rejection(source, "Malformed " ++ label(source) ++ " JSON-RPC message")
    case True{}: method_message(J.optional_text(J.get(message, "method")), source, message)

def message_meaning(+source: J.Json) -> J.Json:
  +message = J.get(source, "message")
  message_shape(J.is_object(message) && J.same(J.get(message, "jsonrpc"), J.Text{"2.0"}), source, message)

def diagnostic(+value: J.Json) -> String:
  match value:
    case J.Null{}: "null"
    case J.Boolean{True{}}: "true"
    case J.Boolean{False{}}: "false"
    case J.Text{text}: text
    case J.Number{text}: text
    case J.Object{fields}: "[object Object]"
    case J.Array{items}: "[invalid diagnostic observation]"

def retire_timeout(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, +timeout: Bool) -> J.Json:
  match timeout:
    case True{}: retirement(source, message, authority, "Deadline exceeded", label(source) ++ " request timed out after " ++ diagnostic(J.get(source, "timeoutMs")) ++ " milliseconds; its external outcome may be unknown", False{})
    case False{}: retirement(source, message, authority, "Client cancelled", label(source) ++ " request cancelled", J.boolean(J.get(source, "externalReason")))

def deadline_admission(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, +admitted: Bool) -> J.Json:
  match admitted:
    case False{}: Model.failure("Malformed RPC deadline observation")
    case True{}: retire_timeout(source, message, authority, True{})

type RetireReasonName is Data:
  RetireReasonNameTimeout{}
  RetireReasonNameOther{}

def retire_reason_discriminant(+value: String) -> RetireReasonName:
  Bool.pick(RetireReasonName, String.eq(value, "timeout"), RetireReasonNameTimeout{},
    RetireReasonNameOther{})

def retire_reason_classified(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, +reason: RetireReasonName) -> J.Json:
  match reason:
    case RetireReasonNameTimeout{}: deadline_admission(source, message, authority, issued_identity(J.get(source, "timeoutMs")))
    case RetireReasonNameOther{}: retire_timeout(source, message, authority, False{})

def retire_reason(+source: J.Json, +message: J.Json, authority: {correlation(pending(source), message) == True{} : Bool}, +reason: String) -> J.Json:
  retire_reason_classified(source, message, authority, retire_reason_discriminant(reason))

def retire_correlated(+source: J.Json, member: Categories.Membership<J.Json, Categories.holds(J.Json, (message => correlation(pending(source), message)))>) -> J.Json:
  Categories.Membership{+message, authority} = member
  retire_reason(source, message, authority, J.text(J.get(source, "reason")))

def retire_admission(+source: J.Json, member: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (message => correlation(pending(source), message)))>>) -> J.Json:
  match member:
    case None{}: unchanged("ignore", source, Nil{})
    case Some{member}: retire_correlated(source, member)

def retire_meaning(+source: J.Json) -> J.Json:
  retire_admission(source, Categories.admit(J.Json, (message => correlation(pending(source), message)), J.Object{Con{J.Field{"id", J.get(source, "id")}, Nil{}}}))

def exit_observation(+signal: J.Json, +code: J.Json) -> String:
  match signal:
    case J.Null{}: diagnostic(code)
    case observed_signal: diagnostic(observed_signal)

def exit_closed(+closed: Bool, +source: J.Json) -> J.Json:
  match closed:
    case True{}: unchanged("ignore", source, Nil{})
    case False{}: unchanged("fail", source, Con{J.Field{"error", J.Text{label(source) ++ " " ++ name(source) ++ " exited (" ++ exit_observation(J.get(source, "signal"), J.get(source, "code")) ++ ")"}}, Nil{}})

def exit_code_admitted(+value: J.Json) -> Bool:
  match value:
    case J.Number{text}: True{}
    case J.Null{}: True{}
    case _: False{}

def exit_signal_admitted(+value: J.Json) -> Bool:
  match value:
    case J.Text{text}: True{}
    case J.Null{}: True{}
    case _: False{}

def exit_admission(+source: J.Json, +admitted: Bool) -> J.Json:
  match admitted:
    case False{}: Model.failure("Malformed RPC exit observation")
    case True{}: exit_closed(J.boolean(J.get(J.get(source, "state"), "closing")), source)

def exit_meaning(+source: J.Json) -> J.Json:
  exit_admission(source, field_present(source, "code") && field_present(source, "signal") && exit_code_admitted(J.get(source, "code")) && exit_signal_admitted(J.get(source, "signal")))

def dispatch(+operation: String, +source: J.Json) -> J.Json:
  match operation:
    case "rpc.message": message_meaning(source)
    case "rpc.request": request_meaning(source)
    case "rpc.notification": notification_meaning(source)
    case "rpc.write": write_meaning(source)
    case "rpc.frame": frame_meaning(source)
    case "rpc.retire": retire_meaning(source)
    case "rpc.finish": finish_meaning(source)
    case "rpc.lifecycle": lifecycle_meaning(source)
    case "rpc.exit": exit_meaning(source)
    case "rpc.available": available_meaning(source)
    case unknown: Model.failure("Unknown RPC operation: " ++ unknown)

def admitted_operation(+operation: String, member: Categories.Membership<J.Json, Categories.holds(J.Json, (value => source_category(value)))>) -> J.Json:
  Categories.Membership{+source, evidence} = member
  dispatch(operation, source)

def source_admission(member: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (value => source_category(value)))>>, +operation: String) -> J.Json:
  match member:
    case None{}: Model.failure("Malformed RPC boundary source")
    case Some{member}: admitted_operation(operation, member)

def meaning(+operation: String, +source: J.Json) -> J.Json:
  source_admission(Categories.admit(J.Json, (value => source_category(value)), source), operation)

def operation_adapter(+operation: String) -> Model.Adapter(source => meaning(operation, source)):
  Model.adapter((source => meaning(operation, source)), (source => meaning(operation, source)), (source => {==}))

def run(+operation: String, +source: J.Json) -> J.Json:
  Model.execute((source => meaning(operation, source)), operation_adapter(operation), source)
