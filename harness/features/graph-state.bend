import Base
import ./MODEL.bend as F
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

def graphs_exist(graphs: +List<Finite.Entry(G.Graph)>, +tasks: +List<D.Task>) -> Bool:
  match graphs:
    case Nil{}: True{}
    case Con{(id, G.Graph{name, nodes, rules, receipts}), rest}:
      nodes_exist(nodes, tasks) && graphs_exist(rest, tasks)

def valid(+world: M.World()) -> Bool:
  G.valid(registry(world)) && graphs_exist(G.graphs(registry(world)), D.state_tasks(C.local(D.State, F.State(), world)))
