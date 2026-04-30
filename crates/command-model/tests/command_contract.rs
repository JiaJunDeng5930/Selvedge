use selvedge_command_model::{
    ApiCallCorrelation, ApiEffectId, ApiOutputEnvelope, BeginClientHydration, ClientCommandId,
    ClientEvent, ClientEventFrame, ClientFrame, ClientId, ClientSnapshot, ClientSnapshotFrame,
    ClientSubscription, DeliverySeq, DetailLevel, EventControlMessage, EventIngress,
    HistoryAppendedEvent, HistoryAppendedRawEvent, ModelCallDispatchRequest, ModelCallError,
    ModelCallErrorKind, ModelRunId, RouterIngressApiMessage, SnapshotTaskVersion, TaskId,
    TaskProjection, TaskProjectionStatus, TaskScope, validate_api_output_envelope,
    validate_dispatch_request,
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
            assert_eq!(begin.client_id, ClientId("client-1".to_owned()));
            assert_eq!(
                begin.client_command_id,
                ClientCommandId("attach-1".to_owned())
            );
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
            assert_eq!(event.task_id, TaskId("task-1".to_owned()));
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

    assert!(matches!(snapshot_frame, ClientFrame::Snapshot(_)));
    assert!(matches!(event_frame, ClientFrame::Event(_)));
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
