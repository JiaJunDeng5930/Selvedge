# ADR 0003: Persisted task lifecycle

Status: Accepted

## Context

Runtime-only freeze and stop flags disappear with their actor. They cannot explain task behavior after restart, and archive required router ordering exceptions because durable state and runtime control used different models.

## Decision

Each task stores exactly one lifecycle status: `active`, `frozen`, `stopped`, or `archived`. New tasks are active. Active tasks may freeze or stop. Frozen tasks resume only through unfreeze. Stopped tasks resume when they commit a new user input. Any non-archived task may archive, and archived tasks never resume.

Active, frozen, and stopped tasks own actors. A frozen actor retains its process-local mailbox without consuming it. A stopped actor commits incoming work and completes already-issued tool calls but does not request another model turn. Archived tasks reject runtime creation.

The database is the lifecycle source of truth. Runtime control only wakes an actor after a status change or shuts the actor down; it does not mirror task status in memory.

## Consequences

Restart preserves task behavior. Lifecycle transitions no longer depend on deferred-command inspection. Persisted queued user inputs survive archive, while frozen mailbox entries remain process-local. This is a schema break with no compatibility or migration path.
