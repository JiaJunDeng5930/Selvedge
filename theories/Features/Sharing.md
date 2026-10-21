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

`SharingProofs.v` states laws about the actual command and completion functions,
including positive admission, denied authority, replay, frozen execution context,
and repeated cancellation. The Rocq kernel checks these laws. Extraction and the
JavaScript compiler remain trusted translations. Authenticated controller
identity, faithful prepared commands, external process behavior, and actual stop
completion belong to the IO host; the proofs do not claim those external facts.
