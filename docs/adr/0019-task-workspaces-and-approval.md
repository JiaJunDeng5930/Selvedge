# Task workspaces, process isolation, and approval

Workspace membership describes where work belongs and which root is the default
command directory. It is not an operating-system boundary. A sandbox plan
separately describes writable paths and network permission; a one-operation
approval grants an exception to that plan. A project supplies defaults, not live
authority over tasks that already copied those defaults.

## Platform boundary

`host/sandbox.mjs` interprets a native execution plan. macOS uses Seatbelt through
`/usr/bin/sandbox-exec`; Linux uses bubblewrap mount/user/PID namespaces plus a
seccomp filter. This follows the platform selection documented in the Codex
[security guide](https://developers.openai.com/codex/agent-approvals-security),
reviewed September 27, 2026. The corresponding upstream reference is
`openai/codex` commit `8f195c93d7e7acfef95acf273f0e49cce917e291`, notably
`codex-rs/sandboxing/src/seatbelt_base_policy.sbpl`. This is an independent small
interpreter, not a claim to implement every Codex permission feature.

Paths are canonical absolute directories. Multiple roots are writable under
`workspace-write`; `read-only` adds no workspace write permission. An empty
workspace runs at `/`, without making it writable. Each invocation gets a private
temporary directory. Other filesystem paths are readable but not writable.
The service journal subtree is protected even when nested inside a root.
Root membership is neither a Git worktree nor a snapshot of file contents.

Linux denies host Unix-socket connections, namespace creation and privileged
kernel/process operations even when IP networking is enabled. Directory file
descriptors pin writable bind sources; the child receives a new PID namespace.
The filter checks both the syscall architecture and the x32 ABI, and returns
`ENOSYS` for `clone3` so libc can fall back to the inspected `clone` flags.
macOS restricts signals and process inspection to the sandbox and does not
grant blanket Mach or Unix-socket access. These restrictions prevent common
host-daemon and process-control routes around a filesystem policy.

Missing executables, namespace restrictions, changed canonical roots and
unsupported platforms fail closed. A sandbox startup failure or a command's
nonzero exit is never permission to repeat that command outside isolation:
the first attempt may already have caused partial side effects. Full access is
an explicit unrestricted plan, not an error-recovery fallback.

## Evidence boundary

The Bend proof root owns decisions and permission ownership. Operating-system
isolation, pathname resolution, subprocess cleanup and model judgment remain
external assumptions, exercised by focused tests. `sandbox.test.mjs` checks
canonicalization, SBPL quoting, both Linux BPF encodings, and real subprocess
write/read boundaries. CI installs bubblewrap on Linux. Tests do not turn a
missing sandbox into a pass by substituting unrestricted Bash.

The first implementation step adds the effect adapter. Native task settings,
project defaults and correlated approval decisions are connected in subsequent
steps of the same feature; merely importing the adapter does not enable isolation
for a caller that has not supplied an execution plan.
