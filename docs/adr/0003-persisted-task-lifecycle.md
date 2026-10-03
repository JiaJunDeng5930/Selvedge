# ADR 0003: Persisted task lifecycle

Status: Accepted

## Context

Runtime-only freeze and stop flags disappear with their actor. They cannot explain task behavior after restart, and archive required router ordering exceptions because durable state and runtime control used different models.
