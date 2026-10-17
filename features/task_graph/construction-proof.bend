import Base
import ../../bendlib/categories.bend as Categories
import ../../bendlib/logic-proof.bend as Logic
import ./MODEL.bend as G

def checked_left(+left: Bool, +right: Bool, evidence: {(left && right) == True{} : Bool}) ->
  {left == True{} : Bool}:
  match left:
    case True{}: {==}
    case False{}: evidence

def checked_right(+left: Bool, +right: Bool, evidence: {(left && right) == True{} : Bool}) ->
  {right == True{} : Bool}:
  match left:
    case True{}: evidence
    case False{}: Logic.impossible({right == True{} : Bool}, evidence)

def checked_both(+left: Bool, +right: Bool, first: {left == True{} : Bool}, second: {right == True{} : Bool}) ->
  {(left && right) == True{} : Bool}:
  Equal.trans(Bool, left && right, True{} && right, True{},
    Equal.cong(Bool, Bool, (value => value && right), left, True{}, first), second)

def admitted_identifiers(-declaration: G.Declaration, evidence: G.admissible(declaration)) ->
  {G.identifiers(declaration) == True{} : Bool}:
  Categories.Intersection{identity, remainder} = evidence
  identity

def admitted_references(-declaration: G.Declaration, evidence: G.admissible(declaration)) ->
  {G.references(declaration) == True{} : Bool}:
  Categories.Intersection{identity, Categories.Intersection{references, bounds}} = evidence
  references

def admitted_bounded(-declaration: G.Declaration, evidence: G.admissible(declaration)) ->
  {G.bounded(declaration) == True{} : Bool}:
  Categories.Intersection{identity, Categories.Intersection{references, bounds}} = evidence
  bounds

def admitted_wellformed(+declaration: G.Declaration, evidence: G.admissible(declaration)) ->
  {G.wellformed(declaration) == True{} : Bool}:
  Categories.Intersection{identity, Categories.Intersection{references, bounds}} = evidence
  checked_both(G.identifiers(declaration) && G.references(declaration), G.bounded(declaration),
    checked_both(G.identifiers(declaration), G.references(declaration), identity, references), bounds)

# These eliminators bind structural admission to actual graph endpoint checks.
def head_source_declared(+key: String, +source: String, +actions: +List<G.Action>, +rest: +List<G.Rule>, +keys: +List<String>,
  evidence: {G.rule_references(G.Rule{key, source, actions} <> rest, keys) == True{} : Bool}) ->
  {G.contains(source, keys) == True{} : Bool}:
  checked_left(G.contains(source, keys), G.action_references(actions, keys),
    checked_left(G.contains(source, keys) && G.action_references(actions, keys), G.rule_references(rest, keys), evidence))

def later_rules_declared(+key: String, +source: String, +actions: +List<G.Action>, +rest: +List<G.Rule>, +keys: +List<String>,
  evidence: {G.rule_references(G.Rule{key, source, actions} <> rest, keys) == True{} : Bool}) ->
  {G.rule_references(rest, keys) == True{} : Bool}:
  checked_right(G.contains(source, keys) && G.action_references(actions, keys), G.rule_references(rest, keys), evidence)

def head_target_declared(+target: String, +message: G.Message, +rest: +List<G.Action>, +keys: +List<String>,
  evidence: {G.action_references(G.Action{target, message} <> rest, keys) == True{} : Bool}) ->
  {G.contains(target, keys) == True{} : Bool}:
  checked_left(G.contains(target, keys), G.action_references(rest, keys), evidence)

def later_actions_declared(+target: String, +message: G.Message, +rest: +List<G.Action>, +keys: +List<String>,
  evidence: {G.action_references(G.Action{target, message} <> rest, keys) == True{} : Bool}) ->
  {G.action_references(rest, keys) == True{} : Bool}:
  checked_right(G.contains(target, keys), G.action_references(rest, keys), evidence)

def admitted_head_source(+name: String, +nodes: +List<G.Node>, +key: String, +source: String,
  +actions: +List<G.Action>, +rest: +List<G.Rule>,
  evidence: G.admissible(G.Declaration{name, nodes, G.Rule{key, source, actions} <> rest})) ->
  {G.contains(source, G.node_keys(nodes)) == True{} : Bool}:
  head_source_declared(key, source, actions, rest, G.node_keys(nodes),
    admitted_references(G.Declaration{name, nodes, G.Rule{key, source, actions} <> rest}, evidence))

def admitted_head_target(+name: String, +nodes: +List<G.Node>, +key: String, +source: String,
  +target: String, +message: G.Message, +actions: +List<G.Action>, +rest: +List<G.Rule>,
  evidence: G.admissible(G.Declaration{name, nodes, G.Rule{key, source, G.Action{target, message} <> actions} <> rest})) ->
  {G.contains(target, G.node_keys(nodes)) == True{} : Bool}:
  +keys = G.node_keys(nodes)
  +source_check = G.contains(source, keys)
  +action_check = G.action_references(G.Action{target, message} <> actions, keys)
  +tail_check = G.rule_references(rest, keys)
  +references = admitted_references(G.Declaration{name, nodes, G.Rule{key, source, G.Action{target, message} <> actions} <> rest}, evidence)
  head_target_declared(target, message, actions, keys,
    checked_right(source_check, action_check, checked_left(source_check && action_check, tail_check, references)))

def admitted_head_message(+name: String, +nodes: +List<G.Node>, +key: String, +source: String,
  +target: String, +message: G.Message, +actions: +List<G.Action>, +rest: +List<G.Rule>,
  evidence: G.admissible(G.Declaration{name, nodes, G.Rule{key, source, G.Action{target, message} <> actions} <> rest})) ->
  {G.valid_message(message) == True{} : Bool}:
  +bounds = admitted_bounded(G.Declaration{name, nodes, G.Rule{key, source, G.Action{target, message} <> actions} <> rest}, evidence)
  +rule_bounds = checked_right(
    Nat.is_le(List.length(&2, G.Node, nodes), 32n) && Nat.is_le(List.length(&2, G.Rule, G.Rule{key, source, G.Action{target, message} <> actions} <> rest), 32n),
    G.rule_bounds(G.Rule{key, source, G.Action{target, message} <> actions} <> rest), bounds)
  +action_bounds = checked_right(Nat.is_le(List.length(&2, G.Action, G.Action{target, message} <> actions), 8n),
    G.action_bounds(G.Action{target, message} <> actions),
    checked_left(Nat.is_le(List.length(&2, G.Action, G.Action{target, message} <> actions), 8n) &&
      G.action_bounds(G.Action{target, message} <> actions), G.rule_bounds(rest), rule_bounds))
  checked_left(G.valid_message(message), G.action_bounds(actions), action_bounds)

def composition(+name: String, +left_name: String, +left_nodes: +List<G.Node>, +left_rules: +List<G.Rule>,
  +right_name: String, +right_nodes: +List<G.Node>, +right_rules: +List<G.Rule>) ->
  {G.compose(name, G.Declaration{left_name, left_nodes, left_rules}, G.Declaration{right_name, right_nodes, right_rules}) ==
    G.Declaration{name, List.append(&2, G.Node, left_nodes, right_nodes), List.append(&2, G.Rule, left_rules, right_rules)} : G.Declaration}:
  {==}

def paired_handoff(+name: String, +tests: G.Node, +implementation: G.Node, +rule: String, +message: G.Message) ->
  {G.paired(name, tests, implementation, rule, message) ==
    G.Declaration{name, [tests, implementation], [G.Rule{rule, G.node_key(tests), [G.Action{G.node_key(implementation), message}]}]} : G.Declaration}:
  {==}

def initial_valid() -> {G.valid(G.initial()) == True{} : Bool}:
  {==}

def checked_correspondence(+declaration: G.Declaration, +identity: Bool, +links: Bool, +bounds: Bool,
  identity_evidence: {G.identifiers(declaration) == identity : Bool},
  links_evidence: {G.references(declaration) == links : Bool},
  bounds_evidence: {G.bounded(declaration) == bounds : Bool}) ->
  {G.construction_result(G.construct_checked(declaration, identity, links, bounds, identity_evidence, links_evidence, bounds_evidence)) ==
    G.selected(identity && links && bounds, declaration) : Maybe<&2, G.Declaration>}:
  match identity links bounds:
    case False{} _ _: {==}
    case True{} False{} _: {==}
    case True{} True{} False{}: {==}
    case True{} True{} True{}: {==}

def construction_correspondence(+declaration: G.Declaration) ->
  {G.construction_result(G.construct(declaration)) == G.selected(G.wellformed(declaration), declaration) : Maybe<&2, G.Declaration>}:
  checked_correspondence(declaration, G.identifiers(declaration), G.references(declaration), G.bounded(declaration), {==}, {==}, {==})

def admission() -> G.AdmissionBoundary:
  G.AdmissionBoundary{construction_correspondence, admitted_wellformed}
