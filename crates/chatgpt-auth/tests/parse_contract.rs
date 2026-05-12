use base64::Engine;
use chatgpt_auth::{
    ChatgptAuthParseError, JwtParseError, parse_auth_file, parse_chatgpt_jwt_claims,
};
use chrono::{TimeZone, Utc};

// @verifies selvedge.auth.file.parse.schema
#[test]
fn parse_auth_file_reads_valid_contract() {
    let parsed = parse_auth_file(
        br#"{
            "schema_version": 1,
            "provider": "chatgpt",
            "login_method": "device_code",
            "tokens": {
                "id_token": "id-token",
                "access_token": "access-token",
                "refresh_token": "refresh-token"
            }
        }"#,
    )
    .expect("parse auth file");

    // @verifies selvedge.auth
    assert_eq!(parsed.schema_version, 1);
    // @verifies selvedge.auth
    assert_eq!(parsed.provider, "chatgpt");
    // @verifies selvedge.auth
    assert_eq!(parsed.login_method, "device_code");
    // @verifies selvedge.auth
    assert_eq!(parsed.tokens.id_token, "id-token");
}

// @verifies selvedge.auth.file.tokens.required
#[test]
fn parse_auth_file_rejects_missing_required_token_field() {
    let error = parse_auth_file(
        br#"{
            "schema_version": 1,
            "provider": "chatgpt",
            "login_method": "device_code",
            "tokens": {
                "id_token": "id-token",
                "access_token": "access-token"
            }
        }"#,
    )
    .expect_err("missing refresh token must fail");

    // @verifies selvedge.auth
    assert!(matches!(
        error,
        ChatgptAuthParseError::MissingField {
            field: "tokens.refresh_token"
        }
    ));
}

// @verifies selvedge.auth.file.schema_version
#[test]
fn parse_auth_file_rejects_unsupported_schema_version() {
    let error = parse_auth_file(
        br#"{
            "schema_version": 2,
            "provider": "chatgpt",
            "login_method": "device_code",
            "tokens": {
                "id_token": "id-token",
                "access_token": "access-token",
                "refresh_token": "refresh-token"
            }
        }"#,
    )
    .expect_err("unsupported schema version must fail");

    // @verifies selvedge.auth
    assert!(matches!(
        error,
        ChatgptAuthParseError::UnsupportedSchemaVersion { version: 2 }
    ));
}

// @verifies selvedge.auth.jwt.parse.claims
#[test]
fn parse_chatgpt_jwt_claims_extracts_expected_fields() {
    let token = build_jwt(
        r#"{"alg":"none"}"#,
        r#"{
            "sub":"subject",
            "email":"user@example.com",
            "exp":1700000000,
            "https://api.openai.com/auth.chatgpt_account_id":"account-id",
            "https://api.openai.com/auth.chatgpt_user_id":"user-id",
            "https://api.openai.com/auth.chatgpt_plan_type":"plus"
        }"#,
    );

    let claims = parse_chatgpt_jwt_claims(&token).expect("parse jwt");

    // @verifies selvedge.auth
    assert_eq!(claims.subject.as_deref(), Some("subject"));
    // @verifies selvedge.auth
    assert_eq!(claims.account_id.as_deref(), Some("account-id"));
    // @verifies selvedge.auth
    assert_eq!(claims.user_id.as_deref(), Some("user-id"));
    // @verifies selvedge.auth
    assert_eq!(claims.email.as_deref(), Some("user@example.com"));
    // @verifies selvedge.auth
    assert_eq!(claims.plan_type.as_deref(), Some("plus"));
    // @verifies selvedge.auth
    assert_eq!(
        claims.expires_at,
        Some(
            Utc.timestamp_opt(1_700_000_000, 0)
                .single()
                .expect("expiration")
        )
    );
}

// @verifies selvedge.auth.jwt.claims
#[test]
fn parse_chatgpt_jwt_claims_uses_sub_for_user_id_when_chatgpt_user_id_is_missing() {
    let token = build_jwt(
        r#"{"alg":"none"}"#,
        r#"{
            "sub":"subject",
            "https://api.openai.com/auth.chatgpt_account_id":"account-id"
        }"#,
    );

    let claims = parse_chatgpt_jwt_claims(&token).expect("parse jwt");

    // @verifies selvedge.auth
    assert_eq!(claims.user_id.as_deref(), Some("subject"));
}

// @verifies selvedge.auth.jwt.segments
#[test]
fn parse_chatgpt_jwt_claims_rejects_invalid_format() {
    let error = parse_chatgpt_jwt_claims("not-a-jwt").expect_err("invalid format must fail");

    // @verifies selvedge.auth
    assert_eq!(error, JwtParseError::InvalidFormat);
}

// @verifies selvedge.auth.jwt.expiration
#[test]
fn parse_chatgpt_jwt_claims_rejects_invalid_expiration() {
    let token = build_jwt(
        r#"{"alg":"none"}"#,
        r#"{
            "sub":"subject",
            "exp":"soon"
        }"#,
    );

    let error = parse_chatgpt_jwt_claims(&token).expect_err("invalid expiration must fail");

    // @verifies selvedge.auth
    assert_eq!(error, JwtParseError::InvalidExpiration);
}

// @verifies selvedge.auth.jwt.json
#[test]
fn parse_chatgpt_jwt_claims_rejects_invalid_header_json() {
    let invalid_header = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode("not-json");
    let payload = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(
        r#"{"sub":"subject","https://api.openai.com/auth.chatgpt_account_id":"account-id"}"#,
    );
    let token = format!("{invalid_header}.{payload}.signature");

    let error = parse_chatgpt_jwt_claims(&token).expect_err("invalid header json must fail");

    // @verifies selvedge.auth
    assert_eq!(error, JwtParseError::InvalidJson);
}

fn build_jwt(header_json: &str, payload_json: &str) -> String {
    let header = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(header_json);
    let payload = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(payload_json);

    format!("{header}.{payload}.signature")
}
