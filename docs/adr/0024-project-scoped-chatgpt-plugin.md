# 0024: Project-scoped ChatGPT connections

## Context

ChatGPT must operate local files through explicitly shared Selvedge projects.
The grant belongs to an MCP connection across conversations. Reusing a task's
frozen tool contract would attach that authority to a conversation. Exposing the
administrative command API would permit arbitrary Workspace and policy overrides.
Official OpenAI Secure MCP Tunnel reaches private stdio MCP servers without public
HTTP ingress. Its registered ChatGPT connection ID exists only after deployment.

## Decision

Keep the MCP package independent of the native model. A dedicated loopback
credential selects a configured connection; secrets and tunnel identities do not
enter the model or journal. The native feature owns project membership, operation
resolution, ownership, deduplication and durable outcomes. Its interpreter refines
independent complete-decision equations and preserves unrelated feature state.

Accepted operations capture the project's current Workspace and the connection's
restricted sandbox. They commit before Bash launches. Retained request IDs prevent
duplicate dispatch after lost responses. Recovery marks running work as uncertain
instead of replaying it. Cancellation requests a physical stop without claiming
to undo writes.

Plugin execution grants reads to captured roots, private scratch space and explicit
system runtimes. Ordinary task reads remain unchanged: sharing a project must not
implicitly share the rest of the filesystem.

The source package declares local stdio MCP through `mcp.json`. Installed clients
read a private, owned configuration under `PLUGIN_DATA`; arbitrary environment
inheritance is not a portable contract. Direct Tunnel launches can use explicit
connection environment variables. Deployment packaging binds a real ChatGPT app
ID and omits the local MCP declaration to avoid duplicate tool routes. Neither
package embeds credentials or a fictitious registered ID.

## Consequences

Configuration needs existing project IDs and takes effect on startup. External
dependencies outside a shared Workspace require an explicit sharing decision.
OS adapters, the native compiler, SQLite, MCP transport and OpenAI Tunnel remain
external assumptions. Integration tests cover local dispatch, filesystem
isolation, credential separation and restart. Live ChatGPT/Tunnel validation
requires a real associated tunnel and runtime key.
