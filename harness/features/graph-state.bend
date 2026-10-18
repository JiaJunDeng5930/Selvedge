import Base
import ./MODEL.bend as F
import ./work-state.bend as WorkState
import ../MODEL.bend as M
import ../DOMAIN.bend as D
import ../tasks/PROGRAM.bend as Tasks
import ../../features/task_graph/MODEL.bend as G
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/component.bend as C

def registry(world: M.World()) -> G.State:
  F.task_graph(C.rest(D.State, F.State(), world))

def store(state: G.State, world: M.World()) -> M.World():
  C.map_rest(D.State, F.State(), features => F.with_task_graph(state, features), world)

def task_exists(found: Maybe<&2, D.Task>) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: True{}

def nodes_exist(nodes: +List<G.ResolvedNode>, +tasks: +List<D.Task>) -> Bool:
  match nodes:
    case Nil{}: True{}
    case Con{G.ResolvedNode{key, id}, rest}:
      task_exists(Tasks.find(tasks, id)) && nodes_exist(rest, tasks)

# A Work owns a graph independently of the graph declaration and Task lineage.
def work_exists(work: Maybe<&2, Nat>, world: M.World()) -> Bool:
  match work:
    case None{}: True{}
    case Some{id}: WorkState.exists(id, world)

def same_work(expected: Nat, found: Maybe<&2, Nat>) -> Bool:
  match found:
    case None{}: False{}
    case Some{actual}: Nat.is_eq(expected, actual)

def task_in_work(work: Maybe<&2, Nat>, task: Nat, world: M.World()) -> Bool:
  match work:
    case None{}: True{}
    case Some{id}: same_work(id, WorkState.task_owner(task, world))

def associate_task(work: Maybe<&2, Nat>, task: Nat, world: M.World()) -> M.World():
  match work:
    case None{}: world
    case Some{id}: WorkState.associate_task(task, id, world)

def associate_graph(work: Maybe<&2, Nat>, graph: Nat, world: M.World()) -> M.World():
  match work:
    case None{}: world
    case Some{id}: WorkState.associate_graph(graph, id, world)

def nodes_in_work(nodes: +List<G.ResolvedNode>, +work: Maybe<&2, Nat>, +world: M.World()) -> Bool:
  match nodes:
    case Nil{}: True{}
    case Con{G.ResolvedNode{key, id}, rest}:
      task_in_work(work, id, world) && nodes_in_work(rest, work, world)

def graphs_in_work(graphs: +List<Finite.Entry(G.Graph)>, +world: M.World()) -> Bool:
  match graphs:
    case Nil{}: True{}
    case Con{(+id, G.Graph{name, nodes, rules, receipts}), rest}:
      work_exists(WorkState.graph_owner(id, world), world) &&
        nodes_in_work(nodes, WorkState.graph_owner(id, world), world) && graphs_in_work(rest, world)

def graphs_exist(graphs: +List<Finite.Entry(G.Graph)>, +tasks: +List<D.Task>) -> Bool:
  match graphs:
    case Nil{}: True{}
    case Con{(id, G.Graph{name, nodes, rules, receipts}), rest}:
      nodes_exist(nodes, tasks) && graphs_exist(rest, tasks)

def valid(+world: M.World()) -> Bool:
  G.valid(registry(world)) && graphs_exist(G.graphs(registry(world)), D.state_tasks(C.local(D.State, F.State(), world))) &&
    graphs_in_work(G.graphs(registry(world)), world)
