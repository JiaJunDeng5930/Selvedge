import Base
import ../context/MODEL.bend as Context
import ../context/KINDS.bend as ContextKinds
import ../tools/MODEL.bend as Tools
import ../../bendlib/categories.bend as Categories
import ../features/CODEC.bend as FeatureCodec
import ./wire-shape.bend as Shape
import ../workspace/WORKSPACE.bend as Workspace
import ../features/MODEL.bend as Features
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../protocol/PROGRAM.bend as Protocol
import ../../bendlib/json.bend as J
import ./schema.bend as Schema
import ./presentation.bend as View
import ../INVARIANTS.bend as I
import ../approval/HOOKS.bend as Hooks
import ../approval/MODEL.bend as Approvals
import ../reasoning/MODEL.bend as Reasoning

def choose_spec(same: Bool, spec: M.CommandSpec, rest: Maybe<&2, M.CommandSpec>) -> Maybe<&2, M.CommandSpec>:
  match same:
    case True{}: Some{spec}
    case False{}: rest

def find_spec(specs: +List<M.CommandSpec>, +name: String) -> Maybe<&2, M.CommandSpec>:
  match specs:
    case Nil{}: None{}
    case Con{M.CommandSpec{+key, +description, +kind, +schema}, rest}:
      choose_spec(String.eq(key, name), M.CommandSpec{key, description, kind, schema}, find_spec(rest, name))

def approval_outcome(kind: String, +value: J.Json) -> D.ApprovalOutcome:
  match kind:
    case "allow": D.ApprovalAllowed{J.text_or(J.get(value, "reason"), "")}
    case "deny": D.ApprovalDenied{J.text_or(J.get(value, "reason"), "")}
    case _: D.ApprovalFailed{J.text_or(J.get(value, "reason"), "The review did not return a valid decision")}

def execution_sandbox(read_only: Bool, network: Bool) -> D.Sandbox:
  match read_only:
    case True{}: D.Sandbox{D.ReadOnly{}, network}
    case False{}: D.Sandbox{D.WorkspaceWrite{}, network}

def execution_approval(mode: String, key: String) -> D.ApprovalPolicy:
  match mode:
    case "full-access": D.FullAccess{}
    case "ask-for-approval": D.AskForApproval{}
    case _: D.ApprovalForMe{D.Profile{key, "", "", Reasoning.Fixed{}, None{}}}

def construct_command(kind: M.CommandKind, +body: J.Json) -> M.Command:
  match kind:
    case M.ConfigureTaskExecutionCommand{}:
      M.ConfigureTaskExecution{Protocol.number(body, "task_id", 0n), J.text(J.get(body, "profile")), J.text(J.get(body, "reasoning")),
        execution_sandbox(String.eq(J.text(J.get(J.get(body, "sandbox"), "mode")), "read-only"), J.boolean(J.get(J.get(body, "sandbox"), "network_access"))),
        execution_approval(J.text(J.get(J.get(body, "approval"), "mode")), J.text_or(J.get(J.get(body, "approval"), "reviewer_profile"), J.text(J.get(body, "profile"))))}
    case M.FeatureKind{kind}: FeatureCodec.construct(kind, body)
    case M.CreateCommand{}:
      M.Create{J.text(J.get(body, "profile")), J.text_or(J.get(body, "reasoning"), "default"), J.text(J.get(body, "message")), J.get(body, "settings")}
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
        J.text_values(J.items(J.get(body, "messages"))), J.get(body, "settings")}
    case M.ReadCommand{}:
      M.Observe{M.Read{Protocol.number(body, "task_id", 0n), Protocol.number(body, "after", 0n), Protocol.number(body, "limit", 100n)}}
    case M.ListCommand{}: M.Observe{M.ListTasks{}}
    case M.CompactCommand{}: M.Compact{Protocol.number(body, "task_id", 0n), J.optional_text(J.get(body, "summary"))}
    case M.DescribeCommand{}: M.Observe{M.Describe{}}
    case M.CreateProjectCommand{}:
      M.CreateProject{J.text(J.get(body, "name")), J.get(body, "workspace"), J.get(body, "guidance")}
    case M.UpdateProjectCommand{}:
      M.UpdateProject{Protocol.number(body, "project_id", 0n), J.optional_text(J.get(body, "name")), J.get(body, "workspace"), J.get(body, "guidance")}
    case M.DeleteProjectCommand{}: M.DeleteProject{Protocol.number(body, "project_id", 0n)}
    case M.ListProjectsCommand{}: M.Observe{M.ListProjects{}}
    case M.ReadProjectCommand{}: M.Observe{M.ReadProject{Protocol.number(body, "project_id", 0n)}}
    case M.ReviewApprovalCommand{}: M.ReviewApproval{Protocol.number(body, "task_id", 0n), Protocol.number(body, "operation_id", 0n),
      approval_outcome(J.text(J.get(body, "decision")), body)}

def command_constraints(kind: M.CommandKind, +body: J.Json) -> Bool:
  match kind:
    case M.ConfigureTaskExecutionCommand{}:
      ((String.eq(J.text(J.get(J.get(body, "sandbox"), "mode")), "workspace-write")) || (String.eq(J.text(J.get(J.get(body, "sandbox"), "mode")), "read-only"))) &&
        Shape.is_bool(J.get(J.get(body, "sandbox"), "network_access")) &&
        ((String.eq(J.text(J.get(J.get(body, "approval"), "mode")), "full-access")) || (String.eq(J.text(J.get(J.get(body, "approval"), "mode")), "ask-for-approval")) || (String.eq(J.text(J.get(J.get(body, "approval"), "mode")), "approval-for-me")))
    case M.FeatureKind{kind}: FeatureCodec.valid(kind, body)
    case _: True{}

def command_payload(+schema: J.Json, +kind: M.CommandKind, +body: J.Json) -> Bool:
  Schema.valid(schema, body) && command_constraints(kind, body)

def command_accepted(+schema: J.Json, +kind: M.CommandKind,
  member: Categories.Membership<J.Json, Categories.holds(J.Json, (body => command_payload(schema, kind, body)))>) -> Result<&2, &2, String, M.Input>:
  Categories.Membership{body, evidence} = member
  Done{M.UserCommand{construct_command(kind, body)}}

def command_admission(+schema: J.Json, +kind: M.CommandKind,
  admission: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (body => command_payload(schema, kind, body)))>>) -> Result<&2, &2, String, M.Input>:
  match admission:
    case None{}: Fail{"Command does not satisfy its declared schema"}
    case Some{member}: command_accepted(schema, kind, member)



def command_spec(found: Maybe<&2, M.CommandSpec>, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match found:
    case None{}: Fail{"Unknown command; use describe for the executable vocabulary"}
    case Some{M.CommandSpec{name, description, +kind, +schema}}:
      command_admission(schema, kind, Categories.admit(J.Json, (body => command_payload(schema, kind, body)), body))

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

def context_payload(ok: Bool, +body: J.Json) -> Bool:
  match ok:
    case True{}:
      Shape.object_keys(body, ["kind", "task_id", "ticket", "ok", "observations"])
    case False{}:
      Shape.object_keys(body, ["kind", "task_id", "ticket", "ok", "message"]) && J.is_text(J.get(body, "message")) &&
        Nat.is_le(J.utf8_length(J.text(J.get(body, "message"))), 4096n)

def context_completion_payload(+body: J.Json) -> Bool:
  Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "ticket")) && Shape.is_bool(J.get(body, "ok")) &&
    context_payload(J.boolean(J.get(body, "ok")), body)

def parsed_context_input(id: Nat, ticket: Nat, parsed: Maybe<&2, +List<D.ContextObservation()>>) -> Result<&2, &2, String, M.Input>:
  match parsed:
    case Some{items}: Done{M.ContextObserved{id, ticket, Done{items}}}
    case None{}: Fail{"Malformed context observation"}

def context_input(ok: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match ok:
    case False{}: Done{M.ContextObserved{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n), Fail{J.text(J.get(body, "message"))}}}
    case True{}: parsed_context_input(Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
      Context.observations(ContextKinds.definitions(), J.get(body, "observations")))

def context_envelope(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed context completion"}
    case True{}: context_input(J.boolean(J.get(body, "ok")), body)

def decode_context(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  context_envelope(context_completion_payload(body), body)

def model_outcome(ok: Bool, +body: J.Json) -> D.Outcome:
  match ok:
    case True{}: D.ModelReply{model_items(J.items(J.get(body, "items")))}
    case False{}: model_failure(J.get(body, "failure_kind"), J.text(J.get(body, "message")))

def valid_model_payload(ok: Bool, +body: J.Json) -> Bool:
  match ok:
    case True{}: is_array(J.get(body, "items")) && valid_items(J.items(J.get(body, "items")))
    case False{}: J.is_text(J.get(body, "message")) && valid_failure_kind(J.get(body, "failure_kind"))

def model_payload(+body: J.Json) -> Bool:
  Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "ticket")) &&
    Shape.is_bool(J.get(body, "ok")) && valid_model_payload(J.boolean(J.get(body, "ok")), body)

def model_accepted(member: Categories.Membership<J.Json, Categories.holds(J.Json, (value => model_payload(value)))>) -> Result<&2, &2, String, M.Input>:
  Categories.Membership{+body, evidence} = member
  Done{M.ModelCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
    model_outcome(J.boolean(J.get(body, "ok")), body)}}

def model_admission(admission: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (value => model_payload(value)))>>) -> Result<&2, &2, String, M.Input>:
  match admission:
    case None{}: Fail{"Malformed model completion"}
    case Some{member}: model_accepted(member)

def decode_model(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  model_admission(Categories.admit(J.Json, (value => model_payload(value)), body))

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

def reasoning_completion_payload(+body: J.Json) -> Bool:
  Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "ticket")) &&
    Shape.is_bool(J.get(body, "ok")) && reasoning_payload(J.boolean(J.get(body, "ok")), body)

def reasoning_accepted(member: Categories.Membership<J.Json, Categories.holds(J.Json, (value => reasoning_completion_payload(value)))>) -> Result<&2, &2, String, M.Input>:
  Categories.Membership{+body, evidence} = member
  Done{M.ReasoningCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
  reasoning_outcome(J.boolean(J.get(body, "ok")), body)}}

def reasoning_admission(admission: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (value => reasoning_completion_payload(value)))>>) -> Result<&2, &2, String, M.Input>:
  match admission:
    case None{}: Fail{"Malformed reasoning completion"}
    case Some{member}: reasoning_accepted(member)

def decode_reasoning(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  reasoning_admission(Categories.admit(J.Json, (value => reasoning_completion_payload(value)), body))

def tool_payload(+body: J.Json) -> Bool:
  Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "ticket")) && Shape.is_bool(J.get(body, "error"))

def tool_accepted(member: Categories.Membership<J.Json, Categories.holds(J.Json, (value => tool_payload(value)))>) -> Result<&2, &2, String, M.Input>:
  Categories.Membership{+body, evidence} = member
  Done{M.ToolCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
    J.get(body, "value"), J.boolean(J.get(body, "error"))}}

def tool_admission(admission: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (value => tool_payload(value)))>>) -> Result<&2, &2, String, M.Input>:
  match admission:
    case None{}: Fail{"Malformed tool completion"}
    case Some{member}: tool_accepted(member)

def decode_tool(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  tool_admission(Categories.admit(J.Json, (value => tool_payload(value)), body))

def reasoning_transport(value: String) -> Reasoning.Transport:
  match value:
    case "configuration_update": Reasoning.ConfigurationUpdates{}
    case _: Reasoning.RequestEffort{}

def reasoning_policy(+value: J.Json) -> Reasoning.Policy:
  match value:
    case J.Null{}: Reasoning.Fixed{}
    case other:
      Reasoning.Adaptive{J.text(J.get(value, "evaluator")), J.text_values(J.items(J.get(value, "efforts"))),
        J.text(J.get(value, "baseline")), reasoning_transport(J.text(J.get(value, "transport"))), Protocol.number(value, "max_lease", 0n)}

def valid_reasoning_policy(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case other:
      Shape.object_keys(value, ["evaluator", "efforts", "baseline", "transport", "max_lease"]) &&
        is_array(J.get(value, "efforts")) && Shape.is_natural(J.get(value, "max_lease")) &&
        (String.eq(J.text(J.get(value, "transport")), "configuration_update") || String.eq(J.text(J.get(value, "transport")), "request_effort")) &&
        Reasoning.valid(reasoning_policy(value))

def requested_reasoning_default(value: J.Json) -> Maybe<&2, String>:
  match value:
    case J.Text{text}: Some{text}
    case _: None{}

def reasoning_options(+value: J.Json) -> Maybe<&2, D.ReasoningOptions>:
  match value:
    case J.Null{}: None{}
    case other: D.normalize_reasoning_options(J.text_values(J.items(J.get(other, "values"))), requested_reasoning_default(J.get(other, "default")))

def valid_reasoning_values(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{J.Text{+value}, rest}: D.nonempty(value) && Bool.not(String.eq(value, "auto")) && valid_reasoning_values(rest)
    case _: False{}

def valid_reasoning_default(value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case J.Text{text}: True{}
    case _: False{}

def valid_reasoning_options(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case other:
      Shape.object_keys(other, ["default", "values"]) && valid_reasoning_default(J.get(other, "default")) &&
        is_array(J.get(other, "values")) && Nat.is_lt(0n, List.length(&2, J.Json, J.items(J.get(other, "values")))) && valid_reasoning_values(J.items(J.get(other, "values")))

def profile_values(values: +List<J.Json>) -> +List<D.Profile>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      D.Profile{J.text(J.get(value, "key")), J.text(J.get(value, "provider")), J.text(J.get(value, "name")),
        reasoning_policy(J.get(value, "adaptive_reasoning")), reasoning_options(J.get(value, "reasoning_options"))} <> profile_values(rest)

def profile_options_present(value: J.Json) -> Bool:
  match value:
    case J.Object{fields}: Schema.exists(fields, "reasoning_options")
    case _: False{}

def valid_profiles(values: +List<J.Json>, +seen: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}:
      +key = J.text(J.get(value, "key"))
      D.nonempty(key) && D.nonempty(J.text(J.get(value, "provider"))) && D.nonempty(J.text(J.get(value, "name"))) &&
        profile_options_present(value) && valid_reasoning_options(J.get(value, "reasoning_options")) && D.policy_options_valid(reasoning_policy(J.get(value, "adaptive_reasoning")), reasoning_options(J.get(value, "reasoning_options"))) && valid_reasoning_policy(J.get(value, "adaptive_reasoning")) && Bool.not(Schema.contains(seen, key)) && valid_profiles(rest, key <> seen)

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
      D.nonempty(name) && valid_route(J.get(value, "plugin"), value) && Bool.not(Schema.contains(seen, name)) &&
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
    case Con{J.Text{value}, rest}: Schema.contains(D.plugin_events(), value) && string_values(rest)
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

def instruction_snapshot(+value: J.Json) -> Maybe<&2, D.InstructionSnapshot>:
  match value:
    case J.Null{}: None{}
    case other: Some{D.InstructionSnapshot{J.text(J.get(other, "path")), J.text(J.get(other, "revision")), J.text(J.get(other, "content"))}}

def initial_instructions(+value: J.Json) -> D.InitialInstructions:
  D.InitialInstructions{J.text(J.get(value, "configured")), instruction_snapshot(J.get(value, "global"))}

def valid_instruction_snapshot(+value: J.Json) -> Bool:
  match value:
    case J.Null{}: True{}
    case other:
      Shape.object_keys(other, ["path", "revision", "content"]) && J.is_text(J.get(other, "path")) &&
        Workspace.valid_path(J.text(J.get(other, "path"))) && J.is_text(J.get(other, "revision")) &&
        Nat.is_eq(J.utf8_length(J.text(J.get(other, "revision"))), 64n) && J.is_text(J.get(other, "content")) &&
        Nat.is_le(J.utf8_length(J.text(J.get(other, "content"))), D.project_limit())

def valid_initial_instructions(+value: J.Json) -> Bool:
  Shape.object_keys(value, ["configured", "global"]) && J.is_text(J.get(value, "configured")) &&
    Nat.is_le(J.utf8_length(J.text(J.get(value, "configured"))), D.project_limit()) && valid_instruction_snapshot(J.get(value, "global"))

def config_payload(+body: J.Json) -> Bool:
  valid_initial_instructions(J.get(body, "instructions")) && valid_plugins(J.get(body, "plugins")) && valid_project(J.get(body, "project")) && is_array(J.get(body, "profiles")) && valid_profiles(J.items(J.get(body, "profiles")), Nil{}) &&
    is_array(J.get(body, "tools")) && valid_remote_tools(J.items(J.get(body, "tools")), Nil{}) &&
    Shape.is_natural(J.get(body, "max_fork")) && Nat.is_le(1n, Protocol.number(body, "max_fork", 0n)) &&
    Nat.is_le(Protocol.number(body, "max_fork", 0n), U32.to_nat(4294967295)) &&
    Shape.is_natural(J.get(body, "max_descendants")) && Nat.is_le(1n, Protocol.number(body, "max_descendants", 0n))

def config_accepted(member: Categories.Membership<J.Json, Categories.holds(J.Json, (value => config_payload(value)))>) -> Result<&2, &2, String, M.Input>:
  Categories.Membership{+body, evidence} = member
  +max_fork = Protocol.number(body, "max_fork", 0n)
  Done{M.Configure{D.Environment{List.append(&2, D.Tool, Tools.catalog(max_fork),
      List.append(&2, D.Tool, Features.native_catalog(D.task_settings_schema()), remote_tools(J.items(J.get(body, "tools"))))),
    profile_values(J.items(J.get(body, "profiles"))), max_fork, Protocol.number(body, "max_descendants", 0n), project(J.get(body, "project")),
    plugin_values(J.items(J.get(body, "plugins"))), initial_instructions(J.get(body, "instructions"))}}}

def config_admission(admission: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (value => config_payload(value)))>>) -> Result<&2, &2, String, M.Input>:
  match admission:
    case None{}: Fail{"Malformed environment: profiles/routes must be unique and limits must be positive integers"}
    case Some{member}: config_accepted(member)

def decode_config(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  config_admission(Categories.admit(J.Json, (value => config_payload(value)), body))

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

def hook_payload(+body: J.Json) -> Bool:
  Shape.object_keys(body, ["kind", "task_id", "ticket", "outcome"]) && Shape.is_natural(J.get(body, "task_id")) &&
    Shape.is_natural(J.get(body, "ticket")) && valid_hook_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome"))

def hook_accepted(member: Categories.Membership<J.Json, Categories.holds(J.Json, (value => hook_payload(value)))>) -> Result<&2, &2, String, M.Input>:
  Categories.Membership{+body, evidence} = member
  Done{M.HookCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
  hook_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome"))}}

def hook_admission(admission: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (value => hook_payload(value)))>>) -> Result<&2, &2, String, M.Input>:
  match admission:
    case None{}: Fail{"Malformed hook completion"}
    case Some{member}: hook_accepted(member)

def decode_hook(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  hook_admission(Categories.admit(J.Json, (value => hook_payload(value)), body))

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

def after_payload(+body: J.Json) -> Bool:
  Shape.object_keys(body, ["kind", "task_id", "operation_id", "ticket", "outcome"]) &&
    Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "operation_id")) && Shape.is_natural(J.get(body, "ticket")) &&
    valid_after_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome"))

def after_accepted(member: Categories.Membership<J.Json, Categories.holds(J.Json, (value => after_payload(value)))>) -> Result<&2, &2, String, M.Input>:
  Categories.Membership{+body, evidence} = member
  Done{M.AfterCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "operation_id", 0n),
  Protocol.number(body, "ticket", 0n), after_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome"))}}

def after_admission(admission: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (value => after_payload(value)))>>) -> Result<&2, &2, String, M.Input>:
  match admission:
    case None{}: Fail{"Malformed after-hook completion"}
    case Some{member}: after_accepted(member)

def decode_after(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  after_admission(Categories.admit(J.Json, (value => after_payload(value)), body))

def approval_reply(+outcome: J.Json) -> Bool:
  Shape.object_keys(outcome, ["decision", "reason"]) && D.nonempty(J.text(J.get(outcome, "reason"))) &&
    Approvals.bounded(J.text(J.get(outcome, "reason"))) &&
    (String.eq(J.text(J.get(outcome, "decision")), "allow") || String.eq(J.text(J.get(outcome, "decision")), "deny") ||
      String.eq(J.text(J.get(outcome, "decision")), "failed"))

def approval_payload(+body: J.Json) -> Bool:
  Shape.object_keys(body, ["kind", "task_id", "ticket", "outcome"]) &&
    Shape.is_natural(J.get(body, "task_id")) && Shape.is_natural(J.get(body, "ticket")) && approval_reply(J.get(body, "outcome"))

def approval_accepted(member: Categories.Membership<J.Json, Categories.holds(J.Json, (value => approval_payload(value)))>) -> Result<&2, &2, String, M.Input>:
  Categories.Membership{+body, evidence} = member
  Done{M.ApprovalCompleted{Protocol.number(body, "task_id", 0n), Protocol.number(body, "ticket", 0n),
  approval_outcome(J.text(J.get(J.get(body, "outcome"), "decision")), J.get(body, "outcome"))}}

def approval_admission(admission: Maybe<&1, Categories.Membership<J.Json, Categories.holds(J.Json, (value => approval_payload(value)))>>) -> Result<&2, &2, String, M.Input>:
  match admission:
    case None{}: Fail{"Malformed approval completion envelope"}
    case Some{member}: approval_accepted(member)



def decode_approval(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  approval_admission(Categories.admit(J.Json, (value => approval_payload(value)), body))

def feature_completion(decoded: Result<&2, &2, String, Features.Completion>) -> Result<&2, &2, String, M.Input>:
  match decoded:
    case Fail{reason}: Fail{reason}
    case Done{completion}: Done{M.FeatureCompleted{completion}}

def decode_kind(kind: String, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match kind:
    case "command": decode_command(J.get(body, "command"))
    case "context_observed": decode_context(body)
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
