# test-support

This crate provides shared fixtures for Selvedge integration tests.

Use narrow feature flags so each test crate imports only the fixture layer it needs:

- `config` initializes a temporary Selvedge home and global config/logging state.
- `http` owns loopback server and port helpers with abort-on-drop server tasks.
- `chatgpt-auth` writes ChatGPT auth fixture files and unsigned JWT strings.
- `local-transport` provides a scripted local protocol transport for client and TUI tests.
- `db-fixtures` provides downstream database setup helpers.

The helpers are test infrastructure only. Protocol-specific mock behavior should remain in the test that owns the behavior contract.
