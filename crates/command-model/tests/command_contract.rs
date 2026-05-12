use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, BeginClientHydration, ClientCommandId,
    ClientEvent, ClientEventFrame, ClientFrame, ClientId, ClientSnapshot, ClientSnapshotFrame,
    ClientSubscription, CreatedRuntimeKind, DeliverySeq, DetailLevel, EventControlMessage,
    EventIngress, FactoryEffectId, FactoryFailure, FactoryFailureKind, FactoryOutput,
    FactoryOutputEnvelope, FactoryScanOutput, FactorySkipReason, FactorySkippedTask,
    FactoryTaskFailure, HistoryAppendedEvent, HistoryAppendedRawEvent, ModelCallDispatchRequest,
    ModelCallError, ModelCallErrorKind, ModelRunId, RouterCommand, RouterCommandEnvelope,
    RouterCommandValidationError, RouterIngressApiMessage, RouterIngressMessage,
    SnapshotTaskVersion, TaskId, TaskProjection, TaskProjectionStatus, TaskRuntimeControl,
    TaskRuntimeCreated, TaskScope, validate_api_output_envelope, validate_dispatch_request,
    validate_router_command,
};
use selvedge_domain_model::{
    ConversationMessage, ConversationPath, HistoryNodeId, MessageContent, MessageRole,
    ModelFinishReason, ModelProfileKey, ModelProviderProfile, ModelReply, ReasoningEffort,
    ResponsePreference, UnixTs,
};

#[test]
fn dispatch_request_requires_complete_correlation_provider_and_conversation() {
    let mut request = valid_dispatch_request();
    request.correlation.api_effect_id = ApiEffectId(" ".to_owned());

    let error = validate_dispatch_request(&request).expect_err("empty api effect id");
    // @verifies selvedge.task
    assert_eq!(error.kind, ModelCallErrorKind::Validation);
    // @verifies selvedge.task
    assert!(error.message.contains("api_effect_id"));

    let mut request = valid_dispatch_request();
    request.provider.provider_name.clear();

    let error = validate_dispatch_request(&request).expect_err("empty provider name");
    // @verifies selvedge.task
    assert_eq!(error.kind, ModelCallErrorKind::Validation);
    // @verifies selvedge.task
    assert!(error.message.contains("provider"));

    let mut request = valid_dispatch_request();
    request.conversation.messages.clear();

    let error = validate_dispatch_request(&request).expect_err("empty conversation");
    // @verifies selvedge.task
    assert_eq!(error.kind, ModelCallErrorKind::Validation);
    // @verifies selvedge.task
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
            // @verifies selvedge.task
            assert_eq!(error.kind, ModelCallErrorKind::Cancelled);
        }
        _ => panic!("unexpected message"),
    }
}

#[test]
fn event_ingress_and_client_frames_expose_router_events_contract() {
    let (outbound, _rx) = tokio::sync::mpsc::channel(4);
    let task = task_projection("task-1", 7);

    let ingress = EventIngress::Control(EventControlMessage::BeginClientHydration(
        BeginClientHydration {
            client_id: ClientId("client-1".to_owned()),
            client_command_id: ClientCommandId("attach-1".to_owned()),
            outbound,
            subscription: ClientSubscription {
                task_scope: TaskScope::AllTasks,
                detail_level: DetailLevel::Verbose,
                include_model_call_status: true,
                include_tool_execution_status: true,
                include_debug_notices: true,
            },
        },
    ));

    match ingress {
        EventIngress::Control(EventControlMessage::BeginClientHydration(begin)) => {
            // @verifies selvedge.task
            assert_eq!(begin.client_id, ClientId("client-1".to_owned()));
            // @verifies selvedge.task
            assert_eq!(
                begin.client_command_id,
                ClientCommandId("attach-1".to_owned())
            );
            // @verifies selvedge.task
            assert_eq!(begin.subscription.detail_level, DetailLevel::Verbose);
        }
        _ => panic!("unexpected event ingress"),
    }

    let raw = EventIngress::Raw(selvedge_command_model::RawEvent::HistoryAppended(
        HistoryAppendedRawEvent {
            task_id: TaskId("task-1".to_owned()),
            task_state_version: 8,
            appended_nodes: Vec::new(),
        },
    ));

    match raw {
        EventIngress::Raw(selvedge_command_model::RawEvent::HistoryAppended(event)) => {
            // @verifies selvedge.task
            assert_eq!(event.task_id, TaskId("task-1".to_owned()));
            // @verifies selvedge.task
            assert_eq!(event.task_state_version, 8);
        }
        _ => panic!("unexpected raw event"),
    }

    let snapshot_frame = ClientFrame::Snapshot(ClientSnapshotFrame {
        delivery_seq: DeliverySeq(1),
        client_command_id: ClientCommandId("attach-1".to_owned()),
        snapshot: ClientSnapshot {
            generated_at: UnixTs(100),
            tasks: vec![task.clone()],
            task_parent_edges: Vec::new(),
            history_nodes: Vec::new(),
            task_versions: vec![SnapshotTaskVersion {
                task_id: task.task_id.clone(),
                state_version: task.state_version,
            }],
        },
    });

    let event_frame = ClientFrame::Event(ClientEventFrame {
        delivery_seq: DeliverySeq(2),
        event: ClientEvent::HistoryAppended(HistoryAppendedEvent {
            task_id: TaskId("task-1".to_owned()),
            task_state_version: 8,
            appended_nodes: Vec::new(),
        }),
    });

    // @verifies selvedge.task
    assert!(matches!(snapshot_frame, ClientFrame::Snapshot(_)));
    // @verifies selvedge.task
    assert!(matches!(event_frame, ClientFrame::Event(_)));
}

#[test]
fn factory_output_envelope_exposes_runtime_created_scan_and_failure_contract() {
    let (task_runtime_tx, _task_runtime_rx) = tokio::sync::mpsc::channel(4);

    let runtime_created = TaskRuntimeCreated {
        task_id: TaskId("task-1".to_owned()),
        task_runtime_tx,
        task_runtime_control: TaskRuntimeControl::new(),
        created_runtime_kind: CreatedRuntimeKind::ExistingTaskRuntime,
    };
    let created = FactoryOutputEnvelope {
        effect_id: FactoryEffectId("factory-1".to_owned()),
        output: FactoryOutput::RuntimeCreated(runtime_created),
    };

    match created.output {
        FactoryOutput::RuntimeCreated(created) => {
            // @verifies selvedge.task
            assert_eq!(created.task_id, TaskId("task-1".to_owned()));
            // @verifies selvedge.task
            assert!(matches!(
                created.created_runtime_kind,
                CreatedRuntimeKind::ExistingTaskRuntime
            ));
        }
        _ => panic!("unexpected factory output"),
    }

    let scan = FactoryOutput::ScanFinished(FactoryScanOutput {
        created: Vec::new(),
        skipped: vec![FactorySkippedTask {
            task_id: TaskId("task-live".to_owned()),
            reason: FactorySkipReason::RuntimeAlreadyLive,
        }],
        failed: vec![FactoryTaskFailure {
            task_id: TaskId("task-failed".to_owned()),
            kind: FactoryFailureKind::CoreSpawnFailed,
            message: "spawn failed".to_owned(),
        }],
    });

    match scan {
        FactoryOutput::ScanFinished(scan) => {
            // @verifies selvedge.task
            assert_eq!(scan.skipped[0].task_id, TaskId("task-live".to_owned()));
            // @verifies selvedge.task
            assert!(matches!(
                scan.skipped[0].reason,
                FactorySkipReason::RuntimeAlreadyLive
            ));
            // @verifies selvedge.task
            assert_eq!(scan.failed[0].kind, FactoryFailureKind::CoreSpawnFailed);
        }
        _ => panic!("unexpected factory output"),
    }

    let failed = FactoryOutput::Failed(FactoryFailure {
        task_id: Some(TaskId("task-archived".to_owned())),
        kind: FactoryFailureKind::TaskArchived,
        message: "task is archived".to_owned(),
    });

    match failed {
        FactoryOutput::Failed(failure) => {
            // @verifies selvedge.task
            assert_eq!(failure.task_id, Some(TaskId("task-archived".to_owned())));
            // @verifies selvedge.task
            assert_eq!(failure.kind, FactoryFailureKind::TaskArchived);

            let duplicate = FactoryFailure {
                task_id: Some(TaskId("task-live".to_owned())),
                kind: FactoryFailureKind::RuntimeAlreadyLive,
                message: "task runtime is already live".to_owned(),
            };
            // @verifies selvedge.task
            assert_eq!(duplicate.kind, FactoryFailureKind::RuntimeAlreadyLive);
        }
        _ => panic!("unexpected factory output"),
    }
}

#[test]
fn router_ingress_exposes_factory_output_and_runtime_inventory_query() {
    let command = RouterIngressMessage::Command(RouterCommandEnvelope {
        client_id: None,
        client_command_id: None,
        command: RouterCommand::EnsureMissingTaskRuntimes,
    });
    // @verifies selvedge.task
    assert!(matches!(command, RouterIngressMessage::Command(_)));

    let stop = RouterIngressMessage::StopRouter;
    // @verifies selvedge.task
    assert!(matches!(stop, RouterIngressMessage::StopRouter));
}

#[test]
fn router_command_validation_enforces_envelope_and_task_payload_contract() {
    let (outbound, _outbound_rx) = tokio::sync::mpsc::channel(4);
    let subscription = ClientSubscription {
        task_scope: TaskScope::AllTasks,
        detail_level: DetailLevel::Verbose,
        include_model_call_status: true,
        include_tool_execution_status: true,
        include_debug_notices: true,
    };
    let (admission_tx, _admission_rx) = tokio::sync::oneshot::channel();

    let attach = RouterCommandEnvelope {
        client_id: Some(ClientId("client-1".to_owned())),
        client_command_id: Some(ClientCommandId("attach-1".to_owned())),
        command: RouterCommand::AttachClient {
            client_id: ClientId("client-1".to_owned()),
            client_command_id: ClientCommandId("attach-1".to_owned()),
            outbound,
            subscription,
            admission_tx,
        },
    };
    validate_router_command(&attach).expect("valid attach command");

    let missing_client_id = RouterCommandEnvelope {
        client_id: None,
        client_command_id: Some(ClientCommandId("detach-1".to_owned())),
        command: RouterCommand::DetachClient {
            client_id: ClientId("client-1".to_owned()),
            client_command_id: ClientCommandId("detach-1".to_owned()),
        },
    };
    // @verifies selvedge.task
    assert_eq!(
        validate_router_command(&missing_client_id),
        Err(RouterCommandValidationError::MissingClientId)
    );

    let mismatched_client_id = RouterCommandEnvelope {
        client_id: Some(ClientId("client-1".to_owned())),
        client_command_id: Some(ClientCommandId("detach-1".to_owned())),
        command: RouterCommand::DetachClient {
            client_id: ClientId("client-2".to_owned()),
            client_command_id: ClientCommandId("detach-1".to_owned()),
        },
    };
    // @verifies selvedge.task
    assert_eq!(
        validate_router_command(&mismatched_client_id),
        Err(RouterCommandValidationError::MismatchedClientId)
    );

    let mismatched_client_command_id = RouterCommandEnvelope {
        client_id: Some(ClientId("client-1".to_owned())),
        client_command_id: Some(ClientCommandId("detach-1".to_owned())),
        command: RouterCommand::DetachClient {
            client_id: ClientId("client-1".to_owned()),
            client_command_id: ClientCommandId("detach-2".to_owned()),
        },
    };
    // @verifies selvedge.task
    assert_eq!(
        validate_router_command(&mismatched_client_command_id),
        Err(RouterCommandValidationError::MismatchedClientCommandId)
    );

    let empty_task_id = RouterCommandEnvelope {
        client_id: None,
        client_command_id: None,
        command: RouterCommand::EnsureTaskRuntime {
            task_id: TaskId(" ".to_owned()),
        },
    };
    // @verifies selvedge.task
    assert_eq!(
        validate_router_command(&empty_task_id),
        Err(RouterCommandValidationError::EmptyTaskId)
    );

    let empty_message = RouterCommandEnvelope {
        client_id: None,
        client_command_id: None,
        command: RouterCommand::SendUserInput {
            task_id: TaskId("task-1".to_owned()),
            message_text: " ".to_owned(),
        },
    };
    // @verifies selvedge.task
    assert_eq!(
        validate_router_command(&empty_message),
        Err(RouterCommandValidationError::EmptyMessageText)
    );
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

fn task_projection(task_id: &str, state_version: u64) -> TaskProjection {
    TaskProjection {
        task_id: TaskId(task_id.to_owned()),
        status: TaskProjectionStatus::Active,
        cursor_node_id: HistoryNodeId(1),
        model_profile_key: ModelProfileKey("default".to_owned()),
        reasoning_effort: ReasoningEffort::Medium,
        state_version,
        created_at: UnixTs(10),
        updated_at: UnixTs(20),
    }
}
