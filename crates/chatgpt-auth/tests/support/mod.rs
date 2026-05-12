use std::{
    net::SocketAddr,
    process::{Child, Command, Output},
};

use axum::Router;
use tempfile::TempDir;
use tokio::{net::TcpListener, task::JoinHandle};

// @intent selvedge.auth.tests Auth integration test helpers create isolated config, auth file, HTTP server, and child process fixtures.
// @intent selvedge.auth.tests.child_mode Auth integration tests isolate global config state by rerunning selected cases in child processes.
pub fn child_mode(flag: &str) -> bool {
    std::env::var_os(flag).is_some()
}

// @intent selvedge.auth.tests.run_child Auth integration tests execute a named child test with an environment flag for process-local config isolation.
pub fn run_child(test_name: &str, flag: &str) -> Output {
    let current_executable = std::env::current_exe().expect("current test executable");

    Command::new(current_executable)
        .arg("--exact")
        .arg(test_name)
        .env(flag, "1")
        .output()
        .expect("run child test")
}

// @intent selvedge.auth.tests.spawn_child Auth integration tests spawn child processes to verify shared auth-file locking across processes.
pub fn spawn_child(test_name: &str, flag: &str, extra_envs: &[(&str, &str)]) -> Child {
    let current_executable = std::env::current_exe().expect("current test executable");
    let mut command = Command::new(current_executable);

    command.arg("--exact").arg(test_name).env(flag, "1");

    for (key, value) in extra_envs {
        command.env(key, value);
    }

    command.spawn().expect("spawn child test")
}

// @intent selvedge.auth.tests.child_success Auth integration tests report child process failures through the parent test assertion output.
pub fn assert_child_success(output: &Output) {
    // @verifies selvedge.auth
    assert!(output.status.success(), "child test failed: {output:?}");
}

// @intent selvedge.auth.tests.init Auth integration tests create isolated Selvedge homes with per-test ChatGPT auth configuration.
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

// @intent selvedge.auth.tests.write_auth_file Auth integration tests write local ChatGPT auth files under the isolated Selvedge home.
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

// @intent selvedge.auth.tests.server Auth integration tests use an in-process HTTP server to observe and shape refresh interactions.
pub struct TestServer {
    pub addr: SocketAddr,
    handle: JoinHandle<()>,
}

// @intent selvedge.auth.tests.server_url Auth integration tests build provider URLs from the in-process test server address.
impl TestServer {
    pub fn url(&self, path: &str) -> String {
        format!("http://{}{}", self.addr, path)
    }
}

// @intent selvedge.auth.tests.server_drop Auth integration tests stop in-process HTTP servers when the server handle leaves scope.
impl Drop for TestServer {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

// @intent selvedge.auth.tests.spawn_server Auth integration tests bind an ephemeral local HTTP server for provider refresh responses.
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
