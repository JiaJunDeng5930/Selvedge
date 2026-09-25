# Bend support definitions

Read the root MODEL, INVARIANTS, LAWS, and PROGRAM entry points before following
an implementation detail into this directory.

`theory.bend` contains domain-independent list-monoid, replay composition,
stuttering, and transition-invariant induction results. PROOF instantiates them
with the production state transition.

`tasks.bend` implements task collection, history, queue, and recovery operations,
including closing interrupted tool attempts and validating summary completions.
`MODEL.context_history` is the authoritative checkpoint projection. Full history
remains append-only; the presentation layer renders whichever history the
authorized effect carries. `INVARIANTS.settled_calls` guards context cuts against
unsettled function calls.
`equality.bend` supplies bounded structural comparisons used by INVARIANTS.
A comparison budget exhaustion returns false; it never certifies unchecked values.
These comparisons establish value relations, not physical pointer sharing.

`json.bend` preserves JSON number spellings and provides bounded decoding and
rendering. `schema.bend` checks the supported command and built-in tool schemas.
`wire.bend` decodes external messages to MODEL inputs. `presentation.bend` renders
model values and decisions. None of these modules performs an operating-system
effect; all external work crosses the host boundary.

Run `npm run check` for the proof gate and `npm test` for native execution and
host integration. Changing a Bend source changes the journal's kernel identity.
