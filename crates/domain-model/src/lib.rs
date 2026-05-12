#![doc = include_str!("../README.md")]
//! @behavior selvedge.model.domain Model-call packages exchange conversation history, tool schemas, provider choices, structured payloads, and normalized replies through this API.

use std::collections::{BTreeMap, BTreeSet};

use serde::Serialize;

/// @behavior selvedge.model.domain.ids External callers address persisted history nodes, tasks, tools, function calls, model profiles, and timestamps with typed identifiers.
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
pub struct HistoryNodeIdRef(pub String);

/// @behavior selvedge.model.domain.task_id_type External callers compare and serialize task identifiers as stable domain identifiers.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize)]
pub struct TaskId(pub String);

/// @behavior selvedge.model.domain.history_node_id_type External callers compare and serialize persisted history-node identifiers as stable domain identifiers.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Serialize)]
pub struct HistoryNodeId(pub i64);

/// @behavior selvedge.model.domain.tool_name_type External callers compare and serialize tool names as stable domain identifiers.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize)]
pub struct ToolName(pub String);

// @behavior selvedge.model.domain.tool_parameter_name_type External callers compare and serialize tool parameter names as stable domain identifiers.
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize)]
pub struct ToolParameterName(pub String);

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
// @behavior selvedge.model.domain.function_call_id_type External callers compare and serialize function-call identifiers as stable domain identifiers.
pub struct FunctionCallId(pub String);

#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize)]
// @behavior selvedge.model.domain.model_profile_key_type External callers compare and serialize model profile keys as stable domain identifiers.
pub struct ModelProfileKey(pub String);

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize)]
// @behavior selvedge.model.domain.unix_ts_type External callers compare and serialize Unix timestamps as stable domain timestamps.
pub struct UnixTs(pub i64);

// @behavior selvedge.model.domain.conversation_path Model dispatch receives an ordered conversation path as the request history.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ConversationPath {
    // @behavior selvedge.model.domain.conversation_path_messages Callers provide conversation messages in the order sent to the model provider.
    pub messages: Vec<ConversationMessage>,
}

// @behavior selvedge.model.domain.conversation_message Model dispatch receives each conversation message with role, content, and optional source history reference.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ConversationMessage {
    // @behavior selvedge.model.domain.conversation_message_role Callers expose the model-visible role for a conversation message.
    pub role: MessageRole,
    // @behavior selvedge.model.domain.conversation_message_content Callers expose the model-visible content for a conversation message.
    pub content: MessageContent,
    // @behavior selvedge.model.domain.conversation_message_source Callers can link a conversation message to a persisted history node.
    pub source_node_id: Option<HistoryNodeIdRef>,
}

// @behavior selvedge.model.domain.message_role Model dispatch exposes the supported model-visible message roles.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum MessageRole {
    System,
    Developer,
    User,
    Assistant,
    Tool,
}

// @behavior selvedge.model.domain.message_content Model dispatch exposes text, structured payload, and tool result summary message content.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub enum MessageContent {
    Text(String),
    Structured(StructuredPayload),
    ToolResultSummary(String),
}

// @behavior selvedge.model.domain.tool_manifest Model dispatch receives the available tool schema list for a model call.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ToolManifest {
    // @behavior selvedge.model.domain.tool_manifest_tools Callers provide every tool schema available to a model call.
    pub tools: Vec<ToolSpec>,
}

// @behavior selvedge.model.domain.tool_spec Model dispatch receives each tool schema with name, description, and parameters.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ToolSpec {
    // @behavior selvedge.model.domain.tool_spec_name Callers expose the model-visible tool name.
    pub name: String,
    // @behavior selvedge.model.domain.tool_spec_description Callers expose the model-visible tool description.
    pub description: String,
    // @behavior selvedge.model.domain.tool_spec_parameters Callers expose the model-visible tool parameter schema.
    pub parameters: Vec<ToolParameter>,
}

// @behavior selvedge.model.domain.tool_parameter Model dispatch receives each tool parameter with name, type, description, and required flag.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ToolParameter {
    // @behavior selvedge.model.domain.tool_parameter_name_field Callers expose the model-visible parameter name.
    pub name: String,
    // @behavior selvedge.model.domain.tool_parameter_type_field Callers expose the model-visible parameter type.
    pub parameter_type: ToolParameterType,
    // @behavior selvedge.model.domain.tool_parameter_description Callers expose the model-visible parameter description.
    pub description: String,
    // @behavior selvedge.model.domain.tool_parameter_required Callers expose whether the model-visible parameter is required.
    pub required: bool,
}

// @behavior selvedge.model.domain.tool_parameter_type Model dispatch exposes the supported scalar tool parameter types.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum ToolParameterType {
    String,
    Integer,
    Number,
    Boolean,
}

// @behavior selvedge.model.domain.reasoning_effort Model dispatch exposes supported reasoning effort levels.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum ReasoningEffort {
    Minimal,
    Low,
    Medium,
    High,
}

// @behavior selvedge.model.domain.conversation Model packages exchange ordered conversation items for runtime history.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Conversation {
    // @behavior selvedge.model.domain.conversation_items Callers receive conversation items in runtime history order.
    pub items: Vec<ConversationItem>,
}

// @behavior selvedge.model.domain.conversation_item Runtime history exposes messages, function calls, and function outputs as conversation items.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub enum ConversationItem {
    Message {
        role: MessageRole,
        text: String,
    },
    FunctionCall {
        function_call_id: FunctionCallId,
        tool_name: ToolName,
        arguments: Vec<ToolCallArgument>,
    },
    FunctionOutput {
        function_call_id: FunctionCallId,
        tool_name: ToolName,
        output_text: String,
        is_error: bool,
    },
}

// @behavior selvedge.model.domain.tool_call_argument Model packages exchange named tool-call arguments as structured values.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ToolCallArgument {
    // @behavior selvedge.model.domain.tool_call_argument_name Callers expose the tool parameter name attached to an argument.
    pub name: ToolParameterName,
    // @behavior selvedge.model.domain.tool_call_argument_value Callers expose the structured value attached to an argument.
    pub value: ToolArgumentValue,
}

// @behavior selvedge.model.domain.tool_argument_value Tool-call arguments expose string, integer, number, and boolean values.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub enum ToolArgumentValue {
    String(String),
    Integer(i64),
    Number(f64),
    Boolean(bool),
}

// @behavior selvedge.model.domain.structured_payload Model packages exchange JSON-like structured payload values.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub enum StructuredPayload {
    Object(BTreeMap<String, StructuredPayload>),
    Array(Vec<StructuredPayload>),
    String(String),
    Number(f64),
    Boolean(bool),
    Null,
}

// @behavior selvedge.model.domain.provider_profile Model dispatch receives provider, model, and optional generation limits for a model call.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ModelProviderProfile {
    // @behavior selvedge.model.domain.provider_profile_provider_name Callers expose the provider name selected for a model call.
    pub provider_name: String,
    // @behavior selvedge.model.domain.provider_profile_model_name Callers expose the provider model selected for a model call.
    pub model_name: String,
    // @behavior selvedge.model.domain.provider_profile_temperature Callers expose an optional generation temperature for a model call.
    pub temperature: Option<f32>,
    // @behavior selvedge.model.domain.provider_profile_max_output_tokens Callers expose an optional output token ceiling for a model call.
    pub max_output_tokens: Option<u32>,
}

// @behavior selvedge.model.domain.response_preference Model dispatch exposes supported response shape preferences.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum ResponsePreference {
    PlainTextOrToolCalls,
    PlainTextOnly,
    ToolCallsAllowed,
    StructuredOutput,
}

// @behavior selvedge.model.domain.model_reply Provider adapters return normalized model replies with content, tool calls, usage, and finish reason.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ModelReply {
    // @behavior selvedge.model.domain.model_reply_content Callers receive optional assistant text content from a normalized model reply.
    pub content: Option<String>,
    // @behavior selvedge.model.domain.model_reply_tool_calls Callers receive requested tool calls from a normalized model reply.
    pub tool_calls: Vec<ToolCallProposal>,
    // @behavior selvedge.model.domain.model_reply_usage Callers receive optional token usage from a normalized model reply.
    pub usage: Option<TokenUsage>,
    // @behavior selvedge.model.domain.model_reply_finish_reason Callers receive the provider completion reason from a normalized model reply.
    pub finish_reason: ModelFinishReason,
}

// @behavior selvedge.model.domain.tool_call_proposal Provider adapters expose each requested tool call with identifier, name, and arguments.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct ToolCallProposal {
    // @behavior selvedge.model.domain.tool_call_proposal_call_id Callers receive the provider tool-call identifier.
    pub call_id: String,
    // @behavior selvedge.model.domain.tool_call_proposal_tool_name Callers receive the provider requested tool name.
    pub tool_name: String,
    // @behavior selvedge.model.domain.tool_call_proposal_arguments Callers receive the provider requested tool arguments as structured payload.
    pub arguments: StructuredPayload,
}

// @behavior selvedge.model.domain.token_usage Provider adapters expose input and output token counts for a model reply.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct TokenUsage {
    // @behavior selvedge.model.domain.token_usage_input Callers receive the input token count for a model reply.
    pub input_tokens: u64,
    // @behavior selvedge.model.domain.token_usage_output Callers receive the output token count for a model reply.
    pub output_tokens: u64,
}

// @behavior selvedge.model.domain.finish_reason Provider adapters expose normalized model completion reasons.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub enum ModelFinishReason {
    Stop,
    Length,
    ToolCalls,
    ContentFilter,
    Unknown,
}

// @behavior selvedge.model.domain.validation_error Domain validation returns stable validation error categories.
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

// @constraint selvedge.model.domain.validation Domain validation returns typed errors for caller-visible invalid model-call data.
// @constraint selvedge.model.domain.validation.conversation Conversation path validation accepts paths with at least one message and returns EmptyConversationPath for empty paths.
pub fn validate_conversation_path(path: &ConversationPath) -> Result<(), ApiDomainValidationError> {
    if path.messages.is_empty() {
        return Err(ApiDomainValidationError::EmptyConversationPath);
    }

    Ok(())
}

// @constraint selvedge.model.domain.validation.tools Tool manifest validation accepts unique nonblank tool and parameter names within each manifest.
pub fn validate_tool_manifest(manifest: &ToolManifest) -> Result<(), ApiDomainValidationError> {
    let mut tool_names = BTreeSet::new();

    for tool in &manifest.tools {
        if tool.name.trim().is_empty() {
            // @constraint selvedge.model.domain.validation.tools.empty_tool_name Tool manifest validation returns EmptyToolName for blank tool names.
            return Err(ApiDomainValidationError::EmptyToolName);
        }

        if !tool_names.insert(tool.name.as_str()) {
            // @constraint selvedge.model.domain.validation.tools.duplicate_tool_name Tool manifest validation returns DuplicateToolName for repeated tool names.
            return Err(ApiDomainValidationError::DuplicateToolName);
        }

        let mut parameter_names = BTreeSet::new();

        for parameter in &tool.parameters {
            if parameter.name.trim().is_empty() {
                // @constraint selvedge.model.domain.validation.tools.empty_parameter_name Tool manifest validation returns EmptyToolParameterName for blank parameter names.
                return Err(ApiDomainValidationError::EmptyToolParameterName);
            }

            if !parameter_names.insert(parameter.name.as_str()) {
                // @constraint selvedge.model.domain.validation.tools.duplicate_parameter_name Tool manifest validation returns DuplicateToolParameterName for repeated parameter names within one tool.
                return Err(ApiDomainValidationError::DuplicateToolParameterName);
            }
        }
    }

    Ok(())
}

// @constraint selvedge.model.domain.validation.provider Provider profile validation accepts nonblank provider and model names.
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

// @constraint selvedge.model.domain.validation.reply Model reply validation accepts replies with nonblank text or named tool-call proposals.
pub fn validate_model_reply(reply: &ModelReply) -> Result<(), ApiDomainValidationError> {
    let has_content = reply
        .content
        .as_deref()
        .is_some_and(|content| !content.trim().is_empty());

    if !has_content && reply.tool_calls.is_empty() {
        // @constraint selvedge.model.domain.validation.reply.empty Model reply validation returns EmptyModelReply when text and tool calls are absent.
        return Err(ApiDomainValidationError::EmptyModelReply);
    }

    for tool_call in &reply.tool_calls {
        if tool_call.call_id.trim().is_empty() {
            // @constraint selvedge.model.domain.validation.reply.empty_tool_call_id Model reply validation returns EmptyToolCallId for blank tool-call identifiers.
            return Err(ApiDomainValidationError::EmptyToolCallId);
        }

        if tool_call.tool_name.trim().is_empty() {
            // @constraint selvedge.model.domain.validation.reply.empty_tool_call_name Model reply validation returns EmptyToolCallName for blank tool-call names.
            return Err(ApiDomainValidationError::EmptyToolCallName);
        }
    }

    Ok(())
}
