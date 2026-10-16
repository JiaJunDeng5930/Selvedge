import Base
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J
import ../../features/task_graph/MODEL.bend as G
import ../../features/task_graph/PROGRAM.bend as Graph
import ../../features/task_graph/CODEC.bend as Codec
import ./operations.bend as O
import ./graph-state.bend as State
import ./graph-spec.bend as Spec
import ./MODEL.bend as F

def next_task(world: M.World()) -> Nat:
  D.state_next_task(C.local(D.State, F.State(), world))

def admitted(accepted: Bool, key: String, id: Nat, previous: +List<G.ResolvedNode>, before: +List<M.Effect()>, world: M.World(), reply: J.Json, effects: +List<M.Effect()>) -> Spec.Births:
  match accepted:
    case False{}: Spec.BirthFailed{reply}
    case True{}: Spec.Born{world, List.append(&2, G.ResolvedNode, previous, [G.ResolvedNode{key, id}]), List.append(&2, M.Effect(), before, effects)}

def created(key: String, id: Nat, previous: +List<G.ResolvedNode>, before: +List<M.Effect()>, decision: M.Decision()) -> Spec.Births:
  C.Decision{world, +reply, effects} = decision
  admitted(J.boolean(J.get(reply, "ok")), key, id, previous, before, world, reply, effects)

def birth(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), progress: Spec.Births, node: O.GraphNode) -> Spec.Births:
  match progress node:
    case Spec.BirthFailed{reply} _: Spec.BirthFailed{reply}
    case Spec.Born{world, previous, effects} O.GraphExisting{key, task}:
      Spec.Born{world, List.append(&2, G.ResolvedNode, previous, [G.ResolvedNode{key, task}]), effects}
    case Spec.Born{+world, previous, effects} O.GraphSpawn{key, profile, reasoning, message, selection}:
      created(key, next_task(world), previous, effects, spawn(profile, reasoning, message, selection, world))

def births_from(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), nodes: +List<O.GraphNode>, progress: Spec.Births) -> Spec.Births:
  List.foldl(~&2, ~O.GraphNode, ~Spec.Births, ~(state => node => birth(~spawn, state, node)), nodes, progress)

def births(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), nodes: +List<O.GraphNode>, world: M.World()) -> Spec.Births:
  births_from(~spawn, nodes, Spec.Born{world, Nil{}, Nil{}})

def installed(+id: Nat, declaration: G.Declaration, result: Spec.Births, original: M.World()) -> M.Decision():
  match declaration result:
    case _ Spec.BirthFailed{reply}: C.Decision{original, reply, Nil{}}
    case G.Declaration{+name, declared, +rules} Spec.Born{+world, +nodes, effects}:
      C.Decision{State.store(Graph.install(id, G.Declaration{name, declared, rules}, nodes, State.registry(world)), world),
        D.success(Codec.graph_json(id, G.Graph{name, nodes, rules, Nil{}})), effects}

def install(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), id: Nat, declaration: G.Declaration, nodes: +List<O.GraphNode>, +world: M.World()) -> M.Decision():
  installed(id, declaration, births(~spawn, nodes, world), world)

def remove(+id: Nat, +world: M.World()) -> M.Decision():
  C.Decision{State.store(Graph.remove(id, State.registry(world)), world), D.success(J.Object{[J.Field{"graph_id", J.nat(id)}]}), Nil{}}

def recorded(source: Nat, graph: Nat, rule: String, target: Nat, before: +List<M.Effect()>, decision: M.Decision()) -> M.Decision():
  C.Decision{+world, reply, effects} = decision
  C.Decision{State.store(Graph.receipts(graph, [G.Receipt{source, rule, target, reply}], State.registry(world)), world), J.Null{}, List.append(&2, M.Effect(), before, effects)}

def delivery(~send: Nat -> String -> @+world:M.World() -> M.Decision(), progress: Spec.Dispatch, item: G.Delivery) -> Spec.Dispatch:
  Spec.Dispatch{+source, C.Decision{world, reply, effects}} = progress
  G.Delivery{graph, rule, +target, message} = item
  Spec.Dispatch{source, recorded(source, graph, rule, target, effects, send(target, message, world))}

def deliveries_from(~send: Nat -> String -> @+world:M.World() -> M.Decision(), pending: +List<G.Delivery>, progress: Spec.Dispatch) -> Spec.Dispatch:
  List.foldl(~&2, ~G.Delivery, ~Spec.Dispatch, ~(state => item => delivery(~send, state, item)), pending, progress)

def decision(progress: Spec.Dispatch) -> M.Decision():
  Spec.decision(progress)

def deliveries(~send: Nat -> String -> @+world:M.World() -> M.Decision(), source: Nat, pending: +List<G.Delivery>, world: M.World()) -> M.Decision():
  decision(deliveries_from(~send, pending, Spec.Dispatch{source, C.Decision{world, J.Null{}, Nil{}}}))

def react(~send: Nat -> String -> @+world:M.World() -> M.Decision(), +source: Nat, output: String, +world: M.World()) -> M.Decision():
  deliveries(~send, source, Graph.pending(source, output, State.registry(world)), world)

def append_effects(before: +List<M.Effect()>, result: M.Decision()) -> M.Decision():
  C.Decision{world, reply, effects} = result
  C.Decision{world, reply, List.append(&2, M.Effect(), before, effects)}

def output(~send: Nat -> String -> @+world:M.World() -> M.Decision(), progress: Spec.Dispatch, text: String) -> Spec.Dispatch:
  Spec.Dispatch{+source, C.Decision{world, reply, effects}} = progress
  Spec.Dispatch{source, append_effects(effects, react(~send, source, text, world))}

def outputs_from(~send: Nat -> String -> @+world:M.World() -> M.Decision(), outputs: +List<String>, progress: Spec.Dispatch) -> Spec.Dispatch:
  List.foldl(~&2, ~String, ~Spec.Dispatch, ~(state => text => output(~send, state, text)), outputs, progress)

def react_outputs(~send: Nat -> String -> @+world:M.World() -> M.Decision(), source: Nat, outputs: +List<String>, world: M.World()) -> M.Decision():
  decision(outputs_from(~send, outputs, Spec.Dispatch{source, C.Decision{world, J.Null{}, Nil{}}}))
