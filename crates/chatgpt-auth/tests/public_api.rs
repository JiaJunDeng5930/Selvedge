use std::{path::PathBuf, time::Duration};

use chatgpt_auth::{
    ChatgptAuthConfig, ChatgptAuthError, ChatgptAuthFile, ChatgptAuthFileWriteError,
    ChatgptAuthParseError, ChatgptJwtClaims, ChatgptStoredTokens, JwtParseError,
    ResolvedChatgptAuth, chatgpt_auth_file_path, parse_auth_file, parse_chatgpt_jwt_claims,
    persist_chatgpt_auth_file, read_chatgpt_auth_config, resolve_after_unauthorized,
    resolve_for_request,
};
use chrono::{TimeZone, Utc};

#[test]
fn public_api_exposes_chatgpt_auth_types_and_functions() {
    let auth_file = ChatgptAuthFile {
        schema_version: 1,
        provider: "chatgpt".to_owned(),
        credential_kind: "login".to_owned(),
        tokens: ChatgptStoredTokens {
            id_token: "id-token".to_owned(),
            access_token: "access-token".to_owned(),
            refresh_token: "refresh-token".to_owned(),
        },
    };
    let claims = ChatgptJwtClaims {
        subject: Some("subject".to_owned()),
        account_id: Some("account-id".to_owned()),
        user_id: Some("user-id".to_owned()),
        email: Some("user@example.com".to_owned()),
        plan_type: Some("plus".to_owned()),
        expires_at: Some(
            Utc.timestamp_opt(1_700_000_000, 0)
                .single()
                .expect("expires_at"),
        ),
    };
    let resolved = ResolvedChatgptAuth {
        access_token: "access-token".to_owned(),
        access_token_expires_at: Some(
            Utc.timestamp_opt(1_700_000_100, 0)
                .single()
                .expect("access token expiration"),
        ),
        account_id: Some("account-id".to_owned()),
        user_id: Some("user-id".to_owned()),
        email: Some("user@example.com".to_owned()),
        plan_type: Some("plus".to_owned()),
    };

    assert_eq!(auth_file.tokens.refresh_token, "refresh-token");
    assert_eq!(claims.account_id.as_deref(), Some("account-id"));
    assert_eq!(resolved.account_id.as_deref(), Some("account-id"));
    assert!(matches!(
        JwtParseError::InvalidFormat,
        JwtParseError::InvalidFormat
    ));
    assert!(matches!(
        ChatgptAuthParseError::MissingField { field: "tokens" },
        ChatgptAuthParseError::MissingField { .. }
    ));
    let error = ChatgptAuthError::AuthFileReadFailed {
        path: PathBuf::from("/tmp/chatgpt-auth.json"),
        reason: "permission denied".to_owned(),
    };
    assert!(matches!(error, ChatgptAuthError::AuthFileReadFailed { .. }));
    let _ = Duration::from_secs(1);
    let _ = resolve_for_request;
    let _ = resolve_after_unauthorized;
    let _ = parse_auth_file;
    let _ = parse_chatgpt_jwt_claims;
    let _ = read_chatgpt_auth_config;
    let _ = chatgpt_auth_file_path;
    let _ = persist_chatgpt_auth_file;
    let _ = std::mem::size_of::<ChatgptAuthConfig>();
    let _ = std::mem::size_of::<ChatgptAuthFileWriteError>();
}

#[test]
fn public_writer_rejects_empty_tokens_without_replacing_file() {
    let tempdir = tempfile::tempdir().expect("temp dir");
    let path = tempdir.path().join("chatgpt.json");
    std::fs::write(&path, "existing credentials").expect("write existing file");
    let tokens = ChatgptStoredTokens {
        id_token: "id-token".to_owned(),
        access_token: String::new(),
        refresh_token: "refresh-token".to_owned(),
    };

    let error = persist_chatgpt_auth_file(&path, &tokens).expect_err("empty token must fail");

    assert_eq!(error.path, path);
    assert_eq!(error.reason, "tokens.access_token must not be empty");
    assert_eq!(
        std::fs::read_to_string(&path).expect("read existing file"),
        "existing credentials"
    );
}
