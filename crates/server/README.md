# server

<!-- selvedge-package-readme
package: selvedge-server
freshness_fingerprint: 35b8aa34f1874aef8f5e58fddbcbf3a57581efc6
-->

This crate owns the process-local Selvedge server lifecycle.

Use it to start the server runtime, hold the singleton lock, initialize config and logging, open the SQLite database at `<selvedge_home>/selvedge.sqlite`, start events, client-sync, router, and optional web surface tasks, and expose the in-process `ServerControl` used by local clients and UI surfaces.

`ServerStartArgs` uses the current `selvedge-api` boundary: server passes `ApiExecutorConfig` into the router, and provider selection remains inside each model-call request. This crate does not own a provider registry.

The singleton lock is `<selvedge_home>/server.lock`. The lock file is removed during normal shutdown and startup-failure cleanup.

Config and logging initialization recognize repeated initialization through their typed `AlreadyInitialized` variants. Every other initialization error remains a startup failure.

This crate exposes the in-process control surface, validates localhost bind targets, and accepts attach requests after router-mediated events reservation succeeds.

`ServerControl::attach_client` creates an internal client frame channel, sends router attach admission, sends `StartHydration` to client-sync after admission succeeds, and returns a local-protocol frame stream. Frames from `selvedge-events` are converted from command-model client frames into local-protocol frames without reordering.

Active, hydrated, closing, and cancellable-operation attach data shares one
process-local state lock. Admission and cancellation decisions therefore observe
one atomic attach state.

## Package State Machine

Server-owned local commands execute through the injected `LocalOperationExecutor`.
`list-models` and provider login operations are admitted only for an attached
client, run outside the router mailbox, and deliver terminal notice frames.

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([start server])
  Lock[Acquire singleton lock]
  InitConfig[Initialize config and logging]
  OpenDb[Open selvedge.sqlite]
  SpawnServices[Start events, client-sync, router, and web surface]
  Ready[ServerControl ready]
  Probe[Handle ready probe]
  Submit[Handle local command]
  LocalOperation[Run server-owned local operation]
  RouterCommand[Send router command]
  Attach[Handle attach request]
  Hydrate[Start client hydration]
  Stop[Stop server]
  StartupFailure[Return startup error and cleanup]
  RequestFailure[Return control-surface error]
  Stopped[Server stopped]

  Start -->|startup called| Lock
  Lock -->|lock file opens and exclusive lock succeeds| InitConfig
  Lock -->|lock path, open, or exclusive lock fails| StartupFailure
  InitConfig -->|config and logging initialize or report typed AlreadyInitialized| OpenDb
  InitConfig -->|config or logging fails| StartupFailure
  OpenDb -->|SQLite opens at selected home| SpawnServices
  OpenDb -->|database open or schema setup fails| StartupFailure
  SpawnServices -->|events, client-sync, router, and optional web tasks start| Ready
  SpawnServices -->|any required task setup fails| StartupFailure
  Ready -->|ready probe arrives| Probe
  Probe -->|server is ready| Ready
  Ready -->|command request arrives| Submit
  Submit -->|command name is server-owned and attach admission is satisfied| LocalOperation
  Submit -->|router accepts command send| RouterCommand
  Submit -->|command validation or router send fails| RequestFailure
  LocalOperation -->|operation task starts and terminal notice will be delivered| Ready
  LocalOperation -->|operation admission or task startup fails| RequestFailure
  RouterCommand -->|router mailbox accepts command| Ready
  Ready -->|attach request arrives| Attach
  Attach -->|router reserves event session| Hydrate
  Attach -->|router admission rejects or channel creation fails| RequestFailure
  Hydrate -->|client-sync StartHydration send succeeds| Ready
  Hydrate -->|client-sync send fails| RequestFailure
  Ready -->|shutdown is requested or control is dropped| Stop
  Stop -->|tasks stop and lock file is removed| Stopped
  StartupFailure -->|normal cleanup removes lock file when owned| Stopped
```
