import Base
import ../../bendlib/component.bend as Component
import ../DOMAIN.bend as D
import ../MODEL.bend as M
import ../../bendlib/json.bend as J
import ./wire.bend as Wire
import ../protocol/COMMIT.bend as Commit
import ../execution/PROGRAM.bend as Execution

# The pure native protocol: malformed packets cannot mutate a world or acquire
# durability. Accepted packets have the complete independently specified input
# meaning, including output admission. Transport itself only supplies tokens.
type Output is Data:
  Output{decision: M.Decision(), durable: Bool}

def invalid(code: String, reason: String, world: M.World()) -> Output:
  Output{Component.Decision{world, D.failure(code, reason), Nil{}}, False{}}

def input(input: Result<&2, &2, String, M.Input>, world: M.World()) -> Output:
  match input:
    case Fail{reason}: invalid("invalid_input", reason, world)
    case Done{+input}:
      Output{Commit.input(~Execution.scheduled, input, world), M.durable(input)}

def json(json: Result<&2, &2, String, J.Json>, world: M.World()) -> Output:
  match json:
    case Fail{reason}: invalid("invalid_json", reason, world)
    case Done{json}: input(Wire.decode(json), world)

def packet(tokens: +List<String>, world: M.World()) -> Output:
  json(J.decode(tokens), world)

def state(output: Output) -> M.World():
  Output{Component.Decision{world, reply, effects}, durable} = output
  world

def envelope(output: Output) -> J.Json:
  Output{decision, durable} = output
  Wire.envelope(durable, decision)
