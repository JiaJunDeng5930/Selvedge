import Base
import ../../bendlib/json.bend as J
import ../../bendlib/association-map.bend as Finite
import ../../bendlib/categories.bend as Categories

type Message is Data:
  Output{}
  Literal{value: String}
  Concat{parts: +List<Message>}

type Node is Data:
  Existing{key: String, task: Nat}
  Spawn{key: String, profile: String, reasoning: String, message: String, settings: J.Json}

type Action is Data:
  Action{target: String, message: Message}

type Rule is Data:
  Rule{key: String, source: String, actions: +List<Action>}

type Declaration is Data:
  Declaration{name: String, nodes: +List<Node>, rules: +List<Rule>}

type ResolvedNode is Data:
  ResolvedNode{key: String, task: Nat}

type Receipt is Data:
  Receipt{source: Nat, rule: String, target: Nat, reply: J.Json}

type Graph is Data:
  Graph{name: String, nodes: +List<ResolvedNode>, rules: +List<Rule>, receipts: +List<Receipt>}

type State is Data:
  State{graphs: +List<Finite.Entry(Graph)>, next: Nat}

type Command is Data:
  Create{work: Maybe<&2, Nat>, declaration: Declaration}
  Update{id: Nat, declaration: Declaration}
  Delete{id: Nat}

type Query is Data:
  ListGraphs{}
  ReadGraph{id: Nat}

type Delivery is Data:
  Delivery{graph: Nat, rule: String, target: Nat, message: String}

def initial() -> State:
  State{Nil{}, 0n}

def graphs(state: State) -> +List<Finite.Entry(Graph)>:
  State{graphs, next} = state
  graphs

def next(state: State) -> Nat:
  State{graphs, next} = state
  next

def find(state: State, id: Nat) -> Maybe<&2, Graph>:
  Finite.find(~Graph, graphs(state), id)

def name(graph: Graph) -> String:
  Graph{name, nodes, rules, receipts} = graph
  name

def nodes(graph: Graph) -> +List<ResolvedNode>:
  Graph{name, nodes, rules, receipts} = graph
  nodes

def rules(graph: Graph) -> +List<Rule>:
  Graph{name, nodes, rules, receipts} = graph
  rules

def receipts(graph: Graph) -> +List<Receipt>:
  Graph{name, nodes, rules, receipts} = graph
  receipts

def node_key(node: Node) -> String:
  match node:
    case Existing{key, task}: key
    case Spawn{key, profile, reasoning, message, settings}: key

def node_task(node: Node) -> Maybe<&2, Nat>:
  match node:
    case Existing{key, task}: Some{task}
    case Spawn{key, profile, reasoning, message, settings}: None{}

def resolve(+key: String, nodes: +List<ResolvedNode>) -> Maybe<&2, Nat>:
  match nodes:
    case Nil{}: None{}
    case Con{ResolvedNode{+candidate, task}, rest}:
      Finite.choose(~Nat, String.eq(key, candidate), task, resolve(key, rest))

def nonempty(text: String) -> Bool:
  Bool.not(String.eq(text, ""))

def contains(+key: String, keys: +List<String>) -> Bool:
  match keys:
    case Nil{}: False{}
    case Con{candidate, rest}: String.eq(key, candidate) || contains(key, rest)

def unique(keys: +List<String>) -> Bool:
  match keys:
    case Nil{}: True{}
    case Con{+key, +rest}: nonempty(key) && Bool.not(contains(key, rest)) && unique(rest)

def node_keys(nodes: +List<Node>) -> +List<String>:
  match nodes:
    case Nil{}: Nil{}
    case Con{node, rest}: node_key(node) <> node_keys(rest)

def resolved_keys(nodes: +List<ResolvedNode>) -> +List<String>:
  match nodes:
    case Nil{}: Nil{}
    case Con{ResolvedNode{key, task}, rest}: key <> resolved_keys(rest)

def rule_keys(rules: +List<Rule>) -> +List<String>:
  match rules:
    case Nil{}: Nil{}
    case Con{Rule{key, source, actions}, rest}: key <> rule_keys(rest)

type MessageFrame is Data:
  MessageFrame{message: Message, depth: Nat}

def message_frames(+depth: Nat, parts: +List<Message>) -> +List<MessageFrame>:
  match parts:
    case Nil{}: Nil{}
    case Con{part, rest}: MessageFrame{part, depth} <> message_frames(depth, rest)

# The work budget counts expression nodes, including each Concat constructor.
def message_scan(fuel: Nat, work: +List<MessageFrame>) -> Bool:
  match fuel work:
    case 0n Nil{}: True{}
    case 0n Con{frame, rest}: False{}
    case 1n+remaining Nil{}: True{}
    case 1n+remaining Con{MessageFrame{message, 0n}, rest}: False{}
    case 1n+remaining Con{MessageFrame{Output{}, depth}, rest}: message_scan(remaining, rest)
    case 1n+remaining Con{MessageFrame{Literal{value}, depth}, rest}: message_scan(remaining, rest)
    case 1n+remaining Con{MessageFrame{Concat{+parts}, 1n+lower}, +rest}:
      Nat.is_le(List.length(&2, Message, parts), 64n) &&
        message_scan(remaining, List.append(&2, MessageFrame, message_frames(lower, parts), rest))

def valid_message(message: Message) -> Bool:
  message_scan(64n, [MessageFrame{message, 8n}])

def action_references(actions: +List<Action>, +keys: +List<String>) -> Bool:
  match actions:
    case Nil{}: True{}
    case Con{Action{target, message}, rest}: contains(target, keys) && action_references(rest, keys)

def rule_references(rules: +List<Rule>, +keys: +List<String>) -> Bool:
  match rules:
    case Nil{}: True{}
    case Con{Rule{key, source, actions}, rest}:
      contains(source, keys) && action_references(actions, keys) && rule_references(rest, keys)

def action_bounds(actions: +List<Action>) -> Bool:
  match actions:
    case Nil{}: True{}
    case Con{Action{target, message}, rest}: valid_message(message) && action_bounds(rest)

def rule_bounds(rules: +List<Rule>) -> Bool:
  match rules:
    case Nil{}: True{}
    case Con{Rule{key, source, +actions}, rest}:
      Nat.is_le(List.length(&2, Action, actions), 8n) && action_bounds(actions) && rule_bounds(rest)

def identifiers(declaration: Declaration) -> Bool:
  Declaration{name, nodes, rules} = declaration
  nonempty(name) && unique(node_keys(nodes)) && unique(rule_keys(rules))

def references(declaration: Declaration) -> Bool:
  Declaration{name, nodes, rules} = declaration
  rule_references(rules, node_keys(nodes))

def bounded(declaration: Declaration) -> Bool:
  Declaration{name, +nodes, +rules} = declaration
  Nat.is_le(List.length(&2, Node, nodes), 32n) && Nat.is_le(List.length(&2, Rule, rules), 32n) && rule_bounds(rules)

def wellformed(+declaration: Declaration) -> Bool:
  identifiers(declaration) && references(declaration) && bounded(declaration)

def admissible(declaration: Declaration) -> Type:
  Categories.intersection(Declaration, Categories.holds(Declaration, identifiers),
    (value => Categories.intersection(Declaration, Categories.holds(Declaration, references),
      Categories.holds(Declaration, bounded), value)), declaration)

def construct_checked(+declaration: Declaration, identity: Bool, links: Bool, bounds: Bool,
  identity_evidence: {identifiers(declaration) == identity : Bool},
  links_evidence: {references(declaration) == links : Bool},
  bounds_evidence: {bounded(declaration) == bounds : Bool}) -> Maybe<&1, Categories.Membership<Declaration, admissible>>:
  match identity links bounds:
    case True{} True{} True{}:
      Some{Categories.Membership{declaration, Categories.Intersection{identity_evidence,
        Categories.Intersection{links_evidence, bounds_evidence}}}}
    case _ _ _: None{}

def construct(+declaration: Declaration) -> Maybe<&1, Categories.Membership<Declaration, admissible>>:
  construct_checked(declaration, identifiers(declaration), references(declaration), bounded(declaration), {==}, {==}, {==})

def constructed_declaration(member: Categories.Membership<Declaration, admissible>) -> Declaration:
  Categories.Membership{declaration, evidence} = member
  declaration

def construction_result(result: Maybe<&1, Categories.Membership<Declaration, admissible>>) -> Maybe<&2, Declaration>:
  match result:
    case None{}: None{}
    case Some{member}: Some{constructed_declaration(member)}

def selected(accepted: Bool, declaration: Declaration) -> Maybe<&2, Declaration>:
  match accepted:
    case False{}: None{}
    case True{}: Some{declaration}

type AdmissionBoundary is Type:
  AdmissionBoundary{
    correspondence: @+declaration:Declaration ->
      {construction_result(construct(declaration)) == selected(wellformed(declaration), declaration) : Maybe<&2, Declaration>},
    sound: @+declaration:Declaration -> admissible(declaration) -> {wellformed(declaration) == True{} : Bool}}

def valid_graph(graph: Graph) -> Bool:
  Graph{name, +nodes, +rules, +receipts} = graph
  nonempty(name) && unique(resolved_keys(nodes)) && unique(rule_keys(rules)) &&
    rule_references(rules, resolved_keys(nodes)) && Nat.is_le(List.length(&2, ResolvedNode, nodes), 32n) &&
    Nat.is_le(List.length(&2, Rule, rules), 32n) && rule_bounds(rules) && Nat.is_le(List.length(&2, Receipt, receipts), 256n)

def entry_ids(entries: +List<Finite.Entry(Graph)>) -> +List<Nat>:
  match entries:
    case Nil{}: Nil{}
    case Con{(key, value), rest}: key <> entry_ids(rest)

def contains_id(+id: Nat, ids: +List<Nat>) -> Bool:
  match ids:
    case Nil{}: False{}
    case Con{candidate, rest}: Nat.is_eq(id, candidate) || contains_id(id, rest)

def valid_entries(entries: +List<Finite.Entry(Graph)>, +next: Nat) -> Bool:
  match entries:
    case Nil{}: True{}
    case Con{(+id, graph), +rest}:
      Nat.is_lt(id, next) && Bool.not(contains_id(id, entry_ids(rest))) && valid_graph(graph) && valid_entries(rest, next)

def valid(+state: State) -> Bool:
  Nat.is_le(List.length(&2, Finite.Entry(Graph), graphs(state)), 32n) && valid_entries(graphs(state), next(state))

def capacity(state: State) -> Bool:
  Nat.is_lt(List.length(&2, Finite.Entry(Graph), graphs(state)), 32n)

# These are ordinary declaration producers; composition adds no interpreter case.
def existing(key: String, task: Nat) -> Node:
  Existing{key, task}

def spawn(key: String, profile: String, reasoning: String, message: String, settings: J.Json) -> Node:
  Spawn{key, profile, reasoning, message, settings}

def link(key: String, source: String, target: String, message: Message) -> Rule:
  Rule{key, source, [Action{target, message}]}

def compose(name: String, left: Declaration, right: Declaration) -> Declaration:
  Declaration{left_name, left_nodes, left_rules} = left
  Declaration{right_name, right_nodes, right_rules} = right
  Declaration{name, List.append(&2, Node, left_nodes, right_nodes), List.append(&2, Rule, left_rules, right_rules)}

def paired(name: String, +tests: Node, +implementation: Node, rule: String, message: Message) -> Declaration:
  Declaration{name, [tests, implementation], [link(rule, node_key(tests), node_key(implementation), message)]}
