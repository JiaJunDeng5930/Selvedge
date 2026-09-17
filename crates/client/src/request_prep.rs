use std::io::Write;

use bytes::Bytes;
use http::{
    HeaderMap, HeaderName, HeaderValue,
    header::{CONTENT_ENCODING, CONTENT_LENGTH, CONTENT_TYPE, USER_AGENT},
};
use reqwest::Url;
use url::form_urlencoded;

use crate::config_resolution::ResolvedCallConfig;
use crate::{
    HttpError, HttpMethod, HttpRequest, HttpRequestBody, RequestCompression, build_error,
    run_blocking,
};

#[derive(Debug)]
pub(crate) struct PreparedRequest {
    pub(crate) method: HttpMethod,
    pub(crate) url: Url,
    pub(crate) headers: HeaderMap,
    body: PreparedBody,
}

impl PreparedRequest {
    pub(crate) fn body_len(&self) -> usize {
        self.body.len()
    }

    pub(crate) fn to_request(&self) -> reqwest::Request {
        let mut request = reqwest::Request::new(self.method.clone().into(), self.url.clone());
        *request.headers_mut() = self.headers.clone();
        if let PreparedBody::Buffered {
            bytes,
            content_type_if_missing,
            content_encoding,
        } = &self.body
        {
            if let Some(content_type) = content_type_if_missing {
                request
                    .headers_mut()
                    .entry(CONTENT_TYPE)
                    .or_insert(content_type.clone());
            }
            if let Some(content_encoding) = content_encoding {
                request
                    .headers_mut()
                    .insert(CONTENT_ENCODING, content_encoding.clone());
            }
            *request.body_mut() = Some(bytes.clone().into());
        }
        request
    }
}

#[derive(Debug)]
pub(crate) enum PreparedBody {
    Empty,
    Buffered {
        bytes: Bytes,
        content_type_if_missing: Option<HeaderValue>,
        content_encoding: Option<HeaderValue>,
    },
}

impl PreparedBody {
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

    body = maybe_compress_body(body, request.compression, &mut headers).await?;

    reconcile_content_length(&body, &mut headers)?;
    Ok(PreparedRequest {
        method: request.method,
        url,
        headers,
        body,
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
                content_encoding: None,
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
                content_encoding: None,
            })
        }
        HttpRequestBody::Bytes(bytes) => Ok(PreparedBody::Buffered {
            bytes,
            content_type_if_missing: None,
            content_encoding: None,
        }),
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
                ..
            },
            RequestCompression::Zstd,
        ) => {
            if headers.contains_key(CONTENT_ENCODING) {
                return Err(build_error(
                    "cannot apply request compression when Content-Encoding is already set",
                ));
            }
            if let Some(integrity_header) = find_integrity_header(headers) {
                return Err(build_error(format!(
                    "cannot apply request compression when {} is already set",
                    integrity_header.as_str()
                )));
            }

            let compressed = run_blocking(move || compress_bytes(bytes)).await?;

            Ok(PreparedBody::Buffered {
                bytes: compressed,
                content_type_if_missing,
                content_encoding: Some(HeaderValue::from_static("zstd")),
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

fn is_integrity_header(name: &HeaderName) -> bool {
    matches!(
        name.as_str().to_ascii_lowercase().as_str(),
        "content-md5" | "digest" | "content-digest" | "repr-digest"
    )
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
