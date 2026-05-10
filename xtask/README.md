# xtask

`xtask` contains repository-local automation that should stay out of production crates.

## Requirement Commands

- `cargo xtask req scan` prints parsed requirement comments, their bindings, and diagnostics.
- `cargo xtask req fmt-agents` regenerates only the AGENTS.md requirement index block from source comments.
- `cargo xtask req check --staged` validates the staged Git snapshot for pre-commit.
- `cargo xtask req check --all` validates the full tracked checkout for CI.
- `cargo xtask req check --base <git-ref>` validates changed Rust hunks against a base ref for CI.

The requirement registry is in memory for one command invocation. AGENTS.md is the only generated tracked artifact.
