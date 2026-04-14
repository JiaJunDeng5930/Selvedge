use std::time::Duration;

use chatgpt_api::{
    ChatgptApiEndpointError, ChatgptApiError, ChatgptApiLowerLayerError,
    ChatgptFailedEndpointError, ChatgptFailedEndpointKind, ChatgptIncompleteEndpointError,
    ChatgptModelCapabilities, ChatgptOtherEndpointError, ChatgptReasoningOptions,
    ChatgptRequestContext, ChatgptResponseEvent, ChatgptResponseSnapshot, ChatgptResponseStream,
    ChatgptResponsesRequest, ChatgptServiceTier, ChatgptTextOptions, ChatgptUsage, ContentItem,
    FunctionCallItem, FunctionCallOutputItem, JsonObject, MessageItem, OpaqueResponseItem,
    ReasoningItem, RequestValidationError, ResponseItem, TextVerbosity, ToolDescriptor, ToolOutput,
    stream,
};

#[test]
fn public_api_exposes_chatgpt_response_stream_types() {
    let json_object = JsonObject::new();
    let request = ChatgptResponsesRequest {
        model: "gpt-5".to_owned(),
        model_capabilities: ChatgptModelCapabilities {
            supports_reasoning_summaries: true,
            supports_text_verbosity: true,
            default_reasoning_effort: Some("medium".to_owned()),
        },
        context: ChatgptRequestContext {
            conversation_id: "conversation-123".to_owned(),
            window_generation: 2,
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
        service_tier: Some(ChatgptServiceTier::Fast),
    };
    let usage = ChatgptUsage {
        input_tokens: Some(1),
        cached_input_tokens: Some(2),
        output_tokens: Some(3),
        reasoning_output_tokens: Some(4),
        total_tokens: Some(10),
    };
    let snapshot = ChatgptResponseSnapshot {
        id: Some("resp-1".to_owned()),
        model: Some("gpt-5".to_owned()),
        usage: Some(usage),
        service_tier: Some("priority".to_owned()),
        raw: json_object.clone(),
    };
    let validation_error = RequestValidationError {
        field: "model",
        reason: "must not be blank".to_owned(),
    };
    let lower_error = ChatgptApiLowerLayerError::StreamCompletionTimeout {
        timeout: Duration::from_secs(30),
    };
    let endpoint_error = ChatgptApiEndpointError::Failed(ChatgptFailedEndpointError {
        kind: ChatgptFailedEndpointKind::InvalidPrompt,
        response_id: Some("resp-1".to_owned()),
        code: Some("invalid_prompt".to_owned()),
        message: Some("bad prompt".to_owned()),
        raw: json_object.clone(),
    });
    let other_endpoint_error =
        ChatgptApiEndpointError::Incomplete(ChatgptIncompleteEndpointError {
            response_id: Some("resp-1".to_owned()),
            reason: Some("max_output_tokens".to_owned()),
            raw: json_object.clone(),
        });
    let other = ChatgptApiEndpointError::Other(ChatgptOtherEndpointError {
        event_type: Some("response.failed".to_owned()),
        code: Some("server_overloaded".to_owned()),
        message: Some("retry later".to_owned()),
        retry_after: Some(Duration::from_secs(5)),
        raw: json_object.clone(),
    });
    let event = ChatgptResponseEvent::Completed(snapshot);
    let item = ResponseItem::FunctionCall(FunctionCallItem {
        id: Some("call-item".to_owned()),
        status: Some("completed".to_owned()),
        name: "do_work".to_owned(),
        namespace: Some("tools".to_owned()),
        arguments: "{\"x\":1}".to_owned(),
        call_id: "call-1".to_owned(),
    });
    let output_item = ResponseItem::FunctionCallOutput(FunctionCallOutputItem {
        id: Some("call-output".to_owned()),
        status: Some("completed".to_owned()),
        call_id: "call-1".to_owned(),
        output: ToolOutput::Text("done".to_owned()),
    });
    let reasoning_item = ResponseItem::Reasoning(ReasoningItem {
        id: Some("reasoning-1".to_owned()),
        status: Some("completed".to_owned()),
        summary: Some(serde_json::json!([{ "type": "summary_text", "text": "thinking" }])),
        content: None,
        encrypted_content: Some("cipher".to_owned()),
    });
    let opaque = ResponseItem::Opaque(OpaqueResponseItem { raw: json_object });

    assert_eq!(request.model, "gpt-5");
    assert!(matches!(
        lower_error,
        ChatgptApiLowerLayerError::StreamCompletionTimeout { .. }
    ));
    assert!(matches!(endpoint_error, ChatgptApiEndpointError::Failed(_)));
    assert!(matches!(
        other_endpoint_error,
        ChatgptApiEndpointError::Incomplete(_)
    ));
    assert!(matches!(other, ChatgptApiEndpointError::Other(_)));
    assert!(matches!(event, ChatgptResponseEvent::Completed(_)));
    assert!(matches!(item, ResponseItem::FunctionCall(_)));
    assert!(matches!(output_item, ResponseItem::FunctionCallOutput(_)));
    assert!(matches!(reasoning_item, ResponseItem::Reasoning(_)));
    assert!(matches!(opaque, ResponseItem::Opaque(_)));
    assert_eq!(validation_error.field, "model");

    let _ = ChatgptResponseStream::effective_turn_state;
    let _ = ChatgptResponsesRequest::validate;
    let _ = ChatgptApiError::LowerLayer(lower_error);
    let _ = stream;
}
