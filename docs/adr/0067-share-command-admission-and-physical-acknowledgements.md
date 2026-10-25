# Share command admission and physical acknowledgements

Date: 2026-10-25

## Context

A field could be advertised by one schema, accepted by a different decoder and
interpreted a third way by a native tool. This made a valid title tool unusable
and allowed malformed commands to become durable business operations. Optional
field presence also lost the distinction between omission and an explicit null.

Files had a similar boundary problem: a successful write acknowledged content,
but callers used it as evidence that a new filename and its ancestors would
survive a crash. Reading a path's size before opening it did not bound the
actual descriptor read. Plugin installations needed the same physical protocol
as the source checkout.

## Decision

Internal argument descriptions are programs in a finite language. Their schema
is a projection, and their interpreter accepts the original program directly.
Parsing an external extension schema is a separate admission operation; an
unsupported assertion cannot silently disappear. Public and observed commands
share field declarations while keeping host observations outside client
ownership. Format checks precede business resolution so they cannot consume a
durable command or reorder profile, permission and capacity failures.

Omission and nullability have separate constructors. Bounds on selected wire
fields do not narrow the domain's arbitrary precision naturals or opaque JSON
numbers. Title instructions and controller identities use the same executable
rules in their owners and in command/tool admission.

Durable publishers share byte operations with explicit replacement and exclusive
creation semantics. Directory creation and the uncached directory barrier are
separate because an earlier successful creation does not acknowledge later
namespace changes. A bounded reader owns one nonblocking descriptor and checks
its observations before and after a bounded read; callers retain their own
text, credential and error policies. The plugin ships these same operations.

These admission changes, member-preserving calls and resource release outcomes
change recorded decisions. Journal format 7 is the single current format;
replaying older formats through a stricter decoder would misrepresent their
original contract.

## Consequences

The Rocq kernel checks the executable admission and controller propositions.
Extraction, runtime encoding, filesystem barriers, Git and provider transports
still require their own physical evidence. A persisted acknowledgement is
issued only after the relevant physical operations complete. It does not imply
network exactly-once delivery or strengthen an operating system guarantee.
