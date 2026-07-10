use std::process::{Command, Stdio};
use std::time::{Duration, Instant};
use tempfile::TempDir;

#[test]
fn binary_usage_error_reports_stderr_without_creating_config() {
    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    let expected_config = tempdir.path().join(".selvedge/config.toml");
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

    assert!(!output.status.success(), "binary should fail without args");

    let stdout = String::from_utf8(output.stdout).expect("stdout utf8");
    let stderr = String::from_utf8(output.stderr).expect("stderr utf8");

    assert_eq!(stdout.trim(), "");
    assert_eq!(stderr.trim(), "Invalid arguments: missing --client-id");
    assert!(
        !expected_config.exists(),
        "usage errors must not create config"
    );
}

#[test]
fn usage_error_skips_xdg_bootstrap_when_home_is_missing() {
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

    assert!(!output.status.success(), "binary should fail without args");
    assert!(
        !expected_config.exists(),
        "usage error must skip xdg bootstrap"
    );
}

#[test]
fn usage_error_skips_bootstrap_when_home_path_is_missing() {
    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    let missing_home = tempdir.path().join("missing-home");
    let expected_config = tempdir.path().join("xdg-home/selvedge/config.toml");

    command.env_remove("SELVEDGE_HOME");
    command.env_remove("SELVEDGE_CONFIG");
    command.env("HOME", &missing_home);
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

    assert!(!output.status.success(), "binary should fail without args");
    assert!(
        !expected_config.exists(),
        "usage error must skip xdg bootstrap"
    );
    assert!(
        !missing_home.join(".selvedge/config.toml").exists(),
        "missing home path should not be bootstrapped"
    );
}

#[cfg(unix)]
#[test]
fn usage_error_skips_writable_home_fallback() {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    let tempdir = TempDir::new().expect("tempdir");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    let home_dir = tempdir.path().join("readonly-home");
    let xdg_dir = tempdir.path().join("xdg-home");
    let expected_config = xdg_dir.join("selvedge/config.toml");
    let home_config = home_dir.join(".selvedge/config.toml");

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

    assert!(!output.status.success(), "binary should fail without args");
    assert!(
        !expected_config.exists(),
        "usage error must skip xdg fallback"
    );
    assert!(
        !home_config.exists(),
        "usage error must skip home bootstrap"
    );
}

#[test]
fn usage_error_skips_config_home_discovery() {
    let tempdir = TempDir::new().expect("tempdir");
    let work_dir = tempdir.path().join("workspace");
    let home_dir = tempdir.path().join("user-home");
    let valid_home = home_dir.join(".selvedge");
    let valid_config = valid_home.join("config.toml");
    let xdg_config = tempdir.path().join("xdg-home/selvedge/config.toml");
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

    assert!(!output.status.success(), "binary should fail without args");
    assert!(!xdg_config.exists(), "usage error must skip home discovery");
}

#[cfg(unix)]
#[test]
fn server_sigint_runs_supervised_shutdown_and_exits_130() {
    let tempdir = TempDir::new().expect("tempdir");
    let port = released_loopback_port();
    let lock_path = tempdir.path().join("server.lock");
    let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
    command
        .arg("server")
        .env("SELVEDGE_HOME", tempdir.path())
        .env("SELVEDGE_APP_SERVER__PORT", port.to_string())
        .stdout(Stdio::null())
        .stderr(Stdio::piped());
    let mut child = command.spawn().expect("spawn server");
    let deadline = Instant::now() + Duration::from_secs(5);
    let ready = loop {
        if lock_path.exists() && std::net::TcpStream::connect(("127.0.0.1", port)).is_ok() {
            break true;
        }
        if child.try_wait().expect("poll server").is_some() || Instant::now() >= deadline {
            break false;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    if !ready {
        let _ = child.kill();
        let output = child.wait_with_output().expect("collect failed server");
        panic!(
            "server did not become ready: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    let signal_status = Command::new("kill")
        .args(["-INT", &child.id().to_string()])
        .status()
        .expect("send SIGINT");
    assert!(signal_status.success(), "kill must deliver SIGINT");
    let output = child
        .wait_with_output()
        .expect("wait for graceful shutdown");

    assert_eq!(output.status.code(), Some(130));
    assert!(!lock_path.exists(), "supervised shutdown must remove lock");
}

fn released_loopback_port() -> u16 {
    let listener = std::net::TcpListener::bind(("127.0.0.1", 0)).expect("bind test port");
    listener.local_addr().expect("test port address").port()
}
