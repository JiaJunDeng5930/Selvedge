# Keep one owner for serialized host requests

Status: accepted

## Context

The Journal serializes requests to one Worker through the complete transaction.
The Kernel host's pending promise, timeout, failure and closing fields govern
that physical conversation. The Worker wrapper
returns one response for each received request. A failed or timed-out Worker is
retired permanently.

The same host also advanced a second `Host.Transaction` state. All its actions
were discarded except the request generation. This repeated the queue's existing
ownership while giving the impression that the transaction model controlled
Worker admission and retirement.

## Decision

Use the Journal's serialized invocation and its pending Worker response as the request owner.
Remove the unused transaction transitions and generation round trip. Retain the
failure check for responses arriving after timeout or journal retirement. A later
request cannot start before the preceding response, and retirement prevents
another request from using an uncertain world.

The Journal uses the same ownership rule. Its serialized invocation awaits one
Worker response, writes an admitted durable input, then publishes only after
SQLite COMMIT returns. Failed storage retires that Worker; an error during COMMIT
retains the unknown outcome until reopen.

The later requirement review found that the retained transaction controller did
not govern any additional asynchronous fact. Its Resolve and Reject primitives
were never interpreted. Commit repeated the response's durability flag; Publish
repeated reaching the successful COMMIT continuation; Retire repeated the
storage/Worker failure handler. Committed and Finish described a synchronous
stretch of that same invocation. Remove this controller and its adapter instead
of maintaining a second account of the host's control flow. Keep the actual
commit/publication/retirement requirements and their public IO acceptance.

The complete caller trace also makes the Kernel's second promise queue
redundant. Startup awaits initialization and each replay before the next
request. Live mutations and assessments share the Journal queue, and close
drains that queue before terminating the Worker. Make the connection a private
Journal field so callers cannot bypass this ordering, and remove the duplicate
queue. Return initialization observations directly instead of storing another
description and initial projection in the connection. The runtime's
[Worker.terminate promise](https://nodejs.org/docs/latest-v24.x/api/worker_threads.html#workerterminate)
already waits for exit, so close needs no second exit promise.

Physical effects retain their independent handles because several operations
can run concurrently and finish out of order.

## Consequences

The Worker conversation and journal invocation share one serialization owner and
carry no unused correlation identifier. Public service, journal recovery, input
refusal and cancellation acceptance remain the evidence for the host's actual
IO behavior. Node's Worker message delivery and the wrapper's one-response construction remain runtime
assumptions; an identifier would add no protection against a faulty runtime.

References: [Node Worker messaging](https://nodejs.org/api/worker_threads.html#event-message)
and [SQLite transaction completion and errors](https://www.sqlite.org/lang_transaction.html).
