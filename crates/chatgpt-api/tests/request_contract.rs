use chatgpt_api::{
    ChatgptModelCapabilities, ChatgptReasoningOptions, ChatgptRequestContext,
    ChatgptResponsesRequest, ChatgptTextOptions, ContentItem, JsonObject, MessageItem,
    ResponseItem, TextVerbosity, ToolDescriptor,
};

fn base_request() -> ChatgptResponsesRequest {
    ChatgptResponsesRequest {
        model: "gpt-5".to_owned(),
        model_capabilities: ChatgptModelCapabilities {
            supports_reasoning_summaries: true,
            supports_text_verbosity: true,
            default_reasoning_effort: Some("medium".to_owned()),
        },
        context: ChatgptRequestContext {
            conversation_id: "conversation-123".to_owned(),
            window_generation: 1,
            installation_id: "install-123".to_owned(),
            turn_state: Some("turn-state".to_owned()),
            turn_metadata: Some("{\"k\":\"v\"}".to_owned()),
            beta_features: vec!["beta-a".to_owned()],
            subagent: Some("planner".to_owned()),
            parent_thread_id: Some("thread-123".to_owned()),
        },
        instructions: Some("follow instructions".to_owned()),
        input: vec![ResponseItem::Message(MessageItem {
            id: Some("msg-1".to_owned()),
            status: Some("completed".to_owned()),
            phase: Some("commentary".to_owned()),
            role: "user".to_owned(),
            content: vec![ContentItem::InputText {
                text: "hello".to_owned(),
            }],
        })],
        tools: vec![ToolDescriptor(JsonObject::new())],
        parallel_tool_calls: true,
        reasoning: ChatgptReasoningOptions {
            effort: Some("high".to_owned()),
            summary: Some("detailed".to_owned()),
        },
        text: ChatgptTextOptions {
            verbosity: Some(TextVerbosity::High),
            json_schema: Some(JsonObject::new()),
        },
        service_tier: None,
    }
}

#[test]
fn request_validation_accepts_a_complete_request() {
    let request = base_request();

    request.validate().expect("valid request");
}

#[test]
fn request_validation_rejects_reasoning_summary_for_unsupported_models() {
    let mut request = base_request();
    request.model_capabilities.supports_reasoning_summaries = false;

    let error = request
        .validate()
        .expect_err("reasoning summary should be rejected");

    assert_eq!(error.field, "reasoning.summary");
}

#[test]
fn request_validation_rejects_verbosity_for_unsupported_models() {
    let mut request = base_request();
    request.model_capabilities.supports_text_verbosity = false;

    let error = request
        .validate()
        .expect_err("verbosity should be rejected");

    assert_eq!(error.field, "text.verbosity");
}

#[test]
fn request_validation_rejects_header_unsafe_values() {
    let mut request = base_request();
    request.context.turn_metadata = Some("bad\r\nvalue".to_owned());

    let error = request
        .validate()
        .expect_err("header unsafe values should be rejected");

    assert_eq!(error.field, "context.turn_metadata");
}

#[test]
fn request_validation_rejects_conversation_ids_with_colons() {
    let mut request = base_request();
    request.context.conversation_id = "conversation:123".to_owned();

    let error = request
        .validate()
        .expect_err("conversation ids with colons should be rejected");

    assert_eq!(error.field, "context.conversation_id");
}
