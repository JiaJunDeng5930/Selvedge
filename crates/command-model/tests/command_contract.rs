use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, ClientCommandId, ClientId,
    ClientSessionIdentity, ModelCallDispatchRequest, ModelCallError, ModelCallErrorKind,
    ModelRunId, RouterCommand, RouterCommandValidationError, TaskCommandError, TaskId,
    send_user_input_response_channel, task_status_change_response_channel,
    validate_api_output_envelope, validate_dispatch_request, validate_router_command,
};
use selvedge_domain_model::{
    CallableTools, Conversation, ConversationMessage, MessageRole, ModelFinishReason,
    ModelProfileKey, ModelProviderProfile, ModelReply, ReasoningEffort, ResponsePreference,
    TaskModelConfig, ToolManifest, ToolName, ToolSpec,
};
use std::sync::Arc;

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
fn dispatch_request_rejects_callable_tools_absent_from_manifest() {
    let mut request = valid_dispatch_request();
    request.tool_manifest = Some(ToolManifest {
        tools: vec![ToolSpec {
            name: "search".to_owned(),
            description: "Search".to_owned(),
            input_schema: serde_json::Map::new(),
        }],
    });
    request.callable_tools = CallableTools::Only(vec![ToolName("bash".to_owned())]);

    let error = validate_dispatch_request(&request).expect_err("unknown callable tool");
    assert_eq!(error.kind, ModelCallErrorKind::Validation);
    assert!(error.message.contains("absent from tool_manifest"));
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
fn router_command_validation_rejects_invalid_session_and_task_payloads() {
    for (client_id, command_id, error) in [
        (" ", "attach", RouterCommandValidationError::MissingClientId),
        (
            "client",
            " ",
            RouterCommandValidationError::MissingClientCommandId,
        ),
    ] {
        let command = RouterCommand::DetachClient {
            session: ClientSessionIdentity::new(
                ClientId(client_id.to_owned()),
                ClientCommandId(command_id.to_owned()),
            ),
        };
        assert_eq!(validate_router_command(&command), Err(error));
    }
    assert_eq!(
        validate_router_command(&RouterCommand::EnsureTaskRuntime {
            task_id: TaskId(" ".to_owned())
        }),
        Err(RouterCommandValidationError::EmptyTaskId)
    );
    assert_eq!(
        validate_router_command(&RouterCommand::SendUserInput {
            task_id: TaskId("task-1".to_owned()),
            message_text: " ".to_owned(),
            responder: send_user_input_response_channel().0,
        }),
        Err(RouterCommandValidationError::EmptyMessageText)
    );
}

#[test]
fn repeated_attach_correlation_allocates_distinct_session_ownership() {
    let first = ClientSessionIdentity::new(
        ClientId("client".to_owned()),
        ClientCommandId("attach".to_owned()),
    );
    let second =
        ClientSessionIdentity::new(first.client_id().clone(), first.attach_command_id().clone());
    assert_ne!(first.session_id(), second.session_id());
    assert_eq!(first.clone().session_id(), first.session_id());
}

#[test]
fn dropped_task_command_responders_settle_as_runtime_unavailable() {
    let (input_responder, mut input_response) = send_user_input_response_channel();
    drop(input_responder);
    assert_eq!(
        input_response.try_recv().expect("input response"),
        Err(TaskCommandError::RuntimeUnavailable)
    );

    let (archive_responder, mut archive_response) = task_status_change_response_channel();
    drop(archive_responder);
    assert_eq!(
        archive_response.try_recv().expect("archive response"),
        Err(TaskCommandError::RuntimeUnavailable)
    );
}

fn valid_dispatch_request() -> ModelCallDispatchRequest {
    ModelCallDispatchRequest {
        correlation: valid_correlation(),
        model_config: Arc::new(
            TaskModelConfig::new(
                ModelProfileKey("default".to_owned()),
                ReasoningEffort::Medium,
            )
            .expect("model config"),
        ),
        provider: ModelProviderProfile {
            provider_name: "provider".to_owned(),
            model_name: "model".to_owned(),
            temperature: None,
            max_output_tokens: None,
        },
        conversation: Conversation {
            messages: vec![ConversationMessage::text(MessageRole::User, "hello", None)],
        },
        tool_manifest: None,
        callable_tools: CallableTools::All,
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

#[test]
fn command_completion_keeps_lease_until_all_result_owners_release_it() {
    use selvedge_command_model::ToolExecutionCompletion;
    use selvedge_domain_model::{
        CommandEnvironmentCommit, CommandEnvironmentId, CommandEnvironmentMode,
        CommandInvocationId, HistoryNodeId,
    };
    let mutex = Arc::new(tokio::sync::Mutex::new(()));
    let lease = mutex.clone().try_lock_owned().expect("initial lease");
    let prepared = ToolExecutionCompletion::command(
        CommandEnvironmentCommit {
            environment_id: CommandEnvironmentId("env".into()),
            invocation: CommandInvocationId {
                task_id: TaskId("task".into()),
                function_call_node_id: HistoryNodeId(1),
            },
            expected_revision: 0,
            checkpoint: vec![1],
            base_checkpoint: vec![0],
            new_child_environment_mode: CommandEnvironmentMode::Shared,
        },
        lease,
    );
    let retained = prepared.clone();
    assert_eq!(prepared, retained);
    drop(prepared);
    assert!(mutex.clone().try_lock_owned().is_err());
    drop(retained);
    assert!(mutex.try_lock_owned().is_ok());
}
