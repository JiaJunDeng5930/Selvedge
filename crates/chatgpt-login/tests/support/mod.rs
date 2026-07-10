use tempfile::TempDir;

pub use selvedge_test_support::http::spawn_http_server;
pub use selvedge_test_support::process::{assert_child_success, child_mode, run_child};

pub fn init_login_test(config_body: &str) -> TempDir {
    selvedge_test_support::config::init_test_home(config_body)
}
