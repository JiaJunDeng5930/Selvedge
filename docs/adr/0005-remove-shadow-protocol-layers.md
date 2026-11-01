# ADR 0005: Remove protocol layers without a behavioral owner

Date: 2026-11-01
Status: Accepted

## Context

The relay and connector admit frames as part of their current session transition.
A second set of exported frame validators, adapter routes and codecs had no
production callers. A forwarding module added another name for each session
operation without contributing a contract. HTTP admission also returned a state
and a singleton action list, although every call supplied the initial state and
discarded the resulting state.

The installed plugin checked regular-file, no-follow and size observations again
after its shared descriptor reader had already established those properties.
Its setup command additionally rejected relative paths and new package directories
inside the source tree, although the package copies an explicit file list.

## Decision

Keep wire declarations at the actual session boundary and call each session owner
directly. Remove the unused validators, adapter routes, codecs and forwarding
module. Model HTTP admission as one decision from the supplied observation; it
does not retain facts between requests. Socket attachments continue to retain
the session identity, grants and tickets needed across hibernation, following
the [Cloudflare attachment lifecycle](https://developers.cloudflare.com/durable-objects/best-practices/websockets/).

Let the shared bounded descriptor reader establish file kind, no-follow access
and size once. Plugin admission owns the additional private-file permissions,
owner and configuration-field requirements. Accept explicitly supplied relative
paths with the ordinary [Node filesystem convention](https://nodejs.org/api/fs.html#file-paths)
of resolving them from the process working directory. Packaging may create a new
directory inside the source tree because its fixed copy list cannot include that
output or unrelated private files. Exclusive directory creation still prevents
overwriting an existing source or deployment directory.

## Consequences

There is one admitted execution path for each remote session observation and one
owner for each plugin file property. Removing the unused surfaces does not create
a compatibility obligation. Packaging remains an explicit export of shipped
files, with the same no-follow regular-file reads and private-data exclusion.
