import Base
import ./TYPES.bend as UI
import ../../bendlib/json.bend as J
import ../../features/task_graph/MODEL.bend as Graph
import ../../harness/MODEL.bend as Harness
import ../../harness/COMMANDS.bend as Commands
import ../../harness/DOMAIN.bend as Domain
import ../../harness/features/graph-state.bend as GraphState
import ../../harness/tasks/PROGRAM.bend as Tasks
import ../../harness/conversation/PROGRAM.bend as Conversation

# Registered live sources observe topology and tasks from this one World value.
# Native identities and journal sequences have one stable exact String type.
def observed_nat( +value: Nat) -> J.Json:
  J.Text{Nat.show(value)}

def node_identity( +graph: Nat, +key: String, +task: Nat) -> String:
  "[\"task-graph-node\"," ++ J.quote(Nat.show(graph)) ++ "," ++ J.quote(key) ++ "," ++ J.quote(Nat.show(task)) ++ "]"

def phase_name( +phase: Domain.Phase) -> String:
  match phase:
    case Domain.Idle{}: "idle"
    case Domain.Ready{calls}: "ready"
    case Domain.ModelPending{ticket, callable, mode}: "model_pending"
    case Domain.ContextPending{ticket, revision, purpose}: "context_pending"
    case Domain.ReasoningPending{ticket, revision}: "reasoning_pending"
    case Domain.HookPending{ticket, plugin, call, pending, remaining}: "hook_pending"

def human_reviewer( +reviewer: Domain.ApprovalReviewer) -> Bool:
  match reviewer:
    case Domain.HumanReviewer{}: True{}
    case _: False{}

def operation_human( +stage: Domain.OperationStage) -> Bool:
  match stage:
    case Domain.ApprovalPending{reviewer}: human_reviewer(reviewer)
    case _: False{}

def awaiting_human( +operations: +List<Domain.Operation()>) -> Bool:
  match operations:
    case Nil{}: False{}
    case Con{(id, Domain.OperationBody{call, announced, stage}), rest}: operation_human(stage) || awaiting_human(rest)

def stage_name( +stage: Domain.OperationStage) -> String:
  match stage:
    case Domain.Executing{}: "executing"
    case Domain.ApprovalPending{reviewer}: "approval_pending"
    case Domain.ApprovalGranted{reviewer}: "approval_granted"
    case Domain.ElevatedExecuting{ticket, reviewer}: "elevated_executing"
    case Domain.ResultPending{ticket, plugin, pending, value, error}: "result_pending"

def operations( +values: +List<Domain.Operation()>) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{(id, Domain.OperationBody{Domain.Call{call_id, name, arguments}, announced, +stage}), rest}:
      J.Object{[J.Field{"id", observed_nat(id)}, J.Field{"name", J.Text{name}}, J.Field{"stage", J.Text{stage_name(stage)}}, J.Field{"awaitingHuman", J.Boolean{operation_human(stage)}}]} <> operations(rest)

def task_value( +found: Maybe<&2, Domain.Task>) -> J.Json:
  match found:
    case None{}: J.Null{}
    case Some{+task}:
      J.Object{[J.Field{"id", observed_nat(Domain.task_id(task))},
        J.Field{"title", J.Text{Conversation.title(task)}},
        J.Field{"control", J.Text{Domain.status_name(Domain.task_status(task))}},
        J.Field{"phase", J.Text{phase_name(Domain.task_phase(task))}},
        J.Field{"working", J.Boolean{Conversation.working(Domain.task_phase(task), Domain.task_operations(task))}},
        J.Field{"awaitingHuman", J.Boolean{awaiting_human(Domain.task_operations(task))}},
        J.Field{"pendingMessages", J.nat(List.length(&2, String, Domain.task_queue(task)))},
        J.Field{"operations", J.Array{operations(Domain.task_operations(task))}},
        J.Field{"statusLabel", J.Text{Conversation.status(task)}}]}

def nodes( +values: +List<Graph.ResolvedNode>, +graph: Nat, +world: Harness.World()) -> +List<J.Json>:
  match values:
    case Nil{}: Nil{}
    case Con{Graph.ResolvedNode{+key, +task}, rest}:
      J.Object{[J.Field{"identity", J.Text{node_identity(graph, key, task)}}, J.Field{"key", J.Text{key}},
        J.Field{"taskId", observed_nat(task)}, J.Field{"task", task_value(Tasks.find(Commands.entries(world), task))}]} <> nodes(rest, graph, world)

def resolved_identity( +found: Maybe<&2, Nat>, +graph: Nat, +key: String) -> String:
  match found:
    case None{}: ""
    case Some{task}: node_identity(graph, key, task)

def action_kind( +value: Graph.Message) -> String:
  match value:
    case Graph.Output{}: "output"
    case Graph.Literal{value}: "literal"
    case Graph.Concat{parts}: "concat"

def action_edges( +actions: +List<Graph.Action>, +graph: Nat, +rule: String, +source: String, +resolved: +List<Graph.ResolvedNode>, +ordinal: Nat) -> +List<J.Json>:
  match actions:
    case Nil{}: Nil{}
    case Con{Graph.Action{+target, message}, rest}:
      J.Object{[J.Field{"identity", J.Text{"[\"task-graph-edge\"," ++ J.quote(Nat.show(graph)) ++ "," ++ J.quote(rule) ++ "," ++ J.quote(Nat.show(ordinal)) ++ "," ++ J.quote(source) ++ "," ++ J.quote(target) ++ "]"}},
        J.Field{"ruleKey", J.Text{rule}},
        J.Field{"sourceIdentity", J.Text{resolved_identity(Graph.resolve(source, resolved), graph, source)}},
        J.Field{"targetIdentity", J.Text{resolved_identity(Graph.resolve(target, resolved), graph, target)}},
        J.Field{"actionKind", J.Text{action_kind(message)}}]} <> action_edges(rest, graph, rule, source, resolved, 1n+ordinal)

def edges( +rules: +List<Graph.Rule>, +graph: Nat, +resolved: +List<Graph.ResolvedNode>) -> +List<J.Json>:
  match rules:
    case Nil{}: Nil{}
    case Con{Graph.Rule{key, source, actions}, rest}:
      List.append(&2, J.Json, action_edges(actions, graph, key, source, resolved, 0n), edges(rest, graph, resolved))

def graph_value(+id: Nat, +graph: Graph.Graph, +world: Harness.World()) -> J.Json:
  J.Object{[J.Field{"id", observed_nat(id)}, J.Field{"name", J.Text{Graph.name(graph)}},
    J.Field{"nodes", J.Array{nodes(Graph.nodes(graph), id, world)}},
    J.Field{"edges", J.Array{edges(Graph.rules(graph), id, Graph.nodes(graph))}}]}

def source_handle( +status: String, +fresh: Bool, +sequence: Nat, +value: J.Json) -> J.Json:
  J.Object{[J.Field{"status", J.Text{status}}, J.Field{"fresh", J.Boolean{fresh}},
    J.Field{"sequence", observed_nat(sequence)}, J.Field{"value", value}]}

def source_node_bounds(+values: +List<Graph.ResolvedNode>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{Graph.ResolvedNode{key, task}, rest}: Nat.is_le(String.length(key), 512n) && source_node_bounds(rest)

def source_rule_bounds(+values: +List<Graph.Rule>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{Graph.Rule{key, source, actions}, rest}: Nat.is_le(String.length(key), 512n) && source_rule_bounds(rest)

def source_edge_count(+values: +List<Graph.Rule>) -> Nat:
  match values:
    case Nil{}: 0n
    case Con{Graph.Rule{key, source, actions}, rest}: Nat.add(List.length(&2, Graph.Action, actions), source_edge_count(rest))

def source_graph_bounds(+graph: Graph.Graph) -> Bool:
  Nat.is_le(String.length(Graph.name(graph)), 4096n) && Nat.is_le(List.length(&2, Graph.ResolvedNode, Graph.nodes(graph)), 128n) && Nat.is_le(source_edge_count(Graph.rules(graph)), 512n) && source_node_bounds(Graph.nodes(graph)) && source_rule_bounds(Graph.rules(graph))

def graph_admitted(+allowed: Bool, +id: Nat, +graph: Graph.Graph, +world: Harness.World(), +sequence: Nat, +fresh: Bool) -> J.Json:
  match allowed:
    case True{}: source_handle("ready", fresh, sequence, graph_value(id, graph, world))
    case False{}: J.Object{[J.Field{"status", J.Text{"error"}}, J.Field{"fresh", J.Boolean{fresh}}, J.Field{"sequence", observed_nat(sequence)}, J.Field{"value", J.Null{}}, J.Field{"message", J.Text{"任务图规模、名称或标识超过交互视图限制"}}]}

def graph_observation( +found: Maybe<&2, Graph.Graph>, +id: Nat, +world: Harness.World(), +sequence: Nat, +fresh: Bool) -> J.Json:
  match found:
    case None{}: source_handle("missing", fresh, sequence, J.Null{})
    case Some{+graph}: graph_admitted(source_graph_bounds(graph), id, graph, world, sequence, fresh)

def project( +request: UI.SourceRequest, +world: Harness.World(), +sequence: Nat, +fresh: Bool) -> J.Field:
  UI.SourceRequest{owner, name, +graph_id} = request
  J.Field{name, graph_observation(Graph.find(GraphState.registry(world), graph_id), graph_id, world, sequence, fresh)}

def projection( +requests: +List<UI.SourceRequest>, +world: Harness.World(), +sequence: Nat, +fresh: Bool) -> +List<J.Field>:
  match requests:
    case Nil{}: Nil{}
    case Con{request, rest}: project(request, world, sequence, fresh) <> projection(rest, world, sequence, fresh)
