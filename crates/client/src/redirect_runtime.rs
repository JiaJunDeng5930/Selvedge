use http::{StatusCode, header::LOCATION};

use crate::{HttpError, HttpMethod, HttpResponse, HttpStreamResponse, build_error};
use crate::{
    config_resolution::ResolvedCallConfig,
    request_prep::PreparedRequest,
    runtime::{
        RequestBudget, collect_status_error, collect_success_body, same_origin, send_with_budget,
        strip_origin_bound_headers, wrap_stream,
    },
    transport::RequestTransport,
};

const MAX_REDIRECT_HOPS: usize = 10;

pub(crate) async fn execute_inner(
    call_config: &ResolvedCallConfig,
    initial_prepared: PreparedRequest,
    mut request_budget: RequestBudget,
) -> Result<HttpResponse, HttpError> {
    let (response, request_url) =
        send_request(call_config, initial_prepared, &mut request_budget).await?;

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
    initial_prepared: PreparedRequest,
    mut request_budget: RequestBudget,
    idle_timeout: Option<std::time::Duration>,
) -> Result<HttpStreamResponse, HttpError> {
    let (response, request_url) =
        send_request(call_config, initial_prepared, &mut request_budget).await?;

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

async fn send_request(
    call_config: &ResolvedCallConfig,
    initial_prepared: PreparedRequest,
    request_budget: &mut RequestBudget,
) -> Result<(reqwest::Response, String), HttpError> {
    let mut current_request = initial_prepared;
    let mut transport = RequestTransport::new(call_config);
    let mut hop = 0_usize;

    loop {
        let request_url = crate::redaction::sanitize_parsed_url(&current_request.url).into_string();
        let client = transport
            .client(current_request.url.scheme() == "https")
            .await?;
        let response = send_with_budget(
            client,
            current_request.to_request(),
            &request_url,
            request_budget,
        )
        .await?;

        if should_follow_redirect(&current_request.method, response.status()) {
            let next_request = build_redirect_request(current_request, &response, hop)?;
            current_request = next_request;
            hop += 1;
            continue;
        }

        return Ok((response, request_url));
    }
}

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

fn build_redirect_request(
    mut current_request: PreparedRequest,
    response: &reqwest::Response,
    hop: usize,
) -> Result<PreparedRequest, HttpError> {
    if hop >= MAX_REDIRECT_HOPS {
        return Err(build_error("too many redirects"));
    }

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
        .map_err(|error| build_error(format!("invalid redirect target URL: {error}")))?;

    if !same_origin(response.url(), &next_url) {
        strip_origin_bound_headers(&mut current_request.headers);
    }

    let from_url = crate::redaction::sanitize_parsed_url(response.url());
    let to_url = crate::redaction::sanitize_parsed_url(&next_url);

    crate::log_event!(
        selvedge_logging::LogLevel::Debug,
        "http request redirected";
        from = from_url.as_str(),
        to = to_url.as_str(),
        status = response.status().as_u16(),
        hop = hop + 1
    );

    current_request.url = crate::request_prep::parse_absolute_http_url(next_url.as_str())?;

    Ok(current_request)
}

#[cfg(test)]
mod tests {
    use http::StatusCode;

    use crate::HttpMethod;

    use super::should_follow_redirect;

    #[test]
    fn only_get_redirects_are_followed() {
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
