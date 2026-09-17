# tui

<!-- selvedge-package-readme
package: selvedge-tui
freshness_fingerprint: f3b6a94e7b1cb11ea0cb806a477142379322639e
-->

This crate owns the TUI startup boundary for attaching to an existing Selvedge local server.

Use it to connect through `selvedge-local-client`, probe readiness, open an attach stream, wait for the first snapshot, submit an optional initial command, close the client, and return a typed exit status. This entry point performs startup and an optional one-shot submission; it does not run an interactive terminal loop.

`run_tui` connects through the concrete HTTP localhost transport exposed by
`selvedge-local-client`. Transport injection stays private to state-machine
tests. Client and attach command identifiers are validated before the transport
connects.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([TUI startup])
  Connect[Connect local client]
  ReadyProbe[Probe server readiness]
  Attach[Open attach stream]
  WaitSnapshot[Wait for first snapshot frame]
  SubmitInitial[Submit optional initial command]
  Exited[Close client and return Exited]
  ConnectError[Return connect error]
  ReadyError[Return server-unready error]
  AttachError[Return attach error]
  SnapshotError[Return snapshot wait error]
  SubmitError[Return initial command submit error]

  Start -->|startup function is called| Connect
  Connect -->|LocalConnector connect succeeds| ReadyProbe
  Connect -->|connect fails| ConnectError
  ReadyProbe -->|ready response says server ready| Attach
  ReadyProbe -->|ready request fails or server reports unready| ReadyError
  Attach -->|attach accepted and frame stream opens| WaitSnapshot
  Attach -->|attach rejected or stream open fails| AttachError
  WaitSnapshot -->|snapshot frame arrives| SubmitInitial
  WaitSnapshot -->|event or notice arrives before snapshot| WaitSnapshot
  WaitSnapshot -->|stream ends, deadline expires, or transport fails before snapshot| SnapshotError
  SubmitInitial -->|no initial command configured| Exited
  SubmitInitial -->|initial command submit succeeds| Exited
  SubmitInitial -->|initial command submit fails| SubmitError
```
