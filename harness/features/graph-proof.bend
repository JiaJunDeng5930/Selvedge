import Base
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../workspace/WORKSPACE.bend as Workspace
import ../../bendlib/component.bend as C
import ../../bendlib/json.bend as J
import ../../features/task_graph/MODEL.bend as G
import ../../features/task_graph/PROGRAM.bend as Graph
import ../../features/task_graph/SPEC.bend as GraphSpec
import ../../features/task_graph/registry-proof.bend as Registry
import ../../features/task_graph/CODEC.bend as Codec
import ./operations.bend as O
import ./graph-state.bend as State
import ./graph-spec.bend as Spec
import ./graph-execution.bend as Actual

def admitted(+accepted: Bool, +key: String, +id: Nat, +previous: +List<G.ResolvedNode>, +before: +List<M.Effect()>, +world: M.World(), +reply: J.Json, +effects: +List<M.Effect()>) ->
  {Actual.admitted(accepted, key, id, previous, before, world, reply, effects) == Spec.admitted(accepted, key, id, previous, before, world, reply, effects) : Spec.Births}:
  match accepted:
    case False{}: {==}
    case True{}: {==}

def created(+key: String, +id: Nat, +previous: +List<G.ResolvedNode>, +before: +List<M.Effect()>, +decision: M.Decision()) ->
  {Actual.created(key, id, previous, before, decision) == Spec.created(key, id, previous, before, decision) : Spec.Births}:
  C.Decision{+world, +reply, +effects} = decision
  admitted(J.boolean(J.get(reply, "ok")), key, id, previous, before, world, reply, effects)

# Full decisions are the interaction premise, including effects and failures.
def birth(~actual_spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  ~spec_spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  ~creation: @+profile:D.Profile -> @+reasoning:String -> @+message:String -> @+selection:Workspace.Selection -> @+world:M.World() ->
    {actual_spawn(profile, reasoning, message, selection, world) == spec_spawn(profile, reasoning, message, selection, world) : M.Decision()},
  +progress: Spec.Births, +node: O.GraphNode) ->
  {Actual.birth(~actual_spawn, progress, node) == Spec.birth(~spec_spawn, progress, node) : Spec.Births}:
  match progress node:
    case Spec.BirthFailed{reply} _: {==}
    case Spec.Born{world, previous, effects} O.GraphExisting{key, task}: {==}
    case Spec.Born{+world, +previous, +effects} O.GraphSpawn{+key, +profile, +reasoning, +message, +selection}:
      Equal.trans(Spec.Births,
        Actual.created(key, Actual.next_task(world), previous, effects, actual_spawn(profile, reasoning, message, selection, world)),
        Actual.created(key, Actual.next_task(world), previous, effects, spec_spawn(profile, reasoning, message, selection, world)),
        Spec.created(key, Spec.next_task(world), previous, effects, spec_spawn(profile, reasoning, message, selection, world)),
        Equal.cong(M.Decision(), Spec.Births,
          value => Actual.created(key, Actual.next_task(world), previous, effects, value),
          actual_spawn(profile, reasoning, message, selection, world), spec_spawn(profile, reasoning, message, selection, world),
          creation(profile, reasoning, message, selection, world)),
        created(key, Actual.next_task(world), previous, effects, spec_spawn(profile, reasoning, message, selection, world)))

def births_from(~actual_spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  ~spec_spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  ~creation: @+profile:D.Profile -> @+reasoning:String -> @+message:String -> @+selection:Workspace.Selection -> @+world:M.World() ->
    {actual_spawn(profile, reasoning, message, selection, world) == spec_spawn(profile, reasoning, message, selection, world) : M.Decision()},
  nodes: +List<O.GraphNode>, +progress: Spec.Births) ->
  {Actual.births_from(~actual_spawn, nodes, progress) == Spec.births_from(~spec_spawn, nodes, progress) : Spec.Births}:
  match nodes:
    case Nil{}: {==}
    case Con{+node, +rest}:
      Equal.trans(Spec.Births,
        Actual.births_from(~actual_spawn, rest, Actual.birth(~actual_spawn, progress, node)),
        Spec.births_from(~spec_spawn, rest, Actual.birth(~actual_spawn, progress, node)),
        Spec.births_from(~spec_spawn, rest, Spec.birth(~spec_spawn, progress, node)),
        births_from(~actual_spawn, ~spec_spawn, ~creation, rest, Actual.birth(~actual_spawn, progress, node)),
        Equal.cong(Spec.Births, Spec.Births, value => Spec.births_from(~spec_spawn, rest, value),
          Actual.birth(~actual_spawn, progress, node), Spec.birth(~spec_spawn, progress, node),
          birth(~actual_spawn, ~spec_spawn, ~creation, progress, node)))

def installed(+id: Nat, +declaration: G.Declaration, +result: Spec.Births, +original: M.World()) ->
  {Actual.installed(id, declaration, result, original) == Spec.installed(id, declaration, result, original) : M.Decision()}:
  match declaration result:
    case _ Spec.BirthFailed{reply}: {==}
    case G.Declaration{+name, +declared, +rules} Spec.Born{+world, +nodes, +effects}:
      Equal.cong(G.State, M.Decision(),
        registry => C.Decision{State.store(registry, world), D.success(Codec.graph_json(id, G.Graph{name, nodes, rules, Nil{}})), effects},
        Graph.install(id, G.Declaration{name, declared, rules}, nodes, State.registry(world)),
        GraphSpec.install(id, G.Declaration{name, declared, rules}, nodes, State.registry(world)),
        Registry.install_meaning(id, G.Declaration{name, declared, rules}, nodes, State.registry(world)))

def install(~actual_spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  ~spec_spawn: D.Profile -> String -> String -> Workspace.Selection -> @+world:M.World() -> M.Decision(),
  ~creation: @+profile:D.Profile -> @+reasoning:String -> @+message:String -> @+selection:Workspace.Selection -> @+world:M.World() ->
    {actual_spawn(profile, reasoning, message, selection, world) == spec_spawn(profile, reasoning, message, selection, world) : M.Decision()},
  +id: Nat, +declaration: G.Declaration, +nodes: +List<O.GraphNode>, +world: M.World()) ->
  {Actual.install(~actual_spawn, id, declaration, nodes, world) == Spec.install(~spec_spawn, id, declaration, nodes, world) : M.Decision()}:
  Equal.trans(M.Decision(),
    Actual.installed(id, declaration, Actual.births(~actual_spawn, nodes, world), world),
    Actual.installed(id, declaration, Spec.births(~spec_spawn, nodes, world), world),
    Spec.installed(id, declaration, Spec.births(~spec_spawn, nodes, world), world),
    Equal.cong(Spec.Births, M.Decision(), result => Actual.installed(id, declaration, result, world),
      Actual.births(~actual_spawn, nodes, world), Spec.births(~spec_spawn, nodes, world),
      births_from(~actual_spawn, ~spec_spawn, ~creation, nodes, Spec.Born{world, Nil{}, Nil{}})),
    installed(id, declaration, Spec.births(~spec_spawn, nodes, world), world))

def remove(+id: Nat, +world: M.World()) ->
  {Actual.remove(id, world) == Spec.remove(id, world) : M.Decision()}:
  Equal.cong(G.State, M.Decision(), registry => C.Decision{State.store(registry, world), D.success(J.Object{[J.Field{"graph_id", J.nat(id)}]}), Nil{}},
    Graph.remove(id, State.registry(world)), GraphSpec.remove(id, State.registry(world)), Registry.remove_meaning(id, State.registry(world)))

def recorded(+source: Nat, +graph: Nat, +rule: String, +target: Nat, +before: +List<M.Effect()>, +decision: M.Decision()) ->
  {Actual.recorded(source, graph, rule, target, before, decision) == Spec.recorded(source, graph, rule, target, before, decision) : M.Decision()}:
  C.Decision{+world, +reply, +effects} = decision
  Equal.cong(G.State, M.Decision(), registry => C.Decision{State.store(registry, world), J.Null{}, List.append(&2, M.Effect(), before, effects)},
    Graph.receipts(graph, [G.Receipt{source, rule, target, reply}], State.registry(world)),
    GraphSpec.receipts(graph, [G.Receipt{source, rule, target, reply}], State.registry(world)),
    Registry.receipts_meaning(graph, [G.Receipt{source, rule, target, reply}], State.registry(world)))

def delivery(~actual_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~spec_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~sending: @+target:Nat -> @+message:String -> @+world:M.World() ->
    {actual_send(target, message, world) == spec_send(target, message, world) : M.Decision()},
  +progress: Spec.Dispatch, +item: G.Delivery) ->
  {Actual.delivery(~actual_send, progress, item) == Spec.delivery(~spec_send, progress, item) : Spec.Dispatch}:
  Spec.Dispatch{+source, C.Decision{+world, reply, +effects}} = progress
  G.Delivery{+graph, +rule, +target, +message} = item
  Equal.trans(Spec.Dispatch,
    Spec.Dispatch{source, Actual.recorded(source, graph, rule, target, effects, actual_send(target, message, world))},
    Spec.Dispatch{source, Actual.recorded(source, graph, rule, target, effects, spec_send(target, message, world))},
    Spec.Dispatch{source, Spec.recorded(source, graph, rule, target, effects, spec_send(target, message, world))},
    Equal.cong(M.Decision(), Spec.Dispatch,
      value => Spec.Dispatch{source, Actual.recorded(source, graph, rule, target, effects, value)},
      actual_send(target, message, world), spec_send(target, message, world), sending(target, message, world)),
    Equal.cong(M.Decision(), Spec.Dispatch, value => Spec.Dispatch{source, value},
      Actual.recorded(source, graph, rule, target, effects, spec_send(target, message, world)),
      Spec.recorded(source, graph, rule, target, effects, spec_send(target, message, world)),
      recorded(source, graph, rule, target, effects, spec_send(target, message, world))))

def deliveries_from(~actual_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~spec_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~sending: @+target:Nat -> @+message:String -> @+world:M.World() ->
    {actual_send(target, message, world) == spec_send(target, message, world) : M.Decision()},
  pending: +List<G.Delivery>, +progress: Spec.Dispatch) ->
  {Actual.deliveries_from(~actual_send, pending, progress) == Spec.deliveries_from(~spec_send, pending, progress) : Spec.Dispatch}:
  match pending:
    case Nil{}: {==}
    case Con{+item, +rest}:
      Equal.trans(Spec.Dispatch,
        Actual.deliveries_from(~actual_send, rest, Actual.delivery(~actual_send, progress, item)),
        Spec.deliveries_from(~spec_send, rest, Actual.delivery(~actual_send, progress, item)),
        Spec.deliveries_from(~spec_send, rest, Spec.delivery(~spec_send, progress, item)),
        deliveries_from(~actual_send, ~spec_send, ~sending, rest, Actual.delivery(~actual_send, progress, item)),
        Equal.cong(Spec.Dispatch, Spec.Dispatch, value => Spec.deliveries_from(~spec_send, rest, value),
          Actual.delivery(~actual_send, progress, item), Spec.delivery(~spec_send, progress, item),
          delivery(~actual_send, ~spec_send, ~sending, progress, item)))

def deliveries(~actual_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~spec_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~sending: @+target:Nat -> @+message:String -> @+world:M.World() ->
    {actual_send(target, message, world) == spec_send(target, message, world) : M.Decision()},
  +source: Nat, +pending: +List<G.Delivery>, +world: M.World()) ->
  {Actual.deliveries(~actual_send, source, pending, world) == Spec.deliveries(~spec_send, source, pending, world) : M.Decision()}:
  Equal.cong(Spec.Dispatch, M.Decision(), Actual.decision,
    Actual.deliveries_from(~actual_send, pending, Spec.Dispatch{source, C.Decision{world, J.Null{}, Nil{}}}),
    Spec.deliveries_from(~spec_send, pending, Spec.Dispatch{source, C.Decision{world, J.Null{}, Nil{}}}),
    deliveries_from(~actual_send, ~spec_send, ~sending, pending, Spec.Dispatch{source, C.Decision{world, J.Null{}, Nil{}}}))

def react(~actual_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~spec_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~sending: @+target:Nat -> @+message:String -> @+world:M.World() ->
    {actual_send(target, message, world) == spec_send(target, message, world) : M.Decision()},
  +source: Nat, +output: String, +world: M.World()) ->
  {Actual.react(~actual_send, source, output, world) == Spec.react(~spec_send, source, output, world) : M.Decision()}:
  Equal.trans(M.Decision(),
    Actual.deliveries(~actual_send, source, Graph.pending(source, output, State.registry(world)), world),
    Spec.deliveries(~spec_send, source, Graph.pending(source, output, State.registry(world)), world),
    Spec.deliveries(~spec_send, source, GraphSpec.pending(source, output, State.registry(world)), world),
    deliveries(~actual_send, ~spec_send, ~sending, source, Graph.pending(source, output, State.registry(world)), world),
    Equal.cong(+List<G.Delivery>, M.Decision(), pending => Spec.deliveries(~spec_send, source, pending, world),
      Graph.pending(source, output, State.registry(world)), GraphSpec.pending(source, output, State.registry(world)),
      Registry.pending_meaning(source, output, State.registry(world))))

def append_effects(+before: +List<M.Effect()>, +decision: M.Decision()) ->
  {Actual.append_effects(before, decision) == Spec.append_effects(before, decision) : M.Decision()}:
  C.Decision{world, reply, effects} = decision
  {==}

def output(~actual_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~spec_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~sending: @+target:Nat -> @+message:String -> @+world:M.World() ->
    {actual_send(target, message, world) == spec_send(target, message, world) : M.Decision()},
  +progress: Spec.Dispatch, +text: String) ->
  {Actual.output(~actual_send, progress, text) == Spec.output(~spec_send, progress, text) : Spec.Dispatch}:
  Spec.Dispatch{+source, C.Decision{+world, reply, +effects}} = progress
  Equal.trans(Spec.Dispatch,
    Spec.Dispatch{source, Actual.append_effects(effects, Actual.react(~actual_send, source, text, world))},
    Spec.Dispatch{source, Actual.append_effects(effects, Spec.react(~spec_send, source, text, world))},
    Spec.Dispatch{source, Spec.append_effects(effects, Spec.react(~spec_send, source, text, world))},
    Equal.cong(M.Decision(), Spec.Dispatch, value => Spec.Dispatch{source, Actual.append_effects(effects, value)},
      Actual.react(~actual_send, source, text, world), Spec.react(~spec_send, source, text, world),
      react(~actual_send, ~spec_send, ~sending, source, text, world)),
    Equal.cong(M.Decision(), Spec.Dispatch, value => Spec.Dispatch{source, value},
      Actual.append_effects(effects, Spec.react(~spec_send, source, text, world)),
      Spec.append_effects(effects, Spec.react(~spec_send, source, text, world)),
      append_effects(effects, Spec.react(~spec_send, source, text, world))))

def outputs_from(~actual_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~spec_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~sending: @+target:Nat -> @+message:String -> @+world:M.World() ->
    {actual_send(target, message, world) == spec_send(target, message, world) : M.Decision()},
  outputs: +List<String>, +progress: Spec.Dispatch) ->
  {Actual.outputs_from(~actual_send, outputs, progress) == Spec.outputs_from(~spec_send, outputs, progress) : Spec.Dispatch}:
  match outputs:
    case Nil{}: {==}
    case Con{+text, +rest}:
      Equal.trans(Spec.Dispatch,
        Actual.outputs_from(~actual_send, rest, Actual.output(~actual_send, progress, text)),
        Spec.outputs_from(~spec_send, rest, Actual.output(~actual_send, progress, text)),
        Spec.outputs_from(~spec_send, rest, Spec.output(~spec_send, progress, text)),
        outputs_from(~actual_send, ~spec_send, ~sending, rest, Actual.output(~actual_send, progress, text)),
        Equal.cong(Spec.Dispatch, Spec.Dispatch, value => Spec.outputs_from(~spec_send, rest, value),
          Actual.output(~actual_send, progress, text), Spec.output(~spec_send, progress, text),
          output(~actual_send, ~spec_send, ~sending, progress, text)))

def react_outputs(~actual_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~spec_send: Nat -> String -> @+world:M.World() -> M.Decision(),
  ~sending: @+target:Nat -> @+message:String -> @+world:M.World() ->
    {actual_send(target, message, world) == spec_send(target, message, world) : M.Decision()},
  +source: Nat, +outputs: +List<String>, +world: M.World()) ->
  {Actual.react_outputs(~actual_send, source, outputs, world) == Spec.react_outputs(~spec_send, source, outputs, world) : M.Decision()}:
  Equal.cong(Spec.Dispatch, M.Decision(), Actual.decision,
    Actual.outputs_from(~actual_send, outputs, Spec.Dispatch{source, C.Decision{world, J.Null{}, Nil{}}}),
    Spec.outputs_from(~spec_send, outputs, Spec.Dispatch{source, C.Decision{world, J.Null{}, Nil{}}}),
    outputs_from(~actual_send, ~spec_send, ~sending, outputs, Spec.Dispatch{source, C.Decision{world, J.Null{}, Nil{}}}))
