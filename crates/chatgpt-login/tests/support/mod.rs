use std::{
    net::SocketAddr,
    process::{Command, Output},
};

use axum::Router;
use tempfile::TempDir;
use tokio::{net::TcpListener, task::JoinHandle};

// @intent selvedge.login.tests Login integration test helpers create isolated config, HTTP server, and child process fixtures.
// @intent selvedge.login.tests.child_mode Login integration tests isolate global config state by rerunning selected cases in child processes.
pub fn child_mode(flag: &str) -> bool {
    std::env::var_os(flag).is_some()
}

// @intent selvedge.login.tests.run_child Login integration tests execute a named child test with an environment flag for process-local config isolation.
pub fn run_child(test_name: &str, flag: &str) -> Output {
    let current_executable = std::env::current_exe().expect("current test executable");

    Command::new(current_executable)
        .arg("--exact")
        .arg(test_name)
        .env(flag, "1")
        .output()
        .expect("run child test")
}

// @intent selvedge.login.tests.child_success Login integration tests report child process failures through the parent test assertion output.
pub fn assert_child_success(output: &Output) {
    // @verifies selvedge.login
    assert!(output.status.success(), "child test failed: {output:?}");
}

// @intent selvedge.login.tests.init Login integration tests create isolated Selvedge homes with per-test ChatGPT auth configuration.
pub fn init_login_test(config_body: &str) -> TempDir {
    let tempdir = TempDir::new().expect("tempdir");
    let config_home = tempdir.path().join(".selvedge");
    let config_path = config_home.join("config.toml");

    std::fs::create_dir_all(&config_home).expect("create config home");
    std::fs::write(&config_path, config_body).expect("write config");

    selvedge_config::init_with_home(&config_home).expect("init config");
    selvedge_logging::init().expect("init logging");

    tempdir
}

// @intent selvedge.login.tests.server Login integration tests use an in-process HTTP server to observe and shape device-code provider interactions.
pub struct TestServer {
    pub addr: SocketAddr,
    handle: JoinHandle<()>,
}

// @intent selvedge.login.tests.server_url Login integration tests build provider URLs from the in-process test server address.
impl TestServer {
    pub fn url(&self, path: &str) -> String {
        format!("http://{}{}", self.addr, path)
    }
}

// @intent selvedge.login.tests.server_drop Login integration tests stop in-process HTTP servers when the server handle leaves scope.
impl Drop for TestServer {
    fn drop(&mut self) {
        self.handle.abort();
    }
}

// @intent selvedge.login.tests.spawn_server Login integration tests bind an ephemeral local HTTP server for provider responses.
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
