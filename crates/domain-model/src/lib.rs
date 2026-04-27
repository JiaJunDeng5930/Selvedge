#![doc = include_str!("../README.md")]

use std::collections::{BTreeMap, BTreeSet};

use serde::Serialize;

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
pub struct HistoryNodeIdRef(pub String);

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ConversationPath {
    pub messages: Vec<ConversationMessage>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ConversationMessage {
    pub role: MessageRole,
    pub content: MessageContent,
    pub source_node_id: Option<HistoryNodeIdRef>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum MessageRole {
    System,
    User,
    Assistant,
    Tool,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub enum MessageContent {
    Text(String),
    Structured(StructuredPayload),
    ToolResultSummary(String),
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ToolManifest {
    pub tools: Vec<ToolSpec>,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub parameters: Vec<ToolParameter>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ToolParameter {
    pub name: String,
    pub parameter_type: ToolParameterType,
    pub description: String,
    pub required: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum ToolParameterType {
    String,
    Integer,
    Number,
    Boolean,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub enum StructuredPayload {
    Object(BTreeMap<String, StructuredPayload>),
    Array(Vec<StructuredPayload>),
    String(String),
    Number(f64),
    Boolean(bool),
    Null,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ModelProviderProfile {
    pub provider_name: String,
    pub model_name: String,
    pub temperature: Option<f32>,
    pub max_output_tokens: Option<u32>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum ResponsePreference {
    PlainTextOrToolCalls,
    PlainTextOnly,
    ToolCallsAllowed,
    StructuredOutput,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ModelReply {
    pub content: Option<String>,
    pub tool_calls: Vec<ToolCallProposal>,
    pub usage: Option<TokenUsage>,
    pub finish_reason: ModelFinishReason,
}

#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ToolCallProposal {
    pub call_id: String,
    pub tool_name: String,
    pub arguments: StructuredPayload,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct TokenUsage {
    pub input_tokens: u64,
    pub output_tokens: u64,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum ModelFinishReason {
    Stop,
    Length,
    ToolCalls,
    ContentFilter,
    Unknown,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ApiDomainValidationError {
    EmptyConversationPath,
    EmptyToolName,
    DuplicateToolName,
    EmptyToolParameterName,
    DuplicateToolParameterName,
    EmptyProviderName,
    EmptyModelName,
    EmptyModelReply,
    EmptyToolCallId,
    EmptyToolCallName,
}

pub fn validate_conversation_path(path: &ConversationPath) -> Result<(), ApiDomainValidationError> {
    if path.messages.is_empty() {
        return Err(ApiDomainValidationError::EmptyConversationPath);
    }

    Ok(())
}

pub fn validate_tool_manifest(manifest: &ToolManifest) -> Result<(), ApiDomainValidationError> {
    let mut tool_names = BTreeSet::new();

    for tool in &manifest.tools {
        if tool.name.trim().is_empty() {
            return Err(ApiDomainValidationError::EmptyToolName);
        }

        if !tool_names.insert(tool.name.as_str()) {
            return Err(ApiDomainValidationError::DuplicateToolName);
        }

        let mut parameter_names = BTreeSet::new();

        for parameter in &tool.parameters {
            if parameter.name.trim().is_empty() {
                return Err(ApiDomainValidationError::EmptyToolParameterName);
            }

            if !parameter_names.insert(parameter.name.as_str()) {
                return Err(ApiDomainValidationError::DuplicateToolParameterName);
            }
        }
    }

    Ok(())
}

pub fn validate_model_provider_profile(
    profile: &ModelProviderProfile,
) -> Result<(), ApiDomainValidationError> {
    if profile.provider_name.trim().is_empty() {
        return Err(ApiDomainValidationError::EmptyProviderName);
    }

    if profile.model_name.trim().is_empty() {
        return Err(ApiDomainValidationError::EmptyModelName);
    }

    Ok(())
}

pub fn validate_model_reply(reply: &ModelReply) -> Result<(), ApiDomainValidationError> {
    let has_content = reply
        .content
        .as_deref()
        .is_some_and(|content| !content.trim().is_empty());

    if !has_content && reply.tool_calls.is_empty() {
        return Err(ApiDomainValidationError::EmptyModelReply);
    }

    for tool_call in &reply.tool_calls {
        if tool_call.call_id.trim().is_empty() {
            return Err(ApiDomainValidationError::EmptyToolCallId);
        }

        if tool_call.tool_name.trim().is_empty() {
            return Err(ApiDomainValidationError::EmptyToolCallName);
        }
    }

    Ok(())
}
