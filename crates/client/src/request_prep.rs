use std::io::Write;

use bytes::Bytes;
use http::{
    HeaderMap, HeaderName, HeaderValue,
    header::{CONTENT_ENCODING, CONTENT_LENGTH, CONTENT_TYPE, USER_AGENT},
};
use reqwest::Url;
use url::form_urlencoded;

use crate::{
    HttpError, HttpMethod, HttpRequest, HttpRequestBody, RequestCompression, build_error,
    run_blocking,
};
use crate::{config_resolution::ResolvedCallConfig, redaction::sanitize_url};

// @behavior selvedge.client.request.compression Request compression changes body bytes only when the caller selects a supported compression mode.
// @behavior selvedge.client.request HTTP requests are prepared as absolute http or https requests with encoded bodies and caller-visible build errors.
#[derive(Debug)]
pub(crate) struct PreparedRequest {
    /// @behavior selvedge.client.request.prepared PreparedRequest carries the transport request, sanitized URL, method, and body length used by execution.
    pub(crate) request: reqwest::Request,
    /// @behavior selvedge.client.request.prepared_method PreparedRequest carries the method used for logging and redirect behavior.
    pub(crate) method: HttpMethod,
    /// @behavior selvedge.client.request.prepared_url PreparedRequest carries the sanitized request URL used for logs and errors.
    pub(crate) request_url: String,
    /// @behavior selvedge.client.request.prepared_body_len PreparedRequest carries the encoded request body length used for logs.
    pub(crate) body_len: usize,
}

// @behavior selvedge.client.request.body Request bodies are encoded as empty, JSON, form-url-encoded, or raw bytes according to HttpRequestBody.
#[derive(Debug)]
pub(crate) enum PreparedBody {
    Empty,
    Buffered {
        bytes: Bytes,
        content_type_if_missing: Option<HeaderValue>,
    },
}

impl PreparedBody {
    // @behavior selvedge.client.request.body.into_bytes Prepared request bodies expose buffered bytes for transport when a body exists.
    pub(crate) fn into_bytes(self) -> Option<Bytes> {
        match self {
            Self::Empty => None,
            Self::Buffered { bytes, .. } => Some(bytes),
        }
    }

    // @behavior selvedge.client.request.body.len Prepared request bodies report the byte length that will be logged and sent.
    pub(crate) fn len(&self) -> usize {
        match self {
            Self::Empty => 0,
            Self::Buffered { bytes, .. } => bytes.len(),
        }
    }
}

// @behavior selvedge.client.request.prepare Prepared requests expose the final transport request, sanitized URL, method, and encoded body length.
pub(crate) async fn prepare_request(
    request: HttpRequest,
    call_config: &ResolvedCallConfig,
) -> Result<PreparedRequest, HttpError> {
    // @constraint selvedge.client.request.url HTTP requests require an absolute http or https URL before transport execution starts.
    let url = parse_absolute_http_url(&request.url)?;
    let mut headers = request.headers;
    let mut body = encode_body(request.body)?;

    // @behavior selvedge.client.request.user_agent network.user_agent is added only when the caller did not supply a User-Agent header.
    if !headers.contains_key(USER_AGENT)
        && let Some(user_agent) = &call_config.user_agent
    {
        let user_agent = HeaderValue::from_str(user_agent)
            .map_err(|_| build_error("network.user_agent violated config-model invariant"))?;
        headers.insert(USER_AGENT, user_agent);
    }

    finalize_headers(&mut headers, &body);
    body = maybe_compress_body(body, request.compression, &mut headers).await?;

    // @behavior selvedge.client.request.content_length A supplied Content-Length header is reconciled to the final encoded request body length.
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
        request_url: sanitize_url(&request.url).into_string(),
        body_len,
    })
}

// @constraint selvedge.client.request.url.parse Request URL parsing accepts only absolute http or https targets.
pub(crate) fn parse_absolute_http_url(url: &str) -> Result<Url, HttpError> {
    let parsed = Url::parse(url)
        .map_err(|error| build_error(format!("url must be an absolute URL: {error}")))?;

    // @constraint selvedge.client.request.url.absolute Relative URLs and URL forms without hosts are rejected as request build errors.
    if !parsed.has_host() || parsed.cannot_be_a_base() {
        return Err(build_error("url must be an absolute URL"));
    }

    // @constraint selvedge.client.request.url.scheme HTTP requests accept only http and https URL schemes.
    match parsed.scheme() {
        "http" | "https" => Ok(parsed),
        other => Err(build_error(format!(
            "url scheme must be http or https, got {other}"
        ))),
    }
}

// @behavior selvedge.client.request.body.encode Prepared request bodies encode empty, JSON, form-url-encoded, or raw bytes for transport.
pub(crate) fn encode_body(body: HttpRequestBody) -> Result<PreparedBody, HttpError> {
    match body {
        HttpRequestBody::Empty => Ok(PreparedBody::Empty),
        HttpRequestBody::Json(value) => {
            // @behavior selvedge.client.request.body.json JSON request bodies are serialized to bytes and receive application/json as the default Content-Type.
            let bytes = serde_json::to_vec(&value)
                .map(Bytes::from)
                .map_err(|error| build_error(format!("failed to encode json body: {error}")))?;

            Ok(PreparedBody::Buffered {
                bytes,
                content_type_if_missing: Some(HeaderValue::from_static("application/json")),
            })
        }
        HttpRequestBody::FormUrlEncoded(pairs) => {
            // @behavior selvedge.client.request.body.form Form request bodies are serialized with application/x-www-form-urlencoded as the default Content-Type.
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

// @behavior selvedge.client.request.headers.defaults Prepared requests add default body headers while preserving caller-supplied headers.
fn finalize_headers(headers: &mut HeaderMap, body: &PreparedBody) {
    // @constraint selvedge.client.request.content_type Caller-supplied Content-Type headers are preserved when a body type has a default Content-Type.
    if let PreparedBody::Buffered {
        content_type_if_missing: Some(content_type),
        ..
    } = body
        && !headers.contains_key(CONTENT_TYPE)
    {
        headers.insert(CONTENT_TYPE, content_type.clone());
    }
}

// @behavior selvedge.client.request.compression.apply Request compression applies the caller-selected compression mode during request preparation.
pub(crate) async fn maybe_compress_body(
    body: PreparedBody,
    compression: RequestCompression,
    headers: &mut HeaderMap,
) -> Result<PreparedBody, HttpError> {
    match (body, compression) {
        // @constraint selvedge.client.request.compression.empty Empty request bodies remain uncompressed and do not add compression headers.
        (PreparedBody::Empty, _) => Ok(PreparedBody::Empty),
        (body, RequestCompression::None) => Ok(body),
        // @constraint selvedge.client.request.compression.zstd_conflicts Zstd request compression updates body bytes and encoding headers only after conflict checks pass.
        (
            PreparedBody::Buffered {
                bytes,
                content_type_if_missing,
            },
            RequestCompression::Zstd,
        ) => {
            // @constraint selvedge.client.request.compression.header Zstd request compression is rejected when Content-Encoding is already supplied.
            if headers.contains_key(CONTENT_ENCODING) {
                return Err(build_error(
                    "cannot apply request compression when Content-Encoding is already set",
                ));
            }
            // @constraint selvedge.client.request.compression.integrity Zstd request compression is rejected when an integrity header would describe the uncompressed body.
            if let Some(integrity_header) = find_integrity_header(headers) {
                return Err(build_error(format!(
                    "cannot apply request compression when {} is already set",
                    integrity_header.as_str()
                )));
            }

            // @behavior selvedge.client.request.compression.zstd Zstd request compression replaces the request body bytes and sets Content-Encoding to zstd.
            let compressed = run_blocking(move || compress_bytes(bytes)).await?;
            headers.insert(CONTENT_ENCODING, HeaderValue::from_static("zstd"));

            Ok(PreparedBody::Buffered {
                bytes: compressed,
                content_type_if_missing,
            })
        }
    }
}

fn find_integrity_header(headers: &HeaderMap) -> Option<HeaderName> {
    headers
        .keys()
        .find(|name| is_integrity_header(name))
        .cloned()
}

// @constraint selvedge.client.request.compression.integrity.names Integrity-header conflict detection recognizes Content-MD5, Digest, Content-Digest, and Repr-Digest header names.
fn is_integrity_header(name: &HeaderName) -> bool {
    matches!(
        name.as_str().to_ascii_lowercase().as_str(),
        "content-md5" | "digest" | "content-digest" | "repr-digest"
    )
}

fn reconcile_content_length(body: &PreparedBody, headers: &mut HeaderMap) -> Result<(), HttpError> {
    // @constraint selvedge.client.request.content_length.final A caller-supplied Content-Length header reflects the encoded body size sent on the wire.
    if headers.contains_key(CONTENT_LENGTH) {
        let content_length = HeaderValue::from_str(&body.len().to_string()).map_err(|error| {
            build_error(format!("invalid computed Content-Length header: {error}"))
        })?;
        headers.insert(CONTENT_LENGTH, content_length);
    }

    Ok(())
}

// @behavior selvedge.client.request.compression.encode Zstd compression encodes request bytes or returns request build errors.
fn compress_bytes(bytes: Bytes) -> Result<Bytes, HttpError> {
    // @behavior selvedge.client.request.compression.start_error Zstd encoder start failures are returned to callers as request build errors.
    let mut encoder = zstd::stream::write::Encoder::new(Vec::new(), 0)
        .map_err(|error| build_error(format!("failed to start zstd encoder: {error}")))?;

    for chunk in bytes.chunks(64 * 1024) {
        encoder
            .write_all(chunk)
            .map_err(|error| build_error(format!("failed to encode zstd body: {error}")))?;
    }

    let compressed = encoder
        .finish()
        // @behavior selvedge.client.request.compression.finish_error Zstd encoder finish failures are returned to callers as request build errors.
        .map_err(|error| build_error(format!("failed to finish zstd body: {error}")))?;

    // @behavior selvedge.client.request.compression.output Successful zstd compression returns the compressed request bytes for the HTTP call.
    Ok(Bytes::from(compressed))
}
