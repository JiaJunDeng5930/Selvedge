# Requirements and design reasons

The Gallina sources in this directory explain the current user and engineering
goals, select the existing contracts that express them, and prove any missing
connection to the operation the product executes. Read the relevant requirement
before changing a public contract. Domain definitions, computations and proofs
remain under `theories/` and supply the contracts selected here.

Keep a reason next to the contract it explains. Use an existing theorem directly
when it already states the requirement. Add a proposition or derivation when the
goal requires a relationship that is not yet expressed. Requirements and
implementation choices depend on current goals and observations; old designs
and historical alternatives do not create additional requirements.

## Capability design

Selvedge owns the capabilities needed to run and manage agent tasks. Apply this
boundary when adding functionality, designing interfaces or changing architecture.

- At the system boundary, use existing external programs for general-purpose
  work when they meet the requirement. Provide public interfaces that let those
  programs invoke harness operations and consume their results.
- Across subsystems, compose existing operations through their interfaces. Keep
  domain rules and state transitions with the subsystem that owns them.
- At the module and interface level, keep each domain's set of basic operations
  as small as possible while covering its required behavior. Each domain defines
  its own set. Build derived capabilities by composing operations, fixing
  arguments or projecting results. Convenience interfaces delegate to the
  operations that already own the core semantics.
- Within functions and algorithms, use ordinary reuse and encapsulation. The
  distinction between basic and derived capabilities is for designing interfaces.

Start by specifying the observable behavior and identifying the semantics
Selvedge must own. Evaluate external programs and compositions of existing
public operations against the full contract, including required permissions,
persistence, atomicity and failure handling. A viable composition preserves
those guarantees through supported interfaces, without depending on private
state or reimplementing a component's core rules. Computational equivalence
alone leaves those guarantees unaddressed. Add a basic operation only when it
supplies a necessary behavior or guarantee that a practical composition cannot
provide. Explain that choice alongside the owning requirement.

For example, a `launchd` job or a service activated by a `systemd` timer can
invoke an existing Selvedge CLI command against a running service. The external
scheduler owns when the command runs. Selvedge owns command admission and task
execution.
[launchd scheduling](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html),
[systemd.timer](https://www.freedesktop.org/software/systemd/man/258/systemd.timer.html).

For domain extensions, reuse controlled constructors and composition operations
whose contracts supply the required shared properties. Prove only the additional
behavior required by the extension. [Construction interfaces](../theories/Programming/README.md)
and [engineering contracts](Engineering.v) describe the available guarantees.

## Checking and dependency direction

The normal build discovers every `.v` file in this directory and checks its
assumptions. A focused check uses the existing module option:

```sh
bun scripts/build.mjs --module Requirements.Engineering
```

`requirements/` has the logical root `SelvedgeRequirements`. Its compilation can
import `Selvedge` and other requirements. Production modules and extraction only
receive the `Selvedge` load path, so they cannot depend on this directory.
Changing a requirement therefore does not invalidate an unchanged runtime
module. No requirement registry or per-module build list needs updating when a
new source is added.

Physical behavior is checked at the public boundary where it occurs. Permanent
tests exercise complete public operations and express user or engineering
requirements. Properties already guaranteed by construction or proof are not
repeated in tests. Temporary experiments belong in `.workpad/`.
