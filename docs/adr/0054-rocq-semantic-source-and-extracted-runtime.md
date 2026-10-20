# 0054: Rocq semantic source and extracted runtime

Date: 2026-10-21
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

The external interchange uses domain JSON, independently of either language's
internal constructor representation. JSON number lexemes remain exact at this
boundary. UTF-8 text and numeric operations require an explicit extraction
interpretation and executable boundary checks. External malformed input is
rejected by admission functions; dependent internal data does not remove that
runtime responsibility.

Each migration unit owns related data, operations, admission, requirements,
proofs and its execution entry. Dependencies follow contracts and actual
reduction requirements. Cross-domain invariants belong to composition modules.
Files are split to limit rechecking without duplicating domain declarations.

Keep historical ADRs as the reasons for earlier decisions. Their obsolete Bend
mechanisms are superseded where they conflict with this decision. Do not retain
obsolete code, tests or a second architectural description solely to preserve
those mechanisms.

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

- [Rocq extraction reference](https://docs.rocq-prover.org/master/refman/addendum/extraction.html)
- [MetaRocq project and Template API](https://github.com/MetaRocq/metarocq)
- [js_of_ocaml documentation](https://ocsigen.org/js_of_ocaml/latest/manual/overview)
