import { parseJson } from './json-tokens.mjs';

// Called only at a tool's admitted native/extension boundary, or the MCP
// parsed-object boundary whose argument schema belongs to its server.
export function materializeCallArguments(call) {
  return parseJson(call.arguments_json);
}
