use std::collections::BTreeMap;

use selvedge_domain_model_api_slice::{
    ApiDomainValidationError, ConversationMessage, ConversationPath, MessageContent, MessageRole,
    ModelFinishReason, ModelProviderProfile, ModelReply, StructuredPayload, ToolCallProposal,
    ToolManifest, ToolParameter, ToolParameterType, ToolSpec, validate_conversation_path,
    validate_model_provider_profile, validate_model_reply, validate_tool_manifest,
};

#[test]
fn conversation_path_requires_at_least_one_message_and_preserves_order() {
    let empty = ConversationPath {
        messages: Vec::new(),
    };

    assert_eq!(
        validate_conversation_path(&empty),
        Err(ApiDomainValidationError::EmptyConversationPath)
    );

    let path = ConversationPath {
        messages: vec![
            ConversationMessage {
                role: MessageRole::System,
                content: MessageContent::Text("system".to_owned()),
                source_node_id: None,
            },
            ConversationMessage {
                role: MessageRole::User,
                content: MessageContent::Text("user".to_owned()),
                source_node_id: None,
            },
        ],
    };

    validate_conversation_path(&path).expect("valid conversation path");

    match &path.messages[0].content {
        MessageContent::Text(value) => assert_eq!(value, "system"),
        _ => panic!("unexpected content"),
    }
    match &path.messages[1].content {
        MessageContent::Text(value) => assert_eq!(value, "user"),
        _ => panic!("unexpected content"),
    }
}

#[test]
fn tool_manifest_rejects_empty_or_duplicate_tool_names() {
    let empty_name = ToolManifest {
        tools: vec![ToolSpec {
            name: " ".to_owned(),
            description: "search".to_owned(),
            parameters: Vec::new(),
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
                parameters: Vec::new(),
            },
            ToolSpec {
                name: "search".to_owned(),
                description: "search again".to_owned(),
                parameters: Vec::new(),
            },
        ],
    };

    assert_eq!(
        validate_tool_manifest(&duplicate_name),
        Err(ApiDomainValidationError::DuplicateToolName)
    );
}

#[test]
fn tool_manifest_rejects_empty_or_duplicate_parameter_names_per_tool() {
    let empty_parameter = ToolManifest {
        tools: vec![ToolSpec {
            name: "search".to_owned(),
            description: "search".to_owned(),
            parameters: vec![ToolParameter {
                name: String::new(),
                parameter_type: ToolParameterType::String,
                description: "query".to_owned(),
                required: true,
            }],
        }],
    };

    assert_eq!(
        validate_tool_manifest(&empty_parameter),
        Err(ApiDomainValidationError::EmptyToolParameterName)
    );

    let duplicate_parameter = ToolManifest {
        tools: vec![ToolSpec {
            name: "search".to_owned(),
            description: "search".to_owned(),
            parameters: vec![
                ToolParameter {
                    name: "query".to_owned(),
                    parameter_type: ToolParameterType::String,
                    description: "query".to_owned(),
                    required: true,
                },
                ToolParameter {
                    name: "query".to_owned(),
                    parameter_type: ToolParameterType::String,
                    description: "query again".to_owned(),
                    required: false,
                },
            ],
        }],
    };

    assert_eq!(
        validate_tool_manifest(&duplicate_parameter),
        Err(ApiDomainValidationError::DuplicateToolParameterName)
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
            arguments: StructuredPayload::Object(BTreeMap::new()),
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
            arguments: StructuredPayload::Object(BTreeMap::new()),
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
