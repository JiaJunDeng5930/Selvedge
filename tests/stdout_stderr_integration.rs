use std::process::Command;
use tempfile::TempDir;

#[test]
fn binary_keeps_logs_off_stdout() {
    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    command.env_remove("SELVEDGE_HOME");
    command.env_remove("SELVEDGE_CONFIG");
    command.env("HOME", tempdir.path());
    command.env("XDG_CONFIG_HOME", tempdir.path());

    for (key, _) in std::env::vars_os() {
        if key
            .to_str()
            .is_some_and(|name| name.starts_with("SELVEDGE_APP_"))
        {
            command.env_remove(key);
        }
    }

    let output = command.output().expect("run selvedge binary");

    assert!(output.status.success(), "binary failed: {output:?}");

    let stdout = String::from_utf8(output.stdout).expect("stdout utf8");
    let stderr = String::from_utf8(output.stderr).expect("stderr utf8");

    assert_eq!(stdout.trim(), "selvedge is ready.");
    assert!(stderr.contains("message=\"selvedge started\""));
}

#[test]
fn binary_creates_default_selvedge_home_when_missing() {
    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    let expected_config = tempdir.path().join(".selvedge/config.toml");

    command.env_remove("SELVEDGE_HOME");
    command.env_remove("SELVEDGE_CONFIG");
    command.env("HOME", tempdir.path());
    command.env("XDG_CONFIG_HOME", tempdir.path().join("xdg-home"));

    for (key, _) in std::env::vars_os() {
        if key
            .to_str()
            .is_some_and(|name| name.starts_with("SELVEDGE_APP_"))
        {
            command.env_remove(key);
        }
    }

    let output = command.output().expect("run selvedge binary");

    assert!(output.status.success(), "binary failed: {output:?}");
    assert!(expected_config.is_file(), "default config was not created");
}

#[test]
fn binary_bootstraps_under_xdg_when_home_is_missing() {
    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    let expected_config = tempdir.path().join("xdg-home/selvedge/config.toml");

    command.env_remove("SELVEDGE_HOME");
    command.env_remove("SELVEDGE_CONFIG");
    command.env_remove("HOME");
    command.env("XDG_CONFIG_HOME", tempdir.path().join("xdg-home"));

    for (key, _) in std::env::vars_os() {
        if key
            .to_str()
            .is_some_and(|name| name.starts_with("SELVEDGE_APP_"))
        {
            command.env_remove(key);
        }
    }

    let output = command.output().expect("run selvedge binary");

    assert!(output.status.success(), "binary failed: {output:?}");
    assert!(expected_config.is_file(), "xdg config was not created");
}

#[test]
fn failed_init_does_not_create_default_home() {
    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    let expected_config = tempdir.path().join(".selvedge/config.toml");

    command.env_remove("SELVEDGE_HOME");
    command.env_remove("SELVEDGE_CONFIG");
    command.env("HOME", tempdir.path());
    command.env("XDG_CONFIG_HOME", tempdir.path().join("xdg-home"));
    command.env("SELVEDGE_APP_SERVER__PORT", "\"not-a-port\"");

    let output = command.output().expect("run selvedge binary");

    assert!(!output.status.success(), "binary unexpectedly succeeded");
    assert!(
        !expected_config.exists(),
        "default config should not be created on failed init"
    );
}

#[test]
fn legacy_selvedge_config_env_is_rejected_explicitly() {
    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    let legacy_config = tempdir.path().join("selvedge.toml");

    std::fs::write(
        &legacy_config,
        r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000
        "#,
    )
    .expect("write legacy config");

    command.env_remove("SELVEDGE_HOME");
    command.env("SELVEDGE_CONFIG", &legacy_config);

    let output = command.output().expect("run selvedge binary");
    let stderr = String::from_utf8(output.stderr).expect("stderr utf8");

    assert!(!output.status.success(), "binary unexpectedly succeeded");
    assert!(
        stderr.contains("LegacyConfigEnvUnsupported") || stderr.contains("SELVEDGE_CONFIG"),
        "stderr was: {stderr}"
    );
}

#[cfg(unix)]
#[test]
fn binary_falls_back_when_home_is_not_writable() {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    let home_dir = tempdir.path().join("readonly-home");
    let xdg_dir = tempdir.path().join("xdg-home");
    let expected_config = xdg_dir.join("selvedge/config.toml");

    fs::create_dir_all(&home_dir).expect("create home dir");
    fs::set_permissions(&home_dir, fs::Permissions::from_mode(0o555))
        .expect("set readonly permissions");

    command.env_remove("SELVEDGE_HOME");
    command.env_remove("SELVEDGE_CONFIG");
    command.env("HOME", &home_dir);
    command.env("XDG_CONFIG_HOME", &xdg_dir);

    for (key, _) in std::env::vars_os() {
        if key
            .to_str()
            .is_some_and(|name| name.starts_with("SELVEDGE_APP_"))
        {
            command.env_remove(key);
        }
    }

    let output = command.output().expect("run selvedge binary");

    assert!(output.status.success(), "binary failed: {output:?}");
    assert!(expected_config.is_file(), "xdg config was not created");
}

#[test]
fn incomplete_local_home_does_not_block_valid_user_home() {
    let tempdir = TempDir::new().expect("tempdir");
    let work_dir = tempdir.path().join("workspace");
    let home_dir = tempdir.path().join("user-home");
    let valid_home = home_dir.join(".selvedge");
    let valid_config = valid_home.join("config.toml");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));

    std::fs::create_dir_all(work_dir.join(".selvedge")).expect("create incomplete local home");
    std::fs::create_dir_all(&valid_home).expect("create valid home");
    std::fs::write(
        &valid_config,
        r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000

[logging]
level = "info"
        "#,
    )
    .expect("write valid config");

    command.current_dir(&work_dir);
    command.env_remove("SELVEDGE_HOME");
    command.env_remove("SELVEDGE_CONFIG");
    command.env("HOME", &home_dir);
    command.env("XDG_CONFIG_HOME", tempdir.path().join("xdg-home"));

    let output = command.output().expect("run selvedge binary");

    assert!(output.status.success(), "binary failed: {output:?}");
}

#[test]
fn malformed_user_home_is_not_silently_skipped() {
    let tempdir = TempDir::new().expect("tempdir");
    let work_dir = tempdir.path().join("workspace");
    let home_dir = tempdir.path().join("user-home");
    let malformed_home = home_dir.join(".config/selvedge");
    let fallback_home = home_dir.join(".selvedge");
    let fallback_config = fallback_home.join("config.toml");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));

    std::fs::create_dir_all(&work_dir).expect("create work dir");
    std::fs::create_dir_all(&malformed_home).expect("create malformed home");
    std::fs::create_dir_all(&fallback_home).expect("create fallback home");
    std::fs::write(
        &fallback_config,
        r#"
[server]
host = "127.0.0.1"
port = 8080
request_timeout_ms = 5000
        "#,
    )
    .expect("write fallback config");

    command.current_dir(&work_dir);
    command.env_remove("SELVEDGE_HOME");
    command.env_remove("SELVEDGE_CONFIG");
    command.env("HOME", &home_dir);
    command.env("XDG_CONFIG_HOME", tempdir.path().join("xdg-home"));

    let output = command.output().expect("run selvedge binary");

    assert!(!output.status.success(), "binary unexpectedly succeeded");
}
