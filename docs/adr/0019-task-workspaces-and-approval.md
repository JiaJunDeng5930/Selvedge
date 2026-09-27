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

## One-operation review

`APPROVALS` defines review resolution independently of `PROGRAM`. A pending
request owns the complete post-hook Bash call and its task-local operation ID.
Human and model completions are distinct inputs: neither can answer the other's
request. A successful review commits an audit record and a one-use grant before
the scheduler exchanges it for a fresh execution ticket. Frozen tasks may accept
a decision, but cannot dispatch that grant until resumed. Forks inherit context,
not live approval rights. Interrupted reviews are settled during recovery rather
than resubmitted or treated as permission to execute.

Approval for Me is a separate provider call, not an agent task or a child fork.
It has no tools and receives the exact command, frozen settings and at most four
recent user requests, each bounded to 4096 characters. Its instructions require
denial when this partial context does not establish permission. Strict decoding
rejects duplicate JSON members (including escaped keys), additional authority
fields, tool calls, malformed decisions and excess output. Transport failure
settles as a failed review; it never grants access.
This constrains the mechanism, not the model's judgment or resistance to prompt
injection. Full Access deliberately bypasses the sandbox; a reviewed exception
does so only for its one frozen invocation, without changing task settings.

`LAWS.review_semantics` is the public refinement shared by protocol and approval
proofs. The protocol module provides its evidence; approval assembly consumes
that declared law rather than importing a sibling's private helper.

Human approval controls are generated in `UI.bend` with ordinary live command
gates. The browser displays the full command literally and forwards the exact
one-operation event; it cannot alter the requested command through that event.
A stale click returns a refused command receipt alongside the updated screen.
The adapter does not infer permission from HTTP success or maintain approval
state. Browser tests use pointer hit-testing on both desktop and narrow layouts.

## Evidence boundary

The Bend proof root owns decisions and permission ownership. Operating-system
isolation, pathname resolution, subprocess cleanup and model judgment remain
external assumptions, exercised by focused tests. `sandbox.test.mjs` checks
canonicalization, SBPL quoting, both Linux BPF encodings, and real subprocess
write/read boundaries. CI installs bubblewrap on Linux. Tests do not turn a
missing sandbox into a pass by substituting unrestricted Bash.

## Native location and project model

`MODEL.TaskContext` is the product of a workspace, a sandbox, an approval policy
and an optional project identity. It is part of the task's immutable contract.
`WORKSPACE` admits canonical observations and defines the model-fork authority
check. `PROJECTS` instantiates the already imported ExtLib association map for
organizational projects. `Commands.Start` and `Commands.Branch` carry resolved
birth selections; their full decision meanings remain separate from `PROGRAM`.

`ContextBoundary` binds the actual birth and project operations to proofs:
default children inherit the context but no live operation rights, explicit
overrides affect the child template, project updates preserve the entire task
collection, and the imported map removal theorem establishes project removal.
Existing tasks still require exact contract equality across every commit.
A model fork may narrow but not broaden write/network/approval authority.
The authenticated user command may explicitly choose a different child context.

The host canonicalizes only user-selected roots and captures the primary root's
AGENTS.md before handing that observation to the native command. It does not
choose project defaults or implement inheritance. The service requires the
native execution plan for every Bash dispatch and passes the same captured
coordinates to the provider and subprocess interpreter.

Journal format 2 no longer binds the database to one global working directory.
Task plans and project defaults are journaled values; a changed service launch
directory cannot reinterpret them. Existing format-1 databases are refused,
not silently reinterpreted or automatically migrated. A service home should be
separate from writable project directories, because sandboxed Bash cannot modify
the service's persistence, credentials, or artifact subtree.
