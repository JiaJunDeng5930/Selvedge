use tempfile::TempDir;

pub use selvedge_test_support::chatgpt_auth::{auth_file_json, build_unsigned_jwt as build_jwt};
pub use selvedge_test_support::http::spawn_http_server;
pub use selvedge_test_support::process::{assert_child_success, child_mode, run_child};

pub fn init_api_test(config_body: &str) -> TempDir {
    selvedge_test_support::config::init_test_home(config_body)
}

pub fn write_auth_file(tempdir: &TempDir, auth_file_body: &str) -> std::path::PathBuf {
    selvedge_test_support::chatgpt_auth::write_auth_file(tempdir, auth_file_body)
}
