import Base
import ../../bendlib/json.bend as J
import ../../bendlib/categories.bend as Categories
import ./MODEL.bend as Model
import ../../harness/DOMAIN.bend as D
import ../../harness/context/MODEL.bend as Context
import ../../harness/context/KINDS.bend as ContextKinds
import ../../harness/compaction/MODEL.bend as Compaction

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
# Automatic context maintenance is configured independently of model identity.
# Only actual advertised windows or explicit target settings admit automation.
def compact_has_fields(fields: +List<J.Field>, +name: String) -> Bool:
  match fields:
    case Nil{}: False{}
    case Con{J.Field{key, value}, rest}: String.eq(key, name) || compact_has_fields(rest, name)
def compact_has(value: J.Json, name: String) -> Bool:
  match value:
    case J.Object{fields}: compact_has_fields(fields, name)
    case _: False{}
def compact_field(+value: J.Json, +name: String, fallback: J.Json) -> J.Json:
  config_select(compact_has(value, name), J.get(value, name), fallback)
def compact_contains(values: +List<String>, +text: String) -> Bool:
  match values:
    case Nil{}: False{}
    case Con{head, rest}: String.eq(head, text) || compact_contains(rest, text)
def compact_keys(fields: +List<J.Field>, +allowed: +List<String>) -> Bool:
  match fields:
    case Nil{}: True{}
    case Con{J.Field{key, value}, rest}:
      compact_contains(allowed, key) && compact_keys(rest, allowed)
def compact_object(value: J.Json, allowed: +List<String>) -> Bool:
  match value:
    case J.Object{fields}: compact_keys(fields, allowed)
    case _: False{}
def compact_number(+value: J.Json, minimum: String, maximum: String) -> Bool:
  Model.nonnegative_le(value, maximum) && Model.decimal_le(minimum, config_number_text(value))
def compact_nat(value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)
def compact_array(value: J.Json) -> Bool:
  match value:
    case J.Array{items}: True{}
    case _: False{}
def compact_boolean(value: J.Json) -> Bool:
  match value:
    case J.Boolean{observed}: True{}
    case _: False{}
def compact_defaults() -> J.Json:
  J.Object{[J.Field{"enabled", J.Boolean{True{}}}, J.Field{"background_percent", J.nat(65n)}, J.Field{"blocking_percent", J.nat(90n)}, J.Field{"idle_lead_ms", J.nat(60000n)}, J.Field{"targets", J.Array{Nil{}}}]}
def compact_value(+source: J.Json) -> J.Json:
  compact_field(J.get(source, "config"), "compaction", compact_defaults())
def compact_policy_field(+source: J.Json, +name: String) -> J.Json:
  compact_field(compact_value(source), name, J.get(compact_defaults(), name))
def compact_threshold_requirements(+source: J.Json) -> Bool:
  compact_object(compact_value(source), ["enabled", "background_percent", "blocking_percent", "idle_lead_ms", "targets"]) &&
    compact_boolean(compact_policy_field(source, "enabled")) &&
    compact_number(compact_policy_field(source, "background_percent"), "1", "98") &&
    compact_number(compact_policy_field(source, "blocking_percent"), "2", "99") &&
    Nat.is_lt(compact_nat(compact_policy_field(source, "background_percent")), compact_nat(compact_policy_field(source, "blocking_percent"))) &&
    compact_number(compact_policy_field(source, "idle_lead_ms"), "0", "9007199254740991")
def compact_target_reserve(+target: J.Json) -> J.Json:
  compact_field(target, "output_reserve_tokens", J.nat(Nat.min(8192n, Nat.div(compact_nat(J.get(target, "window_tokens")), 8n))))
def compact_target_method(target: J.Json) -> J.Json:
  compact_field(target, "method", J.Text{"auto"})
def compact_target_cache(target: J.Json) -> J.Json:
  compact_field(target, "cache_ttl_ms", J.Null{})
def compact_target_budget(+target: J.Json) -> Bool:
  compact_number(J.get(target, "window_tokens"), "0", "4294967295") &&
    compact_number(compact_target_reserve(target), "0", "4294967295") &&
    Compaction.legal_budget(compact_nat(J.get(target, "window_tokens")), compact_nat(compact_target_reserve(target)))
def compact_supported_provider(profile: J.Json) -> Bool:
  compact_contains(["responses", "chatgpt"], J.text(J.get(profile, "provider")))
def compact_target_valid(+target: J.Json, +profiles: J.Json, +lead: Nat, +seen: +List<String>) -> Bool:
  +profile = J.get(target, "profile")
  +cache = compact_target_cache(target)
  compact_object(target, ["profile", "window_tokens", "output_reserve_tokens", "cache_ttl_ms", "method"]) &&
    (Bool.not(String.is_empty(J.text(profile)))) && Bool.not(compact_contains(seen, J.text(profile))) &&
    (Bool.not(compact_has(profiles, J.text(profile))) || compact_supported_provider(J.get(profiles, J.text(profile)))) &&
    compact_target_budget(target) &&
    compact_contains(["auto", "summary"], J.text(compact_target_method(target))) &&
    (J.same(cache, J.Null{}) || (compact_number(cache, "1", "9007199254740991") && Nat.is_lt(lead, compact_nat(cache))))
def compact_targets_valid(values: +List<J.Json>, +profiles: J.Json, +lead: Nat, +seen: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+target, rest}: compact_target_valid(target, profiles, lead, seen) &&
      compact_targets_valid(rest, profiles, lead, Con{J.text(J.get(target, "profile")), seen})
def compact_target_requirements(+source: J.Json) -> Bool:
  +targets = compact_policy_field(source, "targets")
  compact_array(targets) && compact_targets_valid(J.items(targets), J.get(source, "profiles"), compact_nat(compact_policy_field(source, "idle_lead_ms")), Nil{})
def compact_target(+target: J.Json) -> J.Json:
  J.Object{[J.Field{"profile", J.get(target, "profile")}, J.Field{"window_tokens", J.get(target, "window_tokens")},
    J.Field{"output_reserve_tokens", compact_target_reserve(target)}, J.Field{"cache_ttl_ms", compact_target_cache(target)}, J.Field{"method", compact_target_method(target)}]}
def compact_targets(values: +List<J.Json>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{head, rest}: Con{compact_target(head), compact_targets(rest)}
def compact_policy(+source: J.Json, targets: +List<J.Json>) -> J.Json:
  J.Object{[J.Field{"enabled", compact_policy_field(source, "enabled")}, J.Field{"background_percent", compact_policy_field(source, "background_percent")},
    J.Field{"blocking_percent", compact_policy_field(source, "blocking_percent")}, J.Field{"idle_lead_ms", compact_policy_field(source, "idle_lead_ms")}, J.Field{"targets", J.Array{targets}}]}
def compact_projection(+source: J.Json) -> J.Json:
  Model.success(compact_policy(source, compact_targets(J.items(compact_policy_field(source, "targets")))))
def compact_admitted(member: Maybe<&1, Categories.Membership<J.Json, (candidate => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => compact_threshold_requirements(candidate))), Categories.holds(J.Json, (candidate => compact_target_requirements(candidate))), candidate))>>) -> J.Json:
  match member:
    case None{}: Model.failure("Invalid compaction settings: require 1 <= background < blocking < 100, unique Responses-model targets, valid window/reserve headroom and cache TTL greater than idle lead")
    case Some{member}: compact_projection(Categories.value(J.Json, (candidate => Categories.intersection(J.Json, Categories.holds(J.Json, (candidate => compact_threshold_requirements(candidate))), Categories.holds(J.Json, (candidate => compact_target_requirements(candidate))), candidate)), member))
def config_compaction(+source: J.Json) -> J.Json:
  compact_admitted(Categories.admit_intersection(J.Json, (candidate => compact_threshold_requirements(candidate)), (candidate => compact_target_requirements(candidate)), source))
def compact_find_target(values: +List<J.Json>, +key: String) -> J.Json:
  match values:
    case Nil{}: J.Null{}
    case Con{+head, rest}: config_select(String.eq(J.text(J.get(head, "profile")), key), head, compact_find_target(rest, key))
def compact_model_window(+model: J.Json) -> Nat:
  +percent = compact_field(model, "effective_context_window_percent", J.nat(100n))
  Nat.div(Nat.mul(compact_nat(J.get(model, "context_window")), compact_nat(percent)), 100n)
def compact_discovered_target(+key: String, +profile: J.Json) -> J.Json:
  compact_target(J.Object{[J.Field{"profile", J.Text{key}}, J.Field{"window_tokens", J.nat(compact_model_window(J.get(profile, "model_info")))}]})
def compact_runtime_item(+key: String, +profile: J.Json, +explicit: J.Json) -> J.Json:
  config_select(J.same(explicit, J.Null{}), compact_discovered_target(key, profile), explicit)
def compact_runtime_cons(include: Bool, target: J.Json, rest: +List<J.Json>) -> +List<J.Json>:
  match include:
    case True{}: Con{target, rest}
    case False{}: rest
def compact_runtime_targets(values: +List<J.Field>, +configured: +List<J.Json>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{J.Field{+key, +profile}, rest}:
      +target = compact_runtime_item(key, profile, compact_find_target(configured, key))
      compact_runtime_cons(compact_supported_provider(profile) && compact_target_budget(target), target, compact_runtime_targets(rest, configured))
def compact_profile_fields(value: J.Json) -> +List<J.Field>:
  match value:
    case J.Object{fields}: fields
    case _: Nil{}
def compact_runtime_references(values: +List<J.Json>, +profiles: J.Json) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+head, rest}: compact_has(profiles, J.text(J.get(head, "profile"))) && compact_supported_provider(J.get(profiles, J.text(J.get(head, "profile")))) && compact_runtime_references(rest, profiles)
def compact_policy_runtime(+source: J.Json) -> J.Json:
  +config = J.get(source, "config")
  +profile_set = J.get(config, "profiles")
  +settings: J.Json = J.Object{[J.Field{"config", config}, J.Field{"profiles", profile_set}]}
  Model.success(compact_policy(settings, compact_runtime_targets(compact_profile_fields(profile_set), J.items(J.get(J.get(config, "compaction"), "targets")))))
def compact_runtime_checked(valid: Bool, +source: J.Json) -> J.Json:
  match valid:
    case False{}: Model.failure("Compaction target must resolve to an available responses or chatgpt model profile")
    case True{}: compact_policy_runtime(source)
def config_compaction_runtime(+source: J.Json) -> J.Json:
  +config = J.get(source, "config")
  +settings: J.Json = J.Object{[J.Field{"config", config}, J.Field{"profiles", J.get(config, "profiles")}]}
  compact_runtime_checked(compact_threshold_requirements(settings) && compact_target_requirements(settings) && compact_runtime_references(J.items(J.get(J.get(config, "compaction"), "targets")), J.get(config, "profiles")), source)

# URL parsing is an external observation. Admission owns the public transport
# boundary; private host credentials never enter configuration or this source.
def remote_origin_requirements(+source: J.Json) -> Bool:
  +endpoint = J.get(source, "endpoint_observation")
  String.eq(J.text(J.get(endpoint, "protocol")), "https:") &&
    String.eq(J.text(J.get(endpoint, "port")), "") &&
    Bool.not(String.is_empty(J.text(J.get(endpoint, "hostname")))) &&
    String.eq(J.text(J.get(endpoint, "username")), "") && String.eq(J.text(J.get(endpoint, "password")), "") &&
    String.eq(J.text(J.get(endpoint, "pathname")), "/") && String.eq(J.text(J.get(endpoint, "search")), "") &&
    String.eq(J.text(J.get(endpoint, "hash")), "")
def remote_configuration_requirements(+source: J.Json) -> Bool:
  +remote = J.get(source, "remote")
  compact_object(remote, ["relay_url"]) && compact_has(remote, "relay_url") &&
    Bool.not(String.is_empty(J.text(J.get(remote, "relay_url")))) && remote_origin_requirements(source)
def remote_configuration_projection(+source: J.Json) -> J.Json:
  Model.success(J.Object{[J.Field{"relay_url", J.get(J.get(source, "endpoint_observation"), "origin")}]})
def remote_configuration_admitted(member: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (candidate => remote_configuration_requirements(candidate)))>>) -> J.Json:
  match member:
    case None{}: Model.failure_code("TypeError", "remote requires only relay_url: an HTTPS origin on TCP 443 without credentials, path, query or fragment")
    case Some{member}: remote_configuration_projection(Categories.value(J.Json, Categories.holds(J.Json, (candidate => remote_configuration_requirements(candidate))), member))
def remote_configuration_checked(disabled: Bool, +source: J.Json) -> J.Json:
  match disabled:
    case True{}: Model.success(J.Boolean{False{}})
    case False{}: remote_configuration_admitted(Categories.admit(J.Json, (candidate => remote_configuration_requirements(candidate)), source))
def config_remote(+source: J.Json) -> J.Json:
  remote_configuration_checked(J.same(J.get(source, "remote"), J.Boolean{False{}}), source)

# Cloud credentials are service environment bindings, never configuration fields.
def cloud_nonempty(+value: J.Json) -> Bool:
  J.is_text(value) && Bool.not(String.is_empty(J.text(value)))

def cloud_text_fields(fields: +List<String>, +value: J.Json) -> Bool:
  match fields:
    case Nil{}: True{}
    case Con{name, rest}: cloud_nonempty(J.get(value, name)) && cloud_text_fields(rest, value)

def cloud_security_groups(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{head, rest}: cloud_nonempty(head) && cloud_security_groups(rest)

def cloud_groups(value: J.Json) -> Bool:
  match value:
    case J.Array{Con{head, rest}}: cloud_nonempty(head) && cloud_security_groups(rest)
    case _: False{}

def cloud_optional_text(+value: J.Json, +name: String) -> Bool:
  Bool.not(compact_has(value, name)) || cloud_nonempty(J.get(value, name))

def cloud_optional_number(+value: J.Json, +name: String, minimum: String, maximum: String) -> Bool:
  Bool.not(compact_has(value, name)) || compact_number(J.get(value, name), minimum, maximum)

def cloud_tencent_requirements(+value: J.Json) -> Bool:
  compact_object(value, ["region", "zone", "image_id", "instance_type", "vpc_id", "subnet_id", "security_group_ids",
    "key_id", "ssh_private_key", "ssh_user", "ssh_port", "spot_max_price", "internet_max_bandwidth_out", "startup_timeout_ms", "address_type", "api_endpoint"]) &&
    cloud_text_fields(["region", "zone", "image_id", "instance_type", "vpc_id", "subnet_id", "key_id", "ssh_private_key", "spot_max_price"], value) &&
    cloud_groups(J.get(value, "security_group_ids")) && cloud_optional_text(value, "ssh_user") && cloud_optional_text(value, "api_endpoint") &&
    cloud_optional_number(value, "ssh_port", "1", "65535") && cloud_optional_number(value, "internet_max_bandwidth_out", "0", "1000") &&
    cloud_optional_number(value, "startup_timeout_ms", "1000", "3600000") &&
    (Bool.not(compact_has(value, "address_type")) || J.same(J.get(value, "address_type"), J.Text{"public"}) || J.same(J.get(value, "address_type"), J.Text{"private"}))

def cloud_requirements(+value: J.Json) -> Bool:
  compact_object(value, ["backend", "tencent_cvm"]) && J.same(J.get(value, "backend"), J.Text{"tencent_cvm"}) &&
    cloud_tencent_requirements(J.get(value, "tencent_cvm"))

def cloud_checked(disabled: Bool, +value: J.Json) -> J.Json:
  match disabled:
    case True{}: Model.success(J.Boolean{False{}})
    case False{}: Bool.pick(J.Json, cloud_requirements(value), Model.success(value),
      Model.failure_code("TypeError", "cloud requires backend tencent_cvm and complete CVM, network, SSH key and spot_max_price settings; credentials belong in the service environment"))

def config_cloud(+source: J.Json) -> J.Json:
  cloud_checked(J.same(J.get(source, "cloud"), J.Boolean{False{}}) || J.same(J.get(source, "cloud"), J.Null{}), J.get(source, "cloud"))

def configured_instruction(instructions: D.InitialInstructions) -> String:
  D.InitialInstructions{configured, global} = instructions
  configured

def configured_default() -> String:
  configured_instruction(D.default_instructions())

def config_base_defaults(+source: J.Json) -> J.Json:
  J.Object{[J.Field{"format", J.Text{"selvedge-bend-config-1"}}, J.Field{"host", J.Text{"127.0.0.1"}}, J.Field{"port", J.Number{"7421"}}, J.Field{"max_fork", J.Number{"4"}}, J.Field{"max_descendants", J.Number{"64"}}, J.Field{"instructions", J.Text{configured_default()}}, J.Field{"profiles", J.Object{[J.Field{"demo", J.Object{[J.Field{"provider", J.Text{"echo"}}, J.Field{"model", J.Text{"echo"}}]}}]}}, J.Field{"mcp", J.Object{[]}}, J.Field{"plugins", J.Object{[]}}, J.Field{"skills", J.Array{[]}}, J.Field{"remote", J.Boolean{False{}}}, J.Field{"cloud", J.Boolean{False{}}}, J.Field{"compaction", compact_defaults()}]}
def config_context_definitions() -> J.Json:
  Context.definitions_json(ContextKinds.definitions())
def config_context_observer(+definition: J.Json) -> J.Json:
  J.get(definition, "observer")
def config_context_setting(+definition: J.Json) -> String:
  J.text(J.get(config_context_observer(definition), "setting"))
def config_context_configured(+definition: J.Json) -> Bool:
  +observer = config_context_observer(definition)
  String.eq(J.text(J.get(observer, "type")), "config_text") || String.eq(J.text(J.get(observer, "type")), "config_files")
def config_context_default(+definition: J.Json) -> J.Json:
  +base = J.get(config_base_defaults(J.Null{}), config_context_setting(definition))
  config_select(config_present(base), base,
    config_select(String.eq(J.text(J.get(config_context_observer(definition), "type")), "config_text"), J.Text{""}, J.Array{[]}))
def config_context_defaults_case(keep: Bool, +definition: J.Json, rest: +List<J.Field>) -> +List<J.Field>:
  match keep:
    case True{}: Con{J.Field{config_context_setting(definition), config_context_default(definition)}, rest}
    case False{}: rest
def config_context_defaults(definitions: +List<J.Json>) -> +List<J.Field>:
  match definitions:
    case Nil{}: Nil{}
    case Con{+definition, rest}: config_context_defaults_case(config_context_configured(definition) && Bool.not(config_present(J.get(config_base_defaults(J.Null{}), config_context_setting(definition)))), definition, config_context_defaults(rest))
def config_default_fields(value: J.Json) -> +List<J.Field>:
  match value:
    case J.Object{fields}: fields
    case _: Nil{}
def config_append_fields(left: +List<J.Field>, +right: +List<J.Field>) -> +List<J.Field>:
  match left:
    case Nil{}: right
    case Con{head, rest}: Con{head, config_append_fields(rest, right)}
def config_defaults(+source: J.Json) -> J.Json:
  J.Object{config_append_fields(config_default_fields(config_base_defaults(source)), config_context_defaults(J.items(config_context_definitions())))}
def config_context_keys_case(keep: Bool, definition: J.Json, rest: +List<String>) -> +List<String>:
  match keep:
    case True{}: Con{config_context_setting(definition), rest}
    case False{}: rest
def config_context_keys(definitions: +List<J.Json>, +rest: +List<String>) -> +List<String>:
  match definitions:
    case Nil{}: rest
    case Con{+definition, tail}: config_context_keys_case(config_context_configured(definition), definition, config_context_keys(tail, rest))
def config_context_head_case(keep: Bool, +definition: J.Json, rest: +List<J.Json>, +value: J.Json) -> +List<J.Json>:
  match keep:
    case True{}: Con{J.Object{[J.Field{"key", J.Text{config_context_setting(definition)}}, J.Field{"value", config_value(config_get(value, config_context_setting(definition)), config_context_default(definition))}]}, rest}
    case False{}: rest
def config_context_head_fields(definitions: +List<J.Json>, +value: J.Json) -> +List<J.Json>:
  match definitions:
    case Nil{}: Nil{}
    case Con{+definition, rest}: config_context_head_case(config_context_configured(definition), definition, config_context_head_fields(rest, value), value)
def config_head_format(+valid: Bool, +value: J.Json) -> J.Json:
  match valid:
    case True{}: J.Object{[J.Field{"base", J.get(value, "ref")}, J.Field{"fields", J.Array{config_append([J.Object{[J.Field{"key", J.Text{"host"}}, J.Field{"value", config_value(config_get(value, "host"), J.get(config_defaults(J.Null{}), "host"))}]}, J.Object{[J.Field{"key", J.Text{"port"}}, J.Field{"value", config_value(config_get(value, "port"), J.get(config_defaults(J.Null{}), "port"))}]}, J.Object{[J.Field{"key", J.Text{"max_fork"}}, J.Field{"value", config_value(config_get(value, "max_fork"), J.get(config_defaults(J.Null{}), "max_fork"))}]}, J.Object{[J.Field{"key", J.Text{"max_descendants"}}, J.Field{"value", config_value(config_get(value, "max_descendants"), J.get(config_defaults(J.Null{}), "max_descendants"))}]}, J.Object{[J.Field{"key", J.Text{"profiles"}}, J.Field{"value", config_value(config_get(value, "profiles"), J.get(config_defaults(J.Null{}), "profiles"))}]}, J.Object{[J.Field{"key", J.Text{"mcp"}}, J.Field{"value", config_value(config_get(value, "mcp"), J.get(config_defaults(J.Null{}), "mcp"))}]}, J.Object{[J.Field{"key", J.Text{"plugins"}}, J.Field{"value", config_value(config_get(value, "plugins"), J.get(config_defaults(J.Null{}), "plugins"))}]}], config_context_head_fields(J.items(config_context_definitions()), value))}}]}
    case False{}: J.Object{Con{J.Field{"error", J.Array{Con{config_literal(J.Text{"The configuration is not in the current Bend format"}), Nil{}}}}, Con{J.Field{"code", J.Text{"Error"}}, Nil{}}}}
def config_head_unknown(+unknown: J.Json, +value: J.Json) -> J.Json:
  config_guard(J.same(unknown, J.Null{}), config_error(Con{config_literal(J.Text{"Unknown configuration field: "}), Con{config_ref(unknown), Nil{}}}),
    config_head_format(config_text_equal(config_get(value, "format"), J.text(J.get(config_defaults(J.Null{}), "format"))), value))
def config_configuration_head(+source: J.Json) -> J.Json:
  +value = J.get(source, "value")
  config_guard(config_kind(value, "object"), config_failure("configuration must be an object"),
    config_head_unknown(config_unknown(J.items(J.get(value, "fields")), config_context_keys(J.items(config_context_definitions()), ["format", "host", "port", "max_fork", "max_descendants", "profiles", "chatgpt", "mcp", "plugins", "reasoning_evaluators", "chatgpt_plugin", "remote", "compaction", "cloud"])), value))
def config_context_paths_acc(values: +List<J.Json>, observations: +List<J.Json>, valid: Bool) -> Bool:
  match values observations:
    case Nil{} Nil{}: valid
    case Con{+value, rest} Con{+observed, tail}:
      config_context_paths_acc(rest, tail, valid && config_kind(value, "string") &&
        Bool.not(List.is_empty(&2, J.Json, J.items(J.get(value, "units")))) &&
        J.boolean(J.get(observed, "well_formed")) && Model.nonnegative_le(J.get(observed, "bytes"), "4096"))
    case _ _: False{}

def config_context_paths(values: +List<J.Json>, observations: +List<J.Json>) -> Bool:
  config_context_paths_acc(values, observations, True{})

def config_context_transport_value_case(text: Bool, +value: J.Json, +observation: J.Json) -> Bool:
  match text:
    case True{}: config_kind(value, "string") && J.boolean(J.get(observation, "well_formed")) && Model.nonnegative_le(J.get(observation, "bytes"), Nat.show(D.project_limit()))
    case False{}: config_kind(value, "array") && Nat.is_le(config_list_count(J.items(J.get(value, "items"))), 64n) && config_context_paths(J.items(J.get(value, "items")), J.items(J.get(observation, "items")))
def config_context_transport_value(+definition: J.Json, +value: J.Json, +observation: J.Json) -> Bool:
  config_context_transport_value_case(String.eq(J.text(J.get(config_context_observer(definition), "type")), "config_text"), value, observation)
def config_context_transport(definitions: +List<J.Json>, +values: J.Json, +observations: J.Json) -> Bool:
  match definitions:
    case Nil{}: True{}
    case Con{+definition, rest}:
      (Bool.not(config_context_configured(definition)) || config_context_transport_value(definition, J.get(values, config_context_setting(definition)), J.get(observations, config_context_setting(definition)))) && config_context_transport(rest, values, observations)
def config_context_definition_valid(definition: Maybe<&2, Context.Definition>) -> Bool:
  match definition:
    case Some{definition}: True{}
    case None{}: False{}
def config_context_definitions_valid_acc(definitions: +List<J.Json>, valid: Bool) -> Bool:
  match definitions:
    case Nil{}: valid
    case Con{definition, rest}:
      config_context_definitions_valid_acc(rest, valid && config_context_definition_valid(Context.definition(definition)))

def config_context_definitions_valid(definitions: +List<J.Json>) -> Bool:
  config_context_definitions_valid_acc(definitions, True{})

def config_context_requirements(+source: J.Json) -> Bool:
  +definitions = J.items(J.get(source, "definitions"))
  Model.parsed_array(J.get(source, "definitions")) && config_context_definitions_valid(definitions) && config_context_transport(definitions, J.get(source, "values"), J.get(source, "observations"))
def config_configuration_context(+source: J.Json) -> J.Json:
  config_guard(config_context_requirements(source),
    config_failure("context settings must contain bounded UTF-8 text or at most 64 bounded file paths"), config_literal(J.Null{}))

def config_context_field_schema_acc(fields: +List<J.Json>, found: Bool, +name: String, selected: J.Json) -> J.Json:
  match fields found:
    case Nil{} True{}: selected
    case Nil{} False{}: J.Null{}
    case Con{field, rest} True{}: selected
    case Con{+field, rest} False{}:
      config_context_field_schema_acc(rest, String.eq(J.text(J.get(field, "name")), name), name, field)

def config_context_field_schema(fields: +List<J.Json>, name: String) -> J.Json:
  config_context_field_schema_acc(fields, False{}, name, J.Null{})

def config_context_scalar_text_acc(text: String, valid: Bool) -> Bool:
  match text:
    case SNil{}: valid
    case SCon{Chr{+code}, rest}:
      config_context_scalar_text_acc(rest, valid && Bool.not(U32.is_eq(code, 0) || (U32.is_ge(code, 55296) && U32.is_le(code, 57343))))

def config_context_scalar_text(text: String) -> Bool:
  config_context_scalar_text_acc(text, True{})

def config_context_field_axis(identity: Bool) -> String:
  match identity:
    case True{}: "identity"
    case False{}: "fields"
def config_context_field_bound(identity: Bool) -> Nat:
  match identity:
    case True{}: 4096n
    case False{}: D.project_limit()
def config_context_field_schema_from(+source: J.Json) -> J.Json:
  config_context_field_schema(J.items(J.get(J.get(source, "definition"), config_context_field_axis(J.boolean(J.get(source, "identity"))))), J.text(J.get(source, "field")))
def config_context_field_required(+source: J.Json) -> Bool:
  J.boolean(J.get(config_context_field_schema_from(source), "required"))
def config_context_field_requirements(+source: J.Json) -> Bool:
  +value = J.get(source, "value")
  config_context_definition_valid(Context.definition(J.get(source, "definition"))) &&
    J.is_text(J.get(source, "field")) &&
    (J.same(J.get(source, "identity"), J.Boolean{True{}}) || J.same(J.get(source, "identity"), J.Boolean{False{}})) &&
    config_present(config_context_field_schema_from(source)) && J.is_text(value) &&
    config_context_scalar_text(J.text(value)) && Context.required_text(config_context_field_required(source), J.text(value)) &&
    Nat.is_le(J.utf8_length(J.text(value)), config_context_field_bound(J.boolean(J.get(source, "identity"))))
def config_context_field_admitted(member: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (candidate => config_context_field_requirements(candidate)))>>) -> J.Json:
  match member:
    case Some{Categories.Membership{source, evidence}}: Model.success(J.get(source, "value"))
    case None{}: Model.failure_code("TypeError", "Context field must satisfy its definition and UTF-8 byte bound")
def config_context_field(+source: J.Json) -> J.Json:
  config_context_field_admitted(Categories.admit(J.Json, (candidate => config_context_field_requirements(candidate)), source))
def config_configuration_transport(+source: J.Json) -> J.Json:
  +value = J.get(source, "transport")
  config_guard(config_text_equal(J.get(value, "host"), "127.0.0.1") || config_text_equal(J.get(value, "host"), "::1"), config_failure("The local server requires a loopback address"),
    config_guard(config_bound(J.get(value, "port"), "0", "65535"), config_failure("port must be in 0..65535"),
    config_guard(config_bound(J.get(value, "max_fork"), "1", "4294967295"), config_failure("max_fork must be in 1..4294967295"),
    config_guard(config_bound(J.get(value, "max_descendants"), "1", "4294967295"), config_failure("max_descendants must be in 1..4294967295"),
    config_guard(config_kind(J.get(value, "profiles"), "object"), config_failure("profiles must be an object"),
    config_guard(J.same(J.get(J.get(source, "context"), "definitions"), config_context_definitions()) && config_context_requirements(J.get(source, "context")), config_failure("context settings must contain bounded UTF-8 text or at most 64 bounded file paths"),
    config_literal(J.Null{})))))))
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
def config_compaction_runtime_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: config_compaction_runtime(source)
    case False{}: config_meaning_defaults(String.eq(operation, "config.defaults"), operation, source)
def config_compaction_route(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: config_compaction(source)
    case False{}: config_compaction_runtime_route(String.eq(operation, "config.compaction_runtime"), operation, source)
def config_meaning_context_definitions(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_context_definitions())
    case False{}: config_compaction_route(String.eq(operation, "config.compaction"), operation, source)
def config_meaning_context_transport(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: Model.success(config_configuration_context(source))
    case False{}: config_meaning_context_definitions(String.eq(operation, "config.context_definitions"), operation, source)
def config_meaning_context_field(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: config_context_field(source)
    case False{}: config_meaning_context_transport(String.eq(operation, "config.context_transport"), operation, source)
def config_meaning_remote(accepted: Bool, +operation: String, +source: J.Json) -> J.Json:
  match accepted:
    case True{}: config_remote(source)
    case False{}: config_meaning_context_field(String.eq(operation, "config.context_field"), operation, source)
def meaning(+operation: String, +source: J.Json) -> J.Json:
  Bool.pick(J.Json, String.eq(operation, "config.cloud"), config_cloud(source), config_meaning_remote(String.eq(operation, "config.remote"), operation, source))
def factory(+operation: String) -> Model.Adapter((source => meaning(operation, source))):
  Model.adapter((source => meaning(operation, source)), (source => meaning(operation, source)), source => {==})
def run(+operation: String, source: J.Json) -> J.Json:
  Model.execute((candidate => meaning(operation, candidate)), factory(operation), source)

law initial_instruction_default:
  @source:J.Json -> {J.get(config_defaults(source), "instructions") == J.Text{configured_default()} : J.Json}
