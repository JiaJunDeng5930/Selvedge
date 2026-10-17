import Base
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/logic-proof.bend as Logic
import ./MODEL.bend as G
import ./SPEC.bend as Spec
import ./PROGRAM.bend as P
import ./CONTRACT.bend as C

def same_key(+id: Nat) -> {Nat.is_eq(id, id) == True{} : Bool}:
  match id:
    case 0n: {==}
    case 1n+previous: same_key(previous)

# NOTE: The imported finite map proves removal absence. These small bridges
# connect its Boolean Nat keys to this registry's stable replacement operation.
def equal_key(+left: Nat, +right: Nat, +observed: {Nat.is_eq(left, right) == True{} : Bool}) -> {left == right : Nat}:
  match left right:
    case 0n 0n: {==}
    case 0n 1n+rest: Logic.impossible({0n == 1n+rest : Nat}, observed)
    case 1n+rest 0n: Logic.impossible({1n+rest == 0n : Nat}, observed)
    case 1n+left 1n+right:
      Equal.cong(Nat, Nat, (value => 1n+value), left, right, equal_key(left, right, observed))

def head_miss(+key: Nat, +graph: G.Graph, +rest: +List<Finite.Entry(G.Graph)>, +query: Nat,
  +observed: {Nat.is_eq(query, key) == False{} : Bool}) ->
  {Finite.find(~G.Graph, (key, graph) <> rest, query) == Finite.find(~G.Graph, rest, query) : Maybe<&2, G.Graph>}:
  backwards = Equal.sym(Bool, Nat.is_eq(query, key), False{}, observed)
  %backwards : {Finite.choose(~G.Graph, _, graph, Finite.find(~G.Graph, rest, query)) == Finite.find(~G.Graph, rest, query) : Maybe<&2, G.Graph>}
  {==}

def other_key(+id: Nat, +query: Nat, +key: Nat,
  selected: {Nat.is_eq(id, key) == True{} : Bool}, +different: {Nat.is_eq(query, id) == False{} : Bool}) ->
  {Nat.is_eq(query, key) == False{} : Bool}:
  Equal.trans(Bool, Nat.is_eq(query, key), Nat.is_eq(query, id), False{},
    Equal.sym(Bool, Nat.is_eq(query, id), Nat.is_eq(query, key),
      Equal.cong(Nat, Bool, (value => Nat.is_eq(query, value)), id, key, equal_key(id, key, selected))), different)

def lookup_put_step(+hit: Bool, +key: Nat, +previous: G.Graph, +rest: +List<Finite.Entry(G.Graph)>, +id: Nat, +graph: G.Graph,
  +observed: {Nat.is_eq(id, key) == hit : Bool},
  induction: {Finite.find(~G.Graph, P.put_entries(rest, id, graph), id) == Some{graph} : Maybe<&2, G.Graph>}) ->
  {Finite.find(~G.Graph, P.put_selected(hit, key, previous, rest, graph, P.put_entries(rest, id, graph)), id) == Some{graph} : Maybe<&2, G.Graph>}:
  match hit:
    case True{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, key), True{}, observed)
      %backwards : {Finite.choose(~G.Graph, _, graph, Finite.find(~G.Graph, rest, id)) == Some{graph} : Maybe<&2, G.Graph>}
      {==}
    case False{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, key), False{}, observed)
      %backwards : {Finite.choose(~G.Graph, _, previous, Finite.find(~G.Graph, P.put_entries(rest, id, graph), id)) == Some{graph} : Maybe<&2, G.Graph>}
      induction

def lookup_put(entries: +List<Finite.Entry(G.Graph)>, +id: Nat, +graph: G.Graph) ->
  {Finite.find(~G.Graph, P.put_entries(entries, id, graph), id) == Some{graph} : Maybe<&2, G.Graph>}:
  match entries:
    case Nil{}:
      backwards = Equal.sym(Bool, Nat.is_eq(id, id), True{}, same_key(id))
      %backwards : {Finite.choose(~G.Graph, _, graph, None{}) == Some{graph} : Maybe<&2, G.Graph>}
      {==}
    case Con{(+key, +previous), +rest}:
      lookup_put_step(Nat.is_eq(id, key), key, previous, rest, id, graph, {==}, lookup_put(rest, id, graph))

def unrelated_put_step(+hit: Bool, +key: Nat, +previous: G.Graph, +rest: +List<Finite.Entry(G.Graph)>, +id: Nat, +graph: G.Graph, +query: Nat,
  +observed: {Nat.is_eq(id, key) == hit : Bool}, +different: {Nat.is_eq(query, id) == False{} : Bool},
  induction: {Finite.find(~G.Graph, P.put_entries(rest, id, graph), query) == Finite.find(~G.Graph, rest, query) : Maybe<&2, G.Graph>}) ->
  {Finite.find(~G.Graph, P.put_selected(hit, key, previous, rest, graph, P.put_entries(rest, id, graph)), query) ==
   Finite.find(~G.Graph, (key, previous) <> rest, query) : Maybe<&2, G.Graph>}:
  match hit:
    case True{}:
      Equal.trans(Maybe<&2, G.Graph>, Finite.find(~G.Graph, (key, graph) <> rest, query), Finite.find(~G.Graph, rest, query),
        Finite.find(~G.Graph, (key, previous) <> rest, query), head_miss(key, graph, rest, query, other_key(id, query, key, observed, different)),
        Equal.sym(Maybe<&2, G.Graph>, Finite.find(~G.Graph, (key, previous) <> rest, query), Finite.find(~G.Graph, rest, query),
          head_miss(key, previous, rest, query, other_key(id, query, key, observed, different))))
    case False{}:
      Equal.cong(Maybe<&2, G.Graph>, Maybe<&2, G.Graph>, (tail => Finite.choose(~G.Graph, Nat.is_eq(query, key), previous, tail)),
        Finite.find(~G.Graph, P.put_entries(rest, id, graph), query), Finite.find(~G.Graph, rest, query), induction)

def unrelated_put(entries: +List<Finite.Entry(G.Graph)>, +id: Nat, +graph: G.Graph, +query: Nat,
  +different: {Nat.is_eq(query, id) == False{} : Bool}) ->
  {Finite.find(~G.Graph, P.put_entries(entries, id, graph), query) == Finite.find(~G.Graph, entries, query) : Maybe<&2, G.Graph>}:
  match entries:
    case Nil{}: head_miss(id, graph, Nil{}, query, different)
    case Con{(+key, +previous), +rest}:
      unrelated_put_step(Nat.is_eq(id, key), key, previous, rest, id, graph, query, {==}, different, unrelated_put(rest, id, graph, query, different))

def unrelated_remove_step(+hit: Bool, +key: Nat, +graph: G.Graph, +rest: +List<Finite.Entry(G.Graph)>, +id: Nat, +query: Nat,
  +observed: {Nat.is_eq(id, key) == hit : Bool}, +different: {Nat.is_eq(query, id) == False{} : Bool},
  induction: {Finite.find(~G.Graph, Finite.remove(~G.Graph, rest, id), query) == Finite.find(~G.Graph, rest, query) : Maybe<&2, G.Graph>}) ->
  {Finite.find(~G.Graph, Finite.keep(~G.Graph, Bool.not(hit), key, graph, Finite.remove(~G.Graph, rest, id)), query) ==
   Finite.find(~G.Graph, (key, graph) <> rest, query) : Maybe<&2, G.Graph>}:
  match hit:
    case True{}:
      Equal.trans(Maybe<&2, G.Graph>, Finite.find(~G.Graph, Finite.remove(~G.Graph, rest, id), query), Finite.find(~G.Graph, rest, query),
        Finite.find(~G.Graph, (key, graph) <> rest, query), induction,
        Equal.sym(Maybe<&2, G.Graph>, Finite.find(~G.Graph, (key, graph) <> rest, query), Finite.find(~G.Graph, rest, query),
          head_miss(key, graph, rest, query, other_key(id, query, key, observed, different))))
    case False{}:
      Equal.cong(Maybe<&2, G.Graph>, Maybe<&2, G.Graph>, (tail => Finite.choose(~G.Graph, Nat.is_eq(query, key), graph, tail)),
        Finite.find(~G.Graph, Finite.remove(~G.Graph, rest, id), query), Finite.find(~G.Graph, rest, query), induction)

def unrelated_remove(entries: +List<Finite.Entry(G.Graph)>, +id: Nat, +query: Nat,
  +different: {Nat.is_eq(query, id) == False{} : Bool}) ->
  {Finite.find(~G.Graph, Finite.remove(~G.Graph, entries, id), query) == Finite.find(~G.Graph, entries, query) : Maybe<&2, G.Graph>}:
  match entries:
    case Nil{}: {==}
    case Con{(+key, +graph), +rest}:
      unrelated_remove_step(Nat.is_eq(id, key), key, graph, rest, id, query, {==}, different, unrelated_remove(rest, id, query, different))

def store_step(hit: Bool, +key: Nat, +previous: G.Graph, +rest: +List<Finite.Entry(G.Graph)>, +id: Nat, +graph: G.Graph,
  induction: {P.put_entries(rest, id, graph) == Spec.store(rest, id, graph) : +List<Finite.Entry(G.Graph)>}) ->
  {P.put_selected(hit, key, previous, rest, graph, P.put_entries(rest, id, graph)) == Spec.replacement(hit, key, previous, rest, graph, Spec.store(rest, id, graph)) : +List<Finite.Entry(G.Graph)>}:
  match hit:
    case True{}: {==}
    case False{}:
      Equal.cong(+List<Finite.Entry(G.Graph)>, +List<Finite.Entry(G.Graph)>, (tail => (key, previous) <> tail),
        P.put_entries(rest, id, graph), Spec.store(rest, id, graph), induction)

def store_meaning(entries: +List<Finite.Entry(G.Graph)>, +id: Nat, +graph: G.Graph) ->
  {P.put_entries(entries, id, graph) == Spec.store(entries, id, graph) : +List<Finite.Entry(G.Graph)>}:
  match entries:
    case Nil{}: {==}
    case Con{(+key, +previous), +rest}:
      store_step(Nat.is_eq(id, key), key, previous, rest, id, graph, store_meaning(rest, id, graph))

def install_meaning(+id: Nat, +declaration: G.Declaration, +nodes: +List<G.ResolvedNode>, state: G.State) ->
  {P.install(id, declaration, nodes, state) == Spec.install(id, declaration, nodes, state) : G.State}:
  G.Declaration{name, requested, rules} = declaration
  G.State{+entries, +next} = state
  Equal.cong(+List<Finite.Entry(G.Graph)>, G.State, (values => G.State{values, Nat.max(next, 1n+id)}),
    P.put_entries(entries, id, G.Graph{name, nodes, rules, Nil{}}), Spec.store(entries, id, G.Graph{name, nodes, rules, Nil{}}),
    store_meaning(entries, id, G.Graph{name, nodes, rules, Nil{}}))

def remove_meaning(+id: Nat, +state: G.State) -> {P.remove(id, state) == Spec.remove(id, state) : G.State}:
  G.State{entries, next} = state
  {==}

def recording_meaning(+found: Maybe<&2, G.Graph>, +id: Nat, +values: +List<G.Receipt>, +state: G.State) ->
  {P.receipts_found(found, id, values, state) == Spec.record(found, id, values, state) : G.State}:
  match found:
    case None{}: {==}
    case Some{G.Graph{+name, +nodes, +rules, +previous}}:
      G.State{+entries, +next} = state
      +graph: G.Graph = G.Graph{name, nodes, rules, P.retained_receipts(previous, values)}
      Equal.cong(+List<Finite.Entry(G.Graph)>, G.State, (entries => G.State{entries, next}),
        P.put_entries(entries, id, graph), Spec.store(entries, id, graph), store_meaning(entries, id, graph))

def receipts_meaning(+id: Nat, +values: +List<G.Receipt>, +state: G.State) ->
  {P.receipts(id, values, state) == Spec.receipts(id, values, state) : G.State}:
  recording_meaning(G.find(state, id), id, values, state)

def installed_value(+id: Nat, +declaration: G.Declaration, +nodes: +List<G.ResolvedNode>, state: G.State) ->
  {G.find(P.install(id, declaration, nodes, state), id) == Some{P.installed(declaration, nodes)} : Maybe<&2, G.Graph>}:
  G.State{entries, next} = state
  lookup_put(entries, id, P.installed(declaration, nodes))

def removed_absence(+id: Nat, state: G.State) -> {G.find(P.remove(id, state), id) == None{} : Maybe<&2, G.Graph>}:
  G.State{entries, next} = state
  Finite.removal_absence(~G.Graph, entries, id)

def unrelated_installation(+id: Nat, +other: Nat, +declaration: G.Declaration, +nodes: +List<G.ResolvedNode>, state: G.State,
  +different: {Nat.is_eq(other, id) == False{} : Bool}) ->
  {G.find(P.install(id, declaration, nodes, state), other) == G.find(state, other) : Maybe<&2, G.Graph>}:
  G.State{entries, next} = state
  unrelated_put(entries, id, P.installed(declaration, nodes), other, different)

def unrelated_removal(+id: Nat, +other: Nat, state: G.State, +different: {Nat.is_eq(other, id) == False{} : Bool}) ->
  {G.find(P.remove(id, state), other) == G.find(state, other) : Maybe<&2, G.Graph>}:
  G.State{entries, next} = state
  unrelated_remove(entries, id, other, different)

def concatenation(+parts: +List<G.Message>, +output: String) -> {P.expand(G.Concat{parts}, output) == P.expand_parts(parts, output) : String}:
  match parts:
    case Nil{}: {==}
    case Con{+head, +rest}:
      Equal.cong(String, String, (tail => P.expand(head, output) ++ tail),
        P.expand(G.Concat{rest}, output), P.expand_parts(rest, output), concatenation(rest, output))

def resolved_target(+graph: Nat, +rule: String, +nodes: +List<G.ResolvedNode>, +key: String, +target: Nat, +message: G.Message, +output: String,
  +observed: {G.resolve(key, nodes) == Some{target} : Maybe<&2, Nat>}) ->
  {P.action(graph, rule, nodes, G.Action{key, message}, output) == [G.Delivery{graph, rule, target, P.expand(message, output)}] : +List<G.Delivery>}:
  Equal.cong(Maybe<&2, Nat>, +List<G.Delivery>, (found => P.action_found(found, graph, rule, message, output)),
    G.resolve(key, nodes), Some{target}, observed)

def missing_target(+graph: Nat, +rule: String, +nodes: +List<G.ResolvedNode>, +key: String, +message: G.Message, +output: String,
  +observed: {G.resolve(key, nodes) == None{} : Maybe<&2, Nat>}) ->
  {P.action(graph, rule, nodes, G.Action{key, message}, output) == Nil{} : +List<G.Delivery>}:
  Equal.cong(Maybe<&2, Nat>, +List<G.Delivery>, (found => P.action_found(found, graph, rule, message, output)),
    G.resolve(key, nodes), None{}, observed)

def selected_source(+source: Nat, +graph: Nat, +key: String, +origin: String, +nodes: +List<G.ResolvedNode>, +actions: +List<G.Action>, +output: String,
  +observed: {G.resolve(origin, nodes) == Some{source} : Maybe<&2, Nat>}) ->
  {P.rule(source, graph, nodes, G.Rule{key, origin, actions}, output) == P.actions(graph, key, nodes, actions, output) : +List<G.Delivery>}:
  Equal.trans(+List<G.Delivery>, P.rule(source, graph, nodes, G.Rule{key, origin, actions}, output),
    P.rule_found(Some{source}, source, graph, key, nodes, actions, output), P.actions(graph, key, nodes, actions, output),
    Equal.cong(Maybe<&2, Nat>, +List<G.Delivery>, (found => P.rule_found(found, source, graph, key, nodes, actions, output)),
      G.resolve(origin, nodes), Some{source}, observed),
    Equal.cong(Bool, +List<G.Delivery>, (hit => P.rule_selected(hit, graph, key, nodes, actions, output)),
      Nat.is_eq(source, source), True{}, same_key(source)))

def other_source(+source: Nat, +other: Nat, +graph: Nat, +key: String, +origin: String, +nodes: +List<G.ResolvedNode>, +actions: +List<G.Action>, +output: String,
  +observed: {G.resolve(origin, nodes) == Some{other} : Maybe<&2, Nat>}, +different: {Nat.is_eq(source, other) == False{} : Bool}) ->
  {P.rule(source, graph, nodes, G.Rule{key, origin, actions}, output) == Nil{} : +List<G.Delivery>}:
  Equal.trans(+List<G.Delivery>, P.rule(source, graph, nodes, G.Rule{key, origin, actions}, output),
    P.rule_found(Some{other}, source, graph, key, nodes, actions, output), Nil{},
    Equal.cong(Maybe<&2, Nat>, +List<G.Delivery>, (found => P.rule_found(found, source, graph, key, nodes, actions, output)),
      G.resolve(origin, nodes), Some{other}, observed),
    Equal.cong(Bool, +List<G.Delivery>, (hit => P.rule_selected(hit, graph, key, nodes, actions, output)), Nat.is_eq(source, other), False{}, different))

def expand_meaning(+message: G.Message, +output: String) -> {P.expand(message, output) == Spec.expand(message, output) : String}:
  match message:
    case G.Output{}: {==}
    case G.Literal{value}: {==}
    case G.Concat{Nil{}}: {==}
    case G.Concat{Con{+head, +tail}}:
      Equal.trans(String, P.expand(head, output) ++ P.expand(G.Concat{tail}, output),
        Spec.expand(head, output) ++ P.expand(G.Concat{tail}, output),
        Spec.expand(head, output) ++ Spec.expand(G.Concat{tail}, output),
        Equal.cong(String, String, (value => value ++ P.expand(G.Concat{tail}, output)),
          P.expand(head, output), Spec.expand(head, output), expand_meaning(head, output)),
        Equal.cong(String, String, (value => Spec.expand(head, output) ++ value),
          P.expand(G.Concat{tail}, output), Spec.expand(G.Concat{tail}, output), expand_meaning(G.Concat{tail}, output)))

def action_found_meaning(+found: Maybe<&2, Nat>, +graph: Nat, +rule: String, +message: G.Message, +output: String) ->
  {P.action_found(found, graph, rule, message, output) == Spec.target(found, graph, rule, message, output) : +List<G.Delivery>}:
  match found:
    case None{}: {==}
    case Some{+target}:
      Equal.cong(String, +List<G.Delivery>, (text => [G.Delivery{graph, rule, target, text}]),
        P.expand(message, output), Spec.expand(message, output), expand_meaning(message, output))

def action_meaning(+graph: Nat, +rule: String, +nodes: +List<G.ResolvedNode>, +value: G.Action, +output: String) ->
  {P.action(graph, rule, nodes, value, output) == Spec.action(graph, rule, nodes, value, output) : +List<G.Delivery>}:
  G.Action{key, message} = value
  action_found_meaning(G.resolve(key, nodes), graph, rule, message, output)

def delivery_append(+left: +List<G.Delivery>, +required_left: +List<G.Delivery>, +right: +List<G.Delivery>, +required_right: +List<G.Delivery>,
  head: {left == required_left : +List<G.Delivery>}, tail: {right == required_right : +List<G.Delivery>}) ->
  {List.append(&2, G.Delivery, left, right) == List.append(&2, G.Delivery, required_left, required_right) : +List<G.Delivery>}:
  Equal.trans(+List<G.Delivery>, List.append(&2, G.Delivery, left, right),
    List.append(&2, G.Delivery, required_left, right), List.append(&2, G.Delivery, required_left, required_right),
    Equal.cong(+List<G.Delivery>, +List<G.Delivery>, (value => List.append(&2, G.Delivery, value, right)), left, required_left, head),
    Equal.cong(+List<G.Delivery>, +List<G.Delivery>, (value => List.append(&2, G.Delivery, required_left, value)), right, required_right, tail))

def actions_meaning(+graph: Nat, +rule: String, +nodes: +List<G.ResolvedNode>, +values: +List<G.Action>, +output: String) ->
  {P.actions(graph, rule, nodes, values, output) == Spec.actions(graph, rule, nodes, values, output) : +List<G.Delivery>}:
  match values:
    case Nil{}: {==}
    case Con{+head, +tail}:
      delivery_append(P.action(graph, rule, nodes, head, output), Spec.action(graph, rule, nodes, head, output),
        P.actions(graph, rule, nodes, tail, output), Spec.actions(graph, rule, nodes, tail, output),
        action_meaning(graph, rule, nodes, head, output), actions_meaning(graph, rule, nodes, tail, output))

def source_selected_meaning(+selected: Bool, +graph: Nat, +key: String, +nodes: +List<G.ResolvedNode>, +values: +List<G.Action>, +output: String) ->
  {P.rule_selected(selected, graph, key, nodes, values, output) ==
   Bool.pick(+List<G.Delivery>, selected, Spec.actions(graph, key, nodes, values, output), Nil{}) : +List<G.Delivery>}:
  match selected:
    case False{}: {==}
    case True{}: actions_meaning(graph, key, nodes, values, output)

def source_found_meaning(+found: Maybe<&2, Nat>, +origin: Nat, +graph: Nat, +key: String, +nodes: +List<G.ResolvedNode>, +values: +List<G.Action>, +output: String) ->
  {P.rule_found(found, origin, graph, key, nodes, values, output) == Spec.source(found, origin, graph, key, nodes, values, output) : +List<G.Delivery>}:
  match found:
    case None{}: {==}
    case Some{+task}: source_selected_meaning(Nat.is_eq(origin, task), graph, key, nodes, values, output)

def rule_meaning(+origin: Nat, +graph: Nat, +nodes: +List<G.ResolvedNode>, +value: G.Rule, +output: String) ->
  {P.rule(origin, graph, nodes, value, output) == Spec.rule(origin, graph, nodes, value, output) : +List<G.Delivery>}:
  G.Rule{key, endpoint, values} = value
  source_found_meaning(G.resolve(endpoint, nodes), origin, graph, key, nodes, values, output)

def rules_meaning(+origin: Nat, +graph: Nat, +nodes: +List<G.ResolvedNode>, +values: +List<G.Rule>, +output: String) ->
  {P.rules(origin, graph, nodes, values, output) == Spec.rules(origin, graph, nodes, values, output) : +List<G.Delivery>}:
  match values:
    case Nil{}: {==}
    case Con{+head, +tail}:
      delivery_append(P.rule(origin, graph, nodes, head, output), Spec.rule(origin, graph, nodes, head, output),
        P.rules(origin, graph, nodes, tail, output), Spec.rules(origin, graph, nodes, tail, output),
        rule_meaning(origin, graph, nodes, head, output), rules_meaning(origin, graph, nodes, tail, output))

def pending_entries_meaning(+origin: Nat, +output: String, +entries: +List<Finite.Entry(G.Graph)>) ->
  {P.pending_entries(origin, output, entries) == Spec.pending_entries(origin, output, entries) : +List<G.Delivery>}:
  match entries:
    case Nil{}: {==}
    case Con{(+id, G.Graph{+name, +nodes, +values, +receipts}), +tail}:
      delivery_append(P.rules(origin, id, nodes, values, output), Spec.rules(origin, id, nodes, values, output),
        P.pending_entries(origin, output, tail), Spec.pending_entries(origin, output, tail),
        rules_meaning(origin, id, nodes, values, output), pending_entries_meaning(origin, output, tail))

def pending_meaning(+source: Nat, +output: String, +state: G.State) ->
  {P.pending(source, output, state) == Spec.pending(source, output, state) : +List<G.Delivery>}:
  pending_entries_meaning(source, output, G.graphs(state))

def dispatch_order(+source: Nat, +output: String, left: +List<Finite.Entry(G.Graph)>, +right: +List<Finite.Entry(G.Graph)>) ->
  {P.pending_entries(source, output, List.append(&2, Finite.Entry(G.Graph), left, right)) ==
   List.append(&2, G.Delivery, P.pending_entries(source, output, left), P.pending_entries(source, output, right)) : +List<G.Delivery>}:
  match left:
    case Nil{}: {==}
    case Con{(+id, G.Graph{name, +nodes, +rules, receipts}), +rest}:
      +head = P.rules(source, id, nodes, rules, output)
      Equal.trans(+List<G.Delivery>,
        List.append(&2, G.Delivery, head, P.pending_entries(source, output, List.append(&2, Finite.Entry(G.Graph), rest, right))),
        List.append(&2, G.Delivery, head, List.append(&2, G.Delivery, P.pending_entries(source, output, rest), P.pending_entries(source, output, right))),
        List.append(&2, G.Delivery, List.append(&2, G.Delivery, head, P.pending_entries(source, output, rest)), P.pending_entries(source, output, right)),
        Equal.cong(+List<G.Delivery>, +List<G.Delivery>, (tail => List.append(&2, G.Delivery, head, tail)),
          P.pending_entries(source, output, List.append(&2, Finite.Entry(G.Graph), rest, right)),
          List.append(&2, G.Delivery, P.pending_entries(source, output, rest), P.pending_entries(source, output, right)), dispatch_order(source, output, rest, right)),
        Std.app_assoc(G.Delivery, head, P.pending_entries(source, output, rest), P.pending_entries(source, output, right)))

def message_boundary() -> C.MessageBoundary:
  C.MessageBoundary{
    (text => {==}),
    (text => output => {==}),
    (parts => output => concatenation(parts, output)),
    (output => {==}),
    (head => tail => output => {==}),
    (source => output => state => pending_meaning(source, output, state)),
    (graph => rule => nodes => key => target => message => output => observed => resolved_target(graph, rule, nodes, key, target, message, output, observed)),
    (graph => rule => nodes => key => message => output => observed => missing_target(graph, rule, nodes, key, message, output, observed)),
    (source => graph => key => origin => nodes => actions => output => observed => selected_source(source, graph, key, origin, nodes, actions, output, observed)),
    (source => other => graph => key => origin => nodes => actions => output => observed => different => other_source(source, other, graph, key, origin, nodes, actions, output, observed, different)),
    (source => output => left => right => dispatch_order(source, output, left, right))}

def registry_boundary(admission: G.AdmissionBoundary) -> C.RegistryBoundary:
  C.RegistryBoundary{admission,
    (id => declaration => nodes => state => install_meaning(id, declaration, nodes, state)),
    (id => state => remove_meaning(id, state)),
    (id => values => state => receipts_meaning(id, values, state)),
    (id => declaration => nodes => state => installed_value(id, declaration, nodes, state)),
    (id => state => removed_absence(id, state)),
    (id => other => declaration => nodes => state => different => unrelated_installation(id, other, declaration, nodes, state, different)),
    (id => other => state => different => unrelated_removal(id, other, state, different)),
    message_boundary()}
