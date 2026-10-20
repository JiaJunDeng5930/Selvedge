import Base
import ../../bendlib/json.bend as J

type NaturalDefault is Data:
  ConstantDefault{value: Nat}
  CallerDefault{}

type Natural is Data:
  Constant{value: Nat}
  Caller{}
  RequiredNumber{key: String, description: String, minimum: U32, maximum: U32}
  OptionalNumber{key: String, description: String, minimum: U32, maximum: U32, fallback: NaturalDefault}

type Text is Data:
  TextConstant{value: String}
  TextArgument{key: String, description: String, required: Bool, fallback: String}

type Texts is Data:
  TextsConstant{value: +List<String>}
  TextsArgument{key: String, description: String, required: Bool}

type Settings is Data:
  SettingsConstant{value: J.Json}
  SettingsArgument{key: String, required: Bool}

type Query is Data:
  Read{task: Natural, after: Natural, limit: Natural}
  Search{query: Text, project: Natural, work: Natural, after: Natural, limit: Natural}
  Tasks{}
  Describe{}
  Projects{}
  Project{project: Natural}

type Body is Data:
  Observe{query: Query}
  Discover{}
  Create{profile: Text, reasoning: Text, message: Text, settings: Settings}
  Feature{operation: String, schema: J.Json}
  Send{task: Natural, message: Text}
  Steer{task: Natural, message: Text}
  Archive{task: Natural}
  Cancel{task: Natural, operation: Natural}
  Fork{count: Natural, messages: Texts, settings: Settings}
  Process{}
  ProcessRead{}
  ProcessWrite{}
  ReadImage{}

def external(body: Body) -> Bool:
  match body:
    case Process{}: True{}
    case ProcessRead{}: True{}
    case ProcessWrite{}: True{}
    case ReadImage{}: True{}
    case _: False{}

def default_number(fallback: NaturalDefault, caller: Nat) -> Nat:
  match fallback:
    case ConstantDefault{value}: value
    case CallerDefault{}: caller

def number(term: Natural, +args: J.Json, caller: Nat) -> Nat:
  match term:
    case Constant{value}: value
    case Caller{}: caller
    case RequiredNumber{key, description, minimum, maximum}: J.natural_or(J.natural(J.get(args, key)), 0n)
    case OptionalNumber{key, description, minimum, maximum, fallback}:
      J.natural_or(J.natural(J.get(args, key)), default_number(fallback, caller))

def optional_number(term: Natural, +args: J.Json, caller: Nat) -> Maybe<&2, Nat>:
  match term:
    case OptionalNumber{key, description, minimum, maximum, fallback}: J.natural(J.get(args, key))
    case other: Some{number(other, args, caller)}

def bounded_number(value: Maybe<&2, U32>, minimum: U32, maximum: U32) -> Bool:
  match value:
    case None{}: False{}
    case Some{+value}: U32.is_le(minimum, value) && U32.is_le(value, maximum)

def within_bounds(value: Nat, minimum: U32, maximum: U32) -> Bool:
  bounded_number(U32.read(Nat.show(value)), minimum, maximum)

def natural_defaults_valid(term: Natural) -> Bool:
  match term:
    case OptionalNumber{key, description, minimum, maximum, ConstantDefault{value}}:
      within_bounds(value, minimum, maximum)
    case _: True{}

def query_defaults_valid(query: Query) -> Bool:
  match query:
    case Read{task, after, limit}: natural_defaults_valid(task) && natural_defaults_valid(after) && natural_defaults_valid(limit)
    case Search{query, project, work, after, limit}: natural_defaults_valid(project) && natural_defaults_valid(work) && natural_defaults_valid(after) && natural_defaults_valid(limit)
    case Project{project}: natural_defaults_valid(project)
    case _: True{}

def defaults_valid(body: Body) -> Bool:
  match body:
    case Observe{query}: query_defaults_valid(query)
    case Send{task, message}: natural_defaults_valid(task)
    case Steer{task, message}: natural_defaults_valid(task)
    case Archive{task}: natural_defaults_valid(task)
    case Cancel{task, operation}: natural_defaults_valid(task) && natural_defaults_valid(operation)
    case Fork{count, messages, settings}: natural_defaults_valid(count)
    case _: True{}

# A caller default depends on the invoking task, so its bounds are admitted
# with that invocation. Constant defaults were admitted when the tool was made.
def caller_default_valid(value: J.Json, caller: Nat, minimum: U32, maximum: U32) -> Bool:
  match value:
    case J.Null{}: within_bounds(caller, minimum, maximum)
    case _: True{}

def natural_caller_valid(term: Natural, +args: J.Json, caller: Nat) -> Bool:
  match term:
    case OptionalNumber{key, description, minimum, maximum, CallerDefault{}}:
      caller_default_valid(J.get(args, key), caller, minimum, maximum)
    case _: True{}

def query_caller_valid(query: Query, +args: J.Json, +caller: Nat) -> Bool:
  match query:
    case Read{task, after, limit}: natural_caller_valid(task, args, caller) && natural_caller_valid(after, args, caller) && natural_caller_valid(limit, args, caller)
    case Search{query, project, work, after, limit}: natural_caller_valid(project, args, caller) && natural_caller_valid(work, args, caller) && natural_caller_valid(after, args, caller) && natural_caller_valid(limit, args, caller)
    case Project{project}: natural_caller_valid(project, args, caller)
    case _: True{}

def caller_arguments_valid(body: Body, +args: J.Json, +caller: Nat) -> Bool:
  match body:
    case Observe{query}: query_caller_valid(query, args, caller)
    case Send{task, message}: natural_caller_valid(task, args, caller)
    case Steer{task, message}: natural_caller_valid(task, args, caller)
    case Archive{task}: natural_caller_valid(task, args, caller)
    case Cancel{task, operation}: natural_caller_valid(task, args, caller) && natural_caller_valid(operation, args, caller)
    case Fork{count, messages, settings}: natural_caller_valid(count, args, caller)
    case _: True{}

def text_or(value: J.Json, fallback: String) -> String:
  match value:
    case J.Text{value}: value
    case _: fallback

def text(term: Text, +args: J.Json) -> String:
  match term:
    case TextConstant{value}: value
    case TextArgument{key, description, required, fallback}:
      text_or(J.get(args, key), fallback)

def texts(term: Texts, +args: J.Json) -> +List<String>:
  match term:
    case TextsConstant{value}: value
    case TextsArgument{key, description, required}: J.text_values(J.items(J.get(args, key)))

def settings(term: Settings, +args: J.Json) -> J.Json:
  match term:
    case SettingsConstant{value}: value
    case SettingsArgument{key, required}: J.get(args, key)

def strings_json(values: +List<String>) -> J.Json:
  J.Array{J.text_items(values)}

def default_json(value: NaturalDefault) -> J.Json:
  match value:
    case ConstantDefault{value}: J.Object{[J.Field{"kind", J.Text{"ConstantDefault"}}, J.Field{"value", J.Number{Nat.show(value)}}]}
    case CallerDefault{}: J.Object{[J.Field{"kind", J.Text{"CallerDefault"}}]}

def number_json(value: Natural) -> J.Json:
  match value:
    case Constant{value}: J.Object{[J.Field{"kind", J.Text{"Constant"}}, J.Field{"value", J.Number{Nat.show(value)}}]}
    case Caller{}: J.Object{[J.Field{"kind", J.Text{"Caller"}}]}
    case RequiredNumber{key, description, minimum, maximum}: J.Object{[J.Field{"kind", J.Text{"RequiredNumber"}}, J.Field{"key", J.Text{key}}, J.Field{"description", J.Text{description}}, J.Field{"minimum", J.Number{U32.show(minimum)}}, J.Field{"maximum", J.Number{U32.show(maximum)}}]}
    case OptionalNumber{key, description, minimum, maximum, fallback}: J.Object{[J.Field{"kind", J.Text{"OptionalNumber"}}, J.Field{"key", J.Text{key}}, J.Field{"description", J.Text{description}}, J.Field{"minimum", J.Number{U32.show(minimum)}}, J.Field{"maximum", J.Number{U32.show(maximum)}}, J.Field{"fallback", default_json(fallback)}]}

def text_json(value: Text) -> J.Json:
  match value:
    case TextConstant{value}: J.Object{[J.Field{"kind", J.Text{"TextConstant"}}, J.Field{"value", J.Text{value}}]}
    case TextArgument{key, description, required, fallback}: J.Object{[J.Field{"kind", J.Text{"TextArgument"}}, J.Field{"key", J.Text{key}}, J.Field{"description", J.Text{description}}, J.Field{"required", J.Boolean{required}}, J.Field{"fallback", J.Text{fallback}}]}

def texts_json(value: Texts) -> J.Json:
  match value:
    case TextsConstant{value}: J.Object{[J.Field{"kind", J.Text{"TextsConstant"}}, J.Field{"value", strings_json(value)}]}
    case TextsArgument{key, description, required}: J.Object{[J.Field{"kind", J.Text{"TextsArgument"}}, J.Field{"key", J.Text{key}}, J.Field{"description", J.Text{description}}, J.Field{"required", J.Boolean{required}}]}

def settings_json(value: Settings) -> J.Json:
  match value:
    case SettingsConstant{value}: J.Object{[J.Field{"kind", J.Text{"SettingsConstant"}}, J.Field{"value", value}]}
    case SettingsArgument{key, required}: J.Object{[J.Field{"kind", J.Text{"SettingsArgument"}}, J.Field{"key", J.Text{key}}, J.Field{"required", J.Boolean{required}}]}

def query_json(value: Query) -> J.Json:
  match value:
    case Read{task, after, limit}: J.Object{[J.Field{"kind", J.Text{"Read"}}, J.Field{"task", number_json(task)}, J.Field{"after", number_json(after)}, J.Field{"limit", number_json(limit)}]}
    case Search{query, project, work, after, limit}: J.Object{[J.Field{"kind", J.Text{"Search"}}, J.Field{"query", text_json(query)}, J.Field{"project", number_json(project)}, J.Field{"work", number_json(work)}, J.Field{"after", number_json(after)}, J.Field{"limit", number_json(limit)}]}
    case Tasks{}: J.Object{[J.Field{"kind", J.Text{"Tasks"}}]}
    case Describe{}: J.Object{[J.Field{"kind", J.Text{"Describe"}}]}
    case Projects{}: J.Object{[J.Field{"kind", J.Text{"Projects"}}]}
    case Project{project}: J.Object{[J.Field{"kind", J.Text{"Project"}}, J.Field{"project", number_json(project)}]}

def json(value: Body) -> J.Json:
  match value:
    case Discover{}: J.Object{[J.Field{"kind", J.Text{"Discover"}}]}
    case Observe{query}: J.Object{[J.Field{"kind", J.Text{"Observe"}}, J.Field{"query", query_json(query)}]}
    case Create{profile, reasoning, message, settings}: J.Object{[J.Field{"kind", J.Text{"Create"}}, J.Field{"profile", text_json(profile)}, J.Field{"reasoning", text_json(reasoning)}, J.Field{"message", text_json(message)}, J.Field{"settings", settings_json(settings)}]}
    case Feature{operation, schema}: J.Object{[J.Field{"kind", J.Text{"Feature"}}, J.Field{"operation", J.Text{operation}}, J.Field{"schema", schema}]}
    case Send{task, message}: J.Object{[J.Field{"kind", J.Text{"Send"}}, J.Field{"task", number_json(task)}, J.Field{"message", text_json(message)}]}
    case Steer{task, message}: J.Object{[J.Field{"kind", J.Text{"Steer"}}, J.Field{"task", number_json(task)}, J.Field{"message", text_json(message)}]}
    case Archive{task}: J.Object{[J.Field{"kind", J.Text{"Archive"}}, J.Field{"task", number_json(task)}]}
    case Cancel{task, operation}: J.Object{[J.Field{"kind", J.Text{"Cancel"}}, J.Field{"task", number_json(task)}, J.Field{"operation", number_json(operation)}]}
    case Fork{count, messages, settings}: J.Object{[J.Field{"kind", J.Text{"Fork"}}, J.Field{"count", number_json(count)}, J.Field{"messages", texts_json(messages)}, J.Field{"settings", settings_json(settings)}]}
    case Process{}: J.Object{[J.Field{"kind", J.Text{"Process"}}]}
    case ProcessRead{}: J.Object{[J.Field{"kind", J.Text{"ProcessRead"}}]}
    case ProcessWrite{}: J.Object{[J.Field{"kind", J.Text{"ProcessWrite"}}]}
    case ReadImage{}: J.Object{[J.Field{"kind", J.Text{"ReadImage"}}]}

def same(left: Body, right: Body) -> Bool:
  J.same(json(left), json(right))
