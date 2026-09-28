import Base
import ./MODEL.bend as M
import ./REASONING.bend as Reasoning
import ./COMMANDS.bend as Commands
import ./bendlib/json.bend as J
import ./bendlib/tasks.bend as T
import ./bendlib/operations.bend as Ops
import ./BOARD.bend as B
import ./bendlib/board-codec.bend as BoardCodec
import ./bendlib/board-navigation.bend as BoardNav
import ./bendlib/command-codec.bend as CommandCodec
import ./bendlib/board-view.bend as BoardView

# The presentation model is a platform-independent interaction surface. Bend
# selects content, exposes actions and interprets events against the live world.
# An adapter renders these values and fills the declared event bindings only.
type Choice is Data:
  Choice{value: String, label: String}

type Field is Data:
  Field{name: String, label: String, kind: String, value: J.Json,
    schema: J.Json, choices: +List<Choice>, required: Bool}

type Node is Data:
  Group{key: String, role: String, title: String, children: +List<Node>}
  Text{key: String, role: String, title: String, text: String}
  Value{key: String, title: String, value: J.Json}
  Action{key: String, label: String, event: M.ViewEvent, enabled: Bool, selected: Bool}
  Form{key: String, title: String, label: String, command: M.Command, fields: +List<Field>, enabled: Bool}
  Composition{key: String, role: String, properties: J.Json, children: +List<Node>}

type Presentation is Data:
  Presentation{state: M.ViewState, root: Node}

def initial() -> M.ViewState:
  M.ViewState{None{}, None{}, 0n, "", B.cursor()}

def page_size() -> Nat:
  40n

def selected(operation: Commands.Operation) -> Bool:
  Commands.admitted(operation)

# This is the command resolver's answer, not a frontend lifecycle table.
def enabled(command: M.Command, world: M.World) -> Bool:
  selected(Commands.resolve(command, world))

def command(event: M.ViewEvent) -> M.Command:
  match event:
    case M.Submit{command}: command
    case _: M.Observe{M.Describe{}}

def state_json(state: M.ViewState) -> J.Json:
  M.ViewState{selected, after, tasks_after, profile, board} = state
  J.Object{[J.Field{"selected", J.optional_nat(selected)}, J.Field{"after", J.optional_nat(after)},
    J.Field{"tasks_after", J.nat(tasks_after)}, J.Field{"profile", J.Text{profile}}, J.Field{"board", BoardNav.cursor_json(board)}]}

def command_json(command: M.Command) -> J.Json:
  CommandCodec.command_json(command)

def event_json(event: M.ViewEvent) -> J.Json:
  CommandCodec.event_json(event)

def choices_json(choices: +List<Choice>) -> +List<J.Json>:
  match choices:
    case Nil{}: Nil{}
    case Con{Choice{value, label}, rest}:
      J.Object{[J.Field{"value", J.Text{value}}, J.Field{"label", J.Text{label}}]} <> choices_json(rest)

def fields_json(fields: +List<Field>) -> +List<J.Json>:
  match fields:
    case Nil{}: Nil{}
    case Con{Field{+name, label, kind, value, schema, choices, required}, rest}:
      J.Object{[J.Field{"name", J.Text{name}}, J.Field{"label", J.Text{label}}, J.Field{"kind", J.Text{kind}},
        J.Field{"value", value}, J.Field{"schema", schema}, J.Field{"choices", J.Array{choices_json(choices)}},
        J.Field{"required", J.Boolean{required}}, J.Field{"binding", J.Array{[J.Text{"command"}, J.Text{name}]}}]} <> fields_json(rest)

def form_changes(command: M.Command) -> J.Json:
  match command:
    case M.Create{profile, reasoning, message, options}:
      J.Object{[J.Field{"profile", J.Object{[J.Field{"event", event_json(M.SelectProfile{profile})},
        J.Field{"binding", J.Array{[J.Text{"profile"}]}}, J.Field{"reset_fields", J.Array{[J.Text{"reasoning"}]}}]}}]}
    case _: J.Object{Nil{}}

def nodes_json(nodes: +List<Node>) -> +List<J.Json>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Composition{key, role, properties, children}, rest}:
      J.Object{[J.Field{"kind", J.Text{"composition"}}, J.Field{"key", J.Text{key}}, J.Field{"role", J.Text{role}},
        J.Field{"properties", properties}, J.Field{"children", J.Array{nodes_json(children)}}]} <> nodes_json(rest)
    case Con{Group{key, role, title, children}, rest}:
      J.Object{[J.Field{"kind", J.Text{"group"}}, J.Field{"key", J.Text{key}}, J.Field{"role", J.Text{role}},
        J.Field{"title", J.Text{title}}, J.Field{"children", J.Array{nodes_json(children)}}]} <> nodes_json(rest)
    case Con{Text{key, role, title, text}, rest}:
      J.Object{[J.Field{"kind", J.Text{"text"}}, J.Field{"key", J.Text{key}}, J.Field{"role", J.Text{role}},
        J.Field{"title", J.Text{title}}, J.Field{"text", J.Text{text}}]} <> nodes_json(rest)
    case Con{Value{key, title, value}, rest}:
      J.Object{[J.Field{"kind", J.Text{"value"}}, J.Field{"key", J.Text{key}}, J.Field{"title", J.Text{title}}, J.Field{"value", value}]} <> nodes_json(rest)
    case Con{Action{key, label, event, enabled, selected}, rest}:
      J.Object{[J.Field{"kind", J.Text{"action"}}, J.Field{"key", J.Text{key}}, J.Field{"label", J.Text{label}},
        J.Field{"event", event_json(event)}, J.Field{"enabled", J.Boolean{enabled}}, J.Field{"selected", J.Boolean{selected}}]} <> nodes_json(rest)
    case Con{Form{key, title, label, +command, fields, enabled}, rest}:
      J.Object{[J.Field{"kind", J.Text{"form"}}, J.Field{"key", J.Text{key}}, J.Field{"title", J.Text{title}}, J.Field{"label", J.Text{label}},
        J.Field{"event", event_json(M.Submit{command})}, J.Field{"changes", form_changes(command)},
        J.Field{"fields", J.Array{fields_json(fields)}}, J.Field{"enabled", J.Boolean{enabled}}]} <> nodes_json(rest)

def first_node(nodes: +List<J.Json>) -> J.Json:
  match nodes:
    case Nil{}: J.Null{}
    case Con{node, rest}: node

def node_json(node: Node) -> J.Json:
  first_node(nodes_json([node]))

def json(presentation: Presentation) -> J.Json:
  Presentation{state, root} = presentation
  J.Object{[J.Field{"state", state_json(state)}, J.Field{"root", node_json(root)}]}

def action(key: String, label: String, +command: M.Command, world: M.World) -> Node:
  Action{key, label, M.Submit{command}, enabled(command, world), False{}}

def form(key: String, title: String, label: String, +command: M.Command, fields: +List<Field>, world: M.World) -> Node:
  Form{key, title, label, command, fields, enabled(command, world)}

def schema_selected(same: Bool, schema: J.Json, rest: J.Json) -> J.Json:
  match same:
    case True{}: schema
    case False{}: rest

def schema(specs: +List<M.CommandSpec>, +name: String) -> J.Json:
  match specs:
    case Nil{}: J.Null{}
    case Con{M.CommandSpec{key, description, kind, value}, rest}:
      schema_selected(String.eq(key, name), value, schema(rest, name))

def field_schema(command: String, field: String) -> J.Json:
  J.get(J.get(schema(M.commands(), command), "properties"), field)

def input(command: String, +name: String, label: String, kind: String, value: J.Json, required: Bool) -> Field:
  Field{name, label, kind, value, field_schema(command, name), Nil{}, required}

def profile_label(automatic: Bool, name: String) -> String:
  match automatic:
    case True{}: name ++ " Auto"
    case False{}: name

def profile_choices(profiles: +List<M.Profile>) -> +List<Choice>:
  match profiles:
    case Nil{}: Nil{}
    case Con{M.Profile{+key, provider, model, policy}, rest}:
      Choice{key, profile_label(Reasoning.automatic(policy), model) ++ " · " ++ provider ++ " / " ++ key} <> profile_choices(rest)

def first_profile(profiles: +List<M.Profile>) -> String:
  match profiles:
    case Nil{}: ""
    case Con{M.Profile{key, provider, model, policy}, rest}: key

def preferred_profile(found: Maybe<&2, M.Profile>, fallback: String) -> String:
  match found:
    case None{}: fallback
    case Some{M.Profile{key, provider, name, policy}}: key

def selected_policy(found: Maybe<&2, M.Profile>) -> Reasoning.Policy:
  match found:
    case None{}: Reasoning.Fixed{}
    case Some{profile}: M.profile_reasoning(profile)

def reasoning_field(policy: Reasoning.Policy) -> Field:
  match policy:
    case Reasoning.Fixed{}: input("create", "reasoning", "Reasoning", "text", J.Text{"medium"}, True{})
    case Reasoning.Adaptive{evaluator, efforts, baseline, transport, maximum}:
      Field{"reasoning", "Reasoning", "choice", J.Text{"auto"}, field_schema("create", "reasoning"), [Choice{"auto", "Auto"}], True{}}

def create_config(preferred: String, environment: M.Environment, world: M.World) -> Node:
  M.Environment{catalog, +profiles, max_fork, max_descendants, project, plugins} = environment
  +profile = preferred_profile(M.find_profile(profiles, preferred), first_profile(profiles))
  +policy = selected_policy(M.find_profile(profiles, profile))
  form("create", "New task", "Create task", M.Create{profile, Reasoning.default_selection(policy), "message", J.Object{Nil{}}},
    [Field{"profile", "Model profile", "choice", J.Text{profile}, field_schema("create", "profile"), profile_choices(profiles), True{}},
      reasoning_field(policy),
      input("create", "message", "What should the agent do?", "multiline", J.Text{""}, True{}),
      input("create", "settings", "Workspace, sandbox, approval and project overrides (JSON; {} uses defaults)", "json", J.Object{Nil{}}, True{})], world)

def create(+world: M.World) -> Node:
  create_config("", Commands.settings(world), world)

def is_selected(selected: Maybe<&2, Nat>, id: Nat) -> Bool:
  match selected:
    case None{}: False{}
    case Some{other}: Nat.is_eq(other, id)

def task_label(+task: M.Task) -> String:
  "#" ++ Nat.show(M.task_id(task)) ++ " · " ++ M.status_name(M.task_status(task)) ++ " · " ++ T.phase_name(M.task_phase(task))

def task_links(tasks: +List<M.Task>, +selected: Maybe<&2, Nat>) -> +List<Node>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}:
      +id = M.task_id(task)
      Action{"select/" ++ Nat.show(id), task_label(task), M.SelectTask{Some{id}}, True{}, is_selected(selected, id)} <> task_links(rest, selected)

def bounded(inside: Bool, value: Nat, maximum: Nat) -> Nat:
  match inside:
    case True{}: value
    case False{}: maximum

def clip(+value: Nat, +maximum: Nat) -> Nat:
  bounded(Nat.is_le(value, maximum), value, maximum)

def navigation(+state: M.ViewState, +tasks: +List<M.Task>) -> Node:
  M.ViewState{selected, history_after, +after, profile, board} = state
  +total = List.length(&2, M.Task, tasks)
  links = task_links(List.take(&2, M.Task, List.drop(&2, M.Task, tasks, after), page_size()), selected)
  Group{"navigation", "navigation", "Tasks", List.append(&2, Node,
    [Composition{"workspaces", "board-navigation", J.Object{[J.Field{"actions", J.Array{BoardView.navigation_actions(B.ThreadsPane{})}}]}, Nil{}},
     Action{"new", "New task", M.SelectTask{None{}}, True{}, False{}}],
    List.append(&2, Node, links,
      [Action{"tasks/previous", "Previous tasks", M.TaskPage{Nat.sub(after, page_size())}, Nat.is_lt(0n, after), False{}},
       Action{"tasks/next", "Next tasks", M.TaskPage{Nat.add(after, page_size())}, Nat.is_lt(Nat.add(after, page_size()), total), False{}}]))}

def controls(+id: Nat, +world: M.World) -> Node:
  Group{"controls", "actions", "Task controls",
    [action("freeze", "Freeze", M.ChangeStatus{id, M.Freeze{}}, world),
     action("unfreeze", "Unfreeze", M.ChangeStatus{id, M.Unfreeze{}}, world),
     action("stop", "Stop after accepted work", M.ChangeStatus{id, M.Stop{}}, world),
     action("interrupt", "Interrupt now", M.ChangeStatus{id, M.Interrupt{}}, world),
     action("archive", "Archive permanently", M.ChangeStatus{id, M.Archive{}}, world)]}

def approval_directory(context: M.TaskContext) -> String:
  M.TaskContext{M.Workspace{roots, primary}, sandbox, approval, project} = context
  match primary:
    case None{}: "/"
    case Some{directory}: directory

def approval_controls(reviewer: M.ApprovalReviewer, +id: Nat, +ticket: Nat, +world: M.World) -> +List<Node>:
  match reviewer:
    case M.HumanReviewer{}:
      [Group{"review/actions", "actions", "Decision",
        [action("approval/allow/" ++ Nat.show(ticket), "Approve once",
           M.ReviewApproval{id, ticket, M.ApprovalAllowed{"Approved once by the user in the UI."}}, world),
         action("approval/deny/" ++ Nat.show(ticket), "Deny",
           M.ReviewApproval{id, ticket, M.ApprovalDenied{"Denied by the user in the UI."}}, world)]}]
    case M.ModelReviewer{M.Profile{profile, provider, model, policy}}:
      [Text{"review/model", "note", "Approval for Me",
        "An independent, tool-free call to " ++ profile ++ " is reviewing this command. Bash has not started."}]

def approval_nodes(stage: M.OperationStage, +operation: M.Operation(), +task: M.Task, +world: M.World) -> +List<Node>:
  match stage:
    case M.ApprovalPending{reviewer}:
      +arguments = T.call_arguments(Ops.call(operation))
      [Group{"review", "approval", "Permission request",
        List.append(&2, Node,
          [Text{"review/command", "command", "Exact Bash command", J.text(J.get(arguments, "command"))},
           Text{"review/reason", "note", "Agent's reason", J.text(J.get(arguments, "justification"))},
           Text{"review/cwd", "note", "Working directory", approval_directory(M.task_context(task))},
           Text{"review/scope", "note", "Requested access",
             "Run this invocation once outside filesystem and network isolation. The task's saved settings stay unchanged. A frozen task waits until resumed."},
           Value{"review/settings", "Frozen workspace and permissions", M.task_context_json(M.task_context(task))}],
          approval_controls(reviewer, M.task_id(task), Ops.ticket(operation), world))}]
    case M.ApprovalGranted{reviewer}:
      [Text{"review/granted", "note", "Approved; waiting to run", Ops.stage_notice(M.ApprovalGranted{reviewer})}]
    case _: Nil{}

def operation_nodes(operations: +List<M.Operation()>, +task: M.Task, +world: M.World) -> +List<Node>:
  match operations:
    case Nil{}: Nil{}
    case Con{+operation, rest}:
      +ticket = Ops.ticket(operation)
      Group{"operation/" ++ Nat.show(ticket), "operation", "Operation " ++ Nat.show(ticket),
        List.append(&2, Node, approval_nodes(Ops.stage(operation), operation, task, world),
          [Value{"details", "Live operation", Ops.summary(operation)},
           action("cancel/" ++ Nat.show(ticket), "Cancel this operation", M.Cancel{M.task_id(task), ticket}, world)])} <>
        operation_nodes(rest, task, world)

def lineage_nodes(lineage: +List<Nat>) -> +List<Node>:
  match lineage:
    case Nil{}: Nil{}
    case Con{+id, rest}: Action{"ancestor/" ++ Nat.show(id), "Open ancestor #" ++ Nat.show(id), M.SelectTask{Some{id}}, True{}, False{}} <> lineage_nodes(rest)

def error_title(error: Bool, title: String) -> String:
  match error:
    case True{}: title ++ " · error"
    case False{}: title

def context_part(kind: String, value: J.Json) -> String:
  match kind:
    case "output_text": J.text(J.get(value, "text"))
    case "summary_text": J.text(J.get(value, "text"))
    case "refusal": J.text(J.get(value, "refusal"))
    case _: ""

def context_parts(parts: +List<J.Json>) -> String:
  match parts:
    case Nil{}: ""
    case Con{+part, rest}: context_part(J.text(J.get(part, "type")), part) ++ context_parts(rest)

def assistant_context(assistant: Bool, value: J.Json, key: String) -> +List<Node>:
  match assistant:
    case True{}: [Text{key, "assistant", "Agent", context_parts(J.items(J.get(value, "content")))}]
    case False{}: Nil{}

def provider_context(kind: String, +value: J.Json, key: String) -> +List<Node>:
  match kind:
    case "message": assistant_context(String.eq(J.text(J.get(value, "role")), "assistant"), value, key)
    case "reasoning": [Text{key, "note", "Reasoning summary", context_parts(J.items(J.get(value, "summary")))}]
    case "compaction": [Text{key, "note", "Provider context retained", "Available to subsequent model requests."}]
    case _: Nil{}

def message_nodes(message: M.Message, +key: String) -> +List<Node>:
  match message:
    case M.ReasoningRecord{owner, +effort, remaining, True{}}:
      [Value{key, "Reasoning · " ++ effort, J.Object{[J.Field{"requested_effort", J.Text{effort}},
        J.Field{"generations_remaining", J.nat(remaining)}]}}]
    case M.ReasoningRecord{owner, effort, remaining, False{}}: Nil{}
    case M.ConfigurationUpdate{effort}: Nil{}
    case M.ForkResult{owner, call_id, branch}: [Value{key, "Fork return · " ++ call_id, J.nat(branch)}]
    case M.HookRecord{owner, +call_id, plugin, outcome}:
      [Value{key, "Hook decision · " ++ call_id, T.message_json(M.HookRecord{owner, call_id, plugin, outcome})}]
    case M.ToolReceipt{owner, +operation, call, value, error}:
      [Value{key, "Execution receipt · " ++ Nat.show(operation), T.message_json(M.ToolReceipt{owner, operation, call, value, error})}]
    case M.AfterRecord{owner, +operation, plugin, outcome}:
      [Value{key, "Result hook · " ++ Nat.show(operation), T.message_json(M.AfterRecord{owner, operation, plugin, outcome})}]
    case M.ApprovalRecord{owner, +operation, call, reviewer, outcome}:
      [Value{key, "Approval decision · " ++ Nat.show(operation), T.message_json(M.ApprovalRecord{owner, operation, call, reviewer, outcome})}]
    case M.UserMessage{text}: [Text{key, "user", "You", text}]
    case M.AssistantMessage{text}: [Text{key, "assistant", "Agent", text}]
    case M.FunctionCall{call}: [Value{key, "Tool call", T.call_json(call)}]
    case M.FunctionOutput{id, value, error}: [Value{key, error_title(error, "Tool response · " ++ id), value}]
    case M.OperationResult{ticket, id, tool, value, error}:
      [Value{key, error_title(error, "Operation " ++ Nat.show(ticket) ++ " · " ++ tool), value}]
    case M.FailureMessage{text}: [Text{key, "error", "Execution error", text}]
    case M.ContextCheckpoint{text}: [Text{key, "note", "Context checkpoint", text}]
    case M.ModelContext{+value}: provider_context(J.text(J.get(value, "type")), value, key)

def messages(items: +List<M.Message>, +offset: Nat) -> +List<Node>:
  match items:
    case Nil{}: Nil{}
    case Con{message, rest}:
      List.append(&2, Node, message_nodes(message, "message/" ++ Nat.show(offset)), messages(rest, 1n+offset))

def history_offset(after: Maybe<&2, Nat>, +total: Nat) -> Nat:
  match after:
    case None{}: Nat.sub(total, page_size())
    case Some{offset}: clip(offset, total)

def transcript(+task: M.Task, after: Maybe<&2, Nat>) -> Node:
  +history = M.task_history(task)
  +total = M.history_length(history)
  +offset = history_offset(after, total)
  Group{"transcript", "transcript", "Conversation",
    List.append(&2, Node,
      [Group{"history/pages", "actions", "History",
        [Action{"history/previous", "Earlier messages", M.HistoryPage{Some{Nat.sub(offset, page_size())}}, Nat.is_lt(0n, offset), False{}},
         Action{"history/next", "Later messages", M.HistoryPage{Some{Nat.add(offset, page_size())}}, Nat.is_lt(Nat.add(offset, page_size()), total), False{}},
         Action{"history/latest", "Follow latest", M.HistoryPage{None{}}, True{}, False{}}]}],
      messages(List.take(&2, M.Message, List.drop(&2, M.Message, M.history_messages(history, Nil{}), offset), page_size()), offset))}

def send_forms(+id: Nat, +world: M.World) -> Node:
  Group{"compose", "compose", "Input",
    [form("send/" ++ Nat.show(id), "Queue a message", "Send", M.Send{id, "message"},
       [input("send", "message", "Message", "multiline", J.Text{""}, True{})], world),
     form("steer/" ++ Nat.show(id), "Change direction now", "Steer", M.Steer{id, "message"},
       [input("steer", "message", "Instruction", "multiline", J.Text{""}, True{})], world)]}

def advanced(+id: Nat, +world: M.World) -> Node:
  Group{"advanced", "details", "Branch and context",
    [form("fork/" ++ Nat.show(id), "Fork this task", "Create branches", M.Fork{id, 1n, Nil{}, J.Object{Nil{}}},
       [input("fork", "child_count", "Children", "integer", J.nat(1n), True{}),
        input("fork", "settings", "Child overrides (JSON; {} inherits the parent)", "json", J.Object{Nil{}}, True{})], world),
     action("compact/" ++ Nat.show(id), "Ask the model for a checkpoint", M.Compact{id, None{}}, world),
     form("checkpoint/" ++ Nat.show(id), "Supply a checkpoint", "Save checkpoint", M.Compact{id, Some{"summary"}},
       [input("compact", "summary", "Summary", "multiline", J.Text{""}, True{})], world)]}

def tools(entries: +List<M.Tool>, +catalog: +List<M.Tool>) -> +List<Node>:
  match entries:
    case Nil{}: Nil{}
    case Con{+tool, rest}:
      M.Tool{+name, description, schema, source} = tool
      Group{"tool/" ++ name, "details", name,
        [Text{"description", "note", "Purpose", description},
         Value{"availability", "Available now", J.Boolean{T.available(catalog, tool)}},
         Value{"schema", "Arguments", schema}]} <> tools(rest, catalog)

def task_surface(+task: M.Task, after: Maybe<&2, Nat>, environment: M.Environment, +world: M.World) -> Node:
  M.Environment{catalog, profiles, max_fork, max_descendants, project, plugins} = environment
  +id = M.task_id(task)
  Group{"task/" ++ Nat.show(id), "panel", task_label(task),
    [Group{"lineage", "actions", "Ancestry", lineage_nodes(M.task_lineage(task))},
     Value{"state", "Current state", T.summary(task)}, controls(id, world),
     transcript(task, after),
     Group{"operations", "operations", "Live operations", operation_nodes(M.task_operations(task), task, world)},
     send_forms(id, world), advanced(id, world),
     Group{"tools", "details", "Frozen tool contract", tools(T.task_tools(M.task_contract(task)), catalog)}]}

def task_panel(found: Maybe<&2, M.Task>, after: Maybe<&2, Nat>, +world: M.World) -> Node:
  match found:
    case None{}: Group{"missing", "panel", "Task unavailable", [Text{"missing/reason", "error", "No such task", "Select a task or create a new one."}, create(world)]}
    case Some{task}: task_surface(task, after, Commands.settings(world), world)

def panel(state: M.ViewState, +world: M.World) -> Node:
  M.ViewState{selected, after, tasks_after, profile, board} = state
  match selected:
    case None{}: create_config(profile, Commands.settings(world), world)
    case Some{id}: task_panel(T.find(Commands.entries(world), id), after, world)

def notices(ok: Bool, reply: J.Json) -> +List<Node>:
  match ok:
    case True{}: Nil{}
    case False{}: [Text{"notice", "error", "Request was not accepted", J.text(J.get(J.get(reply, "error"), "message"))}]

def thread_screen(+state: M.ViewState, +world: M.World, +reply: J.Json) -> Node:
  Group{"selvedge", "screen", "Selvedge",
    List.append(&2, Node, notices(J.boolean(J.get(reply, "ok")), reply),
      [navigation(state, Commands.entries(world)), panel(state, world)])}

def embedded_task(id: Maybe<&2, Nat>, after: Maybe<&2, Nat>, +world: M.World) -> +List<Node>:
  match id:
    case None{}: Nil{}
    case Some{id}: [task_panel(T.find(Commands.entries(world), id), after, world)]

def screen_pane(pane: B.Pane, +state: M.ViewState, +world: M.World, +reply: J.Json) -> Node:
  match pane:
    case B.ThreadsPane{}: thread_screen(state, world, reply)
    case _:
      M.ViewState{selected, after, tasks_after, profile, +cursor} = state
      Group{"selvedge", "board-screen", "", List.append(&2, Node, notices(J.boolean(J.get(reply, "ok")), reply),
        [Composition{"board", "task-board", BoardView.screen(cursor, profile, world),
          embedded_task(BoardView.active_task(BoardNav.dialog_of(cursor), world), after, world)}])}

def screen(+state: M.ViewState, world: M.World, reply: J.Json) -> Node:
  M.ViewState{selected, after, tasks_after, profile, cursor} = state
  screen_pane(BoardNav.pane_of(cursor), state, world, reply)

def follow_created(ok: Bool, +reply: J.Json, previous: M.ViewState) -> M.ViewState:
  match ok:
    case False{}: previous
    case True{}:
      M.ViewState{selected, after, tasks_after, profile, board} = previous
      M.ViewState{J.natural(J.get(J.get(reply, "result"), "task_id")), None{}, tasks_after, profile, board}

def navigate(event: M.ViewEvent, previous: M.ViewState, +reply: J.Json) -> M.ViewState:
  match event previous:
    case M.SelectTask{id} M.ViewState{selected, after, tasks_after, profile, board}:
      M.ViewState{id, None{}, tasks_after, profile, BoardNav.with_pane(B.ThreadsPane{}, board)}
    case M.HistoryPage{offset} M.ViewState{selected, after, tasks_after, profile, board}: M.ViewState{selected, offset, tasks_after, profile, board}
    case M.TaskPage{offset} M.ViewState{selected, after, tasks_after, profile, board}: M.ViewState{selected, after, offset, profile, board}
    case M.SelectProfile{profile} M.ViewState{selected, after, tasks_after, old, board}: M.ViewState{selected, after, tasks_after, profile, board}
    case M.BoardEvent{B.OpenDialog{B.AgentDialog{id}}} M.ViewState{selected, after, tasks_after, profile, board}:
      M.ViewState{selected, after, tasks_after, "", BoardNav.navigate(B.OpenDialog{B.AgentDialog{id}}, board)}
    case M.BoardEvent{event} M.ViewState{selected, after, tasks_after, profile, board}:
      M.ViewState{selected, after, tasks_after, profile, BoardNav.navigate(event, board)}
    case M.Submit{M.BoardCommand{command}} M.ViewState{selected, after, tasks_after, profile, board}:
      M.ViewState{selected, after, tasks_after, profile, BoardNav.submitted(J.boolean(J.get(reply, "ok")), command, reply, board)}
    case M.Submit{M.Create{profile, reasoning, message, options}} M.ViewState{selected, after, tasks_after, old, board}:
      follow_created(J.boolean(J.get(reply, "ok")), reply, M.ViewState{selected, after, tasks_after, profile, BoardNav.with_pane(B.ThreadsPane{}, board)})
    case M.Submit{M.CreateProject{name, workspace, guidance}} M.ViewState{selected, after, tasks_after, profile, board}:
      M.ViewState{selected, after, tasks_after, profile, BoardNav.project_submitted(J.boolean(J.get(reply, "ok")), board)}
    case M.Submit{M.UpdateProject{id, name, workspace, guidance}} M.ViewState{selected, after, tasks_after, profile, board}:
      M.ViewState{selected, after, tasks_after, profile, BoardNav.project_submitted(J.boolean(J.get(reply, "ok")), board)}
    case _ _: previous

def receipt(event: M.ViewEvent, reply: J.Json) -> J.Json:
  match event:
    case M.Submit{command}: reply
    case _: M.success(J.Null{})

# This runs after scheduling, before output admission. The tree therefore
# describes the exact candidate being committed; an oversized tree rolls back
# that entire candidate rather than publishing a stale or partial screen.
def decorate(input: M.Input, decision: M.Decision) -> M.Decision:
  match input:
    case M.UserInterface{state, +event}:
      M.Decision{+world, +reply, effects} = decision
      +next = navigate(event, state, reply)
      +result = receipt(event, reply)
      M.Decision{world, M.success(J.Object{[J.Field{"presentation", json(Presentation{next, screen(next, world, result)})}, J.Field{"receipt", result}]}), effects}
    case _: decision
