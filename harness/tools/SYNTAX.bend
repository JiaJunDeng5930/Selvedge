import Base
import ../../bendlib/json.bend as J

type NaturalDefault is Data:
  ConstantDefault{value: Nat}
  CallerDefault{}

type Natural is Data:
  Constant{value: Nat}
  Caller{}
  NumberArgument{key: String, description: String, minimum: U32, maximum: U32, required: Bool, fallback: NaturalDefault}

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
  Tasks{}
  Describe{}
  Projects{}
  Project{project: Natural}

type Body is Data:
  Observe{query: Query}
  Create{profile: Text, reasoning: Text, message: Text, settings: Settings}
  Feature{operation: String, schema: J.Json}
  Send{task: Natural, message: Text}
  Steer{task: Natural, message: Text}
  Archive{task: Natural}
  Cancel{task: Natural, operation: Natural}
  Fork{count: Natural, messages: Texts, settings: Settings}
  Process{}

def external(body: Body) -> Bool:
  match body:
    case Process{}: True{}
    case _: False{}

def default_number(fallback: NaturalDefault, caller: Nat) -> Nat:
  match fallback:
    case ConstantDefault{value}: value
    case CallerDefault{}: caller

def number(term: Natural, +args: J.Json, caller: Nat) -> Nat:
  match term:
    case Constant{value}: value
    case Caller{}: caller
    case NumberArgument{key, description, minimum, maximum, required, fallback}:
      J.natural_or(J.natural(J.get(args, key)), default_number(fallback, caller))

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
    case NumberArgument{key, description, minimum, maximum, required, fallback}: J.Object{[J.Field{"kind", J.Text{"NumberArgument"}}, J.Field{"key", J.Text{key}}, J.Field{"description", J.Text{description}}, J.Field{"minimum", J.Number{U32.show(minimum)}}, J.Field{"maximum", J.Number{U32.show(maximum)}}, J.Field{"required", J.Boolean{required}}, J.Field{"fallback", default_json(fallback)}]}

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
    case Tasks{}: J.Object{[J.Field{"kind", J.Text{"Tasks"}}]}
    case Describe{}: J.Object{[J.Field{"kind", J.Text{"Describe"}}]}
    case Projects{}: J.Object{[J.Field{"kind", J.Text{"Projects"}}]}
    case Project{project}: J.Object{[J.Field{"kind", J.Text{"Project"}}, J.Field{"project", number_json(project)}]}

def json(value: Body) -> J.Json:
  match value:
    case Observe{query}: J.Object{[J.Field{"kind", J.Text{"Observe"}}, J.Field{"query", query_json(query)}]}
    case Create{profile, reasoning, message, settings}: J.Object{[J.Field{"kind", J.Text{"Create"}}, J.Field{"profile", text_json(profile)}, J.Field{"reasoning", text_json(reasoning)}, J.Field{"message", text_json(message)}, J.Field{"settings", settings_json(settings)}]}
    case Feature{operation, schema}: J.Object{[J.Field{"kind", J.Text{"Feature"}}, J.Field{"operation", J.Text{operation}}, J.Field{"schema", schema}]}
    case Send{task, message}: J.Object{[J.Field{"kind", J.Text{"Send"}}, J.Field{"task", number_json(task)}, J.Field{"message", text_json(message)}]}
    case Steer{task, message}: J.Object{[J.Field{"kind", J.Text{"Steer"}}, J.Field{"task", number_json(task)}, J.Field{"message", text_json(message)}]}
    case Archive{task}: J.Object{[J.Field{"kind", J.Text{"Archive"}}, J.Field{"task", number_json(task)}]}
    case Cancel{task, operation}: J.Object{[J.Field{"kind", J.Text{"Cancel"}}, J.Field{"task", number_json(task)}, J.Field{"operation", number_json(operation)}]}
    case Fork{count, messages, settings}: J.Object{[J.Field{"kind", J.Text{"Fork"}}, J.Field{"count", number_json(count)}, J.Field{"messages", texts_json(messages)}, J.Field{"settings", settings_json(settings)}]}
    case Process{}: J.Object{[J.Field{"kind", J.Text{"Process"}}]}

def same(left: Body, right: Body) -> Bool:
  J.same(json(left), json(right))
