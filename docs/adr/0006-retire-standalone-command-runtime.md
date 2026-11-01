# Retire the standalone command inspection runtime

## Context

The service executes the generated command decoder through the kernel. A separate
`commands` extraction target exposed only a decoder/encoder inspection wrapper.
No repository command, test or documented workflow consumed that bundle. Keeping
it required another runtime wrapper and special cases in otherwise shared build
and export handling.

## Decision

Remove the standalone target and its OCaml wrapper. Keep command generation and
the decoder/encoder used by the production kernel. The checked build continues
to check the generated command source and its production consumers.

## Consequences

There is one executable route for service commands. Developer inspection can use
the public service entry or the existing Rocq definitions, without maintaining a
second executable package. The five production targets are unchanged; requesting
the retired build target is an ordinary unknown-target error.
