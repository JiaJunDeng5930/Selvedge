# Semantic guarantees and execution boundaries

A useful guarantee rules out a concrete violation of the product requirement.
Equality with a wrapper's own computation does not establish that requirement.
Read the owning requirement and its theorem together, and verify that the theorem
constrains the definition reached by the production extraction entry.

## Construction, checking and external input

Indexed field values, command payloads and lifecycle constructors rule out
specific internal combinations. They do not establish that arbitrary external
JSON is valid. The checked admission definitions must accept or reject that data
before it becomes a domain value. Shared declarations supply structural facts;
owner-specific requirements still govern authorization, correlation and business
behavior.

A generic theorem supplies a guarantee only after its premises are instantiated
for the actual exported operations. An abstract contract with no checked
production instance is incomplete evidence. A proof of a decoder's field shape
is not a proof that an accepted command has the intended effect.

## What kernel checking establishes

Rocq checks the stated propositions about Gallina definitions. Review both the
proposition's requirement and its premises. Important production results must
have an explicit assumptions audit; an absence of the word `Axiom` in local
files does not by itself exclude imported assumptions.

MetaRocq derives declarations from the common domain descriptions. Generated
source is checked again by Rocq and is not maintained by hand. Generation alone
is not evidence of business correctness, and Template metaprogramming is not a
claim that the OCaml or JavaScript compilation pipeline is verified.

## What execution adds

Standard Rocq extraction and js_of_ocaml are trusted translation steps. Numeric
extraction mappings and their JavaScript runtime support are part of that trust
boundary. Domain JSON parse/render functions are extracted from Gallina.
Internal parsed host values can instead enter through a generic converter into
the same extracted OCaml JSON type and domain entry. The converter, its
JavaScript standard-library operations and the compilation pipeline remain
trusted; raw text admission still uses the Gallina parser. Exact-number and
Unicode execution probes exercise the resulting artifact rather than a second
implementation of its intended behavior.

Bun Workers, SQLite, HTTP, process execution, browser DOM and remote providers
remain physical boundaries. A committed effect is a checked request to an
interpreter, not evidence that a filesystem, model or network obeyed that request.
The host must preserve commit-before-dispatch order and feed observations back
through the admitted completion protocol. Source-origin and request identities
must survive those exchanges without being inferred from display positions.

Public end-to-end tests exercise selected concrete failures across those
boundaries. They do not establish every external behavior, model quality,
scheduler fairness or unbounded resource availability. Build measurements apply
to the measured project and workload; small extraction experiments do not
establish whole-project build performance.
