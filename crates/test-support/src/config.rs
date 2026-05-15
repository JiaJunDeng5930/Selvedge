use tempfile::TempDir;

// @behavior selvedge.testsupport.config Temporary config homes initialize Selvedge global config and logging state from caller-provided TOML.
pub fn init_test_home(config_body: &str) -> TempDir {
    let tempdir = TempDir::new().expect("tempdir");
    let config_home = tempdir.path().join(".selvedge");
    let config_path = config_home.join("config.toml");

    std::fs::create_dir_all(&config_home).expect("create config home");
    std::fs::write(&config_path, config_body).expect("write config");

    selvedge_config::init_with_home(&config_home).expect("init config");
    // @behavior selvedge.testsupport.config.logging Temporary config homes initialize logging after the caller-provided config path is installed.
    selvedge_logging::init().expect("init logging");

    tempdir
}
