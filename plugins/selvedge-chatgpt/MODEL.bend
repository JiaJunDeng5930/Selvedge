import Base
import ../../bendlib/json.bend as J
import ../../host/adapters/MODEL.bend as Model
import ../../host/adapters/PLUGINS.bend as Plugins
import ../../host/adapters/plugins-proof.bend as PluginsProof

def decoded(operation: String, value: Result<&2, &2, String, J.Json>) -> J.Json:
  match value:
    case Fail{reason}: Model.failure_code("invalid_json", reason)
    case Done{source}: Plugins.run(operation, source)

def rendered(value: Result<&2, &2, String, String>) -> String:
  match value:
    case Done{text}: text
    case Fail{reason}: "{\"ok\":false,\"error\":\"Host model JSON rendering failed\",\"code\":\"invalid_output\"}"

def run(operation: String, tokens: +List<String>) -> String:
  rendered(J.show(decoded(operation, J.decode(tokens))))
