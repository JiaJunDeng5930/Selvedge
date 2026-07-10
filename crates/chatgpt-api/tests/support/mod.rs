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

pub fn init_authenticated_api_test(base_url: &str) -> TempDir {
    let tempdir = init_api_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.settings]
issuer = "http://127.0.0.1:1"

[llm.providers.chatgpt]
base_url = "{base_url}"
"#,
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(serde_json::json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );
    tempdir
}
