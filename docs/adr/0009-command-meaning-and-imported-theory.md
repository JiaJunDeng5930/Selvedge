# 0009: Command meaning, imported theory, and a conceptual entry

Status: accepted for the Bend branch.

## Reason

Safety admitted a program that always refused requests, or acknowledged work
without doing it. Root files exposed the implementation vocabulary, but neither
complete functional requirements nor first-class theoretical structure. Moving
project-written list proofs to a library directory did not constitute reuse of
existing theory.

## Decision

`COMMANDS.resolve` is the sole owner of command preconditions. It produces a
closed operation algebra, inaccessible on the external wire. `COMMANDS.meaning`
fixes each operation's full world/reply/effect result. PROGRAM's realizer is
checked against that meaning for every operation and every world. The public
command theorem extends this through bounded scheduling, live-effect filtering,
admission, complete-envelope output bounds and rollback. Exact equations also
constrain scheduling, effect dispatch and successful settlement.

Rejected public commands do not advance unrelated tasks. An already accepted
internal tool that fails still needs a recorded output; those are different
semantic events. A rejected manual fork therefore does not fabricate a tool
call or consume its correlation ticket. Journaling an input is distinct from
changing the modeled world: a durable rejected input can still be replayed.

Standard list/equality proof bodies are quoted from pinned Rocq libraries and
translated by an untrusted restricted converter. Bend rechecks them against
application-used statements. Normal builds use the saved source certificates;
Rocq and MetaRocq are regeneration tools, not deployment dependencies. Unknown
source constructs fail rather than becoming axioms or erased obligations.

`CONCEPTS.bend` contains named, proof-carrying structures indexed by their actual
carriers and operations. It is the first entry for a reader. Queue, history and
replay proofs consume those structures. Decision composition is deliberately a
semigroup: effect concatenation is a monoid, but a decision carries both a reply
owned by the first command and a world owned by the final step.

## Verification and limits

Mutants that remain well-typed but suppress execution, change identities, omit
requests/cancellation, disable scheduling, lose continuations or always reject
are required to fail the same proof gate. Native tests cover every command and
atomic refusal, including refusal while another task is still runnable.

The independent object is the operation's semantic expression, not a second
human-language specification. Changing that expression is a requirements change
and needs review; the type checker cannot infer the author's English intent.
Theoretical reuse is explicit and restricted, not automatic theorem discovery.
The compiler, runtime, OS, database and provider boundaries retain their stated
trust assumptions. Summary fidelity and eventual model/provider progress are
not consequences of a context projection or a bounded scheduler.
