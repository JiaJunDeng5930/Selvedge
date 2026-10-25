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
