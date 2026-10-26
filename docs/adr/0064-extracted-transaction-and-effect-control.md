# ADR 0064: Extracted transaction and effect control

Status: Accepted

A Worker transition can succeed before its SQLite write fails. A SQLite commit can
also succeed while its acknowledgement is lost. Treating both failures as an
ordinary rejected command permits later work to use an uncommitted world, or
permits physical rollback of a resource whose successful callback was committed.
These are program decisions and require the same executable semantic authority as
the task rules.

We place transaction and effect-control decisions in extracted Gallina steps.
Worker requests carry a model-generated generation across the thread boundary.
Journal replay supplies recorded decisions without publishing physical effects;
normal publication requires a successful commit acknowledgement. A pre-commit
failure is a definite rejection. Failure during COMMIT has an unknown outcome and
retires the current world; reopening the journal establishes the durable result.
An unknown outcome does not authorize completion retry or resource rollback.

Running effects have separate generations even when their logical keys match.
This preserves the physical handle of an older operation until it actually ends,
and its finalizer cannot delete a replacement. The model also records whether an
individual callback has already been reduced after a size rejection. A further
rejection retires the service rather than repeating the reduction indefinitely.

Service shutdown and failed-world retirement detach local observers while keeping
retained remote requests available for restart. Provider cancellation requires an
explicit committed task or ticket cancellation. Equating the lifetime of an
observer with the lifetime of its remote request would turn local shutdown into
an unrequested remote Stop.

The checked TypeScript effect bridge interprets the generated discriminated union
exhaustively. An additional effect therefore requires an explicit interpreter;
there is no default tool route. JavaScript primitives retain physical handles and
perform IO, while the extracted steps choose the control actions. SQLite durability,
Worker execution and external-provider outcomes remain explicit trust boundaries.

Recovery uses the same lifecycle runner as ordinary effects because its callback
needs an active generation even though its physical action is observation rather
than creation. The runner installs the controller and the original rejecting
promise before invoking its interpreter. Startup awaits that promise directly;
a background failure observer must not convert a failed recovery into successful
startup. An opaque handle ties completion and settlement to that registration,
and the actual runner and settlement interpreter are included in the strict
TypeScript check. A finalizer removes only its own generation. The runner never
adds a second settlement around an interpreter that already settles its result.

Archive barriers and size-rejection compensation belong to the extracted
dispatch controller. The host supplies resource identities and physical path
overlap observations. This keeps a new running-effect category from silently
bypassing the resource wait policy, and keeps an uncertain journal outcome from
acquiring physical rollback authority through an adapter branch.

Retiring the dispatcher prevents new launches and callback reduction; it does not
undo an already accepted journal commit. Shutdown can occur while the promise
for that commit is returning. Its still-active handle may acknowledge the
accepted result once while preserving the retired dispatcher, so waiting for
physical cleanup does not turn a successful commit into a shutdown failure.

Provider cancellation preserves the registered effect rather than reducing it
to a task number. A ticket cancellation selects that invocation's owner and
ticket; whole-task cancellation retires the task-wide owner and then the
applicable independent approval owners. Receipt retirement selects the exact
request key synchronously before asynchronous Stop transport can run. The
dispatcher distinguishes task and independent provider scopes so this does not
duplicate task-wide Stop or change shutdown's detach-only policy.

Stdio response admission precedes media persistence. `Adapters.Rpc` first
validates a JSON-RPC response, correlates its pending request and consumes that
pending identity into a materialization reservation. Only a `tools/call`
request carries the MCP media continuation. `plugin.mcp_media_plan` admits all
observed image bytes and the complete byte budget before the continuation
writes any attachment. A repeated response cannot reserve the same request
again. Cancellation retires the reservation and aborts its staging interpreter;
late completion cannot settle a retired request. Physical work remains counted
against capacity until its Promise actually ends, and close waits for those
bounded operations. This separates request authority from an already admitted
file operation that is still completing its durability barrier.
