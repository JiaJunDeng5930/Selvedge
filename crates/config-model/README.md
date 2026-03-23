# config-model

## This crate is for

This crate defines the application-facing config schema.

Use it to:

- declare config structs and nested config structs
- assign default values
- define validation rules that must hold for a valid config

## This crate is not for

This crate is not for:

- loading config from files, environment variables, or CLI arguments
- applying runtime patches
- persisting runtime changes back to disk

Those responsibilities belong in the runtime config crate.

## Quick start

```rust
use selvedge_config_model::{AppConfig, default_app_config, validate_app_config};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let config = default_app_config();
    validate_app_config(&config)?;

    println!("default port = {}", config.server.port);

    Ok(())
}
```

## Add config for your module

When your module needs new config:

1. Add a field to the appropriate config struct.
2. Add a default value.
3. Add validation if the new field participates in business constraints.

This crate is the place where schema evolution should happen.

## Read config

Callers read strongly typed fields from `AppConfig` and its nested structs.

Example:

```rust
use selvedge_config_model::default_app_config;

let config = default_app_config();
let timeout_ms = config.server.request_timeout_ms;
# let _ = timeout_ms;
```

## Validation

Use `validate_app_config` to reject invalid combinations before the config is
accepted by the rest of the system.
