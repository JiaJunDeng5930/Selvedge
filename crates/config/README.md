# config

## This crate is for

This crate is the project-specific runtime config entrypoint.

Use it to:

- load the current project's `AppConfig`
- read the current effective config view
- apply runtime-only updates
- apply runtime updates and persist them back to the active config file

## This crate is not for

This crate is not for:

- defining config schema
- defining defaults
- defining validation rules
- exposing file search policy, environment prefixes, or patch internals to
  callers

Those responsibilities belong in `config-model` or stay private inside this
crate.

## Quick start

```no_run
use selvedge_config::AppConfigStore;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let store = AppConfigStore::load()?;
    let port = store.read(|config| config.server.port)?;

    println!("listening on {port}");

    store.update_runtime_and_persist("logging.level", "debug")?;

    Ok(())
}
```

## Add config for your module

When your module needs a new config field:

1. Change `config-model`.
2. Do not change this crate's load/update internals.
3. Read or update the new field through the existing public methods here.

This crate should stay unchanged when a module only adds new config fields.

## Read config

Use `AppConfigStore::read`.

Semantics:

- callers see the current effective config
- effective config = loaded base config + runtime-only patch
- callers never touch internal merge state or path selection state

```no_run
# use selvedge_config::AppConfigStore;
# let store = AppConfigStore::load()?;
let timeout_ms = store.read(|config| config.server.request_timeout_ms)?;
# Ok::<(), Box<dyn std::error::Error>>(())
```

## Update runtime config

Use `update_runtime(path, value)`.

Semantics:

- changes are visible to later `read()` calls immediately
- changes are not written to disk
- failure leaves visible runtime state unchanged

```no_run
# use selvedge_config::AppConfigStore;
# let store = AppConfigStore::load()?;
store.update_runtime("feature.rollout_percentage", 100_u8)?;
store.update_runtime("feature.enabled", true)?;
# Ok::<(), Box<dyn std::error::Error>>(())
```

## Update runtime and persist

Use `update_runtime_and_persist(path, value)`.

Semantics:

- the update changes the current runtime view
- the same update is validated against durable file state before writing
- runtime-only updates are not implicitly persisted
- if there is no active config file path, persistence fails

```no_run
# use selvedge_config::AppConfigStore;
# let store = AppConfigStore::load()?;
store.update_runtime_and_persist("logging.level", "debug")?;
# Ok::<(), Box<dyn std::error::Error>>(())
```

## Errors and guarantees

- `load()` searches config files in a fixed internal order.
- `load_with_explicit_path(path)` bypasses search and uses only that path.
- `SELVEDGE_CONFIG` overrides default search, but still must point to a real
  file.
- invalid explicit/env/searched paths fail fast
- failed updates do not commit runtime state
- failed persisted updates do not commit runtime state or file state

Runnable examples live in `crates/config/examples/`.
