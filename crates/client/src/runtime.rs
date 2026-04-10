use std::{error::Error as StdError, future::Future, path::Path, time::Duration};

use bytes::{Bytes, BytesMut};
use futures::{Stream, StreamExt};
use http::{
    HeaderMap,
    header::{AUTHORIZATION, COOKIE, HOST, LOCATION, ORIGIN, REFERER},
};
use reqwest::{Certificate, Client, Url};
use tokio::{fs as tokio_fs, time::Instant};

use crate::{
    ByteStream, HttpError, HttpMethod, HttpResponse, HttpStatusError, HttpStreamResponse,
    build_error, run_blocking,
};
use crate::{
    config_resolution::ResolvedCallConfig,
    redaction::{sanitize_error_text, sanitize_parsed_url},
    request_prep::PreparedRequest,
};

#[derive(Clone, Copy, Debug)]
pub(crate) struct RequestBudget {
    remaining: Option<Duration>,
}

impl RequestBudget {
    pub(crate) fn new(timeout: Option<Duration>) -> Self {
        Self { remaining: timeout }
    }

    fn remaining(self) -> Option<Duration> {
        self.remaining
    }

    fn charge(&mut self, elapsed: Duration) {
        if let Some(remaining) = &mut self.remaining {
            *remaining = remaining.saturating_sub(elapsed);
        }
    }
}

#[derive(Clone, Copy, Debug)]
struct IdleBudget {
    configured: Option<Duration>,
    remaining: Option<Duration>,
}

impl IdleBudget {
    fn new(timeout: Option<Duration>) -> Self {
        Self {
            configured: timeout,
            remaining: timeout,
        }
    }

    fn remaining(self) -> Option<Duration> {
        self.remaining
    }

    fn charge(&mut self, elapsed: Duration) {
        if let Some(remaining) = &mut self.remaining {
            *remaining = remaining.saturating_sub(elapsed);
        }
    }

    fn on_chunk(&mut self, chunk: &Bytes) {
        if !chunk.is_empty() {
            self.remaining = self.configured;
        }
    }
}

#[derive(Clone, Copy, Debug)]
enum TimeoutReason {
    Request,
    Idle,
}

#[derive(Clone, Copy, Debug)]
struct WaitBudget {
    timeout: Option<Duration>,
    timeout_reason: Option<TimeoutReason>,
}

impl WaitBudget {
    fn new(
        request_remaining: Option<Duration>,
        idle_remaining: Option<Duration>,
    ) -> Result<Self, TimeoutReason> {
        if request_remaining.is_some_and(|duration| duration.is_zero()) {
            return Err(TimeoutReason::Request);
        }

        if idle_remaining.is_some_and(|duration| duration.is_zero()) {
            return Err(TimeoutReason::Idle);
        }

        let timeout_reason = match (request_remaining, idle_remaining) {
            (Some(request_remaining), Some(idle_remaining)) => {
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

pub(crate) async fn execute_inner(
    call_config: &ResolvedCallConfig,
    prepared: PreparedRequest,
    mut request_budget: RequestBudget,
) -> Result<HttpResponse, HttpError> {
    let request_url = prepared.request_url.clone();
    let response = send_with_redirects(call_config, prepared, &mut request_budget).await?;

    if !response.status().is_success() {
        return Err(collect_status_error(response, &mut request_budget, &request_url).await?);
    }

    let status = response.status();
    let headers = response.headers().clone();
    let body = collect_success_body(response, &mut request_budget, &request_url).await?;

    Ok(HttpResponse {
        status,
        headers,
        body,
    })
}

pub(crate) async fn stream_inner(
    call_config: &ResolvedCallConfig,
    prepared: PreparedRequest,
    mut request_budget: RequestBudget,
    idle_timeout: Option<Duration>,
) -> Result<HttpStreamResponse, HttpError> {
    let request_url = prepared.request_url.clone();
    let response = send_with_redirects(call_config, prepared, &mut request_budget).await?;

    if !response.status().is_success() {
        return Err(collect_status_error(response, &mut request_budget, &request_url).await?);
    }

    let status = response.status();
    let headers = response.headers().clone();
    let body = wrap_stream(
        request_url,
        request_budget,
        idle_timeout,
        response.bytes_stream(),
    );

    Ok(HttpStreamResponse {
        status,
        headers,
        body,
    })
}

async fn send_with_redirects(
    call_config: &ResolvedCallConfig,
    prepared: PreparedRequest,
    request_budget: &mut RequestBudget,
) -> Result<reqwest::Response, HttpError> {
    let mut request = prepared.request;
    let method = prepared.method;
    let mut redirect_count = 0_usize;

    loop {
        let current_request_url = sanitize_parsed_url(request.url());
        let client = build_client(call_config, request.url().scheme() == "https").await?;
        let redirect_template = if matches!(method, HttpMethod::Get) {
            Some(
                request
                    .try_clone()
                    .ok_or_else(|| build_error("failed to clone redirectable request"))?,
            )
        } else {
            None
        };
        let response = send_with_budget(
            client,
            request,
            current_request_url.as_str(),
            request_budget,
        )
        .await?;

        if matches!(method, HttpMethod::Get) && response.status().is_redirection() {
            if redirect_count >= 10 {
                return Err(build_error("too many redirects"));
            }

            let Some(location) = response.headers().get(LOCATION) else {
                return Ok(response);
            };
            let location = location.to_str().map_err(|error| {
                build_error(format!("invalid redirect location header: {error}"))
            })?;
            let next_url = response
                .url()
                .join(location)
                .map_err(|error| build_error(format!("invalid redirect target URL: {error}")))?;
            let mut next_request = redirect_template
                .ok_or_else(|| build_error("missing redirect request template"))?;
            if !same_origin(response.url(), &next_url) {
                strip_origin_bound_headers(next_request.headers_mut());
            }
            *next_request.url_mut() = next_url;
            request = next_request;
            redirect_count += 1;
            continue;
        }

        return Ok(response);
    }
}

async fn send_with_budget(
    client: Client,
    request: reqwest::Request,
    request_url: &str,
    request_budget: &mut RequestBudget,
) -> Result<reqwest::Response, HttpError> {
    let wait_budget =
        WaitBudget::new(request_budget.remaining(), None).map_err(timeout_reason_to_error)?;
    let (response, elapsed) = run_wait(wait_budget, client.execute(request))
        .await
        .map_err(timeout_reason_to_error)?;
    request_budget.charge(elapsed);

    response.map_err(|error| map_transport_error(error, request_url))
}

async fn collect_status_error(
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
        let wait_budget = match WaitBudget::new(request_budget.remaining(), None) {
            Ok(wait_budget) => wait_budget,
            Err(_) => {
                crate::log_event!(
                    selvedge_logging::LogLevel::Warn,
                    "http non-success response body timed out";
                    url = url.as_str(),
                    status = status.as_u16()
                );
                return Err(HttpError::Timeout);
            }
        };
        let (next_chunk, elapsed) = match run_wait(wait_budget, stream.next()).await {
            Ok(result) => result,
            Err(_) => {
                crate::log_event!(
                    selvedge_logging::LogLevel::Warn,
                    "http non-success response body timed out";
                    url = url.as_str(),
                    status = status.as_u16()
                );
                return Err(HttpError::Timeout);
            }
        };
        request_budget.charge(elapsed);

        match next_chunk {
            Some(Ok(chunk)) => body.extend_from_slice(&chunk),
            Some(Err(error)) => {
                let mapped = map_transport_error(error, request_url);
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

    Ok(HttpError::Status(HttpStatusError {
        url,
        status,
        headers,
        body: body.freeze(),
    }))
}

async fn collect_success_body(
    response: reqwest::Response,
    request_budget: &mut RequestBudget,
    request_url: &str,
) -> Result<Bytes, HttpError> {
    let mut body = BytesMut::new();
    let mut stream = Box::pin(response.bytes_stream());

    loop {
        let wait_budget =
            WaitBudget::new(request_budget.remaining(), None).map_err(timeout_reason_to_error)?;
        let (next_chunk, elapsed) = run_wait(wait_budget, stream.next())
            .await
            .map_err(timeout_reason_to_error)?;
        request_budget.charge(elapsed);

        match next_chunk {
            Some(Ok(chunk)) => body.extend_from_slice(&chunk),
            Some(Err(error)) => return Err(map_transport_error(error, request_url)),
            None => return Ok(body.freeze()),
        }
    }
}

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
                    yield Err(HttpError::Timeout);
                    break;
                }
            };

            let (next_item, elapsed) = match run_wait(wait_budget, stream.next()).await {
                Ok(result) => result,
                Err(reason) => {
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
                Some(Err(error)) => {
                    let mapped = map_transport_error(error, &request_url);
                    log_transport_error("stream", &request_url, &mapped);
                    yield Err(mapped);
                    break;
                }
                None => {
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
        Err(error) => {
            log_transport_error(mode, request_url, error);
        }
    }
}

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
        Err(error) => {
            log_transport_error("stream", request_url, error);
        }
    }
}

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

async fn build_client(
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

    if let Some(path) = &call_config.ca_bundle_path
        && uses_tls
    {
        let certificates = load_ca_bundle(path).await?;

        for certificate in certificates {
            builder = builder.add_root_certificate(certificate);
        }
    }

    builder
        .build()
        .map_err(|error| build_error(format!("failed to build http client: {error}")))
}

async fn load_ca_bundle(path: &Path) -> Result<Vec<Certificate>, HttpError> {
    let bundle = tokio_fs::read(path).await.map_err(|error| {
        build_error(format!(
            "failed to read network.ca_bundle_path {}: {error}",
            path.display()
        ))
    })?;
    let path = path.to_path_buf();

    run_blocking(move || {
        parse_certificates(&bundle).map_err(|error| {
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

fn same_origin(left: &Url, right: &Url) -> bool {
    left.scheme() == right.scheme()
        && left.host_str() == right.host_str()
        && left.port_or_known_default() == right.port_or_known_default()
}

fn strip_origin_bound_headers(headers: &mut HeaderMap) {
    headers.remove(AUTHORIZATION);
    headers.remove(COOKIE);
    headers.remove(HOST);
    headers.remove(ORIGIN);
    headers.remove(REFERER);
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
