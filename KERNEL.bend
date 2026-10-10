import Base
import ./harness/MODEL.bend as M
import ./harness/transport/PROGRAM.bend as Frontend
import ./harness/transport/MODEL.bend as Interface
import ./bendlib/json.bend as J

def initial() -> M.World():
  M.initial()

def packet(tokens: +List<String>, world: M.World()) -> Interface.Output:
  Frontend.packet(tokens, world)

def state(output: Interface.Output) -> M.World():
  Interface.state(output)

def envelope(output: Interface.Output) -> J.Json:
  Interface.envelope(output)

def show(value: J.Json) -> Result<&2, &2, String, String>:
  J.show(value)
