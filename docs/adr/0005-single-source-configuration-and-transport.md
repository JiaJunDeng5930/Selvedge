# ADR 0005: Single-source configuration and transport contracts

Status: Accepted

## Context

Configuration reads repeatedly serialized and validated the entire application, including when filtering log messages. Credential adapters repeated the storage envelope and atomic-write protocol because a lock guard could not perform store operations. HTTP request redirects rebuilt transports and re-encoded bodies. Local HTTP peers duplicated framing rules, while a successful snapshot could exceed the receiving peer's frame limit.

## Decision

Configuration updates build and validate a candidate effective snapshot and publish it only after the required persistence succeeds. Reads share that immutable snapshot. Configuration fields have one definition; overrides preserve dynamic map keys instead of treating every key segment as a case-insensitive schema field. Unused example-only fields and obsolete accepted fields are removed.

A credential store lock guard provides reads and atomic writes for the locked record. Refresh and login therefore reuse the same path, envelope and persistence implementation. A separately named atomic snapshot read is available only for the pre-lock refresh hint; it uses the same decoder and does not grant write access.

HTTP requests prepare body bytes once. Redirects retain those bytes and apply the existing header rules without reconstructing the original input. Reusable transports are identified by immutable connection settings and actual CA contents. Each call observes current configuration; CA replacement is observed by the next HTTPS call, while an in-flight redirect chain uses its selected transport settings.

The local client and web server delegate HTTP framing to Hyper. Application admission, timeouts and bounded NDJSON records remain application contracts. Sender and receiver use the same frame-size limit; oversized results end with a typed, bounded error rather than an oversized success record. Control identifiers also have a bounded size so correlated error records remain representable. Pagination is not introduced by this repair.

Test connection plans belong to connector instances. Test subprocesses must acknowledge that the expected case actually executed; a successful process exit with zero matching tests is insufficient evidence. Tests that reproduce implementation construction or maintain unreachable production states are removed or replaced with observable contract checks.

## Consequences

Changing shared configuration, credentials or event data no longer requires field-by-field updates in intermediate layers. Transport and credential boundaries retain typed errors until presentation. The local protocol deliberately supports bounded snapshots; clients receive a specific error for larger results.

Freshness remains an explicit documentation-review gate. Its fingerprint is not treated as proof of semantic correctness. Shared dependency versions and lint policy belong to the workspace; package-specific feature requirements remain local.
