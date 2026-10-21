# 0060: Preserve distinct tool protocol contracts

Date: 2026-10-21
Status: Accepted

## Context

An extension descriptor deliberately uses a small schema language. MCP instead
advertises JSON Schema and makes the server responsible for input validation.
Using the extension interpreter for both protocols made a legal MCP tool with a
numeric parameter prevent Selvedge from starting. Applying that same interpreter
to replies and hook rewrites also changed which calls could reach the server.

A shared JSON representation does not make these contracts interchangeable.
Tool origin was previously implicit in free JSON metadata, separate from the
schema admission that it needed to govern.

## Decision

Make origin a domain alternative that carries the corresponding native program,
extension identity or MCP server identity. Derive the existing wire metadata
from that value. This associates each tool with its argument contract without
maintaining a second origin flag or changing the public tool DTO.

Keep the small extension interpreter for extension tools. Admit MCP's object
schemas and send object arguments to the server for full validation. Implementing
another complete JSON Schema interpreter would duplicate server responsibility
and add an unnecessary compatibility burden. Native tools retain admission from
their shared command declarations. All paths that admit or rewrite calls use the same
origin distinction.

Advance the single current journal format to `selvedge-rocq-journal-3`. A reply
that the previous local fragment interpreter rejected can now produce an MCP
execution request, so replaying an older decision stream is not equivalent.
Reject earlier formats explicitly; do not add a second runtime or fallback.

## Evidence and limits

The public regression scenario starts the complete service with an official SDK
MCP server, exercises numeric and referenced parameters, and checks actual calls
and server errors. The same schema remains rejected for extension descriptors.
The uncorrected production baseline fails the MCP startup scenario.

Checked results constrain admission and the actual execution request. Schema
validation by an external MCP server, transport delivery and tool execution
remain external responsibilities. Successful local admission does not establish
that those external operations succeed.

Reference: [MCP Tools, protocol revision 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/server/tools).
