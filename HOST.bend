import Base
import ./bendlib/json.bend as J
import ./host/adapters/MODEL.bend as Model
import ./host/adapters/PROGRAM.bend as Program
import ./host/adapters/PROOF.bend as HostAdaptersProof

def decoded(operation: String, decoded: Result<&2, &2, String, J.Json>) -> J.Json:
  match decoded:
    case Fail{reason}: Model.failure_code("invalid_json", reason)
    case Done{source}: Program.run(operation, source)

def run(operation: String, tokens: +List<String>) -> String:
  J.stringify(decoded(operation, J.decode(tokens)))
