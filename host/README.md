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

The suite also exercises device login and serialized credential refresh against a
loopback issuer, interruption and restart of an actual HTTP stream, MCP catalog
notifications during shutdown, and suppression of effects withdrawn within a
commit. Credential parsing errors must not quote file contents into task history.
Use `npm test` to run these checks; they require no real credentials or model calls.

The browser consumes command schemas and allowed lifecycle controls returned by
the running model. It does not own a second lifecycle table. The exploration
record distinguishes browser interaction evidence from the native proof gate.
