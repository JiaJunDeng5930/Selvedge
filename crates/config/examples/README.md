# `selvedge-config` Examples

These examples are written for crate consumers. They only use the public API of
`selvedge-config` and `selvedge-config-model`.

- `load_defaults.rs`
  Load a config store from defaults and read values through `ConfigStore::read`.
- `layered_sources.rs`
  Build a store from a config file plus CLI overrides.
- `runtime_updates.rs`
  Apply `RuntimeOnly` and `RuntimeAndPersist` updates and show what is, and is
  not, written back to disk.

Run an example from the repository root:

```bash
cargo run -p selvedge-config --example load_defaults
cargo run -p selvedge-config --example layered_sources
cargo run -p selvedge-config --example runtime_updates
```
