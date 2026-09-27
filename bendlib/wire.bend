import Base
import ../MODEL.bend as M
import ./protocol.bend as Protocol
import ./json.bend as J
import ./schema.bend as Schema
import ./tasks.bend as T
import ./presentation.bend as View
import ../INVARIANTS.bend as I
import ../UI.bend as UI
import ../HOOKS.bend as Hooks

def exact_keys(fields: +List<J.Field>, +allowed: +List<String>, +seen: +List<String>) -> Bool:
  match fields:
    case Nil{}: Nat.is_eq(List.length(&2, String, seen), List.length(&2, String, allowed))
    case Con{J.Field{+key, value}, rest}:
      T.has_name(allowed, key) && Bool.not(T.has_name(seen, key)) && exact_keys(rest, allowed, key <> seen)

def object_keys(value: J.Json, allowed: +List<String>) -> Bool:
  match value:
    case J.Object{fields}: exact_keys(fields, allowed, Nil{})
    case _: False{}

# This module converts untrusted values into domain constructors. The host wraps
# public commands; only trusted host paths may construct completion/config inputs.
def choose_spec(same: Bool, spec: M.CommandSpec, rest: Maybe<&2, M.CommandSpec>) -> Maybe<&2, M.CommandSpec>:
  match same:
    case True{}: Some{spec}
    case False{}: rest

def find_spec(specs: +List<M.CommandSpec>, +name: String) -> Maybe<&2, M.CommandSpec>:
  match specs:
    case Nil{}: None{}
    case Con{M.CommandSpec{+key, +description, +kind, +schema}, rest}:
      choose_spec(String.eq(key, name), M.CommandSpec{key, description, kind, schema}, find_spec(rest, name))

def text_or(value: J.Json, fallback: String) -> String:
  match value:
    case J.Text{text}: text
    case _: fallback

def optional_text(value: J.Json) -> Maybe<&2, String>:
  match value:
    case J.Text{text}: Some{text}
    case _: None{}

def construct_command(kind: M.CommandKind, +body: J.Json) -> M.Command:
  match kind:
    case M.CreateCommand{}:
      M.Create{J.text(J.get(body, "profile")), text_or(J.get(body, "reasoning"), "medium"), J.text(J.get(body, "message")), J.get(body, "settings")}
    case M.SendCommand{}:
      M.Send{Protocol.number(body, "task_id", 0n), J.text(J.get(body, "message"))}
    case M.SteerCommand{}:
      M.Steer{Protocol.number(body, "task_id", 0n), J.text(J.get(body, "message"))}
    case M.CancelCommand{}:
      M.Cancel{Protocol.number(body, "task_id", 0n), Protocol.number(body, "operation_id", 0n)}
    case M.ControlCommand{control}:
      M.ChangeStatus{Protocol.number(body, "task_id", 0n), control}
    case M.ForkCommand{}:
      M.Fork{Protocol.number(body, "task_id", 0n), Protocol.number(body, "child_count", 0n),
        Protocol.messages(J.items(J.get(body, "messages"))), J.get(body, "settings")}
    case M.ReadCommand{}:
      M.Observe{M.Read{Protocol.number(body, "task_id", 0n), Protocol.number(body, "after", 0n), Protocol.number(body, "limit", 100n)}}
    case M.ListCommand{}: M.Observe{M.ListTasks{}}
    case M.CompactCommand{}: M.Compact{Protocol.number(body, "task_id", 0n), optional_text(J.get(body, "summary"))}
    case M.DescribeCommand{}: M.Observe{M.Describe{}}
    case M.CreateProjectCommand{}:
      M.CreateProject{J.text(J.get(body, "name")), J.get(body, "workspace"), J.get(body, "guidance")}
    case M.UpdateProjectCommand{}:
      M.UpdateProject{Protocol.number(body, "project_id", 0n), optional_text(J.get(body, "name")), J.get(body, "workspace"), J.get(body, "guidance")}
    case M.DeleteProjectCommand{}: M.DeleteProject{Protocol.number(body, "project_id", 0n)}
    case M.ListProjectsCommand{}: M.Observe{M.ListProjects{}}
    case M.ReadProjectCommand{}: M.Observe{M.ReadProject{Protocol.number(body, "project_id", 0n)}}

def command_valid(valid: Bool, kind: M.CommandKind, body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Command does not satisfy its declared schema"}
    case True{}: Done{M.UserCommand{construct_command(kind, body)}}

def command_spec(found: Maybe<&2, M.CommandSpec>, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match found:
    case None{}: Fail{"Unknown command; use describe for the executable vocabulary"}
    case Some{M.CommandSpec{name, description, kind, schema}}:
      command_valid(Schema.valid(schema, body), kind, body)

def decode_command(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  command_spec(find_spec(M.commands(), J.text(J.get(body, "op"))), body)

def is_some(value: Maybe<&2, Nat>) -> Bool:
  match value:
    case Some{n}: True{}
    case None{}: False{}

def is_natural(value: J.Json) -> Bool:
  match value:
    case J.Number{lexeme}: is_some(Nat.read(lexeme))
    case _: False{}

def item_kind(kind: String, +value: J.Json) -> M.ModelItem:
  match kind:
    case "call": M.Invoke{M.Call{J.text(J.get(value, "id")), J.text(J.get(value, "name")), J.get(value, "arguments")}}
    case "context": M.Context{J.get(value, "value")}
    case _: M.Say{J.text(J.get(value, "text"))}

def model_items(values: +List<J.Json>) -> +List<M.ModelItem>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      item_kind(J.text(J.get(value, "type")), value) <> model_items(rest)

def valid_item_kind(kind: String, +value: J.Json) -> Bool:
  match kind:
    case "text": J.is_text(J.get(value, "text"))
    case "call": J.is_text(J.get(value, "id")) && J.is_text(J.get(value, "name")) && J.is_object(J.get(value, "arguments"))
    case "context": J.is_object(J.get(value, "value"))
    case _: False{}

def valid_items(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}: valid_item_kind(J.text(J.get(value, "type")), value) && valid_items(rest)

def is_array(value: J.Json) -> Bool:
  match value:
    case J.Array{values}: True{}
    case _: False{}

def is_bool(value: J.Json) -> Bool:
  match value:
    case J.Boolean{boolean}: True{}
    case _: False{}

def model_failure(kind: J.Json, message: String) -> M.Outcome:
  match kind:
    case J.Text{"context_limit"}: M.ContextLimit{}
    case _: M.ModelFailure{message}

def valid_failure_kind(kind: J.Json) -> Bool:
  match kind:
    case J.Null{}: True{}
    case J.Text{"context_limit"}: True{}
    case _: False{}

def model_outcome(ok: Bool, +body: J.Json) -> M.Outcome:
  match ok:
    case True{}: M.ModelReply{model_items(J.items(J.get(body, "items")))}
    case False{}: model_failure(J.get(body, "failure_kind"), J.text(J.get(body, "message")))

def valid_model_payload(ok: Bool, +body: J.Json) -> Bool:
  match ok:
    case True{}: is_array(J.get(body, "items")) && valid_items(J.items(J.get(body, "items")))
    case False{}: J.is_text(J.get(body, "message")) && valid_failure_kind(J.get(body, "failure_kind"))

def model_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed model completion"}
    case True{}:
      Done{M.ModelCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
        model_outcome(J.boolean(J.get(body, "ok")), body)}}

def decode_model(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  model_valid(is_natural(J.get(body, "task_id")) && is_natural(J.get(body, "ticket")) &&
    is_bool(J.get(body, "ok")) && valid_model_payload(J.boolean(J.get(body, "ok")), body), body)

def tool_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed tool completion"}
    case True{}:
      Done{M.ToolCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
        J.get(body, "value"), J.boolean(J.get(body, "error"))}}

def decode_tool(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  tool_valid(is_natural(J.get(body, "task_id")) && is_natural(J.get(body, "ticket")) && is_bool(J.get(body, "error")), body)

def profile_values(values: +List<J.Json>) -> +List<M.Profile>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      M.Profile{J.text(J.get(value, "key")), J.text(J.get(value, "provider")), J.text(J.get(value, "name"))} <> profile_values(rest)

def valid_profiles(values: +List<J.Json>, +seen: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}:
      +key = J.text(J.get(value, "key"))
      M.nonempty(key) && M.nonempty(J.text(J.get(value, "provider"))) && M.nonempty(J.text(J.get(value, "name"))) &&
        Bool.not(T.has_name(seen, key)) && valid_profiles(rest, key <> seen)

def plugin_ref(+value: J.Json) -> M.PluginRef:
  M.PluginRef{J.text(J.get(value, "name")), J.text(J.get(value, "revision"))}

def source(plugin: J.Json, +value: J.Json) -> M.Source:
  match plugin:
    case J.Null{}: M.Mcp{J.text(J.get(value, "server")), J.text(J.get(value, "remote"))}
    case other: M.Extension{plugin_ref(other), J.text(J.get(value, "remote"))}

def valid_ref(+value: J.Json) -> Bool:
  object_keys(value, ["name", "revision"]) && J.is_text(J.get(value, "name")) && J.is_text(J.get(value, "revision")) &&
    Hooks.reference_valid(plugin_ref(value))

def valid_route(plugin: J.Json, +value: J.Json) -> Bool:
  match plugin:
    case J.Null{}: String.starts_with(J.text(J.get(value, "name")), "mcp__") && M.nonempty(J.text(J.get(value, "server")))
    case +other: valid_ref(other) && String.eq(J.text(J.get(value, "name")), "plugin__" ++ Hooks.plugin_name(plugin_ref(other)) ++ "__" ++ J.text(J.get(value, "remote")))

def remote_tools(values: +List<J.Json>) -> +List<M.Tool>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      M.Tool{J.text(J.get(value, "name")), J.text(J.get(value, "description")), J.get(value, "schema"),
        source(J.get(value, "plugin"), value)} <> remote_tools(rest)

def valid_remote_tools(values: +List<J.Json>, +seen: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}:
      +name = J.text(J.get(value, "name"))
      M.nonempty(name) && valid_route(J.get(value, "plugin"), value) && Bool.not(T.has_name(seen, name)) &&
        M.nonempty(J.text(J.get(value, "description"))) && J.is_object(J.get(value, "schema")) &&
        M.nonempty(J.text(J.get(value, "remote"))) &&
        valid_remote_tools(rest, name <> seen)

def event_cons(kind: Maybe<&2, M.EventKind>, rest: +List<M.EventKind>) -> +List<M.EventKind>:
  match kind:
    case None{}: rest
    case Some{kind}: kind <> rest

def event_values(values: +List<J.Json>) -> +List<M.EventKind>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: event_cons(M.find_event(M.event_kinds(), J.text(value)), event_values(rest))

def plugin_values(values: +List<J.Json>) -> +List<M.Plugin>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      M.Plugin{plugin_ref(J.get(value, "reference")), J.boolean(J.get(value, "before_tool")),
        J.boolean(J.get(value, "after_tool")),
        event_values(J.items(J.get(value, "events")))} <> plugin_values(rest)

def string_values(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{J.Text{value}, rest}: T.has_name(M.plugin_events(), value) && string_values(rest)
    case _: False{}

def valid_plugin_values(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}:
      object_keys(value, ["reference", "before_tool", "after_tool", "events"]) && valid_ref(J.get(value, "reference")) &&
        is_bool(J.get(value, "before_tool")) && is_bool(J.get(value, "after_tool")) && is_array(J.get(value, "events")) &&
        string_values(J.items(J.get(value, "events"))) && valid_plugin_values(rest)

def valid_plugins(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Array{+values}: valid_plugin_values(values) && Hooks.valid(plugin_values(values))
    case _: False{}

def project(+value: J.Json) -> M.ProjectContext:
  match value:
    case J.Null{}: M.NoProject{}
    case other: M.ProjectContext{J.text(J.get(other, "workspace")), J.text(J.get(other, "revision")), J.text(J.get(other, "instructions"))}

def valid_project(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Object{fields}:
      +body : J.Json = J.Object{fields}
      J.is_text(J.get(body, "workspace")) && J.is_text(J.get(body, "revision")) && J.is_text(J.get(body, "instructions")) &&
        I.project_context(project(body))
    case _: False{}

def config_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed environment: profiles/routes must be unique and limits must be positive integers"}
    case True{}:
      +max_fork = Protocol.number(body, "max_fork", 0n)
      Done{M.Configure{M.Environment{List.append(&2, M.Tool, M.builtins(max_fork), remote_tools(J.items(J.get(body, "tools")))),
        profile_values(J.items(J.get(body, "profiles"))), max_fork, Protocol.number(body, "max_descendants", 0n), project(J.get(body, "project")),
        plugin_values(J.items(J.get(body, "plugins")))}}}

def decode_config(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  config_valid(valid_plugins(J.get(body, "plugins")) && valid_project(J.get(body, "project")) && is_array(J.get(body, "profiles")) && valid_profiles(J.items(J.get(body, "profiles")), Nil{}) &&
    is_array(J.get(body, "tools")) && valid_remote_tools(J.items(J.get(body, "tools")), Nil{}) &&
    is_natural(J.get(body, "max_fork")) && Nat.is_le(1n, Protocol.number(body, "max_fork", 0n)) &&
    is_natural(J.get(body, "max_descendants")) && Nat.is_le(1n, Protocol.number(body, "max_descendants", 0n)), body)

# UI cursors are observations, not cached domain state. The wire may name only
# the public event vocabulary; effect completions cannot be smuggled as events.
def optional_id(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case other: Schema.valid(M.task_id_schema(), other)

def view_state(value: J.Json) -> M.ViewState:
  match value:
    case J.Null{}: UI.initial()
    case +other: M.ViewState{J.natural(J.get(other, "selected")), J.natural(J.get(other, "after")), Protocol.number(other, "tasks_after", 0n)}

def valid_view_state(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case +other: object_keys(other, ["selected", "after", "tasks_after"]) &&
      optional_id(J.get(other, "selected")) && optional_id(J.get(other, "after")) &&
      Schema.valid(M.task_id_schema(), J.get(other, "tasks_after"))

def ui_event(valid: Bool, state: M.ViewState, event: M.ViewEvent) -> Result<&2, &2, String, M.Input>:
  match valid:
    case True{}: Done{M.UserInterface{state, event}}
    case False{}: Fail{"Malformed presentation event"}

def ui_command(valid: Bool, decoded: Result<&2, &2, String, M.Input>, state: M.ViewState) -> Result<&2, &2, String, M.Input>:
  match valid decoded:
    case True{} Done{M.UserCommand{command}}: Done{M.UserInterface{state, M.Submit{command}}}
    case True{} Fail{reason}: Fail{reason}
    case _ _: Fail{"A presentation can submit only a public command"}

def view_event(kind: String, +event: J.Json, state: M.ViewState) -> Result<&2, &2, String, M.Input>:
  match kind:
    case "refresh": ui_event(object_keys(event, ["type"]), state, M.RefreshView{})
    case "select": ui_event(object_keys(event, ["type", "task_id"]) && optional_id(J.get(event, "task_id")),
      state, M.SelectTask{J.natural(J.get(event, "task_id"))})
    case "history": ui_event(object_keys(event, ["type", "after"]) && optional_id(J.get(event, "after")),
      state, M.HistoryPage{J.natural(J.get(event, "after"))})
    case "tasks": ui_event(object_keys(event, ["type", "after"]) && Schema.valid(M.task_id_schema(), J.get(event, "after")),
      state, M.TaskPage{Protocol.number(event, "after", 0n)})
    case "submit": ui_command(object_keys(event, ["type", "command"]), decode_command(J.get(event, "command")), state)
    case _: Fail{"Unknown presentation event"}

def ui_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed presentation cursor"}
    case True{}: view_event(J.text(J.get(J.get(body, "event"), "type")), J.get(body, "event"), view_state(J.get(body, "state")))

def decode_ui(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  ui_valid(valid_view_state(J.get(body, "state")), body)

def hook_outcome(kind: String, +value: J.Json) -> M.HookOutcome:
  match kind:
    case "allow": M.AllowTool{}
    case "rewrite": M.RewriteTool{J.get(value, "arguments")}
    case "deny": M.DenyTool{J.text(J.get(value, "reason"))}
    case _: M.HookFailure{J.text(J.get(value, "reason"))}

def hook_reason(+value: J.Json) -> Bool:
  object_keys(value, ["decision", "reason"]) && M.nonempty(J.text(J.get(value, "reason"))) &&
    Nat.is_le(J.utf8_length(J.text(J.get(value, "reason"))), 4096n)

def valid_hook_outcome(kind: String, +value: J.Json) -> Bool:
  match kind:
    case "allow": object_keys(value, ["decision"])
    case "rewrite": object_keys(value, ["decision", "arguments"]) && J.is_object(J.get(value, "arguments"))
    case "deny": hook_reason(value)
    case "failed": hook_reason(value)
    case _: False{}

def hook_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed hook completion"}
    case True{}: Done{M.HookCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
      hook_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome"))}}

def decode_hook(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  hook_valid(object_keys(body, ["kind", "task_id", "ticket", "outcome"]) && is_natural(J.get(body, "task_id")) &&
    is_natural(J.get(body, "ticket")) && valid_hook_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome")), body)

def after_outcome(kind: String, +value: J.Json) -> M.AfterOutcome:
  match kind:
    case "allow": M.KeepResult{}
    case "rewrite": M.RewriteResult{J.get(value, "value")}
    case "deny": M.DenyResult{J.text(J.get(value, "reason"))}
    case _: M.AfterFailure{J.text(J.get(value, "reason"))}

def valid_after_outcome(kind: String, +value: J.Json) -> Bool:
  match kind:
    case "allow": object_keys(value, ["decision"])
    case "rewrite": object_keys(value, ["decision", "value"])
    case "deny": hook_reason(value)
    case "failed": hook_reason(value)
    case _: False{}

def after_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed after-hook completion"}
    case True{}: Done{M.AfterCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "operation_id", 0n),
      Protocol.number(body, "ticket", 0n), after_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome"))}}

def decode_after(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  after_valid(object_keys(body, ["kind", "task_id", "operation_id", "ticket", "outcome"]) &&
    is_natural(J.get(body, "task_id")) && is_natural(J.get(body, "operation_id")) && is_natural(J.get(body, "ticket")) &&
    valid_after_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome")), body)

def decode_kind(kind: String, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match kind:
    case "command": decode_command(J.get(body, "command"))
    case "ui": decode_ui(body)
    case "model": decode_model(body)
    case "tool": decode_tool(body)
    case "hook": decode_hook(body)
    case "after_hook": decode_after(body)
    case "configure": decode_config(body)
    case "recover": Done{M.Recover{}}
    case "continue": Done{M.Continue{}}
    case _: Fail{"Unknown input envelope"}

def decode(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  decode_kind(J.text(J.get(body, "kind")), body)

def durable(input: M.Input) -> Bool:
  M.durable(input)

def envelope(durable: Bool, decision: M.Decision) -> J.Json:
  View.envelope(durable, decision)
