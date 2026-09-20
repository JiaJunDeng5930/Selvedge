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
    use selvedge::{CliLocalClient, CliLocalClientConnector};
    use selvedge_local_client::{LocalClientConfig, LocalEndpoint};
    use selvedge_local_protocol::{ReadyRequest, ReadyState};

    let lock_path = tempdir.path().join("server.lock");
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("test runtime");
    let child = spawn_server_until(tempdir.path(), |port| {
        lock_path.exists()
            && runtime.block_on(async {
                let Ok(mut client) = selvedge::DefaultCliLocalClientConnector
                    .connect(LocalClientConfig {
                        endpoint: LocalEndpoint::TcpIpv4 { port },
                        request_timeout: Duration::from_millis(100),
                    })
                    .await
                else {
                    return false;
                };
                let ready = client
                    .ready(ReadyRequest {})
                    .await
                    .is_ok_and(|response| response.state == ReadyState::Ready);
                let _ = client.close().await;
                ready
            })
    });

    let signal_status = Command::new("kill")
        .args(["-INT", &child.id().to_string()])
        .status()
        .expect("send SIGINT");
    assert!(signal_status.success(), "kill must deliver SIGINT");
    let output = wait_for_interrupted_server(child);

    assert_eq!(output.status.code(), Some(130));
    assert!(
        lock_path.exists(),
        "supervised shutdown must retain the stable lock inode"
    );
}

#[cfg(unix)]
#[test]
fn server_sigint_cancels_stalled_mcp_startup_and_releases_lock() {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;

    let tempdir = TempDir::new().expect("tempdir");
    let lock_path = tempdir.path().join("server.lock");
    let startup_marker = tempdir.path().join("mcp-started");
    let mcp_script = tempdir.path().join("stall-mcp.sh");
    fs::write(&mcp_script, "#!/bin/sh\ntouch \"$1\"\nexec sleep 60\n")
        .expect("write stalled MCP script");
    fs::set_permissions(&mcp_script, fs::Permissions::from_mode(0o755))
        .expect("make MCP script executable");
    fs::write(
        tempdir.path().join("config.toml"),
        format!(
            "[mcp.servers.stalled]\ncommand = {:?}\nargs = [{:?}]\ntimeout_ms = 60000\n",
            mcp_script.to_string_lossy(),
            startup_marker.to_string_lossy(),
        ),
    )
    .expect("write MCP config");

    let child = spawn_server_until(tempdir.path(), |_| {
        lock_path.exists() && startup_marker.exists()
    });

    let signal_status = Command::new("kill")
        .args(["-INT", &child.id().to_string()])
        .status()
        .expect("send SIGINT");
    assert!(signal_status.success(), "kill must deliver SIGINT");
    let output = wait_for_interrupted_server(child);

    assert_eq!(output.status.code(), Some(130));
    assert!(
        lock_path.exists(),
        "cancelled startup must retain the stable lock inode"
    );
}

// The binary accepts an explicit nonzero port. The candidate is intentionally
// not treated as a reservation: retry only its observed bind-race failure.
#[cfg(unix)]
fn spawn_server_until(home: &std::path::Path, ready: impl Fn(u16) -> bool) -> std::process::Child {
    for attempt in 0..4 {
        let candidate =
            std::net::TcpListener::bind(("127.0.0.1", 0)).expect("choose candidate port");
        let port = candidate.local_addr().expect("candidate address").port();
        let mut command = Command::new(env!("CARGO_BIN_EXE_selvedge"));
        for (key, _) in std::env::vars_os() {
            if key
                .to_str()
                .is_some_and(|name| name.starts_with("SELVEDGE_APP_"))
            {
                command.env_remove(key);
            }
        }
        command
            .arg("server")
            .env("SELVEDGE_HOME", home)
            .env("SELVEDGE_APP_SERVER__PORT", port.to_string())
            .stdout(Stdio::null())
            .stderr(Stdio::piped());
        drop(candidate);
        let mut child = command.spawn().expect("spawn server");
        let started = Instant::now();
        // Newly linked macOS debug binaries containing static V8 can spend more than
        // five seconds in dyld before Rust main. Keep that loader allowance separate
        // from the five-second SIGINT shutdown contract below.
        let startup_budget = Duration::from_secs(if cfg!(target_os = "macos") { 15 } else { 5 });
        let deadline = started + startup_budget;
        let mut startup_timeout = false;
        let mut startup_files = Vec::new();
        loop {
            if child.try_wait().expect("poll server").is_some() {
                break;
            }
            if ready(port) {
                return child;
            }
            if Instant::now() >= deadline {
                startup_timeout = true;
                startup_files = std::fs::read_dir(home)
                    .expect("inspect unsuccessful startup")
                    .map(|entry| entry.expect("startup file").file_name())
                    .collect();
                // Give startup cancellation its normal cleanup path before forcing exit;
                // MCP descendants otherwise keep the stderr pipe open after server SIGKILL.
                let _ = Command::new("kill")
                    .args(["-INT", &child.id().to_string()])
                    .status();
                let cleanup_deadline = Instant::now() + Duration::from_secs(5);
                while child.try_wait().expect("poll startup cleanup").is_none() {
                    if Instant::now() >= cleanup_deadline {
                        let _ = child.kill();
                        break;
                    }
                    std::thread::sleep(Duration::from_millis(10));
                }
                break;
            }
            std::thread::sleep(Duration::from_millis(10));
        }
        let output = child
            .wait_with_output()
            .expect("collect unsuccessful startup");
        let stderr = String::from_utf8_lossy(&output.stderr);
        let address_in_use = stderr.contains("BindFailed")
            && (stderr.contains("os error 48") || stderr.contains("os error 98"));
        assert!(
            address_in_use && attempt < 3,
            "server did not reach expected startup state: status={}, timeout={startup_timeout}, elapsed={:?}, files={startup_files:?}, stderr={stderr}",
            output.status,
            started.elapsed()
        );
    }
    unreachable!("attempt limit returns or reports failure")
}

#[cfg(unix)]
fn wait_for_interrupted_server(mut child: std::process::Child) -> std::process::Output {
    let deadline = Instant::now() + Duration::from_secs(5);
    while child.try_wait().expect("poll interrupted server").is_none() {
        if Instant::now() >= deadline {
            let _ = child.kill();
            let output = child.wait_with_output().expect("collect stalled server");
            panic!(
                "SIGINT did not stop server: {}",
                String::from_utf8_lossy(&output.stderr)
            );
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    child
        .wait_with_output()
        .expect("collect interrupted server")
}
