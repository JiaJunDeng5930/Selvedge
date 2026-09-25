# 0013: Separate control phase from operation rights

Status: accepted for the Bend branch.

## Reason

A sum with one ToolPending phase serializes independent calls and cannot represent
a model request while a sibling tool still runs. Treating partial status as a
completed function result without a separate completion protocol loses meaning.
Blindly recovering a pending shell call can repeat an irreversible mutation.

## Decision

Task state is a product of model/control phase, a bounded collection of operation
rights and an unread-input notification bit. Each operation owns one committed
ticket. Batch dispatch, result acceptance, cancellation, fork and recovery are
specified in Bend. The host realizes keyed effects, not another task scheduler.

At an actual model request, remaining unannounced operations acquire one explicit
running output. Before announcement, completion is an ordinary function output;
after announcement it is an operation-result message. History is append-only.
Quiet operations do not create polling turns. Results received during a model
turn set a sticky notification rather than overwriting the model's control phase.

Steering replaces model work while retaining independent operation rights and
queued follow-ups. CancelOperation consumes only a selected right; cancellation
cannot undo external changes. Explicit cancellation within a decision withdraws
earlier intents from that same decision before they reach the host. Recovery and
fork record unknown or nonowned operations rather than copying execution rights.

Summaries require no live operations. Oversized partial context waits for the
remaining results before summarizing. Queued input is promoted when a call batch
has been dispatched, not accidentally left out of the next model request.

Bash is the only local file/code tool. Independent calls may overlap; dependent
commands belong in one shell program. Head/tail previews, bounded artifacts,
argument validation, deadlines and process-group cleanup follow the relevant
Unreal agent design, within the native output budget. The three file tools and
their separate mutation implementation are removed.

## Evidence and boundaries

The complete command/input/execution/frontend/trace proofs still check. Native
tests cover partial results, in-model races, stale tickets, same-commit withdrawal,
fork ownership, restart, capacity, freeze/interruption and summary races. Real
HTTP/Bash fixtures exercise overlapping commands and independently scoped model
and process cancellation. Authorization is checked against each operation's
causal committed intent, not the latest log entry.

External commands are not assumed commutative, transactional or reversible. A
model request can overlap tools, but two model requests for one task cannot.
Receiving a partial result sooner can cost an additional model turn; the design
does not claim a universal latency/cost optimum. No real provider quality or
throughput advantage is inferred from deterministic fixture tests.
