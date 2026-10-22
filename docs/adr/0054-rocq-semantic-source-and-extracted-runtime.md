# 0054: Rocq semantic source and extracted runtime

Date: 2026-10-20
Status: Accepted

## Context

Selvedge needs its domain rules, requirements and executable implementation to
refer to the same program entities. The previous Bend implementation repeatedly
described command fields, component structures and protocol cases. Its dependent
wrappers sometimes certified correspondence to the computation itself without
excluding an implementation that violated the product requirement. Its compiler
also coupled unrelated proof and runtime work in expensive builds.

Migration starts from the complete product at `242dba9`, including image inputs,
history search and persistent Work interfaces. The old checkout is a read-only
reference. An orphan branch contains the replacement; no Bend value adapters or
parallel Bend implementation are part of the replacement runtime.

## Decision

Gallina definitions own pure domain data, admission rules, transitions and
observations. Proofs constrain those definitions, and the executable runtime is
extracted from them. Bun, the browser, SQLite, the operating system and remote
services interpret explicit effects and supply observations.

Use ordinary indexed data and generic functions first. A shared field and command
description language owns repeated structural facts. Use MetaRocq when deriving
new declarations is necessary; generated declarations must be checked by the Rocq
kernel. Do not import the metaprogramming environment or proof automation into
ordinary computational modules. Rechecking generated constants must not require
rebuilding every business module.

For record updates, reuse the pinned MIT-licensed record-update library rather
than maintain another project-specific derivation engine. Its checked generic
setters remove repeated field lists while preserving the other fields. The
small compile-time Ltac2 mechanism does not become executable domain behavior.

The external interchange uses domain JSON, independently of either language's
internal constructor representation. JSON number lexemes remain exact at this
boundary. UTF-8 text and numeric operations require an explicit extraction
interpretation and executable boundary checks. External malformed input is
rejected by admission functions; dependent internal data does not remove that
runtime responsibility.

Repeatedly rendering and reparsing complete internal host values made the
execution boundary a significant feedback cost. For already parsed values, use
one generic converter into ordinary OCaml JSON constructors, compiled against
the same extracted JSON type, and invoke the same extracted domain entry. This
avoids a private JavaScript constructor ABI and a second business implementation.
Raw text admission continues through the Gallina parser. The converter and the
JavaScript standard-library operations it uses remain trusted foreign code;
this optimization does not extend the kernel's guarantees to them.

A real JavaScript extraction probe found that retaining Peano naturals made
ordinary escaped Unicode scalar decoding overflow the stack. Use the mature
arbitrary-precision natural-number extraction and Zarith JavaScript runtime
support rather than silently narrowing domain naturals to machine integers.
Keep that mapping in extraction configuration, with its runtime dependency
pinned and checked through the public extracted boundary.

Arbitrary-precision extraction alone does not compact numeral syntax. The
default notation expanded `4096` into thousands of successor calls, exceeding
the JavaScript parser's stack before any entry could execute. Use Rocq's standard
abstract numeral notation above a small threshold in the common numeric module.
This changes term representation, not the represented natural number.

A subsequent real input of 16 KiB exposed recursive string scans and repeated
suffix copying. Tail accumulators and the exact native byte-length extraction
primitive preserve Gallina string semantics without a second JSON parser or a
larger JavaScript stack requirement.

A PTY launch owns a fresh Bun terminal session. Detaching the sandbox from
that dedicated terminal broke resize and keyboard-signal delivery. Preserve the
session and give the original command its own foreground job while retaining
the admitted filesystem, network and seccomp policy. Job-control wrapping keeps
the command as an argument rather than evaluating it a second time. Pipe
launches retain their separate session. Bun's controlling-terminal behavior and
OS foreground-process semantics remain physical runtime assumptions.

Each migration unit owns related data, operations, admission, requirements,
proofs and its execution entry. Dependencies follow contracts and actual
reduction requirements. Cross-domain invariants belong to composition modules.
Files are split to limit rechecking without duplicating domain declarations.
Frozen job argument declarations remain independent of complete command routing,
so a routing change does not introduce every command dependency into the world
representation. Job identities advance independently of retained entries;
forgetting a record can release memory without making its old callback valid.

An eleven-name context observer match made one definition take tens of seconds
to check. A declaration table with string equality avoided the pattern compiler's
expansion and checked the complete module in under a second. Use that approach
for this vocabulary; do not encode compiler cost as a domain restriction.

A Project supplies creation defaults, while a Task owns its frozen execution
settings and per-creation choices. Reusing the selected default does not write shared Project configuration;
an explicit remember choice can update that Project preference. Browser
reading position likewise has one owner; retaining an unused second reading
state in Interaction would create competing sources of authority.

A scheduling decision can revoke an earlier intent before physical dispatch.
Capture side-parent context and filter live intents once at final dispatch,
rather than duplicating subtly different checks in every emitter. Keep raw tool
execution evidence separate from the result presented after hooks: redaction,
denial or interruption cannot erase what actually ran. An archived task cannot
receive a new callback right, so self-archive keeps its raw receipt and reports
interrupted result processing. Positive public-entry requirements complement
safety results, since an implementation that never schedules work can satisfy
many negative statements.

Existing account digests use NUL-separated identity components. Reject NUL in
those components instead of changing every ordinary account namespace; this
removes ambiguous digest inputs without depending on a hash collision. Present
malformed credentials must remain an error. A disposable model cache can be
discarded on its observed invalid-encoding error without granting the same
replacement authority over credentials. Cryptography and strict byte decoding
remain physical obligations.

Keep historical ADRs as the reasons for earlier decisions. Their obsolete Bend
mechanisms are superseded where they conflict with this decision. Do not retain
obsolete code, tests or a second architectural description solely to preserve
those mechanisms. The historical `docs/bend2-exploration.md` is retired: its
compiler experiments and measurements concern the previous stack and remain in
Git history. They are not evidence about the Rocq replacement.

## Trust and evidence

Rocq kernel checking establishes the propositions that are actually proved.
MetaRocq Template generation is not a claim of verified compilation. The standard
Rocq OCaml extractor and js_of_ocaml compiler remain trusted translation steps;
OCaml foreign code, JavaScript IO and external observations remain outside those
proofs. A wire-shape or dispatch theorem alone does not establish business
correctness, authority of an observation or external effect completion.

Production validation must follow the real extracted entry through the Bun or
browser host. Permanent tests exercise public end-to-end behavior. Measure clean
builds, unchanged rebuilds and representative local edits after integration;
do not infer whole-project performance from a miniature extraction experiment.

## References

- [Rocq extraction reference](https://rocq-prover.org/doc/v9.2/refman/addendum/extraction.html)
- [MetaRocq project and Template API](https://github.com/MetaRocq/metarocq)
- [js_of_ocaml documentation](https://ocsigen.org/js_of_ocaml/latest/manual/overview)
- [Pinned record-update library](https://github.com/tchajed/coq-record-update/tree/1dd231db87451479043a3812dbdbd9658657ff7c)
