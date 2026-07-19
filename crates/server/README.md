# server

<!-- selvedge-package-readme
package: selvedge-server
freshness_fingerprint: c84391948c596454859584049473e1c4de963c0f
-->

This crate owns the process-local Selvedge server lifecycle.

Use it to start the server runtime, hold the singleton lock, initialize config and logging, open the SQLite database at `<selvedge_home>/selvedge.sqlite`, install the five built-in harness tools, discover configured stdio MCP tools, start events, client-sync, router, and optional web surface tasks, recover active task runtimes, and expose the in-process `ServerControl` used by local clients and UI surfaces.

`ServerStartArgs` uses the current `selvedge-api` boundary: server passes `ApiExecutorConfig` into the router, and provider selection remains inside each model-call request. It also receives the effective harness limits and MCP server map from the configuration boundary; the descendant limit is installed at database open and the per-fork limit is shared by tool schemas and parsing. This crate does not own a provider registry.

After opening SQLite, startup registers the exact harness manifests idempotently as global tools with durable Harness execution routes. It then connects configured MCP servers, discovers their complete tool catalogs, and atomically replaces the published global MCP set before constructing the unified executor. Discovery and catalog conflicts fail startup before task recovery. The shared MCP connections stay alive for concurrent calls and close after the supervised services stop.

Function-call history projections carry one JSON object and function outputs carry one JSON value unchanged across the command-model and local-protocol boundary. The server does not flatten arguments or stringify outputs.

The singleton lock is `<selvedge_home>/server.lock`. The lock file is removed during normal shutdown and startup-failure cleanup.

Config and logging initialization recognize repeated initialization through their typed `AlreadyInitialized` variants. Every other initialization error remains a startup failure.

This crate exposes the in-process control surface, validates localhost bind targets, and accepts attach requests after router-mediated events reservation succeeds.

`ServerControl::attach_client` creates an internal client frame channel, sends router attach admission, sends `StartHydration` to client-sync after admission succeeds, and returns a local-protocol frame stream. Frames from `selvedge-events` are converted from command-model client frames into local-protocol frames without reordering.

Active, hydrated, closing, and cancellable-operation attach data shares one
process-local state lock. Admission and cancellation decisions therefore observe
one atomic attach state.

## Package State Machine

Client command requests decode through the private, closed `ClientCommand` enum.
The exact `login-chatgpt` and `list-models` names both require an empty JSON object
payload; malformed payloads and unsupported names remain distinct rejection
paths. An exhaustive match dispatches both variants through the injected
`LocalOperationExecutor`. Operations are admitted only for an attached client,
run outside the router mailbox, and deliver terminal notice frames.

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([start server])
  Lock[Acquire singleton lock]
  InitConfig[Initialize config and logging]
  OpenDb[Open selvedge.sqlite]
  RegisterTools[Register five global tools with Harness execution routes]
  DiscoverMcp[Connect MCP servers and discover complete tool catalogs]
  PublishMcp[Atomically replace published global MCP tools]
  SpawnServices[Start events, client-sync, router, and web surface]
  Recover[Request active task runtime recovery]
  Ready[ServerControl ready]
  Probe[Handle ready probe]
  Submit[Validate local command request]
  Decode[Decode closed ClientCommand]
  Dispatch{Match ClientCommand variant}
  LocalOperation[Run server-owned local operation]
  Attach[Handle attach request]
  Hydrate[Start client hydration]
  Stop[Stop server]
  CloseMcp[Close MCP server connections]
  StartupFailure[Return startup error and cleanup]
  RequestFailure[Return control-surface error]
  Stopped[Server stopped]

  Start -->|startup called| Lock
  Lock -->|lock file opens and exclusive lock succeeds| InitConfig
  Lock -->|lock path, open, or exclusive lock fails| StartupFailure
  InitConfig -->|config and logging initialize or report typed AlreadyInitialized| OpenDb
  InitConfig -->|config or logging fails| StartupFailure
  OpenDb -->|SQLite opens at selected home| RegisterTools
  OpenDb -->|database open or schema setup fails| StartupFailure
  RegisterTools -->|all five definitions and Harness routes are new or exact repeats| DiscoverMcp
  RegisterTools -->|a definition conflicts or SQLite write fails| StartupFailure
  DiscoverMcp -->|all configured servers initialize and list supported tools| PublishMcp
  DiscoverMcp -->|transport, protocol, discovery, or definition validation fails| StartupFailure
  PublishMcp -->|complete MCP catalog commits atomically| SpawnServices
  PublishMcp -->|catalog route conflict or SQLite write fails| StartupFailure
  SpawnServices -->|events, client-sync, router, and optional web tasks start| Recover
  SpawnServices -->|any required task setup fails| StartupFailure
  Recover -->|router accepts the recovery scan| Ready
  Recover -->|router mailbox closes before accepting recovery| StartupFailure
  Ready -->|ready probe arrives| Probe
  Probe -->|server is ready| Ready
  Ready -->|command request arrives| Submit
  Submit -->|server is ready and protocol fields are valid| Decode
  Submit -->|server is not ready or protocol fields are invalid| RequestFailure
  Decode -->|exact supported name has an empty object payload| Dispatch
  Decode -->|payload is malformed or command name is unsupported| RequestFailure
  Dispatch -->|LoginChatgpt or ListModels passes operation admission| LocalOperation
  Dispatch -->|operation admission fails| RequestFailure
  LocalOperation -->|operation task starts and terminal notice will be delivered| Ready
  Ready -->|attach request arrives| Attach
  Attach -->|router reserves event session| Hydrate
  Attach -->|router admission rejects or channel creation fails| RequestFailure
  Hydrate -->|client-sync StartHydration send succeeds| Ready
  Hydrate -->|client-sync send fails| RequestFailure
  Ready -->|shutdown is requested or control is dropped| Stop
  Stop -->|supervised services have stopped| CloseMcp
  CloseMcp -->|connections close and lock file is removed| Stopped
  StartupFailure -->|normal cleanup removes lock file when owned| Stopped
```
