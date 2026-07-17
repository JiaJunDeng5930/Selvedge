# db

<!-- selvedge-package-readme
package: selvedge-db
freshness_fingerprint: 1474a0da8cc7e1c068edfd7cf1895740c9d77ad4
-->

This crate owns SQLite persistence for router-mediated Selvedge tasks.

Use it to open a schema-v6 SQLite database, migrate schema-v5 databases, register non-global or global harness tools, create root tasks, atomically fork child tasks from open function calls, commit task-runtime state transitions, queue user inputs, archive tasks, and read bounded task snapshots.

This crate is for SQLite persistence only. Runtime wait state, provider calls, tool execution, router registries, and event delivery live in other crates.

Resource boundaries:

- `create_history_node` inserts one history node. History parent links are a standalone graph.
- `create_root_task` inserts one task row at a caller-provided existing `cursor_node_id`. Task parent links and history parent links are separate graphs.
- Tool definitions store the complete input JSON Schema separately from a closed execution route. The current registration APIs create harness routes; a route can also represent one remote tool on a named MCP server.
- `register_global_tool` accepts a new harness definition, an exact harness repeat, or an exact non-global harness definition promoted to global. A conflicting schema, description, or route fails without changing the catalog.
- `unpublish_global_tool` changes only publication. The definition, execution route, task-specific references, and function-call history remain durable.
- `read_tool_manifest_for_task` merges database-marked global tools with that task's `task_tools` rows for active or archived tasks.
- `fork_task_from_function_call` requires an active parent and an exact open function-call identity on its current cursor path. It finds the history node before that call's contiguous function-call batch, appends the child user prompt there, copies the parent model profile, reasoning effort, and task-specific tools, and writes the parent edge in one transaction.
- `read_task` returns task identity, durable status, state version, cursor, optional parent, queued-input count, an exclusive `after_node_id` history page, and an exact `has_more` flag from one SQLite read transaction. Page limits are `1..=100`, and the after node must be on that task's cursor path.
- `read_task_parent_edges` returns durable task-layer parent edges for router snapshots and factory verification.
- A task cursor is a pointer into history, with no ownership claim over the pointed node.

Public transition writes keep cursor movement atomic with the history append they perform: user message commit, model reply with tool calls, assistant reply with queued-input drain, tool output with queued-input drain, queued input promotion, queue input, and archive.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([database API call])
  Open[Open SQLite database]
  Schema{stored schema state}
  Initialize[Create schema v6]
  Migrate[Migrate schema v5 to v6]
  SnapshotTx[Start read_task transaction]
  SnapshotValidate[Validate task, limit, and after node]
  SnapshotPage[Read metadata and cursor-path page]
  Read[Read other tasks, history, queues, tools, or projections]
  WriteTx[Start transition transaction]
  Validate[Validate durable preconditions]
  Commit[Commit transaction]
  Return[Return caller-visible result]
  OpenError[Return open or migration error]
  ReadError[Return read or decode error]
  ValidationError[Return invalid task, cursor, tool, publication, or state error]
  CommitError[Return commit database error]

  Start -->|open_db is called| Open
  Open -->|database has no application tables| Initialize
  Open -->|database has application tables and schema metadata is readable| Schema
  Open -->|SQLite open or schema metadata read fails| OpenError
  Schema -->|stored version is harness-persistence-v5| Migrate
  Schema -->|stored version is json-tool-foundation-v6| Return
  Schema -->|stored version is missing or unsupported| OpenError
  Initialize -->|schema-v6 batch succeeds| Return
  Initialize -->|schema creation fails| OpenError
  Migrate -->|schemas and argument objects are rebuilt, old flat tables are removed, and the version update commits| Return
  Migrate -->|migration transaction fails| OpenError
  Start -->|read_task is called with open connection| SnapshotTx
  SnapshotTx -->|transaction begins| SnapshotValidate
  SnapshotTx -->|transaction begin fails| ReadError
  SnapshotValidate -->|task exists, limit is 1 through 100, and after node is absent or on the cursor path| SnapshotPage
  SnapshotValidate -->|task is missing, limit is invalid, or after node is outside the cursor path| ValidationError
  SnapshotPage -->|metadata, count, parent, and page decode in the same snapshot| Commit
  SnapshotPage -->|query or stored value decode fails| ReadError
  Start -->|any other read API is called with open connection| Read
  Start -->|transition write API is called with open connection| WriteTx
  Read -->|query succeeds and rows decode to domain model| Return
  Read -->|query fails or stored enum, JSON, id, or argument value is invalid| ReadError
  WriteTx -->|transaction begins| Validate
  WriteTx -->|transaction begin fails| CommitError
  Validate -->|task, cursor, queue, history parent, exact global harness tool, publication, and fork-call preconditions hold| Commit
  Validate -->|requested transition conflicts with durable state| ValidationError
  Validate -->|read inside transaction fails| ReadError
  Commit -->|SQLite commit succeeds| Return
  Commit -->|SQLite commit fails| CommitError
```
