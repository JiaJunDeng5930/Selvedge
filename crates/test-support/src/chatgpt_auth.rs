use base64::Engine;
use tempfile::TempDir;

// @behavior selvedge.testsupport.chatgpt_auth ChatGPT auth test support creates canonical auth-file and token fixtures.
// @behavior selvedge.testsupport.chatgpt_auth.write_file ChatGPT auth fixtures write the canonical test auth file under the temporary Selvedge home.
pub fn write_auth_file(tempdir: &TempDir, auth_file_body: &str) -> std::path::PathBuf {
    let auth_file_path = tempdir
        .path()
        .join(".selvedge/auth/model-providers/chatgpt.json");
    // @behavior selvedge.testsupport.chatgpt_auth.write_file.directory ChatGPT auth fixtures create the canonical credential directory before writing the fixture file.
    std::fs::create_dir_all(
        auth_file_path
            .parent()
            .expect("auth file path must have parent"),
    )
    .expect("create auth dir");
    // @behavior selvedge.testsupport.chatgpt_auth.write_file.persist ChatGPT auth fixtures persist the caller-provided auth body at the canonical credential path.
    std::fs::write(&auth_file_path, auth_file_body).expect("write auth file");

    auth_file_path
}

// @behavior selvedge.testsupport.chatgpt_auth.file_json ChatGPT auth fixtures serialize the current schema-one auth file shape.
pub fn auth_file_json(id_token: &str, access_token: &str, refresh_token: &str) -> String {
    serde_json::json!({
        "schema_version": 1,
        "provider": "chatgpt",
        "credential_kind": "login",
        "payload": {
            "tokens": {
                "id_token": id_token,
                "access_token": access_token,
                "refresh_token": refresh_token
            }
        }
    })
    .to_string()
}

// @behavior selvedge.testsupport.chatgpt_auth.jwt ChatGPT auth fixtures build unsigned JWT strings with caller-provided JSON claims.
pub fn build_unsigned_jwt(payload: serde_json::Value) -> String {
    let engine = base64::engine::general_purpose::URL_SAFE_NO_PAD;
    let header = engine.encode(r#"{"alg":"none","typ":"JWT"}"#);
    let payload = engine.encode(payload.to_string());

    format!("{header}.{payload}.signature")
}
