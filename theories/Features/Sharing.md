# Remote access and connection jobs

`Remote.v` and `Chatgpt.v` own different forms of delegated authority. Native
remote commands use revocable controller generations and bounded retained
receipts. Connection jobs freeze a granted execution context at admission and
retain an outcome without replaying an uncertain external execution.

The distinction matters: revocation prevents subsequent access, while an already
issued process may still complete. Forgetting its receipt cannot make its
operation identifier available for another execution. Cancellation requests a
stop; it does not undo physical changes.

Connection argument values use `Kernel/ChatgptArguments.v`, shared with the public
tool protocol. Schema admission constructs the typed fields stored in a job;
encoding those fields also supplies the actual host effect. Reordered JSON object
members therefore describe the same retry. A separate monotone identifier supply
allows retained jobs to be removed without keeping an ever-growing sparse array.

`Runtime.v` composes these domains with the other feature domains. Remote execution
receives the existing scheduler executor. It neither starts another scheduler nor
performs a second transition hook. Queries do not apply a prepared configuration.

`RemoteProofs.v` derives fresh admission and retained-result replay from current
grants, componentwise permission requirements, request bounds and stored receipts.
It also checks disabled access, revoked authority and oversized-reply rollback.
Replay is derived without assuming that authorization already returned `Replay`.
`SharingProofs.v` contains the separate connection-job guarantees for frozen
execution context and repeated cancellation, so editing remote proofs does not
recheck the connection-job proofs.

`RemoteEntryProofs.v` composes authority with the actual `Packet.execute_domain`
interpreter: for a running first task and its satisfied workspace guard, a
current control grant stops the task and retains the success receipt before
the ordinary scheduler runs. It does
not require read, configure or approve authority. This scoped positive family
rules out rejecting every command or preserving every task unchanged; business
properties of other commands remain with their owning domains.

The Rocq kernel checks these laws. Extraction and the JavaScript compiler remain
trusted translations. Authenticated controller identity, faithful prepared
commands, external process behavior and actual stop completion belong to the IO
host; the proofs do not claim those external facts.
