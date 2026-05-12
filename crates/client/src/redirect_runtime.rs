use http::{StatusCode, header::LOCATION};

use crate::{HttpError, HttpMethod, HttpRequest, HttpResponse, HttpStreamResponse, build_error};
use crate::{
    config_resolution::ResolvedCallConfig,
    request_prep::{PreparedRequest, prepare_request},
    runtime::{
        RequestBudget, collect_status_error, collect_success_body, same_origin,
        strip_origin_bound_headers, wrap_stream,
    },
    single_hop::send_single_hop,
};

const MAX_REDIRECT_HOPS: usize = 10;

// @behavior selvedge.client.execute.inner execute_inner follows redirects, buffers successful bodies, and returns status errors for non-success responses.
pub(crate) async fn execute_inner(
    call_config: &ResolvedCallConfig,
    request: HttpRequest,
    initial_prepared: PreparedRequest,
    mut request_budget: RequestBudget,
) -> Result<HttpResponse, HttpError> {
    let (response, request_url) =
        send_request(call_config, request, initial_prepared, &mut request_budget).await?;

    if !response.status().is_success() {
        // @behavior selvedge.client.execute.status execute returns non-success HTTP responses as HttpError::Status.
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

// @behavior selvedge.client.stream.inner stream_inner follows redirects, returns successful response metadata, and exposes successful bodies as streams.
pub(crate) async fn stream_inner(
    call_config: &ResolvedCallConfig,
    request: HttpRequest,
    initial_prepared: PreparedRequest,
    mut request_budget: RequestBudget,
    idle_timeout: Option<std::time::Duration>,
) -> Result<HttpStreamResponse, HttpError> {
    let (response, request_url) =
        send_request(call_config, request, initial_prepared, &mut request_budget).await?;

    if !response.status().is_success() {
        // @behavior selvedge.client.stream.status_error stream returns non-success HTTP responses as HttpError::Status before exposing a body stream.
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

// @behavior selvedge.client.redirect GET requests follow standard redirect statuses up to the fixed redirect hop limit.
async fn send_request(
    call_config: &ResolvedCallConfig,
    request: HttpRequest,
    initial_prepared: PreparedRequest,
    request_budget: &mut RequestBudget,
) -> Result<(reqwest::Response, String), HttpError> {
    let mut current_request = request;
    let mut next_prepared = Some(initial_prepared);
    let mut hop = 0_usize;

    loop {
        let prepared = match next_prepared.take() {
            Some(prepared) => prepared,
            None => prepare_request(current_request.clone(), call_config).await?,
        };
        let request_url = prepared.request_url.clone();
        let response = send_single_hop(call_config, prepared, request_budget).await?;

        if should_follow_redirect(&current_request.method, response.status()) {
            // @behavior selvedge.client.redirect.hop Each followed redirect rebuilds the request for the next target URL.
            let next_request = build_redirect_request(current_request, &response, hop)?;
            current_request = next_request;
            hop += 1;
            continue;
        }

        return Ok((response, request_url));
    }
}

// @constraint selvedge.client.redirect.method Only GET requests follow redirect responses.
// @constraint selvedge.client.redirect.statuses Redirect following accepts 301, 302, 303, 307, and 308 responses.
fn should_follow_redirect(method: &HttpMethod, status: StatusCode) -> bool {
    matches!(method, HttpMethod::Get)
        && matches!(
            status,
            StatusCode::MOVED_PERMANENTLY
                | StatusCode::FOUND
                | StatusCode::SEE_OTHER
                | StatusCode::TEMPORARY_REDIRECT
                | StatusCode::PERMANENT_REDIRECT
        )
}

// @constraint selvedge.client.redirect.limit Redirect following stops with a build error after ten hops.
fn build_redirect_request(
    mut current_request: HttpRequest,
    response: &reqwest::Response,
    hop: usize,
) -> Result<HttpRequest, HttpError> {
    if hop >= MAX_REDIRECT_HOPS {
        return Err(build_error("too many redirects"));
    }

    // @constraint selvedge.client.redirect.location Followed redirects require a valid Location header that resolves to a target URL.
    let location = response
        .headers()
        .get(LOCATION)
        .ok_or_else(|| build_error("redirect response did not include Location header"))?;
    let location = location
        .to_str()
        .map_err(|error| build_error(format!("invalid redirect location header: {error}")))?;
    let next_url = response
        .url()
        .join(location)
        // @constraint selvedge.client.redirect.target Redirect targets must resolve to a valid URL before the next request is sent.
        .map_err(|error| build_error(format!("invalid redirect target URL: {error}")))?;

    if !same_origin(response.url(), &next_url) {
        // @constraint selvedge.client.redirect.cross_origin Cross-origin redirects remove caller-supplied origin-bound headers before the next request.
        strip_origin_bound_headers(&mut current_request.headers);
    }

    let from_url = crate::redaction::sanitize_parsed_url(response.url());
    let to_url = crate::redaction::sanitize_parsed_url(&next_url);

    // @behavior selvedge.client.redirect.log Followed redirects emit a structured debug log with sanitized source and target URLs.
    crate::log_event!(
        selvedge_logging::LogLevel::Debug,
        "http request redirected";
        from = from_url.as_str(),
        to = to_url.as_str(),
        status = response.status().as_u16(),
        hop = hop + 1
    );

    // @constraint selvedge.client.redirect.preserve_request Followed redirects preserve method, body, timeout, compression, and same-origin headers while replacing the request URL.
    current_request.url = next_url.into();

    Ok(current_request)
}

#[cfg(test)]
mod tests {
    use http::StatusCode;

    use crate::HttpMethod;

    use super::should_follow_redirect;

    #[test]
    fn only_get_redirects_are_followed() {
        // @verifies selvedge.client.redirect.method
        assert!(should_follow_redirect(&HttpMethod::Get, StatusCode::FOUND));
        assert!(!should_follow_redirect(
            &HttpMethod::Post,
            StatusCode::FOUND
        ));
        assert!(!should_follow_redirect(
            &HttpMethod::Get,
            StatusCode::BAD_REQUEST
        ));
    }
}
