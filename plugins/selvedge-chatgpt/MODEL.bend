import Base
import ../../bendlib/json.bend as J
import ../../host/adapters/MODEL.bend as Model
import ../../host/adapters/PLUGINS.bend as Plugins
import ../../host/adapters/plugins-proof.bend as PluginsProof

def decoded(operation: String, value: Result<&2, &2, String, J.Json>) -> J.Json:
  match value:
    # DEFENSE: MCP requests and connection-file JSON can violate the shared token decoder's grammar or bounds.
    case Fail{reason}: Model.failure_code("invalid_json", reason)
    case Done{source}: Plugins.run(operation, source)

def run(operation: String, tokens: +List<String>) -> String:
  J.stringify(decoded(operation, J.decode(tokens)))
