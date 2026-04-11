mod support;

use std::fs::OpenOptions;

use axum::{Json, Router, routing::post};
use base64::Engine;
use chatgpt_login::{
    ChatgptLoginError, DeviceCodeAuthorization, DeviceCodeChallenge, complete_device_code_login,
};
use fs2::FileExt;
use serde_json::json;
use support::{assert_child_success, child_mode, init_login_test, run_child, spawn_http_server};
use tokio::time::sleep;

#[tokio::test(flavor = "multi_thread")]
async fn complete_device_code_login_persists_auth_file_and_returns_claims() {
    const FLAG: &str = "CHATGPT_LOGIN_COMPLETE_SUCCESS_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "complete_device_code_login_persists_auth_file_and_returns_claims",
            FLAG,
        ));
        return;
    }

    let id_token = build_test_jwt(json!({
        "https://api.openai.com/auth.chatgpt_account_id": "workspace-123",
        "https://api.openai.com/auth.chatgpt_user_id": "user-456",
        "https://api.openai.com/auth.chatgpt_plan_type": "plus",
        "email": "user@example.com"
    }));
    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(move || {
            let id_token = id_token.clone();
            async move {
                Json(json!({
                    "id_token": id_token,
                    "access_token": "access-token",
                    "refresh_token": "refresh-token"
                }))
            }
        }),
    ))
    .await;

    let tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));

    let challenge = DeviceCodeChallenge {
        verification_url: format!("{}/codex/device", server.url("")),
        user_code: "ABCD-EFGH".to_owned(),
        device_auth_id: "device-auth-id".to_owned(),
        poll_interval: std::time::Duration::from_secs(5),
        issued_at: chrono::Utc::now(),
        expires_at: chrono::Utc::now() + chrono::Duration::minutes(15),
    };
    let authorization = DeviceCodeAuthorization {
        authorization_code: "authorization-code".to_owned(),
        code_verifier: "code-verifier".to_owned(),
    };

    let result = complete_device_code_login(&challenge, authorization)
        .await
        .expect("complete device code login");
    let persisted_path = tempdir.path().join(".selvedge/auth/chatgpt-auth.json");
    let persisted = std::fs::read_to_string(&persisted_path).expect("read persisted auth file");

    assert_eq!(result.auth_file_path, persisted_path);
    assert_eq!(result.account_id, "workspace-123");
    assert_eq!(result.user_id.as_deref(), Some("user-456"));
    assert_eq!(result.email.as_deref(), Some("user@example.com"));
    assert_eq!(result.plan_type.as_deref(), Some("plus"));
    assert!(persisted.contains("\"schema_version\":1"));
    assert!(persisted.contains("\"provider\":\"chatgpt\""));
    assert!(persisted.contains("\"login_method\":\"device_code\""));
    assert!(persisted.contains("\"id_token\":\""));
    assert!(persisted.contains("\"access_token\":\"access-token\""));
    assert!(persisted.contains("\"refresh_token\":\"refresh-token\""));
}

#[tokio::test(flavor = "multi_thread")]
async fn complete_device_code_login_waits_for_auth_file_lock_before_persisting() {
    const FLAG: &str = "CHATGPT_LOGIN_COMPLETE_LOCK_WAIT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "complete_device_code_login_waits_for_auth_file_lock_before_persisting",
            FLAG,
        ));
        return;
    }

    let id_token = build_test_jwt(json!({
        "https://api.openai.com/auth.chatgpt_account_id": "workspace-123",
        "email": "user@example.com"
    }));
    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(move || {
            let id_token = id_token.clone();
            async move {
                Json(json!({
                    "id_token": id_token,
                    "access_token": "access-token",
                    "refresh_token": "refresh-token"
                }))
            }
        }),
    ))
    .await;

    let tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let persisted_path = tempdir.path().join(".selvedge/auth/chatgpt-auth.json");
    let lock_path = tempdir.path().join(".selvedge/.chatgpt-auth.lock");
    let lock_file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .read(true)
        .write(true)
        .open(&lock_path)
        .expect("open lock file");
    lock_file.lock_exclusive().expect("lock auth file");

    let challenge = DeviceCodeChallenge {
        verification_url: format!("{}/codex/device", server.url("")),
        user_code: "ABCD-EFGH".to_owned(),
        device_auth_id: "device-auth-id".to_owned(),
        poll_interval: std::time::Duration::from_secs(5),
        issued_at: chrono::Utc::now(),
        expires_at: chrono::Utc::now() + chrono::Duration::minutes(15),
    };
    let authorization = DeviceCodeAuthorization {
        authorization_code: "authorization-code".to_owned(),
        code_verifier: "code-verifier".to_owned(),
    };

    let login_task = tokio::spawn(async move {
        complete_device_code_login(&challenge, authorization)
            .await
            .expect("complete device code login")
    });

    sleep(std::time::Duration::from_millis(50)).await;
    assert!(!persisted_path.exists());

    lock_file.unlock().expect("unlock auth file");

    let result = login_task.await.expect("join login task");
    let persisted = std::fs::read_to_string(&persisted_path).expect("read persisted auth file");

    assert_eq!(result.auth_file_path, persisted_path);
    assert!(persisted.contains("\"access_token\":\"access-token\""));
}

#[tokio::test(flavor = "multi_thread")]
async fn complete_device_code_login_recreates_missing_selvedge_home_before_persisting() {
    const FLAG: &str = "CHATGPT_LOGIN_COMPLETE_RECREATE_HOME_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "complete_device_code_login_recreates_missing_selvedge_home_before_persisting",
            FLAG,
        ));
        return;
    }

    let id_token = build_test_jwt(json!({
        "https://api.openai.com/auth.chatgpt_account_id": "workspace-123",
        "email": "user@example.com"
    }));
    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(move || {
            let id_token = id_token.clone();
            async move {
                Json(json!({
                    "id_token": id_token,
                    "access_token": "access-token",
                    "refresh_token": "refresh-token"
                }))
            }
        }),
    ))
    .await;

    let tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let selvedge_home = tempdir.path().join(".selvedge");
    std::fs::remove_dir_all(&selvedge_home).expect("remove selvedge home");

    let challenge = DeviceCodeChallenge {
        verification_url: format!("{}/codex/device", server.url("")),
        user_code: "ABCD-EFGH".to_owned(),
        device_auth_id: "device-auth-id".to_owned(),
        poll_interval: std::time::Duration::from_secs(5),
        issued_at: chrono::Utc::now(),
        expires_at: chrono::Utc::now() + chrono::Duration::minutes(15),
    };
    let authorization = DeviceCodeAuthorization {
        authorization_code: "authorization-code".to_owned(),
        code_verifier: "code-verifier".to_owned(),
    };

    let result = complete_device_code_login(&challenge, authorization)
        .await
        .expect("complete device code login");
    let persisted_path = tempdir.path().join(".selvedge/auth/chatgpt-auth.json");
    let persisted = std::fs::read_to_string(&persisted_path).expect("read persisted auth file");

    assert_eq!(result.auth_file_path, persisted_path);
    assert!(persisted.contains("\"refresh_token\":\"refresh-token\""));
}

fn build_test_jwt(payload: serde_json::Value) -> String {
    let engine = base64::engine::general_purpose::URL_SAFE_NO_PAD;
    let header = engine.encode(r#"{"alg":"none","typ":"JWT"}"#);
    let payload = engine.encode(payload.to_string());

    format!("{header}.{payload}.signature")
}

fn build_test_jwt_with_header(header: &str, payload: serde_json::Value) -> String {
    let engine = base64::engine::general_purpose::URL_SAFE_NO_PAD;
    let payload = engine.encode(payload.to_string());

    format!("{header}.{payload}.signature")
}

#[tokio::test(flavor = "multi_thread")]
async fn complete_device_code_login_rejects_expired_challenge() {
    const FLAG: &str = "CHATGPT_LOGIN_COMPLETE_EXPIRED_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "complete_device_code_login_rejects_expired_challenge",
            FLAG,
        ));
        return;
    }

    let tempdir = init_login_test(
        r#"
[logging]
level = "debug"
"#,
    );
    let challenge = DeviceCodeChallenge {
        verification_url: "https://auth.openai.com/codex/device".to_owned(),
        user_code: "ABCD-EFGH".to_owned(),
        device_auth_id: "device-auth-id".to_owned(),
        poll_interval: std::time::Duration::from_secs(5),
        issued_at: chrono::Utc::now() - chrono::Duration::minutes(16),
        expires_at: chrono::Utc::now() - chrono::Duration::minutes(1),
    };
    let authorization = DeviceCodeAuthorization {
        authorization_code: "authorization-code".to_owned(),
        code_verifier: "code-verifier".to_owned(),
    };

    let error = complete_device_code_login(&challenge, authorization)
        .await
        .expect_err("expired challenge must fail");

    assert!(matches!(error, ChatgptLoginError::ChallengeExpired));
    assert!(
        !tempdir
            .path()
            .join(".selvedge/auth/chatgpt-auth.json")
            .exists()
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn complete_device_code_login_rejects_workspace_mismatch_without_overwriting_file() {
    const FLAG: &str = "CHATGPT_LOGIN_COMPLETE_WORKSPACE_MISMATCH_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "complete_device_code_login_rejects_workspace_mismatch_without_overwriting_file",
            FLAG,
        ));
        return;
    }

    let id_token = build_test_jwt(json!({
        "https://api.openai.com/auth.chatgpt_account_id": "workspace-actual",
        "email": "user@example.com"
    }));
    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(move || {
            let id_token = id_token.clone();
            async move {
                Json(json!({
                    "id_token": id_token,
                    "access_token": "access-token",
                    "refresh_token": "refresh-token"
                }))
            }
        }),
    ))
    .await;

    let tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
expected_workspace_id = "workspace-expected"
"#,
        server.url("")
    ));
    let persisted_path = tempdir.path().join(".selvedge/auth/chatgpt-auth.json");
    std::fs::create_dir_all(
        persisted_path
            .parent()
            .expect("persisted path must have parent"),
    )
    .expect("create auth dir");
    std::fs::write(&persisted_path, "original-auth-file").expect("write original auth file");

    let challenge = DeviceCodeChallenge {
        verification_url: format!("{}/codex/device", server.url("")),
        user_code: "ABCD-EFGH".to_owned(),
        device_auth_id: "device-auth-id".to_owned(),
        poll_interval: std::time::Duration::from_secs(5),
        issued_at: chrono::Utc::now(),
        expires_at: chrono::Utc::now() + chrono::Duration::minutes(15),
    };
    let authorization = DeviceCodeAuthorization {
        authorization_code: "authorization-code".to_owned(),
        code_verifier: "code-verifier".to_owned(),
    };

    let error = complete_device_code_login(&challenge, authorization)
        .await
        .expect_err("workspace mismatch must fail");

    assert!(matches!(
        error,
        ChatgptLoginError::WorkspaceMismatch {
            expected,
            actual
        } if expected == "workspace-expected" && actual.as_deref() == Some("workspace-actual")
    ));
    assert_eq!(
        std::fs::read_to_string(&persisted_path).expect("read original auth file"),
        "original-auth-file"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn complete_device_code_login_rejects_missing_account_id_claim() {
    const FLAG: &str = "CHATGPT_LOGIN_COMPLETE_INVALID_TOKEN_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "complete_device_code_login_rejects_missing_account_id_claim",
            FLAG,
        ));
        return;
    }

    let id_token = build_test_jwt(json!({
        "email": "user@example.com",
        "sub": "fallback-user-id"
    }));
    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(move || {
            let id_token = id_token.clone();
            async move {
                Json(json!({
                    "id_token": id_token,
                    "access_token": "access-token",
                    "refresh_token": "refresh-token"
                }))
            }
        }),
    ))
    .await;

    let tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let challenge = DeviceCodeChallenge {
        verification_url: format!("{}/codex/device", server.url("")),
        user_code: "ABCD-EFGH".to_owned(),
        device_auth_id: "device-auth-id".to_owned(),
        poll_interval: std::time::Duration::from_secs(5),
        issued_at: chrono::Utc::now(),
        expires_at: chrono::Utc::now() + chrono::Duration::minutes(15),
    };
    let authorization = DeviceCodeAuthorization {
        authorization_code: "authorization-code".to_owned(),
        code_verifier: "code-verifier".to_owned(),
    };

    let error = complete_device_code_login(&challenge, authorization)
        .await
        .expect_err("missing account_id must fail");

    assert!(matches!(error, ChatgptLoginError::InvalidTokenSet { .. }));
    assert!(
        !tempdir
            .path()
            .join(".selvedge/auth/chatgpt-auth.json")
            .exists()
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn complete_device_code_login_rejects_blank_account_id_claim() {
    const FLAG: &str = "CHATGPT_LOGIN_COMPLETE_BLANK_ACCOUNT_ID_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "complete_device_code_login_rejects_blank_account_id_claim",
            FLAG,
        ));
        return;
    }

    let id_token = build_test_jwt(json!({
        "https://api.openai.com/auth.chatgpt_account_id": "",
        "email": "user@example.com",
        "sub": "fallback-user-id"
    }));
    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(move || {
            let id_token = id_token.clone();
            async move {
                Json(json!({
                    "id_token": id_token,
                    "access_token": "access-token",
                    "refresh_token": "refresh-token"
                }))
            }
        }),
    ))
    .await;

    let tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let challenge = DeviceCodeChallenge {
        verification_url: format!("{}/codex/device", server.url("")),
        user_code: "ABCD-EFGH".to_owned(),
        device_auth_id: "device-auth-id".to_owned(),
        poll_interval: std::time::Duration::from_secs(5),
        issued_at: chrono::Utc::now(),
        expires_at: chrono::Utc::now() + chrono::Duration::minutes(15),
    };
    let authorization = DeviceCodeAuthorization {
        authorization_code: "authorization-code".to_owned(),
        code_verifier: "code-verifier".to_owned(),
    };

    let error = complete_device_code_login(&challenge, authorization)
        .await
        .expect_err("blank account_id must fail");

    assert!(matches!(error, ChatgptLoginError::InvalidTokenSet { .. }));
    assert!(
        !tempdir
            .path()
            .join(".selvedge/auth/chatgpt-auth.json")
            .exists()
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn complete_device_code_login_rejects_invalid_id_token_header() {
    const FLAG: &str = "CHATGPT_LOGIN_COMPLETE_INVALID_HEADER_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "complete_device_code_login_rejects_invalid_id_token_header",
            FLAG,
        ));
        return;
    }

    let id_token = build_test_jwt_with_header(
        "%%%invalid%%%",
        json!({
            "https://api.openai.com/auth.chatgpt_account_id": "workspace-123",
            "sub": "user-123"
        }),
    );
    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(move || {
            let id_token = id_token.clone();
            async move {
                Json(json!({
                    "id_token": id_token,
                    "access_token": "access-token",
                    "refresh_token": "refresh-token"
                }))
            }
        }),
    ))
    .await;

    let tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let challenge = DeviceCodeChallenge {
        verification_url: format!("{}/codex/device", server.url("")),
        user_code: "ABCD-EFGH".to_owned(),
        device_auth_id: "device-auth-id".to_owned(),
        poll_interval: std::time::Duration::from_secs(5),
        issued_at: chrono::Utc::now(),
        expires_at: chrono::Utc::now() + chrono::Duration::minutes(15),
    };
    let authorization = DeviceCodeAuthorization {
        authorization_code: "authorization-code".to_owned(),
        code_verifier: "code-verifier".to_owned(),
    };

    let error = complete_device_code_login(&challenge, authorization)
        .await
        .expect_err("invalid header must fail");

    assert!(matches!(error, ChatgptLoginError::InvalidTokenSet { .. }));
    assert!(
        !tempdir
            .path()
            .join(".selvedge/auth/chatgpt-auth.json")
            .exists()
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn complete_device_code_login_reads_current_issuer_from_runtime_config() {
    const FLAG: &str = "CHATGPT_LOGIN_COMPLETE_REFRESH_CONFIG_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "complete_device_code_login_reads_current_issuer_from_runtime_config",
            FLAG,
        ));
        return;
    }

    let old_server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(|| async {
            Json(json!({
                "id_token": build_test_jwt(json!({
                    "https://api.openai.com/auth.chatgpt_account_id": "workspace-old"
                })),
                "access_token": "access-old",
                "refresh_token": "refresh-old"
            }))
        }),
    ))
    .await;
    let new_server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(|| async {
            Json(json!({
                "id_token": build_test_jwt(json!({
                    "https://api.openai.com/auth.chatgpt_account_id": "workspace-new",
                    "sub": "user-new"
                })),
                "access_token": "access-new",
                "refresh_token": "refresh-new"
            }))
        }),
    ))
    .await;

    let tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        old_server.url("")
    ));
    selvedge_config::update_runtime("llm.providers.chatgpt.auth.issuer", new_server.url(""))
        .expect("update issuer");

    let challenge = DeviceCodeChallenge {
        verification_url: format!("{}/codex/device", old_server.url("")),
        user_code: "ABCD-EFGH".to_owned(),
        device_auth_id: "device-auth-id".to_owned(),
        poll_interval: std::time::Duration::from_secs(5),
        issued_at: chrono::Utc::now(),
        expires_at: chrono::Utc::now() + chrono::Duration::minutes(15),
    };
    let authorization = DeviceCodeAuthorization {
        authorization_code: "authorization-code".to_owned(),
        code_verifier: "code-verifier".to_owned(),
    };

    let result = complete_device_code_login(&challenge, authorization)
        .await
        .expect("complete with updated issuer");
    let persisted =
        std::fs::read_to_string(tempdir.path().join(".selvedge/auth/chatgpt-auth.json"))
            .expect("read persisted auth file");

    assert_eq!(result.account_id, "workspace-new");
    assert_eq!(result.user_id.as_deref(), Some("user-new"));
    assert!(persisted.contains("\"access_token\":\"access-new\""));
}
