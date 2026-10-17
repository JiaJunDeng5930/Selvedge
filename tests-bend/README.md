# Test responsibilities

For each property, prefer construction in the domain language, then types, then
proofs, then focused tests, and finally end-to-end tests. Inspect the actual
production binding before claiming a property is guaranteed. Do not test it again
at a later layer.

A test also needs a convincing likelihood of real failure relative to its setup,
runtime and maintenance cost. A possible error, an unproved property or an
external boundary alone is insufficient; default to deletion when the case is
unconvincing. Merge related checks and setup. Do not preserve scenario matrices
inside one large test merely to reduce the reported test count.

The mandatory [production proof root](../PROOF.bend), source-ownership gate and
certificate checks run through `bun run check` and ordinary builds. They own
semantic requirements, component refinement and unrelated-state preservation.
Tests do not recompile hypothetical application extensions or repeat semantic
traces through HTTP and SQLite.

The small physical suite targets failure mechanisms that the model cannot rule
out: SQLite failing after a kernel transition, execution before durable authority,
subprocess pipe pressure and process-tree cleanup, filesystem links and content
integrity, byte-split network decoding, credential rotation and secret-file
handling, transport teardown, and observed browser connection/IME regressions.
The handwritten source scanners retain small syntax regressions. These checks
exercise the actual production paths rather than test-only models.

Use Bun 1.4.2 or later and the pinned Bend toolchain installed by
`bash scripts/bootstrap.sh`:

```sh
bun run check
bun run test
bun run index:check
```

`bun run test` builds the production JavaScript libraries once and invokes Bun's
standard test runner with sequential tests. Fixtures do not compile more Bend
programs. The suite uses temporary homes, loopback servers and subprocesses; no
real model account or paid request is needed. OS isolation requires Seatbelt on
macOS or bubblewrap/seccomp on Linux. Chromium or Google Chrome is required for
the focused DOM regression; `SELVEDGE_BROWSER` may name its executable.

A passing physical probe is local evidence, not a proof about all compiler,
operating-system or provider behavior. Synthetic keyboard events do not establish
hardware input or operating-system IME behavior. Loopback OAuth and model fixtures
do not establish commercial service availability or model quality. GitHub Actions
CI is disabled; run the checks explicitly. Git hooks apply only when installed.
