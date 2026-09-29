import Base
import ./feature-codec.bend as FeatureCodec
import ../FEATURES.bend as Features
import ./domain.bend as D
import ../MODEL.bend as M
import ./json.bend as J
import ./tasks.bend as T

# The native command and event wire representation shared by all presentations.
# No renderer recreates command shapes or endpoint-specific transitions.
def compact_json(id: Nat, summary: Maybe<&2, String>) -> J.Json:
  match summary:
    case None{}: J.Object{[J.Field{"op", J.Text{"compact"}}, J.Field{"task_id", J.nat(id)}]}
    case Some{text}: J.Object{[J.Field{"op", J.Text{"compact"}}, J.Field{"task_id", J.nat(id)}, J.Field{"summary", J.Text{text}}]}

def optional_field(name: String, value: J.Json, fields: +List<J.Field>) -> +List<J.Field>:
  match value:
    case J.Null{}: fields
    case value: J.Field{name, value} <> fields

def command_json(command: M.Command) -> J.Json:
  match command:
    case M.FeatureCommand{command}: FeatureCodec.command_json(command)
    case M.Observe{M.FeatureQuery{query}}: FeatureCodec.query_json(query)
    case M.Create{profile, reasoning, message, options}:
      J.Object{optional_field("settings", options, [J.Field{"op", J.Text{"create"}}, J.Field{"profile", J.Text{profile}},
        J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", J.Text{message}}])}
    case M.Send{id, message}:
      J.Object{[J.Field{"op", J.Text{"send"}}, J.Field{"task_id", J.nat(id)}, J.Field{"message", J.Text{message}}]}
    case M.Steer{id, message}:
      J.Object{[J.Field{"op", J.Text{"steer"}}, J.Field{"task_id", J.nat(id)}, J.Field{"message", J.Text{message}}]}
    case M.Cancel{id, operation}:
      J.Object{[J.Field{"op", J.Text{"cancel_operation"}}, J.Field{"task_id", J.nat(id)}, J.Field{"operation_id", J.nat(operation)}]}
    case M.ChangeStatus{id, control}:
      J.Object{[J.Field{"op", J.Text{D.control_name(control)}}, J.Field{"task_id", J.nat(id)}]}
    case M.Fork{id, count, messages, options}:
      J.Object{optional_field("settings", options, [J.Field{"op", J.Text{"fork"}}, J.Field{"task_id", J.nat(id)}, J.Field{"child_count", J.nat(count)},
        J.Field{"messages", J.Array{T.strings_json(messages)}}])}
    case M.Compact{id, summary}: compact_json(id, summary)
    case M.Observe{M.Read{id, after, limit}}:
      J.Object{[J.Field{"op", J.Text{"read"}}, J.Field{"task_id", J.nat(id)}, J.Field{"after", J.nat(after)}, J.Field{"limit", J.nat(limit)}]}
    case M.Observe{M.ListTasks{}}: J.Object{[J.Field{"op", J.Text{"list"}}]}
    case M.Observe{M.Describe{}}: J.Object{[J.Field{"op", J.Text{"describe"}}]}
    case M.Observe{M.ListProjects{}}: J.Object{[J.Field{"op", J.Text{"list_projects"}}]}
    case M.Observe{M.ReadProject{id}}: J.Object{[J.Field{"op", J.Text{"read_project"}}, J.Field{"project_id", J.nat(id)}]}
    case M.CreateProject{name, workspace, guidance}:
      J.Object{optional_field("guidance", guidance, [J.Field{"op", J.Text{"create_project"}}, J.Field{"name", J.Text{name}},
        J.Field{"workspace", workspace}])}
    case M.UpdateProject{id, name, workspace, guidance}:
      J.Object{optional_field("guidance", guidance, optional_field("workspace", workspace,
        optional_field("name", D.optional_string(name), [J.Field{"op", J.Text{"update_project"}}, J.Field{"project_id", J.nat(id)}])))}
    case M.DeleteProject{id}: J.Object{[J.Field{"op", J.Text{"delete_project"}}, J.Field{"project_id", J.nat(id)}]}
    case M.ReviewApproval{id, operation, +outcome}:
      J.Object{[J.Field{"op", J.Text{"review_approval"}}, J.Field{"task_id", J.nat(id)}, J.Field{"operation_id", J.nat(operation)},
        J.Field{"decision", J.Text{D.approval_decision(outcome)}}, J.Field{"reason", J.Text{D.approval_reason(outcome)}}]}
