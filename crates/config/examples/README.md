# `selvedge-config` Examples

These examples are written for crate consumers. They only use the public API of
`selvedge-config` and `selvedge-config-model`.

- `load_defaults.rs`
  Initialize the configuration service and read values through `read`.
- `layered_sources.rs`
  Initialize from a configuration directory, environment, and CLI overrides.
- `runtime_updates.rs`
  Apply runtime updates and persisted updates through the public service API.

Run an example from the repository root:

```bash
cargo run -p selvedge-config --example load_defaults
cargo run -p selvedge-config --example layered_sources
cargo run -p selvedge-config --example runtime_updates
```
