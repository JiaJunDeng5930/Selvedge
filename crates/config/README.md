# config

## This crate is for

This crate is the public entrypoint for loading, reading, and updating runtime
configuration.

Callers use it to:

- build a config store from defaults, config files, environment variables, and
  CLI overrides
- read the current config view through `ConfigStore::read`
- apply runtime-only changes through `PersistMode::RuntimeOnly`
- apply runtime changes that are also written back to disk through
  `PersistMode::RuntimeAndPersist`

## This crate is not for

This crate is not for:

- defining your module's config schema
- storing module-specific business rules in the runtime layer
- exposing internal merge details or internal state to callers
- requiring callers to understand how the crate is implemented internally

Schema, defaults, and validation belong in the caller's config type or in the
schema crate used by the caller.

## Quick start

```no_run
use selvedge_config::{ConfigStore, LoadSpec, OverrideOp, PersistMode};
# use selvedge_config_model::{AppConfig, default_app_config, validate_app_config};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let store = ConfigStore::load(
        LoadSpec {
            explicit_file_path: None,
            file_path_candidates: vec!["./selvedge.toml".into()],
            env_prefix: "SELVEDGE_APP".to_owned(),
            cli_overrides: vec![OverrideOp::new("server.port", 9000_u16)],
        },
        default_app_config,
        validate_app_config,
    )?;

    let port = store.read(|config: &AppConfig| config.server.port)?;
    println!("listening on {port}");

    store.set(
        OverrideOp::new("logging.level", "debug"),
        PersistMode::RuntimeAndPersist,
    )?;

    Ok(())
}
```

## Add config for your module

When your module needs a new config field:

1. Add the field to your config type.
2. Add its default value there.
3. Add any cross-field validation there.
4. Read or update it through the existing public API in this crate.

Callers should not need to change `selvedge-config` internals when a new config
field is introduced.

## Read config

Use `ConfigStore::read` whenever your code needs the current config view.

Semantics:

- the callback sees the current effective config
- the effective config includes base config plus any runtime-only overrides
- callers do not get direct access to internal merge state

Example:

```no_run
# use selvedge_config::{ConfigStore, LoadSpec};
# use selvedge_config_model::{AppConfig, default_app_config, validate_app_config};
# let store = ConfigStore::load(
#     LoadSpec {
#         explicit_file_path: None,
#         file_path_candidates: Vec::new(),
#         env_prefix: "SELVEDGE_APP".to_owned(),
#         cli_overrides: Vec::new(),
#     },
#     default_app_config,
#     validate_app_config,
# )?;
let timeout_ms = store.read(|config: &AppConfig| config.server.request_timeout_ms)?;
# Ok::<(), Box<dyn std::error::Error>>(())
```

## Update runtime config

Use `ConfigStore::set(..., PersistMode::RuntimeOnly)` when the change should
affect only the current process.

Semantics:

- the new value is visible to later `read()` calls immediately
- the selected config file is not changed
- a failed update does not commit the new runtime state

Example:

```no_run
# use selvedge_config::{ConfigStore, LoadSpec, OverrideOp, PersistMode};
# use selvedge_config_model::{AppConfig, default_app_config, validate_app_config};
# let store = ConfigStore::load(
#     LoadSpec {
#         explicit_file_path: None,
#         file_path_candidates: Vec::new(),
#         env_prefix: "SELVEDGE_APP".to_owned(),
#         cli_overrides: Vec::new(),
#     },
#     default_app_config,
#     validate_app_config,
# )?;
store.set(
    OverrideOp::new("feature.rollout_percentage", 100_u8),
    PersistMode::RuntimeOnly,
)?;
# Ok::<(), Box<dyn std::error::Error>>(())
```

## Update runtime and persist

Use `ConfigStore::set(..., PersistMode::RuntimeAndPersist)` when the change
must both affect the current process and be written back to the selected config
file.

Semantics:

- the file target comes from `explicit_file_path` or `file_path_candidates`
- if no config file exists yet, the first candidate path becomes the persistence
  target
- runtime-only changes are not implicitly written to disk
- only durable state is written back

Example:

```no_run
# use selvedge_config::{ConfigStore, LoadSpec, OverrideOp, PersistMode};
# use selvedge_config_model::{AppConfig, default_app_config, validate_app_config};
# let store = ConfigStore::load(
#     LoadSpec {
#         explicit_file_path: Some("./selvedge.toml".into()),
#         file_path_candidates: Vec::new(),
#         env_prefix: "SELVEDGE_APP".to_owned(),
#         cli_overrides: Vec::new(),
#     },
#     default_app_config,
#     validate_app_config,
# )?;
store.set(
    OverrideOp::new("logging.level", "debug"),
    PersistMode::RuntimeAndPersist,
)?;
# Ok::<(), Box<dyn std::error::Error>>(())
```

## Errors and guarantees

- Invalid config values fail fast through `ConfigStore::load` or `ConfigStore::set`.
- A failed `RuntimeOnly` update does not change the visible runtime config.
- A failed `RuntimeAndPersist` update does not change the visible runtime config.
- Persisted writes validate the durable file state before they are committed.
- `read()` exposes only the current effective config, not internal merge state.
- Environment variables use keys such as `SELVEDGE_APP_SERVER__PORT=7001`.
- CLI overrides and runtime overrides use dot paths such as `server.port`.

Runnable examples are available in `crates/config/examples/`.
