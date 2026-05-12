use std::{
    net::SocketAddr,
    process::{Command, Output},
};

use axum::Router;
use tempfile::TempDir;
use tokio::{net::TcpListener, task::JoinHandle};

pub fn child_mode(flag: &str) -> bool {
    std::env::var_os(flag).is_some()
}

pub fn run_child(test_name: &str, flag: &str) -> Output {
    // @verifies selvedge.model.chatgpt.event.verify_surface
    let current_executable = std::env::current_exe().expect("current test executable");

    Command::new(current_executable)
        .arg("--exact")
        .arg(test_name)
        .env(flag, "1")
        .output()
        // @verifies selvedge.model.chatgpt.event.verify_surface
        .expect("run child test")
}

pub fn assert_child_success(output: &Output) {
    // @verifies selvedge.model.chatgpt.event.verify_surface
    assert!(output.status.success(), "child test failed: {output:?}");
}

pub fn init_api_test(config_body: &str) -> TempDir {
    // @verifies selvedge.model.chatgpt.event.verify_surface
    let tempdir = TempDir::new().expect("tempdir");
    let config_home = tempdir.path().join(".selvedge");
    let config_path = config_home.join("config.toml");

    // @verifies selvedge.model.chatgpt.event.verify_surface
    std::fs::create_dir_all(&config_home).expect("create config home");
    // @verifies selvedge.model.chatgpt.event.verify_surface
    std::fs::write(&config_path, config_body).expect("write config");

    // @verifies selvedge.model.chatgpt.event.verify_surface
    selvedge_config::init_with_home(&config_home).expect("init config");
    // @verifies selvedge.model.chatgpt.event.verify_surface
    selvedge_logging::init().expect("init logging");

    tempdir
}

pub fn write_auth_file(tempdir: &TempDir, auth_file_body: &str) -> std::path::PathBuf {
    let auth_file_path = tempdir.path().join(".selvedge/auth/chatgpt-auth.json");
    std::fs::create_dir_all(
        auth_file_path
            .parent()
            // @verifies selvedge.model.chatgpt.event.verify_surface
            .expect("auth file path must have parent"),
    )
    // @verifies selvedge.model.chatgpt.event.verify_surface
    .expect("create auth dir");
    // @verifies selvedge.model.chatgpt.event.verify_surface
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
        // @verifies selvedge.model.chatgpt.event.verify_surface
        .expect("bind test server");
    // @verifies selvedge.model.chatgpt.event.verify_surface
    let addr = listener.local_addr().expect("local addr");
    let handle = tokio::spawn(async move {
        // @verifies selvedge.model.chatgpt.event.verify_surface
        axum::serve(listener, router).await.expect("serve test app");
    });

    TestServer { addr, handle }
}
