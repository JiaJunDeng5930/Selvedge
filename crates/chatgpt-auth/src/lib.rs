#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]
//! @behavior selvedge.auth A ChatGPT provider request can resolve usable credentials from the local auth store before contacting the provider.

mod auth_file;
mod config;
mod jwt;
mod lock;
mod refresh;
mod resolve;

use std::path::PathBuf;

/// @behavior selvedge.auth.file The local ChatGPT auth file stores device-code tokens in the schema consumed by request-time authentication.
#[derive(Clone, Debug)]
pub struct ChatgptAuthFile {
    /// @constraint selvedge.auth.file.schema_field Persisted ChatGPT auth files expose schema version one to callers after parsing.
    pub schema_version: u32,
    /// @constraint selvedge.auth.file.provider_field Persisted ChatGPT auth files expose the ChatGPT provider marker to callers after parsing.
    pub provider: String,
    /// @constraint selvedge.auth.file.login_method_field Persisted ChatGPT auth files expose the device-code login method marker to callers after parsing.
    pub login_method: String,
    /// @behavior selvedge.auth.file.tokens_field Persisted ChatGPT auth files expose stored id, access, and refresh tokens to auth resolution.
    pub tokens: ChatgptStoredTokens,
}

/// @behavior selvedge.auth.file.tokens The stored ChatGPT token set exposes id, access, and refresh tokens to request resolution and refresh flows.
#[derive(Clone, Debug)]
pub struct ChatgptStoredTokens {
    /// @behavior selvedge.auth.file.tokens.id_field The stored id token supplies available account claims for auth resolution and refresh validation.
    pub id_token: String,
    /// @behavior selvedge.auth.file.tokens.access_field The stored access token is returned to provider requests after auth resolution succeeds.
    pub access_token: String,
    /// @behavior selvedge.auth.file.tokens.refresh_field The stored refresh token is sent to the provider token endpoint when credentials need renewal.
    pub refresh_token: String,
}

/// @behavior selvedge.auth.jwt.claims ChatGPT JWT parsing returns available account, user, email, plan, subject, and expiration claims visible to callers.
#[derive(Clone, Debug)]
pub struct ChatgptJwtClaims {
    /// @behavior selvedge.auth.jwt.claims.subject_field Parsed JWT claims expose the subject claim as fallback user metadata.
    pub subject: Option<String>,
    /// @behavior selvedge.auth.jwt.claims.account_field Parsed JWT claims expose the ChatGPT account ID when the provider supplies it.
    pub account_id: Option<String>,
    /// @behavior selvedge.auth.jwt.claims.user_field Parsed JWT claims expose the ChatGPT user ID when the provider supplies it.
    pub user_id: Option<String>,
    /// @behavior selvedge.auth.jwt.claims.email_field Parsed JWT claims expose the account email when the provider supplies it.
    pub email: Option<String>,
    /// @behavior selvedge.auth.jwt.claims.plan_field Parsed JWT claims expose the account plan type when the provider supplies it.
    pub plan_type: Option<String>,
    /// @behavior selvedge.auth.jwt.claims.expiration_field Parsed JWT claims expose the token expiration time when the provider supplies it.
    pub expires_at: Option<chrono::DateTime<chrono::Utc>>,
}

/// @behavior selvedge.auth.resolved A resolved ChatGPT authentication result returns the access token and available account metadata used by provider requests.
#[derive(Clone, Debug)]
pub struct ResolvedChatgptAuth {
    /// @behavior selvedge.auth.resolved.access_field Resolved ChatGPT auth returns the access token used by provider requests.
    pub access_token: String,
    /// @behavior selvedge.auth.resolved.expiration_field Resolved ChatGPT auth returns the access token expiration when the token carries one.
    pub access_token_expires_at: Option<chrono::DateTime<chrono::Utc>>,
    /// @behavior selvedge.auth.resolved.account_field Resolved ChatGPT auth returns the account ID when the provider supplies it.
    pub account_id: Option<String>,
    /// @behavior selvedge.auth.resolved.user_field Resolved ChatGPT auth returns user metadata when the id token carries it.
    pub user_id: Option<String>,
    /// @behavior selvedge.auth.resolved.email_field Resolved ChatGPT auth returns email metadata when the id token carries it.
    pub email: Option<String>,
    /// @behavior selvedge.auth.resolved.plan_field Resolved ChatGPT auth returns plan metadata when the id token carries it.
    pub plan_type: Option<String>,
}

/// @behavior selvedge.auth.file.parse_errors Auth file parsing reports malformed JSON, unsupported schema versions, missing fields, and invalid fields to callers.
#[derive(Debug)]
pub enum ChatgptAuthParseError {
    InvalidJson { reason: String },
    UnsupportedSchemaVersion { version: u32 },
    MissingField { field: &'static str },
    InvalidField { field: &'static str, reason: String },
}

/// @behavior selvedge.auth.jwt.errors JWT parsing reports invalid structure, base64url, JSON, and expiration fields to callers.
#[derive(Debug, PartialEq, Eq)]
pub enum JwtParseError {
    InvalidFormat,
    InvalidBase64,
    InvalidJson,
    InvalidExpiration,
}

/// @behavior selvedge.auth.errors Request-time ChatGPT auth resolution reports config, transport, local file, refresh, workspace, and persistence failures to callers.
#[derive(Debug)]
pub enum ChatgptAuthError {
    Config(selvedge_config::ConfigError),
    Transport(selvedge_client::HttpError),
    AuthFileMissing {
        path: PathBuf,
    },
    AuthFileReadFailed {
        path: PathBuf,
        reason: String,
    },
    AuthFileMalformed {
        path: PathBuf,
        reason: String,
    },
    MissingAccountId,
    WorkspaceMismatch {
        expected: String,
        actual: Option<String>,
    },
    ReauthenticationRequired {
        provider_code: Option<String>,
        provider_message: Option<String>,
    },
    RefreshFailed {
        status: Option<u16>,
        provider_code: Option<String>,
        provider_message: Option<String>,
    },
    PersistFailed {
        path: PathBuf,
        reason: String,
    },
}

/// @behavior selvedge.auth.resolve.request A provider request resolves existing credentials or refreshes stale credentials before returning caller-visible auth metadata.
pub async fn resolve_for_request() -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    resolve::resolve_for_request().await
}

/// @behavior selvedge.auth.resolve.unauthorized A provider request retried after an unauthorized response forces a token refresh before returning caller-visible auth metadata.
pub async fn resolve_after_unauthorized() -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    resolve::resolve_after_unauthorized().await
}

/// @behavior selvedge.auth.file.parse Public auth file parsing returns the stored token contract or a structured parse error.
pub fn parse_auth_file(bytes: &[u8]) -> Result<ChatgptAuthFile, ChatgptAuthParseError> {
    auth_file::parse(bytes)
}

/// @behavior selvedge.auth.jwt.parse Public ChatGPT JWT parsing returns known profile claims or a structured JWT parse error.
pub fn parse_chatgpt_jwt_claims(token: &str) -> Result<ChatgptJwtClaims, JwtParseError> {
    jwt::parse(token)
}
