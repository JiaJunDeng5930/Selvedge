import Base
import ./MODEL.bend as A
import ../../harness/conversation/TITLE.bend as Title
import ../../harness/transport/schema.bend as Schema
import ../../harness/transport/wire-shape.bend as Shape
import ../../bendlib/json.bend as J

type EntryKind is Data:
  ConfigureKind{}
  SettingsKind{}

type Spec is Data:
  Spec{name: String, description: String, kind: EntryKind, schema: J.Json}

def text_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"string"}}, J.Field{"minLength", J.nat(1n)}, J.Field{"maxLength", J.nat(Title.maximum_instruction_bytes())}]}

def revision_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"integer"}}, J.Field{"minimum", J.nat(0n)}]}

def schema(+kind: EntryKind) -> J.Json:
  match kind:
    case SettingsKind{}: Schema.object([J.Field{"op", J.Object{[J.Field{"type", J.Text{"string"}}]}}], [J.Text{"op"}])
    case ConfigureKind{}: Schema.object([
      J.Field{"op", J.Object{[J.Field{"type", J.Text{"string"}}]}},
      J.Field{"revision", revision_schema()}, J.Field{"task_prompt", text_schema()}, J.Field{"agent_prompt", text_schema()}],
      [J.Text{"op"}, J.Text{"revision"}, J.Text{"task_prompt"}, J.Text{"agent_prompt"}])

def specs() -> +List<Spec>:
  [Spec{"read_title_settings", "Read independent Task board and Agent conversation title instructions.", SettingsKind{}, schema(SettingsKind{})},
   Spec{"configure_title_settings", "Save independent title instructions at their current revision; existing names and pending requests are preserved.", ConfigureKind{}, schema(ConfigureKind{})}]

def valid(kind: EntryKind, +body: J.Json) -> Bool:
  match kind:
    case SettingsKind{}: Shape.object_keys(body, ["op"])
    case ConfigureKind{}: Shape.object_keys(body, ["op", "revision", "task_prompt", "agent_prompt"]) &&
      Shape.is_natural(J.get(body, "revision")) && J.is_text(J.get(body, "task_prompt")) && J.is_text(J.get(body, "agent_prompt")) &&
      Title.valid_prompts(Title.Prompts{J.text(J.get(body, "task_prompt")), J.text(J.get(body, "agent_prompt"))})

def command(+body: J.Json) -> A.Command:
  A.Configure{J.natural_or(J.natural(J.get(body, "revision")), 0n),
    Title.Prompts{J.text(J.get(body, "task_prompt")), J.text(J.get(body, "agent_prompt"))}}

def command_json(command: A.Command) -> J.Json:
  A.Configure{revision, Title.Prompts{task, agent}} = command
  J.Object{[J.Field{"op", J.Text{"configure_title_settings"}}, J.Field{"revision", J.nat(revision)},
    J.Field{"task_prompt", J.Text{task}}, J.Field{"agent_prompt", J.Text{agent}}]}

def query_json(query: A.Query) -> J.Json:
  J.Object{[J.Field{"op", J.Text{"read_title_settings"}}]}

def settings(+state: A.State) -> J.Json:
  J.Object{[J.Field{"revision", J.nat(A.revision(state))},
    J.Field{"task_prompt", J.Text{Title.task_instructions(A.prompts(state))}},
    J.Field{"agent_prompt", J.Text{Title.agent_instructions(A.prompts(state))}}]}
