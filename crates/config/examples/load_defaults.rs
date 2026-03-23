use selvedge_config::AppConfigStore;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let store = AppConfigStore::load()?;

    let summary = store.read(|config| {
        format!(
            "server=http://{}:{} timeout={}ms log_level={}",
            config.server.host,
            config.server.port,
            config.server.request_timeout_ms,
            config.logging.level,
        )
    })?;

    println!("{summary}");

    Ok(())
}
