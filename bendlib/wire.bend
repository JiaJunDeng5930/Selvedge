import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ./json.bend as J
import ./schema.bend as Schema
import ./tasks.bend as T
import ./presentation.bend as View

# This module converts untrusted values into domain constructors. The host wraps
# public commands; only trusted host paths may construct completion/config inputs.
def choose_spec(same: Bool, spec: M.CommandSpec, rest: Maybe<&2, M.CommandSpec>) -> Maybe<&2, M.CommandSpec>:
  match same:
    case True{}: Some{spec}
    case False{}: rest

def find_spec(specs: +List<M.CommandSpec>, +name: String) -> Maybe<&2, M.CommandSpec>:
  match specs:
    case Nil{}: None{}
    case Con{M.CommandSpec{+key, +description, +kind, +schema}, rest}:
      choose_spec(String.eq(key, name), M.CommandSpec{key, description, kind, schema}, find_spec(rest, name))

def text_or(value: J.Json, fallback: String) -> String:
  match value:
    case J.Text{text}: text
    case _: fallback

def construct_command(kind: M.CommandKind, +body: J.Json) -> M.Command:
  match kind:
    case M.CreateCommand{}:
      M.Create{J.text(J.get(body, "profile")), text_or(J.get(body, "reasoning"), "medium"), J.text(J.get(body, "message"))}
    case M.SendCommand{}:
      M.Send{P.argument_nat(body, "task_id", 0n), J.text(J.get(body, "message"))}
    case M.ControlCommand{control}:
      M.ChangeStatus{P.argument_nat(body, "task_id", 0n), control}
    case M.ForkCommand{}:
      M.Fork{P.argument_nat(body, "task_id", 0n), P.argument_nat(body, "child_count", 0n),
        P.decode_messages(J.items(J.get(body, "messages")))}
    case M.ReadCommand{}:
      M.Observe{M.Read{P.argument_nat(body, "task_id", 0n), P.argument_nat(body, "after", 0n), P.argument_nat(body, "limit", 100n)}}
    case M.ListCommand{}: M.Observe{M.ListTasks{}}
    case M.DescribeCommand{}: M.Observe{M.Describe{}}

def command_valid(valid: Bool, kind: M.CommandKind, body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Command does not satisfy its declared schema"}
    case True{}: Done{M.UserCommand{construct_command(kind, body)}}

def command_spec(found: Maybe<&2, M.CommandSpec>, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match found:
    case None{}: Fail{"Unknown command; use describe for the executable vocabulary"}
    case Some{M.CommandSpec{name, description, kind, schema}}:
      command_valid(Schema.valid(schema, body), kind, body)

def decode_command(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  command_spec(find_spec(M.commands(), J.text(J.get(body, "op"))), body)

def is_some(value: Maybe<&2, Nat>) -> Bool:
  match value:
    case Some{n}: True{}
    case None{}: False{}

def is_natural(value: J.Json) -> Bool:
  match value:
    case J.Number{lexeme}: is_some(Nat.read(lexeme))
    case _: False{}

def item_kind(kind: String, +value: J.Json) -> M.ModelItem:
  match kind:
    case "call": M.Invoke{M.Call{J.text(J.get(value, "id")), J.text(J.get(value, "name")), J.get(value, "arguments")}}
    case "context": M.Context{J.get(value, "value")}
    case _: M.Say{J.text(J.get(value, "text"))}

def model_items(values: +List<J.Json>) -> +List<M.ModelItem>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      item_kind(J.text(J.get(value, "type")), value) <> model_items(rest)

def valid_item_kind(kind: String, +value: J.Json) -> Bool:
  match kind:
    case "text": J.is_text(J.get(value, "text"))
    case "call": J.is_text(J.get(value, "id")) && J.is_text(J.get(value, "name")) && J.is_object(J.get(value, "arguments"))
    case "context": J.is_object(J.get(value, "value"))
    case _: False{}

def valid_items(values: +List<J.Json>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}: valid_item_kind(J.text(J.get(value, "type")), value) && valid_items(rest)

def is_array(value: J.Json) -> Bool:
  match value:
    case J.Array{values}: True{}
    case _: False{}

def is_bool(value: J.Json) -> Bool:
  match value:
    case J.Boolean{boolean}: True{}
    case _: False{}

def model_outcome(ok: Bool, +body: J.Json) -> M.Outcome:
  match ok:
    case True{}: M.ModelReply{model_items(J.items(J.get(body, "items")))}
    case False{}: M.ModelFailure{J.text(J.get(body, "message"))}

def valid_model_payload(ok: Bool, +body: J.Json) -> Bool:
  match ok:
    case True{}: is_array(J.get(body, "items")) && valid_items(J.items(J.get(body, "items")))
    case False{}: J.is_text(J.get(body, "message"))

def model_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed model completion"}
    case True{}:
      Done{M.ModelCompleted{P.argument_nat(body, "task_id", 0n), P.argument_nat(body, "ticket", 0n),
        model_outcome(J.boolean(J.get(body, "ok")), body)}}

def decode_model(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  model_valid(is_natural(J.get(body, "task_id")) && is_natural(J.get(body, "ticket")) &&
    is_bool(J.get(body, "ok")) && valid_model_payload(J.boolean(J.get(body, "ok")), body), body)

def tool_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed tool completion"}
    case True{}:
      Done{M.ToolCompleted{P.argument_nat(body, "task_id", 0n), P.argument_nat(body, "ticket", 0n),
        J.get(body, "value"), J.boolean(J.get(body, "error"))}}

def decode_tool(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  tool_valid(is_natural(J.get(body, "task_id")) && is_natural(J.get(body, "ticket")) && is_bool(J.get(body, "error")), body)

def profile_values(values: +List<J.Json>) -> +List<M.Profile>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      M.Profile{J.text(J.get(value, "key")), J.text(J.get(value, "provider")), J.text(J.get(value, "name"))} <> profile_values(rest)

def valid_profiles(values: +List<J.Json>, +seen: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}:
      +key = J.text(J.get(value, "key"))
      M.nonempty(key) && M.nonempty(J.text(J.get(value, "provider"))) && M.nonempty(J.text(J.get(value, "name"))) &&
        Bool.not(T.has_name(seen, key)) && valid_profiles(rest, key <> seen)

def remote_tools(values: +List<J.Json>) -> +List<M.Tool>:
  match values:
    case Nil{}: Nil{}
    case Con{+value, rest}:
      M.Tool{J.text(J.get(value, "name")), J.text(J.get(value, "description")), J.get(value, "schema"),
        M.Mcp{J.text(J.get(value, "server")), J.text(J.get(value, "remote"))}} <> remote_tools(rest)

def valid_remote_tools(values: +List<J.Json>, +seen: +List<String>) -> Bool:
  match values:
    case Nil{}: True{}
    case Con{+value, rest}:
      +name = J.text(J.get(value, "name"))
      M.nonempty(name) && String.starts_with(name, "mcp__") && Bool.not(T.has_name(seen, name)) &&
        M.nonempty(J.text(J.get(value, "description"))) && J.is_object(J.get(value, "schema")) &&
        M.nonempty(J.text(J.get(value, "server"))) && M.nonempty(J.text(J.get(value, "remote"))) &&
        valid_remote_tools(rest, name <> seen)

def config_valid(valid: Bool, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match valid:
    case False{}: Fail{"Malformed environment: profiles/routes must be unique and limits must be positive integers"}
    case True{}:
      +max_fork = P.argument_nat(body, "max_fork", 0n)
      Done{M.Configure{M.Environment{List.append(&2, M.Tool, M.builtins(max_fork), remote_tools(J.items(J.get(body, "tools")))),
        profile_values(J.items(J.get(body, "profiles"))), max_fork, P.argument_nat(body, "max_descendants", 0n)}}}

def decode_config(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  config_valid(is_array(J.get(body, "profiles")) && valid_profiles(J.items(J.get(body, "profiles")), Nil{}) &&
    is_array(J.get(body, "tools")) && valid_remote_tools(J.items(J.get(body, "tools")), Nil{}) &&
    is_natural(J.get(body, "max_fork")) && Nat.is_le(1n, P.argument_nat(body, "max_fork", 0n)) &&
    is_natural(J.get(body, "max_descendants")) && Nat.is_le(1n, P.argument_nat(body, "max_descendants", 0n)), body)

def decode_kind(kind: String, +body: J.Json) -> Result<&2, &2, String, M.Input>:
  match kind:
    case "command": decode_command(J.get(body, "command"))
    case "model": decode_model(body)
    case "tool": decode_tool(body)
    case "configure": decode_config(body)
    case "recover": Done{M.Recover{}}
    case "continue": Done{M.Continue{}}
    case _: Fail{"Unknown input envelope"}

def decode(+body: J.Json) -> Result<&2, &2, String, M.Input>:
  decode_kind(J.text(J.get(body, "kind")), body)

def durable(input: M.Input) -> Bool:
  M.durable(input)

def envelope(durable: Bool, decision: M.Decision) -> J.Json:
  View.envelope(durable, decision)
