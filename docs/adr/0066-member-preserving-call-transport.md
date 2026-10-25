# ADR 0066: Preserve call members until tool admission

## Context

The domain JSON AST records object members in order, including repeated names,
and retains each numeric token's spelling. Sending this AST as an ordinary
JavaScript object erased repeated names before before-tool hooks and the final
tool schema could inspect them. Rejecting repeated names at the provider would
also reject calls that a hook could repair and impose native policy on MCP.
[RFC 8259 sections 4 and 6](https://www.rfc-editor.org/rfc/rfc8259.html#section-4)
describe the interoperability differences for repeated names and the precision
limits of common number implementations.

## Decision

Use one internal call wire projection with `arguments_json` text. The owning
`Foundation.CallWire` codec shares its declaration, object admission and bounded member
parser across providers and the kernel. Decoding consumes the original logical
callback nesting budget even though physical transport now contains a string.
The core still owns the ordered AST; the wire text is derived from that AST.

Parameterize `Codec.message_json_with` by the call projection. Internal history and
effects use the wire projection. Public messages retain their display projection
and expose derived argument text for exact auditing. Display messages are not
accepted by the internal call decoder. Existing side quotations remain text
rendered inside the core.

Materialize parsed objects only at the explicit native, extension, hook or MCP
protocol boundary. Approval reviewer prompts retain their external command object
projection; the core renders that projection to text before provider transport. Native and extension admission follows before-tool rewrites;
MCP retains its server-owned schema. `materializeCallArguments` uses the existing
number-preserving JSON codec. Allow keeps the original core call and rewrite
replaces its arguments while retaining identity and origin.

Transport byte budgets measure the escaped wire representation. Image selection
observes the original AST. Evaluator previews remove private continuations before
truncation and text encoding, and apply the final encoded-byte bound afterwards.
ChatGPT Web v1 retains its external object argument protocol. Its raw JSON/SSE
entry text-encodes only that subtree before strict protocol parsing, so repeated
protocol fields still fail while tool-owned members survive. Cached resources
use the internal shape; the Web request store therefore advances to format 2.
The current journal also changes with this transport. Old records are rejected
rather than decoded through a second argument authority.
