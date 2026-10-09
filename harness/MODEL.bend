import Base
import ../bendlib/effects.bend as Effects
import ./features/MODEL.bend as F
import ../bendlib/component.bend as C
import ./DOMAIN.bend as D
import ./reasoning/MODEL.bend as Reasoning
import ../bendlib/json.bend as J

# This module assembles application state and the component vocabularies.
def World() -> Data:
  C.Frame<D.State, F.State()>

def initial() -> World():
  C.Frame{D.initial_state(), F.initial()}

def Effect() -> Data:
  Effects.Effect<F.Effect>

# A public query observes a world without acquiring permission to advance it.
# A tool may use the same query, then durably append its own tool result.

type Query is Data:
  Read{task_id: Nat, after: Nat, limit: Nat}
  ListTasks{}
  Describe{}
  ListProjects{}
  ReadProject{project_id: Nat}
  FeatureQuery{query: F.Query}

type Command is Data:
  Create{profile: String, reasoning: String, message: String, settings: J.Json}
  Send{task_id: Nat, message: String}
  Steer{task_id: Nat, message: String}
  Cancel{task_id: Nat, operation_id: Nat}
  ChangeStatus{task_id: Nat, control: D.Control}
  Fork{task_id: Nat, count: Nat, messages: +List<String>, settings: J.Json}
  Compact{task_id: Nat, summary: Maybe<&2, String>}
  Observe{query: Query}
  CreateProject{name: String, workspace: J.Json, guidance: J.Json}
  UpdateProject{project_id: Nat, name: Maybe<&2, String>, workspace: J.Json, guidance: J.Json}
  DeleteProject{project_id: Nat}
  ReviewApproval{task_id: Nat, operation_id: Nat, outcome: D.ApprovalOutcome}
  FeatureCommand{command: F.Command}

type CommandKind is Data:
  CreateCommand{}
  SendCommand{}
  SteerCommand{}
  CancelCommand{}
  ControlCommand{control: D.Control}
  ForkCommand{}
  CompactCommand{}
  ReadCommand{}
  ListCommand{}
  DescribeCommand{}
  CreateProjectCommand{}
  UpdateProjectCommand{}
  DeleteProjectCommand{}
  ListProjectsCommand{}
  ReadProjectCommand{}
  ReviewApprovalCommand{}
  FeatureKind{kind: F.CommandKind}

type CommandSpec is Data:
  CommandSpec{name: String, description: String, kind: CommandKind, schema: J.Json}

def control_spec(+control: D.Control, description: String) -> CommandSpec:
  CommandSpec{D.control_name(control), description, ControlCommand{control},
    D.command_schema([J.Field{"task_id", D.task_id_schema()}], [J.Text{"task_id"}])}

# Clients obtain their command descriptions and validation schema from here.

def feature_specs(specs: +List<F.CommandSpec>) -> +List<CommandSpec>:
  match specs:
    case Nil{}: Nil{}
    case Con{F.CommandSpec{name, description, kind, schema}, rest}:
      CommandSpec{name, description, FeatureKind{kind}, schema} <> feature_specs(rest)

def commands() -> +List<CommandSpec>:
  List.append(&2, CommandSpec, feature_specs(F.specs(D.task_settings_schema())),
  [CommandSpec{"create", "Start an agent with a frozen model and tool contract.", CreateCommand{},
     D.command_schema([J.Field{"profile", D.string_schema("Configured model profile")},
       J.Field{"reasoning", D.string_schema("Reasoning effort; defaults to medium")},
       J.Field{"message", D.string_schema("Initial user request")}, J.Field{"settings", D.task_settings_schema()}], [J.Text{"profile"}, J.Text{"message"}])},
   CommandSpec{"send", "Commit or queue a user message; reactivate a stopped task.", SendCommand{},
     D.command_schema([J.Field{"task_id", D.task_id_schema()}, J.Field{"message", D.string_schema("User message")}],
       [J.Text{"task_id"}, J.Text{"message"}])},
   CommandSpec{"steer", "Replace current model work with immediate user input without cancelling independent operations or discarding queued follow-ups. Frozen tasks remain frozen.", SteerCommand{},
     D.command_schema([J.Field{"task_id", D.task_id_schema()}, J.Field{"message", D.string_schema("Immediate user instruction")}],
       [J.Text{"task_id"}, J.Text{"message"}])},
   CommandSpec{"cancel_operation", "Cancel one live operation. Other work continues; previous side effects cannot be undone.", CancelCommand{},
     D.command_schema([J.Field{"task_id", D.task_id_schema()}, J.Field{"operation_id", D.task_id_schema()}],
       [J.Text{"task_id"}, J.Text{"operation_id"}])},
   control_spec(D.Freeze{}, "Suspend dispatch without discarding accepted results."),
   control_spec(D.Unfreeze{}, "Resume a frozen task."),
   control_spec(D.Stop{}, "Settle accepted tools without requesting another model reply."),
   control_spec(D.Interrupt{}, "Cancel current work without archiving. Retain queued messages; record unknown outcomes for already-dispatched tools. A new message resumes the task."),
   control_spec(D.Archive{}, "Permanently archive a task and cancel external work."),
   CommandSpec{"compact", "Checkpoint an idle task without deleting original history. Without summary, request a model summary (active tasks only). A supplied bounded summary also works on stopped or frozen tasks, without calling a model.", CompactCommand{},
     D.command_schema([J.Field{"task_id", D.task_id_schema()}, J.Field{"summary", D.string_schema("Optional continuation note; useful when the provider cannot accept the old context. Read describe for the byte limit.")}], [J.Text{"task_id"}])},
   CommandSpec{"fork", "Fork an idle task, subject to every ancestor's descendant limit.", ForkCommand{},
     D.command_schema([J.Field{"task_id", D.task_id_schema()},
       J.Field{"child_count", D.integer_schema("Number of children", 1n, U32.to_nat(4294967295))},
       J.Field{"messages", J.Object{[J.Field{"type", J.Text{"array"}}, J.Field{"items", D.string_schema("Child request")}]}},
       J.Field{"settings", D.task_settings_schema()}],
       [J.Text{"task_id"}, J.Text{"child_count"}])},
   CommandSpec{"read", "Read a bounded history page without advancing the task.", ReadCommand{},
     D.command_schema([J.Field{"task_id", D.task_id_schema()}, J.Field{"after", D.integer_schema("History offset", 0n, U32.to_nat(4294967295))},
       J.Field{"limit", D.integer_schema("Page size; defaults to 100", 1n, 100n)}], [J.Text{"task_id"}])},
   CommandSpec{"list", "Read task summaries and the currently available model profiles and tools.", ListCommand{},
     D.command_schema(Nil{}, Nil{})},
   CommandSpec{"describe", "Read this executable command vocabulary and the effect-boundary limits.", DescribeCommand{},
     D.command_schema(Nil{}, Nil{})},
   CommandSpec{"create_project", "Create an organizational project with default workspace roots; existing tasks never follow later default changes.", CreateProjectCommand{},
     D.command_schema([J.Field{"name", D.string_schema("Project name")}, J.Field{"workspace", D.workspace_schema()},
       J.Field{"guidance", D.guidance_schema()}], [J.Text{"name"}, J.Text{"workspace"}])},
   CommandSpec{"update_project", "Change the project's name or workspace defaults without rewriting task contracts.", UpdateProjectCommand{},
     D.command_schema([J.Field{"project_id", D.task_id_schema()}, J.Field{"name", D.string_schema("Project name")},
       J.Field{"workspace", D.workspace_schema()}, J.Field{"guidance", D.guidance_schema()}], [J.Text{"project_id"}])},
   CommandSpec{"delete_project", "Delete an empty project. A project referenced by any task cannot be deleted.", DeleteProjectCommand{},
     D.command_schema([J.Field{"project_id", D.task_id_schema()}], [J.Text{"project_id"}])},
   CommandSpec{"list_projects", "Read project summaries without advancing tasks.", ListProjectsCommand{}, D.command_schema(Nil{}, Nil{})},
   CommandSpec{"read_project", "Read a project's workspace defaults and frozen root guidance.", ReadProjectCommand{},
     D.command_schema([J.Field{"project_id", D.task_id_schema()}], [J.Text{"project_id"}])},
   CommandSpec{"review_approval", "Approve exactly one pending human-reviewed command, or deny it. A grant cannot change the command, task settings, or any later operation.", ReviewApprovalCommand{},
     D.command_schema([J.Field{"task_id", D.task_id_schema()}, J.Field{"operation_id", D.task_id_schema()},
       J.Field{"decision", J.Object{[J.Field{"type", J.Text{"string"}}, J.Field{"enum", J.Array{[J.Text{"allow"}, J.Text{"deny"}]}}]}},
       J.Field{"reason", D.string_schema("Optional bounded explanation, at most 2048 UTF-8 bytes")}],
       [J.Text{"task_id"}, J.Text{"operation_id"}, J.Text{"decision"}])}])

def command_specs_json(specs: +List<CommandSpec>) -> +List<J.Json>:
  match specs:
    case Nil{}: Nil{}
    case Con{CommandSpec{name, description, kind, schema}, rest}:
      J.Object{[J.Field{"name", J.Text{name}}, J.Field{"description", J.Text{description}}, J.Field{"schema", schema}]} <>
        command_specs_json(rest)

def description() -> J.Json:
  J.Object{[J.Field{"commands", J.Array{command_specs_json(commands())}}, J.Field{"limits", D.boundary_limits()},
    J.Field{"plugins", J.Object{[J.Field{"protocolVersion", J.Text{"selvedge-plugin-2"}}, J.Field{"max_plugins", J.nat(D.plugin_limit())},
      J.Field{"events", J.Array{J.text_items(D.plugin_events())}}]}}]}

type Input is Data:
  UserCommand{command: Command}
  ModelCompleted{task_id: Nat, ticket: Nat, outcome: D.Outcome}
  ReasoningCompleted{task_id: Nat, ticket: Nat, outcome: Reasoning.Outcome}
  FeatureCompleted{completion: F.Completion}
  ToolCompleted{task_id: Nat, ticket: Nat, value: J.Json, error: Bool}
  HookCompleted{task_id: Nat, ticket: Nat, outcome: D.HookOutcome}
  AfterCompleted{task_id: Nat, operation_id: Nat, ticket: Nat, outcome: D.AfterOutcome}
  ApprovalCompleted{task_id: Nat, ticket: Nat, outcome: D.ApprovalOutcome}
  Configure{environment: D.Environment}
  Recover{}
  Continue{}

def Decision() -> Data:
  C.Decision<World(), Effect()>

type InputMode is Data:
  Observation{}
  UpdateOnly{}
  UpdateAndSchedule{}

# Persistence and scheduling derive from the same classification. Configuration
# commits a catalog without starting work before startup recovery has run.

def input_mode(input: Input) -> InputMode:
  match input:
    case UserCommand{Observe{query}}: Observation{}
    case Configure{environment}: UpdateOnly{}
    case _: UpdateAndSchedule{}

def mode_durable(mode: InputMode) -> Bool:
  match mode:
    case Observation{}: False{}
    case _: True{}

def mode_schedules(mode: InputMode) -> Bool:
  match mode:
    case UpdateAndSchedule{}: True{}
    case _: False{}

def durable(input: Input) -> Bool:
  mode_durable(input_mode(input))

def schedules(input: Input) -> Bool:
  mode_schedules(input_mode(input))
