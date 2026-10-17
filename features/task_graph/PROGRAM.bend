import Base
import ../../bendlib/association-map.bend as Finite
import ./MODEL.bend as G

def expand(message: G.Message, +output: String) -> String:
  match message:
    case G.Output{}: output
    case G.Literal{value}: value
    case G.Concat{Nil{}}: ""
    case G.Concat{Con{head, rest}}: expand(head, output) ++ expand(G.Concat{rest}, output)

def expand_parts(parts: +List<G.Message>, +output: String) -> String:
  match parts:
    case Nil{}: ""
    case Con{head, rest}: expand(head, output) ++ expand_parts(rest, output)

def put_selected(selected: Bool, key: Nat, previous: G.Graph, rest: +List<Finite.Entry(G.Graph)>, graph: G.Graph, replacement: +List<Finite.Entry(G.Graph)>) -> +List<Finite.Entry(G.Graph)>:
  match selected:
    case True{}: (key, graph) <> rest
    case False{}: (key, previous) <> replacement

# NOTE: Replacing an entry keeps its dispatch position; only new graphs append.
def put_entries(entries: +List<Finite.Entry(G.Graph)>, +id: Nat, +graph: G.Graph) -> +List<Finite.Entry(G.Graph)>:
  match entries:
    case Nil{}: [(id, graph)]
    case Con{(+key, previous), +rest}:
      put_selected(Nat.is_eq(id, key), key, previous, rest, graph, put_entries(rest, id, graph))

def installed(declaration: G.Declaration, nodes: +List<G.ResolvedNode>) -> G.Graph:
  G.Declaration{name, requested, rules} = declaration
  G.Graph{name, nodes, rules, Nil{}}

def install(+id: Nat, declaration: G.Declaration, nodes: +List<G.ResolvedNode>, state: G.State) -> G.State:
  G.State{graphs, next} = state
  G.State{put_entries(graphs, id, installed(declaration, nodes)), Nat.max(next, 1n+id)}

def remove(+id: Nat, state: G.State) -> G.State:
  G.State{graphs, next} = state
  G.State{Finite.remove(~G.Graph, graphs, id), next}

def retained_receipts(+previous: +List<G.Receipt>, values: +List<G.Receipt>) -> +List<G.Receipt>:
  +combined = List.append(&2, G.Receipt, previous, values)
  List.drop(&2, G.Receipt, combined, Nat.sub(List.length(&2, G.Receipt, combined), 256n))

def with_receipts(graph: G.Graph, values: +List<G.Receipt>) -> G.Graph:
  G.Graph{name, nodes, rules, previous} = graph
  G.Graph{name, nodes, rules, retained_receipts(previous, values)}

def receipts_found(found: Maybe<&2, G.Graph>, +id: Nat, values: +List<G.Receipt>, state: G.State) -> G.State:
  match found:
    case None{}: state
    case Some{graph}:
      G.State{graphs, next} = state
      G.State{put_entries(graphs, id, with_receipts(graph, values)), next}

def receipts(+id: Nat, values: +List<G.Receipt>, +state: G.State) -> G.State:
  receipts_found(G.find(state, id), id, values, state)

def action_found(found: Maybe<&2, Nat>, graph: Nat, rule: String, message: G.Message, output: String) -> +List<G.Delivery>:
  match found:
    case None{}: Nil{}
    case Some{target}: [G.Delivery{graph, rule, target, expand(message, output)}]

def action(+graph: Nat, +rule: String, nodes: +List<G.ResolvedNode>, value: G.Action, output: String) -> +List<G.Delivery>:
  G.Action{target, message} = value
  action_found(G.resolve(target, nodes), graph, rule, message, output)

def actions(+graph: Nat, +rule: String, +nodes: +List<G.ResolvedNode>, values: +List<G.Action>, +output: String) -> +List<G.Delivery>:
  match values:
    case Nil{}: Nil{}
    case Con{head, rest}:
      List.append(&2, G.Delivery, action(graph, rule, nodes, head, output), actions(graph, rule, nodes, rest, output))

def rule_selected(selected: Bool, graph: Nat, rule: String, nodes: +List<G.ResolvedNode>, values: +List<G.Action>, output: String) -> +List<G.Delivery>:
  match selected:
    case False{}: Nil{}
    case True{}: actions(graph, rule, nodes, values, output)

def rule_found(found: Maybe<&2, Nat>, source: Nat, graph: Nat, rule: String, nodes: +List<G.ResolvedNode>, values: +List<G.Action>, output: String) -> +List<G.Delivery>:
  match found:
    case None{}: Nil{}
    case Some{task}: rule_selected(Nat.is_eq(source, task), graph, rule, nodes, values, output)

def rule(+source: Nat, +graph: Nat, +nodes: +List<G.ResolvedNode>, value: G.Rule, output: String) -> +List<G.Delivery>:
  G.Rule{key, origin, values} = value
  rule_found(G.resolve(origin, nodes), source, graph, key, nodes, values, output)

def rules(+source: Nat, +graph: Nat, +nodes: +List<G.ResolvedNode>, values: +List<G.Rule>, +output: String) -> +List<G.Delivery>:
  match values:
    case Nil{}: Nil{}
    case Con{head, rest}:
      List.append(&2, G.Delivery, rule(source, graph, nodes, head, output), rules(source, graph, nodes, rest, output))

def pending_entries(+source: Nat, +output: String, entries: +List<Finite.Entry(G.Graph)>) -> +List<G.Delivery>:
  match entries:
    case Nil{}: Nil{}
    case Con{(id, G.Graph{name, nodes, values, receipts}), rest}:
      List.append(&2, G.Delivery, rules(source, id, nodes, values, output), pending_entries(source, output, rest))

def pending(source: Nat, output: String, state: G.State) -> +List<G.Delivery>:
  pending_entries(source, output, G.graphs(state))
