# ADR 0053: load external tool definitions through committed results

## Context

Sending every MCP and plugin parameter schema consumes model context before the
model needs those tools. Task contracts already freeze a catalog independently
of current route availability and approvals. Reusing a changing set of loaded
definitions as permission state would confuse those separate responsibilities.

Claude Code keeps tool search resident and defers full definitions. Claude's API
expands `tool_reference` results at their conversation position and excludes
deferred definitions from the rendered tool-prefix cache key. Selvedge's current
Responses and ChatGPT Web transports have ordinary function declarations and
results, without that reference expansion facility.

## Decision

Keep native definitions resident and expose a stable lightweight declaration for
each frozen external tool. Its name preserves the existing invocation route;
its bounded description provides a directory entry. The permissive object schema
is a provider presentation, while execution continues using the frozen descriptor
and its existing source-specific validation.

Tasks whose frozen catalog has no discovery capability retain their complete
definitions: hiding those schemas would leave them without a loading entry.
The capability is identified by its source program rather than a reserved name.

Return complete external definitions through the resident discovery tool's
ordinary committed result. Exact public names bypass keyword selection and page
limits so a known tool remains reachable even when keyword search misses it.

Discovery appends history rather than changing the request's tool declarations
or inserting definitions earlier in the conversation. This preserves the model
context prefix across discovery and invocation. Inherited history and journal
replay already carry the results, so no persistent loaded-tools state is needed.
Compaction may omit an old result; the model can request the definition again.

## References

- [Claude Code MCP tool search](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search)
- [Tool search](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool)
- [Tool references and caching](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-reference)
