import Base
import ./MODEL.bend as F
import ../MODEL.bend as M
import ../DOMAIN.bend as D
import ../tasks/PROGRAM.bend as Tasks
import ../../features/work/MODEL.bend as W
import ../../features/task_graph/MODEL.bend as Graph
import ../../bendlib/component.bend as C
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/json.bend as J

def registry(world: M.World()) -> W.State:
  F.work(C.rest(D.State, F.State(), world))

def store(state: W.State, world: M.World()) -> M.World():
  C.map_rest(D.State, F.State(), features => F.with_work(state, features), world)

def present(found: Maybe<&2, W.Work>) -> Bool:
  match found:
    case None{}: False{}
    case Some{work}: True{}

def exists(id: Nat, world: M.World()) -> Bool:
  present(W.find(registry(world), id))

# Task membership follows its immutable root association through fork lineage.
def task_work(+task: D.Task, world: M.World()) -> Maybe<&2, Nat>:
  W.task_owner(registry(world), D.task_id(task), D.task_lineage(task))

def found_owner(found: Maybe<&2, D.Task>, world: M.World()) -> Maybe<&2, Nat>:
  match found:
    case None{}: None{}
    case Some{task}: task_work(task, world)

def task_owner(id: Nat, +world: M.World()) -> Maybe<&2, Nat>:
  found_owner(Tasks.find(D.state_tasks(C.local(D.State, F.State(), world)), id), world)

def graph_owner(id: Nat, world: M.World()) -> Maybe<&2, Nat>:
  W.graph_owner(registry(world), id)

def associate_task(task: Nat, work: Nat, +world: M.World()) -> M.World():
  store(W.associate_task(task, work, registry(world)), world)

def associate_graph(graph: Nat, work: Nat, +world: M.World()) -> M.World():
  store(W.associate_graph(graph, work, registry(world)), world)

def dissociate_graph(graph: Nat, +world: M.World()) -> M.World():
  store(W.dissociate_graph(graph, registry(world)), world)

def embed(decision: C.Decision<W.State, Unit>, world: M.World()) -> M.Decision():
  C.Decision{state, reply, effects} = decision
  C.Decision{store(state, world), reply, Nil{}}

def matches(owner: Maybe<&2, Nat>, work: Nat) -> Bool:
  match owner:
    case None{}: False{}
    case Some{id}: Nat.is_eq(work, id)

def include_id(accepted: Bool, id: Nat, rest: +List<J.Json>) -> +List<J.Json>:
  match accepted:
    case False{}: rest
    case True{}: J.nat(id) <> rest

def task_ids(tasks: +List<D.Task>, +work: Nat, +world: M.World()) -> +List<J.Json>:
  match tasks:
    case Nil{}: Nil{}
    case Con{+task, rest}:
      include_id(matches(task_work(task, world), work), D.task_id(task), task_ids(rest, work, world))

def graph_ids(graphs: +List<Finite.Entry(Nat)>, +work: Nat) -> +List<J.Json>:
  match graphs:
    case Nil{}: Nil{}
    case Con{(graph, owner), rest}:
      include_id(Nat.is_eq(owner, work), graph, graph_ids(rest, work))

def detail(+id: Nat, work: W.Work, +world: M.World()) -> J.Json:
  J.Object{[J.Field{"work_id", J.nat(id)}, J.Field{"name", J.Text{W.name(work)}},
    J.Field{"task_ids", J.Array{task_ids(D.state_tasks(C.local(D.State, F.State(), world)), id, world)}},
    J.Field{"graph_ids", J.Array{graph_ids(W.graphs(registry(world)), id)}}]}

def details(entries: +List<Finite.Entry(W.Work)>, +world: M.World()) -> +List<J.Json>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, work), rest}: detail(id, work, world) <> details(rest, world)

def found_detail(found: Maybe<&2, W.Work>, id: Nat, world: M.World()) -> J.Json:
  match found:
    case None{}: D.failure("work_not_found", "The Work does not exist")
    case Some{work}: D.success(detail(id, work, world))

def query(query: W.Query, +world: M.World()) -> J.Json:
  match query:
    case W.ListWorks{}: D.success(J.Object{[J.Field{"works", J.Array{details(W.works(registry(world)), world)}}]})
    case W.ReadWork{+id}: found_detail(W.find(registry(world), id), id, world)

def root_lineage(lineage: +List<Nat>) -> Bool:
  match lineage:
    case Nil{}: True{}
    case _: False{}

def root_task(found: Maybe<&2, D.Task>) -> Bool:
  match found:
    case None{}: False{}
    case Some{task}: root_lineage(D.task_lineage(task))

def root_references(entries: +List<Finite.Entry(Nat)>, +tasks: +List<D.Task>) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(id, work), rest}: root_task(Tasks.find(tasks, id)) && root_references(rest, tasks)

def graph_present(found: Maybe<&2, Graph.Graph>) -> Bool:
  match found:
    case None{}: False{}
    case Some{graph}: True{}

def graph_references(entries: +List<Finite.Entry(Nat)>, +graphs: Graph.State) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(id, work), rest}: graph_present(Graph.find(graphs, id)) && graph_references(rest, graphs)

def valid(+world: M.World()) -> Bool:
  +state = registry(world)
  W.valid(state) && root_references(W.roots(state), D.state_tasks(C.local(D.State, F.State(), world))) &&
    graph_references(W.graphs(state), F.task_graph(C.rest(D.State, F.State(), world)))

def accepted_birth(accepted: Bool, work: Nat, task: Nat, original: M.World(), decision: M.Decision()) -> M.Decision():
  match accepted decision:
    case False{} C.Decision{world, reply, effects}: C.Decision{original, reply, Nil{}}
    case True{} C.Decision{world, reply, effects}: C.Decision{associate_task(task, work, world), reply, effects}

def born(work: Nat, task: Nat, original: M.World(), +decision: M.Decision()) -> M.Decision():
  C.Decision{world, +reply, effects} = decision
  accepted_birth(J.boolean(J.get(reply, "ok")), work, task, original, C.Decision{world, reply, effects})
