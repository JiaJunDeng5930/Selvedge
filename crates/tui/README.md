# tui

This crate owns the TUI startup boundary for attaching to an existing Selvedge local server.

Use it to connect through `selvedge-local-client`, probe readiness, open an attach stream, wait for the first snapshot, submit an optional initial command, and return a typed exit status.

The current entry point is generic over `LocalTransport` because the repository has not yet implemented the real localhost transport below `selvedge-local-client`.
