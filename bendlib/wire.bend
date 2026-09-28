import Base
import ./feature-codec.bend as FeatureCodec
import ./wire-shape.bend as Shape
import ../FEATURES.bend as Features
import ./domain.bend as D
import ../MODEL.bend as M
import ./protocol.bend as Protocol
import ./json.bend as J
import ./schema.bend as Schema
import ./tasks.bend as T
import ./presentation.bend as View
import ../INVARIANTS.bend as I
import ../UI.bend as UI
import ../HOOKS.bend as Hooks
import ../APPROVALS.bend as Approvals
import ../REASONING.bend as Reasoning

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

def approval_outcome(kind: String, +value: J.Json) -> D.ApprovalOutcome:
  match kind:
    case "allow": D.ApprovalAllowed{text_or(J.get(value, "reason"), "")}
    case "deny": D.ApprovalDenied{text_or(J.get(value, "reason"), "")}
    case _: D.ApprovalFailed{text_or(J.get(value, "reason"), "The review did not return a valid decision")}

def construct_command(kind: M.CommandKind, +body: J.Json) -> M.Command:
  match kind:
    case M.FeatureKind{kind}: FeatureCodec.construct(kind, body)
    case M.CreateCommand{}:
      M.Create{J.text(J.get(body, "profile")), text_or(J.get(body, "reasoning"), "default"), J.text(J.get(body, "message")), J.get(body, "settings")}
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
    case M.ReviewApprovalCommand{}: M.ReviewApproval{Protocol.number(body, "task_id", 0n), Protocol.number(body, "operation_id", 0n),
      approval_outcome(J.text(J.get(body, "decision")), body)}

def command_valid(valid: Bool, kind: M.CommandKind, body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Command does not satisfy its declared schema"}
    case True{}: Done{M.UserCommand{construct_command(kind, body)}}

def command_constraints(kind: M.CommandKind, body: J.Json) -> Bool:
  match kind:
    case M.FeatureKind{kind}: FeatureCodec.valid(kind, body)
    case _: True{}

def command_spec(found: Maybe<&2, M.CommandSpec>, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match found:
    case None{}: Fail{"Unknown command; use describe for the executable vocabulary"}
    case Some{M.CommandSpec{name, description, +kind, schema}}:
      command_valid(Schema.valid(schema, body) && command_constraints(kind, body), kind, body)

def decode_command(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  command_spec(find_spec(M.commands(), J.text(J.get(body, "op"))), body)

def item_kind(kind: String, +value: J.Json) -> D.ModelItem:
  match kind:
    case "call": D.Invoke{D.Call{J.text(J.get(value, "id")), J.text(J.get(value, "name")), J.get(value, "arguments")}}
    case "context": D.Context{J.get(value, "value")}
    case _: D.Say{J.text(J.get(value, "text"))}

def model_items(values: +List<J.Json>) -> +List<D.ModelItem>:
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

def model_failure(kind: J.Json, message: String) -> D.Outcome:
  match kind:
    case J.Text{"context_limit"}: D.ContextLimit{}
    case _: D.ModelFailure{message}

def valid_failure_kind(kind: J.Json) -> Bool:
  match kind:
    case J.Null{}: True{}
    case J.Text{"context_limit"}: True{}
    case _: False{}

def model_outcome(ok: Bool, +body: J.Json) -> D.Outcome:
  match ok:
    case True{}: D.ModelReply{model_items(J.items(J.get(body, "items")))}
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
  model_valid(Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "ticket")) &&
    Shape.is_bool(J.get(body, "ok")) && valid_model_payload(J.boolean(J.get(body, "ok")), body), body)

def reasoning_outcome(ok: Bool, +body: J.Json) -> Reasoning.Outcome:
  match ok:
    case True{}: Reasoning.Chosen{J.text(J.get(body, "effort")), Protocol.number(body, "generations", 0n)}
    case False{}: Reasoning.EvaluationFailed{J.text(J.get(body, "message"))}

def reasoning_payload(ok: Bool, +body: J.Json) -> Bool:
  match ok:
    case True{}:
      Shape.object_keys(body, ["kind", "task_id", "ticket", "ok", "effort", "generations"]) &&
        J.is_text(J.get(body, "effort")) && Nat.is_le(J.utf8_length(J.text(J.get(body, "effort"))), 64n) &&
        Shape.is_natural(J.get(body, "generations"))
    case False{}:
      Shape.object_keys(body, ["kind", "task_id", "ticket", "ok", "message"]) && J.is_text(J.get(body, "message")) &&
        Nat.is_le(J.utf8_length(J.text(J.get(body, "message"))), 4096n)

def reasoning_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed reasoning completion"}
    case True{}: Done{M.ReasoningCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
      reasoning_outcome(J.boolean(J.get(body, "ok")), body)}}

def decode_reasoning(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  reasoning_valid(Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "ticket")) &&
    Shape.is_bool(J.get(body, "ok")) && reasoning_payload(J.boolean(J.get(body, "ok")), body), body)

def tool_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed tool completion"}
    case True{}:
      Done{M.ToolCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
        J.get(body, "value"), J.boolean(J.get(body, "error"))}}

def decode_tool(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  tool_valid(Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "ticket")) && Shape.is_bool(J.get(body, "error")), body)

def reasoning_transport(value: String) -> Reasoning.Transport:
  match value:
    case "configuration_update": Reasoning.ConfigurationUpdates{}
    case _: Reasoning.RequestEffort{}

def reasoning_policy(+value: J.Json) -> Reasoning.Policy:
  match value:
    case J.Null{}: Reasoning.Fixed{}
    case other:
      Reasoning.Adaptive{J.text(J.get(value, "evaluator")), Protocol.messages(J.items(J.get(value, "efforts"))),
        J.text(J.get(value, "baseline")), reasoning_transport(J.text(J.get(value, "transport"))), Protocol.number(value, "max_lease", 0n)}

def valid_reasoning_policy(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case other:
      Shape.object_keys(value, ["evaluator", "efforts", "baseline", "transport", "max_lease"]) &&
        is_array(J.get(value, "efforts")) && Shape.is_natural(J.get(value, "max_lease")) &&
        (String.eq(J.text(J.get(value, "transport")), "configuration_update") || String.eq(J.text(J.get(value, "transport")), "request_effort")) &&
        Reasoning.valid(reasoning_policy(value))

def profile_values(values: +List<J.Json>) -> +List<D.Profile>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      D.Profile{J.text(J.get(value, "key")), J.text(J.get(value, "provider")), J.text(J.get(value, "name")),
        reasoning_policy(J.get(value, "adaptive_reasoning"))} <> profile_values(rest)

def valid_profiles(values: +List<J.Json>, +seen: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}:
      +key = J.text(J.get(value, "key"))
      D.nonempty(key) && D.nonempty(J.text(J.get(value, "provider"))) && D.nonempty(J.text(J.get(value, "name"))) &&
        valid_reasoning_policy(J.get(value, "adaptive_reasoning")) && Bool.not(T.has_name(seen, key)) && valid_profiles(rest, key <> seen)

def plugin_ref(+value: J.Json) -> D.PluginRef:
  D.PluginRef{J.text(J.get(value, "name")), J.text(J.get(value, "revision"))}

def source(plugin: J.Json, +value: J.Json) -> D.Source:
  match plugin:
    case J.Null{}: D.Mcp{J.text(J.get(value, "server")), J.text(J.get(value, "remote"))}
    case other: D.Extension{plugin_ref(other), J.text(J.get(value, "remote"))}

def valid_ref(+value: J.Json) -> Bool:
  Shape.object_keys(value, ["name", "revision"]) && J.is_text(J.get(value, "name")) && J.is_text(J.get(value, "revision")) &&
    Hooks.reference_valid(plugin_ref(value))

def valid_route(plugin: J.Json, +value: J.Json) -> Bool:
  match plugin:
    case J.Null{}: String.starts_with(J.text(J.get(value, "name")), "mcp__") && D.nonempty(J.text(J.get(value, "server")))
    case +other: valid_ref(other) && String.eq(J.text(J.get(value, "name")), "plugin__" ++ Hooks.plugin_name(plugin_ref(other)) ++ "__" ++ J.text(J.get(value, "remote")))

def remote_tools(values: +List<J.Json>) -> +List<D.Tool>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      D.Tool{J.text(J.get(value, "name")), J.text(J.get(value, "description")), J.get(value, "schema"),
        source(J.get(value, "plugin"), value)} <> remote_tools(rest)

def valid_remote_tools(values: +List<J.Json>, +seen: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}:
      +name = J.text(J.get(value, "name"))
      D.nonempty(name) && valid_route(J.get(value, "plugin"), value) && Bool.not(T.has_name(seen, name)) &&
        D.nonempty(J.text(J.get(value, "description"))) && J.is_object(J.get(value, "schema")) &&
        D.nonempty(J.text(J.get(value, "remote"))) &&
        valid_remote_tools(rest, name <> seen)

def event_cons(kind: Maybe<&2, D.EventKind>, rest: +List<D.EventKind>) -> +List<D.EventKind>:
  match kind:
    case None{}: rest
    case Some{kind}: kind <> rest

def event_values(values: +List<J.Json>) -> +List<D.EventKind>:
  match values:
    case Nil{}: Nil{}
    case Con{value, rest}: event_cons(D.find_event(D.event_kinds(), J.text(value)), event_values(rest))

def plugin_values(values: +List<J.Json>) -> +List<D.Plugin>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      D.Plugin{plugin_ref(J.get(value, "reference")), J.boolean(J.get(value, "before_tool")),
        J.boolean(J.get(value, "after_tool")),
        event_values(J.items(J.get(value, "events")))} <> plugin_values(rest)

def string_values(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{J.Text{value}, rest}: T.has_name(D.plugin_events(), value) && string_values(rest)
    case _: False{}

def valid_plugin_values(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}:
      Shape.object_keys(value, ["reference", "before_tool", "after_tool", "events"]) && valid_ref(J.get(value, "reference")) &&
        Shape.is_bool(J.get(value, "before_tool")) && Shape.is_bool(J.get(value, "after_tool")) && is_array(J.get(value, "events")) &&
        string_values(J.items(J.get(value, "events"))) && valid_plugin_values(rest)

def valid_plugins(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Array{+values}: valid_plugin_values(values) && Hooks.valid(plugin_values(values))
    case _: False{}

def project(+value: J.Json) -> D.ProjectContext:
  match value:
    case J.Null{}: D.NoProject{}
    case other: D.ProjectContext{J.text(J.get(other, "workspace")), J.text(J.get(other, "revision")), J.text(J.get(other, "instructions"))}

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
      Done{M.Configure{D.Environment{List.append(&2, D.Tool, D.builtins(max_fork), remote_tools(J.items(J.get(body, "tools")))),
        profile_values(J.items(J.get(body, "profiles"))), max_fork, Protocol.number(body, "max_descendants", 0n), project(J.get(body, "project")),
        plugin_values(J.items(J.get(body, "plugins")))}}}

def decode_config(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  config_valid(valid_plugins(J.get(body, "plugins")) && valid_project(J.get(body, "project")) && is_array(J.get(body, "profiles")) && valid_profiles(J.items(J.get(body, "profiles")), Nil{}) &&
    is_array(J.get(body, "tools")) && valid_remote_tools(J.items(J.get(body, "tools")), Nil{}) &&
    Shape.is_natural(J.get(body, "max_fork")) && Nat.is_le(1n, Protocol.number(body, "max_fork", 0n)) &&
    Shape.is_natural(J.get(body, "max_descendants")) && Nat.is_le(1n, Protocol.number(body, "max_descendants", 0n)), body)

# UI cursors are observations, not cached domain state. The wire may name only
# the public event vocabulary; effect completions cannot be smuggled as events.
def optional_id(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case other: Schema.valid(D.task_id_schema(), other)

def view_state(value: J.Json) -> M.ViewState:
  match value:
    case J.Null{}: UI.initial()
    case +other: M.ViewState{J.natural(J.get(other, "selected")), J.natural(J.get(other, "after")), Protocol.number(other, "tasks_after", 0n), J.text(J.get(other, "profile")), FeatureCodec.cursor(other)}

def view_clock(state: M.ViewState, observed: J.Json) -> M.ViewState:
  M.ViewState{selected, after, tasks_after, profile, +board} = state
  M.ViewState{selected, after, tasks_after, profile, FeatureCodec.observe_cursor(board, observed)}

def optional_profile(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case +other: J.is_text(other) && Nat.is_le(J.utf8_length(J.text(other)), 512n)

def valid_view_state(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case +other: Shape.object_keys(other, List.append(&2, String, ["selected", "after", "tasks_after", "profile"], FeatureCodec.cursor_keys())) &&
      optional_id(J.get(other, "selected")) && optional_id(J.get(other, "after")) &&
      Schema.valid(D.task_id_schema(), J.get(other, "tasks_after")) && optional_profile(J.get(other, "profile")) && FeatureCodec.valid_cursor(other)

def ui_event(valid: Bool, state: M.ViewState, event: M.ViewEvent) -> Result<&2, &2, String, M.Input>:
  match valid:
    case True{}: Done{M.UserInterface{state, event}}
    case False{}: Fail{"Malformed presentation event"}

def ui_command(valid: Bool, decoded: Result<&2, &2, String, M.Input>, state: M.ViewState) -> Result<&2, &2, String, M.Input>:
  match valid decoded:
    case True{} Done{M.UserCommand{command}}: Done{M.UserInterface{state, M.Submit{command}}}
    case True{} Fail{reason}: Fail{reason}
    case _ _: Fail{"A presentation can submit only a public command"}

def feature_navigation(decoded: Result<&2, &2, String, Features.Navigation>, state: M.ViewState) -> Result<&2, &2, String, M.Input>:
  match decoded:
    case Fail{reason}: Fail{reason}
    case Done{event}: Done{M.UserInterface{state, M.FeatureEvent{event}}}

def view_event(kind: String, +event: J.Json, state: M.ViewState) -> Result<&2, &2, String, M.Input>:
  match kind:
    case "refresh": ui_event(Shape.object_keys(event, ["type"]), state, M.RefreshView{})
    case "select": ui_event(Shape.object_keys(event, ["type", "task_id"]) && optional_id(J.get(event, "task_id")),
      state, M.SelectTask{J.natural(J.get(event, "task_id"))})
    case "history": ui_event(Shape.object_keys(event, ["type", "after"]) && optional_id(J.get(event, "after")),
      state, M.HistoryPage{J.natural(J.get(event, "after"))})
    case "tasks": ui_event(Shape.object_keys(event, ["type", "after"]) && Schema.valid(D.task_id_schema(), J.get(event, "after")),
      state, M.TaskPage{Protocol.number(event, "after", 0n)})
    case "profile": ui_event(Shape.object_keys(event, ["type", "profile"]) && J.is_text(J.get(event, "profile")) && optional_profile(J.get(event, "profile")),
      state, M.SelectProfile{J.text(J.get(event, "profile"))})
    case "submit": ui_command(Shape.object_keys(event, ["type", "command"]), decode_command(J.get(event, "command")), state)
    case other: feature_navigation(FeatureCodec.navigation(other, event), state)

def ui_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed presentation cursor"}
    case True{}: view_event(J.text(J.get(J.get(body, "event"), "type")), J.get(body, "event"), view_clock(view_state(J.get(body, "state")), J.get(body, "observed_at")))

def decode_ui(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  ui_valid(valid_view_state(J.get(body, "state")) && FeatureCodec.valid_clock(J.get(body, "observed_at")), body)

def hook_outcome(kind: String, +value: J.Json) -> D.HookOutcome:
  match kind:
    case "allow": D.AllowTool{}
    case "rewrite": D.RewriteTool{J.get(value, "arguments")}
    case "deny": D.DenyTool{J.text(J.get(value, "reason"))}
    case _: D.HookFailure{J.text(J.get(value, "reason"))}

def hook_reason(+value: J.Json) -> Bool:
  Shape.object_keys(value, ["decision", "reason"]) && D.nonempty(J.text(J.get(value, "reason"))) &&
    Nat.is_le(J.utf8_length(J.text(J.get(value, "reason"))), 4096n)

def valid_hook_outcome(kind: String, +value: J.Json) -> Bool:
  match kind:
    case "allow": Shape.object_keys(value, ["decision"])
    case "rewrite": Shape.object_keys(value, ["decision", "arguments"]) && J.is_object(J.get(value, "arguments"))
    case "deny": hook_reason(value)
    case "failed": hook_reason(value)
    case _: False{}

def hook_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed hook completion"}
    case True{}: Done{M.HookCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
      hook_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome"))}}

def decode_hook(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  hook_valid(Shape.object_keys(body, ["kind", "task_id", "ticket", "outcome"]) && Shape.is_natural(J.get(body, "task_id")) &&
    Shape.is_natural(J.get(body, "ticket")) && valid_hook_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome")), body)

def after_outcome(kind: String, +value: J.Json) -> D.AfterOutcome:
  match kind:
    case "allow": D.KeepResult{}
    case "rewrite": D.RewriteResult{J.get(value, "value")}
    case "deny": D.DenyResult{J.text(J.get(value, "reason"))}
    case _: D.AfterFailure{J.text(J.get(value, "reason"))}

def valid_after_outcome(kind: String, +value: J.Json) -> Bool:
  match kind:
    case "allow": Shape.object_keys(value, ["decision"])
    case "rewrite": Shape.object_keys(value, ["decision", "value"])
    case "deny": hook_reason(value)
    case "failed": hook_reason(value)
    case _: False{}

def after_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed after-hook completion"}
    case True{}: Done{M.AfterCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "operation_id", 0n),
      Protocol.number(body, "ticket", 0n), after_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome"))}}

def decode_after(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  after_valid(Shape.object_keys(body, ["kind", "task_id", "operation_id", "ticket", "outcome"]) &&
    Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "operation_id")) && Shape.is_natural(J.get(body, "ticket")) &&
    valid_after_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome")), body)

def approval_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed approval completion envelope"}
    case True{}: Done{M.ApprovalCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
      approval_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome"))}}

def approval_reply(+outcome: J.Json) -> Bool:
  Shape.object_keys(outcome, ["decision", "reason"]) && D.nonempty(J.text(J.get(outcome, "reason"))) &&
    Approvals.bounded(J.text(J.get(outcome, "reason"))) &&
    (String.eq(J.text(J.get(outcome, "decision")), "allow") || String.eq(J.text(J.get(outcome, "decision")), "deny") ||
      String.eq(J.text(J.get(outcome, "decision")), "failed"))

def decode_approval(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  approval_valid(Shape.object_keys(body, ["kind", "task_id", "ticket", "outcome"]) &&
    Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "ticket")) && approval_reply(J.get(body, "outcome")), body)

def feature_completion(decoded: Result<&2, &2, String, Features.Completion>) -> Result<&2, &2, String, M.Input>:
  match decoded:
    case Fail{reason}: Fail{reason}
    case Done{completion}: Done{M.FeatureCompleted{completion}}

def decode_kind(kind: String, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match kind:
    case "command": decode_command(J.get(body, "command"))
    case "ui": decode_ui(body)
    case "model": decode_model(body)
    case "reasoning": decode_reasoning(body)
    case "tool": decode_tool(body)
    case "hook": decode_hook(body)
    case "after_hook": decode_after(body)
    case "approval": decode_approval(body)
    case "configure": decode_config(body)
    case "recover": Done{M.Recover{}}
    case "continue": Done{M.Continue{}}
    case other: feature_completion(FeatureCodec.completion(other, body))

def decode(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  decode_kind(J.text(J.get(body, "kind")), body)

def durable(input: M.Input) -> Bool:
  M.durable(input)

def envelope(durable: Bool, decision: M.Decision()) -> J.Json:
  View.envelope(durable, decision)
