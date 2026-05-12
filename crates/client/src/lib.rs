#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]

//! @behavior selvedge.client HTTP callers can execute buffered requests or streaming requests and receive typed status, body, and error results.
//! @behavior selvedge.client.execute Buffered HTTP execution returns complete responses or typed errors.
//! @behavior selvedge.client.stream Streaming HTTP execution returns response metadata and a raw byte stream or typed errors.
//! @behavior selvedge.client.response HTTP responses expose raw status, headers, and body data without automatic parsing.
//! @behavior selvedge.client.transport HTTP transport sends prepared requests with explicit timeout, proxy, retry, redirect, and TLS behavior.
//! @behavior selvedge.client.log HTTP calls emit structured logs for start, preparation, transport, status, stream completion, and configured runtime outcomes.
//! @behavior selvedge.client.tls HTTPS calls can use a configured CA bundle as additional root certificates.

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

// @behavior selvedge.client.log.macro HTTP lifecycle logging uses the repository structured logging macro and ignores logging backend errors.
pub(crate) use log_event;

// @behavior selvedge.client.stream.bytes ByteStream yields raw response body chunks or typed HTTP errors to the caller.
pub type ByteStream = Pin<Box<dyn Stream<Item = Result<bytes::Bytes, HttpError>> + Send + 'static>>;

// @constraint selvedge.client.method HTTP requests support GET, POST, PUT, PATCH, and DELETE methods.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HttpMethod {
    Get,
    Post,
    Put,
    Patch,
    Delete,
}

// @constraint selvedge.client.compression HTTP requests support no compression or zstd request body compression.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RequestCompression {
    None,
    Zstd,
}

// @behavior selvedge.client.body HTTP request bodies can be empty, JSON, form-url-encoded pairs, or raw bytes.
#[derive(Clone, Debug)]
pub enum HttpRequestBody {
    Empty,
    Json(serde_json::Value),
    FormUrlEncoded(Vec<(String, String)>),
    Bytes(bytes::Bytes),
}

// @behavior selvedge.client.request.public HttpRequest carries the caller-visible method, URL, headers, body, timeout override, and compression choice for one HTTP call.
#[derive(Clone, Debug)]
pub struct HttpRequest {
    /// @behavior selvedge.client.request.method HttpRequest carries the HTTP method selected by the caller.
    pub method: HttpMethod,
    /// @behavior selvedge.client.request.url_public HttpRequest carries the URL text selected by the caller.
    pub url: String,
    /// @behavior selvedge.client.request.headers HttpRequest carries caller-supplied request headers.
    pub headers: HeaderMap,
    /// @behavior selvedge.client.request.body_public HttpRequest carries the request body selected by the caller.
    pub body: HttpRequestBody,
    /// @behavior selvedge.client.request.timeout_public HttpRequest carries an optional per-call request timeout override.
    pub timeout: Option<Duration>,
    /// @behavior selvedge.client.request.compression_public HttpRequest carries the request compression mode selected by the caller.
    pub compression: RequestCompression,
}

// @behavior selvedge.client.response.public HttpResponse returns the successful HTTP status, headers, and raw buffered body to the caller.
#[derive(Clone, Debug)]
pub struct HttpResponse {
    /// @behavior selvedge.client.response.status HttpResponse carries the successful HTTP status code.
    pub status: StatusCode,
    /// @behavior selvedge.client.response.headers HttpResponse carries response headers returned by the server.
    pub headers: HeaderMap,
    /// @behavior selvedge.client.response.body_public HttpResponse carries the raw buffered response body bytes.
    pub body: bytes::Bytes,
}

// @behavior selvedge.client.stream.public HttpStreamResponse returns successful HTTP status, headers, and a raw byte stream to the caller.
pub struct HttpStreamResponse {
    /// @behavior selvedge.client.stream.status HttpStreamResponse carries the successful HTTP status code.
    pub status: StatusCode,
    /// @behavior selvedge.client.stream.headers HttpStreamResponse carries response headers returned by the server.
    pub headers: HeaderMap,
    /// @behavior selvedge.client.stream.body_public HttpStreamResponse carries the raw response byte stream.
    pub body: ByteStream,
}

// @behavior selvedge.client.error HTTP failures are returned as typed configuration, build, timeout, connect, TLS, I/O, or status errors.
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

// @behavior selvedge.client.status.public HttpStatusError carries the sanitized URL, HTTP status, headers, and raw error body for non-success responses.
#[derive(Debug)]
pub struct HttpStatusError {
    /// @behavior selvedge.client.status.url HttpStatusError carries the sanitized response URL.
    pub url: String,
    /// @behavior selvedge.client.status.code HttpStatusError carries the non-success HTTP status code.
    pub status: StatusCode,
    /// @behavior selvedge.client.status.headers HttpStatusError carries response headers returned by the server.
    pub headers: HeaderMap,
    /// @behavior selvedge.client.status.body HttpStatusError carries the raw buffered non-success response body bytes.
    pub body: bytes::Bytes,
}

// @constraint selvedge.client.stream.debug HttpStreamResponse debug output exposes status and headers while representing the live response body as a stream placeholder.
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
        // @behavior selvedge.client.error.display HttpError display text gives callers a stable human-readable failure message for each error category.
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
    // @intent selvedge.client.error.source StdError integration lets callers inspect configuration and status failure sources through the standard error interface.
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
        // @behavior selvedge.client.status.display HttpStatusError display text reports the non-success status code and sanitized URL.
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

// @behavior selvedge.client.execute.log execute emits structured start and prepared logs with sanitized URL, method, and body length.
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

// @behavior selvedge.client.stream.log stream emits structured start and prepared logs with sanitized URL, method, and body length.
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

// @behavior selvedge.client.error.build Build failures preserve caller-visible reason text in HttpError::Build.
pub(crate) fn build_error(reason: impl Into<String>) -> HttpError {
    HttpError::Build {
        reason: reason.into(),
    }
}

// @constraint selvedge.client.log.timeout_absent Absent HTTP timeout settings are logged as zero milliseconds.
pub(crate) fn duration_millis_or_zero(duration: Option<Duration>) -> u64 {
    duration
        .map(|timeout| timeout.as_millis() as u64)
        .unwrap_or(0)
}

// @behavior selvedge.client.blocking CPU-bound HTTP preparation work returns the same typed result after running on the blocking task pool.
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
        // @constraint selvedge.client.method.string HTTP method log fields use uppercase wire method names.
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
        // @constraint selvedge.client.method.reqwest Public HTTP methods map directly to reqwest methods with the same wire semantics.
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
        // @verifies selvedge.client.request.url.absolute
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

        // @verifies selvedge.client.request.compression.header
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

        // @verifies selvedge.client.request.compression.integrity
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

        // @verifies selvedge.client.request.body.json
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

        // @verifies selvedge.client.request.body.json
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
        // @verifies selvedge.client.request.compression.zstd
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
        // @verifies selvedge.client.error.build
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

        // @verifies selvedge.client.stream.idle
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
        // @verifies selvedge.client.stream.idle
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

        // @verifies selvedge.client.timeout
        let mut wrapped = wrap_stream(
            "http://example.test/stream".to_owned(),
            RequestBudget::new(Some(Duration::from_millis(50))),
            None,
            inner,
        );

        sleep(Duration::from_millis(120)).await;

        let first = wrapped.next().await.expect("first item");
        // @verifies selvedge.client.timeout
        assert_eq!(first.expect("first chunk"), Bytes::from_static(b"first"));
    }

    #[test]
    fn sanitize_url_removes_sensitive_parts() {
        // @verifies selvedge.client.redaction.parts
        let sanitized =
            sanitize_url("https://user:pass@example.com:8443/path?token=secret#fragment");

        assert_eq!(sanitized.as_str(), "https://example.com:8443/path");
    }

    #[test]
    fn sanitize_url_hides_invalid_input() {
        // @verifies selvedge.client.redaction.invalid
        let sanitized = sanitize_url("not a valid url\r\nsecret");

        assert_eq!(sanitized.as_str(), "<invalid-url>");
    }

    #[test]
    fn sanitize_error_text_replaces_known_urls() {
        let url =
            Url::parse("https://user:pass@example.com/path?token=secret").expect("parse known url");
        let raw = format!("connect error for {}", url.as_str());
        // @verifies selvedge.client.redaction.error_text
        let sanitized = sanitize_error_text(&raw, &[url.as_str()]);

        assert!(sanitized.contains("https://example.com/path"));
        assert!(!sanitized.contains("user:pass"));
        assert!(!sanitized.contains("token=secret"));
    }

    #[test]
    fn sanitize_error_text_scrubs_earliest_https_url_before_later_http_url() {
        let raw = concat!(
            "tls failed for https://user:pass@example.com/path?token=secret ",
            "before redirecting to http://other.example.test/path?x=1"
        );
        // @verifies selvedge.client.redaction.embedded
        let sanitized = sanitize_error_text(raw, &[]);

        assert!(sanitized.contains("https://example.com/path"));
        assert!(sanitized.contains("http://other.example.test/path"));
        assert!(!sanitized.contains("user:pass"));
        assert!(!sanitized.contains("token=secret"));
        assert!(!sanitized.contains("?x=1"));
    }
}
