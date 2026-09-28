import Base
import ./bendlib/surface.bend as Surface
import ./bendlib/feature-view.bend as FeatureView
import ./bendlib/feature-codec.bend as FeatureCodec
import ./bendlib/feature-ui.bend as FeatureUI
import ./FEATURES.bend as Features
import ./bendlib/component.bend as Component
import ./bendlib/domain.bend as D
import ./MODEL.bend as M
import ./REASONING.bend as Reasoning
import ./COMMANDS.bend as Commands
import ./bendlib/json.bend as J
import ./bendlib/tasks.bend as T
import ./bendlib/operations.bend as Ops
import ./bendlib/command-codec.bend as CommandCodec
import ./bendlib/conversation.bend as Conversation

def initial() -> M.ViewState:
  M.ViewState{None{}, None{}, 0n, "", Features.initial_cursor()}

def page_size() -> Nat:
  40n

def selected(operation: Commands.Operation) -> Bool:
  Commands.admitted(operation)

# This is the command resolver's answer, not a frontend lifecycle table.
def enabled(command: M.Command, world: M.World()) -> Bool:
  selected(Commands.resolve(command, world))

def command(event: M.ViewEvent) -> M.Command:
  match event:
    case M.Submit{command}: command
    case _: M.Observe{M.Describe{}}

def state_json(state: M.ViewState) -> J.Json:
  M.ViewState{selected, after, tasks_after, profile, cursor} = state
  J.Object{List.append(&2, J.Field,
    [J.Field{"selected", J.optional_nat(selected)}, J.Field{"after", J.optional_nat(after)},
     J.Field{"tasks_after", J.nat(tasks_after)}, J.Field{"profile", J.Text{profile}}],
    FeatureCodec.cursor_fields(cursor))}

def command_json(command: M.Command) -> J.Json:
  CommandCodec.command_json(command)

def event_json(event: M.ViewEvent) -> J.Json:
  CommandCodec.event_json(event)

def choices_json(choices: +List<Surface.Choice>) -> +List<J.Json>:
  match choices:
    case Nil{}: Nil{}
    case Con{Surface.Choice{value, label}, rest}:
      J.Object{[J.Field{"value", J.Text{value}}, J.Field{"label", J.Text{label}}]} <> choices_json(rest)

def fields_json(fields: +List<Surface.Field>) -> +List<J.Json>:
  match fields:
    case Nil{}: Nil{}
    case Con{Surface.Field{+name, label, kind, value, schema, choices, required}, rest}:
      J.Object{[J.Field{"name", J.Text{name}}, J.Field{"label", J.Text{label}}, J.Field{"kind", J.Text{kind}},
        J.Field{"value", value}, J.Field{"schema", schema}, J.Field{"choices", J.Array{choices_json(choices)}},
        J.Field{"required", J.Boolean{required}}, J.Field{"binding", J.Array{[J.Text{"command"}, J.Text{name}]}}]} <> fields_json(rest)

def form_changes(command: M.Command) -> J.Json:
  match command:
    case M.Create{profile, reasoning, message, options}:
      J.Object{[J.Field{"profile", J.Object{[J.Field{"event", event_json(M.SelectProfile{profile})},
        J.Field{"binding", J.Array{[J.Text{"profile"}]}}, J.Field{"reset_fields", J.Array{[J.Text{"reasoning"}]}}]}}]}
    case _: J.Object{Nil{}}

def first_node(nodes: +List<J.Json>) -> J.Json:
  match nodes:
    case Nil{}: J.Null{}
    case Con{node, rest}: node

def nodes_json(nodes: +List<Surface.Node>) -> +List<J.Json>:
  match nodes:
    case Nil{}: Nil{}
    case Con{Surface.Thread{key, task_id, title, subtitle, timeline, composer, details, actions}, rest}:
      J.Object{[J.Field{"kind", J.Text{"thread"}}, J.Field{"key", J.Text{key}},
        J.Field{"task_id", J.optional_nat(task_id)}, J.Field{"title", J.Text{title}}, J.Field{"subtitle", J.Text{subtitle}},
        J.Field{"timeline", J.Array{nodes_json(timeline)}}, J.Field{"composer", J.Array{nodes_json(composer)}},
        J.Field{"details", J.Array{nodes_json(details)}}, J.Field{"actions", J.Array{nodes_json(actions)}}]} <> nodes_json(rest)
    case Con{Surface.ThreadLink{key, title, subtitle, state, event, selected}, rest}:
      J.Object{[J.Field{"kind", J.Text{"thread-link"}}, J.Field{"key", J.Text{key}},
        J.Field{"title", J.Text{title}}, J.Field{"subtitle", J.Text{subtitle}}, J.Field{"state", J.Text{state}},
        J.Field{"event", event_json(event)}, J.Field{"selected", J.Boolean{selected}}]} <> nodes_json(rest)
    case Con{Surface.Composer{key, draft_key, title, hint, forms, actions}, rest}:
      J.Object{[J.Field{"kind", J.Text{"composer"}}, J.Field{"key", J.Text{key}},
        J.Field{"draft_key", J.Text{draft_key}}, J.Field{"title", J.Text{title}}, J.Field{"hint", J.Text{hint}},
        J.Field{"forms", J.Array{nodes_json(forms)}}, J.Field{"actions", J.Array{nodes_json(actions)}}]} <> nodes_json(rest)
    case Con{Surface.Activity{key, title, state, children}, rest}:
      J.Object{[J.Field{"kind", J.Text{"activity"}}, J.Field{"key", J.Text{key}},
        J.Field{"title", J.Text{title}}, J.Field{"state", J.Text{Surface.activity_state(state)}},
        J.Field{"children", J.Array{nodes_json(children)}}]} <> nodes_json(rest)
    case Con{Surface.Composition{key, role, properties, children}, rest}:
      J.Object{[J.Field{"kind", J.Text{"composition"}}, J.Field{"key", J.Text{key}}, J.Field{"role", J.Text{role}},
        J.Field{"properties", properties}, J.Field{"children", J.Array{nodes_json(children)}}]} <> nodes_json(rest)
    case Con{Surface.Group{key, role, title, children}, rest}:
      J.Object{[J.Field{"kind", J.Text{"group"}}, J.Field{"key", J.Text{key}}, J.Field{"role", J.Text{role}},
        J.Field{"title", J.Text{title}}, J.Field{"children", J.Array{nodes_json(children)}}]} <> nodes_json(rest)
    case Con{Surface.Text{key, role, title, text}, rest}:
      J.Object{[J.Field{"kind", J.Text{"text"}}, J.Field{"key", J.Text{key}}, J.Field{"role", J.Text{role}},
        J.Field{"title", J.Text{title}}, J.Field{"text", J.Text{text}}]} <> nodes_json(rest)
    case Con{Surface.Value{key, title, value}, rest}:
      J.Object{[J.Field{"kind", J.Text{"value"}}, J.Field{"key", J.Text{key}}, J.Field{"title", J.Text{title}}, J.Field{"value", value}]} <> nodes_json(rest)
    case Con{Surface.Action{key, label, event, enabled, selected}, rest}:
      J.Object{[J.Field{"kind", J.Text{"action"}}, J.Field{"key", J.Text{key}}, J.Field{"label", J.Text{label}},
        J.Field{"event", event_json(event)}, J.Field{"enabled", J.Boolean{enabled}}, J.Field{"selected", J.Boolean{selected}}]} <> nodes_json(rest)
    case Con{Surface.Form{key, title, label, +command, fields, enabled}, rest}:
      J.Object{[J.Field{"kind", J.Text{"form"}}, J.Field{"key", J.Text{key}}, J.Field{"title", J.Text{title}}, J.Field{"label", J.Text{label}},
        J.Field{"event", event_json(M.Submit{command})}, J.Field{"changes", form_changes(command)},
        J.Field{"fields", J.Array{fields_json(fields)}}, J.Field{"enabled", J.Boolean{enabled}}]} <> nodes_json(rest)

def node_json(node: Surface.Node) -> J.Json:
  first_node(nodes_json([node]))

def json(presentation: Surface.Presentation) -> J.Json:
  Surface.Presentation{state, root} = presentation
  J.Object{[J.Field{"state", state_json(state)}, J.Field{"root", node_json(root)}]}

def action(key: String, label: String, +command: M.Command, world: M.World()) -> Surface.Node:
  Surface.Action{key, label, M.Submit{command}, enabled(command, world), False{}}

def form(key: String, title: String, label: String, +command: M.Command, fields: +List<Surface.Field>, world: M.World()) -> Surface.Node:
  Surface.Form{key, title, label, command, fields, enabled(command, world)}

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

def input(command: String, +name: String, label: String, kind: String, value: J.Json, required: Bool) -> Surface.Field:
  Surface.Field{name, label, kind, value, field_schema(command, name), Nil{}, required}

def profile_label(automatic: Bool, name: String) -> String:
  match automatic:
    case True{}: name ++ " Auto"
    case False{}: name

def profile_choices(profiles: +List<D.Profile>) -> +List<Surface.Choice>:
  match profiles:
    case Nil{}: Nil{}
    case Con{D.Profile{+key, provider, model, policy}, rest}:
      Surface.Choice{key, profile_label(Reasoning.automatic(policy), model) ++ " · " ++ provider ++ " / " ++ key} <> profile_choices(rest)

def first_profile(profiles: +List<D.Profile>) -> String:
  match profiles:
    case Nil{}: ""
    case Con{D.Profile{key, provider, model, policy}, rest}: key

def preferred_profile(found: Maybe<&2, D.Profile>, fallback: String) -> String:
  match found:
    case None{}: fallback
    case Some{D.Profile{key, provider, name, policy}}: key

def selected_policy(found: Maybe<&2, D.Profile>) -> Reasoning.Policy:
  match found:
    case None{}: Reasoning.Fixed{}
    case Some{profile}: D.profile_reasoning(profile)

def reasoning_field(policy: Reasoning.Policy) -> Surface.Field:
  match policy:
    case Reasoning.Fixed{}: input("create", "reasoning", "Reasoning", "text", J.Text{"medium"}, True{})
    case Reasoning.Adaptive{evaluator, efforts, baseline, transport, maximum}:
      Surface.Field{"reasoning", "Reasoning", "choice", J.Text{"auto"}, field_schema("create", "reasoning"), [Surface.Choice{"auto", "Auto"}], True{}}

def create_config(preferred: String, environment: D.Environment, world: M.World()) -> Surface.Node:
  D.Environment{catalog, +profiles, max_fork, max_descendants, project, plugins} = environment
  +profile = preferred_profile(D.find_profile(profiles, preferred), first_profile(profiles))
  +policy = selected_policy(D.find_profile(profiles, profile))
  form("create", "New task", "Create task", M.Create{profile, Reasoning.default_selection(policy), "message", J.Object{Nil{}}},
    [Surface.Field{"profile", "Model profile", "choice", J.Text{profile}, field_schema("create", "profile"), profile_choices(profiles), True{}},
      reasoning_field(policy),
      input("create", "message", "What should the agent do?", "multiline", J.Text{""}, True{}),
      input("create", "settings", "Workspace, sandbox, approval and project overrides (JSON; {} uses defaults)", "json", J.Object{Nil{}}, True{})], world)

def create(+world: M.World()) -> Surface.Node:
  create_config("", Commands.settings(world), world)

def is_selected(selected: Maybe<&2, Nat>, id: Nat) -> Bool:
  match selected:
    case None{}: False{}
    case Some{other}: Nat.is_eq(other, id)

def task_label(+task: D.Task) -> String:
  Conversation.title(task)

def approval_directory(context: D.TaskContext) -> String:
  D.TaskContext{D.Workspace{roots, primary}, sandbox, approval, project} = context
  match primary:
    case None{}: "/"
    case Some{directory}: directory

def task_links(tasks: +List<D.Task>, +selected: Maybe<&2, Nat>) -> +List<Surface.Node>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}:
      +id = D.task_id(task)
      Surface.ThreadLink{"select/" ++ Nat.show(id), task_label(task),
        "#" ++ Nat.show(id) ++ " · " ++ approval_directory(D.task_context(task)), Conversation.status(task),
        M.SelectTask{Some{id}}, is_selected(selected, id)} <> task_links(rest, selected)

def bounded(inside: Bool, value: Nat, maximum: Nat) -> Nat:
  match inside:
    case True{}: value
    case False{}: maximum

def clip(+value: Nat, +maximum: Nat) -> Nat:
  bounded(Nat.is_le(value, maximum), value, maximum)

def navigation(+state: M.ViewState, +tasks: +List<D.Task>) -> Surface.Node:
  M.ViewState{selected, history_after, +after, profile, +board} = state
  +total = List.length(&2, D.Task, tasks)
  links = task_links(List.take(&2, D.Task, List.drop(&2, D.Task, tasks, after), page_size()), selected)
  Surface.Group{"navigation", "navigation", "Tasks", List.append(&2, Surface.Node,
    [FeatureView.navigation(),
     Surface.Action{"new", "New task", M.SelectTask{None{}}, True{}, False{}}],
    List.append(&2, Surface.Node, links,
      [Surface.Action{"tasks/previous", "Previous tasks", M.TaskPage{Nat.sub(after, page_size())}, Nat.is_lt(0n, after), False{}},
       Surface.Action{"tasks/next", "Next tasks", M.TaskPage{Nat.add(after, page_size())}, Nat.is_lt(Nat.add(after, page_size()), total), False{}}]))}

def controls(+id: Nat, +world: M.World()) -> Surface.Node:
  Surface.Group{"controls", "actions", "Task controls",
    [action("freeze", "Freeze", M.ChangeStatus{id, D.Freeze{}}, world),
     action("unfreeze", "Unfreeze", M.ChangeStatus{id, D.Unfreeze{}}, world),
     action("stop", "Stop after accepted work", M.ChangeStatus{id, D.Stop{}}, world),
     action("interrupt", "Interrupt now", M.ChangeStatus{id, D.Interrupt{}}, world),
     action("archive", "Archive permanently", M.ChangeStatus{id, D.Archive{}}, world)]}

def approval_controls(reviewer: D.ApprovalReviewer, +id: Nat, +ticket: Nat, +world: M.World()) -> +List<Surface.Node>:
  match reviewer:
    case D.HumanReviewer{}:
      [Surface.Group{"review/actions", "actions", "Decision",
        [action("approval/allow/" ++ Nat.show(ticket), "Approve once",
           M.ReviewApproval{id, ticket, D.ApprovalAllowed{"Approved once by the user in the UI."}}, world),
         action("approval/deny/" ++ Nat.show(ticket), "Deny",
           M.ReviewApproval{id, ticket, D.ApprovalDenied{"Denied by the user in the UI."}}, world)]}]
    case D.ModelReviewer{D.Profile{profile, provider, model, policy}}:
      [Surface.Text{"review/model", "note", "Approval for Me",
        "An independent, tool-free call to " ++ profile ++ " is reviewing this command. Bash has not started."}]

def approval_nodes(stage: D.OperationStage, +operation: D.Operation(), +task: D.Task, +world: M.World()) -> +List<Surface.Node>:
  match stage:
    case D.ApprovalPending{reviewer}:
      +arguments = T.call_arguments(Ops.call(operation))
      [Surface.Group{"review", "approval", "Permission request",
        List.append(&2, Surface.Node,
          [Surface.Text{"review/command", "command", "Exact Bash command", J.text(J.get(arguments, "command"))},
           Surface.Text{"review/reason", "note", "Agent's reason", J.text(J.get(arguments, "justification"))},
           Surface.Text{"review/cwd", "note", "Working directory", approval_directory(D.task_context(task))},
           Surface.Text{"review/scope", "note", "Requested access",
             "Run this invocation once outside filesystem and network isolation. The task's saved settings stay unchanged. A frozen task waits until resumed."},
           Surface.Value{"review/settings", "Frozen workspace and permissions", D.task_context_json(D.task_context(task))}],
          approval_controls(reviewer, D.task_id(task), Ops.ticket(operation), world))}]
    case D.ApprovalGranted{reviewer}:
      [Surface.Text{"review/granted", "note", "Approved; waiting to run", Ops.stage_notice(D.ApprovalGranted{reviewer})}]
    case _: Nil{}

def operation_state(stage: D.OperationStage) -> Surface.ActivityState:
  match stage:
    case D.ApprovalPending{reviewer}: Surface.Waiting{}
    case D.ApprovalGranted{reviewer}: Surface.Waiting{}
    case _: Surface.Running{}

def operation_nodes(operations: +List<D.Operation()>, +task: D.Task, +world: M.World()) -> +List<Surface.Node>:
  match operations:
    case Nil{}: Nil{}
    case Con{+operation, rest}:
      +ticket = Ops.ticket(operation)
      Surface.Activity{"operation/" ++ Nat.show(ticket), T.call_name(Ops.call(operation)), operation_state(Ops.stage(operation)),
        List.append(&2, Surface.Node, approval_nodes(Ops.stage(operation), operation, task, world),
          [Surface.Value{"details", "Live operation", Ops.summary(operation)},
           action("cancel/" ++ Nat.show(ticket), "Cancel this operation", M.Cancel{D.task_id(task), ticket}, world)])} <>
        operation_nodes(rest, task, world)

def lineage_nodes(lineage: +List<Nat>) -> +List<Surface.Node>:
  match lineage:
    case Nil{}: Nil{}
    case Con{+id, rest}: Surface.Action{"ancestor/" ++ Nat.show(id), "Open ancestor #" ++ Nat.show(id), M.SelectTask{Some{id}}, True{}, False{}} <> lineage_nodes(rest)

def result_state(error: Bool) -> Surface.ActivityState:
  match error:
    case True{}: Surface.Failed{}
    case False{}: Surface.Complete{}

def output_node(value: J.Json) -> Surface.Node:
  match value:
    case J.Text{text}: Surface.Text{"output", "tool-output", "Output", text}
    case value: Surface.Value{"output", "Output", value}

def result_node(key: String, title: String, value: J.Json, error: Bool) -> Surface.Node:
  Surface.Activity{key, title, result_state(error), [output_node(value)]}

def assistant_context(assistant: Bool, value: J.Json, key: String) -> +List<Surface.Node>:
  match assistant:
    case True{}: [Surface.Text{key, "assistant", "Agent", Conversation.content_parts(J.items(J.get(value, "content")))}]
    case False{}: Nil{}

def provider_context(kind: Conversation.ContextKind, +value: J.Json, key: String) -> +List<Surface.Node>:
  match kind:
    case Conversation.SpeechContext{}: assistant_context(String.eq(J.text(J.get(value, "role")), "assistant"), value, key)
    case Conversation.ReasoningContext{}: [Surface.Activity{key, "Thinking", Surface.Informational{},
      [Surface.Text{"summary", "note", "Reasoning summary", Conversation.content_parts(J.items(J.get(value, "summary")))}]}]
    case Conversation.CompactionContext{}: [Surface.Activity{key, "Context compacted", Surface.Complete{},
      [Surface.Text{"context", "note", "Provider context retained", "Available to subsequent model requests."}]}]
    case Conversation.OtherContext{}: Nil{}

def message_nodes(message: D.Message, +key: String) -> +List<Surface.Node>:
  match message:
    case D.ReasoningRecord{owner, +effort, remaining, True{}}:
      [Surface.Activity{key, "Reasoning · " ++ effort, Surface.Informational{},
        [Surface.Value{"decision", "Reasoning decision", J.Object{[J.Field{"requested_effort", J.Text{effort}},
          J.Field{"generations_remaining", J.nat(remaining)}]}}]}]
    case D.ReasoningRecord{owner, effort, remaining, False{}}: Nil{}
    case D.ConfigurationUpdate{effort}: Nil{}
    case D.ForkResult{owner, call_id, +branch}: [Surface.Activity{key, "Created branch #" ++ Nat.show(branch), Surface.Complete{},
      [Surface.Action{"open", "Open branch", M.SelectTask{Some{branch}}, True{}, False{}}]}]
    case D.HookRecord{owner, call_id, plugin, outcome}: Nil{}
    case D.ToolReceipt{owner, operation, call, value, error}: Nil{}
    case D.AfterRecord{owner, operation, plugin, outcome}: Nil{}
    case D.ApprovalRecord{owner, operation, call, reviewer, outcome}: Nil{}
    case D.UserMessage{text}: [Surface.Text{key, "user", "You", text}]
    case D.AssistantMessage{text}: [Surface.Text{key, "assistant", "Agent", text}]
    case D.FunctionCall{+call}: [Surface.Activity{key, T.call_name(call), Surface.Informational{},
      [Surface.Value{"call", "Arguments", T.call_json(call)}]}]
    case D.FunctionOutput{id, value, error}: [result_node(key, "Tool result · " ++ id, value, error)]
    case D.OperationResult{ticket, id, tool, value, error}:
      [result_node(key, tool ++ " · " ++ Nat.show(ticket), value, error)]
    case D.FailureMessage{text}: [Surface.Text{key, "error", "Execution error", text}]
    case D.ContextCheckpoint{text}: [Surface.Activity{key, "Context checkpoint", Surface.Complete{},
      [Surface.Text{"checkpoint", "note", "Checkpoint", text}]}]
    case D.ModelContext{+value}: provider_context(Conversation.context_kind(J.text(J.get(value, "type"))), value, key)

def messages(items: +List<D.Message>, +offset: Nat) -> +List<Surface.Node>:
  match items:
    case Nil{}: Nil{}
    case Con{message, rest}:
      List.append(&2, Surface.Node, message_nodes(message, "message/" ++ Nat.show(offset)), messages(rest, 1n+offset))

# Execution receipts and hook decisions remain inspectable without masquerading
# as conversation messages or repeating a tool's already-visible result.
def audit_message(+message: D.Message, key: String) -> +List<Surface.Node>:
  match message:
    case D.HookRecord{owner, +call_id, plugin, outcome}:
      [Surface.Value{key, "Hook decision · " ++ call_id, T.message_json(D.HookRecord{owner, call_id, plugin, outcome})}]
    case D.ToolReceipt{owner, +operation, call, value, error}:
      [Surface.Value{key, "Execution receipt · " ++ Nat.show(operation), T.message_json(D.ToolReceipt{owner, operation, call, value, error})}]
    case D.AfterRecord{owner, +operation, plugin, outcome}:
      [Surface.Value{key, "Result hook · " ++ Nat.show(operation), T.message_json(D.AfterRecord{owner, operation, plugin, outcome})}]
    case D.ApprovalRecord{owner, +operation, call, reviewer, outcome}:
      [Surface.Value{key, "Approval decision · " ++ Nat.show(operation), T.message_json(D.ApprovalRecord{owner, operation, call, reviewer, outcome})}]
    case _: Nil{}

def audit_messages(items: +List<D.Message>, +offset: Nat) -> +List<Surface.Node>:
  match items:
    case Nil{}: Nil{}
    case Con{message, rest}:
      List.append(&2, Surface.Node, audit_message(message, "audit/" ++ Nat.show(offset)), audit_messages(rest, 1n+offset))

def history_offset(after: Maybe<&2, Nat>, +total: Nat) -> Nat:
  match after:
    case None{}: Nat.sub(total, page_size())
    case Some{offset}: clip(offset, total)

def audit_trail(+task: D.Task, after: Maybe<&2, Nat>) -> Surface.Node:
  +history = D.task_history(task)
  +offset = history_offset(after, D.history_length(history))
  Surface.Group{"audit", "details", "Execution audit · current history page",
    audit_messages(List.take(&2, D.Message, List.drop(&2, D.Message, D.history_messages(history, Nil{}), offset), page_size()), offset)}

def transcript(+task: D.Task, after: Maybe<&2, Nat>) -> Surface.Node:
  +history = D.task_history(task)
  +total = D.history_length(history)
  +offset = history_offset(after, total)
  Surface.Group{"transcript", "transcript", "Conversation",
    List.append(&2, Surface.Node,
      [Surface.Group{"history/pages", "actions", "History",
        [Surface.Action{"history/previous", "Earlier messages", M.HistoryPage{Some{Nat.sub(offset, page_size())}}, Nat.is_lt(0n, offset), False{}},
         Surface.Action{"history/next", "Later messages", M.HistoryPage{Some{Nat.add(offset, page_size())}}, Nat.is_lt(Nat.add(offset, page_size()), total), False{}},
         Surface.Action{"history/latest", "Follow latest", M.HistoryPage{None{}}, True{}, False{}}]}],
      messages(List.take(&2, D.Message, List.drop(&2, D.Message, D.history_messages(history, Nil{}), offset), page_size()), offset))}

def send_forms(+id: Nat, +world: M.World()) -> Surface.Node:
  Surface.Composer{"compose", "task/" ++ Nat.show(id), "Message", "Send queues the message. Steer changes the current direction immediately.",
    [form("send/" ++ Nat.show(id), "Send a follow-up", "Send", M.Send{id, "message"},
       [input("send", "message", "Message", "multiline", J.Text{""}, True{})], world),
     form("steer/" ++ Nat.show(id), "Change direction now", "Steer", M.Steer{id, "message"},
       [input("steer", "message", "Message", "multiline", J.Text{""}, True{})], world)], Nil{}}

def advanced(+id: Nat, +world: M.World()) -> Surface.Node:
  Surface.Group{"advanced", "details", "Branch and context",
    [form("fork/" ++ Nat.show(id), "Fork this task", "Create branches", M.Fork{id, 1n, Nil{}, J.Object{Nil{}}},
       [input("fork", "child_count", "Children", "integer", J.nat(1n), True{}),
        input("fork", "settings", "Child overrides (JSON; {} inherits the parent)", "json", J.Object{Nil{}}, True{})], world),
     action("compact/" ++ Nat.show(id), "Ask the model for a checkpoint", M.Compact{id, None{}}, world),
     form("checkpoint/" ++ Nat.show(id), "Supply a checkpoint", "Save checkpoint", M.Compact{id, Some{"summary"}},
       [input("compact", "summary", "Summary", "multiline", J.Text{""}, True{})], world)]}

def tools(entries: +List<D.Tool>, +catalog: +List<D.Tool>) -> +List<Surface.Node>:
  match entries:
    case Nil{}: Nil{}
    case Con{+tool, rest}:
      D.Tool{+name, description, schema, source} = tool
      Surface.Group{"tool/" ++ name, "details", name,
        [Surface.Text{"description", "note", "Purpose", description},
         Surface.Value{"availability", "Available now", J.Boolean{T.available(catalog, tool)}},
         Surface.Value{"schema", "Arguments", schema}]} <> tools(rest, catalog)

def task_surface(+task: D.Task, +after: Maybe<&2, Nat>, environment: D.Environment, +world: M.World()) -> Surface.Node:
  D.Environment{catalog, profiles, max_fork, max_descendants, project, plugins} = environment
  +id = D.task_id(task)
  Surface.Thread{"task/" ++ Nat.show(id), Some{id}, task_label(task),
    Conversation.status(task) ++ " · " ++ approval_directory(D.task_context(task)),
    [transcript(task, after), Surface.Group{"operations", "operations", "", operation_nodes(D.task_operations(task), task, world)}],
    [send_forms(id, world)],
    [Surface.Group{"lineage", "actions", "Ancestry", lineage_nodes(D.task_lineage(task))},
     Surface.Value{"state", "Current state", T.summary(task)}, advanced(id, world), audit_trail(task, after),
     Surface.Group{"tools", "details", "Frozen tool contract", tools(T.task_tools(D.task_contract(task)), catalog)}],
    [controls(id, world)]}

def new_thread(preferred: String, +world: M.World()) -> Surface.Node:
  Surface.Thread{"new-task", None{}, "New task", "",
    [Surface.Text{"welcome", "welcome", "What would you like to work on?", ""}],
    [Surface.Composer{"compose", "new-task", "New task", "Enter to send · Shift + Enter for a new line",
      [create_config(preferred, Commands.settings(world), world)], Nil{}}], Nil{}, Nil{}}

def task_panel(found: Maybe<&2, D.Task>, after: Maybe<&2, Nat>, +world: M.World()) -> Surface.Node:
  match found:
    case None{}: Surface.Thread{"missing", None{}, "Task unavailable", "",
      [Surface.Text{"missing/reason", "error", "No such task", "Select a task or create a new one."}],
      [Surface.Composer{"compose", "new-task", "New task", "", [create(world)], Nil{}}], Nil{}, Nil{}}
    case Some{task}: task_surface(task, after, Commands.settings(world), world)

def panel(state: M.ViewState, +world: M.World()) -> Surface.Node:
  M.ViewState{selected, after, tasks_after, profile, +board} = state
  match selected:
    case None{}: new_thread(profile, world)
    case Some{id}: task_panel(T.find(Commands.entries(world), id), after, world)

def notices(ok: Bool, reply: J.Json) -> +List<Surface.Node>:
  match ok:
    case True{}: Nil{}
    case False{}: [Surface.Text{"notice", "error", "Request was not accepted", J.text(J.get(J.get(reply, "error"), "message"))}]

def thread_screen(+state: M.ViewState, +world: M.World(), +reply: J.Json) -> Surface.Node:
  Surface.Group{"selvedge", "screen", "Selvedge",
    List.append(&2, Surface.Node, notices(J.boolean(J.get(reply, "ok")), reply),
      [navigation(state, Commands.entries(world)), panel(state, world)])}

def embedded_task(id: Maybe<&2, Nat>, after: Maybe<&2, Nat>, +world: M.World()) -> +List<Surface.Node>:
  match id:
    case None{}: Nil{}
    case Some{id}: [task_panel(T.find(Commands.entries(world), id), after, world)]

def screen(state: M.ViewState, world: M.World(), reply: J.Json) -> Surface.Node:
  FeatureView.screen(state => world => reply => thread_screen(state, world, reply),
    id => after => world => embedded_task(id, after, world), notices, state, world, reply)

def follow_created(ok: Bool, +reply: J.Json, previous: M.ViewState) -> M.ViewState:
  match ok:
    case False{}: previous
    case True{}:
      M.ViewState{selected, after, tasks_after, profile, +board} = previous
      M.ViewState{J.natural(J.get(J.get(reply, "result"), "task_id")), None{}, tasks_after, profile, board}

def navigate(event: M.ViewEvent, previous: M.ViewState, +reply: J.Json) -> M.ViewState:
  match event previous:
    case M.SelectTask{id} M.ViewState{selected, after, tasks_after, profile, +board}:
      M.ViewState{id, None{}, tasks_after, profile, FeatureUI.select_task(board)}
    case M.HistoryPage{offset} M.ViewState{selected, after, tasks_after, profile, +board}: M.ViewState{selected, offset, tasks_after, profile, board}
    case M.TaskPage{offset} M.ViewState{selected, after, tasks_after, profile, +board}: M.ViewState{selected, after, offset, profile, board}
    case M.SelectProfile{profile} M.ViewState{selected, after, tasks_after, old, +board}: M.ViewState{selected, after, tasks_after, profile, board}
    case M.FeatureEvent{event} _: FeatureUI.navigate(event, previous)
    case M.Submit{M.FeatureCommand{command}} _: FeatureUI.submitted(command, reply, previous)
    case M.Submit{M.Create{profile, reasoning, message, options}} M.ViewState{selected, after, tasks_after, old, +board}:
      follow_created(J.boolean(J.get(reply, "ok")), reply, M.ViewState{selected, after, tasks_after, profile, FeatureUI.select_task(board)})
    case M.Submit{M.CreateProject{name, workspace, guidance}} M.ViewState{selected, after, tasks_after, profile, +board}:
      M.ViewState{selected, after, tasks_after, profile, FeatureUI.project_submitted(J.boolean(J.get(reply, "ok")), board)}
    case M.Submit{M.UpdateProject{id, name, workspace, guidance}} M.ViewState{selected, after, tasks_after, profile, +board}:
      M.ViewState{selected, after, tasks_after, profile, FeatureUI.project_submitted(J.boolean(J.get(reply, "ok")), board)}
    case _ _: previous

def receipt(event: M.ViewEvent, reply: J.Json) -> J.Json:
  match event:
    case M.Submit{command}: reply
    case _: D.success(J.Null{})

# This runs after scheduling, before output admission. The tree therefore
# describes the exact candidate being committed; an oversized tree rolls back
# that entire candidate rather than publishing a stale or partial screen.
def decorate(input: M.Input, decision: M.Decision()) -> M.Decision():
  match input:
    case M.UserInterface{state, +event}:
      Component.Decision{+world, +reply, effects} = decision
      +next = navigate(event, state, reply)
      +result = receipt(event, reply)
      Component.Decision{world, D.success(J.Object{[J.Field{"presentation", json(Surface.Presentation{next, screen(next, world, result)})}, J.Field{"receipt", result}]}), effects}
    case _: decision
