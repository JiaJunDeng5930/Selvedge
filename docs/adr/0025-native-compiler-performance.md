# 0025: Pin the native compiler's emission improvements

## Context

The complete feature-extension fixture compiles the production entry point with
frozen clients. On the development machine, its Bend 2.0.27 compilation could
exceed the existing subprocess limit while other proof checks were running.
Clang was already using `-O3`; the expensive earlier phase was Bend's repeated
whole-program C emission. Merely enabling a native optimization flag therefore
would not address that work.

## Decision

Pin the official Bend 2.0.34 archives and their published checksums. This release
includes upstream improvements to word-type and nullary-constructor emission,
and to shared-graph conversion, recorded in the
[upstream changelog](https://github.com/bendlang/bend/blob/v2.0.34/CHANGELOG.md). Use the official compiler rather than maintaining
a patched compiler or weakening the proof and compilation gates.

Its Base adds names that conflict with the old `Event` types and board `Move`
constructor. Alpha-rename the resolved input/completion types to `ResolvedEvent`
and the card command to `MoveCard`. Keep their operations, laws and public JSON
command names unchanged.

Accept only this compiler's complete positive report at the pure proof gate.
Check the native entry separately: its negative proof verdict is admissible only
for the exact three existing IO assumptions, not additional promises or a type
error. This does not turn the native entry into pure evidence. The default checker
remains a trusted boundary; the optional independent BendTT verdict is not claimed.

Keep test files serialized because native compilation still has a large working
set. Retain the existing subprocess limit, every mutation test and actual native
round trips.

## Evidence and consequences

An isolated run of the same extension changed native build time from 138.651 s
on 2.0.27 to 78.456 s on 2.0.34. Five-second process samples first observed Clang
at 85.136 s and 35.056 s respectively. These are individual local measurements,
not a universal performance guarantee. The newer compiler's sampled peak Bend
RSS was still about 10.5 GiB, so memory contention remains relevant.

Bun's `--smol` mode on the old compiler produced byte-identical C but took
151.628 s; its small RSS reduction did not justify adopting it. The compiler
upgrade requires the workspace-local install and changes the build fingerprint,
so an old cached binary cannot count as a current build.

The hosted `macos-latest` label moved to macOS 26 ARM64 with 7 GB RAM. Its complete
extension fixture took 320.726 s and failed with the existing native deadline.
Select the standard `macos-26-intel` runner with 14 GB RAM so the measured
compiler working set fits the job's resource budget. Keep macOS 26 coverage and
the existing deadline. These standard runner specifications are published in
the [GitHub hosted-runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).

The first 14 GB Intel run still exceeded the native deadline, so additional RAM
alone did not resolve the hosted compilation problem. Select the image's installed
upstream Clang 20 through Bend's supported `CC` setting and retain `-O3`. Native
build diagnostics sample only process-group IDs, CPU, RSS and command names to
distinguish Bend emission from C compilation without logging arguments. Validate
this toolchain choice against the same production fixture and 300 s deadline;
the failing Intel run does not count as readiness evidence.
