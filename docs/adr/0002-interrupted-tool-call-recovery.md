# ADR 0002: Interrupted tool-call recovery

Status: Accepted

## Context

After an interruption, a function call without a committed output does not prove that its effects did not occur. Retrying every open call can duplicate effects, including messages and external commands. Forked task histories can also inherit open calls that were intended for another branch.

## Decision

Each task-owned tool contract freezes a recovery policy with the tool definition. A tool is retry-safe only when repeating it cannot duplicate an observable effect, including when its effects and output commit atomically. All other tools have an unknown outcome after interruption; whether a tool is internal or external does not determine the policy.

At actor startup, retry-safe open calls resume normally. For an open call with an unknown outcome, the actor does not invoke the executor. It commits an ordinary error output explaining the uncertainty and continues the model loop, allowing the model to inspect relevant state and call the tool again only when needed.

## Consequences

Interrupted and branch-inherited calls do not automatically duplicate uncertain effects. Recovery remains durable and follows the task's original tool contract across restarts. Some interrupted operations may require model-driven reconciliation because the system cannot provide exactly-once execution across independently committed effects and history outputs.
