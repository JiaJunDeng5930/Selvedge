# Host effects

The native Bend process owns task state. The host accepts JSON commands, performs
the effects returned by that process, and sends their results back as inputs.
It must commit an input and its decision to SQLite before publishing a reply or
starting an effect. A failed commit terminates the process; committed inputs are
replayed through the same Bend transition at the next start.

`transport.c` only receives bounded, length-prefixed UTF-8 tokens. It constructs
the generic token list consumed by the checked JSON decoder. It has no task
constructors, persistence operations, lifecycle rules, or tool policy. The native
compiler's effect ABI and the operating system remain trusted boundaries.

Host integration tests exercise persistence, HTTP delivery, model transport, and
process execution. Bend laws do not prove those implementations or their services.
