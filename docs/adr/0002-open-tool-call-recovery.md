# ADR 0002: Open tool-call recovery

Status: Accepted

## Context

A function call without a committed output may have been interrupted after its effects occurred. It may also have been inherited by a child history when `fork_task` and the call appeared in the same model turn without being executed on that branch. Retrying every open call can therefore duplicate messages, commands, and other effects.

## Decision

Each task-owned tool contract freezes a recovery policy with the tool definition. A tool is retry-safe only when repeating it cannot duplicate an observable effect, including when its effects and output commit atomically. Whether a tool is internal or external does not determine the policy.

At actor startup, retry-safe open calls resume normally. For any other open call, the actor does not invoke the executor. It commits an ordinary `tool_outcome_unknown` error output that explains both interruption and fork inheritance, then continues the model loop so the model can inspect relevant state and call the tool again only when needed.

## Consequences

Interrupted and branch-inherited calls do not automatically duplicate uncertain effects. Recovery remains durable and follows the task's original tool contract across restarts. Some calls require model-driven reconciliation because the system does not distinguish an interrupted execution from a call inherited without execution on that branch.
