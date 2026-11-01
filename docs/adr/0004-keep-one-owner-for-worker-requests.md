# Keep one owner for Worker requests

Status: accepted

## Context

The Kernel host serializes requests to one Worker. Its pending promise, timeout,
failure and closing fields govern that physical conversation. The Worker wrapper
returns one response for each received request. A failed or timed-out Worker is
retired permanently.

The same host also advanced a second `Host.Transaction` state. All its actions
were discarded except the request generation. This repeated the queue's existing
ownership while giving the impression that the transaction model controlled
Worker admission and retirement.

## Decision

Use the serialized promise and its pending response as the Worker request owner.
Remove the unused transaction transitions and generation round trip. Retain the
failure check for responses arriving after timeout or journal retirement. A later
request cannot start before the preceding response, and retirement prevents
another request from using an uncertain world.

The Journal retains its transaction controller: its actions select durable
commit, publication and retirement. Physical effects retain their independent
handles because several operations can run concurrently and finish out of order.

## Consequences

The Worker conversation has one state owner and carries no unused correlation
identifier. Public service, journal recovery, input refusal and cancellation
acceptance remain the evidence for the host's actual IO behavior. Node's Worker
message delivery and the wrapper's one-response construction remain runtime
assumptions; an identifier would add no protection against a faulty runtime.

Reference: [Node Worker messaging](https://nodejs.org/api/worker_threads.html#event-message).
