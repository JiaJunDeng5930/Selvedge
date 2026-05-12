use crate::{
    HttpError,
    config_resolution::ResolvedCallConfig,
    request_prep::PreparedRequest,
    runtime::{RequestBudget, build_client, send_with_budget},
};

// @behavior selvedge.client.transport.single_hop Each redirect hop builds a fresh HTTP client and sends exactly one prepared request.
pub(crate) async fn send_single_hop(
    call_config: &ResolvedCallConfig,
    prepared: PreparedRequest,
    request_budget: &mut RequestBudget,
) -> Result<reqwest::Response, HttpError> {
    let request_url = prepared.request_url;
    let request = prepared.request;
    let client = build_client(call_config, request.url().scheme() == "https").await?;

    send_with_budget(client, request, request_url.as_str(), request_budget).await
}
