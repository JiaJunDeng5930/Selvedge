import Base
import ./bendlib/json.bend as J
import ./host/adapters/MODEL.bend as Model
import ./host/adapters/PROGRAM.bend as Program
import ./host/adapters/PROOF.bend as HostAdaptersProof

def decoded(operation: String, decoded: Result<&2, &2, String, J.Json>) -> J.Json:
  match decoded:
    case Fail{reason}: Model.failure_code("invalid_json", reason)
    case Done{source}: Program.run(operation, source)

def rendered(rendered: Result<&2, &2, String, String>) -> String:
  match rendered:
    case Done{text}: text
    case Fail{reason}: "{\"ok\":false,\"error\":\"Host model JSON rendering failed\",\"code\":\"invalid_output\"}"

def run(operation: String, tokens: +List<String>) -> String:
  rendered(J.show(decoded(operation, J.decode(tokens))))
