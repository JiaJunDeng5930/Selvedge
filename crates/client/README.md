# client

<!-- selvedge-package-readme
package: selvedge-client
freshness_fingerprint: 9319fb7e12af6068d53a1e8fb07445b64c852ea6
-->

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
- this crate does not support outbound proxies and intentionally ignores environment proxy settings such as `HTTP_PROXY` and `HTTPS_PROXY`
- `request.timeout` overrides `network.request_timeout_ms` only for that call
- `network.request_timeout_ms` is optional; when it is unset and no per-call timeout is supplied, this crate does not install a request timeout and leaves timeout behavior to the underlying HTTP client
- when `request.timeout` or `network.request_timeout_ms` is set, the timeout budget applies to transport wait phases such as sending the request, waiting for response headers, and waiting for response body chunks; it does not count caller-side processing time between stream polls
- `network.connect_timeout_ms` and `network.stream_idle_timeout_ms` follow the same rule: unset means this crate does not synthesize a fallback value
- `network.stream_idle_timeout_ms` applies only to the successful body stream returned by `stream(...)` after a `2xx` response head has been received
- `network.stream_idle_timeout_ms` does not apply to `execute(...)` body buffering and does not apply while `stream(...)` buffers a non-`2xx` response body before returning `HttpError::Status`
- for the successful `stream(...)` body stream, the idle timeout applies per wait window while waiting for the next body bytes and is reset only when non-empty bytes arrive

## Response semantics

- `GET` requests follow standard redirect statuses inside this crate, with a fixed hop limit
- redirect hops are rebuilt inside the crate; cross-origin hops keep only a small safe request-header allowlist and do not forward other caller-supplied headers
- `execute(...)` returns a full `HttpResponse` only for `2xx`
- `stream(...)` returns a raw `ByteStream` only for `2xx`
- non-`2xx` responses are returned as `HttpError::Status`
- bodies buffered by `execute(...)` and non-`2xx` handling are capped at 4 MiB and return `HttpError::ResponseTooLarge`
- response bodies stay raw; this crate does not auto-decompress or parse them

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([execute or stream])
  ReadConfig[Read network config]
  Prepare[Build request client, URL, headers, and body]
  Send[Send HTTP request]
  Redirect{redirect decision}
  Buffer[Buffer response body]
  OpenBody[Return streaming body]
  Success[Return HttpResponse or HttpStreamResponse]
  ConfigError[Return Config error]
  BuildError[Return Build error]
  TransportError[Return Transport error]
  StatusError[Return Status error with raw body]
  TimeoutError[Return Timeout]
  TooLarge[Return ResponseTooLarge]

  Start -->|caller invokes execute or stream| ReadConfig
  ReadConfig -->|selvedge_config read succeeds| Prepare
  ReadConfig -->|selvedge_config read fails| ConfigError
  Prepare -->|method, URL, TLS, timeout, compression, and body are prepared| Send
  Prepare -->|URL, client, certificate, compression, or request build fails| BuildError
  Send -->|response head arrives before configured timeout| Redirect
  Send -->|transport fails while sending request or reading response head| TransportError
  Send -->|configured request timeout expires| TimeoutError
  Redirect -->|GET response has supported redirect status and hop count remains| Prepare
  Redirect -->|redirect hop limit is exceeded or location is invalid| BuildError
  Redirect -->|status is 2xx and caller invoked execute| Buffer
  Redirect -->|status is 2xx and caller invoked stream| OpenBody
  Redirect -->|status is non-2xx| Buffer
  Buffer -->|execute body read succeeds for 2xx| Success
  Buffer -->|non-2xx body read succeeds| StatusError
  Buffer -->|body read fails| TransportError
  Buffer -->|buffered bytes exceed 4 MiB| TooLarge
  OpenBody -->|stream response created| Success
```
