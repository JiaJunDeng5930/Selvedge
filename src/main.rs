fn main() -> Result<(), Box<dyn std::error::Error>> {
    selvedge_config::init()?;
    selvedge_logging::init()?;
    selvedge_logging::selvedge_log!(selvedge_logging::LogLevel::Info, "selvedge started")?;
    println!("{}", selvedge::startup_message());

    Ok(())
}
