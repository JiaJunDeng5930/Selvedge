# db

This crate owns SQLite persistence for router-mediated Selvedge tasks.

Use it to open a schema-v4 SQLite database, register global tools, create tasks, commit task-runtime state transitions, queue user inputs, archive tasks, and read task-local model context.

This crate is for SQLite persistence only. Runtime wait state, provider calls, tool execution, router registries, and event delivery live in other crates.

Public writes are transition-sized: user message commit, model reply with tool calls, assistant reply with queued-input drain, tool output with queued-input drain, queue input, and archive. Single-node history insertion is an internal helper so callers do not split cursor movement across multiple transactions.
