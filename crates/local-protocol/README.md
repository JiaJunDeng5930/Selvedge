# local-protocol

This crate defines the localhost protocol data model shared by the Selvedge server, root CLI, local client, TUI, and web client.

Use it for serializable ready probes, command submission envelopes, attach requests, attach responses, client subscriptions, client frames, snapshots, projections, events, and validation errors.

This crate does not access the network, database, filesystem, runtime, or mailbox. Transport limits, authentication, concrete command support, payload schemas, and task existence checks are enforced by the crates that own those boundaries.

Command rejection and attach rejection use separate reason enums. Attach rejection must cover protocol mismatch, malformed request, server not ready, duplicate active attach, client registry capacity exhaustion, router mailbox closure, client-sync unavailability, attach channel creation failure, and internal failure.
