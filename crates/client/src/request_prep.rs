use std::io::Write;

use bytes::Bytes;
use http::{
    HeaderMap, HeaderValue,
    header::{CONTENT_ENCODING, CONTENT_LENGTH, CONTENT_TYPE, USER_AGENT},
};
use reqwest::Url;
use url::form_urlencoded;

use crate::{
    HttpError, HttpMethod, HttpRequest, HttpRequestBody, RequestCompression, build_error,
    run_blocking,
};
use crate::{config_resolution::ResolvedCallConfig, redaction::sanitize_url};

#[derive(Debug)]
pub(crate) struct PreparedRequest {
    pub(crate) request: reqwest::Request,
    pub(crate) method: HttpMethod,
    pub(crate) request_url: String,
    pub(crate) body_len: usize,
}

#[derive(Debug)]
pub(crate) enum PreparedBody {
    Empty,
    Buffered {
        bytes: Bytes,
        content_type_if_missing: Option<HeaderValue>,
    },
}

impl PreparedBody {
    pub(crate) fn into_bytes(self) -> Option<Bytes> {
        match self {
            Self::Empty => None,
            Self::Buffered { bytes, .. } => Some(bytes),
        }
    }

    pub(crate) fn len(&self) -> usize {
        match self {
            Self::Empty => 0,
            Self::Buffered { bytes, .. } => bytes.len(),
        }
    }
}

pub(crate) async fn prepare_request(
    request: HttpRequest,
    call_config: &ResolvedCallConfig,
) -> Result<PreparedRequest, HttpError> {
    let url = parse_absolute_http_url(&request.url)?;
    let mut headers = request.headers;
    let mut body = encode_body(request.body)?;

    if !headers.contains_key(USER_AGENT)
        && let Some(user_agent) = &call_config.user_agent
    {
        let user_agent = HeaderValue::from_str(user_agent)
            .map_err(|_| build_error("network.user_agent violated config-model invariant"))?;
        headers.insert(USER_AGENT, user_agent);
    }

    finalize_headers(&mut headers, &body);
    body = maybe_compress_body(body, request.compression, &mut headers).await?;

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

pub(crate) fn parse_absolute_http_url(url: &str) -> Result<Url, HttpError> {
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

pub(crate) fn encode_body(body: HttpRequestBody) -> Result<PreparedBody, HttpError> {
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

pub(crate) async fn maybe_compress_body(
    body: PreparedBody,
    compression: RequestCompression,
    headers: &mut HeaderMap,
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

            let compressed = run_blocking(move || compress_bytes(bytes)).await?;
            headers.insert(CONTENT_ENCODING, HeaderValue::from_static("zstd"));

            Ok(PreparedBody::Buffered {
                bytes: compressed,
                content_type_if_missing,
            })
        }
    }
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

fn compress_bytes(bytes: Bytes) -> Result<Bytes, HttpError> {
    let mut encoder = zstd::stream::write::Encoder::new(Vec::new(), 0)
        .map_err(|error| build_error(format!("failed to start zstd encoder: {error}")))?;

    for chunk in bytes.chunks(64 * 1024) {
        encoder
            .write_all(chunk)
            .map_err(|error| build_error(format!("failed to encode zstd body: {error}")))?;
    }

    let compressed = encoder
        .finish()
        .map_err(|error| build_error(format!("failed to finish zstd body: {error}")))?;

    Ok(Bytes::from(compressed))
}
