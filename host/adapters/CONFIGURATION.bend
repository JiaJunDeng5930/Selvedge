import Base
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ./MODEL.bend as Model
import ../../harness/DOMAIN.bend as D

# Sources are observations of persisted JSON. Original UTF-16 strings and
# environment bytes remain in host; reconstruction plans select original refs.
def config_select(condition: Bool, yes: J.Json, no: J.Json) -> J.Json:
  match condition:
    case True{}: yes
    case False{}: no

def config_kind(+value: J.Json, +kind: String) -> Bool:
  String.eq(J.text(J.get(value, "kind")), kind)
def config_list_count(values: +List<J.Json>) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{head, rest}: Nat.add(1n, config_list_count(rest))
def config_append(left: +List<J.Json>, +right: +List<J.Json>) -> +List<J.Json>:
  match left:
    case Nil{}: right
    case Con{head, rest}: Con{head, config_append(rest, right)}
def config_units_equal(units: +List<J.Json>, text: String) -> Bool:
  match units text:
    case Nil{} SNil{}: True{}
    case Con{head, rest} SCon{Chr{code}, tail}:
      J.same(head, J.nat(U32.to_nat(code))) && config_units_equal(rest, tail)
    case _ _: False{}
def config_text_equal(+value: J.Json, text: String) -> Bool:
  config_kind(value, "string") && config_units_equal(J.items(J.get(value, "units")), text)
def config_find(entries: +List<J.Json>, +name: String) -> J.Json:
  match entries:
    case Nil{}: J.Null{}
    case Con{+entry, rest}:
      config_select(config_text_equal(J.get(entry, "key"), name), J.get(entry, "value"), config_find(rest, name))
def config_get(+value: J.Json, name: String) -> J.Json:
  config_find(J.items(J.get(value, "fields")), name)
def config_present(value: J.Json) -> Bool:
  Bool.not(J.same(value, J.Null{}))
def config_defined(+value: J.Json) -> Bool:
  config_present(value) && Bool.not(config_kind(value, "undefined"))
def config_ref(value: J.Json) -> J.Json:
  J.Object{Con{J.Field{"ref", J.get(value, "ref")}, Nil{}}}
def config_literal(value: J.Json) -> J.Json:
  J.Object{Con{J.Field{"literal", value}, Nil{}}}
def config_value(+value: J.Json, fallback: J.Json) -> J.Json:
  config_select(config_present(value), config_ref(value), config_literal(fallback))
def config_nullish(+value: J.Json) -> Bool:
  Bool.not(config_defined(value)) || config_kind(value, "null")
def config_parts(text: String) -> +List<J.Json>:
  Con{config_literal(J.Text{text}), Nil{}}
def config_error(parts: +List<J.Json>) -> J.Json:
  J.Object{Con{J.Field{"error", J.Array{parts}}, Con{J.Field{"code", J.Text{"TypeError"}}, Nil{}}}}
def config_failure(text: String) -> J.Json:
  config_error(config_parts(text))
def config_guard(valid: Bool, error: J.Json, next: J.Json) -> J.Json:
  match valid:
    case True{}: next
    case False{}: error

def config_number_text(value: J.Json) -> String:
  match value:
    case J.Number{text}: text
    case _: ""
def config_code_range(+value: J.Json, lower: String, upper: String) -> Bool:
  Model.nonnegative_le(value, upper) && Model.decimal_le(lower, config_number_text(value))
def config_alpha(+code: J.Json) -> Bool:
  config_code_range(code, "65", "90") || config_code_range(code, "97", "122")
def config_digit(code: J.Json) -> Bool:
  config_code_range(code, "48", "57")
def config_code(+code: J.Json, value: String) -> Bool:
  J.same(code, J.Number{value})
def config_name_tail(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+head, rest}:
      (config_alpha(head) || config_digit(head) || config_code(head, "46") ||
        config_code(head, "95") || config_code(head, "47") || config_code(head, "45")) && config_name_tail(rest)
def config_name_units(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{+head, +rest}:
      (config_alpha(head) || config_digit(head)) && config_name_tail(rest) && Nat.is_le(config_list_count(rest), 127n)
def config_name(+value: J.Json) -> Bool:
  config_kind(value, "string") && config_name_units(J.items(J.get(value, "units")))
def config_variable_tail(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+head, rest}:
      (config_alpha(head) || config_digit(head) || config_code(head, "95")) && config_variable_tail(rest)
def config_variable_units(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{+head, rest}:
      (config_alpha(head) || config_code(head, "95")) && config_variable_tail(rest)
def config_variable(+value: J.Json) -> Bool:
  config_kind(value, "string") && config_variable_units(J.items(J.get(value, "units")))
def config_plugin_units(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{head, +rest}:
      config_alpha(head) && config_variable_tail(rest) && Nat.is_le(config_list_count(rest), 63n)
def config_plugin_name(+value: J.Json) -> Bool:
  config_kind(value, "string") && config_plugin_units(J.items(J.get(value, "units")))
def config_space(+code: J.Json) -> Bool:
  config_code_range(code, "9", "13") || config_code(code, "32") || config_code(code, "160") ||
    config_code(code, "5760") || config_code_range(code, "8192", "8202") || config_code(code, "8232") ||
    config_code(code, "8233") || config_code(code, "8239") || config_code(code, "8287") ||
    config_code(code, "12288") || config_code(code, "65279")
def config_content(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{head, rest}: Bool.not(config_space(head)) || config_content(rest)
def config_nonempty(+value: J.Json) -> Bool:
  config_kind(value, "string") && config_content(J.items(J.get(value, "units")))
def config_bound(+value: J.Json, lower: String, upper: String) -> Bool:
  config_kind(value, "number") && Model.safe_integer(J.get(value, "number")) && config_code_range(J.get(value, "number"), lower, upper)
def config_allowed(+key: J.Json, keys: +List<String>) -> Bool:
  match keys:
    case Nil{}: False{}
    case Con{head, rest}: config_text_equal(key, head) || config_allowed(key, rest)
def config_unknown(entries: +List<J.Json>, +keys: +List<String>) -> J.Json:
  match entries:
    case Nil{}: J.Null{}
    case Con{+entry, rest}: config_select(config_allowed(J.get(entry, "key"), keys),
      config_unknown(rest, keys), J.get(entry, "key"))
def config_fields(+value: J.Json, keys: +List<String>) -> Bool:
  config_kind(value, "object") && J.same(config_unknown(J.items(J.get(value, "fields")), keys), J.Null{})
def config_optional_text(+value: J.Json) -> Bool:
  Bool.not(config_defined(value)) || config_nonempty(value)
def config_optional_bound(+value: J.Json, lower: String, upper: String) -> Bool:
  Bool.not(config_defined(value)) || config_bound(value, lower, upper)
def config_strings(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{head, rest}: config_kind(head, "string") && config_strings(rest)
def config_arguments(+value: J.Json) -> Bool:
  Bool.not(config_defined(value)) || (config_kind(value, "array") && config_strings(J.items(J.get(value, "items"))))
def config_env_fields(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{head, rest}: config_kind(J.get(head, "value"), "string") && config_env_fields(rest)
def config_environment(+value: J.Json) -> Bool:
  Bool.not(config_defined(value)) || (config_kind(value, "object") && config_env_fields(J.items(J.get(value, "fields"))))
def configured_instruction(instructions: D.InitialInstructions) -> String:
  D.InitialInstructions{configured, global} = instructions
  configured

def configured_default() -> String:
  configured_instruction(D.default_instructions())

def config_defaults(+source: J.Json) -> J.Json:
  J.Object{[J.Field{"format", J.Text{"selvedge-bend-config-1"}}, J.Field{"host", J.Text{"127.0.0.1"}}, J.Field{"port", J.Number{"7421"}}, J.Field{"max_fork", J.Number{"4"}}, J.Field{"max_descendants", J.Number{"64"}}, J.Field{"instructions", J.Text{configured_default()}}, J.Field{"profiles", J.Object{[J.Field{"demo", J.Object{[J.Field{"provider", J.Text{"echo"}}, J.Field{"model", J.Text{"echo"}}]}}]}}, J.Field{"mcp", J.Object{[]}}, J.Field{"plugins", J.Object{[]}}, J.Field{"skills", J.Array{[]}}]}
def config_head_format(+valid: Bool, +value: J.Json) -> J.Json:
  match valid:
    case True{}: J.Object{[J.Field{"base", J.get(value, "ref")}, J.Field{"fields", J.Array{[J.Object{[J.Field{"key", J.Text{"host"}}, J.Field{"value", config_value(config_get(value, "host"), J.get(config_defaults(J.Null{}), "host"))}]}, J.Object{[J.Field{"key", J.Text{"port"}}, J.Field{"value", config_value(config_get(value, "port"), J.get(config_defaults(J.Null{}), "port"))}]}, J.Object{[J.Field{"key", J.Text{"max_fork"}}, J.Field{"value", config_value(config_get(value, "max_fork"), J.get(config_defaults(J.Null{}), "max_fork"))}]}, J.Object{[J.Field{"key", J.Text{"max_descendants"}}, J.Field{"value", config_value(config_get(value, "max_descendants"), J.get(config_defaults(J.Null{}), "max_descendants"))}]}, J.Object{[J.Field{"key", J.Text{"instructions"}}, J.Field{"value", config_value(config_get(value, "instructions"), J.get(config_defaults(J.Null{}), "instructions"))}]}, J.Object{[J.Field{"key", J.Text{"profiles"}}, J.Field{"value", config_value(config_get(value, "profiles"), J.get(config_defaults(J.Null{}), "profiles"))}]}, J.Object{[J.Field{"key", J.Text{"mcp"}}, J.Field{"value", config_value(config_get(value, "mcp"), J.get(config_defaults(J.Null{}), "mcp"))}]}, J.Object{[J.Field{"key", J.Text{"plugins"}}, J.Field{"value", config_value(config_get(value, "plugins"), J.get(config_defaults(J.Null{}), "plugins"))}]}, J.Object{[J.Field{"key", J.Text{"skills"}}, J.Field{"value", config_value(config_get(value, "skills"), J.get(config_defaults(J.Null{}), "skills"))}]}]}}]}
    case False{}: J.Object{Con{J.Field{"error", J.Array{Con{config_literal(J.Text{"The configuration is not in the current Bend format"}), Nil{}}}}, Con{J.Field{"code", J.Text{"Error"}}, Nil{}}}}
def config_head_unknown(+unknown: J.Json, +value: J.Json) -> J.Json:
  config_guard(J.same(unknown, J.Null{}), config_error(Con{config_literal(J.Text{"Unknown configuration field: "}), Con{config_ref(unknown), Nil{}}}),
    config_head_format(config_text_equal(config_get(value, "format"), J.text(J.get(config_defaults(J.Null{}), "format"))), value))
def config_configuration_head(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  config_guard(config_kind(value, "object"), config_failure("configuration must be an object"),
    config_head_unknown(config_unknown(J.items(J.get(value, "fields")), Con{"format", Con{"host", Con{"port", Con{"max_fork", Con{"max_descendants", Con{"profiles", Con{"chatgpt", Con{"mcp", Con{"plugins", Con{"reasoning_evaluators", Con{"chatgpt_plugin", Con{"instructions", Con{"skills", Nil{}}}}}}}}}}}}}}), value))
def config_configuration_transport(+source: J.Json) -> J.Json:
  +value = J.get(source, "transport")
  config_guard(config_text_equal(J.get(value, "host"), "127.0.0.1") || config_text_equal(J.get(value, "host"), "::1"), config_failure("The local server requires a loopback address"),
    config_guard(config_bound(J.get(value, "port"), "0", "65535"), config_failure("port must be in 0..65535"),
    config_guard(config_bound(J.get(value, "max_fork"), "1", "4294967295"), config_failure("max_fork must be in 1..4294967295"),
    config_guard(config_bound(J.get(value, "max_descendants"), "1", "4294967295"), config_failure("max_descendants must be in 1..4294967295"),
    config_guard(config_kind(J.get(value, "profiles"), "object"), config_failure("profiles must be an object"),
    config_guard(config_kind(J.get(value, "instructions"), "string") && J.boolean(J.get(source, "instructions_well_formed")) && Model.nonnegative_le(J.get(source, "instructions_bytes"), Nat.show(D.project_limit())), config_failure("instructions must be a bounded UTF-8 string"),
    config_guard(config_kind(J.get(value, "skills"), "array") && config_strings(J.items(J.get(J.get(value, "skills"), "items"))) && Nat.is_le(config_list_count(J.items(J.get(J.get(value, "skills"), "items"))), 64n) && J.boolean(J.get(source, "skill_paths_well_formed")), config_failure("skills must contain at most 64 bounded UTF-8 file paths"),
    config_literal(J.Null{}))))))))
def config_label_prefix(+plugin: Bool) -> String:
  match plugin:
    case True{}: "plugin "
    case False{}: "MCP "
def config_label(+plugin: Bool, +name: J.Json) -> +List<J.Json>:
  Con{config_literal(J.Text{config_label_prefix(plugin)}), Con{config_ref(name), Nil{}}}
def config_extension_error_object(+plugin: Bool, +name: J.Json) -> J.Json:
  config_error(config_append(config_parts(""), config_append(config_label(plugin, name), config_parts(" must be an object"))))
def config_extension_error_command(+plugin: Bool, +name: J.Json) -> J.Json:
  config_error(config_append(config_parts(""), config_append(config_label(plugin, name), config_parts(" command must be a nonempty string"))))
def config_extension_error_arguments(+plugin: Bool, +name: J.Json) -> J.Json:
  config_error(config_append(config_parts("Invalid "), config_append(config_label(plugin, name), config_parts(" arguments"))))
def config_extension_error_cwd(+plugin: Bool, +name: J.Json) -> J.Json:
  config_error(config_append(config_parts(""), config_append(config_label(plugin, name), config_parts(" cwd must be a nonempty string"))))
def config_extension_error_timeout(+plugin: Bool, +name: J.Json) -> J.Json:
  config_error(config_append(config_parts(""), config_append(config_label(plugin, name), config_parts(" timeout must be in 100..1800000"))))
def config_extension_error_event_timeout(+plugin: Bool, +name: J.Json) -> J.Json:
  config_error(config_append(config_parts(""), config_append(config_label(plugin, name), config_parts(" event timeout must be in 100..60000"))))
def config_extension_error_event_queue(+plugin: Bool, +name: J.Json) -> J.Json:
  config_error(config_append(config_parts(""), config_append(config_label(plugin, name), config_parts(" event queue must be in 1..4096"))))
def config_extension_error_env(+plugin: Bool, +name: J.Json) -> J.Json:
  config_error(config_append(config_parts("Invalid "), config_append(config_label(plugin, name), config_parts(" environment"))))
def config_extension_keys(plugin: Bool) -> +List<String>:
  match plugin:
    case True{}: Con{"command", Con{"args", Con{"cwd", Con{"env", Con{"timeout_ms", Con{"event_timeout_ms", Con{"event_queue", Nil{}}}}}}}}
    case False{}: Con{"command", Con{"args", Con{"cwd", Con{"env", Con{"timeout_ms", Nil{}}}}}}
def config_extension_unknown(+unknown: J.Json, +plugin: Bool, +name: J.Json, next: J.Json) -> J.Json:
  config_guard(J.same(unknown, J.Null{}), config_error(config_append(config_parts("Unknown "), config_append(config_label(plugin, name), Con{config_literal(J.Text{" field: "}), Con{config_ref(unknown), Nil{}}}))),
    next)
def config_extension_entry(+plugin: Bool, +name: J.Json, +value: J.Json) -> J.Json:
  config_guard(config_kind(value, "object"), config_extension_error_object(plugin, name),
    config_extension_unknown(config_unknown(J.items(J.get(value, "fields")), config_extension_keys(plugin)), plugin, name, config_guard(config_nonempty(config_get(value, "command")), config_extension_error_command(plugin, name),
    config_guard(config_arguments(config_get(value, "args")), config_extension_error_arguments(plugin, name),
    config_guard(config_optional_text(config_get(value, "cwd")), config_extension_error_cwd(plugin, name),
    config_guard(config_optional_bound(config_get(value, "timeout_ms"), "100", "1800000"), config_extension_error_timeout(plugin, name),
    config_guard(Bool.not(plugin) || config_optional_bound(config_get(value, "event_timeout_ms"), "100", "60000"), config_extension_error_event_timeout(plugin, name),
    config_guard(Bool.not(plugin) || config_optional_bound(config_get(value, "event_queue"), "1", "4096"), config_extension_error_event_queue(plugin, name),
    config_guard(config_environment(config_get(value, "env")), config_extension_error_env(plugin, name),
    config_literal(J.Null{}))))))))))
def config_has_error(+value: J.Json) -> Bool:
  J.is_object(value) && Bool.not(J.same(J.get(value, "error"), J.Null{}))
def config_extension_name(+plugin: Bool, +name: J.Json, +value: J.Json) -> J.Json:
  match plugin:
    case True{}: config_guard(config_plugin_name(name), config_error(Con{config_literal(J.Text{"Invalid plugin name: "}), Con{config_ref(name), Nil{}}}),
    config_extension_entry(True{}, name, value))
    case False{}: config_guard(config_nonempty(name), config_failure("MCP server name must be a nonempty string"),
    config_extension_entry(False{}, name, value))
def config_extension_next(rest: +List<J.Json>, failed: Bool, result: J.Json, +plugin: Bool) -> J.Json:
  match rest failed:
    case _ True{}: result
    case Nil{} False{}: config_literal(J.Null{})
    case Con{+head, tail} False{}:
      +next = config_extension_name(plugin, J.get(head, "key"), J.get(head, "value"))
      config_extension_next(tail, config_has_error(next), next, plugin)
def config_extension_entries(+plugin: Bool, values: +List<J.Json>) -> J.Json:
  config_extension_next(values, False{}, config_literal(J.Null{}), plugin)
def config_extensions_plugins(failed: Bool, result: J.Json, +source: J.Json) -> J.Json:
  match failed:
    case True{}: result
    case False{}: config_guard(config_kind(J.get(source, "plugins"), "object"), config_failure("plugins must be an object"),
    config_extension_entries(True{}, J.items(J.get(J.get(source, "plugins"), "fields"))))
def config_extensions_mcp(+source: J.Json) -> J.Json:
  +result = config_extension_entries(False{}, J.items(J.get(J.get(source, "mcp"), "fields")))
  config_extensions_plugins(config_has_error(result), result, source)
def config_configuration_extensions(+source: J.Json) -> J.Json:
  config_guard(config_kind(J.get(source, "mcp"), "object"), config_failure("mcp must be an object"),
    config_extensions_mcp(source))
def config_evaluators(+source: J.Json) -> J.Json:
  config_guard(String.eq(J.text(J.get(source, "kind")), "object") && Model.nonnegative_le(J.get(source, "count"), "32"), config_failure("reasoning_evaluators must be a bounded object"),
    J.get(source, "positions"))
def config_provider_vercel(+entry: J.Json) -> J.Json:
  J.Object{Con{J.Field{"base", J.get(entry, "ref")}, Con{J.Field{"fields", J.Array{Con{J.Object{Con{J.Field{"key", J.Text{"provider"}}, Con{J.Field{"value", config_value(config_get(entry, "provider"), J.Text{"vercel"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"model"}}, Con{J.Field{"value", config_value(config_get(entry, "model"), J.Text{"typesafe-ai/jev"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"endpoint"}}, Con{J.Field{"value", config_value(config_get(entry, "endpoint"), J.Text{"https://ai-gateway.vercel.sh/v1/evaluate"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"api_key_env"}}, Con{J.Field{"value", config_value(config_get(entry, "api_key_env"), J.Text{"JEV_API_KEY"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"timeout_ms"}}, Con{J.Field{"value", config_value(config_get(entry, "timeout_ms"), J.Number{"30000"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"max_attempts"}}, Con{J.Field{"value", config_value(config_get(entry, "max_attempts"), J.Number{"3"})}, Nil{}}}}, Nil{}}}}}}}}}, Nil{}}}}
def config_provider_typesafe(+entry: J.Json) -> J.Json:
  J.Object{Con{J.Field{"base", J.get(entry, "ref")}, Con{J.Field{"fields", J.Array{Con{J.Object{Con{J.Field{"key", J.Text{"provider"}}, Con{J.Field{"value", config_value(config_get(entry, "provider"), J.Text{"typesafe"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"model"}}, Con{J.Field{"value", config_value(config_get(entry, "model"), J.Text{"jev-latest"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"endpoint"}}, Con{J.Field{"value", config_value(config_get(entry, "endpoint"), J.Text{"https://api.typesafe.ai/v1/systemone"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"api_key_env"}}, Con{J.Field{"value", config_value(config_get(entry, "api_key_env"), J.Text{"JEV_API_KEY"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"timeout_ms"}}, Con{J.Field{"value", config_value(config_get(entry, "timeout_ms"), J.Number{"30000"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"max_attempts"}}, Con{J.Field{"value", config_value(config_get(entry, "max_attempts"), J.Number{"3"})}, Nil{}}}}, Nil{}}}}}}}}}, Nil{}}}}
def config_provider_openrouter(+entry: J.Json) -> J.Json:
  J.Object{Con{J.Field{"base", J.get(entry, "ref")}, Con{J.Field{"fields", J.Array{Con{J.Object{Con{J.Field{"key", J.Text{"provider"}}, Con{J.Field{"value", config_value(config_get(entry, "provider"), J.Text{"openrouter"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"model"}}, Con{J.Field{"value", config_value(config_get(entry, "model"), J.Text{"typesafe/jev-1.13"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"endpoint"}}, Con{J.Field{"value", config_value(config_get(entry, "endpoint"), J.Text{"https://openrouter.ai/api/alpha/decisions"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"api_key_env"}}, Con{J.Field{"value", config_value(config_get(entry, "api_key_env"), J.Text{"JEV_API_KEY"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"timeout_ms"}}, Con{J.Field{"value", config_value(config_get(entry, "timeout_ms"), J.Number{"30000"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"max_attempts"}}, Con{J.Field{"value", config_value(config_get(entry, "max_attempts"), J.Number{"3"})}, Nil{}}}}, Nil{}}}}}}}}}, Nil{}}}}
def config_provider_route_2(valid: Bool, +entry: J.Json, +provider: J.Json) -> J.Json:
  match valid:
    case True{}: config_provider_openrouter(entry)
    case False{}: config_failure("Unknown Jev API provider")
def config_provider_route_1(valid: Bool, +entry: J.Json, +provider: J.Json) -> J.Json:
  match valid:
    case True{}: config_provider_typesafe(entry)
    case False{}: config_provider_route_2(config_text_equal(provider, "openrouter"), entry, provider)
def config_provider_route_0(valid: Bool, +entry: J.Json, +provider: J.Json) -> J.Json:
  match valid:
    case True{}: config_provider_vercel(entry)
    case False{}: config_provider_route_1(config_text_equal(provider, "typesafe"), entry, provider)
def config_name_default(+value: J.Json) -> Bool:
  Bool.not(config_present(value)) || config_name(value)
def config_variable_default(+value: J.Json) -> Bool:
  Bool.not(config_present(value)) || config_variable(value)
def config_plan_observed(plan: J.Json, +entry: J.Json) -> J.Json:
  config_guard(config_name_default(config_get(entry, "model")) && config_variable_default(config_get(entry, "api_key_env")), config_failure("Invalid evaluator model or API-key environment variable"), plan)
def config_evaluator_provider_result(failed: Bool, +plan: J.Json, entry: J.Json) -> J.Json:
  match failed:
    case True{}: plan
    case False{}: config_plan_observed(plan, entry)
def config_evaluator_provider(+entry: J.Json) -> J.Json:
  +raw = config_get(entry, "provider")
  +provider = config_select(config_nullish(raw), J.Object{Con{J.Field{"kind", J.Text{"string"}}, Con{J.Field{"units", J.Array{Con{J.Number{"118"}, Con{J.Number{"101"}, Con{J.Number{"114"}, Con{J.Number{"99"}, Con{J.Number{"101"}, Con{J.Number{"108"}, Nil{}}}}}}}}}, Nil{}}}}, raw)
  +plan = config_provider_route_0(config_text_equal(provider, "vercel"), entry, provider)
  config_evaluator_provider_result(config_has_error(plan), plan, entry)
def config_evaluator_plan(+source: J.Json) -> J.Json:
  +entry = J.get(source, "entry")
  config_guard(config_name(J.get(source, "name")), config_failure("Invalid reasoning evaluator name"),
    config_guard(config_fields(entry, Con{"provider", Con{"model", Con{"endpoint", Con{"api_key_env", Con{"timeout_ms", Con{"max_attempts", Nil{}}}}}}}), config_failure("Invalid reasoning evaluator configuration fields"),
    config_evaluator_provider(entry)))
def config_endpoint_requirements(+source: J.Json) -> Bool:
  +url = J.get(source, "url")
  String.eq(J.text(J.get(url, "username")), "") && String.eq(J.text(J.get(url, "password")), "") &&
    String.eq(J.text(J.get(url, "hash")), "") && String.eq(J.text(J.get(url, "search")), "") &&
    (String.eq(J.text(J.get(url, "protocol")), "https:") ||
      (String.eq(J.text(J.get(url, "protocol")), "http:") &&
       (String.eq(J.text(J.get(url, "hostname")), "localhost") || String.eq(J.text(J.get(url, "hostname")), "127.0.0.1") || String.eq(J.text(J.get(url, "hostname")), "[::1]"))))
def config_bound_default(+value: J.Json, lower: String, upper: String) -> Bool:
  Bool.not(config_present(value)) || config_bound(value, lower, upper)
def config_deadline_requirements(+source: J.Json) -> Bool:
  config_bound_default(config_get(J.get(source, "entry"), "timeout_ms"), "100", "120000")
def config_retry_requirements(+source: J.Json) -> Bool:
  config_bound_default(config_get(J.get(source, "entry"), "max_attempts"), "1", "3")
def config_timing_requirements(+source: J.Json) -> Bool:
  config_deadline_requirements(source) && config_retry_requirements(source)
def config_evaluator_admitted(member: Maybe<&1, Categories.Membership<J.Json, (candidate => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => config_endpoint_requirements(candidate))), Categories.holds(J.Json, (candidate => config_timing_requirements(candidate))), candidate))>>) -> J.Json:
  match member:
    case None{}: config_failure("Invalid evaluator deadline or same-provider retry bound")
    case Some{Categories.Membership{source, evidence}}: config_literal(J.Null{})
def config_evaluator_entry(+source: J.Json) -> J.Json:
  config_guard(config_endpoint_requirements(source), config_failure("The evaluator endpoint requires HTTPS except on loopback, without embedded credentials"),
    config_evaluator_admitted(Categories.admit_intersection(J.Json, (candidate => config_endpoint_requirements(candidate)), (candidate => config_timing_requirements(candidate)), source)))
def config_seen(values: +List<J.Json>, +value: J.Json) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{+head, rest}: J.same(J.get(head, "units"), J.get(value, "units")) && config_kind(head, "string") && config_kind(value, "string") || config_seen(rest, value)
def config_effort_entries(values: +List<J.Json>, bytes: +List<J.Json>, +seen: +List<J.Json>) -> Bool:
  match values bytes:
    case Nil{} Nil{}: True{}
    case Con{+head, rest} Con{bound, remaining}:
      config_name(head) && Bool.not(config_text_equal(head, "auto")) && Model.nonnegative_le(bound, "64") &&
        Bool.not(config_seen(seen, head)) && config_effort_entries(rest, remaining, Con{head, seen})
    case _ _: False{}
def config_effort_requirements(+source: J.Json) -> Bool:
  +value = J.get(source, "value")
  +efforts = config_get(value, "efforts")
  +items = J.items(J.get(efforts, "items"))
  config_name(config_get(value, "evaluator")) && config_kind(efforts, "array") &&
    Nat.is_le(1n, config_list_count(items)) && Nat.is_le(config_list_count(items), 16n) &&
    config_effort_entries(items, J.items(J.get(source, "bytes")), Nil{}) && config_seen(items, config_get(value, "baseline")) &&
    (config_text_equal(config_get(value, "transport"), "configuration_update") || config_text_equal(config_get(value, "transport"), "request_effort"))
def config_lease_requirements(+source: J.Json) -> Bool:
  config_bound_default(config_get(J.get(source, "value"), "max_lease"), "1", "10")
def config_effort_refs(values: +List<J.Json>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{head, rest}: Con{config_ref(head), config_effort_refs(rest)}
def config_adaptive_projection(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  J.Object{Con{J.Field{"base", J.get(value, "ref")}, Con{J.Field{"fields", J.Array{Con{J.Object{Con{J.Field{"key", J.Text{"max_lease"}}, Con{J.Field{"value", config_value(config_get(value, "max_lease"), J.Number{"10"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"efforts"}}, Con{J.Field{"value", J.Object{Con{J.Field{"array", J.Array{config_effort_refs(J.items(J.get(config_get(value, "efforts"), "items")))}}, Nil{}}}}, Nil{}}}}, Nil{}}}}}, Nil{}}}}
def config_adaptive_admitted(member: Maybe<&1, Categories.Membership<J.Json, (candidate => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => config_effort_requirements(candidate))), Categories.holds(J.Json, (candidate => config_lease_requirements(candidate))), candidate))>>) -> J.Json:
  match member:
    case None{}: config_failure("Adaptive reasoning requires an evaluator, distinct actual efforts, a supported baseline, transport, and a lease bound of 1..10")
    case Some{Categories.Membership{+source, evidence}}:
      config_adaptive_projection(source)
def config_adaptive_required(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  config_guard(config_fields(value, Con{"evaluator", Con{"efforts", Con{"baseline", Con{"transport", Con{"max_lease", Nil{}}}}}}), config_failure("Invalid adaptive reasoning configuration fields"),
    config_adaptive_admitted(Categories.admit_intersection(J.Json, (candidate => config_effort_requirements(candidate)), (candidate => config_lease_requirements(candidate)), source)))
def config_adaptive_optional(absent: Bool, source: J.Json) -> J.Json:
  match absent:
    case True{}: config_literal(J.Null{})
    case False{}: config_adaptive_required(source)
def config_adaptive_policy(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  config_adaptive_optional(config_kind(value, "undefined") || config_kind(value, "null") || (config_kind(value, "boolean") && J.same(J.get(value, "boolean"), J.Boolean{False{}})), source)
def config_unique_seen(duplicate: Bool, effort: J.Json, +seen: +List<J.Json>) -> +List<J.Json>:
  match duplicate:
    case True{}: seen
    case False{}: Con{effort, seen}
def config_unique_step(duplicate: Bool, effort: J.Json, +rest: +List<J.Json>) -> +List<J.Json>:
  match duplicate:
    case True{}: rest
    case False{}: Con{effort, rest}
def config_unique_efforts(values: +List<J.Json>, +seen: +List<J.Json>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{head, rest}:
      +effort = config_get(head, "effort")
      +duplicate = config_seen(seen, effort)
      config_unique_step(duplicate, effort, config_unique_efforts(rest, config_unique_seen(duplicate, effort, seen)))
def config_any_auto(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{head, rest}: config_text_equal(head, "auto") || config_any_auto(rest)
def config_first(values: +List<J.Json>) -> J.Json:
  match values:
    case Nil{}: J.Null{}
    case Con{head, rest}: head
def config_auto_efforts(+source: J.Json, +efforts: +List<J.Json>) -> J.Json:
  +baseline = config_get(J.get(source, "descriptor"), "default_reasoning_level")
  config_guard(Nat.is_le(1n, config_list_count(efforts)) && Bool.not(config_any_auto(efforts)), J.Object{Con{J.Field{"undefined", J.Boolean{True{}}}, Nil{}}},
    J.Object{Con{J.Field{"fields", J.Array{Con{J.Object{Con{J.Field{"key", J.Text{"evaluator"}}, Con{J.Field{"value", config_literal(J.Text{"jev"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"efforts"}}, Con{J.Field{"value", J.Object{Con{J.Field{"array", J.Array{config_effort_refs(efforts)}}, Nil{}}}}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"baseline"}}, Con{J.Field{"value", config_ref(config_select(config_seen(efforts, baseline), baseline, config_first(efforts)))}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"transport"}}, Con{J.Field{"value", config_literal(J.Text{"configuration_update"})}, Nil{}}}}, Con{J.Object{Con{J.Field{"key", J.Text{"max_lease"}}, Con{J.Field{"value", config_literal(J.Number{"10"})}, Nil{}}}}, Nil{}}}}}}}}, Nil{}}})
def config_auto_preset(+source: J.Json) -> J.Json:
  config_guard(config_text_equal(config_get(J.get(source, "descriptor"), "slug"), "gpt-6-astra"), J.Object{Con{J.Field{"undefined", J.Boolean{True{}}}, Nil{}}},
    config_auto_efforts(source, config_unique_efforts(J.items(J.get(config_get(J.get(source, "descriptor"), "supported_reasoning_levels"), "items")), Nil{})))
def config_admissible_head(+source: J.Json) -> Bool:
  Bool.not(config_has_error(config_configuration_head(source)))
def config_admissible_transport(+source: J.Json) -> Bool:
  Bool.not(config_has_error(config_configuration_transport(source)))
def config_admissible_extensions(+source: J.Json) -> Bool:
  Bool.not(config_has_error(config_configuration_extensions(source)))
# A complete configuration-stage source carries the three original observations.
def config_admissible_configuration(+source: J.Json) -> Bool:
  config_admissible_head(J.get(source, "head")) && config_admissible_transport(J.get(source, "transport")) &&
    config_admissible_extensions(J.get(source, "extensions"))
def config_valid_adaptive_policy(+source: J.Json) -> Bool:
  config_effort_requirements(source) && config_lease_requirements(source)
def config_valid_evaluator_entry(+source: J.Json) -> Bool:
  config_endpoint_requirements(source) && config_timing_requirements(source)
def config_meaning_route_7(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_auto_preset(source))
    case False{}: Model.failure("Unknown configuration operation")
def config_meaning_route_6(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_adaptive_policy(source))
    case False{}: config_meaning_route_7(String.eq(operation, "config.auto_preset"), operation, source)
def config_meaning_route_5(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_evaluator_entry(source))
    case False{}: config_meaning_route_6(String.eq(operation, "config.adaptive_policy"), operation, source)
def config_meaning_route_4(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_evaluator_plan(source))
    case False{}: config_meaning_route_5(String.eq(operation, "config.evaluator_entry"), operation, source)
def config_meaning_route_3(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_evaluators(source))
    case False{}: config_meaning_route_4(String.eq(operation, "config.evaluator_plan"), operation, source)
def config_meaning_route_2(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_configuration_extensions(source))
    case False{}: config_meaning_route_3(String.eq(operation, "config.evaluators"), operation, source)
def config_meaning_route_1(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_configuration_transport(source))
    case False{}: config_meaning_route_2(String.eq(operation, "config.configuration_extensions"), operation, source)
def config_meaning_route_0(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_configuration_head(source))
    case False{}: config_meaning_route_1(String.eq(operation, "config.configuration_transport"), operation, source)
def config_meaning_defaults(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_defaults(source))
    case False{}: config_meaning_route_0(String.eq(operation, "config.configuration_head"), operation, source)
def meaning(+operation: String, +source: J.Json) -> J.Json:
  config_meaning_defaults(String.eq(operation, "config.defaults"), operation, source)
def factory(+operation: String) -> Model.Adapter((source => meaning(operation, source))):
  Model.adapter((source => meaning(operation, source)), (source => meaning(operation, source)), source => {==})
def run(+operation: String, source: J.Json) -> J.Json:
  Model.execute((candidate => meaning(operation, candidate)), factory(operation), source)

law initial_instruction_default:
  @source:J.Json -> {J.get(config_defaults(source), "instructions") == J.Text{configured_default()} : J.Json}
