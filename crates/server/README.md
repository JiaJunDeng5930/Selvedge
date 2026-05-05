# server

This crate owns the process-local Selvedge server lifecycle.

Use it to start the server runtime, hold the singleton lock, initialize config and logging, open the SQLite database at `<selvedge_home>/selvedge.sqlite`, start events, client-sync, router, and optional web surface tasks, and expose the in-process `ServerControl` used by local clients and UI surfaces.

`ServerStartArgs` uses the current `selvedge-api` boundary: server passes `ApiExecutorConfig` into the router, and provider selection remains inside each model-call request. This crate does not own a provider registry.

The singleton lock is `<selvedge_home>/server.lock`. The lock file is removed during normal shutdown and startup-failure cleanup.

This crate exposes the in-process control surface, validates localhost bind targets, and accepts attach requests by sending hydration starts into `selvedge-client-sync`.

`ServerControl::attach_client` creates an internal client frame channel, sends `StartHydration` to client-sync, and returns a local-protocol frame stream. Frames from `selvedge-events` are converted from command-model client frames into local-protocol frames without reordering.
