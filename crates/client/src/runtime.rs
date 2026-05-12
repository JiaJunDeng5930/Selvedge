use std::{error::Error as StdError, future::Future, path::Path, time::Duration};

use bytes::{Bytes, BytesMut};
use futures::{Stream, StreamExt};
use http::{
    HeaderMap, HeaderName,
    header::{ACCEPT, ACCEPT_ENCODING, ACCEPT_LANGUAGE, CACHE_CONTROL, PRAGMA, USER_AGENT},
};
use reqwest::{Certificate, Client, Url};
use tokio::{fs as tokio_fs, time::Instant};

use crate::{
    ByteStream, HttpError, HttpMethod, HttpStatusError, HttpStreamResponse, build_error,
    run_blocking,
};
use crate::{
    config_resolution::ResolvedCallConfig,
    redaction::{sanitize_error_text, sanitize_parsed_url},
};

// @constraint selvedge.client.timeout Request timeout budgets apply only while the HTTP client is waiting for transport progress.
#[derive(Clone, Copy, Debug)]
pub(crate) struct RequestBudget {
    remaining: Option<Duration>,
}

impl RequestBudget {
    // @behavior selvedge.client.timeout.new RequestBudget starts with the configured request timeout for one HTTP call.
    pub(crate) fn new(timeout: Option<Duration>) -> Self {
        Self { remaining: timeout }
    }

    // @behavior selvedge.client.timeout.remaining RequestBudget exposes the remaining wait budget for the next transport poll.
    fn remaining(self) -> Option<Duration> {
        self.remaining
    }

    // @constraint selvedge.client.timeout.charge RequestBudget charges elapsed transport wait time without underflowing below zero.
    fn charge(&mut self, elapsed: Duration) {
        if let Some(remaining) = &mut self.remaining {
            *remaining = remaining.saturating_sub(elapsed);
        }
    }
}

// @constraint selvedge.client.stream.idle Stream idle timeout budgets reset only after a non-empty response body chunk is received.
#[derive(Clone, Copy, Debug)]
struct IdleBudget {
    configured: Option<Duration>,
    remaining: Option<Duration>,
}

impl IdleBudget {
    // @behavior selvedge.client.stream.idle.new IdleBudget starts with the configured stream idle timeout for a returned stream.
    fn new(timeout: Option<Duration>) -> Self {
        Self {
            configured: timeout,
            remaining: timeout,
        }
    }

    // @behavior selvedge.client.stream.idle.remaining IdleBudget exposes the remaining idle wait budget for the next stream poll.
    fn remaining(self) -> Option<Duration> {
        self.remaining
    }

    // @constraint selvedge.client.stream.idle.charge IdleBudget charges elapsed stream wait time without underflowing below zero.
    fn charge(&mut self, elapsed: Duration) {
        if let Some(remaining) = &mut self.remaining {
            *remaining = remaining.saturating_sub(elapsed);
        }
    }

    // @constraint selvedge.client.stream.idle.reset IdleBudget resets only after a non-empty response body chunk.
    fn on_chunk(&mut self, chunk: &Bytes) {
        if !chunk.is_empty() {
            self.remaining = self.configured;
        }
    }
}

// @behavior selvedge.client.timeout.wait WaitBudget chooses the caller-visible timeout reason for a transport wait window.
#[derive(Clone, Copy, Debug)]
enum TimeoutReason {
    Request,
    Idle,
}

/// @behavior selvedge.client.timeout.wait_budget Stream wait budgets expose the next timeout duration and caller-visible timeout reason.
#[derive(Clone, Copy, Debug)]
struct WaitBudget {
    timeout: Option<Duration>,
    timeout_reason: Option<TimeoutReason>,
}

impl WaitBudget {
    // @behavior selvedge.client.timeout.wait_new WaitBudget returns the shortest configured timeout and remembers whether request or idle timeout caused it.
    fn new(
        request_remaining: Option<Duration>,
        idle_remaining: Option<Duration>,
    ) -> Result<Self, TimeoutReason> {
        let timeout_reason = match (request_remaining, idle_remaining) {
            (Some(request_remaining), Some(idle_remaining)) => {
                // @constraint selvedge.client.timeout.wait.tie Equal request and idle timeouts report idle timeout as the caller-visible stream timeout reason.
                if idle_remaining <= request_remaining {
                    Some(TimeoutReason::Idle)
                } else {
                    Some(TimeoutReason::Request)
                }
            }
            (Some(_), None) => Some(TimeoutReason::Request),
            (None, Some(_)) => Some(TimeoutReason::Idle),
            (None, None) => None,
        };
        let timeout = min_duration(request_remaining, idle_remaining);

        Ok(Self {
            timeout,
            timeout_reason,
        })
    }
}

// @behavior selvedge.client.transport.send A prepared HTTP request is sent once and transport failures are mapped to HttpError for the caller.
pub(crate) async fn send_with_budget(
    client: Client,
    request: reqwest::Request,
    request_url: &str,
    request_budget: &mut RequestBudget,
) -> Result<reqwest::Response, HttpError> {
    let wait_budget =
        WaitBudget::new(request_budget.remaining(), None).map_err(timeout_reason_to_error)?;
    // @constraint selvedge.client.transport.timeout A request timeout while sending returns HttpError::Timeout to the caller.
    let (response, elapsed) = run_wait(wait_budget, client.execute(request))
        .await
        .map_err(timeout_reason_to_error)?;
    request_budget.charge(elapsed);

    // @behavior selvedge.client.transport.failure Send failures are mapped into caller-visible HTTP error categories.
    response.map_err(|error| map_transport_error(error, request_url))
}

// @behavior selvedge.client.status Non-success HTTP responses are returned as HttpError::Status with sanitized URL, status, headers, and buffered body bytes.
pub(crate) async fn collect_status_error(
    response: reqwest::Response,
    request_budget: &mut RequestBudget,
    request_url: &str,
) -> Result<HttpError, HttpError> {
    let url = sanitize_parsed_url(response.url()).into_string();
    let status = response.status();
    let headers = response.headers().clone();
    let mut body = BytesMut::new();
    let mut stream = Box::pin(response.bytes_stream());

    loop {
        // @constraint selvedge.client.status.wait_budget Status error body buffering uses only the request timeout budget.
        let wait_budget = match WaitBudget::new(request_budget.remaining(), None) {
            Ok(wait_budget) => wait_budget,
            Err(_) => unreachable!("status body collection does not use idle timeout"),
        };
        let (next_chunk, elapsed) = match run_wait(wait_budget, stream.next()).await {
            Ok(result) => result,
            // @constraint selvedge.client.status.timeout A timeout while buffering a non-success response body returns the partial status error body.
            Err(_) => {
                // @behavior selvedge.client.status.timeout.log Non-success response body timeout emits a warning log with sanitized URL and status.
                crate::log_event!(
                    selvedge_logging::LogLevel::Warn,
                    "http non-success response body timed out";
                    url = url.as_str(),
                    status = status.as_u16()
                );
                break;
            }
        };
        request_budget.charge(elapsed);

        match next_chunk {
            Some(Ok(chunk)) => body.extend_from_slice(&chunk),
            // @constraint selvedge.client.status.truncated A transport error while buffering a non-success response body returns the partial status error body.
            Some(Err(error)) => {
                let mapped = map_transport_error(error, request_url);
                // @behavior selvedge.client.status.truncated.log Non-success response body truncation emits a warning log with sanitized URL, status, and mapped error text.
                crate::log_event!(
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

    // @behavior selvedge.client.response.status_body Non-success HTTP responses expose the captured error body bytes to callers.
    Ok(HttpError::Status(HttpStatusError {
        url,
        status,
        headers,
        body: body.freeze(),
    }))
}

// @behavior selvedge.client.response.body Successful execute calls buffer the complete raw response body before returning HttpResponse.
pub(crate) async fn collect_success_body(
    response: reqwest::Response,
    request_budget: &mut RequestBudget,
    request_url: &str,
) -> Result<Bytes, HttpError> {
    let mut body = BytesMut::new();
    let mut stream = Box::pin(response.bytes_stream());

    loop {
        // @constraint selvedge.client.response.wait_budget Successful execute response body buffering uses the remaining request timeout budget.
        let wait_budget =
            WaitBudget::new(request_budget.remaining(), None).map_err(timeout_reason_to_error)?;
        // @constraint selvedge.client.response.timeout A timeout while buffering a successful execute response returns HttpError::Timeout.
        let (next_chunk, elapsed) = run_wait(wait_budget, stream.next())
            .await
            .map_err(timeout_reason_to_error)?;
        request_budget.charge(elapsed);

        match next_chunk {
            Some(Ok(chunk)) => body.extend_from_slice(&chunk),
            // @behavior selvedge.client.response.transport_error A transport error while buffering a successful execute response returns the mapped HttpError.
            Some(Err(error)) => return Err(map_transport_error(error, request_url)),
            None => return Ok(body.freeze()),
        }
    }
}

// @behavior selvedge.client.stream.body Successful stream calls return raw response chunks and surface later stream errors through the byte stream.
pub(crate) fn wrap_stream(
    request_url: String,
    mut request_budget: RequestBudget,
    idle_timeout: Option<Duration>,
    stream: impl Stream<Item = Result<Bytes, reqwest::Error>> + Send + 'static,
) -> ByteStream {
    let stream = async_stream::stream! {
        let mut stream = Box::pin(stream);
        let mut idle_budget = IdleBudget::new(idle_timeout);

        loop {
            // @constraint selvedge.client.stream.wait_budget Stream polling uses the shorter remaining request timeout or idle timeout.
            let wait_budget = match WaitBudget::new(
                request_budget.remaining(),
                idle_budget.remaining(),
            ) {
                Ok(wait_budget) => wait_budget,
                Err(reason) => {
                    crate::log_event!(
                        selvedge_logging::LogLevel::Warn,
                        timeout_message(reason);
                        mode = "stream",
                        url = request_url.as_str()
                    );
                    // @behavior selvedge.client.stream.wait_timeout_item The returned byte stream yields HttpError::Timeout when waiting for body bytes times out.
                    yield Err(HttpError::Timeout);
                    break;
                }
            };

            // @constraint selvedge.client.stream.inter_poll Caller-side delay between stream polls is excluded from request and idle timeout accounting.
            let (next_item, elapsed) = match run_wait(wait_budget, stream.next()).await {
                Ok(result) => result,
                Err(reason) => {
                    // @behavior selvedge.client.stream.wait_timeout A request or idle timeout while waiting for response body bytes yields HttpError::Timeout and ends the stream.
                    crate::log_event!(
                        selvedge_logging::LogLevel::Warn,
                        timeout_message(reason);
                        mode = "stream",
                        url = request_url.as_str()
                    );
                    yield Err(HttpError::Timeout);
                    break;
                }
            };
            request_budget.charge(elapsed);
            idle_budget.charge(elapsed);

            match next_item {
                Some(Ok(bytes)) => {
                    idle_budget.on_chunk(&bytes);
                    yield Ok(bytes);
                }
                // @behavior selvedge.client.stream.transport_error A transport error after stream establishment yields the mapped HttpError and ends the stream.
                Some(Err(error)) => {
                    let mapped = map_transport_error(error, &request_url);
                    log_transport_error("stream", &request_url, &mapped);
                    yield Err(mapped);
                    break;
                }
                None => {
                    // @behavior selvedge.client.stream.finish_log Successful stream completion emits a structured debug log with sanitized URL and success outcome.
                    crate::log_event!(
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

// @behavior selvedge.client.transport.error Transport errors are categorized as timeout, TLS, connect, build, or I/O errors, with sanitized request context on reason-carrying variants.
pub(crate) fn map_transport_error(error: reqwest::Error, request_url: &str) -> HttpError {
    let error_url = error.url().map(|url| url.as_str().to_owned());
    let mut known_urls = Vec::new();

    if let Some(error_url) = error_url.as_deref() {
        known_urls.push(error_url);
    }

    let rendered = sanitize_error_text(&render_error_chain(&error), &known_urls);
    let reason = format!("{request_url}: {rendered}");

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

// @behavior selvedge.client.log.finish execute calls emit structured completion logs for success, status failure, and transport failure outcomes.
pub(crate) fn log_result<T>(
    mode: &str,
    method: &HttpMethod,
    request_url: &str,
    body_len: usize,
    result: &Result<T, HttpError>,
) {
    match result {
        Ok(_) => {
            crate::log_event!(
                selvedge_logging::LogLevel::Debug,
                "http request finished";
                mode = mode,
                method = method.as_str(),
                url = request_url,
                body_len = body_len,
                outcome = "success"
            );
        }
        // @behavior selvedge.client.log.status execute status failures emit a warning log with status and error body length.
        Err(HttpError::Status(error)) => {
            crate::log_event!(
                selvedge_logging::LogLevel::Warn,
                "http request returned non-success status";
                mode = mode,
                method = method.as_str(),
                url = error.url.as_str(),
                status = error.status.as_u16(),
                body_len = error.body.len()
            );
        }
        // @behavior selvedge.client.log.failure execute transport failures emit a transport failure warning log.
        Err(error) => {
            log_transport_error(mode, request_url, error);
        }
    }
}

// @behavior selvedge.client.log.stream stream calls emit structured establishment logs for success, status failure, and transport failure outcomes.
pub(crate) fn log_stream_result(
    method: &HttpMethod,
    request_url: &str,
    body_len: usize,
    result: &Result<HttpStreamResponse, HttpError>,
) {
    match result {
        Ok(_) => {
            crate::log_event!(
                selvedge_logging::LogLevel::Debug,
                "http stream established";
                mode = "stream",
                method = method.as_str(),
                url = request_url,
                body_len = body_len
            );
        }
        // @behavior selvedge.client.log.stream_status stream status failures emit a warning log with status and error body length.
        Err(HttpError::Status(error)) => {
            crate::log_event!(
                selvedge_logging::LogLevel::Warn,
                "http request returned non-success status";
                mode = "stream",
                method = method.as_str(),
                url = error.url.as_str(),
                status = error.status.as_u16(),
                body_len = error.body.len()
            );
        }
        // @behavior selvedge.client.log.stream_failure stream transport failures emit a transport failure warning log.
        Err(error) => {
            log_transport_error("stream", request_url, error);
        }
    }
}

// @behavior selvedge.client.log.transport Transport failures emit structured warning logs with mode, sanitized URL, and caller-visible error text.
pub(crate) fn log_transport_error(mode: &str, request_url: &str, error: &HttpError) {
    let message = match error {
        HttpError::Timeout => "http request timed out",
        HttpError::Connect { .. } => "http request connect failure",
        HttpError::Tls { .. } => "http request tls failure",
        HttpError::Io { .. } => "http request i/o failure",
        HttpError::Build { .. } => "http request build failure",
        HttpError::Config { .. } => "http request config failure",
        HttpError::Status(_) => "http request status failure",
    };

    crate::log_event!(
        selvedge_logging::LogLevel::Warn,
        message;
        mode = mode,
        url = request_url,
        error = error.to_string()
    );
}

// @behavior selvedge.client.transport.config HTTP clients use configured connect timeout, ignore environment proxies, disable implicit retries, and disable reqwest redirects.
pub(crate) async fn build_client(
    call_config: &ResolvedCallConfig,
    uses_tls: bool,
) -> Result<Client, HttpError> {
    let mut builder = Client::builder()
        .retry(reqwest::retry::never())
        .redirect(reqwest::redirect::Policy::none());

    if let Some(connect_timeout) = call_config.connect_timeout {
        builder = builder.connect_timeout(connect_timeout);
    }
    builder = builder.no_proxy();

    // @behavior selvedge.client.tls.ca_bundle.http_skip Configured CA bundle paths are read only for TLS requests, so HTTP calls ignore missing or invalid CA bundle files.
    if let Some(path) = &call_config.ca_bundle_path
        && uses_tls
    {
        // @behavior selvedge.client.tls.ca_bundle HTTPS calls load the configured CA bundle path as additional root certificates.
        let certificates = load_ca_bundle(path).await?;

        for certificate in certificates {
            builder = builder.add_root_certificate(certificate);
        }
    }
    builder
        .build()
        // @behavior selvedge.client.transport.build_error HTTP client construction failures return request build errors.
        .map_err(|error| build_error(format!("failed to build http client: {error}")))
}

// @behavior selvedge.client.tls.ca_bundle.read CA bundle read and parse failures are returned as request build errors naming network.ca_bundle_path.
async fn load_ca_bundle(path: &Path) -> Result<Vec<Certificate>, HttpError> {
    let bundle = tokio_fs::read(path).await.map_err(|error| {
        // @behavior selvedge.client.tls.ca_bundle.read_error CA bundle read failure returns a request build error naming the configured path.
        build_error(format!(
            "failed to read network.ca_bundle_path {}: {error}",
            path.display()
        ))
    })?;
    let path = path.to_path_buf();

    run_blocking(move || {
        parse_certificates(&bundle).map_err(|error| {
            // @behavior selvedge.client.tls.ca_bundle.parse_error CA bundle parse failure returns a request build error naming the configured path.
            build_error(format!(
                "failed to parse network.ca_bundle_path {}: {error}",
                path.display()
            ))
        })
    })
    .await
}

fn parse_certificates(bundle: &[u8]) -> Result<Vec<Certificate>, HttpError> {
    let mut reader = bundle;
    let mut certificates = Vec::new();

    for parsed in rustls_pemfile::certs(&mut reader) {
        let parsed = parsed
            // @behavior selvedge.client.tls.ca_bundle.pem_error Invalid PEM certificate data returns a request build error.
            .map_err(|error| build_error(format!("failed to parse pem certificate: {error}")))?;
        let certificate = Certificate::from_der(parsed.as_ref())
            // @behavior selvedge.client.tls.ca_bundle.der_error Invalid DER certificate data returns a request build error.
            .map_err(|error| build_error(format!("failed to load pem certificate: {error}")))?;
        certificates.push(certificate);
    }

    if certificates.is_empty() {
        // @constraint selvedge.client.tls.ca_bundle.nonempty A configured CA bundle must contain at least one PEM certificate.
        return Err(build_error("ca bundle did not contain any certificates"));
    }

    Ok(certificates)
}

// @constraint selvedge.client.redirect.origin Same-origin redirect comparison uses scheme, host, and effective port.
pub(crate) fn same_origin(left: &Url, right: &Url) -> bool {
    left.scheme() == right.scheme()
        && left.host_str() == right.host_str()
        && left.port_or_known_default() == right.port_or_known_default()
}

// @constraint selvedge.client.redirect.headers Cross-origin redirects retain only cache, accept, encoding, language, and user-agent headers.
pub(crate) fn strip_origin_bound_headers(headers: &mut HeaderMap) {
    let names_to_remove = headers
        .keys()
        .filter(|name| !is_cross_origin_whitelisted_header(name))
        .cloned()
        .collect::<Vec<_>>();

    for name in names_to_remove {
        headers.remove(name);
    }
}

fn is_cross_origin_whitelisted_header(name: &HeaderName) -> bool {
    matches!(
        *name,
        ACCEPT | ACCEPT_ENCODING | ACCEPT_LANGUAGE | CACHE_CONTROL | PRAGMA | USER_AGENT
    )
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

// @intent selvedge.client.transport.error_chain Rendering an error chain preserves caller-visible transport failure causes before URL redaction.
fn render_error_chain(error: &dyn StdError) -> String {
    let mut parts = vec![error.to_string()];
    let mut source = error.source();

    while let Some(current) = source {
        parts.push(current.to_string());
        source = current.source();
    }

    parts.join(": ")
}

// @constraint selvedge.client.timeout.ready A zero-duration wait budget still allows an immediately ready transport poll to complete.
async fn run_wait<T, F>(wait_budget: WaitBudget, future: F) -> Result<(T, Duration), TimeoutReason>
where
    F: Future<Output = T>,
{
    let started = Instant::now();
    let output = match wait_budget.timeout {
        Some(timeout) => tokio::time::timeout(timeout, future)
            .await
            .map_err(|_| wait_budget.timeout_reason.unwrap_or(TimeoutReason::Request))?,
        None => future.await,
    };

    Ok((output, started.elapsed()))
}

fn min_duration(left: Option<Duration>, right: Option<Duration>) -> Option<Duration> {
    match (left, right) {
        (Some(left), Some(right)) => Some(left.min(right)),
        (Some(left), None) => Some(left),
        (None, Some(right)) => Some(right),
        (None, None) => None,
    }
}

fn timeout_reason_to_error(_: TimeoutReason) -> HttpError {
    HttpError::Timeout
}

fn timeout_message(reason: TimeoutReason) -> &'static str {
    match reason {
        TimeoutReason::Request => "http stream request timeout",
        TimeoutReason::Idle => "http stream idle timeout",
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use super::{TimeoutReason, WaitBudget, run_wait};

    #[tokio::test(flavor = "current_thread")]
    async fn zero_request_budget_allows_ready_poll() {
        // @verifies selvedge.client.timeout.ready
        let wait_budget =
            WaitBudget::new(Some(Duration::ZERO), None).expect("wait budget must exist");
        // @verifies selvedge.client.timeout.ready
        let (value, _) = run_wait(wait_budget, std::future::ready(7_u8))
            .await
            .expect("ready future must succeed");

        assert_eq!(value, 7);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn zero_idle_budget_allows_ready_poll() {
        // @verifies selvedge.client.timeout.ready
        let wait_budget =
            WaitBudget::new(None, Some(Duration::ZERO)).expect("wait budget must exist");
        // @verifies selvedge.client.timeout.ready
        let (value, _) = run_wait(wait_budget, std::future::ready(9_u8))
            .await
            .expect("ready future must succeed");

        assert_eq!(value, 9);
    }

    #[tokio::test(flavor = "current_thread")]
    async fn zero_budget_still_times_out_pending_poll() {
        // @verifies selvedge.client.timeout
        let wait_budget =
            WaitBudget::new(Some(Duration::ZERO), None).expect("wait budget must exist");
        // @verifies selvedge.client.timeout
        let error = run_wait(wait_budget, std::future::pending::<()>())
            .await
            .expect_err("pending future must time out");

        assert!(matches!(error, TimeoutReason::Request));
    }
}
