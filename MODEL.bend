import Base
import ./bendlib/json.bend as J

# Persistent agents: a task has its own lifecycle and immutable contract.
# Its lineage describes task ancestry; History describes message ancestry.
# A fork shares History but adds a task ancestor. Those are different relations.
type Status is Data:
  Active{}
  Frozen{}
  Stopped{}
  Archived{}

type Control is Data:
  Freeze{}
  Unfreeze{}
  Stop{}
  Archive{}

def status_name(status: Status) -> String:
  match status:
    case Active{}: "active"
    case Frozen{}: "frozen"
    case Stopped{}: "stopped"
    case Archived{}: "archived"

def control_name(control: Control) -> String:
  match control:
    case Freeze{}: "freeze"
    case Unfreeze{}: "unfreeze"
    case Stop{}: "stop"
    case Archive{}: "archive"

# This table is also used to derive the controls exposed to clients.
def control(status: Status, request: Control) -> Maybe<&2, Status>:
  match status request:
    case Active{} Freeze{}: Some{Frozen{}}
    case Frozen{} Unfreeze{}: Some{Active{}}
    case Active{} Stop{}: Some{Stopped{}}
    case Active{} Archive{}: Some{Archived{}}
    case Frozen{} Archive{}: Some{Archived{}}
    case Stopped{} Archive{}: Some{Archived{}}
    case _ _: None{}

def retain_status(result: Maybe<&2, Status>, previous: Status) -> Status:
  match result:
    case Some{next}: next
    case None{}: previous

def control_total(+status: Status, request: Control) -> Status:
  retain_status(control(status, request), status)

def control_entry(result: Maybe<&2, Status>, name: String, rest: +List<J.Json>) -> +List<J.Json>:
  match result:
    case Some{next}: J.Text{name} <> rest
    case None{}: rest

def controls(+status: Status) -> J.Json:
  J.Array{control_entry(control(status, Freeze{}), "freeze",
    control_entry(control(status, Unfreeze{}), "unfreeze",
    control_entry(control(status, Stop{}), "stop",
    control_entry(control(status, Archive{}), "archive", Nil{}))))}

def accepts_input(status: Status) -> Bool:
  match status:
    case Archived{}: False{}
    case _: True{}

def after_input(status: Status) -> Status:
  match status:
    case Stopped{}: Active{}
    case other: other

type Builtin is Data:
  ForkTask{}
  ReadTask{}
  SendMessage{}
  ArchiveTask{}
  Bash{}

type Source is Data:
  Harness{tool: Builtin}
  Mcp{server: String, remote: String}

type Recovery is Data:
  RetrySafe{}
  OutcomeUnknown{}

type Tool is Data:
  Tool{name: String, description: String, schema: J.Json, source: Source}

# Internal task operations and their outputs commit in the same journal record.
# External execution has no such atomicity. Its unknown outcomes are not retried.
def recovery(source: Source) -> Recovery:
  match source:
    case Harness{Bash{}}: OutcomeUnknown{}
    case Harness{_}: RetrySafe{}
    case Mcp{server, remote}: OutcomeUnknown{}

def tool_name(tool: Tool) -> String:
  Tool{name, description, schema, source} = tool
  name

def tool_source(tool: Tool) -> Source:
  Tool{name, description, schema, source} = tool
  source

def source_same(a: Source, b: Source) -> Bool:
  match a b:
    case Harness{ForkTask{}} Harness{ForkTask{}}: True{}
    case Harness{ReadTask{}} Harness{ReadTask{}}: True{}
    case Harness{SendMessage{}} Harness{SendMessage{}}: True{}
    case Harness{ArchiveTask{}} Harness{ArchiveTask{}}: True{}
    case Harness{Bash{}} Harness{Bash{}}: True{}
    case Mcp{server_a, remote_a} Mcp{server_b, remote_b}:
      String.eq(server_a, server_b) && String.eq(remote_a, remote_b)
    case _ _: False{}

def source_json(source: Source) -> J.Json:
  match source:
    case Harness{tool}:
      J.Text{"harness"}
    case Mcp{server, remote}:
      J.Object{[J.Field{"server", J.Text{server}}, J.Field{"name", J.Text{remote}}]}

def tool_json(tool: Tool) -> J.Json:
  Tool{name, description, schema, source} = tool
  J.Object{[J.Field{"name", J.Text{name}}, J.Field{"description", J.Text{description}},
    J.Field{"parameters", schema}, J.Field{"source", source_json(source)}]}

def tools_json(tools: +List<Tool>) -> +List<J.Json>:
  match tools:
    case Nil{}: Nil{}
    case Con{tool, rest}: tool_json(tool) <> tools_json(rest)

def string_schema(description: String) -> J.Json:
  J.Object{[J.Field{"type", J.Text{"string"}}, J.Field{"description", J.Text{description}}]}

def integer_schema(description: String, minimum: Nat, maximum: Nat) -> J.Json:
  J.Object{[J.Field{"type", J.Text{"integer"}}, J.Field{"description", J.Text{description}},
    J.Field{"minimum", J.nat(minimum)}, J.Field{"maximum", J.nat(maximum)}]}

def object_schema(properties: +List<J.Field>, required: +List<J.Json>) -> J.Json:
  J.Object{[J.Field{"type", J.Text{"object"}}, J.Field{"properties", J.Object{properties}},
    J.Field{"required", J.Array{required}}, J.Field{"additionalProperties", J.Boolean{False{}}}]}

# These definitions are the provider manifest and the executable tool vocabulary.
# A task freezes them at birth; catalog reloads only affect route availability.
def builtins(max_fork: Nat) -> +List<Tool>:
  [Tool{"fork_task", "Fork this task. The caller receives 0 and each child receives its one-based branch number.",
    object_schema([J.Field{"child_count", integer_schema("Number of children", 1n, max_fork)},
      J.Field{"messages", J.Object{[J.Field{"type", J.Text{"array"}},
        J.Field{"items", string_schema("Initial child message")}]} }], [J.Text{"child_count"}]), Harness{ForkTask{}}},
   Tool{"read_task", "Read a bounded page of another task's history and its current lifecycle.",
    object_schema([J.Field{"task_id", integer_schema("Task identity", 0n, U32.to_nat(4294967295))},
      J.Field{"after", integer_schema("Exclusive history offset", 0n, U32.to_nat(4294967295))},
      J.Field{"limit", integer_schema("Maximum messages", 1n, 100n)}], [J.Text{"task_id"}]), Harness{ReadTask{}}},
   Tool{"send_message_to_task", "Commit a user message to another task, or queue it while that task is busy or frozen.",
    object_schema([J.Field{"task_id", integer_schema("Task identity", 0n, U32.to_nat(4294967295))},
      J.Field{"message", string_schema("Nonempty message")}], [J.Text{"task_id"}, J.Text{"message"}]), Harness{SendMessage{}}},
   Tool{"archive_task", "Archive a task permanently and cancel its outstanding external work.",
    object_schema([J.Field{"task_id", integer_schema("Task identity", 0n, U32.to_nat(4294967295))}], [J.Text{"task_id"}]), Harness{ArchiveTask{}}},
   Tool{"bash", "Run a noninteractive Bash command with a deadline and bounded stdout and stderr.",
    object_schema([J.Field{"command", string_schema("Command to run")},
      J.Field{"timeout_ms", integer_schema("Deadline in milliseconds", 100n, U32.to_nat(120000))}], [J.Text{"command"}]), Harness{Bash{}}}]

type Profile is Data:
  Profile{key: String, provider: String, name: String}

def select_profile(same: Bool, profile: Profile, rest: Maybe<&2, Profile>) -> Maybe<&2, Profile>:
  match same:
    case True{}: Some{profile}
    case False{}: rest

def find_profile(profiles: +List<Profile>, +key: String) -> Maybe<&2, Profile>:
  match profiles:
    case Nil{}: None{}
    case Con{Profile{+name, provider, model}, rest}:
      select_profile(String.eq(name, key), Profile{name, provider, model}, find_profile(rest, key))

def profiles_json(profiles: +List<Profile>) -> +List<J.Json>:
  match profiles:
    case Nil{}: Nil{}
    case Con{Profile{key, provider, name}, rest}:
      J.Object{[J.Field{"key", J.Text{key}}, J.Field{"provider", J.Text{provider}}, J.Field{"name", J.Text{name}}]} <>
        profiles_json(rest)

# Freeze the selected model identity, not just a key whose configuration may
# later change. Credentials and endpoint availability remain external inputs.
type Model is Data:
  Model{profile: Profile, reasoning: String}

type Contract is Data:
  Contract{model: Model, tools: +List<Tool>, max_fork: Nat, max_descendants: Nat}

type Call is Data:
  Call{id: String, name: String, arguments: J.Json}

type Message is Data:
  UserMessage{text: String}
  AssistantMessage{text: String}
  FunctionCall{call: Call}
  FunctionOutput{call_id: String, value: J.Json, error: Bool}
  FailureMessage{text: String}
  ModelContext{value: J.Json}

# A model may produce ordered answers, invocations, and opaque continuation data.
# It cannot construct user messages or tool results. Continuation data is retained
# without granting it the execution authority of a FunctionCall constructor.
type ModelItem is Data:
  Say{text: String}
  Invoke{call: Call}
  Context{value: J.Json}

# Sharing a prefix is a value-level relation, independent of task ownership.
type History is Data:
  EmptyHistory{}
  HistoryNode{previous: History, message: Message}

def history_messages(history: History, tail: +List<Message>) -> +List<Message>:
  match history:
    case EmptyHistory{}: tail
    case HistoryNode{previous, message}:
      history_messages(previous, message <> tail)

def history_length(history: History) -> Nat:
  match history:
    case EmptyHistory{}: 0n
    case HistoryNode{previous, message}: 1n+history_length(previous)

def history_append(messages: +List<Message>, history: History) -> History:
  match messages:
    case Nil{}: history
    case Con{message, rest}:
      history_append(rest, HistoryNode{history, message})

def branch_history(history: History, call_id: String, branch: Nat) -> History:
  HistoryNode{history, FunctionOutput{call_id, J.nat(branch), False{}}}

type Phase is Data:
  Idle{}
  Ready{calls: List<&2, Attempt>}
  ModelPending{ticket: Nat, callable: +List<String>}
  ToolPending{ticket: Nat, call: Call, remaining: List<&2, Attempt>}

# A copied history does not confer permission to repeat an external effect.
# Fork inheritance and interrupted execution both produce recovery attempts.
type Attempt is Data:
  InitialAttempt{call: Call}
  RecoveryAttempt{call: Call}

def attempt_call(attempt: Attempt) -> Call:
  match attempt:
    case InitialAttempt{call}: call
    case RecoveryAttempt{call}: call

def may_execute(policy: Recovery, attempt: Attempt) -> Bool:
  match policy attempt:
    case RetrySafe{} _: True{}
    case OutcomeUnknown{} InitialAttempt{call}: True{}
    case OutcomeUnknown{} RecoveryAttempt{call}: False{}

def inherit_attempts(calls: +List<Attempt>) -> +List<Attempt>:
  match calls:
    case Nil{}: Nil{}
    case Con{attempt, rest}:
      RecoveryAttempt{attempt_call(attempt)} <> inherit_attempts(rest)

def initial_attempts(calls: +List<Call>) -> +List<Attempt>:
  match calls:
    case Nil{}: Nil{}
    case Con{call, rest}:
      InitialAttempt{call} <> initial_attempts(rest)

type Work is Data:
  NoWork{}
  RequestNextModel{}
  RunNextTool{}
  BecomeIdle{}

# Frozen tasks settle arriving results but dispatch nothing. Stopped tasks may
# settle already accepted calls; only fresh user input reactivates model work.
def work(status: Status, phase: Phase) -> Work:
  match status phase:
    case Archived{} _: NoWork{}
    case Frozen{} _: NoWork{}
    case Active{} Ready{Nil{}}: RequestNextModel{}
    case Stopped{} Ready{Nil{}}: BecomeIdle{}
    case Active{} Ready{Con{call, rest}}: RunNextTool{}
    case Stopped{} Ready{Con{call, rest}}: RunNextTool{}
    case _ _: NoWork{}

def has_work(work: Work) -> Bool:
  match work:
    case NoWork{}: False{}
    case _: True{}

def is_model_request(work: Work) -> Bool:
  match work:
    case RequestNextModel{}: True{}
    case _: False{}

type Task is Data:
  Task{id: Nat, lineage: +List<Nat>, contract: Contract, status: Status,
    history: History, queued: +List<String>, phase: Phase}

def task_id(task: Task) -> Nat:
  Task{id, lineage, contract, status, history, queued, phase} = task
  id

def task_status(task: Task) -> Status:
  Task{id, lineage, contract, status, history, queued, phase} = task
  status

def task_history(task: Task) -> History:
  Task{id, lineage, contract, status, history, queued, phase} = task
  history

def task_contract(task: Task) -> Contract:
  Task{id, lineage, contract, status, history, queued, phase} = task
  contract

def task_lineage(task: Task) -> +List<Nat>:
  Task{id, lineage, contract, status, history, queued, phase} = task
  lineage

def task_phase(task: Task) -> Phase:
  Task{id, lineage, contract, status, history, queued, phase} = task
  phase

def task_queue(task: Task) -> +List<String>:
  Task{id, lineage, contract, status, history, queued, phase} = task
  queued

def with_status(status: Status, task: Task) -> Task:
  Task{id, lineage, contract, old, history, queued, phase} = task
  Task{id, lineage, contract, status, history, queued, phase}

def with_phase(phase: Phase, task: Task) -> Task:
  Task{id, lineage, contract, status, history, queued, old} = task
  Task{id, lineage, contract, status, history, queued, phase}

def with_history(history: History, task: Task) -> Task:
  Task{id, lineage, contract, status, old, queued, phase} = task
  Task{id, lineage, contract, status, history, queued, phase}

def append_message(message: Message, task: Task) -> Task:
  Task{id, lineage, contract, status, history, queued, phase} = task
  Task{id, lineage, contract, status, HistoryNode{history, message}, queued, phase}

def queue_message(text: String, task: Task) -> Task:
  Task{id, lineage, contract, status, history, queued, phase} = task
  Task{id, lineage, contract, status, history, List.append(&2, String, queued, [text]), phase}

type Environment is Data:
  Environment{catalog: +List<Tool>, profiles: +List<Profile>, max_fork: Nat, max_descendants: Nat}

type ExecutionLimits is Data:
  ExecutionLimits{schedule_steps: Nat, render_steps: Nat, frame_bytes: U32}

def frame_bytes() -> U32:
  4194304

def execution_limits() -> ExecutionLimits:
  ExecutionLimits{256n, U32.to_nat(65536), frame_bytes()}

# Resource bounds are explicit model parameters. Laws hold for any such bounds;
# the native entry point supplies these defaults when it constructs the world.
type World is Data:
  World{tasks: +List<Task>, next_task: Nat, next_ticket: Nat, environment: Environment, limits: ExecutionLimits}

def initial() -> World:
  World{Nil{}, 0n, 0n, Environment{builtins(4n), Nil{}, 4n, 64n}, execution_limits()}

type Effect is Data:
  RequestModel{task_id: Nat, ticket: Nat, model: Model, history: History,
    tools: +List<Tool>, callable: +List<String>}
  ExecuteTool{task_id: Nat, ticket: Nat, tool: Tool, call: Call}
  CancelTask{task_id: Nat}
  ContinueScheduling{}

# A public query observes a world without acquiring permission to advance it.
# A tool may use the same query, then durably append its own tool result.
type Query is Data:
  Read{task_id: Nat, after: Nat, limit: Nat}
  ListTasks{}
  Describe{}

type Command is Data:
  Create{profile: String, reasoning: String, message: String}
  Send{task_id: Nat, message: String}
  ChangeStatus{task_id: Nat, control: Control}
  Fork{task_id: Nat, count: Nat, messages: +List<String>}
  Observe{query: Query}

type CommandKind is Data:
  CreateCommand{}
  SendCommand{}
  ControlCommand{control: Control}
  ForkCommand{}
  ReadCommand{}
  ListCommand{}
  DescribeCommand{}

type CommandSpec is Data:
  CommandSpec{name: String, description: String, kind: CommandKind, schema: J.Json}

def task_id_schema() -> J.Json:
  integer_schema("Task identity", 0n, U32.to_nat(4294967295))

def command_schema(properties: +List<J.Field>, required: +List<J.Json>) -> J.Json:
  object_schema(J.Field{"op", string_schema("Command name")} <> properties, J.Text{"op"} <> required)

def control_spec(+control: Control, description: String) -> CommandSpec:
  CommandSpec{control_name(control), description, ControlCommand{control},
    command_schema([J.Field{"task_id", task_id_schema()}], [J.Text{"task_id"}])}

# Clients obtain their command descriptions and validation schema from here.
def commands() -> +List<CommandSpec>:
  [CommandSpec{"create", "Start an agent with a frozen model and tool contract.", CreateCommand{},
     command_schema([J.Field{"profile", string_schema("Configured model profile")},
       J.Field{"reasoning", string_schema("Reasoning effort; defaults to medium")},
       J.Field{"message", string_schema("Initial user request")}], [J.Text{"profile"}, J.Text{"message"}])},
   CommandSpec{"send", "Commit or queue a user message; reactivate a stopped task.", SendCommand{},
     command_schema([J.Field{"task_id", task_id_schema()}, J.Field{"message", string_schema("User message")}],
       [J.Text{"task_id"}, J.Text{"message"}])},
   control_spec(Freeze{}, "Suspend dispatch without discarding accepted results."),
   control_spec(Unfreeze{}, "Resume a frozen task."),
   control_spec(Stop{}, "Settle accepted tools without requesting another model reply."),
   control_spec(Archive{}, "Permanently archive a task and cancel external work."),
   CommandSpec{"fork", "Fork an idle task, subject to every ancestor's descendant limit.", ForkCommand{},
     command_schema([J.Field{"task_id", task_id_schema()},
       J.Field{"child_count", integer_schema("Number of children", 1n, U32.to_nat(4294967295))},
       J.Field{"messages", J.Object{[J.Field{"type", J.Text{"array"}}, J.Field{"items", string_schema("Child request")}]}}],
       [J.Text{"task_id"}, J.Text{"child_count"}])},
   CommandSpec{"read", "Read a bounded history page without advancing the task.", ReadCommand{},
     command_schema([J.Field{"task_id", task_id_schema()}, J.Field{"after", integer_schema("History offset", 0n, U32.to_nat(4294967295))},
       J.Field{"limit", integer_schema("Page size; defaults to 100", 1n, 100n)}], [J.Text{"task_id"}])},
   CommandSpec{"list", "Read task summaries and the currently available model profiles and tools.", ListCommand{},
     command_schema(Nil{}, Nil{})},
   CommandSpec{"describe", "Read this executable command vocabulary and the effect-boundary limits.", DescribeCommand{},
     command_schema(Nil{}, Nil{})}]

def command_specs_json(specs: +List<CommandSpec>) -> +List<J.Json>:
  match specs:
    case Nil{}: Nil{}
    case Con{CommandSpec{name, description, kind, schema}, rest}:
      J.Object{[J.Field{"name", J.Text{name}}, J.Field{"description", J.Text{description}}, J.Field{"schema", schema}]} <>
        command_specs_json(rest)

def boundary_limits() -> J.Json:
  J.Object{[J.Field{"frame_bytes", J.nat(U32.to_nat(frame_bytes()))}, J.Field{"header_bytes", J.nat(U32.to_nat(16384))},
    J.Field{"request_timeout_ms", J.nat(U32.to_nat(5000))}, J.Field{"tool_output_bytes", J.nat(U32.to_nat(65536))},
    J.Field{"bash_timeout_ms", J.nat(U32.to_nat(30000))}, J.Field{"mcp_catalog_tools", J.nat(U32.to_nat(1024))},
    J.Field{"mcp_timeout_ms", J.nat(U32.to_nat(30000))}]}

def description() -> J.Json:
  J.Object{[J.Field{"commands", J.Array{command_specs_json(commands())}}, J.Field{"limits", boundary_limits()}]}

type Outcome is Data:
  ModelReply{items: +List<ModelItem>}
  ModelFailure{message: String}

type Input is Data:
  UserCommand{command: Command}
  ModelCompleted{task_id: Nat, ticket: Nat, outcome: Outcome}
  ToolCompleted{task_id: Nat, ticket: Nat, value: J.Json, error: Bool}
  Configure{environment: Environment}
  Recover{}
  Continue{}

type Decision is Data:
  Decision{world: World, reply: J.Json, effects: +List<Effect>}

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

def success(result: J.Json) -> J.Json:
  J.Object{[J.Field{"ok", J.Boolean{True{}}}, J.Field{"result", result}]}

def failure(code: String, message: String) -> J.Json:
  J.Object{[J.Field{"ok", J.Boolean{False{}}},
    J.Field{"error", J.Object{[J.Field{"code", J.Text{code}}, J.Field{"message", J.Text{message}}]}}]}

def nonempty(text: String) -> Bool:
  Bool.not(String.is_empty(String.trim(text)))
