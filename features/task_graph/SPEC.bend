import Base
import ./MODEL.bend as G
import ../../bendlib/association-map.bend as Finite

def wellformed(declaration: G.Declaration) -> Bool:
  G.wellformed(declaration)

def valid(state: G.State) -> Bool:
  G.valid(state)

def replacement(hit: Bool, key: Nat, previous: G.Graph, tail: +List<Finite.Entry(G.Graph)>, graph: G.Graph, updated: +List<Finite.Entry(G.Graph)>) -> +List<Finite.Entry(G.Graph)>:
  match hit:
    case True{}: (key, graph) <> tail
    case False{}: (key, previous) <> updated

# Existing graphs retain their dispatch position; a previously absent graph is
# inserted after every existing entry.
def store(entries: +List<Finite.Entry(G.Graph)>, +id: Nat, +graph: G.Graph) -> +List<Finite.Entry(G.Graph)>:
  match entries:
    case Nil{}: [(id, graph)]
    case Con{(+key, previous), +tail}:
      replacement(Nat.is_eq(id, key), key, previous, tail, graph, store(tail, id, graph))

def install(+id: Nat, declaration: G.Declaration, nodes: +List<G.ResolvedNode>, state: G.State) -> G.State:
  G.Declaration{name, requested, rules} = declaration
  G.State{entries, next} = state
  G.State{store(entries, id, G.Graph{name, nodes, rules, Nil{}}), Nat.max(next, 1n+id)}

def remove(+id: Nat, state: G.State) -> G.State:
  G.State{entries, next} = state
  G.State{Finite.remove(~G.Graph, entries, id), next}

def receipt_values(+previous: +List<G.Receipt>, incoming: +List<G.Receipt>) -> +List<G.Receipt>:
  +all = List.append(&2, G.Receipt, previous, incoming)
  List.drop(&2, G.Receipt, all, Nat.sub(List.length(&2, G.Receipt, all), 256n))

def record(found: Maybe<&2, G.Graph>, +id: Nat, incoming: +List<G.Receipt>, state: G.State) -> G.State:
  match found:
    case None{}: state
    case Some{G.Graph{name, nodes, rules, previous}}:
      G.State{entries, next} = state
      G.State{store(entries, id, G.Graph{name, nodes, rules, receipt_values(previous, incoming)}), next}

def receipts(+id: Nat, incoming: +List<G.Receipt>, +state: G.State) -> G.State:
  record(G.find(state, id), id, incoming, state)

def expand(message: G.Message, +output: String) -> String:
  match message:
    case G.Output{}: output
    case G.Literal{value}: value
    case G.Concat{Nil{}}: ""
    case G.Concat{Con{head, tail}}: expand(head, output) ++ expand(G.Concat{tail}, output)

def target(found: Maybe<&2, Nat>, graph: Nat, rule: String, message: G.Message, output: String) -> +List<G.Delivery>:
  match found:
    case None{}: Nil{}
    case Some{task}: [G.Delivery{graph, rule, task, expand(message, output)}]

def action(graph: Nat, rule: String, nodes: +List<G.ResolvedNode>, value: G.Action, output: String) -> +List<G.Delivery>:
  G.Action{key, message} = value
  target(G.resolve(key, nodes), graph, rule, message, output)

def actions(+graph: Nat, +rule: String, +nodes: +List<G.ResolvedNode>, values: +List<G.Action>, +output: String) -> +List<G.Delivery>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}: List.append(&2, G.Delivery, action(graph, rule, nodes, head, output), actions(graph, rule, nodes, tail, output))

def source(found: Maybe<&2, Nat>, origin: Nat, graph: Nat, rule: String, nodes: +List<G.ResolvedNode>, values: +List<G.Action>, output: String) -> +List<G.Delivery>:
  match found:
    case None{}: Nil{}
    case Some{task}: Bool.pick(+List<G.Delivery>, Nat.is_eq(origin, task), actions(graph, rule, nodes, values, output), Nil{})

def rule(+origin: Nat, graph: Nat, +nodes: +List<G.ResolvedNode>, value: G.Rule, output: String) -> +List<G.Delivery>:
  G.Rule{key, endpoint, values} = value
  source(G.resolve(endpoint, nodes), origin, graph, key, nodes, values, output)

def rules(+origin: Nat, +graph: Nat, +nodes: +List<G.ResolvedNode>, values: +List<G.Rule>, +output: String) -> +List<G.Delivery>:
  match values:
    case Nil{}: Nil{}
    case Con{head, tail}: List.append(&2, G.Delivery, rule(origin, graph, nodes, head, output), rules(origin, graph, nodes, tail, output))

def graph(+origin: Nat, +output: String, entry: Finite.Entry(G.Graph)) -> +List<G.Delivery>:
  (id, G.Graph{name, nodes, values, receipts}) = entry
  rules(origin, id, nodes, values, output)

def pending_entries(+origin: Nat, +output: String, entries: +List<Finite.Entry(G.Graph)>) -> +List<G.Delivery>:
  match entries:
    case Nil{}: Nil{}
    case Con{head, tail}: List.append(&2, G.Delivery, graph(origin, output, head), pending_entries(origin, output, tail))

def pending(origin: Nat, output: String, state: G.State) -> +List<G.Delivery>:
  pending_entries(origin, output, G.graphs(state))
