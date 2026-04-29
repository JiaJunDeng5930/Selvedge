# db

This crate owns SQLite persistence for router-mediated Selvedge tasks.

Use it to open a schema-v3 SQLite database, register global tools, create tasks, append history nodes while moving task cursors, queue user inputs, archive tasks, and read task-local model context.

This crate is for SQLite persistence only. Runtime wait state, provider calls, tool execution, router registries, and event delivery live in other crates.
