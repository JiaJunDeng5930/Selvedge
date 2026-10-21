# Runtime acceptance

The runtime suite exercises physical behavior through public service, HTTP,
CLI, plugin and relay entry points. It uses local model/MCP/network peers and
isolated temporary homes; it does not require a live model account.

The retained responsibilities include commit-before-effect ordering, replay
without repeated external calls, SQLite ownership, credentials, filesystem
integrity, process cleanup, network framing/backpressure and browser streaming.
Gallina domain rules and structural guarantees belong to their executable
constructions and checked proofs. Tests of the removed Bend compiler, runtime
intrinsics and source-scanning gates are not part of this suite.

Run `bun run build` before `bun run test`. Browser acceptance uses a real
Chromium instance through Playwright and the application's HTTP entry. A passed
Rocq proof or successful module build does not report a physical scenario as
having passed; run the corresponding public entry before recording that result.
