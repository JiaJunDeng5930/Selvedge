import Base
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J
import ../../features/task_graph/MODEL.bend as G
import ../../features/task_graph/SPEC.bend as Graph
import ../../features/task_graph/CODEC.bend as Codec
import ./operations.bend as O
import ./graph-state.bend as State
import ./MODEL.bend as F

# The installation outcome carries provisional Task changes until every birth
# succeeds. A failed birth discards the entire provisional world and effects.
type Births is Data:
  Born{world: M.World(), nodes: +List<G.ResolvedNode>, effects: +List<M.Effect()>}
  BirthFailed{reply: J.Json}

def next_task(world: M.World()) -> Nat:
  D.state_next_task(C.local(D.State, F.State(), world))

def admitted(accepted: Bool, key: String, id: Nat, previous: +List<G.ResolvedNode>, before: +List<M.Effect()>, world: M.World(), reply: J.Json, effects: +List<M.Effect()>) -> Births:
  match accepted:
    case False{}: BirthFailed{reply}
    case True{}: Born{world, List.append(&2, G.ResolvedNode, previous, [G.ResolvedNode{key, id}]), List.append(&2, M.Effect(), before, effects)}

def created(key: String, id: Nat, previous: +List<G.ResolvedNode>, before: +List<M.Effect()>, decision: M.Decision()) -> Births:
  C.Decision{world, +reply, effects} = decision
  admitted(J.boolean(J.get(reply, "ok")), key, id, previous, before, world, reply, effects)

def birth(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), progress: Births, node: O.GraphNode) -> Births:
  match progress node:
    case BirthFailed{reply} _: BirthFailed{reply}
    case Born{world, previous, effects} O.GraphExisting{key, task}:
      Born{world, List.append(&2, G.ResolvedNode, previous, [G.ResolvedNode{key, task}]), effects}
    case Born{+world, previous, effects} O.GraphSpawn{key, profile, reasoning, message, selection}:
      created(key, next_task(world), previous, effects, spawn(profile, reasoning, message, selection, world))

def births_from(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), nodes: +List<O.GraphNode>, progress: Births) -> Births:
  match nodes:
    case Nil{}: progress
    case Con{node, rest}: births_from(~spawn, rest, birth(~spawn, progress, node))

def births(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), nodes: +List<O.GraphNode>, world: M.World()) -> Births:
  births_from(~spawn, nodes, Born{world, Nil{}, Nil{}})

def installed(+id: Nat, declaration: G.Declaration, result: Births, original: M.World()) -> M.Decision():
  match declaration result:
    case _ BirthFailed{reply}: C.Decision{original, reply, Nil{}}
    case G.Declaration{+name, declared, +rules} Born{+world, +nodes, effects}:
      C.Decision{State.store(Graph.install(id, G.Declaration{name, declared, rules}, nodes, State.registry(world)), world),
        D.success(Codec.graph_json(id, G.Graph{name, nodes, rules, Nil{}})), effects}

def install(~spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(), id: Nat, declaration: G.Declaration, nodes: +List<O.GraphNode>, +world: M.World()) -> M.Decision():
  installed(id, declaration, births(~spawn, nodes, world), world)

def remove(+id: Nat, +world: M.World()) -> M.Decision():
  C.Decision{State.store(Graph.remove(id, State.registry(world)), world), D.success(J.Object{[J.Field{"graph_id", J.nat(id)}]}), Nil{}}

# Source identity is part of the fold carrier, so the statically reusable Send
# capability never captures a runtime value in a compile-time argument.
type Dispatch is Data:
  Dispatch{source: Nat, decision: M.Decision()}

def recorded(source: Nat, graph: Nat, rule: String, target: Nat, before: +List<M.Effect()>, decision: M.Decision()) -> M.Decision():
  C.Decision{+world, reply, effects} = decision
  C.Decision{State.store(Graph.receipts(graph, [G.Receipt{source, rule, target, reply}], State.registry(world)), world), J.Null{}, List.append(&2, M.Effect(), before, effects)}

def delivery(~send: Nat -> String -> @+world:M.World() -> M.Decision(), progress: Dispatch, item: G.Delivery) -> Dispatch:
  Dispatch{+source, C.Decision{world, reply, effects}} = progress
  G.Delivery{graph, rule, +target, message} = item
  Dispatch{source, recorded(source, graph, rule, target, effects, send(target, message, world))}

def deliveries_from(~send: Nat -> String -> @+world:M.World() -> M.Decision(), pending: +List<G.Delivery>, progress: Dispatch) -> Dispatch:
  match pending:
    case Nil{}: progress
    case Con{item, rest}: deliveries_from(~send, rest, delivery(~send, progress, item))

def decision(progress: Dispatch) -> M.Decision():
  Dispatch{source, result} = progress
  result

def deliveries(~send: Nat -> String -> @+world:M.World() -> M.Decision(), source: Nat, pending: +List<G.Delivery>, world: M.World()) -> M.Decision():
  decision(deliveries_from(~send, pending, Dispatch{source, C.Decision{world, J.Null{}, Nil{}}}))

def react(~send: Nat -> String -> @+world:M.World() -> M.Decision(), +source: Nat, output: String, +world: M.World()) -> M.Decision():
  deliveries(~send, source, Graph.pending(source, output, State.registry(world)), world)

def append_effects(before: +List<M.Effect()>, result: M.Decision()) -> M.Decision():
  C.Decision{world, reply, effects} = result
  C.Decision{world, reply, List.append(&2, M.Effect(), before, effects)}

def output(~send: Nat -> String -> @+world:M.World() -> M.Decision(), progress: Dispatch, text: String) -> Dispatch:
  Dispatch{+source, C.Decision{world, reply, effects}} = progress
  Dispatch{source, append_effects(effects, react(~send, source, text, world))}

def outputs_from(~send: Nat -> String -> @+world:M.World() -> M.Decision(), outputs: +List<String>, progress: Dispatch) -> Dispatch:
  match outputs:
    case Nil{}: progress
    case Con{text, rest}: outputs_from(~send, rest, output(~send, progress, text))

def react_outputs(~send: Nat -> String -> @+world:M.World() -> M.Decision(), source: Nat, outputs: +List<String>, world: M.World()) -> M.Decision():
  decision(outputs_from(~send, outputs, Dispatch{source, C.Decision{world, J.Null{}, Nil{}}}))
