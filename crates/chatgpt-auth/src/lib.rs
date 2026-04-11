#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]

mod auth_file;
mod config;
mod jwt;
mod lock;
mod refresh;
mod resolve;

use std::path::PathBuf;

#[derive(Clone, Debug)]
pub struct ChatgptAuthFile {
    pub schema_version: u32,
    pub provider: String,
    pub login_method: String,
    pub tokens: ChatgptStoredTokens,
}

#[derive(Clone, Debug)]
pub struct ChatgptStoredTokens {
    pub id_token: String,
    pub access_token: String,
    pub refresh_token: String,
}

#[derive(Clone, Debug)]
pub struct ChatgptJwtClaims {
    pub subject: Option<String>,
    pub account_id: Option<String>,
    pub user_id: Option<String>,
    pub email: Option<String>,
    pub plan_type: Option<String>,
    pub expires_at: Option<chrono::DateTime<chrono::Utc>>,
}

#[derive(Clone, Debug)]
pub struct ResolvedChatgptAuth {
    pub access_token: String,
    pub access_token_expires_at: Option<chrono::DateTime<chrono::Utc>>,
    pub account_id: String,
    pub user_id: Option<String>,
    pub email: Option<String>,
    pub plan_type: Option<String>,
}

#[derive(Debug)]
pub enum ChatgptAuthParseError {
    InvalidJson { reason: String },
    UnsupportedSchemaVersion { version: u32 },
    MissingField { field: &'static str },
    InvalidField { field: &'static str, reason: String },
}

#[derive(Debug, PartialEq, Eq)]
pub enum JwtParseError {
    InvalidFormat,
    InvalidBase64,
    InvalidJson,
    InvalidExpiration,
}

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

pub async fn resolve_for_request() -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    resolve::resolve_for_request().await
}

pub async fn resolve_after_unauthorized() -> Result<ResolvedChatgptAuth, ChatgptAuthError> {
    resolve::resolve_after_unauthorized().await
}

pub fn parse_auth_file(bytes: &[u8]) -> Result<ChatgptAuthFile, ChatgptAuthParseError> {
    auth_file::parse(bytes)
}

pub fn parse_chatgpt_jwt_claims(token: &str) -> Result<ChatgptJwtClaims, JwtParseError> {
    jwt::parse(token)
}
