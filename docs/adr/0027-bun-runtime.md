# ADR 0027: Bun runtime

## Decision

Use Bun 1.4.2 for the host, JavaScript compilation drivers, maintenance scripts,
and developer and CI entry points. Keep one Bun lockfile and the exact
`gpt-tokenizer` 4.0.0 dependency. Install frozen dependencies without lifecycle
scripts. Server startup explicitly builds before launching the CLI.

## Reason

A single runtime removes Node version admission and compiler V8 launch flags,
and keeps local setup and CI on the same executable contract. Bun provides the
host library interfaces already used by this repository, so their `node:` import
names do not require a second runtime or an adapter layer.

## Boundaries

The runtime change preserves worker isolation, SQLite transactions and journal
locking, subprocess groups, and native transport. Bend continues to own task
policy and proof obligations. The optional native Bend build remains available.
Historical validation records describe the runtime used at the time; this
migration does not establish that the unchanged test suite has passed on Bun.
