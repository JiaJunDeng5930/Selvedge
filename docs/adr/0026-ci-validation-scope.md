# 0026: Separate routine CI from compiler-intensive assurance checks

## Context

The Linux full-suite run at `0a32dbe` passed 278 tests in 1755.5 s. Most of that
cost came from whole-program proof mutations and extension fixtures: the
whole-program proof group alone took 462.9 s and the complete native extension
271.8 s. Repeating those suites on every PR and both operating systems made CI
feedback depend heavily on hosted compiler performance. Increasing macOS memory
did not eliminate the timeout; the Clang override was never validated.

## Decision

Run production proof and certificate checks, syntax, the production native build,
regular integration tests and the tracked-file index on Linux for automatic CI.
Keep actual sandbox, process cancellation, persistence and plugin boundary tests
in that suite. New test files enter routine CI by default.

Retain compiler-intensive mutations and native extension fixtures in the complete
`npm test` suite and pre-push hook. Provide a manual full-validation input for
Linux and macOS using the same workflow rather than duplicating environment setup.
The explicit routine-test selection lives in `scripts/test-ci.mjs`.

Remove the speculative macOS compiler override and its process sampler. Keep all
production proof obligations, mutation assertions and individual compiler limits.

## Consequences

Routine CI gives bounded feedback without claiming complete compiler-assurance or
macOS readiness. Changes to proof machinery or component composition still require
full relevant local validation. The manual workflow becomes available after the
configuration reaches the default branch, as required by
[GitHub's workflow dispatch contract](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow).
Hosted macOS full-suite performance remains unresolved; a green routine check does
not establish that the full suite passes there.
