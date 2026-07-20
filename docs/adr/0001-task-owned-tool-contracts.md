# ADR 0001: Task-owned tool contracts

Status: Accepted

## Context

A mutable global tool catalog lets configuration and MCP discovery changes alter the definitions presented for an existing task. Its history can then disagree with its current tools, and otherwise stable provider request prefixes lose cache reuse. Runtime availability still changes independently when a backing tool disappears or returns.

## Decision

Each root task stores one ordered, immutable snapshot of its complete `ToolSpec` values, execution routes, and harness limits. Forked tasks inherit that snapshot exactly. The database has no global tool catalog.

Each task separately stores an unavailable-tool exception set, empty by default. Runtime reconciliation changes only this set. Model dispatch always carries the complete frozen manifest plus a provider-neutral callable subset; provider adapters translate the subset to their native selection mechanism, such as OpenAI `tool_choice.allowed_tools`.

## Consequences

Existing task definitions and request prefixes remain stable across restarts and configuration changes. An unavailable tool remains defined in history but cannot be selected or executed. MCP routes become available only when the discovered definition and route exactly match the frozen contract. This is a schema break with no compatibility or migration path.
