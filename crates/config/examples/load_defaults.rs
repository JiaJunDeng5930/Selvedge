use selvedge_config::{ConfigStore, LoadSpec};
use selvedge_config_model::{AppConfig, default_app_config, validate_app_config};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let store = ConfigStore::load(
        LoadSpec {
            explicit_file_path: None,
            file_path_candidates: Vec::new(),
            env_prefix: "SELVEDGE_APP".to_owned(),
            cli_overrides: Vec::new(),
        },
        default_app_config,
        validate_app_config,
    )?;

    let summary = store.read(|config: &AppConfig| {
        format!(
            "server={}://{}:{} timeout={}ms log_level={}",
            "http",
            config.server.host,
            config.server.port,
            config.server.request_timeout_ms,
            config.logging.level,
        )
    })?;

    println!("{summary}");

    Ok(())
}
