use selvedge_domain_model::{
    ApiDomainValidationError, Conversation, ConversationMessage, FunctionCallId, JsonObject,
    MessageRole, ModelFinishReason, ModelProviderProfile, ModelReply, TaskLifecycleEvent,
    TaskStatus, ToolCallProposal, ToolManifest, ToolName, ToolSpec, validate_conversation,
    validate_model_provider_profile, validate_model_reply, validate_tool_manifest,
};

#[test]
fn task_lifecycle_transition_table_is_exhaustive() {
    use TaskLifecycleEvent::{Archive, Freeze, Stop, Unfreeze, UserInput};
    use TaskStatus::{Active, Archived, Frozen, Stopped};

    let statuses = [Active, Frozen, Stopped, Archived];
    let events = [Freeze, Unfreeze, Stop, Archive, UserInput];
    let valid = [
        (Active, Freeze, Frozen),
        (Frozen, Unfreeze, Active),
        (Active, Stop, Stopped),
        (Active, Archive, Archived),
        (Frozen, Archive, Archived),
        (Stopped, Archive, Archived),
        (Active, UserInput, Active),
        (Frozen, UserInput, Frozen),
        (Stopped, UserInput, Active),
    ];

    for status in statuses {
        for event in events {
            let expected = valid
                .iter()
                .find_map(|(from, cause, to)| (*from == status && *cause == event).then_some(*to));
            assert_eq!(status.transition(event), expected, "{status:?} + {event:?}");
        }
    }
}

#[test]
fn conversation_requires_at_least_one_message_and_preserves_text_json() {
    let empty = Conversation {
        messages: Vec::new(),
    };

    assert_eq!(
        validate_conversation(&empty),
        Err(ApiDomainValidationError::EmptyConversation)
    );

    let conversation = Conversation {
        messages: vec![
            ConversationMessage::text(MessageRole::System, "system", None),
            ConversationMessage::text(MessageRole::User, "user", None),
        ],
    };

    validate_conversation(&conversation).expect("valid conversation");

    assert_eq!(
        conversation.messages[0].content,
        serde_json::json!("system")
    );
    assert_eq!(conversation.messages[1].content, serde_json::json!("user"));
}

#[test]
fn conversation_tool_content_uses_the_shared_json_contract() {
    let arguments = serde_json::from_value::<JsonObject>(serde_json::json!({
        "query": "rust",
        "page": 2,
    }))
    .expect("arguments object");
    let function_call = ConversationMessage::function_call(
        FunctionCallId("call-1".to_owned()),
        ToolName("search".to_owned()),
        arguments.clone(),
        None,
    );

    assert_eq!(function_call.role, MessageRole::Assistant);
    assert_eq!(
        function_call.content,
        serde_json::json!({
            "type": "function_call",
            "function_call_id": "call-1",
            "tool_name": "search",
            "arguments": arguments,
        })
    );
    assert_eq!(function_call.content_type(), Some("function_call"));
    assert_eq!(function_call.function_call_id(), Some("call-1"));
    assert_eq!(function_call.tool_name(), Some("search"));
    assert_eq!(
        function_call.function_call_arguments(),
        function_call
            .content
            .get("arguments")
            .and_then(serde_json::Value::as_object)
    );

    let output = serde_json::json!({"matches": ["serde", "serde_json"]});
    let function_output = ConversationMessage::function_output(
        FunctionCallId("call-1".to_owned()),
        ToolName("search".to_owned()),
        output.clone(),
        false,
        None,
    );

    assert_eq!(function_output.role, MessageRole::Tool);
    assert_eq!(
        function_output.content,
        serde_json::json!({
            "type": "function_output",
            "function_call_id": "call-1",
            "tool_name": "search",
            "output": output,
            "is_error": false,
        })
    );
    assert_eq!(function_output.content_type(), Some("function_output"));
    assert_eq!(function_output.function_call_id(), Some("call-1"));
    assert_eq!(function_output.tool_name(), Some("search"));
    assert_eq!(
        function_output.function_output_value(),
        function_output.content.get("output")
    );
    assert_eq!(function_output.function_output_is_error(), Some(false));
}

#[test]
fn tool_manifest_rejects_empty_or_duplicate_tool_names() {
    let empty_name = ToolManifest {
        tools: vec![ToolSpec {
            name: " ".to_owned(),
            description: "search".to_owned(),
            input_schema: JsonObject::new(),
        }],
    };

    assert_eq!(
        validate_tool_manifest(&empty_name),
        Err(ApiDomainValidationError::EmptyToolName)
    );

    let duplicate_name = ToolManifest {
        tools: vec![
            ToolSpec {
                name: "search".to_owned(),
                description: "search".to_owned(),
                input_schema: JsonObject::new(),
            },
            ToolSpec {
                name: "search".to_owned(),
                description: "search again".to_owned(),
                input_schema: JsonObject::new(),
            },
        ],
    };

    assert_eq!(
        validate_tool_manifest(&duplicate_name),
        Err(ApiDomainValidationError::DuplicateToolName)
    );
}

#[test]
fn provider_profile_requires_provider_and_model_names() {
    let empty_provider = ModelProviderProfile {
        provider_name: String::new(),
        model_name: "model".to_owned(),
        temperature: None,
        max_output_tokens: None,
    };

    assert_eq!(
        validate_model_provider_profile(&empty_provider),
        Err(ApiDomainValidationError::EmptyProviderName)
    );

    let empty_model = ModelProviderProfile {
        provider_name: "provider".to_owned(),
        model_name: " ".to_owned(),
        temperature: Some(0.2),
        max_output_tokens: Some(128),
    };

    assert_eq!(
        validate_model_provider_profile(&empty_model),
        Err(ApiDomainValidationError::EmptyModelName)
    );
}

#[test]
fn model_reply_requires_text_or_valid_tool_calls() {
    let empty_reply = ModelReply {
        content: None,
        tool_calls: Vec::new(),
        usage: None,
        finish_reason: ModelFinishReason::Stop,
    };

    assert_eq!(
        validate_model_reply(&empty_reply),
        Err(ApiDomainValidationError::EmptyModelReply)
    );

    let missing_call_id = ModelReply {
        content: None,
        tool_calls: vec![ToolCallProposal {
            call_id: String::new(),
            tool_name: "search".to_owned(),
            arguments: JsonObject::new(),
        }],
        usage: None,
        finish_reason: ModelFinishReason::ToolCalls,
    };

    assert_eq!(
        validate_model_reply(&missing_call_id),
        Err(ApiDomainValidationError::EmptyToolCallId)
    );

    let missing_tool_name = ModelReply {
        content: None,
        tool_calls: vec![ToolCallProposal {
            call_id: "call-1".to_owned(),
            tool_name: " ".to_owned(),
            arguments: JsonObject::new(),
        }],
        usage: None,
        finish_reason: ModelFinishReason::ToolCalls,
    };

    assert_eq!(
        validate_model_reply(&missing_tool_name),
        Err(ApiDomainValidationError::EmptyToolCallName)
    );

    let text_reply = ModelReply {
        content: Some("hello".to_owned()),
        tool_calls: Vec::new(),
        usage: None,
        finish_reason: ModelFinishReason::Stop,
    };

    validate_model_reply(&text_reply).expect("valid text reply");
}
