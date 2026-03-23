# `selvedge-config` Examples

These examples are written for crate consumers. They only use the public API of
`selvedge-config` and `selvedge-config-model`.

- `load_defaults.rs`
  Load a config store and read values through `AppConfigStore::read`.
- `layered_sources.rs`
  Build a store from a config file and internal search/env rules.
- `runtime_updates.rs`
  Apply runtime updates and persisted updates through the public store API.

Run an example from the repository root:

```bash
cargo run -p selvedge-config --example load_defaults
cargo run -p selvedge-config --example layered_sources
cargo run -p selvedge-config --example runtime_updates
```
