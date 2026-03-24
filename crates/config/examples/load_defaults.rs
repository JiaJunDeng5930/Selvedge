use selvedge_config::{init, read};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    init()?;

    let summary = read(|config| {
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
