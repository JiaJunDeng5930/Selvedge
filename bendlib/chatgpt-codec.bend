import Base
import ../CHATGPT.bend as G
import ./domain.bend as D
import ./json.bend as J
import ./schema.bend as Schema
import ./association-map.bend as Finite

type WriteKind is Data:
  ConfigureKind{}
  RunKind{}
  CancelKind{}
  ForgetKind{}

type ReadKind is Data:
  ProjectsKind{}
  ProjectKind{}
  OperationKind{}
  OperationsKind{}

type EntryKind is Data:
  Write{kind: WriteKind}
  Read{kind: ReadKind}

type Spec is Data:
  Spec{name: String, description: String, kind: EntryKind, schema: J.Json}

def array(items: J.Json) -> J.Json:
  J.Object{[J.Field{"type", J.Text{"array"}}, J.Field{"items", items}]}

def id_schema() -> J.Json:
  G.integer_schema(0n, 4294967295n)

def sandbox_schema() -> J.Json:
  D.object_schema([J.Field{"mode", D.string_schema("read-only or workspace-write")},
    J.Field{"network_access", J.Object{[J.Field{"type", J.Text{"boolean"}}]}}],
    [J.Text{"mode"}, J.Text{"network_access"}])

def grant_schema() -> J.Json:
  D.object_schema([J.Field{"connection_id", id_schema()}, J.Field{"project_ids", array(id_schema())},
    J.Field{"sandbox", sandbox_schema()}], [J.Text{"connection_id"}, J.Text{"project_ids"}, J.Text{"sandbox"}])

def connection_fields() -> +List<J.Field>:
  [J.Field{"connection_id", id_schema()}]

def project_fields() -> +List<J.Field>:
  J.Field{"project_id", id_schema()} <> connection_fields()

def operation_schema() -> J.Json:
  D.command_schema(J.Field{"operation_id", id_schema()} <> project_fields(),
    [J.Text{"connection_id"}, J.Text{"project_id"}, J.Text{"operation_id"}])

def write_schema(kind: WriteKind) -> J.Json:
  match kind:
    case ConfigureKind{}: D.command_schema([J.Field{"connections", array(grant_schema())}], [J.Text{"connections"}])
    case RunKind{}: D.command_schema(J.Field{"request_id", G.text_schema()} <> J.Field{"arguments", G.args_schema()} <> project_fields(),
      [J.Text{"connection_id"}, J.Text{"project_id"}, J.Text{"request_id"}, J.Text{"arguments"}])
    case CancelKind{}: operation_schema()
    case ForgetKind{}: operation_schema()

def read_schema(kind: ReadKind) -> J.Json:
  match kind:
    case ProjectsKind{}: D.command_schema(connection_fields(), [J.Text{"connection_id"}])
    case ProjectKind{}: D.command_schema(project_fields(), [J.Text{"connection_id"}, J.Text{"project_id"}])
    case OperationKind{}: operation_schema()
    case OperationsKind{}: D.command_schema(project_fields(), [J.Text{"connection_id"}, J.Text{"project_id"}])

def specs() -> +List<Spec>:
  [Spec{"configure_chatgpt_connections", "Replace local ChatGPT connection grants; administrative access only.", Write{ConfigureKind{}}, write_schema(ConfigureKind{})},
   Spec{"chatgpt_exec", "Commit one project-scoped Bash operation. Retained request IDs deduplicate retries.", Write{RunKind{}}, write_schema(RunKind{})},
   Spec{"chatgpt_cancel", "Interrupt one connection-owned operation; physical changes are not undone.", Write{CancelKind{}}, write_schema(CancelKind{})},
   Spec{"chatgpt_forget", "Delete a settled receipt and end its request-ID deduplication retention.", Write{ForgetKind{}}, write_schema(ForgetKind{})},
   Spec{"chatgpt_projects", "List only projects granted to this connection.", Read{ProjectsKind{}}, read_schema(ProjectsKind{})},
   Spec{"chatgpt_project", "Read an authorized project and its root guidance.", Read{ProjectKind{}}, read_schema(ProjectKind{})},
   Spec{"chatgpt_operation", "Read one operation owned by this connection and project.", Read{OperationKind{}}, read_schema(OperationKind{})},
   Spec{"chatgpt_operations", "List bounded operation summaries, without their output bodies.", Read{OperationsKind{}}, read_schema(OperationsKind{})}]

def number(value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)

def numbers(values: +List<J.Json>) -> +List<Nat>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: number(value) <> numbers(rest)

def mode(name: String) -> D.SandboxMode:
  match name:
    case "read-only": D.ReadOnly{}
    case _: D.WorkspaceWrite{}

def sandbox(+value: J.Json) -> D.Sandbox:
  D.Sandbox{mode(J.text(J.get(value, "mode"))), J.boolean(J.get(value, "network_access"))}

def grants(values: +List<J.Json>) -> +List<Finite.Entry(G.Grant)>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}: (number(J.get(value, "connection_id")),
      G.Grant{numbers(J.items(J.get(value, "project_ids"))), sandbox(J.get(value, "sandbox"))}) <> grants(rest)

def construct(kind: WriteKind, +body: J.Json) -> G.Command:
  match kind:
    case ConfigureKind{}: G.Configure{grants(J.items(J.get(body, "connections")))}
    case RunKind{}: G.Run{number(J.get(body, "connection_id")), number(J.get(body, "project_id")),
      J.text(J.get(body, "request_id")), J.get(body, "arguments")}
    case CancelKind{}: G.Cancel{number(J.get(body, "connection_id")), number(J.get(body, "project_id")), number(J.get(body, "operation_id"))}
    case ForgetKind{}: G.Forget{number(J.get(body, "connection_id")), number(J.get(body, "project_id")), number(J.get(body, "operation_id"))}

def query(kind: ReadKind, +body: J.Json) -> G.Query:
  match kind:
    case ProjectsKind{}: G.ListProjects{number(J.get(body, "connection_id"))}
    case ProjectKind{}: G.ReadProject{number(J.get(body, "connection_id")), number(J.get(body, "project_id"))}
    case OperationKind{}: G.ReadJob{number(J.get(body, "connection_id")), number(J.get(body, "project_id")), number(J.get(body, "operation_id"))}
    case OperationsKind{}: G.ListJobs{number(J.get(body, "connection_id")), number(J.get(body, "project_id"))}

def grant_modes(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}:
      (String.eq(J.text(J.get(J.get(value, "sandbox"), "mode")), "read-only") ||
       String.eq(J.text(J.get(J.get(value, "sandbox"), "mode")), "workspace-write")) && grant_modes(rest)

def valid(kind: EntryKind, +body: J.Json) -> Bool:
  match kind:
    case Write{ConfigureKind{}}: Schema.valid(write_schema(ConfigureKind{}), body) && grant_modes(J.items(J.get(body, "connections")))
    case Write{kind}: Schema.valid(write_schema(kind), body)
    case Read{kind}: Schema.valid(read_schema(kind), body)

def number_json(values: +List<Nat>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: J.nat(value) <> number_json(rest)

def grants_json(entries: +List<Finite.Entry(G.Grant)>) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, G.Grant{ids, sandbox}), rest}:
      J.Object{[J.Field{"connection_id", J.nat(id)}, J.Field{"project_ids", J.Array{number_json(ids)}},
        J.Field{"sandbox", D.sandbox_json(sandbox)}]} <> grants_json(rest)

def command(op: String, fields: +List<J.Field>) -> J.Json:
  J.Object{J.Field{"op", J.Text{op}} <> fields}

def identity(connection: Nat, project: Nat) -> +List<J.Field>:
  [J.Field{"connection_id", J.nat(connection)}, J.Field{"project_id", J.nat(project)}]

def command_json(value: G.Command) -> J.Json:
  match value:
    case G.Configure{entries}: command("configure_chatgpt_connections", [J.Field{"connections", J.Array{grants_json(entries)}}])
    case G.Run{connection, project, request, arguments}: command("chatgpt_exec",
      J.Field{"request_id", J.Text{request}} <> J.Field{"arguments", arguments} <> identity(connection, project))
    case G.Cancel{connection, project, operation}: command("chatgpt_cancel", J.Field{"operation_id", J.nat(operation)} <> identity(connection, project))
    case G.Forget{connection, project, operation}: command("chatgpt_forget", J.Field{"operation_id", J.nat(operation)} <> identity(connection, project))

def query_json(value: G.Query) -> J.Json:
  match value:
    case G.ListProjects{connection}: command("chatgpt_projects", [J.Field{"connection_id", J.nat(connection)}])
    case G.ReadProject{connection, project}: command("chatgpt_project", identity(connection, project))
    case G.ReadJob{connection, project, operation}: command("chatgpt_operation", J.Field{"operation_id", J.nat(operation)} <> identity(connection, project))
    case G.ListJobs{connection, project}: command("chatgpt_operations", identity(connection, project))
