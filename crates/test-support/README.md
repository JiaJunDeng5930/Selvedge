# test-support

<!-- selvedge-package-readme
package: selvedge-test-support
freshness_commit: f2a0e6aa7f63b0fb8b575fefc5026e0535a7e64f
-->

This crate provides shared fixtures for Selvedge integration tests.

Use narrow feature flags so each test crate imports only the fixture layer it needs:

- `config` initializes a temporary Selvedge home and global config/logging state.
- `http` owns loopback server and port helpers with abort-on-drop server tasks.
- `chatgpt-auth` writes ChatGPT auth fixture files and unsigned JWT strings.
- `local-transport` provides a scripted local protocol transport for client and TUI tests.
- `db-fixtures` provides downstream database setup helpers.

The helpers are test infrastructure only. Protocol-specific mock behavior stays in the test that owns the behavior contract.

## Package State Machine

The diagram records the package-level observable fixture states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([Test requests shared fixture])
  Feature{Feature selected}
  Process[Child process fixture]
  Config[Temporary config home]
  Http[Loopback HTTP server or port]
  Auth[ChatGPT auth file or JWT]
  Db[In-memory database fixture]
  LocalTransport[Scripted local transport]
  Ready[Return fixture handle or value]
  FixturePanic[Fail calling test during fixture setup]

  Start -->|process helpers are always compiled| Process
  Start -->|caller enables a fixture feature| Feature
  Feature -->|config| Config
  Feature -->|http| Http
  Feature -->|chatgpt-auth| Auth
  Feature -->|db-fixtures| Db
  Feature -->|local-transport| LocalTransport
  Process -->|current test binary is spawned or inspected| Ready
  Config -->|temp home, config file, config state, and logging initialize| Ready
  Http -->|loopback listener binds and server task starts| Ready
  Auth -->|auth JSON or unsigned JWT is created| Ready
  Db -->|database schema and fixture rows are created| Ready
  LocalTransport -->|scripted state and response queues are installed| Ready
  Process -->|child process cannot spawn or exits unsuccessfully| FixturePanic
  Config -->|tempdir, file, config, or logging setup fails| FixturePanic
  Http -->|loopback bind or server setup fails| FixturePanic
  Auth -->|auth fixture write fails| FixturePanic
  Db -->|database or fixture row creation fails| FixturePanic
  LocalTransport -->|scripted connection setup fails| FixturePanic
```
