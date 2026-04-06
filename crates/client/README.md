# client

## This crate is for

This crate is the project HTTP client entrypoint.

Use it to:

- execute one-shot HTTP requests through `execute(...)`
- execute streaming HTTP requests through `stream(...)`
- read `network.*` config fresh for every call
- emit structured transport logs through `selvedge_logging`

## This crate is not for

This crate is not for:

- exposing a reusable client object
- caching config, transport builders, or per-request derived state
- retrying requests implicitly
- parsing response bodies into JSON, SSE, or auth-specific models

## Call model

Callers build an `HttpRequest` value and pass it to one of two functions:

- `execute(...)` for full-body responses
- `stream(...)` for raw byte streams

```no_run
use http::HeaderMap;
use selvedge_client::{
    HttpMethod, HttpRequest, HttpRequestBody, RequestCompression, execute,
};

# #[tokio::main(flavor = "current_thread")]
# async fn main() -> Result<(), Box<dyn std::error::Error>> {
let response = execute(HttpRequest {
    method: HttpMethod::Post,
    url: "https://example.com/endpoint".to_owned(),
    headers: HeaderMap::new(),
    body: HttpRequestBody::Json(serde_json::json!({ "x": 1 })),
    timeout: None,
    compression: RequestCompression::None,
})
.await?;

assert!(response.status.is_success());
# Ok(())
# }
```

## Runtime and config

- callers must initialize `selvedge_config` before using this crate
- callers must run these async functions inside a Tokio runtime
- every call reads `network.*` config immediately through `selvedge_config::read`
- `request.timeout` overrides `network.request_timeout_ms` only for that call

## Response semantics

- `execute(...)` returns a full `HttpResponse` only for `2xx`
- `stream(...)` returns a raw `ByteStream` only for `2xx`
- non-`2xx` responses are returned as `HttpError::Status`
- response bodies stay raw; this crate does not auto-decompress or parse them
