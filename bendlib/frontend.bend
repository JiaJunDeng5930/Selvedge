import Base
import ../MODEL.bend as M
import ../PROGRAM.bend as P
import ./json.bend as J
import ./wire.bend as Wire
import ./interface.bend as Interface

def input(input: Result<&2, &2, String, M.Input>, world: M.World) -> Interface.Output:
  match input:
    case Fail{reason}:
      Interface.Output{P.reject(world, "invalid_input", reason), False{}}
    case Done{+input}:
      Interface.Output{P.transition(input, world), Wire.durable(input)}

def json(json: Result<&2, &2, String, J.Json>, world: M.World) -> Interface.Output:
  match json:
    case Fail{reason}:
      Interface.Output{P.reject(world, "invalid_json", reason), False{}}
    case Done{json}: input(Wire.decode(json), world)

def packet(tokens: +List<String>, world: M.World) -> Interface.Output:
  json(J.decode(tokens), world)
