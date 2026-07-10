# tui

<!-- selvedge-package-readme
package: selvedge-tui
freshness_fingerprint: 744f0e9817aa51b5f25d0257a078d19d098bb453
-->

This crate owns the TUI startup boundary for attaching to an existing Selvedge local server.

Use it to connect through `selvedge-local-client`, probe readiness, open an attach stream, wait for the first snapshot, submit an optional initial command, and return a typed exit status.

`run_tui` connects through the concrete HTTP localhost transport exposed by
`selvedge-local-client`. Transport injection stays private to state-machine
tests.

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
  Running[Return running exit status]
  ConnectError[Return connect error]
  ReadyError[Return server-unready error]
  AttachError[Return attach error]
  SnapshotError[Return snapshot wait error]
  SubmitError[Return initial command submit error]

  Start -->|startup function is called| Connect
  Connect -->|LocalTransport connect succeeds| ReadyProbe
  Connect -->|connect fails| ConnectError
  ReadyProbe -->|ready response says server ready| Attach
  ReadyProbe -->|ready request fails or server reports unready| ReadyError
  Attach -->|attach accepted and frame stream opens| WaitSnapshot
  Attach -->|attach rejected or stream open fails| AttachError
  WaitSnapshot -->|first frame is snapshot| SubmitInitial
  WaitSnapshot -->|stream ends, yields notice, yields event, or transport fails before snapshot| SnapshotError
  SubmitInitial -->|no initial command configured| Running
  SubmitInitial -->|initial command submit succeeds| Running
  SubmitInitial -->|initial command submit fails| SubmitError
```
