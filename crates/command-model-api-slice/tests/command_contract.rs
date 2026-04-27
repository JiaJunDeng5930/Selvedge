use selvedge_command_model_api_slice::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, ModelCallDispatchRequest, ModelCallError,
    ModelCallErrorKind, ModelRunId, RouterIngressApiMessage, TaskId, validate_api_output_envelope,
    validate_dispatch_request,
};
use selvedge_domain_model_api_slice::{
    ConversationMessage, ConversationPath, MessageContent, MessageRole, ModelFinishReason,
    ModelProviderProfile, ModelReply, ResponsePreference,
};

#[test]
fn dispatch_request_requires_complete_correlation_provider_and_conversation() {
    let mut request = valid_dispatch_request();
    request.correlation.api_effect_id = ApiEffectId(" ".to_owned());

    let error = validate_dispatch_request(&request).expect_err("empty api effect id");
    assert_eq!(error.kind, ModelCallErrorKind::Validation);
    assert!(error.message.contains("api_effect_id"));

    let mut request = valid_dispatch_request();
    request.provider.provider_name.clear();

    let error = validate_dispatch_request(&request).expect_err("empty provider name");
    assert_eq!(error.kind, ModelCallErrorKind::Validation);
    assert!(error.message.contains("provider"));

    let mut request = valid_dispatch_request();
    request.conversation.messages.clear();

    let error = validate_dispatch_request(&request).expect_err("empty conversation");
    assert_eq!(error.kind, ModelCallErrorKind::Validation);
    assert!(error.message.contains("conversation"));
}

#[test]
fn dispatch_request_accepts_valid_optional_empty_tool_manifest() {
    let request = valid_dispatch_request();

    validate_dispatch_request(&request).expect("valid dispatch request");
}

#[test]
fn api_output_envelope_carries_exactly_success_or_failure_payload() {
    let correlation = valid_correlation();
    let reply = ModelReply {
        content: Some("reply".to_owned()),
        tool_calls: Vec::new(),
        usage: None,
        finish_reason: ModelFinishReason::Stop,
    };

    let success = ApiOutputEnvelope::Success {
        correlation: correlation.clone(),
        reply,
    };
    validate_api_output_envelope(&success).expect("valid success envelope");

    let failure = ApiOutputEnvelope::Failure {
        correlation,
        error: ModelCallError {
            kind: ModelCallErrorKind::ProviderNetwork,
            message: "network failure".to_owned(),
        },
    };
    validate_api_output_envelope(&failure).expect("valid failure envelope");
}

#[test]
fn router_ingress_api_message_wraps_output_envelope() {
    let message = RouterIngressApiMessage::ApiOutput(ApiOutputEnvelope::Failure {
        correlation: valid_correlation(),
        error: ModelCallError {
            kind: ModelCallErrorKind::Cancelled,
            message: "cancelled".to_owned(),
        },
    });

    match message {
        RouterIngressApiMessage::ApiOutput(ApiOutputEnvelope::Failure { error, .. }) => {
            assert_eq!(error.kind, ModelCallErrorKind::Cancelled);
        }
        _ => panic!("unexpected message"),
    }
}

fn valid_dispatch_request() -> ModelCallDispatchRequest {
    ModelCallDispatchRequest {
        correlation: valid_correlation(),
        provider: ModelProviderProfile {
            provider_name: "provider".to_owned(),
            model_name: "model".to_owned(),
            temperature: None,
            max_output_tokens: None,
        },
        conversation: ConversationPath {
            messages: vec![ConversationMessage {
                role: MessageRole::User,
                content: MessageContent::Text("hello".to_owned()),
                source_node_id: None,
            }],
        },
        tool_manifest: None,
        response_preference: ResponsePreference::PlainTextOrToolCalls,
    }
}

fn valid_correlation() -> ApiCallCorrelation {
    ApiCallCorrelation {
        api_effect_id: ApiEffectId("api-1".to_owned()),
        task_id: TaskId("task-1".to_owned()),
        model_run_id: ModelRunId("run-1".to_owned()),
    }
}
