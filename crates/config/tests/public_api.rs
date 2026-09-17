use std::{env, fs, process::Command};

use selvedge_config::{
    init_with_cli, read, selvedge_home, update_runtime, update_runtime_and_persist,
};
use selvedge_config_model::LogFilter;
use tempfile::TempDir;

#[test]
fn public_api_supports_singleton_read_runtime_update_persist_and_cli_precedence() {
    let tempdir = TempDir::new().expect("tempdir");
    let config_home = tempdir.path().join(".selvedge");
    let config_path = config_home.join("config.toml");

    fs::create_dir_all(&config_home).expect("create config home");

    fs::write(
        &config_path,
        r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000

[logging]
level = "info"
"#,
    )
    .expect("write config file");

    init_with_cli(
        Some(config_home.clone()),
        vec![
            ("server.port".to_owned(), "9100".to_owned()),
            ("server.request_timeout_ms".to_owned(), "10000".to_owned()),
        ],
    )
    .expect("init config");

    let before = read(|config| {
        (
            config.server.port,
            config.harness.max_children_per_fork,
            config.logging.level,
        )
    })
    .expect("read before update");

    assert_eq!(before, (9100, 5, LogFilter::Info));

    update_runtime("harness.max_children_per_fork", 10_u32).expect("set fork limit");
    update_runtime_and_persist("logging.level", "debug").expect("persist logging level");

    let after = read(|config| {
        (
            config.server.port,
            config.harness.max_children_per_fork,
            config.logging.level,
        )
    })
    .expect("read after update");
    let persisted = fs::read_to_string(config_path).expect("read persisted file");
    let selected_home = selvedge_home().expect("read selected home");

    assert_eq!(after, (9100, 10, LogFilter::Debug));
    assert_eq!(
        selected_home,
        fs::canonicalize(config_home).expect("canonicalize config home")
    );
    assert!(persisted.contains("level = \"debug\""));
    assert!(!persisted.contains("max_children_per_fork = 10"));
    let loaded = read(|config| (config.server.port, config.server.request_timeout_ms))
        .expect("read config with cli overrides");

    assert_eq!(loaded, (9100, 10_000));
}

#[test]
fn environment_overrides_preserve_dynamic_keys_through_public_api() {
    if env::var_os("SELVEDGE_CONFIG_ENV_DYNAMIC_CHILD").is_some() {
        println!("ENV_DYNAMIC_REGRESSION_EXECUTED");
        let tempdir = TempDir::new().expect("tempdir");
        let config_home = tempdir.path().join(".selvedge");
        let config_path = config_home.join("config.toml");

        fs::create_dir_all(&config_home).expect("create config home");
        fs::write(
            &config_path,
            r#"
[mcp.servers."acme.tools"]
command = "mcp-server"
[mcp.servers."acme.tools".env]
LOG_LEVEL = "info"

[mcp.servers."Acme.Tools"]
command = "mcp-server"
[mcp.servers."Acme.Tools".env]
LOG_LEVEL = "info"

[llm.providers."Acme.API".settings]
ReasoningMode = "fast"
"#,
        )
        .expect("write config file");

        init_with_cli(Some(config_home), Vec::<(String, String)>::new()).expect("init config");

        let observed = read(|config| {
            (
                config.mcp.servers["acme.tools"]
                    .env
                    .get("LOG_LEVEL")
                    .cloned(),
                config.mcp.servers["Acme.Tools"]
                    .env
                    .get("LOG_LEVEL")
                    .cloned(),
                config.llm.providers["Acme.API"].settings["ReasoningMode"]
                    .as_str()
                    .map(str::to_owned),
            )
        })
        .expect("read environment overrides");

        assert_eq!(
            observed,
            (
                Some("debug".to_owned()),
                Some("trace".to_owned()),
                Some("deep".to_owned()),
            )
        );
        return;
    }

    let current_executable = env::current_exe().expect("current test executable");
    let output = Command::new(current_executable)
        .arg("--nocapture")
        .arg("--exact")
        .arg("environment_overrides_preserve_dynamic_keys_through_public_api")
        .env_clear()
        .env("SELVEDGE_CONFIG_ENV_DYNAMIC_CHILD", "1")
        .env(
            "SELVEDGE_APP_MCP__SERVERS__acme.tools__ENV__LOG_LEVEL",
            "debug",
        )
        .env(
            "SELVEDGE_APP_MCP__SERVERS__Acme.Tools__ENV__LOG_LEVEL",
            "trace",
        )
        .env(
            "SELVEDGE_APP_LLM__PROVIDERS__Acme.API__SETTINGS__ReasoningMode",
            "deep",
        )
        .output()
        .expect("run environment override child test");

    assert!(output.status.success(), "child test failed: {output:?}");
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(
        stdout.contains("ENV_DYNAMIC_REGRESSION_EXECUTED")
            || stderr.contains("ENV_DYNAMIC_REGRESSION_EXECUTED"),
        "child test did not execute the regression body: {output:?}"
    );
}
