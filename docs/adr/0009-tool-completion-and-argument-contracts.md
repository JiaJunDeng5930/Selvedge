# ADR 0009: Tool completion authority and argument contracts

Status: Accepted

## Context

Durable command environments introduced a second way to commit a tool result.
The task actor inspected environment admission and selected a database commit
function, although admission consistency belongs to the transaction that writes
the result. Changing that consistency rule consequently required coordinated
changes in the actor and database.

An admitted invocation can finish after its task has been archived. The previous
implementation temporarily changed the task status inside the transaction to
pass ordinary history-write checks. This preserved the externally visible status
but made completion depend on an artificial lifecycle transition. Scoped and
ordinary command entry points also repeated some underlying history updates.

Tool argument names, types, optionality and bounds were maintained separately in
JSON schemas, parsers and script command signatures. Extending a parameter could
leave those representations inconsistent even when command execution itself had
not changed.

## Decision

Represent persistence completion separately from ownership of runtime resources.
A tool result owns its completion state, including any environment lease; the
database receives a borrowed persistence description through one result-commit
entry point. The database validates admission and commits all associated changes
in the same transaction. The task actor preserves the resource lifetime through
that call without interpreting command-environment admission.

Represent permission to finish an admitted invocation independently of task
lifecycle status. Establish that permission inside the committing transaction,
bind it to the exact invocation and task, and grant it only to the caller and
pending children belonging to that invocation. Ordinary history writes retain
their ordinary lifecycle checks. Both paths use shared transaction operations
for history, cursor and queue changes; scope checks, deduplication and deferred
lifecycle decisions remain responsibilities of their respective entry points.

Define tool fields and value domains once in typed argument declarations.
Generate schema, parsing and script parameter signatures from those declarations.
Keep checks involving multiple fields on their argument entity, and keep task
permissions and recovery policy outside argument syntax. Interfaces share an
argument entity only when their argument meanings and defaults agree.

## Consequences

Changing command admission or its atomic commit no longer requires the task actor
to choose a command-specific commit path. Resource ownership still prevents a
shared environment from being reused before its outer result is committed.
Completing admitted work does not require changing the task's lifecycle state.

Changing a shared parameter field or bound updates its schema, validation and
script description together. Tool implementations continue to own their behavior
and recovery policy. This change preserves the model-facing protocol and current
database format; it does not introduce a plugin registry or another persisted
representation of the same rules.
