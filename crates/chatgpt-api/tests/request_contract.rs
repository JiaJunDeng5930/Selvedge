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
            internal_chat_message_metadata_passthrough: None,
            phase: None,
            id: Some("msg-1".to_owned()),
            status: Some("completed".to_owned()),
            role: "user".to_owned(),
            content: vec![ContentItem::InputText {
                text: "hello".to_owned(),
            }],
        })],
        tools: vec![ToolDescriptor(JsonObject::new())],
        allowed_tools: None,
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
fn request_validation_accepts_controls_omitted_for_unsupported_models() {
    let mut request = base_request();
    request.model_capabilities.supports_reasoning_summaries = false;
    request.model_capabilities.supports_text_verbosity = false;
    request
        .validate()
        .expect("unsupported optional controls are omitted at encoding");
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

#[test]
fn configuration_updates_validate_typed_and_opaque_histories_together() {
    use chatgpt_api::{ConfigurationReasoningEffort, ConfigurationUpdateItem, OpaqueResponseItem};
    let update = ResponseItem::ConfigurationUpdate(ConfigurationUpdateItem {
        reasoning_effort: ConfigurationReasoningEffort::Max,
    });
    let mut request = base_request();
    request.model = "gpt-6-astra".to_owned();
    request.context.subagent = None;
    request.input.push(update.clone());
    request.validate().expect("typed configuration update");

    request.input.push(ResponseItem::Opaque(OpaqueResponseItem {
        raw: serde_json::from_value(serde_json::json!({
            "type": "configuration_update", "reasoning": {"effort": "low"}
        }))
        .expect("JSON object fixture"),
    }));
    let error = request
        .validate()
        .expect_err("opaque update cannot bypass adjacency");
    assert_eq!(error.field, "input.configuration_update");
    assert!(error.reason.contains("adjacent"));

    request.input = vec![update.clone(), base_request().input.remove(0), update];
    request.validate().expect("separated updates");
}

#[test]
fn configuration_updates_reject_unsupported_fields_and_efforts() {
    use chatgpt_api::OpaqueResponseItem;
    for invalid_update in [
        serde_json::json!({"type": "configuration_update"}),
        serde_json::json!({"type": "configuration_update", "reasoning": {}}),
        serde_json::json!({"type": "configuration_update", "reasoning": {"effort": "none"}}),
        serde_json::json!({"type": "configuration_update", "reasoning": {"effort": "minimal"}}),
        serde_json::json!({"type": "configuration_update", "reasoning": {"effort": "ultra"}}),
        serde_json::json!({"type": "configuration_update", "reasoning": {"effort": 3}}),
        serde_json::json!({"type": "configuration_update", "reasoning": {"effort": "high", "summary": "auto"}}),
        serde_json::json!({"type": "configuration_update", "reasoning": {"effort": "high"}, "model": "gpt-6-astra"}),
    ] {
        let mut request = base_request();
        request.input.push(ResponseItem::Opaque(OpaqueResponseItem {
            raw: serde_json::from_value(invalid_update.clone()).expect("JSON object fixture"),
        }));
        assert_eq!(
            request
                .validate()
                .expect_err(&invalid_update.to_string())
                .field,
            "input.configuration_update"
        );
    }
}

#[test]
fn async_tool_flags_require_booleans_in_descriptors_and_opaque_calls() {
    use chatgpt_api::OpaqueResponseItem;
    use serde_json::{Value, json};
    for tool_type in ["function", "custom"] {
        for asynchronous in [None, Some(Value::Bool(false)), Some(Value::Bool(true))] {
            let mut request = base_request();
            let mut descriptor = json!({"type": tool_type, "name": "lookup"});
            if let Some(asynchronous) = asynchronous {
                descriptor["async"] = asynchronous;
            }
            request.tools = vec![ToolDescriptor(
                serde_json::from_value(descriptor).expect("JSON object fixture"),
            )];
            request
                .validate()
                .expect("optional boolean async descriptor");
        }
        for invalid in [Value::Null, json!("true"), json!(1), json!([])] {
            let mut request = base_request();
            request.tools = vec![ToolDescriptor(
                serde_json::from_value(json!({
                    "type": tool_type, "name": "lookup", "async": invalid
                }))
                .expect("JSON object fixture"),
            )];
            assert_eq!(
                request
                    .validate()
                    .expect_err("invalid async descriptor")
                    .field,
                "tools.async"
            );
            request.tools.clear();
            request.input.push(ResponseItem::Opaque(OpaqueResponseItem {
                raw: serde_json::from_value(json!({
                    "type": if tool_type == "function" { "function_call" } else { "custom_tool_call" }, "async": invalid
                }))
                .expect("JSON object fixture"),
            }));
            assert_eq!(
                request
                    .validate()
                    .expect_err("invalid opaque async call")
                    .field,
                "input.async"
            );
        }
    }
}
