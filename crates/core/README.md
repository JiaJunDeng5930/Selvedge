# core

This crate runs one task runtime actor per active task.

Use it to spawn a task-local runtime that loads SQLite state through `selvedge-db`, appends history, queues input while busy, requests model calls through the router, requests tool execution through the router, and exits on archive or database errors.

This crate only talks to the router mailbox and the database package. Provider calls, tool execution, event fanout, runtime registry ownership, and direct client delivery live in other crates.
