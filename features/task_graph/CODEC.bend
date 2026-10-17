import Base
import ./MODEL.bend as G
import ../../harness/DOMAIN.bend as D
import ../../bendlib/json.bend as J
import ../../bendlib/stdlib.bend as Std
import ../../bendlib/association-map.bend as Finite
import ../../harness/transport/schema.bend as Schema

type WriteKind is Data:
  CreateKind{}
  UpdateKind{}
  DeleteKind{}

type ReadKind is Data:
  GraphsKind{}
  GraphKind{}

type EntryKind is Data:
  Write{kind: WriteKind}
  Read{kind: ReadKind}

type Spec is Data:
  Spec{name: String, description: String, kind: EntryKind, schema: J.Json}

def text_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"string"}}]}

def integer_schema() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"integer"}}, J.Field{"minimum", J.Number{"0"}}, J.Field{"maximum", J.Number{"4294967295"}}]}

def array_schema(items: J.Json) -> J.Json:
  J.Object{[J.Field{"type", J.Text{"array"}}, J.Field{"items", items}]}

def message_kinds() -> J.Json:
  J.Object{[J.Field{"type", J.Text{"string"}}, J.Field{"enum", J.Array{[J.Text{"output"}, J.Text{"literal"}, J.Text{"concat"}]}}]}

# The native schema fragment has no recursive references or discriminated unions.
# Inline its finite depth; raw admission below checks the exact variant fields.
def message_schema(depth: Nat) -> J.Json:
  match depth:
    case 0n: Schema.object([J.Field{"kind", message_kinds()}, J.Field{"value", text_schema()},
      J.Field{"parts", array_schema(Schema.object(Nil{}, Nil{}))}], [J.Text{"kind"}])
    case 1n+p: Schema.object([J.Field{"kind", message_kinds()}, J.Field{"value", text_schema()},
      J.Field{"parts", array_schema(message_schema(p))}], [J.Text{"kind"}])

def node_schema(task_settings: J.Json) -> J.Json:
  Schema.object([J.Field{"key", text_schema()}, J.Field{"task_id", integer_schema()}, J.Field{"profile", text_schema()},
    J.Field{"reasoning", text_schema()}, J.Field{"message", text_schema()}, J.Field{"settings", task_settings}], [J.Text{"key"}])

def action_schema() -> J.Json:
  Schema.object([J.Field{"target", text_schema()}, J.Field{"message", message_schema(7n)}], [J.Text{"target"}, J.Text{"message"}])

def rule_schema() -> J.Json:
  Schema.object([J.Field{"key", text_schema()}, J.Field{"source", text_schema()}, J.Field{"actions", array_schema(action_schema())}],
    [J.Text{"key"}, J.Text{"source"}, J.Text{"actions"}])

def declaration_properties(task_settings: J.Json) -> +List<J.Field>:
  [J.Field{"name", text_schema()}, J.Field{"nodes", array_schema(node_schema(task_settings))}, J.Field{"rules", array_schema(rule_schema())}]

def command_schema(properties: +List<J.Field>, required: +List<J.Json>) -> J.Json:
  Schema.object(J.Field{"op", text_schema()} <> properties, J.Text{"op"} <> required)

def specifications(+task_settings: J.Json) -> +List<Spec>:
  [Spec{"create_task_graph", "Create Tasks and install their output handlers atomically before scheduling them.", Write{CreateKind{}},
      command_schema(declaration_properties(task_settings), [J.Text{"name"}, J.Text{"nodes"}, J.Text{"rules"}])},
   Spec{"update_task_graph", "Replace a graph declaration atomically; retained Task references keep their existing settings and history.", Write{UpdateKind{}},
      command_schema(J.Field{"graph_id", integer_schema()} <> declaration_properties(task_settings),
        [J.Text{"graph_id"}, J.Text{"name"}, J.Text{"nodes"}, J.Text{"rules"}])},
   Spec{"delete_task_graph", "Remove a graph and its future output handlers without archiving its Tasks.", Write{DeleteKind{}},
      command_schema([J.Field{"graph_id", integer_schema()}], [J.Text{"graph_id"}])},
   Spec{"list_task_graphs", "Observe installed Task graphs, resolved Task references and latest delivery receipts.", Read{GraphsKind{}},
      command_schema(Nil{}, Nil{})},
   Spec{"read_task_graph", "Observe one installed Task graph, its rules and latest delivery receipts.", Read{GraphKind{}},
      command_schema([J.Field{"graph_id", integer_schema()}], [J.Text{"graph_id"}])}]

def find_spec(+name: String, specs: +List<Spec>) -> Maybe<&2, Spec>:
  match specs:
    case Nil{}: None{}
    case Con{Spec{+candidate, description, kind, schema}, rest}:
      Finite.choose(~Spec, String.eq(name, candidate), Spec{candidate, description, kind, schema}, find_spec(name, rest))

def lookup(name: String, task_settings: J.Json) -> Maybe<&2, Spec>:
  find_spec(name, specifications(task_settings))

def present(+body: J.Json, key: String) -> Bool:
  match body:
    case J.Object{fields}: Schema.exists(fields, key)
    case _: False{}

def optional_text(+body: J.Json, +key: String) -> Bool:
  Bool.not(present(body, key)) || J.is_text(J.get(body, key))

def optional_settings(+body: J.Json) -> Bool:
  Bool.not(present(body, "settings")) || J.is_object(J.get(body, "settings"))

def is_array(value: J.Json) -> Bool:
  match value:
    case J.Array{values}: True{}
    case _: False{}

def natural(value: J.Json) -> Bool:
  Schema.valid(integer_schema(), value)

def valid_node_variant(existing: Bool, +node: J.Json) -> Bool:
  match existing:
    case True{}: Schema.keys(node, ["key", "task_id"]) && J.is_text(J.get(node, "key")) && natural(J.get(node, "task_id"))
    case False{}: Schema.keys(node, ["key", "profile", "reasoning", "message", "settings"]) &&
      J.is_text(J.get(node, "key")) && optional_text(node, "profile") && optional_text(node, "reasoning") &&
      optional_text(node, "message") && optional_settings(node)

def valid_node(+node: J.Json) -> Bool:
  valid_node_variant(present(node, "task_id"), node)

def valid_nodes(limit: Nat, nodes: +List<J.Json>) -> Bool:
  match limit nodes:
    case 0n Nil{}: True{}
    case 0n Con{node, rest}: False{}
    case 1n+p Nil{}: True{}
    case 1n+p Con{node, rest}: valid_node(node) && valid_nodes(p, rest)

type MessageCheck is Data:
  CheckMessage{depth: Nat, kind: String, value: J.Json}
  CheckParts{depth: Nat, values: +List<J.Json>}

def message_job(depth: Nat, +value: J.Json) -> MessageCheck:
  CheckMessage{depth, J.text(J.get(value, "kind")), value}

def message_check(fuel: Nat, job: MessageCheck) -> Bool:
  match fuel job:
    case 0n _: False{}
    case 1n+p CheckMessage{0n, kind, value}: False{}
    case 1n+p CheckMessage{1n+depth, kind, +value}:
      match kind:
        case "output": Schema.keys(value, ["kind"])
        case "literal": Schema.keys(value, ["kind", "value"]) && J.is_text(J.get(value, "value"))
        case "concat": Schema.keys(value, ["kind", "parts"]) && is_array(J.get(value, "parts")) &&
          message_check(p, CheckParts{depth, J.items(J.get(value, "parts"))})
        case _: False{}
    case 1n+p CheckParts{depth, Nil{}}: True{}
    case 1n+ +p CheckParts{+depth, Con{value, rest}}:
      message_check(p, message_job(depth, value)) && message_check(p, CheckParts{depth, rest})

def valid_action(+action: J.Json) -> Bool:
  Schema.keys(action, ["target", "message"]) && J.is_text(J.get(action, "target")) &&
    message_check(256n, message_job(8n, J.get(action, "message")))

def valid_actions(limit: Nat, actions: +List<J.Json>) -> Bool:
  match limit actions:
    case 0n Nil{}: True{}
    case 0n Con{action, rest}: False{}
    case 1n+p Nil{}: True{}
    case 1n+p Con{action, rest}: valid_action(action) && valid_actions(p, rest)

def valid_rule(+rule: J.Json) -> Bool:
  Schema.keys(rule, ["key", "source", "actions"]) && J.is_text(J.get(rule, "key")) &&
    J.is_text(J.get(rule, "source")) && is_array(J.get(rule, "actions")) && valid_actions(8n, J.items(J.get(rule, "actions")))

def valid_rules(limit: Nat, rules: +List<J.Json>) -> Bool:
  match limit rules:
    case 0n Nil{}: True{}
    case 0n Con{rule, rest}: False{}
    case 1n+p Nil{}: True{}
    case 1n+p Con{rule, rest}: valid_rule(rule) && valid_rules(p, rest)

def valid_declaration(+body: J.Json) -> Bool:
  J.is_text(J.get(body, "name")) && is_array(J.get(body, "nodes")) && is_array(J.get(body, "rules")) &&
    valid_nodes(32n, J.items(J.get(body, "nodes"))) && valid_rules(32n, J.items(J.get(body, "rules")))

# The editor validates the same declaration body before attaching its operation.
def operation_matches(+body: J.Json, name: String) -> Bool:
  Bool.not(present(body, "op")) || J.same(J.get(body, "op"), J.Text{name})

def valid(kind: WriteKind, +body: J.Json) -> Bool:
  match kind:
    case CreateKind{}: Schema.keys(body, ["op", "name", "nodes", "rules"]) &&
      operation_matches(body, "create_task_graph") && valid_declaration(body)
    case UpdateKind{}: Schema.keys(body, ["op", "graph_id", "name", "nodes", "rules"]) &&
      operation_matches(body, "update_task_graph") && natural(J.get(body, "graph_id")) && valid_declaration(body)
    case DeleteKind{}: Schema.keys(body, ["op", "graph_id"]) && operation_matches(body, "delete_task_graph") && natural(J.get(body, "graph_id"))

def entry_valid(kind: EntryKind, +body: J.Json) -> Bool:
  match kind:
    case Write{kind}: valid(kind, body)
    case Read{GraphsKind{}}: Schema.keys(body, ["op"]) && operation_matches(body, "list_task_graphs")
    case Read{GraphKind{}}: Schema.keys(body, ["op", "graph_id"]) && operation_matches(body, "read_task_graph") && natural(J.get(body, "graph_id"))

def number(value: J.Json) -> Nat:
  J.natural_or(J.natural(value), 0n)

def settings(value: J.Json) -> J.Json:
  match value:
    case J.Object{fields}: J.Object{fields}
    case _: J.Object{Nil{}}

def node_variant(existing: Bool, +body: J.Json) -> G.Node:
  match existing:
    case True{}: G.Existing{J.text(J.get(body, "key")), number(J.get(body, "task_id"))}
    case False{}: G.Spawn{J.text(J.get(body, "key")), J.text(J.get(body, "profile")), J.text_or(J.get(body, "reasoning"), "default"),
      J.text(J.get(body, "message")), settings(J.get(body, "settings"))}

def node(+body: J.Json) -> G.Node:
  node_variant(present(body, "task_id"), body)

def nodes(values: +List<J.Json>) -> +List<G.Node>:
  Std.map(~J.Json, ~G.Node, ~(value => node(value)), values)

def read_message(fuel: Nat, job: MessageCheck) -> +List<G.Message>:
  match fuel job:
    case 0n _: Nil{}
    case 1n+p CheckMessage{0n, kind, value}: Nil{}
    case 1n+p CheckMessage{1n+depth, kind, +value}:
      match kind:
        case "output": [G.Output{}]
        case "literal": [G.Literal{J.text(J.get(value, "value"))}]
        case "concat": [G.Concat{read_message(p, CheckParts{depth, J.items(J.get(value, "parts"))})}]
        case _: Nil{}
    case 1n+p CheckParts{depth, Nil{}}: Nil{}
    case 1n+ +p CheckParts{+depth, Con{value, rest}}:
      List.append(&2, G.Message, read_message(p, message_job(depth, value)), read_message(p, CheckParts{depth, rest}))

def first_message(values: +List<G.Message>) -> G.Message:
  match values:
    case Nil{}: G.Output{}
    case Con{value, rest}: value

def message(body: J.Json) -> G.Message:
  first_message(read_message(256n, message_job(8n, body)))

def action(+body: J.Json) -> G.Action:
  G.Action{J.text(J.get(body, "target")), message(J.get(body, "message"))}

def actions(values: +List<J.Json>) -> +List<G.Action>:
  Std.map(~J.Json, ~G.Action, ~(value => action(value)), values)

def rule(+body: J.Json) -> G.Rule:
  G.Rule{J.text(J.get(body, "key")), J.text(J.get(body, "source")), actions(J.items(J.get(body, "actions")))}

def rules(values: +List<J.Json>) -> +List<G.Rule>:
  Std.map(~J.Json, ~G.Rule, ~(value => rule(value)), values)

def declaration(+body: J.Json) -> G.Declaration:
  G.Declaration{J.text(J.get(body, "name")), nodes(J.items(J.get(body, "nodes"))), rules(J.items(J.get(body, "rules")))}

def construct(kind: WriteKind, +body: J.Json) -> G.Command:
  match kind:
    case CreateKind{}: G.Create{declaration(body)}
    case UpdateKind{}: G.Update{number(J.get(body, "graph_id")), declaration(body)}
    case DeleteKind{}: G.Delete{number(J.get(body, "graph_id"))}

def query(kind: ReadKind, body: J.Json) -> G.Query:
  match kind:
    case GraphsKind{}: G.ListGraphs{}
    case GraphKind{}: G.ReadGraph{number(J.get(body, "graph_id"))}

def node_json(node: G.Node) -> J.Json:
  match node:
    case G.Existing{key, task}: J.Object{[J.Field{"key", J.Text{key}}, J.Field{"task_id", J.nat(task)}]}
    case G.Spawn{key, profile, reasoning, message, settings}: J.Object{[J.Field{"key", J.Text{key}},
      J.Field{"profile", J.Text{profile}}, J.Field{"reasoning", J.Text{reasoning}}, J.Field{"message", J.Text{message}}, J.Field{"settings", settings}]}

type MessageOutput is Data:
  WriteMessage{depth: Nat, value: G.Message}
  WriteParts{depth: Nat, values: +List<G.Message>}

def write_message(fuel: Nat, job: MessageOutput) -> +List<J.Json>:
  match fuel job:
    case 0n _: Nil{}
    case 1n+p WriteMessage{0n, value}: Nil{}
    case 1n+p WriteMessage{1n+depth, G.Output{}}: [J.Object{[J.Field{"kind", J.Text{"output"}}]}]
    case 1n+p WriteMessage{1n+depth, G.Literal{text}}:
      [J.Object{[J.Field{"kind", J.Text{"literal"}}, J.Field{"value", J.Text{text}}]}]
    case 1n+p WriteMessage{1n+depth, G.Concat{parts}}:
      [J.Object{[J.Field{"kind", J.Text{"concat"}}, J.Field{"parts", J.Array{write_message(p, WriteParts{depth, parts})}}]}]
    case 1n+p WriteParts{depth, Nil{}}: Nil{}
    case 1n+ +p WriteParts{+depth, Con{value, rest}}:
      List.append(&2, J.Json, write_message(p, WriteMessage{depth, value}), write_message(p, WriteParts{depth, rest}))

def first_json(values: +List<J.Json>) -> J.Json:
  match values:
    case Nil{}: J.Null{}
    case Con{value, rest}: value

def message_json(value: G.Message) -> J.Json:
  first_json(write_message(256n, WriteMessage{8n, value}))

def action_json(action: G.Action) -> J.Json:
  G.Action{target, message} = action
  J.Object{[J.Field{"target", J.Text{target}}, J.Field{"message", message_json(message)}]}

def rule_json(rule: G.Rule) -> J.Json:
  G.Rule{key, source, actions} = rule
  J.Object{[J.Field{"key", J.Text{key}}, J.Field{"source", J.Text{source}},
    J.Field{"actions", J.Array{Std.map(~G.Action, ~J.Json, ~action_json, actions)}}]}

def declaration_fields(declaration: G.Declaration) -> +List<J.Field>:
  G.Declaration{name, nodes, rules} = declaration
  [J.Field{"name", J.Text{name}}, J.Field{"nodes", J.Array{Std.map(~G.Node, ~J.Json, ~node_json, nodes)}},
    J.Field{"rules", J.Array{Std.map(~G.Rule, ~J.Json, ~rule_json, rules)}}]

def command(op: String, fields: +List<J.Field>) -> J.Json:
  J.Object{J.Field{"op", J.Text{op}} <> fields}

def command_json(input: G.Command) -> J.Json:
  match input:
    case G.Create{declaration}: command("create_task_graph", declaration_fields(declaration))
    case G.Update{id, declaration}: command("update_task_graph", J.Field{"graph_id", J.nat(id)} <> declaration_fields(declaration))
    case G.Delete{id}: command("delete_task_graph", [J.Field{"graph_id", J.nat(id)}])

def query_json(input: G.Query) -> J.Json:
  match input:
    case G.ListGraphs{}: command("list_task_graphs", Nil{})
    case G.ReadGraph{id}: command("read_task_graph", [J.Field{"graph_id", J.nat(id)}])

def resolved_node_json(node: G.ResolvedNode) -> J.Json:
  G.ResolvedNode{key, task} = node
  J.Object{[J.Field{"key", J.Text{key}}, J.Field{"task_id", J.nat(task)}]}

def receipt_json(receipt: G.Receipt) -> J.Json:
  G.Receipt{source, rule, target, reply} = receipt
  J.Object{[J.Field{"source_task_id", J.nat(source)}, J.Field{"rule", J.Text{rule}},
    J.Field{"target_task_id", J.nat(target)}, J.Field{"reply", reply}]}

def graph_fields(id: Nat, graph: G.Graph) -> +List<J.Field>:
  G.Graph{name, nodes, rules, receipts} = graph
  [J.Field{"graph_id", J.nat(id)}, J.Field{"name", J.Text{name}},
    J.Field{"nodes", J.Array{Std.map(~G.ResolvedNode, ~J.Json, ~resolved_node_json, nodes)}},
    J.Field{"rules", J.Array{Std.map(~G.Rule, ~J.Json, ~rule_json, rules)}},
    J.Field{"receipts", J.Array{Std.map(~G.Receipt, ~J.Json, ~receipt_json, receipts)}}]

def graph_json(id: Nat, graph: G.Graph) -> J.Json:
  J.Object{graph_fields(id, graph)}

def graph_entry_json(entry: Finite.Entry(G.Graph)) -> J.Json:
  (id, graph) = entry
  graph_json(id, graph)

def found_graph(id: Nat, found: Maybe<&2, G.Graph>) -> J.Json:
  match found:
    case None{}: D.failure("not_found", "Task graph does not exist.")
    case Some{graph}: D.success(graph_json(id, graph))

def query_reply(input: G.Query, state: G.State) -> J.Json:
  match input:
    case G.ListGraphs{}: D.success(J.Object{[J.Field{"graphs", J.Array{Std.map(~Finite.Entry(G.Graph), ~J.Json, ~graph_entry_json, G.graphs(state))}}]})
    case G.ReadGraph{+id}: found_graph(id, G.find(state, id))
