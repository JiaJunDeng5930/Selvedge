#![doc = include_str!("../README.md")]

use tokio::sync::mpsc;

use selvedge_domain_model::{
    ApiDomainValidationError, ConversationPath, ModelProviderProfile, ModelReply,
    ResponsePreference, ToolManifest, validate_conversation_path, validate_model_provider_profile,
    validate_model_reply, validate_tool_manifest,
};

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ApiEffectId(pub String);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct TaskId(pub String);

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct ModelRunId(pub String);

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ApiCallCorrelation {
    pub api_effect_id: ApiEffectId,
    pub task_id: TaskId,
    pub model_run_id: ModelRunId,
}

#[derive(Clone, Debug, PartialEq)]
pub struct ModelCallDispatchRequest {
    pub correlation: ApiCallCorrelation,
    pub provider: ModelProviderProfile,
    pub conversation: ConversationPath,
    pub tool_manifest: Option<ToolManifest>,
    pub response_preference: ResponsePreference,
}

#[derive(Clone, Debug, PartialEq)]
pub enum ApiOutputEnvelope {
    Success {
        correlation: ApiCallCorrelation,
        reply: ModelReply,
    },
    Failure {
        correlation: ApiCallCorrelation,
        error: ModelCallError,
    },
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModelCallError {
    pub kind: ModelCallErrorKind,
    pub message: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ModelCallErrorKind {
    Validation,
    ProviderRequest,
    ProviderNetwork,
    ProviderTimeout,
    ProviderResponse,
    Cancelled,
}

#[derive(Clone, Debug, PartialEq)]
pub enum RouterIngressApiMessage {
    ApiOutput(ApiOutputEnvelope),
}

pub type RouterIngressSender = mpsc::Sender<RouterIngressApiMessage>;

pub fn validate_dispatch_request(request: &ModelCallDispatchRequest) -> Result<(), ModelCallError> {
    validate_correlation(&request.correlation)?;

    validate_model_provider_profile(&request.provider)
        .map_err(|error| validation_error("provider", error))?;

    validate_conversation_path(&request.conversation)
        .map_err(|error| validation_error("conversation", error))?;

    if let Some(tool_manifest) = &request.tool_manifest {
        validate_tool_manifest(tool_manifest)
            .map_err(|error| validation_error("tool_manifest", error))?;
    }

    Ok(())
}

pub fn validate_api_output_envelope(envelope: &ApiOutputEnvelope) -> Result<(), ModelCallError> {
    match envelope {
        ApiOutputEnvelope::Success { correlation, reply } => {
            validate_correlation(correlation)?;
            validate_model_reply(reply).map_err(|error| validation_error("reply", error))?;
        }
        ApiOutputEnvelope::Failure { correlation, error } => {
            if error.kind != ModelCallErrorKind::Validation {
                validate_correlation(correlation)?;
            }
        }
    }

    Ok(())
}

fn validate_correlation(correlation: &ApiCallCorrelation) -> Result<(), ModelCallError> {
    if correlation.api_effect_id.0.trim().is_empty() {
        return Err(validation_message("api_effect_id must not be empty"));
    }

    if correlation.task_id.0.trim().is_empty() {
        return Err(validation_message("task_id must not be empty"));
    }

    if correlation.model_run_id.0.trim().is_empty() {
        return Err(validation_message("model_run_id must not be empty"));
    }

    Ok(())
}

fn validation_error(field: &str, error: ApiDomainValidationError) -> ModelCallError {
    validation_message(format!("{field} is invalid: {error:?}"))
}

fn validation_message(message: impl Into<String>) -> ModelCallError {
    ModelCallError {
        kind: ModelCallErrorKind::Validation,
        message: message.into(),
    }
}
