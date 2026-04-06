#![doc = include_str!("../README.md")]
#![allow(clippy::result_large_err)]

use std::{error::Error as StdError, fmt, io::Write, path::PathBuf, pin::Pin, time::Duration};

use bytes::{Bytes, BytesMut};
use futures::{Stream, StreamExt};
use http::{
    HeaderMap, HeaderValue, StatusCode,
    header::{CONTENT_ENCODING, CONTENT_LENGTH, CONTENT_TYPE, USER_AGENT},
};
use reqwest::{Certificate, Client, Method, Proxy, Url};
use tokio::time::{Instant, timeout_at};
use tokio::{fs as tokio_fs, task};
use url::form_urlencoded;

macro_rules! log_event {
    ($level:expr, $message:expr $(; $($key:ident = $value:expr),+ $(,)?)?) => {{
        let _ = selvedge_logging::selvedge_log!($level, $message $(; $($key = $value),+)?);
    }};
}

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

#[derive(Debug, Clone)]
struct ResolvedCallConfig {
    connect_timeout: Option<Duration>,
    request_timeout: Option<Duration>,
    stream_idle_timeout: Option<Duration>,
    proxy_url: Option<String>,
    ca_bundle_path: Option<PathBuf>,
    user_agent: Option<String>,
}

#[derive(Debug)]
struct PreparedRequest {
    request: reqwest::Request,
    method: HttpMethod,
    request_url: String,
    body_len: usize,
}

#[derive(Debug)]
enum PreparedBody {
    Empty,
    Buffered {
        bytes: Bytes,
        content_type_if_missing: Option<HeaderValue>,
    },
}

#[derive(Debug, Clone, Copy)]
enum StreamTimeoutState {
    AwaitingFirstByte {
        request_timeout_remaining: Option<Duration>,
        idle_timeout: Option<Duration>,
    },
    Streaming {
        request_timeout_remaining: Option<Duration>,
        idle_timeout: Option<Duration>,
    },
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
    let sanitized_request_url = sanitize_url_for_output(&request.url);
    log_event!(
        selvedge_logging::LogLevel::Debug,
        "http request started";
        mode = "execute",
        method = request.method.as_str(),
        url = sanitized_request_url.as_str()
    );

    let call_config = resolve_call_config(request.timeout)?;
    let request_deadline = call_config
        .request_timeout
        .map(|duration| Instant::now() + duration);
    check_request_deadline(request_deadline)?;
    let prepared = prepare_request(request, &call_config, request_deadline).await?;

    log_event!(
        selvedge_logging::LogLevel::Debug,
        "http request prepared";
        mode = "execute",
        method = prepared.method.as_str(),
        url = prepared.request_url.as_str(),
        body_len = prepared.body_len
    );

    let client = build_client(&call_config, request_deadline).await?;
    let request_url = prepared.request_url.clone();
    let method = prepared.method.clone();
    let body_len = prepared.body_len;
    let result = execute_inner(client, prepared, request_deadline).await;

    log_result("execute", &method, &request_url, body_len, &result);

    result
}

pub async fn stream(request: HttpRequest) -> Result<HttpStreamResponse, HttpError> {
    let sanitized_request_url = sanitize_url_for_output(&request.url);
    log_event!(
        selvedge_logging::LogLevel::Debug,
        "http request started";
        mode = "stream",
        method = request.method.as_str(),
        url = sanitized_request_url.as_str()
    );

    let call_config = resolve_call_config(request.timeout)?;
    let request_deadline = call_config
        .request_timeout
        .map(|duration| Instant::now() + duration);
    check_request_deadline(request_deadline)?;
    let prepared = prepare_request(request, &call_config, request_deadline).await?;

    log_event!(
        selvedge_logging::LogLevel::Debug,
        "http request prepared";
        mode = "stream",
        method = prepared.method.as_str(),
        url = prepared.request_url.as_str(),
        body_len = prepared.body_len
    );

    let client = build_client(&call_config, request_deadline).await?;
    let idle_timeout = call_config.stream_idle_timeout;
    let request_url = prepared.request_url.clone();
    let method = prepared.method.clone();
    let body_len = prepared.body_len;

    let result = stream_inner(
        client,
        prepared,
        call_config.request_timeout,
        request_deadline,
        idle_timeout,
    )
    .await;

    log_stream_result(&method, &request_url, body_len, &result);

    result
}

async fn execute_inner(
    client: Client,
    prepared: PreparedRequest,
    request_deadline: Option<Instant>,
) -> Result<HttpResponse, HttpError> {
    let response = send_with_deadline(
        client,
        prepared.request,
        &prepared.request_url,
        request_deadline,
    )
    .await?;

    if !response.status().is_success() {
        return Err(collect_status_error(response, request_deadline, &prepared.request_url).await?);
    }

    let status = response.status();
    let headers = response.headers().clone();
    let body = collect_success_body(response, request_deadline, &prepared.request_url).await?;

    Ok(HttpResponse {
        status,
        headers,
        body,
    })
}

async fn stream_inner(
    client: Client,
    prepared: PreparedRequest,
    request_timeout: Option<Duration>,
    request_deadline: Option<Instant>,
    idle_timeout: Option<Duration>,
) -> Result<HttpStreamResponse, HttpError> {
    let response = send_with_deadline(
        client,
        prepared.request,
        &prepared.request_url,
        request_deadline,
    )
    .await?;

    if !response.status().is_success() {
        return Err(collect_status_error(response, request_deadline, &prepared.request_url).await?);
    }

    let status = response.status();
    let headers = response.headers().clone();
    let body = wrap_stream(
        prepared.request_url.clone(),
        request_timeout.and_then(|_| remaining_duration_until(request_deadline)),
        idle_timeout,
        response.bytes_stream(),
    );

    Ok(HttpStreamResponse {
        status,
        headers,
        body,
    })
}

async fn send(
    client: Client,
    request: reqwest::Request,
    request_url: &str,
) -> Result<reqwest::Response, HttpError> {
    client
        .execute(request)
        .await
        .map_err(|error| map_transport_error(error, request_url))
}

async fn send_with_deadline(
    client: Client,
    request: reqwest::Request,
    request_url: &str,
    deadline: Option<Instant>,
) -> Result<reqwest::Response, HttpError> {
    match deadline {
        Some(deadline) => timeout_at(deadline, client.execute(request))
            .await
            .map_err(|_| HttpError::Timeout)?
            .map_err(|error| map_transport_error(error, request_url)),
        None => send(client, request, request_url).await,
    }
}

async fn collect_status_error(
    response: reqwest::Response,
    deadline: Option<Instant>,
    request_url: &str,
) -> Result<HttpError, HttpError> {
    let url = sanitize_url_for_output(response.url().as_str());
    let status = response.status();
    let headers = response.headers().clone();
    let mut body = BytesMut::new();
    let mut stream = Box::pin(response.bytes_stream());

    loop {
        let next_chunk = match deadline {
            Some(deadline) => match timeout_at(deadline, stream.next()).await {
                Ok(next_chunk) => next_chunk,
                Err(_) => {
                    log_event!(
                        selvedge_logging::LogLevel::Warn,
                        "http non-success response body timed out";
                        url = url.as_str(),
                        status = status.as_u16()
                    );
                    return Err(HttpError::Timeout);
                }
            },
            None => stream.next().await,
        };

        match next_chunk {
            Some(Ok(chunk)) => body.extend_from_slice(&chunk),
            Some(Err(error)) => {
                let mapped = map_transport_error(error, request_url);
                log_event!(
                    selvedge_logging::LogLevel::Warn,
                    "http non-success response body truncated";
                    url = url.as_str(),
                    status = status.as_u16(),
                    error = mapped.to_string()
                );
                break;
            }
            None => break,
        }
    }

    Ok(HttpError::Status(HttpStatusError {
        url,
        status,
        headers,
        body: body.freeze(),
    }))
}

async fn collect_success_body(
    response: reqwest::Response,
    deadline: Option<Instant>,
    request_url: &str,
) -> Result<Bytes, HttpError> {
    let mut body = BytesMut::new();
    let mut stream = Box::pin(response.bytes_stream());

    loop {
        let next_chunk = match deadline {
            Some(deadline) => timeout_at(deadline, stream.next())
                .await
                .map_err(|_| HttpError::Timeout)?,
            None => stream.next().await,
        };

        match next_chunk {
            Some(Ok(chunk)) => body.extend_from_slice(&chunk),
            Some(Err(error)) => return Err(map_transport_error(error, request_url)),
            None => return Ok(body.freeze()),
        }
    }
}

fn resolve_call_config(
    timeout_override: Option<Duration>,
) -> Result<ResolvedCallConfig, HttpError> {
    if timeout_override.is_some_and(|timeout| timeout.is_zero()) {
        return Err(build_error("request.timeout must be greater than zero"));
    }

    let (
        connect_timeout_ms,
        request_timeout_ms,
        stream_idle_timeout_ms,
        proxy_url,
        ca_bundle_path,
        user_agent,
    ) = selvedge_config::read(|config| {
        (
            config.network.connect_timeout_ms,
            config.network.request_timeout_ms,
            config.network.stream_idle_timeout_ms,
            config.network.proxy_url.clone(),
            config.network.ca_bundle_path.clone(),
            config.network.user_agent.clone(),
        )
    })?;

    let config = ResolvedCallConfig {
        connect_timeout: connect_timeout_ms.map(Duration::from_millis),
        request_timeout: timeout_override.or_else(|| request_timeout_ms.map(Duration::from_millis)),
        stream_idle_timeout: stream_idle_timeout_ms.map(Duration::from_millis),
        proxy_url,
        ca_bundle_path,
        user_agent,
    };

    log_event!(
        selvedge_logging::LogLevel::Debug,
        "http config resolved";
        connect_timeout_ms = duration_millis_or_zero(config.connect_timeout),
        request_timeout_ms = duration_millis_or_zero(config.request_timeout),
        stream_idle_timeout_ms = duration_millis_or_zero(config.stream_idle_timeout),
        has_proxy = config.proxy_url.is_some(),
        has_ca_bundle = config.ca_bundle_path.is_some(),
        has_user_agent = config.user_agent.is_some()
    );

    Ok(config)
}

async fn prepare_request(
    request: HttpRequest,
    call_config: &ResolvedCallConfig,
    request_deadline: Option<Instant>,
) -> Result<PreparedRequest, HttpError> {
    let url = parse_absolute_http_url(&request.url)?;
    let mut headers = request.headers;
    let mut body = encode_body(request.body)?;

    if !headers.contains_key(USER_AGENT)
        && let Some(user_agent) = &call_config.user_agent
    {
        let user_agent = HeaderValue::from_str(user_agent)
            .map_err(|error| build_error(format!("invalid network.user_agent header: {error}")))?;
        headers.insert(USER_AGENT, user_agent);
    }

    finalize_headers(&mut headers, &body);
    body = maybe_compress_body(body, request.compression, &mut headers, request_deadline).await?;

    let body_len = body.len();
    reconcile_content_length(&body, &mut headers)?;
    let mut reqwest_request = reqwest::Request::new(request.method.clone().into(), url);
    *reqwest_request.headers_mut() = headers;

    if let Some(bytes) = body.into_bytes() {
        *reqwest_request.body_mut() = Some(bytes.into());
    }

    Ok(PreparedRequest {
        request: reqwest_request,
        method: request.method,
        request_url: sanitize_url_for_output(&request.url),
        body_len,
    })
}

fn reconcile_content_length(body: &PreparedBody, headers: &mut HeaderMap) -> Result<(), HttpError> {
    if headers.contains_key(CONTENT_LENGTH) {
        let content_length = HeaderValue::from_str(&body.len().to_string()).map_err(|error| {
            build_error(format!("invalid computed Content-Length header: {error}"))
        })?;
        headers.insert(CONTENT_LENGTH, content_length);
    }

    Ok(())
}

fn parse_absolute_http_url(url: &str) -> Result<Url, HttpError> {
    let parsed = Url::parse(url)
        .map_err(|error| build_error(format!("url must be an absolute URL: {error}")))?;

    if !parsed.has_host() || parsed.cannot_be_a_base() {
        return Err(build_error("url must be an absolute URL"));
    }

    match parsed.scheme() {
        "http" | "https" => Ok(parsed),
        other => Err(build_error(format!(
            "url scheme must be http or https, got {other}"
        ))),
    }
}

fn encode_body(body: HttpRequestBody) -> Result<PreparedBody, HttpError> {
    match body {
        HttpRequestBody::Empty => Ok(PreparedBody::Empty),
        HttpRequestBody::Json(value) => {
            let bytes = serde_json::to_vec(&value)
                .map(Bytes::from)
                .map_err(|error| build_error(format!("failed to encode json body: {error}")))?;

            Ok(PreparedBody::Buffered {
                bytes,
                content_type_if_missing: Some(HeaderValue::from_static("application/json")),
            })
        }
        HttpRequestBody::FormUrlEncoded(pairs) => {
            let mut encoded = pairs.into_iter().fold(
                form_urlencoded::Serializer::new(String::new()),
                |mut serializer, (key, value)| {
                    serializer.append_pair(&key, &value);
                    serializer
                },
            );

            Ok(PreparedBody::Buffered {
                bytes: Bytes::from(encoded.finish()),
                content_type_if_missing: Some(HeaderValue::from_static(
                    "application/x-www-form-urlencoded",
                )),
            })
        }
        HttpRequestBody::Bytes(bytes) => Ok(PreparedBody::Buffered {
            bytes,
            content_type_if_missing: None,
        }),
    }
}

fn finalize_headers(headers: &mut HeaderMap, body: &PreparedBody) {
    if let PreparedBody::Buffered {
        content_type_if_missing: Some(content_type),
        ..
    } = body
        && !headers.contains_key(CONTENT_TYPE)
    {
        headers.insert(CONTENT_TYPE, content_type.clone());
    }
}

async fn maybe_compress_body(
    body: PreparedBody,
    compression: RequestCompression,
    headers: &mut HeaderMap,
    request_deadline: Option<Instant>,
) -> Result<PreparedBody, HttpError> {
    match (body, compression) {
        (PreparedBody::Empty, _) => Ok(PreparedBody::Empty),
        (body, RequestCompression::None) => Ok(body),
        (
            PreparedBody::Buffered {
                bytes,
                content_type_if_missing,
            },
            RequestCompression::Zstd,
        ) => {
            if headers.contains_key(CONTENT_ENCODING) {
                return Err(build_error(
                    "cannot apply request compression when Content-Encoding is already set",
                ));
            }

            let compressed =
                run_blocking(move || compress_bytes_with_deadline(bytes, request_deadline)).await?;
            headers.insert(CONTENT_ENCODING, HeaderValue::from_static("zstd"));

            Ok(PreparedBody::Buffered {
                bytes: compressed,
                content_type_if_missing,
            })
        }
    }
}

async fn build_client(
    call_config: &ResolvedCallConfig,
    request_deadline: Option<Instant>,
) -> Result<Client, HttpError> {
    let mut builder = Client::builder().retry(reqwest::retry::never());

    if let Some(connect_timeout) = call_config.connect_timeout {
        builder = builder.connect_timeout(connect_timeout);
    }

    if let Some(proxy_url) = &call_config.proxy_url {
        let proxy = Proxy::all(proxy_url)
            .map_err(|error| build_error(format!("invalid network.proxy_url: {error}")))?;
        builder = builder.proxy(proxy);
    } else {
        builder = builder.no_proxy();
    }

    if let Some(path) = &call_config.ca_bundle_path {
        let bundle = match request_deadline {
            Some(deadline) => timeout_at(deadline, tokio_fs::read(path))
                .await
                .map_err(|_| HttpError::Timeout)?,
            None => tokio_fs::read(path).await,
        }
        .map_err(|error| {
            build_error(format!(
                "failed to read network.ca_bundle_path {}: {error}",
                path.display()
            ))
        })?;
        check_request_deadline(request_deadline)?;
        let path = path.clone();
        let certificates = run_blocking(move || {
            parse_certificates(&bundle).map_err(|error| {
                build_error(format!(
                    "failed to parse network.ca_bundle_path {}: {error}",
                    path.display()
                ))
            })
        })
        .await?;

        for certificate in certificates {
            builder = builder.add_root_certificate(certificate);
        }
    }

    builder
        .build()
        .map_err(|error| build_error(format!("failed to build http client: {error}")))
}

fn parse_certificates(bundle: &[u8]) -> Result<Vec<Certificate>, HttpError> {
    let mut reader = bundle;
    let mut certificates = Vec::new();

    for parsed in rustls_pemfile::certs(&mut reader) {
        let parsed = parsed
            .map_err(|error| build_error(format!("failed to parse pem certificate: {error}")))?;
        let certificate = Certificate::from_der(parsed.as_ref())
            .map_err(|error| build_error(format!("failed to load pem certificate: {error}")))?;
        certificates.push(certificate);
    }

    if certificates.is_empty() {
        return Err(build_error("ca bundle did not contain any certificates"));
    }

    Ok(certificates)
}

fn compress_bytes_with_deadline(
    bytes: Bytes,
    deadline: Option<Instant>,
) -> Result<Bytes, HttpError> {
    let mut encoder = zstd::stream::write::Encoder::new(Vec::new(), 0)
        .map_err(|error| build_error(format!("failed to start zstd encoder: {error}")))?;

    for chunk in bytes.chunks(64 * 1024) {
        check_request_deadline(deadline)?;
        encoder
            .write_all(chunk)
            .map_err(|error| build_error(format!("failed to encode zstd body: {error}")))?;
    }

    check_request_deadline(deadline)?;

    let compressed = encoder
        .finish()
        .map_err(|error| build_error(format!("failed to finish zstd body: {error}")))?;

    Ok(Bytes::from(compressed))
}

fn sanitize_url_for_output(raw_url: &str) -> String {
    let Ok(mut parsed) = Url::parse(raw_url) else {
        return raw_url.to_owned();
    };

    if !parsed.username().is_empty() {
        let _ = parsed.set_username("");
    }

    if parsed.password().is_some() {
        let _ = parsed.set_password(None);
    }

    parsed.set_query(None);
    parsed.set_fragment(None);

    parsed.to_string()
}

fn wrap_stream(
    request_url: String,
    request_timeout: Option<Duration>,
    idle_timeout: Option<Duration>,
    stream: impl Stream<Item = Result<Bytes, reqwest::Error>> + Send + 'static,
) -> ByteStream {
    let stream = async_stream::stream! {
        let mut stream = Box::pin(stream);
        let mut timeout_state = StreamTimeoutState::AwaitingFirstByte {
            request_timeout_remaining: request_timeout,
            idle_timeout,
        };

        loop {
            let wait_started_at = Instant::now();
            let next_item = match timeout_state.deadline() {
                Some(deadline) => match timeout_at(deadline, stream.next()).await {
                    Ok(item) => item,
                    Err(_) => {
                        log_event!(
                            selvedge_logging::LogLevel::Warn,
                            timeout_state.timeout_message();
                            mode = "stream",
                            url = request_url.as_str()
                        );
                        yield Err(HttpError::Timeout);
                        break;
                    }
                },
                None => stream.next().await,
            };
            let waited = wait_started_at.elapsed();
            timeout_state = timeout_state.after_wait(waited);

            match next_item {
                Some(Ok(bytes)) => {
                    timeout_state = timeout_state.on_chunk(&bytes);
                    yield Ok(bytes);
                }
                Some(Err(error)) => {
                    let mapped = map_transport_error(error, &request_url);
                    log_transport_error("stream", &request_url, &mapped);
                    yield Err(mapped);
                    break;
                }
                None => {
                    log_event!(
                        selvedge_logging::LogLevel::Debug,
                        "http stream finished";
                        mode = "stream",
                        url = request_url.as_str(),
                        outcome = "success"
                    );
                    break;
                }
            }
        }
    };

    Box::pin(stream)
}

fn map_transport_error(error: reqwest::Error, request_url: &str) -> HttpError {
    let reason = format!("{request_url}: {}", render_error_chain(&error));

    if error.is_timeout() {
        HttpError::Timeout
    } else if is_tls_error(&error) {
        HttpError::Tls { reason }
    } else if error.is_connect() {
        HttpError::Connect { reason }
    } else if error.is_builder() || error.is_redirect() || error.is_request() {
        HttpError::Build { reason }
    } else {
        HttpError::Io { reason }
    }
}

fn is_tls_error(error: &reqwest::Error) -> bool {
    let mut source = error.source();

    while let Some(current) = source {
        let reason = current.to_string().to_ascii_lowercase();

        if [
            "tls",
            "rustls",
            "certificate",
            "unknown issuer",
            "self-signed",
            "dns name",
            "handshake",
            "webpki",
            "peer sent no certificates",
            "not valid for name",
        ]
        .iter()
        .any(|needle| reason.contains(needle))
        {
            return true;
        }

        source = current.source();
    }

    false
}

fn render_error_chain(error: &dyn StdError) -> String {
    let mut parts = vec![error.to_string()];
    let mut source = error.source();

    while let Some(current) = source {
        parts.push(current.to_string());
        source = current.source();
    }

    parts.join(": ")
}

fn build_error(reason: impl Into<String>) -> HttpError {
    HttpError::Build {
        reason: reason.into(),
    }
}

fn duration_millis_or_zero(duration: Option<Duration>) -> u64 {
    duration
        .map(|timeout| timeout.as_millis() as u64)
        .unwrap_or(0)
}

fn relative_deadline(timeout: Option<Duration>) -> Option<Instant> {
    timeout.map(|timeout| Instant::now() + timeout)
}

fn remaining_duration_until(deadline: Option<Instant>) -> Option<Duration> {
    deadline.map(|deadline| deadline.saturating_duration_since(Instant::now()))
}

fn subtract_duration(duration: Option<Duration>, waited: Duration) -> Option<Duration> {
    duration.map(|duration| duration.saturating_sub(waited))
}

fn min_deadline(left: Option<Instant>, right: Option<Instant>) -> Option<Instant> {
    match (left, right) {
        (Some(left), Some(right)) => Some(left.min(right)),
        (Some(left), None) => Some(left),
        (None, Some(right)) => Some(right),
        (None, None) => None,
    }
}

fn check_request_deadline(deadline: Option<Instant>) -> Result<(), HttpError> {
    if deadline.is_some_and(|deadline| Instant::now() >= deadline) {
        return Err(HttpError::Timeout);
    }

    Ok(())
}

async fn run_blocking<T, F>(operation: F) -> Result<T, HttpError>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T, HttpError> + Send + 'static,
{
    let task = task::spawn_blocking(operation);

    task.await.expect("blocking task must not panic")
}

fn log_result<T>(
    mode: &str,
    method: &HttpMethod,
    request_url: &str,
    body_len: usize,
    result: &Result<T, HttpError>,
) {
    match result {
        Ok(_) => {
            log_event!(
                selvedge_logging::LogLevel::Debug,
                "http request finished";
                mode = mode,
                method = method.as_str(),
                url = request_url,
                body_len = body_len,
                outcome = "success"
            );
        }
        Err(HttpError::Status(error)) => {
            log_event!(
                selvedge_logging::LogLevel::Warn,
                "http request returned non-success status";
                mode = mode,
                method = method.as_str(),
                url = error.url.as_str(),
                status = error.status.as_u16(),
                body_len = error.body.len()
            );
        }
        Err(error) => {
            log_transport_error(mode, request_url, error);
        }
    }
}

fn log_stream_result(
    method: &HttpMethod,
    request_url: &str,
    body_len: usize,
    result: &Result<HttpStreamResponse, HttpError>,
) {
    match result {
        Ok(_) => {
            log_event!(
                selvedge_logging::LogLevel::Debug,
                "http stream established";
                mode = "stream",
                method = method.as_str(),
                url = request_url,
                body_len = body_len
            );
        }
        Err(HttpError::Status(error)) => {
            log_event!(
                selvedge_logging::LogLevel::Warn,
                "http request returned non-success status";
                mode = "stream",
                method = method.as_str(),
                url = error.url.as_str(),
                status = error.status.as_u16(),
                body_len = error.body.len()
            );
        }
        Err(error) => {
            log_transport_error("stream", request_url, error);
        }
    }
}

fn log_transport_error(mode: &str, request_url: &str, error: &HttpError) {
    let message = match error {
        HttpError::Timeout => "http request timed out",
        HttpError::Connect { .. } => "http request connect failure",
        HttpError::Tls { .. } => "http request tls failure",
        HttpError::Io { .. } => "http request i/o failure",
        HttpError::Build { .. } => "http request build failure",
        HttpError::Config { .. } => "http request config failure",
        HttpError::Status(_) => "http request status failure",
    };

    log_event!(
        selvedge_logging::LogLevel::Warn,
        message;
        mode = mode,
        url = request_url,
        error = error.to_string()
    );
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

impl PreparedBody {
    fn into_bytes(self) -> Option<Bytes> {
        match self {
            Self::Empty => None,
            Self::Buffered { bytes, .. } => Some(bytes),
        }
    }

    fn len(&self) -> usize {
        match self {
            Self::Empty => 0,
            Self::Buffered { bytes, .. } => bytes.len(),
        }
    }
}

impl StreamTimeoutState {
    fn deadline(self) -> Option<Instant> {
        match self {
            Self::AwaitingFirstByte {
                request_timeout_remaining,
                idle_timeout,
            } => min_deadline(
                relative_deadline(request_timeout_remaining),
                relative_deadline(idle_timeout),
            ),
            Self::Streaming {
                request_timeout_remaining,
                idle_timeout,
            } => min_deadline(
                relative_deadline(request_timeout_remaining),
                relative_deadline(idle_timeout),
            ),
        }
    }

    fn timeout_message(self) -> &'static str {
        match self {
            Self::AwaitingFirstByte {
                request_timeout_remaining,
                idle_timeout,
            }
            | Self::Streaming {
                request_timeout_remaining,
                idle_timeout,
            } => match (request_timeout_remaining, idle_timeout) {
                (Some(request_timeout), Some(idle_timeout)) => {
                    if idle_timeout <= request_timeout {
                        "http stream idle timeout"
                    } else {
                        "http stream request timeout"
                    }
                }
                (Some(_), None) => "http stream request timeout",
                (None, Some(_)) => "http stream idle timeout",
                (None, None) => "http stream request timeout",
            },
        }
    }

    fn after_wait(self, waited: Duration) -> Self {
        match self {
            Self::AwaitingFirstByte {
                request_timeout_remaining,
                idle_timeout,
            } => Self::AwaitingFirstByte {
                request_timeout_remaining: subtract_duration(request_timeout_remaining, waited),
                idle_timeout,
            },
            Self::Streaming {
                request_timeout_remaining,
                idle_timeout,
            } => Self::Streaming {
                request_timeout_remaining: subtract_duration(request_timeout_remaining, waited),
                idle_timeout,
            },
        }
    }

    fn on_chunk(self, chunk: &Bytes) -> Self {
        match self {
            Self::AwaitingFirstByte {
                request_timeout_remaining,
                idle_timeout,
            } => {
                if chunk.is_empty() {
                    Self::AwaitingFirstByte {
                        request_timeout_remaining,
                        idle_timeout,
                    }
                } else {
                    Self::Streaming {
                        request_timeout_remaining,
                        idle_timeout,
                    }
                }
            }
            Self::Streaming {
                request_timeout_remaining,
                idle_timeout,
            } => Self::Streaming {
                request_timeout_remaining,
                idle_timeout,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        HeaderMap, HeaderValue, HttpMethod, HttpRequest, HttpRequestBody, PreparedBody,
        RequestCompression, ResolvedCallConfig, build_client, build_error, encode_body,
        maybe_compress_body, parse_absolute_http_url, prepare_request, sanitize_url_for_output,
        wrap_stream,
    };
    use std::time::Duration;

    use bytes::Bytes;
    use futures::{StreamExt, stream};
    use tokio::time::sleep;

    #[test]
    fn absolute_http_url_is_required() {
        let error = parse_absolute_http_url("/relative").expect_err("relative url must fail");

        assert!(matches!(error, super::HttpError::Build { .. }));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn request_compression_conflicts_with_existing_content_encoding() {
        let mut headers = HeaderMap::new();
        headers.insert(super::CONTENT_ENCODING, HeaderValue::from_static("gzip"));

        let body = PreparedBody::Buffered {
            bytes: bytes::Bytes::from_static(b"payload"),
            content_type_if_missing: None,
        };

        let error = maybe_compress_body(body, RequestCompression::Zstd, &mut headers, None)
            .await
            .expect_err("content-encoding conflict must fail");

        assert!(matches!(error, super::HttpError::Build { .. }));
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
                proxy_url: None,
                ca_bundle_path: None,
                user_agent: None,
            },
            None,
        )
        .await
        .expect("prepare request");

        assert_eq!(
            prepared.request.headers().get(super::CONTENT_TYPE),
            Some(&HeaderValue::from_static("application/json"))
        );
    }

    #[tokio::test(flavor = "current_thread")]
    async fn invalid_proxy_url_fails_client_build() {
        let error = build_client(
            &ResolvedCallConfig {
                connect_timeout: None,
                request_timeout: None,
                stream_idle_timeout: None,
                proxy_url: Some("://bad-proxy".to_owned()),
                ca_bundle_path: None,
                user_agent: None,
            },
            None,
        )
        .await
        .expect_err("invalid proxy must fail");

        assert!(matches!(error, super::HttpError::Build { .. }));
    }

    #[tokio::test(flavor = "current_thread")]
    async fn zstd_compression_changes_request_body() {
        let body = encode_body(HttpRequestBody::Bytes(bytes::Bytes::from_static(
            b"payload",
        )))
        .expect("encode body");
        let mut headers = HeaderMap::new();
        let compressed = maybe_compress_body(body, RequestCompression::Zstd, &mut headers, None)
            .await
            .expect("compress body");

        assert_eq!(
            headers.get(super::CONTENT_ENCODING),
            Some(&HeaderValue::from_static("zstd"))
        );
        assert!(compressed.len() > 0);
    }

    #[test]
    fn build_error_has_stable_shape() {
        let error = build_error("reason");

        assert!(matches!(error, super::HttpError::Build { reason } if reason == "reason"));
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
            None,
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
    async fn first_chunk_timeout_starts_on_first_poll() {
        let inner = stream::unfold(0_u8, |state| async move {
            match state {
                0 => {
                    sleep(Duration::from_millis(10)).await;
                    Some((Ok(Bytes::from_static(b"first")), 1))
                }
                _ => None,
            }
        });

        let mut wrapped = wrap_stream(
            "http://example.test/stream".to_owned(),
            Some(Duration::from_millis(50)),
            None,
            inner,
        );

        sleep(Duration::from_millis(120)).await;

        let first = wrapped.next().await.expect("first item");
        assert_eq!(first.expect("first chunk"), Bytes::from_static(b"first"));
    }

    #[test]
    fn sanitized_url_removes_userinfo_query_and_fragment() {
        let sanitized = sanitize_url_for_output(
            "https://user:pass@example.com/path?access_token=secret#fragment",
        );

        assert_eq!(sanitized, "https://example.com/path");
    }
}
