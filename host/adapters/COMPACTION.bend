import Base
import ../../harness/context/interactive-markdown.bend as InteractiveMarkdown
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ./MODEL.bend as Model

def choose(accepted: Bool, yes: J.Json, no: J.Json) -> J.Json:
  match accepted:
    case True{}: yes
    case False{}: no

def natural(value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)

def fields(value: J.Json) -> +List<J.Field>:
  match value:
    case J.Object{items}: items
    case _: Nil{}

def put(value: J.Json, name: String, item: J.Json) -> J.Json:
  J.Object{Con{J.Field{name, item}, fields(value)}}

def meter_field(+name: String) -> Bool:
  String.eq(name, "model") || String.eq(name, "input") || String.eq(name, "instructions") ||
    String.eq(name, "tools") || String.eq(name, "tool_choice") || String.eq(name, "parallel_tool_calls")

def compact_field(+name: String) -> Bool:
  String.eq(name, "model") || String.eq(name, "input") || String.eq(name, "instructions")

def choose_field(meter: Bool, +name: String) -> Bool:
  match meter:
    case True{}: meter_field(name)
    case False{}: compact_field(name)

def select_field(accepted: Bool, field: J.Field, rest: +List<J.Field>) -> +List<J.Field>:
  match accepted:
    case True{}: Con{field, rest}
    case False{}: rest

def selected_fields(items: +List<J.Field>, +meter: Bool) -> +List<J.Field>:
  match items:
    case Nil{}: Nil{}
    case Con{J.Field{+name, +value}, rest}:
      select_field(choose_field(meter, name), J.Field{name, value}, selected_fields(rest, meter))

def meter_request(+source: J.Json) -> J.Json:
  J.Object{selected_fields(fields(J.get(source, "request")), True{})}

def compact_request(+source: J.Json) -> J.Json:
  J.Object{selected_fields(fields(J.get(source, "request")), False{})}

def call_history(+plan: J.Json) -> J.Json:
  J.Array{[J.Object{[J.Field{"role", J.Text{"user"}}, J.Field{"content", J.Text{
    J.text(J.get(plan, "prompt")) ++ "\n\nPrevious continuation note:\n" ++ J.text(J.get(plan, "carry")) ++
    "\n\nNext quoted history fragment:\n" ++ J.text(J.get(plan, "chunk"))}}]}]}

def call_effect(+source: J.Json) -> J.Json:
  +effect = J.get(source, "effect")
  +plan = J.get(effect, "plan")
  J.Object{[J.Field{"kind", J.Text{"context_compaction"}}, J.Field{"context_selected", J.Boolean{True{}}}, J.Field{"model", J.get(effect, "model")},
    J.Field{"sampling", J.get(effect, "sampling")}, J.Field{"tools", J.Array{Nil{}}},
    J.Field{"callable", J.Array{Nil{}}}, J.Field{"history", choose(String.eq(J.text(J.get(plan, "method")), "native"), J.Array{InteractiveMarkdown.helper_history(J.items(J.get(plan, "history")))}, call_history(plan))}]}

def portable_request(+source: J.Json) -> J.Json:
  put(J.get(source, "request"), "max_output_tokens", J.get(J.get(J.get(source, "effect"), "plan"), "output_reserve_tokens"))

def maybe_natural(value: Maybe<&2, Nat>) -> Bool:
  match value:
    case Some{number}: True{}
    case None{}: False{}

def natural_json(value: J.Json) -> Bool:
  maybe_natural(J.natural(value))

# DEFENSE: An external token counter can return a nonnumeric or negative count; reject it before using the model window budget.
def meter_result_checked(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("The provider returned an invalid input token count")
    case True{}: Model.success(J.Object{[J.Field{"scope", J.get(source, "scope")},
      J.Field{"input_tokens", J.get(J.get(source, "response"), "input_tokens")}, J.Field{"tokenizer", J.Text{"provider"}}]})

def meter_result(+source: J.Json) -> J.Json:
  meter_result_checked(natural_json(J.get(J.get(source, "response"), "input_tokens")), source)

# DEFENSE: A native compaction response can omit or corrupt its replacement window; reject it before replacing history.
def native_result_checked(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("The native compactor returned an invalid replacement window")
    case True{}: Model.success(J.Object{[J.Field{"action", J.Text{"native"}}, J.Field{"format", J.Text{"native"}},
      J.Field{"scope", J.get(source, "scope")}, J.Field{"items", J.Array{[J.Object{[
        J.Field{"role", J.Text{"model_context"}}, J.Field{"content", J.get(J.get(source, "response"), "output")}]}]}},
      J.Field{"usage", J.get(J.get(source, "response"), "usage")}]})

def is_array(value: J.Json) -> Bool:
  match value:
    case J.Array{items}: True{}
    case _: False{}

def native_result(+source: J.Json) -> J.Json:
  native_result_checked(is_array(J.get(J.get(source, "response"), "output")), source)

def content(parts: +List<J.Json>) -> String:
  match parts:
    case Nil{}: ""
    case Con{part, rest}: J.text(J.get(part, "text")) ++ content(rest)

def summary_value(+item: J.Json) -> J.Json:
  choose(String.eq(J.text(J.get(item, "type")), "provider_receipt"), J.get(item, "item"), item)

def summary_parts(items: +List<J.Json>) -> String:
  match items:
    case Nil{}: ""
    case Con{+item, rest}: content(J.items(J.get(summary_value(J.get(item, "value")), "content"))) ++ summary_parts(rest)

def summary_result(+source: J.Json) -> J.Json:
  Model.success(J.Object{[J.Field{"summary_text", J.Text{summary_parts(J.items(J.get(source, "items")))}},
    J.Field{"scope", J.get(source, "scope")}, J.Field{"usage", J.get(source, "usage")}]})

def scope(+source: J.Json) -> J.Json:
  +profile = J.get(source, "profile")
  Model.success(J.Text{J.stringify(J.Array{[J.get(profile, "provider"), J.get(profile, "endpoint"),
    J.get(source, "model"), J.get(source, "account_id")]})})

def bind_item(scoped: Bool, +item: J.Json, scope: J.Json) -> J.Json:
  match scoped:
    case False{}: item
    case True{}: J.Object{[J.Field{"type", J.Text{"context"}}, J.Field{"part", J.get(item, "part")}, J.Field{"value", J.Object{[
      J.Field{"type", J.Text{"provider_receipt"}}, J.Field{"scope", scope}, J.Field{"item", J.get(item, "value")} ]}}]}

def bind_items(items: +List<J.Json>, +scope: J.Json) -> +List<J.Json>:
  match items:
    case Nil{}: Nil{}
    case Con{+item, rest}: Con{bind_item(String.eq(J.text(J.get(item, "type")), "context"), item, scope), bind_items(rest, scope)}

def bind_output(+source: J.Json) -> J.Json:
  Model.success(J.Array{bind_items(J.items(J.get(source, "items")), J.get(source, "scope"))})

def headers_refresh(refresh: Bool, +source: J.Json) -> J.Json:
  match refresh:
    case True{}: Model.success(J.Text{"refresh"})
    case False{}: Model.success(choose(J.boolean(J.get(source, "ok")), J.Text{"continue"}, J.Text{"read_error"}))

def headers(+source: J.Json) -> J.Json:
  headers_refresh(J.same(J.get(source, "status"), J.nat(401n)) && J.boolean(J.get(source, "authorization")) && Bool.not(J.boolean(J.get(source, "refreshed"))), source)

def scope_changed(+source: J.Json) -> J.Json:
  Model.success(J.Object{[J.Field{"action", J.Text{"scope_changed"}}, J.Field{"scope", J.get(source, "scope")},
    J.Field{"scope_changed", J.Boolean{(J.boolean(J.get(J.get(source, "effect"), "context_selected")) || String.eq(J.text(J.get(J.get(source, "effect"), "kind")), "context_compaction")) && J.is_text(J.get(J.get(source, "effect"), "context_scope")) &&
      Bool.not(J.same(J.get(J.get(source, "effect"), "context_scope"), J.get(source, "scope")))}}]})

# The encoded request itself determines whether bytes can bound input tokens.
# This structural classification is never supplied as a host Boolean promise.
def request_has_opaque_acc(value: J.Json, found: Bool) -> Bool:
  match value:
    case J.Array{Con{head, tail}}:
      request_has_opaque_acc(J.Array{tail}, request_has_opaque_acc(head, found))
    case J.Object{Con{J.Field{+name, +value}, tail}}:
      request_has_opaque_acc(J.Object{tail}, request_has_opaque_acc(value,
        found || (String.eq(name, "image_asset") && J.is_object(value)) || (String.eq(name, "encrypted_content") && J.is_text(value) && Bool.not(String.eq(J.text(value), "")))))
    case _: found

def choose_nat(condition: Bool, yes: Nat, no: Nat) -> Nat:
  match condition:
    case True{}: yes
    case False{}: no

def request_image_count(value: J.Json) -> Nat:
  match value:
    case J.Array{Con{head, tail}}: Nat.add(request_image_count(head), request_image_count(J.Array{tail}))
    case J.Object{Con{J.Field{name, +value}, tail}}:
      Nat.add(choose_nat(String.eq(name, "image_asset") && J.is_object(value), 1n, 0n),
        Nat.add(request_image_count(value), request_image_count(J.Object{tail})))
    case _: 0n

def request_has_images(value: J.Json) -> Bool:
  match value:
    case J.Array{Con{head, tail}}: request_has_images(head) || request_has_images(J.Array{tail})
    case J.Object{Con{J.Field{name, +value}, tail}}:
      (String.eq(name, "image_asset") && J.is_object(value)) || request_has_images(value) || request_has_images(J.Object{tail})
    case _: False{}

def request_has_opaque(value: J.Json) -> Bool:
  request_has_opaque_acc(value, False{})

def measurement_local(+source: J.Json) -> J.Json:
  +plaintext = Bool.not(request_has_opaque(J.get(source, "request")))
  Model.success(J.Object{[J.Field{"action", J.Text{"local"}}, J.Field{"scope", J.get(source, "scope")},
    J.Field{"input_tokens", choose(plaintext && Nat.is_lt(natural(J.get(source, "window_tokens")), natural(J.get(source, "bytes"))), J.get(source, "bytes"), J.get(source, "window_tokens"))},
    J.Field{"tokenizer", choose(plaintext, J.Text{"utf8_upper_bound"}, J.Text{"request_bytes_exceeded"})}]})

def measurement_plan(remote: Bool, +source: J.Json) -> J.Json:
  match remote:
    case True{}: Model.success(J.Object{[J.Field{"action", J.Text{"remote"}}]})
    case False{}: measurement_local(source)

# NOTE: Codex's account client estimates non-original images at ceil(7373 / 4) tokens; the private account transport does not promise the public token-count route.
def account_image_estimate(+source: J.Json) -> J.Json:
  Model.success(J.Object{[J.Field{"action", J.Text{"local"}}, J.Field{"scope", J.get(source, "scope")},
    J.Field{"input_tokens", J.nat(Nat.add(J.utf8_length(J.stringify(J.get(source, "request"))), Nat.mul(1844n, request_image_count(J.get(source, "request")))))},
    J.Field{"tokenizer", J.Text{"codex_image_estimate"}}]})

def measurement_image_account(estimate: Bool, +source: J.Json) -> J.Json:
  match estimate:
    case True{}: account_image_estimate(source)
    case False{}: measurement_plan(Nat.is_le(natural(J.get(source, "bytes")), choose_nat(request_has_images(J.get(source, "request")), 33554432n, natural(J.get(J.get(source, "limits"), "frame_bytes")))), source)

def measurement_request(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("Context measurement requires the complete encoded request")
    case True{}: measurement_image_account(String.eq(J.text(J.get(J.get(source, "profile"), "provider")), "chatgpt") && request_has_images(J.get(source, "request")), source)

def unsupported_route(+source: J.Json) -> Bool:
  Bool.not(J.same(J.get(source, "code"), J.Text{"model_not_found"})) &&
    (J.same(J.get(source, "status"), J.nat(404n)) || J.same(J.get(source, "status"), J.nat(405n)) ||
    J.same(J.get(source, "status"), J.nat(501n)) || (J.same(J.get(source, "status"), J.nat(400n)) &&
    (J.same(J.get(source, "code"), J.Text{"unsupported_route"}) || J.same(J.get(source, "code"), J.Text{"unsupported_endpoint"}) ||
    J.same(J.get(source, "code"), J.Text{"route_not_found"}) || J.same(J.get(source, "code"), J.Text{"not_implemented"}))))

def meter_fallback_checked(allowed: Bool, +source: J.Json) -> J.Json:
  match allowed:
    case False{}: Model.success(J.Object{[J.Field{"action", J.Text{"error"}}]})
    case True{}: Model.success(J.Object{[J.Field{"action", J.Text{"local"}}, J.Field{"scope", J.get(source, "scope")},
      J.Field{"input_tokens", J.get(source, "bytes")}, J.Field{"tokenizer", J.Text{"utf8_upper_bound"}}]})

def meter_fallback_content(opaque: Bool, +source: J.Json) -> J.Json:
  match opaque:
    case True{}: Model.success(J.Object{[J.Field{"action", J.Text{"error"}}]})
    case False{}: meter_fallback_checked(J.is_object(J.get(source, "request")) && unsupported_route(source), source)
# DEFENSE: A compatible provider may explicitly reject its token-count route; use the UTF-8 bound only for a readable request and the listed unsupported-route errors.
def meter_fallback(+source: J.Json) -> J.Json:
  meter_fallback_content(request_has_opaque(J.get(source, "request")), source)

def unsupported_compaction_model(+source: J.Json) -> Bool:
  J.same(J.get(source, "status"), J.nat(400n)) &&
    (J.same(J.get(source, "code"), J.Text{"unsupported_operation"}) ||
    J.same(J.get(source, "code"), J.Text{"operation_not_supported"}) ||
    J.same(J.get(source, "code"), J.Text{"unsupported_model"}) ||
    J.same(J.get(source, "code"), J.Text{"model_not_supported"}) ||
    J.same(J.get(source, "code"), J.Text{"model_not_supported_for_compaction"}) ||
    J.same(J.get(source, "code"), J.Text{"compaction_not_supported"}))

def native_failure_checked(unavailable: Bool) -> J.Json:
  match unavailable:
    case True{}: Model.success(J.Object{[J.Field{"action", J.Text{"native_unavailable"}}]})
    case False{}: Model.success(J.Object{[J.Field{"action", J.Text{"error"}}]})

# DEFENSE: A provider can explicitly report an unsupported native compaction route/model; permit the existing portable method only for those capability failures.
def native_failure(+source: J.Json) -> J.Json:
  native_failure_checked(unsupported_route(source) || unsupported_compaction_model(source))

def budget(+source: J.Json) -> J.Json:
  Model.success(choose(Nat.is_le(Nat.add(natural(J.get(source, "input_tokens")), natural(J.get(J.get(source, "plan"), "output_reserve_tokens"))), natural(J.get(J.get(source, "plan"), "window_tokens"))), J.Text{"dispatch"}, J.Text{"resize"}))

def route_14(accepted: Bool, operation: String, source: J.Json) -> J.Json:
  match accepted:
    case True{}: native_failure(source)
    case False{}: Model.failure("Unknown compaction adapter operation: " ++ operation)
def route_13(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: meter_fallback(source)
    case False{}: route_14(String.eq(operation, "backend.compaction_native_failure"), operation, source)
def route_12(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: scope_changed(source)
    case False{}: route_13(String.eq(operation, "backend.compaction_meter_fallback"), operation, source)
def route_11(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: measurement_request(J.is_object(J.get(source, "request")), source)
    case False{}: route_12(String.eq(operation, "backend.compaction_scope_changed"), operation, source)
def route_10(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: headers(source)
    case False{}: route_11(String.eq(operation, "backend.compaction_measurement_plan"), operation, source)
def route_9(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: bind_output(source)
    case False{}: route_10(String.eq(operation, "backend.compaction_headers"), operation, source)
def route_8(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: scope(source)
    case False{}: route_9(String.eq(operation, "backend.compaction_bind_output"), operation, source)
def route_7(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: budget(source)
    case False{}: route_8(String.eq(operation, "backend.compaction_scope"), operation, source)
def route_6(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: summary_result(source)
    case False{}: route_7(String.eq(operation, "backend.compaction_budget"), operation, source)
def route_5(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: native_result(source)
    case False{}: route_6(String.eq(operation, "backend.compaction_summary_result"), operation, source)
def route_4(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: meter_result(source)
    case False{}: route_5(String.eq(operation, "backend.compaction_native_result"), operation, source)
def route_3(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(portable_request(source))
    case False{}: route_4(String.eq(operation, "backend.compaction_meter_result"), operation, source)
def route_2(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(call_effect(source))
    case False{}: route_3(String.eq(operation, "backend.compaction_portable_request"), operation, source)
def route_1(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(compact_request(source))
    case False{}: route_2(String.eq(operation, "backend.compaction_effect"), operation, source)
def route_0(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(meter_request(source))
    case False{}: route_1(String.eq(operation, "backend.compaction_request"), operation, source)

def meaning_entry(+operation: String, +source: J.Json) -> J.Json:
  route_0(String.eq(operation, "backend.compaction_meter_request"), operation, source)

def family(+operation: String) -> Model.Adapter(source => meaning_entry(operation, source)):
  Model.adapter(source => meaning_entry(operation, source), source => meaning_entry(operation, source), source => {==})

def run(+operation: String, +source: J.Json) -> J.Json:
  Model.execute(source => meaning_entry(operation, source), family(operation), source)

law complete_correspondence:
  @operation:String -> @source:J.Json -> {run(operation, source) == meaning_entry(operation, source) : J.Json}

law opaque_input_has_no_local_token_estimate:
  @source:J.Json -> @opaque:{request_has_opaque(J.get(source, "request")) == True{} : Bool} -> {meter_fallback(source) ==
    Model.success(J.Object{[J.Field{"action", J.Text{"error"}}]}) : J.Json}
