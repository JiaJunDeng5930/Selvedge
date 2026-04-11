use std::{
    net::SocketAddr,
    process::{Child, Command, Output},
};

use axum::Router;
use tempfile::TempDir;
use tokio::{net::TcpListener, task::JoinHandle};

pub fn child_mode(flag: &str) -> bool {
    std::env::var_os(flag).is_some()
}

pub fn run_child(test_name: &str, flag: &str) -> Output {
    let current_executable = std::env::current_exe().expect("current test executable");

    Command::new(current_executable)
        .arg("--exact")
        .arg(test_name)
        .env(flag, "1")
        .output()
        .expect("run child test")
}

pub fn spawn_child(test_name: &str, flag: &str, extra_envs: &[(&str, &str)]) -> Child {
    let current_executable = std::env::current_exe().expect("current test executable");
    let mut command = Command::new(current_executable);

    command.arg("--exact").arg(test_name).env(flag, "1");

    for (key, value) in extra_envs {
        command.env(key, value);
    }

    command.spawn().expect("spawn child test")
}

pub fn assert_child_success(output: &Output) {
    assert!(output.status.success(), "child test failed: {output:?}");
}

pub fn init_auth_test(config_body: &str) -> TempDir {
    let tempdir = TempDir::new().expect("tempdir");
    let config_home = tempdir.path().join(".selvedge");
    let config_path = config_home.join("config.toml");

    std::fs::create_dir_all(&config_home).expect("create config home");
    std::fs::write(&config_path, config_body).expect("write config");

    selvedge_config::init_with_home(&config_home).expect("init config");
    selvedge_logging::init().expect("init logging");

    tempdir
}

pub fn write_auth_file(tempdir: &TempDir, auth_file_body: &str) -> std::path::PathBuf {
    let auth_file_path = tempdir.path().join(".selvedge/auth/chatgpt-auth.json");
    std::fs::create_dir_all(
        auth_file_path
            .parent()
            .expect("auth file path must have parent"),
    )
    .expect("create auth dir");
    std::fs::write(&auth_file_path, auth_file_body).expect("write auth file");

    auth_file_path
}

pub struct TestServer {
    pub addr: SocketAddr,
    handle: JoinHandle<()>,
}

impl TestServer {
    pub fn url(&self, path: &str) -> String {
        format!("http://{}{}", self.addr, path)
    }
}

impl Drop for TestServer {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

pub async fn spawn_http_server(router: Router) -> TestServer {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind test server");
    let addr = listener.local_addr().expect("local addr");
    let handle = tokio::spawn(async move {
        axum::serve(listener, router).await.expect("serve test app");
    });

    TestServer { addr, handle }
}
