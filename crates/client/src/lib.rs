#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]

mod config_resolution;
mod redaction;
mod redirect_runtime;
mod request_prep;
mod runtime;
mod single_hop;

use std::{error::Error as StdError, fmt, pin::Pin, time::Duration};

use futures::Stream;
use http::{HeaderMap, StatusCode};
use reqwest::Method;
use tokio::task;

use crate::{
    config_resolution::resolve_call_config,
    redaction::sanitize_url,
    redirect_runtime::{execute_inner, stream_inner},
    request_prep::prepare_request,
    runtime::{RequestBudget, log_result, log_stream_result},
};

macro_rules! log_event {
    ($level:expr, $message:expr $(; $($key:ident = $value:expr),+ $(,)?)?) => {{
        let _ = selvedge_logging::selvedge_log!($level, $message $(; $($key = $value),+)?);
    }};
}

pub(crate) use log_event;

pub type ByteStream = Pin<Box<dyn Stream<Item = Result<bytes::Bytes, HttpError>> + Send + 'static>>;

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HttpMethod {
    Get,
    Post,
    Put,
    Patch,
    Delete,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RequestCompression {
    None,
    Zstd,
}

#[derive(Clone, Debug)]
pub enum HttpRequestBody {
    Empty,
    Json(serde_json::Value),
    FormUrlEncoded(Vec<(String, String)>),
    Bytes(bytes::Bytes),
}

#[derive(Clone, Debug)]
pub struct HttpRequest {
    pub method: HttpMethod,
    pub url: String,
    pub headers: HeaderMap,
    pub body: HttpRequestBody,
    pub timeout: Option<Duration>,
    pub compression: RequestCompression,
}

#[derive(Clone, Debug)]
pub struct HttpResponse {
    pub status: StatusCode,
    pub headers: HeaderMap,
    pub body: bytes::Bytes,
}

pub struct HttpStreamResponse {
    pub status: StatusCode,
    pub headers: HeaderMap,
    pub body: ByteStream,
}

#[derive(Debug)]
pub enum HttpError {
    Config(selvedge_config::ConfigError),
    Build { reason: String },
    Timeout,
    Connect { reason: String },
    Tls { reason: String },
    Io { reason: String },
    Status(HttpStatusError),
}

#[derive(Debug)]
pub struct HttpStatusError {
    pub url: String,
    pub status: StatusCode,
    pub headers: HeaderMap,
    pub body: bytes::Bytes,
}

impl fmt::Debug for HttpStreamResponse {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("HttpStreamResponse")
            .field("status", &self.status)
            .field("headers", &self.headers)
            .field("body", &"<byte-stream>")
            .finish()
    }
}

impl fmt::Display for HttpError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Config(error) => write!(formatter, "config error: {error}"),
            Self::Build { reason } => write!(formatter, "request build failed: {reason}"),
            Self::Timeout => formatter.write_str("request timed out"),
            Self::Connect { reason } => write!(formatter, "connection failed: {reason}"),
            Self::Tls { reason } => write!(formatter, "tls failed: {reason}"),
            Self::Io { reason } => write!(formatter, "i/o failed: {reason}"),
            Self::Status(error) => write!(formatter, "{error}"),
        }
    }
}

impl StdError for HttpError {
    fn source(&self) -> Option<&(dyn StdError + 'static)> {
        match self {
            Self::Config(error) => Some(error),
            Self::Status(error) => Some(error),
            Self::Build { .. }
            | Self::Timeout
            | Self::Connect { .. }
            | Self::Tls { .. }
            | Self::Io { .. } => None,
        }
    }
}

impl fmt::Display for HttpStatusError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            formatter,
            "received non-success status {} for {}",
            self.status, self.url
        )
    }
}

impl StdError for HttpStatusError {}

impl From<selvedge_config::ConfigError> for HttpError {
    fn from(error: selvedge_config::ConfigError) -> Self {
        Self::Config(error)
    }
}

pub async fn execute(request: HttpRequest) -> Result<HttpResponse, HttpError> {
    let sanitized_request_url = sanitize_url(&request.url);
    log_event!(
        selvedge_logging::LogLevel::Debug,
        "http request started";
        mode = "execute",
        method = request.method.as_str(),
        url = sanitized_request_url.as_str()
    );

    let call_config = resolve_call_config(request.timeout)?;
    let prepared = prepare_request(request.clone(), &call_config).await?;

    log_event!(
        selvedge_logging::LogLevel::Debug,
        "http request prepared";
        mode = "execute",
        method = prepared.method.as_str(),
        url = prepared.request_url.as_str(),
        body_len = prepared.body_len
    );

    let request_url = prepared.request_url.clone();
    let method = prepared.method.clone();
    let body_len = prepared.body_len;
    let result = execute_inner(
        &call_config,
        request,
        prepared,
        RequestBudget::new(call_config.request_timeout),
    )
    .await;

    log_result("execute", &method, &request_url, body_len, &result);

    result
}

pub async fn stream(request: HttpRequest) -> Result<HttpStreamResponse, HttpError> {
    let sanitized_request_url = sanitize_url(&request.url);
    log_event!(
        selvedge_logging::LogLevel::Debug,
        "http request started";
        mode = "stream",
        method = request.method.as_str(),
        url = sanitized_request_url.as_str()
    );

    let call_config = resolve_call_config(request.timeout)?;
    let prepared = prepare_request(request.clone(), &call_config).await?;

    log_event!(
        selvedge_logging::LogLevel::Debug,
        "http request prepared";
        mode = "stream",
        method = prepared.method.as_str(),
        url = prepared.request_url.as_str(),
        body_len = prepared.body_len
    );

    let request_url = prepared.request_url.clone();
    let method = prepared.method.clone();
    let body_len = prepared.body_len;
    let result = stream_inner(
        &call_config,
        request,
        prepared,
        RequestBudget::new(call_config.request_timeout),
        call_config.stream_idle_timeout,
    )
    .await;

    log_stream_result(&method, &request_url, body_len, &result);

    result
}

pub(crate) fn build_error(reason: impl Into<String>) -> HttpError {
    HttpError::Build {
        reason: reason.into(),
    }
}

pub(crate) fn duration_millis_or_zero(duration: Option<Duration>) -> u64 {
    duration
        .map(|timeout| timeout.as_millis() as u64)
        .unwrap_or(0)
}

pub(crate) async fn run_blocking<T, F>(operation: F) -> Result<T, HttpError>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, HttpError> + Send + 'static,
{
    let task = task::spawn_blocking(operation);

    task.await.expect("blocking task must not panic")
}

impl HttpMethod {
    fn as_str(&self) -> &'static str {
        match self {
            Self::Get => "GET",
            Self::Post => "POST",
            Self::Put => "PUT",
            Self::Patch => "PATCH",
            Self::Delete => "DELETE",
        }
    }
}

impl From<HttpMethod> for Method {
    fn from(value: HttpMethod) -> Self {
        match value {
            HttpMethod::Get => Method::GET,
            HttpMethod::Post => Method::POST,
            HttpMethod::Put => Method::PUT,
            HttpMethod::Patch => Method::PATCH,
            HttpMethod::Delete => Method::DELETE,
        }
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use bytes::Bytes;
    use futures::{StreamExt, stream};
    use http::{HeaderMap, HeaderValue};
    use tokio::time::sleep;
    use url::Url;

    use crate::{
        HttpError, HttpMethod, HttpRequest, HttpRequestBody, RequestCompression, build_error,
        config_resolution::ResolvedCallConfig,
        redaction::{sanitize_error_text, sanitize_url},
        request_prep::{
            PreparedBody, encode_body, maybe_compress_body, parse_absolute_http_url,
            prepare_request,
        },
        runtime::{RequestBudget, wrap_stream},
    };

    #[test]
    fn absolute_http_url_is_required() {
        let error = parse_absolute_http_url("/relative").expect_err("relative url must fail");

        assert!(matches!(error, HttpError::Build { .. }));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn request_compression_conflicts_with_existing_content_encoding() {
        let mut headers = HeaderMap::new();
        headers.insert(
            http::header::CONTENT_ENCODING,
            HeaderValue::from_static("gzip"),
        );

        let body = PreparedBody::Buffered {
            bytes: Bytes::from_static(b"payload"),
            content_type_if_missing: None,
        };

        let error = maybe_compress_body(body, RequestCompression::Zstd, &mut headers)
            .await
            .expect_err("content-encoding conflict must fail");

        assert!(matches!(error, HttpError::Build { .. }));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn request_compression_rejects_existing_integrity_headers() {
        let mut headers = HeaderMap::new();
        headers.insert(
            http::header::HeaderName::from_static("digest"),
            HeaderValue::from_static("sha-256=abc"),
        );

        let body = PreparedBody::Buffered {
            bytes: Bytes::from_static(b"payload"),
            content_type_if_missing: None,
        };

        let error = maybe_compress_body(body, RequestCompression::Zstd, &mut headers)
            .await
            .expect_err("integrity headers must fail");

        assert!(matches!(error, HttpError::Build { .. }));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn json_body_sets_default_content_type() {
        let request = HttpRequest {
            method: HttpMethod::Post,
            url: "https://example.com".to_owned(),
            headers: HeaderMap::new(),
            body: HttpRequestBody::Json(serde_json::json!({ "x": 1 })),
            timeout: None,
            compression: RequestCompression::None,
        };

        let prepared = prepare_request(
            request,
            &ResolvedCallConfig {
                connect_timeout: None,
                request_timeout: None,
                stream_idle_timeout: None,
                ca_bundle_path: None,
                user_agent: None,
            },
        )
        .await
        .expect("prepare request");

        assert_eq!(
            prepared.request.headers().get(http::header::CONTENT_TYPE),
            Some(&HeaderValue::from_static("application/json"))
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn zstd_compression_changes_request_body() {
        let body = encode_body(HttpRequestBody::Bytes(Bytes::from_static(b"payload")))
            .expect("encode body");
        let mut headers = HeaderMap::new();
        let compressed = maybe_compress_body(body, RequestCompression::Zstd, &mut headers)
            .await
            .expect("compress body");

        assert_eq!(
            headers.get(http::header::CONTENT_ENCODING),
            Some(&HeaderValue::from_static("zstd"))
        );
        assert!(compressed.len() > 0);
    }

    #[test]
    fn build_error_has_stable_shape() {
        let error = build_error("reason");

        assert!(matches!(error, HttpError::Build { reason } if reason == "reason"));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn idle_timeout_starts_when_waiting_for_next_chunk() {
        let inner = stream::unfold(0_u8, |state| async move {
            match state {
                0 => Some((Ok(Bytes::from_static(b"first")), 1)),
                1 => {
                    sleep(Duration::from_millis(10)).await;
                    Some((Ok(Bytes::from_static(b"second")), 2))
                }
                _ => None,
            }
        });

        let mut wrapped = wrap_stream(
            "http://example.test/stream".to_owned(),
            RequestBudget::new(None),
            Some(Duration::from_millis(50)),
            inner,
        );

        let first = wrapped.next().await.expect("first item");
        assert_eq!(first.expect("first chunk"), Bytes::from_static(b"first"));

        sleep(Duration::from_millis(120)).await;

        let second = wrapped.next().await.expect("second item");
        assert_eq!(second.expect("second chunk"), Bytes::from_static(b"second"));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn request_budget_starts_when_waiting_for_first_chunk() {
        let inner = stream::unfold(0_u8, |state| async move {
            match state {
                0 => Some((Ok(Bytes::from_static(b"first")), 1)),
                _ => None,
            }
        });

        let mut wrapped = wrap_stream(
            "http://example.test/stream".to_owned(),
            RequestBudget::new(Some(Duration::from_millis(50))),
            None,
            inner,
        );

        sleep(Duration::from_millis(120)).await;

        let first = wrapped.next().await.expect("first item");
        assert_eq!(first.expect("first chunk"), Bytes::from_static(b"first"));
    }

    #[test]
    fn sanitize_url_removes_sensitive_parts() {
        let sanitized =
            sanitize_url("https://user:pass@example.com:8443/path?token=secret#fragment");

        assert_eq!(sanitized.as_str(), "https://example.com:8443/path");
    }

    #[test]
    fn sanitize_url_hides_invalid_input() {
        let sanitized = sanitize_url("not a valid url\r\nsecret");

        assert_eq!(sanitized.as_str(), "<invalid-url>");
    }

    #[test]
    fn sanitize_error_text_replaces_known_urls() {
        let url =
            Url::parse("https://user:pass@example.com/path?token=secret").expect("parse known url");
        let raw = format!("connect error for {}", url.as_str());
        let sanitized = sanitize_error_text(&raw, &[url.as_str()]);

        assert!(sanitized.contains("https://example.com/path"));
        assert!(!sanitized.contains("user:pass"));
        assert!(!sanitized.contains("token=secret"));
    }
}
