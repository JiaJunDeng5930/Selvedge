import Base
import ../../harness/DOMAIN.bend as D
import ./MODEL.bend as W
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite
import ../../harness/transport/schema.bend as Schema

type WriteKind is Data:
  CreateKind{}
  RenameKind{}
  CreateTaskKind{}

type ReadKind is Data:
  WorksKind{}
  WorkKind{}

type EntryKind is Data:
  Write{kind: WriteKind}
  Read{kind: ReadKind}

type Spec is Data:
  Spec{name: String, description: String, kind: EntryKind, schema: J.Json}

def text_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"string"}}]}

def boolean_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"boolean"}}]}

def integer_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"integer"}}, J.Field{"minimum", J.Number{"0"}}, J.Field{"maximum", J.Number{"4294967295"}}]}

def command_schema(properties: +List<J.Field>, required: +List<J.Json>) -> J.Json:
  Schema.object(J.Field{"op", text_schema()} <> properties, J.Text{"op"} <> required)

def specifications(task_settings: J.Json) -> +List<Spec>:
  [Spec{"create_work", "Create a Work independent of Projects; an omitted name becomes Work #id.", Write{CreateKind{}},
      command_schema([J.Field{"name", text_schema()}], Nil{})},
   Spec{"rename_work", "Rename a Work while preserving its Tasks and Task graphs.", Write{RenameKind{}},
      command_schema([J.Field{"work_id", integer_schema()}, J.Field{"name", text_schema()}], [J.Text{"work_id"}, J.Text{"name"}])},
   Spec{"create_work_task", "Create a root Task and record its immutable Work ownership atomically; optionally create a managed worktree.", Write{CreateTaskKind{}},
      command_schema([J.Field{"work_id", integer_schema()}, J.Field{"profile", text_schema()}, J.Field{"reasoning", text_schema()},
        J.Field{"message", D.content_schema("Initial user request")}, J.Field{"images", D.images_schema()}, J.Field{"settings", task_settings}, J.Field{"create_worktree", boolean_schema()}],
        [J.Text{"work_id"}, J.Text{"profile"}])},
   Spec{"list_works", "Observe Works with their derived Task IDs and associated Task graph IDs.", Read{WorksKind{}},
      command_schema(Nil{}, Nil{})},
   Spec{"read_work", "Observe one Work with its derived Task IDs and associated Task graph IDs.", Read{WorkKind{}},
      command_schema([J.Field{"work_id", integer_schema()}], [J.Text{"work_id"}])}]

def find_spec(+name: String, specs: +List<Spec>) -> Maybe<&2, Spec>:
  match specs:
    case Nil{}: None{}
    case Con{Spec{+candidate, description, kind, schema}, rest}:
      Finite.choose(~Spec, String.eq(name, candidate), Spec{candidate, description, kind, schema}, find_spec(name, rest))

def lookup(name: String, task_settings: J.Json) -> Maybe<&2, Spec>:
  find_spec(name, specifications(task_settings))

def present(+body: J.Json, key: String) -> Bool:
  match body:
    case J.Object{fields}: Schema.exists(fields, key)
    case _: False{}

def optional_text(+body: J.Json, +key: String) -> Bool:
  Bool.not(present(body, key)) || J.is_text(J.get(body, key))

def optional_settings(+body: J.Json) -> Bool:
  Bool.not(present(body, "settings")) || J.is_object(J.get(body, "settings"))

def optional_boolean(+body: J.Json, +key: String) -> Bool:
  Bool.not(present(body, key)) || Schema.valid(boolean_schema(), J.get(body, key))

def natural(value: J.Json) -> Bool:
  Schema.valid(integer_schema(), value)

def operation_matches(+body: J.Json, name: String) -> Bool:
  Bool.not(present(body, "op")) || J.same(J.get(body, "op"), J.Text{name})

def valid(kind: WriteKind, +body: J.Json) -> Bool:
  match kind:
    case CreateKind{}: Schema.keys(body, ["op", "name"]) && operation_matches(body, "create_work") && optional_text(body, "name")
    case RenameKind{}: Schema.keys(body, ["op", "work_id", "name"]) && operation_matches(body, "rename_work") &&
      natural(J.get(body, "work_id")) && J.is_text(J.get(body, "name"))
    case CreateTaskKind{}: Schema.keys(body, ["op", "work_id", "profile", "reasoning", "message", "images", "settings", "create_worktree"]) &&
      operation_matches(body, "create_work_task") && natural(J.get(body, "work_id")) && J.is_text(J.get(body, "profile")) &&
      optional_text(body, "reasoning") && D.content_valid(D.user_content(J.get(body, "message"), J.get(body, "images"))) && optional_settings(body) && optional_boolean(body, "create_worktree")

def entry_valid(kind: EntryKind, +body: J.Json) -> Bool:
  match kind:
    case Write{kind}: valid(kind, body)
    case Read{WorksKind{}}: Schema.keys(body, ["op"]) && operation_matches(body, "list_works")
    case Read{WorkKind{}}: Schema.keys(body, ["op", "work_id"]) && operation_matches(body, "read_work") && natural(J.get(body, "work_id"))

def number(value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)

def settings(value: J.Json) -> J.Json:
  match value:
    case J.Object{fields}: J.Object{fields}
    case _: J.Object{Nil{}}

def construct(kind: WriteKind, +body: J.Json) -> W.Command:
  match kind:
    case CreateKind{}: W.Create{J.text(J.get(body, "name"))}
    case RenameKind{}: W.Rename{number(J.get(body, "work_id")), J.text(J.get(body, "name"))}
    case CreateTaskKind{}: W.CreateTask{number(J.get(body, "work_id")), J.text(J.get(body, "profile")),
      J.text_or(J.get(body, "reasoning"), "default"), D.user_content(J.get(body, "message"), J.get(body, "images")), settings(J.get(body, "settings")),
      J.boolean(J.get(body, "create_worktree"))}

def query(kind: ReadKind, body: J.Json) -> W.Query:
  match kind:
    case WorksKind{}: W.ListWorks{}
    case WorkKind{}: W.ReadWork{number(J.get(body, "work_id"))}

def command(op: String, fields: +List<J.Field>) -> J.Json:
  J.Object{J.Field{"op", J.Text{op}} <> fields}

def command_json(input: W.Command) -> J.Json:
  match input:
    case W.Create{name}: command("create_work", [J.Field{"name", J.Text{name}}])
    case W.Rename{id, name}: command("rename_work", [J.Field{"work_id", J.nat(id)}, J.Field{"name", J.Text{name}}])
    case W.CreateTask{work, profile, reasoning, message, settings, create_worktree}: command("create_work_task", [J.Field{"work_id", J.nat(work)},
      J.Field{"profile", J.Text{profile}}, J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", D.content_json(message)}, J.Field{"settings", settings},
      J.Field{"create_worktree", J.Boolean{create_worktree}}])

def query_json(input: W.Query) -> J.Json:
  match input:
    case W.ListWorks{}: command("list_works", Nil{})
    case W.ReadWork{id}: command("read_work", [J.Field{"work_id", J.nat(id)}])
