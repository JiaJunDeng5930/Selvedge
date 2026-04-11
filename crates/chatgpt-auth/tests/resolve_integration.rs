mod support;

use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};
#[cfg(unix)]
use std::{fs, os::unix::fs::PermissionsExt};

use axum::{Json, Router, extract::State, http::StatusCode, routing::post};
use base64::Engine;
use chatgpt_auth::{ChatgptAuthError, resolve_after_unauthorized, resolve_for_request};
use http::{HeaderMap, HeaderValue};
use serde_json::json;
use support::{
    assert_child_success, child_mode, init_auth_test, run_child, spawn_child, spawn_http_server,
    write_auth_file,
};

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_returns_current_auth_without_refresh() {
    const FLAG: &str = "CHATGPT_AUTH_RESOLVE_DIRECT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_returns_current_auth_without_refresh",
            FLAG,
        ));
        return;
    }

    let tempdir = init_auth_test(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"
"#,
    );
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "email": "user@example.com",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123",
                "https://api.openai.com/auth.chatgpt_user_id": "user-456",
                "https://api.openai.com/auth.chatgpt_plan_type": "plus"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let resolved = resolve_for_request().await.expect("resolve auth");

    assert_eq!(resolved.access_token, "opaque-access-token");
    assert_eq!(resolved.access_token_expires_at, None);
    assert_eq!(resolved.account_id, "workspace-123");
    assert_eq!(resolved.user_id.as_deref(), Some("user-456"));
    assert_eq!(resolved.email.as_deref(), Some("user@example.com"));
    assert_eq!(resolved.plan_type.as_deref(), Some("plus"));
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_refreshes_expired_access_token_and_persists_result() {
    const FLAG: &str = "CHATGPT_AUTH_REFRESH_EXPIRED_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_refreshes_expired_access_token_and_persists_result",
            FLAG,
        ));
        return;
    }

    let refresh_hits = Arc::new(AtomicUsize::new(0));
    let refresh_hits_for_state = Arc::clone(&refresh_hits);
    let refreshed_id_token = build_jwt(json!({
        "sub": "subject",
        "email": "user@example.com",
        "https://api.openai.com/auth.chatgpt_account_id": "workspace-123",
        "https://api.openai.com/auth.chatgpt_user_id": "user-456"
    }));
    let server = spawn_http_server(
        Router::new()
            .route(
                "/oauth/token",
                post(move |State(hits): State<Arc<AtomicUsize>>| {
                    let refreshed_id_token = refreshed_id_token.clone();
                    async move {
                        hits.fetch_add(1, Ordering::SeqCst);
                        Json(json!({
                            "id_token": refreshed_id_token,
                            "access_token": "new-access-token"
                        }))
                    }
                }),
            )
            .with_state(refresh_hits_for_state),
    )
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            &build_jwt(json!({
                "exp": 1
            })),
            "refresh-token",
        ),
    );

    let resolved = resolve_for_request().await.expect("resolve auth");
    let persisted = std::fs::read_to_string(&auth_file_path).expect("read persisted auth file");

    assert_eq!(refresh_hits.load(Ordering::SeqCst), 1);
    assert_eq!(resolved.access_token, "new-access-token");
    assert_eq!(resolved.account_id, "workspace-123");
    assert!(persisted.contains("\"access_token\":\"new-access-token\""));
    assert!(persisted.contains("\"refresh_token\":\"refresh-token\""));
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_after_unauthorized_always_refreshes() {
    const FLAG: &str = "CHATGPT_AUTH_FORCE_REFRESH_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_after_unauthorized_always_refreshes",
            FLAG,
        ));
        return;
    }

    let refresh_hits = Arc::new(AtomicUsize::new(0));
    let refresh_hits_for_state = Arc::clone(&refresh_hits);
    let server = spawn_http_server(
        Router::new()
            .route(
                "/oauth/token",
                post(|State(hits): State<Arc<AtomicUsize>>| async move {
                    hits.fetch_add(1, Ordering::SeqCst);
                    Json(json!({
                        "access_token": "refreshed-access-token"
                    }))
                }),
            )
            .with_state(refresh_hits_for_state),
    )
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "still-valid-access-token",
            "refresh-token",
        ),
    );

    let resolved = resolve_after_unauthorized()
        .await
        .expect("force refresh auth");

    assert_eq!(refresh_hits.load(Ordering::SeqCst), 1);
    assert_eq!(resolved.access_token, "refreshed-access-token");
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_sends_refresh_request_as_form_data() {
    const FLAG: &str = "CHATGPT_AUTH_REFRESH_FORM_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_sends_refresh_request_as_form_data",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(|headers: HeaderMap, body: String| async move {
            let expected_content_type =
                HeaderValue::from_static("application/x-www-form-urlencoded");
            let has_expected_content_type = headers
                .get(http::header::CONTENT_TYPE)
                .is_some_and(|value| value == expected_content_type);
            let has_expected_body = body.contains("grant_type=refresh_token")
                && body.contains("client_id=app_EMoamEEZ73f0CkXaXp7hrann")
                && body.contains("refresh_token=refresh-token");

            if has_expected_content_type && has_expected_body {
                (
                    StatusCode::OK,
                    Json(json!({
                        "id_token": build_jwt(json!({
                            "sub": "subject",
                            "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
                        })),
                        "access_token": "new-access-token"
                    })),
                )
            } else {
                (
                    StatusCode::UNSUPPORTED_MEDIA_TYPE,
                    Json(json!({
                        "error": "bad_request_encoding"
                    })),
                )
            }
        }),
    ))
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject"
            })),
            &build_jwt(json!({
                "exp": 1
            })),
            "refresh-token",
        ),
    );

    let resolved = resolve_for_request().await.expect("refresh with form body");

    assert_eq!(resolved.access_token, "new-access-token");
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_returns_auth_file_read_failed_when_path_is_directory() {
    const FLAG: &str = "CHATGPT_AUTH_READ_FAILED_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_returns_auth_file_read_failed_when_path_is_directory",
            FLAG,
        ));
        return;
    }

    let tempdir = init_auth_test(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"
"#,
    );
    let auth_file_path = tempdir.path().join(".selvedge/auth/chatgpt-auth.json");
    std::fs::create_dir_all(&auth_file_path).expect("create directory at auth file path");

    let error = resolve_for_request()
        .await
        .expect_err("directory path must fail to read");

    assert!(matches!(
        error,
        ChatgptAuthError::AuthFileReadFailed { path, .. } if path == auth_file_path
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_returns_auth_file_missing_when_file_is_absent() {
    const FLAG: &str = "CHATGPT_AUTH_FILE_MISSING_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_returns_auth_file_missing_when_file_is_absent",
            FLAG,
        ));
        return;
    }

    let tempdir = init_auth_test(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"
"#,
    );
    let expected_path = tempdir.path().join(".selvedge/auth/chatgpt-auth.json");

    let error = resolve_for_request()
        .await
        .expect_err("missing auth file must fail");

    assert!(matches!(
        error,
        ChatgptAuthError::AuthFileMissing { path } if path == expected_path
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_maps_illegal_success_response_to_refresh_failed() {
    const FLAG: &str = "CHATGPT_AUTH_ILLEGAL_SUCCESS_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_maps_illegal_success_response_to_refresh_failed",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(|| async { (StatusCode::OK, "not-json") }),
    ))
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );
    let original = std::fs::read_to_string(&auth_file_path).expect("read original auth file");

    let error = resolve_for_request()
        .await
        .expect_err("illegal success response must fail");

    assert!(matches!(
        error,
        ChatgptAuthError::RefreshFailed {
            status: Some(200),
            ..
        }
    ));
    assert_eq!(
        std::fs::read_to_string(&auth_file_path).expect("read original auth file"),
        original
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_rejects_refresh_without_new_id_token_when_old_one_is_unusable() {
    const FLAG: &str = "CHATGPT_AUTH_MISSING_REPLACEMENT_ID_TOKEN_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_rejects_refresh_without_new_id_token_when_old_one_is_unusable",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(|| async {
            Json(json!({
                "access_token": "new-access-token"
            }))
        }),
    ))
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );
    let original = std::fs::read_to_string(&auth_file_path).expect("read original auth file");

    let error = resolve_for_request()
        .await
        .expect_err("missing replacement id token must fail");

    assert!(matches!(
        error,
        ChatgptAuthError::RefreshFailed {
            status: Some(200),
            ..
        }
    ));
    assert_eq!(
        std::fs::read_to_string(&auth_file_path).expect("read original auth file"),
        original
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_maps_unauthorized_refresh_to_reauthentication_required() {
    const FLAG: &str = "CHATGPT_AUTH_REAUTH_REQUIRED_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_maps_unauthorized_refresh_to_reauthentication_required",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(|| async {
            (
                StatusCode::UNAUTHORIZED,
                Json(json!({
                    "error": "refresh_token_expired",
                    "message": "token expired"
                })),
            )
        }),
    ))
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let error = resolve_for_request()
        .await
        .expect_err("unauthorized refresh must fail");

    assert!(matches!(
        error,
        ChatgptAuthError::ReauthenticationRequired {
            provider_code,
            provider_message
        } if provider_code.as_deref() == Some("refresh_token_expired")
            && provider_message.as_deref() == Some("token expired")
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_maps_invalid_grant_refresh_to_reauthentication_required() {
    const FLAG: &str = "CHATGPT_AUTH_INVALID_GRANT_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_maps_invalid_grant_refresh_to_reauthentication_required",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(|| async {
            (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": "invalid_grant",
                    "message": "refresh token expired"
                })),
            )
        }),
    ))
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let error = resolve_for_request()
        .await
        .expect_err("invalid grant must require reauthentication");

    assert!(matches!(
        error,
        ChatgptAuthError::ReauthenticationRequired {
            provider_code,
            provider_message
        } if provider_code.as_deref() == Some("invalid_grant")
            && provider_message.as_deref() == Some("refresh token expired")
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_maps_plain_unauthorized_refresh_to_refresh_failed() {
    const FLAG: &str = "CHATGPT_AUTH_PLAIN_401_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_maps_plain_unauthorized_refresh_to_refresh_failed",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(|| async {
            (
                StatusCode::UNAUTHORIZED,
                Json(json!({
                    "message": "unauthorized client"
                })),
            )
        }),
    ))
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let error = resolve_for_request()
        .await
        .expect_err("plain unauthorized must stay refresh failed");

    assert!(matches!(
        error,
        ChatgptAuthError::RefreshFailed {
            status: Some(401),
            provider_code: None,
            provider_message
        } if provider_message.as_deref() == Some("unauthorized client")
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_rejects_workspace_mismatch() {
    const FLAG: &str = "CHATGPT_AUTH_WORKSPACE_MISMATCH_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_rejects_workspace_mismatch",
            FLAG,
        ));
        return;
    }

    let tempdir = init_auth_test(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"
expected_workspace_id = "workspace-expected"
"#,
    );
    write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-actual"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );

    let error = resolve_for_request()
        .await
        .expect_err("workspace mismatch must fail");

    assert!(matches!(
        error,
        ChatgptAuthError::WorkspaceMismatch { expected, actual }
            if expected == "workspace-expected"
                && actual.as_deref() == Some("workspace-actual")
    ));
}

#[cfg(unix)]
#[tokio::test(flavor = "multi_thread")]
async fn resolve_after_unauthorized_does_not_persist_workspace_mismatch_from_refresh() {
    const FLAG: &str = "CHATGPT_AUTH_REFRESH_WORKSPACE_MISMATCH_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_after_unauthorized_does_not_persist_workspace_mismatch_from_refresh",
            FLAG,
        ));
        return;
    }

    let mismatched_id_token = build_jwt(json!({
        "sub": "subject",
        "https://api.openai.com/auth.chatgpt_account_id": "workspace-actual"
    }));
    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(move || {
            let mismatched_id_token = mismatched_id_token.clone();
            async move {
                Json(json!({
                    "id_token": mismatched_id_token,
                    "access_token": "new-access-token"
                }))
            }
        }),
    ))
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
expected_workspace_id = "workspace-expected"
"#,
        server.url("")
    ));
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-expected"
            })),
            "still-valid-access-token",
            "refresh-token",
        ),
    );
    let original = fs::read_to_string(&auth_file_path).expect("read original auth file");

    let error = resolve_after_unauthorized()
        .await
        .expect_err("mismatched workspace refresh must fail");

    assert!(matches!(
        error,
        ChatgptAuthError::WorkspaceMismatch { expected, actual }
            if expected == "workspace-expected"
                && actual.as_deref() == Some("workspace-actual")
    ));
    assert_eq!(
        fs::read_to_string(&auth_file_path).expect("read original auth file"),
        original
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_after_unauthorized_rejects_refresh_response_without_access_token() {
    const FLAG: &str = "CHATGPT_AUTH_FORCE_REFRESH_MISSING_ACCESS_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_after_unauthorized_rejects_refresh_response_without_access_token",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(|| async {
            Json(json!({
                "id_token": build_jwt(json!({
                    "sub": "subject",
                    "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
                }))
            }))
        }),
    ))
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "known-bad-access-token",
            "refresh-token",
        ),
    );
    let original = fs::read_to_string(&auth_file_path).expect("read original auth file");

    let error = resolve_after_unauthorized()
        .await
        .expect_err("refresh without access token must fail");

    assert!(matches!(
        error,
        ChatgptAuthError::RefreshFailed {
            status: Some(200),
            ..
        }
    ));
    assert_eq!(
        fs::read_to_string(&auth_file_path).expect("read original auth file"),
        original
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn resolve_after_unauthorized_rejects_refresh_response_with_unchanged_access_token() {
    const FLAG: &str = "CHATGPT_AUTH_FORCE_REFRESH_UNCHANGED_ACCESS_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_after_unauthorized_rejects_refresh_response_with_unchanged_access_token",
            FLAG,
        ));
        return;
    }

    let unchanged_access_token = "known-bad-access-token";
    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(move || async move {
            Json(json!({
                "id_token": build_jwt(json!({
                    "sub": "subject",
                    "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
                })),
                "access_token": unchanged_access_token
            }))
        }),
    ))
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            unchanged_access_token,
            "refresh-token",
        ),
    );
    let original = std::fs::read_to_string(&auth_file_path).expect("read original auth file");

    let error = resolve_after_unauthorized()
        .await
        .expect_err("unchanged forced-refresh access token must fail");

    assert!(matches!(
        error,
        ChatgptAuthError::RefreshFailed {
            status: Some(200),
            ..
        }
    ));
    assert_eq!(
        std::fs::read_to_string(&auth_file_path).expect("read original auth file"),
        original
    );
}

#[cfg(unix)]
#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_returns_error_when_lock_file_cannot_be_created() {
    const FLAG: &str = "CHATGPT_AUTH_LOCK_PERMISSION_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_returns_error_when_lock_file_cannot_be_created",
            FLAG,
        ));
        return;
    }

    let tempdir = init_auth_test(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "http://127.0.0.1:1"
"#,
    );
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "opaque-access-token",
            "refresh-token",
        ),
    );
    let selvedge_home = tempdir.path().join(".selvedge");
    let lock_file_path = selvedge_home.join(".chatgpt-auth.lock");
    let mut readonly_permissions = fs::metadata(&selvedge_home)
        .expect("selvedge home metadata")
        .permissions();
    readonly_permissions.set_mode(0o500);
    fs::set_permissions(&selvedge_home, readonly_permissions)
        .expect("make selvedge home read-only");

    let error = resolve_for_request()
        .await
        .expect_err("lock creation failure must return an error");

    let mut restored_permissions = fs::metadata(&selvedge_home)
        .expect("selvedge home metadata")
        .permissions();
    restored_permissions.set_mode(0o700);
    fs::set_permissions(&selvedge_home, restored_permissions)
        .expect("restore selvedge home permissions");

    assert!(!lock_file_path.exists());
    assert!(matches!(
        error,
        ChatgptAuthError::AuthFileReadFailed { path, .. } if path == auth_file_path
    ));
}

#[cfg(unix)]
#[tokio::test(flavor = "multi_thread")]
async fn resolve_for_request_preserves_original_file_when_persist_fails() {
    const FLAG: &str = "CHATGPT_AUTH_PERSIST_FAILED_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "resolve_for_request_preserves_original_file_when_persist_fails",
            FLAG,
        ));
        return;
    }

    let refreshed_id_token = build_jwt(json!({
        "sub": "subject",
        "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
    }));
    let server = spawn_http_server(Router::new().route(
        "/oauth/token",
        post(move || {
            let refreshed_id_token = refreshed_id_token.clone();
            async move {
                Json(json!({
                    "id_token": refreshed_id_token,
                    "access_token": "new-access-token"
                }))
            }
        }),
    ))
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            &build_jwt(json!({
                "exp": 1
            })),
            "refresh-token",
        ),
    );
    let original = fs::read_to_string(&auth_file_path).expect("read original auth file");
    let auth_dir = auth_file_path
        .parent()
        .expect("auth file path must have parent");
    let original_permissions = fs::metadata(auth_dir)
        .expect("auth dir metadata")
        .permissions();
    let mut readonly_permissions = original_permissions.clone();
    readonly_permissions.set_mode(0o500);
    fs::set_permissions(auth_dir, readonly_permissions).expect("make auth dir read-only");

    let error = resolve_for_request()
        .await
        .expect_err("persist must fail when auth dir is read-only");

    let mut restored_permissions = original_permissions;
    restored_permissions.set_mode(0o700);
    fs::set_permissions(auth_dir, restored_permissions).expect("restore auth dir permissions");

    assert!(matches!(error, ChatgptAuthError::PersistFailed { .. }));
    assert_eq!(
        fs::read_to_string(&auth_file_path).expect("read original auth file"),
        original
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn concurrent_calls_refresh_once_for_same_auth_file() {
    const FLAG: &str = "CHATGPT_AUTH_CONCURRENT_REFRESH_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "concurrent_calls_refresh_once_for_same_auth_file",
            FLAG,
        ));
        return;
    }

    let refresh_hits = Arc::new(AtomicUsize::new(0));
    let refresh_hits_for_state = Arc::clone(&refresh_hits);
    let refreshed_id_token = build_jwt(json!({
        "sub": "subject",
        "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
    }));
    let server = spawn_http_server(
        Router::new()
            .route(
                "/oauth/token",
                post(move |State(hits): State<Arc<AtomicUsize>>| {
                    let refreshed_id_token = refreshed_id_token.clone();
                    async move {
                        hits.fetch_add(1, Ordering::SeqCst);
                        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                        Json(json!({
                            "id_token": refreshed_id_token,
                            "access_token": "new-access-token",
                            "refresh_token": "new-refresh-token"
                        }))
                    }
                }),
            )
            .with_state(refresh_hits_for_state),
    )
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject"
            })),
            &build_jwt(json!({
                "exp": 1
            })),
            "refresh-token",
        ),
    );

    let (first, second, third) = tokio::join!(
        resolve_for_request(),
        resolve_for_request(),
        resolve_for_request()
    );

    let first = first.expect("first resolve");
    let second = second.expect("second resolve");
    let third = third.expect("third resolve");
    let persisted = std::fs::read_to_string(&auth_file_path).expect("read persisted auth file");

    assert_eq!(refresh_hits.load(Ordering::SeqCst), 1);
    assert_eq!(first.access_token, "new-access-token");
    assert_eq!(second.access_token, "new-access-token");
    assert_eq!(third.access_token, "new-access-token");
    assert!(persisted.contains("\"refresh_token\":\"new-refresh-token\""));
}

#[tokio::test(flavor = "multi_thread")]
async fn concurrent_forced_refresh_calls_reuse_first_persisted_result() {
    const FLAG: &str = "CHATGPT_AUTH_CONCURRENT_FORCE_REFRESH_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "concurrent_forced_refresh_calls_reuse_first_persisted_result",
            FLAG,
        ));
        return;
    }

    let refresh_hits = Arc::new(AtomicUsize::new(0));
    let refresh_hits_for_state = Arc::clone(&refresh_hits);
    let refreshed_id_token = build_jwt(json!({
        "sub": "subject",
        "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
    }));
    let server = spawn_http_server(
        Router::new()
            .route(
                "/oauth/token",
                post(move |State(hits): State<Arc<AtomicUsize>>| {
                    let refreshed_id_token = refreshed_id_token.clone();
                    async move {
                        hits.fetch_add(1, Ordering::SeqCst);
                        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                        Json(json!({
                            "id_token": refreshed_id_token,
                            "access_token": "new-access-token",
                            "refresh_token": "new-refresh-token"
                        }))
                    }
                }),
            )
            .with_state(refresh_hits_for_state),
    )
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject",
                "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
            })),
            "known-bad-access-token",
            "refresh-token",
        ),
    );

    let (first, second, third) = tokio::join!(
        resolve_after_unauthorized(),
        resolve_after_unauthorized(),
        resolve_after_unauthorized()
    );

    let first = first.expect("first resolve");
    let second = second.expect("second resolve");
    let third = third.expect("third resolve");
    let persisted = std::fs::read_to_string(&auth_file_path).expect("read persisted auth file");

    assert_eq!(refresh_hits.load(Ordering::SeqCst), 1);
    assert_eq!(first.access_token, "new-access-token");
    assert_eq!(second.access_token, "new-access-token");
    assert_eq!(third.access_token, "new-access-token");
    assert!(persisted.contains("\"refresh_token\":\"new-refresh-token\""));
}

#[tokio::test(flavor = "multi_thread")]
async fn refresh_is_serialized_across_processes() {
    const FLAG: &str = "CHATGPT_AUTH_MULTI_PROCESS_CHILD";
    const HOME_ENV: &str = "CHATGPT_AUTH_SHARED_HOME";

    if child_mode(FLAG) {
        let config_home =
            std::path::PathBuf::from(std::env::var(HOME_ENV).expect("shared home env must exist"));

        selvedge_config::init_with_home(&config_home).expect("init config");
        selvedge_logging::init().expect("init logging");

        let resolved = resolve_for_request().await.expect("child resolve");
        assert_eq!(resolved.access_token, "new-access-token");
        return;
    }

    let refresh_hits = Arc::new(AtomicUsize::new(0));
    let refresh_hits_for_state = Arc::clone(&refresh_hits);
    let refreshed_id_token = build_jwt(json!({
        "sub": "subject",
        "https://api.openai.com/auth.chatgpt_account_id": "workspace-123"
    }));
    let server = spawn_http_server(
        Router::new()
            .route(
                "/oauth/token",
                post(move |State(hits): State<Arc<AtomicUsize>>| {
                    let refreshed_id_token = refreshed_id_token.clone();
                    async move {
                        hits.fetch_add(1, Ordering::SeqCst);
                        tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                        Json(json!({
                            "id_token": refreshed_id_token,
                            "access_token": "new-access-token",
                            "refresh_token": "new-refresh-token"
                        }))
                    }
                }),
            )
            .with_state(refresh_hits_for_state),
    )
    .await;

    let tempdir = init_auth_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));
    let config_home = tempdir.path().join(".selvedge");
    let auth_file_path = write_auth_file(
        &tempdir,
        &auth_file_json(
            &build_jwt(json!({
                "sub": "subject"
            })),
            &build_jwt(json!({
                "exp": 1
            })),
            "refresh-token",
        ),
    );
    let config_home_text = config_home.to_string_lossy().into_owned();
    let child = spawn_child(
        "refresh_is_serialized_across_processes",
        FLAG,
        &[(HOME_ENV, &config_home_text)],
    );

    tokio::time::sleep(std::time::Duration::from_millis(20)).await;

    let resolved = resolve_for_request().await.expect("parent resolve");
    let child_output = child.wait_with_output().expect("wait for child");
    let persisted = std::fs::read_to_string(&auth_file_path).expect("read persisted auth file");

    assert_child_success(&child_output);
    assert_eq!(refresh_hits.load(Ordering::SeqCst), 1);
    assert_eq!(resolved.access_token, "new-access-token");
    assert!(persisted.contains("\"refresh_token\":\"new-refresh-token\""));
}

fn auth_file_json(id_token: &str, access_token: &str, refresh_token: &str) -> String {
    json!({
        "schema_version": 1,
        "provider": "chatgpt",
        "login_method": "device_code",
        "tokens": {
            "id_token": id_token,
            "access_token": access_token,
            "refresh_token": refresh_token
        }
    })
    .to_string()
}

fn build_jwt(payload: serde_json::Value) -> String {
    let engine = base64::engine::general_purpose::URL_SAFE_NO_PAD;
    let header = engine.encode(r#"{"alg":"none","typ":"JWT"}"#);
    let payload = engine.encode(payload.to_string());

    format!("{header}.{payload}.signature")
}
