import Base
import ../DOMAIN.bend as D
import ./SYNTAX.bend as Native
import ./discovery.bend as Discovery
import ../../bendlib/categories.bend as Categories
import ../../bendlib/json.bend as J
import ../transport/schema.bend as Schema

type Request is Data:
  Request{name: String, description: String, program: Native.Body}

type Observation is Data:
  Observation{request: Request, tool: D.Tool}

# Binding collection preserves field order and leaves conflicting declarations
# visible to checked construction.
type Bindings is Data:
  Bindings{properties: +List<J.Field>, required: +List<J.Json>}

def empty_bindings() -> Bindings:
  Bindings{Nil{}, Nil{}}

def argument_binding(+key: String, value: J.Json, required: Bool) -> Bindings:
  match required:
    case True{}: Bindings{[J.Field{key, value}], [J.Text{key}]}
    case False{}: Bindings{[J.Field{key, value}], Nil{}}

def join(left: Bindings, right: Bindings) -> Bindings:
  Bindings{left_properties, left_required} = left
  Bindings{right_properties, right_required} = right
  Bindings{List.append(&2, J.Field, left_properties, right_properties),
    List.append(&2, J.Json, left_required, right_required)}

def natural_binding(term: Native.Natural) -> Bindings:
  match term:
    case Native.RequiredNumber{key, description, minimum, maximum}:
      argument_binding(key, D.integer_schema(description, minimum, maximum), True{})
    case Native.OptionalNumber{key, description, minimum, maximum, fallback}:
      argument_binding(key, D.integer_schema(description, minimum, maximum), False{})
    case _: empty_bindings()

def text_binding(term: Native.Text) -> Bindings:
  match term:
    case Native.TextArgument{key, description, required, fallback}:
      argument_binding(key, D.string_schema(description), required)
    case _: empty_bindings()

def texts_binding(term: Native.Texts) -> Bindings:
  match term:
    case Native.TextsArgument{key, description, required}:
      argument_binding(key, J.Object{[J.Field{"type", J.Text{"array"}},
        J.Field{"items", D.string_schema(description)}]}, required)
    case _: empty_bindings()

def settings_binding(schema: J.Json, term: Native.Settings) -> Bindings:
  match term:
    case Native.SettingsArgument{key, required}:
      argument_binding(key, schema, required)
    case _: empty_bindings()

def query_bindings(query: Native.Query) -> Bindings:
  match query:
    case Native.Read{task, after, limit}:
      join(natural_binding(task), join(natural_binding(after), natural_binding(limit)))
    case Native.Search{query, project, work, after, limit}:
      join(text_binding(query), join(natural_binding(project), join(natural_binding(work), join(natural_binding(after), natural_binding(limit)))))
    case Native.Project{project}: natural_binding(project)
    case _: empty_bindings()

def body_bindings(program: Native.Body) -> Bindings:
  match program:
    case Native.Discover{}: empty_bindings()
    case Native.Observe{query}: query_bindings(query)
    case Native.Create{profile, reasoning, message, settings}:
      join(text_binding(profile), join(text_binding(reasoning), join(text_binding(message), settings_binding(D.task_settings_schema(), settings))))
    case Native.Feature{operation, schema}: empty_bindings()
    case Native.Send{task, message}: join(natural_binding(task), text_binding(message))
    case Native.Steer{task, message}: join(natural_binding(task), text_binding(message))
    case Native.Archive{task}: natural_binding(task)
    case Native.Cancel{task, operation}: join(natural_binding(operation), natural_binding(task))
    case Native.Fork{count, messages, settings}:
      join(natural_binding(count), join(texts_binding(messages), settings_binding(D.fork_settings_schema(), settings)))
    case Native.Process{}: empty_bindings()
    case Native.ProcessRead{}: empty_bindings()
    case Native.ProcessWrite{}: empty_bindings()

def bound_schema(bindings: Bindings) -> J.Json:
  Bindings{properties, required} = bindings
  Schema.object(properties, required)

def schema(program: Native.Body) -> J.Json:
  match program:
    case Native.Discover{}: Discovery.schema()
    case Native.Process{}: D.process_schema()
    case Native.ProcessRead{}: D.process_read_schema()
    case Native.ProcessWrite{}: D.process_write_schema()
    case Native.Feature{operation, schema}: Schema.command_arguments(schema)
    case other: bound_schema(body_bindings(other))

def source(request: Request) -> D.Tool:
  Request{name, description, +program} = request
  D.Tool{name, description, schema(program), D.Harness{program}}

def declaration(observation: Observation) -> Type:
  Observation{Request{name, description, program}, D.Tool{actual_name, actual_description, schema, source}} = observation
  Categories.intersection(Observation,
    (value => {actual_name == name : String}),
    (value => {actual_description == description : String}), observation)

def binding(observation: Observation) -> Type:
  Observation{Request{name, description, program}, D.Tool{actual_name, actual_description, actual_schema, source}} = observation
  {actual_schema == schema(program) : J.Json}

def capability(observation: Observation) -> Type:
  Observation{Request{name, description, program}, D.Tool{actual_name, actual_description, schema, actual_source}} = observation
  {actual_source == D.Harness{program} : D.Source}

def execution(observation: Observation) -> Type:
  Observation{Request{name, description, program}, D.Tool{actual_name, actual_description, schema, actual_source}} = observation
  {D.execution(actual_source) == D.native_execution(program) : D.Execution}

def declared_binding(observation: Observation) -> Type:
  Categories.intersection(Observation, declaration, binding, observation)

def executable_capability(observation: Observation) -> Type:
  Categories.intersection(Observation, capability, execution, observation)

def correspondence(observation: Observation) -> Type:
  Categories.intersection(Observation, declared_binding, executable_capability, observation)

def observation_tool(observation: Observation) -> D.Tool:
  Observation{request, tool} = observation
  tool

# NOTE: Avoid full trimming and reversal when initial proof normalization checks descriptions.
def description_present(text: String) -> Bool:
  match text:
    case SNil{}: False{}
    case SCon{head, rest}: Bool.not(Char.is_space(head)) || description_present(rest)

def valid_source(source: D.Source) -> Bool:
  match source:
    case D.Harness{Native.Feature{+operation, +schema}}:
      D.nonempty(operation) && Schema.command_supported(schema) &&
        Schema.valid(J.get(J.get(schema, "properties"), "op"), J.Text{operation})
    case D.Harness{program}: Native.defaults_valid(program)
    case _: True{}

def valid_tool(+tool: D.Tool) -> Bool:
  D.Tool{name, description, schema, source} = tool
  D.nonempty(name) && description_present(description) && Schema.supported(schema) && valid_source(source)

def admissible(observation: Observation) -> Type:
  Categories.holds(Observation, (value => valid_tool(observation_tool(value))))(observation)

def authored(observation: Observation) -> Type:
  Categories.intersection(Observation, correspondence, admissible, observation)

def authored_declaration() -> Categories.Inclusion<Observation, authored, declaration>:
  Categories.inclusion_compose(Observation, authored, correspondence, declaration,
    Categories.intersection_first(Observation, correspondence, admissible),
    Categories.inclusion_compose(Observation, correspondence, declared_binding, declaration,
      Categories.intersection_first(Observation, declared_binding, executable_capability),
      Categories.intersection_first(Observation, declaration, binding)))

def authored_binding() -> Categories.Inclusion<Observation, authored, binding>:
  Categories.inclusion_compose(Observation, authored, correspondence, binding,
    Categories.intersection_first(Observation, correspondence, admissible),
    Categories.inclusion_compose(Observation, correspondence, declared_binding, binding,
      Categories.intersection_first(Observation, declared_binding, executable_capability),
      Categories.intersection_second(Observation, declaration, binding)))

def authored_capability() -> Categories.Inclusion<Observation, authored, capability>:
  Categories.inclusion_compose(Observation, authored, correspondence, capability,
    Categories.intersection_first(Observation, correspondence, admissible),
    Categories.inclusion_compose(Observation, correspondence, executable_capability, capability,
      Categories.intersection_second(Observation, declared_binding, executable_capability),
      Categories.intersection_first(Observation, capability, execution)))

def authored_execution() -> Categories.Inclusion<Observation, authored, execution>:
  Categories.inclusion_compose(Observation, authored, correspondence, execution,
    Categories.intersection_first(Observation, correspondence, admissible),
    Categories.inclusion_compose(Observation, correspondence, executable_capability, execution,
      Categories.intersection_second(Observation, declared_binding, executable_capability),
      Categories.intersection_second(Observation, capability, execution)))

def authored_admissible() -> Categories.Inclusion<Observation, authored, admissible>:
  Categories.intersection_second(Observation, correspondence, admissible)

def correspondence_evidence(+request: Request) -> correspondence(Observation{request, source(request)}):
  Request{name, description, program} = request
  Categories.Intersection{
    Categories.Intersection{Categories.Intersection{{==}, {==}}, {==}},
    Categories.Intersection{{==}, {==}}}

def construct_checked(+observation: Observation, correspondence_evidence: correspondence(observation), accepted: Bool, observed: {valid_tool(observation_tool(observation)) == accepted : Bool}) -> Maybe<&1, Categories.Membership<Observation, authored>>:
  match accepted:
    case True{}: Some{Categories.Membership{observation, Categories.Intersection{correspondence_evidence, observed}}}
    case False{}: None{}

def construct(+request: Request) -> Maybe<&1, Categories.Membership<Observation, authored>>:
  +tool = source(request)
  +observation: Observation = Observation{request, tool}
  construct_checked(observation, correspondence_evidence(request), valid_tool(tool), {==})

def constructed_tool(member: Categories.Membership<Observation, authored>) -> D.Tool:
  Categories.Membership{Observation{request, tool}, evidence} = member
  tool

def journal_execution(observation: Observation) -> Type:
  Observation{Request{name, description, program}, tool} = observation
  {D.native_execution(program) == D.InternalOperation{} : D.Execution}

def external_execution(observation: Observation) -> Type:
  Observation{Request{name, description, program}, tool} = observation
  {D.native_execution(program) == D.ExternalMutation{} : D.Execution}

def journal(observation: Observation) -> Type:
  Categories.intersection(Observation, authored, journal_execution, observation)

def external(observation: Observation) -> Type:
  Categories.intersection(Observation, authored, external_execution, observation)

def journal_authored() -> Categories.Inclusion<Observation, journal, authored>:
  Categories.intersection_first(Observation, authored, journal_execution)

def external_authored() -> Categories.Inclusion<Observation, external, authored>:
  Categories.intersection_first(Observation, authored, external_execution)

def catalog_constructed(member: Maybe<&1, Categories.Membership<Observation, authored>>) -> +List<D.Tool>:
  match member:
    case Some{member}: [constructed_tool(member)]
    case None{}: Nil{}

def catalog_entry(request: Request) -> +List<D.Tool>:
  catalog_constructed(construct(request))

def catalog(max_fork: Nat) -> +List<D.Tool>:
  List.append(&2, D.Tool, catalog_entry(Request{"discover_tools", "Find external MCP and plugin tools by keywords, or load their complete definitions with exact names. External function declarations are a lightweight directory, not parameter definitions. Call this before using an unfamiliar external tool; copy its parameters from the result. names bypasses search and the result limit. Without query or names, returns a bounded directory page. Use offset for later pages. Definitions remain in ordinary tool results; rediscover after compaction if needed.", Native.Discover{}}),
  List.append(&2, D.Tool, catalog_entry(Request{"create_task", "Create an independent task with a configured model. Settings obey the caller's workspace and permission bounds.",
    Native.Create{Native.TextArgument{"profile", "Configured model profile", True{}, ""},
      Native.TextArgument{"reasoning", "Reasoning effort; defaults to the selected profile", False{}, "default"},
      Native.TextArgument{"message", "Initial nonempty user request", True{}, ""}, Native.SettingsArgument{"settings", False{}}}}),
  List.append(&2, D.Tool, catalog_entry(Request{"fork_task", "Fork this task. The caller receives 0 and each child receives its one-based branch number.",
    Native.Fork{Native.RequiredNumber{"child_count", "Number of children", 1, U32.from_nat(max_fork)}, Native.TextsArgument{"messages", "Initial child message", False{}}, Native.SettingsArgument{"settings", False{}}}}),
    List.append(&2, D.Tool, catalog_entry(Request{"search_history", "Search user and assistant messages across tasks by a literal keyword or phrase (ASCII case-insensitive). Restrict to a project or Work, or both. Returns bounded snippets and 0-based message_index; use read_task with after=message_index to read the original message.",
      Native.Observe{Native.Search{Native.TextArgument{"query", "Literal keyword or phrase, 1..240 characters", True{}, ""},
        Native.OptionalNumber{"project_id", "Optional project identity", 0, 4294967295, Native.ConstantDefault{0n}},
        Native.OptionalNumber{"work_id", "Optional Work identity", 0, 4294967295, Native.ConstantDefault{0n}},
        Native.OptionalNumber{"after", "Result offset", 0, 4294967295, Native.ConstantDefault{0n}},
        Native.OptionalNumber{"limit", "Maximum results", 1, 50, Native.ConstantDefault{20n}}}}}),
    List.append(&2, D.Tool, catalog_entry(Request{"read_task", "Read a bounded page of another task's history and its current lifecycle.",
    Native.Observe{Native.Read{Native.RequiredNumber{"task_id", "Task identity", 0, 4294967295}, Native.OptionalNumber{"after", "Exclusive history offset", 0, 4294967295, Native.ConstantDefault{0n}}, Native.OptionalNumber{"limit", "Maximum messages", 1, 100, Native.ConstantDefault{100n}}}}}),
    List.append(&2, D.Tool, catalog_entry(Request{"send_message_to_task", "Commit a user message to another task, or queue it while that task is busy or frozen.",
    Native.Send{Native.RequiredNumber{"task_id", "Task identity", 0, 4294967295}, Native.TextArgument{"message", "Nonempty message", True{}, ""}}}),
    List.append(&2, D.Tool, catalog_entry(Request{"archive_task", "Archive a task permanently and cancel its outstanding external work.",
    Native.Archive{Native.RequiredNumber{"task_id", "Task identity", 0, 4294967295}}}),
    List.append(&2, D.Tool, catalog_entry(Request{"bash", "Run Bash in this task's primary workspace root, or / for an empty workspace. Independent calls run concurrently. A running or awaiting_approval status is not completion; results arrive automatically. Use read_process on demand for incremental output and write_process for input; do not poll automatically. Pipe mode is the default; select pty for interactive terminal programs. Default access obeys the task sandbox. To request one command outside that sandbox, set sandbox_permissions to require_escalated and explain the concrete need in justification BEFORE executing it. A failed command may have partial effects: there is no automatic unrestricted retry. Descendants are terminated on exit. Nonzero exits are errors. Output retains bounded latest content and marks omitted characters. Runtime is unlimited unless timeout_ms is supplied (at most 30 minutes).",
    Native.Process{}}),
    List.append(&2, D.Tool, catalog_entry(Request{"read_process", "Read available incremental output from this task's Bash operation while running or after completion. Use next_cursor from the previous read. Output is bounded and explicitly marks discarded content. Call on demand; do not poll automatically.",
      Native.ProcessRead{}}),
    List.append(&2, D.Tool, catalog_entry(Request{"write_process", "Write input to this task's running Bash operation. Pipe mode supports eof to close stdin. PTY mode accepts terminal keys as control characters and escape sequences, and paired cols/rows to resize; eof is unavailable.",
      Native.ProcessWrite{}}),
    catalog_entry(Request{"cancel_operation", "Cancel one in-flight operation, not the task or its other work. Use an operation_id from a running status or read_task. Cancellation cannot undo side effects already performed.",
    Native.Cancel{Native.OptionalNumber{"task_id", "Task identity; defaults to this task", 0, 4294967295, Native.CallerDefault{}}, Native.RequiredNumber{"operation_id", "Task identity", 0, 4294967295}}})))))))))))
