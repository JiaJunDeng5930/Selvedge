mod support;

use axum::{Json, Router, routing::post};
use chatgpt_login::{
    ChatgptLoginError, DeviceCodeChallenge, DeviceCodePollOutcome, poll_device_code_login,
    start_device_code_login,
};
use serde_json::json;
use support::{assert_child_success, child_mode, init_login_test, run_child, spawn_http_server};

#[tokio::test(flavor = "multi_thread")]
async fn start_device_code_login_returns_challenge_from_provider_response() {
    const FLAG: &str = "CHATGPT_LOGIN_START_SUCCESS_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "start_device_code_login_returns_challenge_from_provider_response",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/api/accounts/deviceauth/usercode",
        post(|| async {
            Json(json!({
                "device_auth_id": "device-auth-id",
                "user_code": "ABCD-EFGH",
                "interval": "5"
            }))
        }),
    ))
    .await;

    let _tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));

    let challenge = start_device_code_login()
        .await
        .expect("start device code login");

    assert_eq!(
        challenge.verification_url,
        format!("{}/codex/device", server.url(""))
    );
    assert_eq!(challenge.user_code, "ABCD-EFGH");
    assert_eq!(challenge.device_auth_id, "device-auth-id");
    assert_eq!(challenge.poll_interval.as_secs(), 5);
    assert_eq!(
        challenge
            .expires_at
            .signed_duration_since(challenge.issued_at),
        chrono::Duration::minutes(15)
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn poll_device_code_login_returns_pending_for_forbidden_response() {
    const FLAG: &str = "CHATGPT_LOGIN_POLL_PENDING_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "poll_device_code_login_returns_pending_for_forbidden_response",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/api/accounts/deviceauth/token",
        post(|| async { axum::http::StatusCode::FORBIDDEN }),
    ))
    .await;

    let _tempdir = init_login_test(&format!(
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

    let outcome = poll_device_code_login(&challenge)
        .await
        .expect("poll device code login");

    assert!(matches!(
        outcome,
        DeviceCodePollOutcome::Pending {
            next_poll_after
        } if next_poll_after == std::time::Duration::from_secs(5)
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn poll_device_code_login_returns_authorization_from_success_response() {
    const FLAG: &str = "CHATGPT_LOGIN_POLL_AUTHORIZED_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "poll_device_code_login_returns_authorization_from_success_response",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/api/accounts/deviceauth/token",
        post(|| async {
            Json(json!({
                "authorization_code": "authorization-code",
                "code_verifier": "code-verifier"
            }))
        }),
    ))
    .await;

    let _tempdir = init_login_test(&format!(
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

    let outcome = poll_device_code_login(&challenge)
        .await
        .expect("poll device code login");

    assert!(matches!(
        outcome,
        DeviceCodePollOutcome::Authorized(authorization)
        if authorization.authorization_code == "authorization-code"
            && authorization.code_verifier == "code-verifier"
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn start_device_code_login_returns_unsupported_for_not_found() {
    const FLAG: &str = "CHATGPT_LOGIN_START_UNSUPPORTED_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "start_device_code_login_returns_unsupported_for_not_found",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/api/accounts/deviceauth/usercode",
        post(|| async { axum::http::StatusCode::NOT_FOUND }),
    ))
    .await;

    let _tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));

    let error = start_device_code_login()
        .await
        .expect_err("start must reject unsupported provider");

    assert!(matches!(error, ChatgptLoginError::DeviceCodeUnsupported));
}

#[tokio::test(flavor = "multi_thread")]
async fn start_device_code_login_rejects_invalid_success_body() {
    const FLAG: &str = "CHATGPT_LOGIN_START_INVALID_BODY_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "start_device_code_login_rejects_invalid_success_body",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/api/accounts/deviceauth/usercode",
        post(|| async {
            Json(json!({
                "device_auth_id": "device-auth-id",
                "user_code": "ABCD-EFGH"
            }))
        }),
    ))
    .await;

    let _tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));

    let error = start_device_code_login()
        .await
        .expect_err("start must reject invalid success body");

    assert!(matches!(
        error,
        ChatgptLoginError::DeviceCodeStartInvalidResponse { .. }
    ));
}

#[tokio::test(flavor = "multi_thread")]
async fn start_device_code_login_accepts_numeric_interval_values() {
    const FLAG: &str = "CHATGPT_LOGIN_START_NUMERIC_INTERVAL_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "start_device_code_login_accepts_numeric_interval_values",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/api/accounts/deviceauth/usercode",
        post(|| async {
            Json(json!({
                "device_auth_id": "device-auth-id",
                "user_code": "ABCD-EFGH",
                "interval": 7
            }))
        }),
    ))
    .await;

    let _tempdir = init_login_test(&format!(
        r#"
[logging]
level = "debug"

[llm.providers.chatgpt.auth]
issuer = "{}"
"#,
        server.url("")
    ));

    let challenge = start_device_code_login()
        .await
        .expect("numeric interval must be accepted");

    assert_eq!(challenge.poll_interval, std::time::Duration::from_secs(7));
}

#[tokio::test(flavor = "multi_thread")]
async fn poll_device_code_login_returns_expired_without_request() {
    const FLAG: &str = "CHATGPT_LOGIN_POLL_EXPIRED_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "poll_device_code_login_returns_expired_without_request",
            FLAG,
        ));
        return;
    }

    let _tempdir = init_login_test(
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

    let outcome = poll_device_code_login(&challenge)
        .await
        .expect("expired challenge should not error");

    assert!(matches!(outcome, DeviceCodePollOutcome::Expired));
}

#[tokio::test(flavor = "multi_thread")]
async fn poll_device_code_login_returns_pending_for_not_found_response() {
    const FLAG: &str = "CHATGPT_LOGIN_POLL_NOT_FOUND_CHILD";

    if !child_mode(FLAG) {
        assert_child_success(&run_child(
            "poll_device_code_login_returns_pending_for_not_found_response",
            FLAG,
        ));
        return;
    }

    let server = spawn_http_server(Router::new().route(
        "/api/accounts/deviceauth/token",
        post(|| async { axum::http::StatusCode::NOT_FOUND }),
    ))
    .await;

    let _tempdir = init_login_test(&format!(
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

    let outcome = poll_device_code_login(&challenge)
        .await
        .expect("404 must map to pending per contract");

    assert!(matches!(
        outcome,
        DeviceCodePollOutcome::Pending {
            next_poll_after
        } if next_poll_after == std::time::Duration::from_secs(5)
    ));
}
