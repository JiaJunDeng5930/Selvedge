use selvedge_local_protocol::{
    AttachAccepted, AttachRejectReason, AttachRejected, AttachRequest, CommandOutcome,
    CommandRejectReason, CommandRequest, CommandResponse, LocalAttachStreamItem,
    LocalAttachStreamOrderError, LocalAttachStreamValidationState, LocalAttachStreamValidator,
    LocalClientCommandId, LocalClientEvent, LocalClientEventFrame, LocalClientFrame, LocalClientId,
    LocalClientNoticeFrame, LocalClientSnapshot, LocalClientSnapshotFrame, LocalClientSubscription,
    LocalDebugNoticeEvent, LocalDetailLevel, LocalHistoryNodeProjection,
    LocalHistoryNodeProjectionBody, LocalHttpProblemCode, LocalMessageRole,
    LocalModelCallStatusEvent, LocalModelCallStatusPhase, LocalNotice, LocalNoticeLevel,
    LocalProtocolValidationError, LocalReasoningEffort, LocalSnapshotTaskVersion, LocalStreamError,
    LocalStreamErrorReason, LocalTaskParentProjection, LocalTaskProjection,
    LocalTaskProjectionStatus, LocalTaskScope, LocalToolArgumentValue, LocalToolCallArgument,
    LocalToolExecutionStatusEvent, LocalToolExecutionStatusPhase, ProtocolVersion, ReadyRequest,
    ReadyResponse, ReadyState, current_protocol_version, http_problem, validate_attach_request,
    validate_attach_stream_item, validate_client_frame, validate_command_request,
    validate_ready_request, validate_snapshot, validate_subscription,
};
use serde_json::json;

#[test]
fn request_validation_enforces_protocol_version_and_required_client_fields() {
    assert_eq!(current_protocol_version(), ProtocolVersion(2));

    let ready = ReadyRequest {
        protocol_version: ProtocolVersion(3),
    };
    assert_eq!(
        validate_ready_request(&ready),
        Err(LocalProtocolValidationError::ProtocolVersionMismatch)
    );

    assert_eq!(
        LocalClientId::new(" "),
        Err(LocalProtocolValidationError::EmptyClientId)
    );
    assert_eq!(
        LocalClientCommandId::new(" "),
        Err(LocalProtocolValidationError::EmptyClientCommandId)
    );

    let request = CommandRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new("command-1").expect("valid command id"),
        command_name: " ".to_owned(),
        payload: json!({"message": "hello"}),
    };
    assert_eq!(
        validate_command_request(&request),
        Err(LocalProtocolValidationError::EmptyCommandName)
    );
}

#[test]
fn attach_validation_enforces_valid_subscription_filters() {
    let valid_subscription = LocalClientSubscription {
        task_scope: LocalTaskScope::TaskIds(vec!["task-1".to_owned(), "task-2".to_owned()]),
        detail_level: LocalDetailLevel::Verbose,
        include_model_call_status: true,
        include_tool_execution_status: true,
        include_debug_notices: false,
    };
    validate_subscription(&valid_subscription).expect("valid subscription");

    let empty_task = LocalClientSubscription {
        task_scope: LocalTaskScope::TaskIds(vec!["task-1".to_owned(), " ".to_owned()]),
        ..valid_subscription.clone()
    };
    assert_eq!(
        validate_subscription(&empty_task),
        Err(LocalProtocolValidationError::EmptyTaskId)
    );

    let duplicate_task = LocalClientSubscription {
        task_scope: LocalTaskScope::TaskIds(vec!["task-1".to_owned(), "task-1".to_owned()]),
        ..valid_subscription.clone()
    };
    assert_eq!(
        validate_subscription(&duplicate_task),
        Err(LocalProtocolValidationError::DuplicateTaskId)
    );

    let attach = AttachRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new("attach-1").expect("valid command id"),
        subscription: valid_subscription,
    };
    validate_attach_request(&attach).expect("valid attach request");
}

#[test]
fn frame_validation_enforces_delivery_sequence_snapshot_and_notice_contracts() {
    let snapshot = valid_snapshot();
    validate_snapshot(&snapshot).expect("valid snapshot");

    let frame = LocalClientFrame::Snapshot(LocalClientSnapshotFrame {
        delivery_seq: 1,
        client_command_id: LocalClientCommandId::new("attach-1").expect("valid command id"),
        snapshot: snapshot.clone(),
    });
    validate_client_frame(&frame).expect("valid snapshot frame");

    let zero_seq = LocalClientFrame::Snapshot(LocalClientSnapshotFrame {
        delivery_seq: 0,
        client_command_id: LocalClientCommandId::new("attach-1").expect("valid command id"),
        snapshot: snapshot.clone(),
    });
    assert_eq!(
        validate_client_frame(&zero_seq),
        Err(LocalProtocolValidationError::InvalidDeliverySeq)
    );

    let duplicate_version = LocalClientSnapshot {
        task_versions: vec![
            LocalSnapshotTaskVersion {
                task_id: "task-1".to_owned(),
                state_version: 1,
            },
            LocalSnapshotTaskVersion {
                task_id: "task-1".to_owned(),
                state_version: 2,
            },
        ],
        ..snapshot.clone()
    };
    assert_eq!(
        validate_snapshot(&duplicate_version),
        Err(LocalProtocolValidationError::DuplicateSnapshotTaskVersion)
    );

    let invalid_task = LocalClientSnapshot {
        tasks: vec![LocalTaskProjection {
            cursor_node_id: 0,
            ..valid_task_projection()
        }],
        ..snapshot.clone()
    };
    assert_eq!(
        validate_snapshot(&invalid_task),
        Err(LocalProtocolValidationError::InvalidHistoryNodeId)
    );

    let invalid_history_parent = LocalClientSnapshot {
        history_nodes: vec![LocalHistoryNodeProjection {
            parent_node_id: Some(0),
            ..valid_history_message()
        }],
        ..snapshot.clone()
    };
    assert_eq!(
        validate_snapshot(&invalid_history_parent),
        Err(LocalProtocolValidationError::InvalidParentHistoryNodeId)
    );

    let empty_parent_edge_task = LocalClientSnapshot {
        task_parent_edges: vec![LocalTaskParentProjection {
            parent_task_id: " ".to_owned(),
            child_task_id: "task-2".to_owned(),
        }],
        ..snapshot.clone()
    };
    assert_eq!(
        validate_snapshot(&empty_parent_edge_task),
        Err(LocalProtocolValidationError::EmptyTaskId)
    );

    let empty_tool_argument = LocalClientSnapshot {
        history_nodes: vec![LocalHistoryNodeProjection {
            body: LocalHistoryNodeProjectionBody::FunctionCall {
                function_call_id: "call-1".to_owned(),
                tool_name: "tool".to_owned(),
                arguments: vec![LocalToolCallArgument {
                    name: " ".to_owned(),
                    value: LocalToolArgumentValue::Boolean(true),
                }],
            },
            ..valid_history_message()
        }],
        ..snapshot.clone()
    };
    assert_eq!(
        validate_snapshot(&empty_tool_argument),
        Err(LocalProtocolValidationError::EmptyToolArgumentName)
    );

    let invalid_function_output_ref = LocalClientSnapshot {
        history_nodes: vec![LocalHistoryNodeProjection {
            body: LocalHistoryNodeProjectionBody::FunctionOutput {
                function_call_node_id: 0,
                function_call_id: "call-1".to_owned(),
                tool_name: "tool".to_owned(),
                output_text: "done".to_owned(),
                is_error: false,
            },
            ..valid_history_message()
        }],
        ..snapshot
    };
    assert_eq!(
        validate_snapshot(&invalid_function_output_ref),
        Err(LocalProtocolValidationError::InvalidHistoryNodeId)
    );

    let empty_notice = LocalClientFrame::Notice(LocalClientNoticeFrame {
        delivery_seq: 1,
        client_command_id: LocalClientCommandId::new("attach-1").expect("valid command id"),
        notice: LocalNotice {
            level: LocalNoticeLevel::Warning,
            message_text: " ".to_owned(),
        },
    });
    assert_eq!(
        validate_client_frame(&empty_notice),
        Err(LocalProtocolValidationError::EmptyNoticeText)
    );

    let invalid_tool_status = LocalClientFrame::Event(LocalClientEventFrame {
        delivery_seq: 1,
        event: LocalClientEvent::ToolExecutionStatus(LocalToolExecutionStatusEvent {
            task_id: "task-1".to_owned(),
            tool_execution_run_id: "tool-run-1".to_owned(),
            function_call_node_id: 0,
            tool_name: "tool".to_owned(),
            phase: LocalToolExecutionStatusPhase::Failed,
        }),
    });
    assert_eq!(
        validate_client_frame(&invalid_tool_status),
        Err(LocalProtocolValidationError::InvalidHistoryNodeId)
    );
}

#[test]
fn protocol_messages_round_trip_through_json() {
    let ready = ReadyResponse {
        protocol_version: current_protocol_version(),
        state: ReadyState::Ready,
    };
    let ready_json = serde_json::to_string(&ready).expect("serialize ready response");
    assert_eq!(
        serde_json::from_str::<ReadyResponse>(&ready_json).expect("deserialize ready response"),
        ready
    );

    let command = CommandResponse {
        protocol_version: current_protocol_version(),
        client_command_id: LocalClientCommandId::new("command-1").expect("valid command id"),
        outcome: CommandOutcome::Rejected(CommandRejectReason::ServerNotReady),
    };
    let command_json = serde_json::to_string(&command).expect("serialize command response");
    assert_eq!(
        serde_json::from_str::<CommandResponse>(&command_json)
            .expect("deserialize command response"),
        command
    );

    let accepted = AttachAccepted {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new("attach-1").expect("valid command id"),
    };
    let accepted_json = serde_json::to_string(&accepted).expect("serialize attach accepted");
    assert_eq!(
        serde_json::from_str::<AttachAccepted>(&accepted_json).expect("deserialize accepted"),
        accepted
    );

    let rejected = AttachRejected {
        protocol_version: current_protocol_version(),
        client_command_id: LocalClientCommandId::new("attach-2").expect("valid command id"),
        reason: AttachRejectReason::ProtocolVersionMismatch,
    };
    let rejected_json = serde_json::to_string(&rejected).expect("serialize attach rejected");
    assert_eq!(
        serde_json::from_str::<AttachRejected>(&rejected_json).expect("deserialize rejected"),
        rejected
    );

    let event_frame = LocalClientFrame::Event(LocalClientEventFrame {
        delivery_seq: 2,
        event: LocalClientEvent::ToolExecutionStatus(LocalToolExecutionStatusEvent {
            task_id: "task-1".to_owned(),
            tool_execution_run_id: "tool-run-1".to_owned(),
            function_call_node_id: 3,
            tool_name: "tool".to_owned(),
            phase: LocalToolExecutionStatusPhase::Completed,
        }),
    });
    let event_json = serde_json::to_string(&event_frame).expect("serialize event frame");
    assert_eq!(
        serde_json::from_str::<LocalClientFrame>(&event_json).expect("deserialize event frame"),
        event_frame
    );

    let model_event = LocalClientEvent::ModelCallStatus(LocalModelCallStatusEvent {
        task_id: "task-1".to_owned(),
        model_call_id: "model-call-1".to_owned(),
        phase: LocalModelCallStatusPhase::Requested,
    });
    assert!(matches!(
        model_event,
        LocalClientEvent::ModelCallStatus(LocalModelCallStatusEvent {
            phase: LocalModelCallStatusPhase::Requested,
            ..
        })
    ));

    let debug_event = LocalClientEvent::DebugNotice(LocalDebugNoticeEvent {
        task_id: Some("task-1".to_owned()),
        message_text: "debug".to_owned(),
    });
    assert!(matches!(debug_event, LocalClientEvent::DebugNotice(_)));

    let parent_edge = LocalTaskParentProjection {
        parent_task_id: "parent".to_owned(),
        child_task_id: "child".to_owned(),
    };
    assert_eq!(parent_edge.child_task_id, "child");

    let error_json = serde_json::to_string(&LocalProtocolValidationError::EmptyTaskId)
        .expect("serialize validation error");
    assert_eq!(
        serde_json::from_str::<LocalProtocolValidationError>(&error_json)
            .expect("deserialize validation error"),
        LocalProtocolValidationError::EmptyTaskId
    );
}

#[test]
fn http_problem_uses_current_protocol_version_and_payload_text() {
    let problem = http_problem(LocalHttpProblemCode::MalformedJson, "invalid json");

    assert_eq!(problem.protocol_version, current_protocol_version());
    assert_eq!(problem.code, LocalHttpProblemCode::MalformedJson);
    assert_eq!(problem.message_text, "invalid json");
}

#[test]
fn attach_stream_item_validation_checks_internal_payload_only() {
    let frame_item =
        LocalAttachStreamItem::Frame(LocalClientFrame::Snapshot(LocalClientSnapshotFrame {
            delivery_seq: 1,
            client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            snapshot: valid_snapshot(),
        }));
    validate_attach_stream_item(&frame_item).expect("valid frame item");

    let invalid_frame =
        LocalAttachStreamItem::Frame(LocalClientFrame::Notice(LocalClientNoticeFrame {
            delivery_seq: 0,
            client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            notice: LocalNotice {
                level: LocalNoticeLevel::Error,
                message_text: "bad".to_owned(),
            },
        }));
    assert_eq!(
        validate_attach_stream_item(&invalid_frame),
        Err(LocalProtocolValidationError::InvalidDeliverySeq)
    );

    let stream_error = LocalAttachStreamItem::StreamError(LocalStreamError {
        protocol_version: current_protocol_version(),
        client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
        reason: LocalStreamErrorReason::StreamClosed,
        message_text: "closed".to_owned(),
    });
    validate_attach_stream_item(&stream_error).expect("valid stream error");
}

#[test]
fn attach_stream_validator_enforces_accepted_first_and_terminal_error_order() {
    let mut validator = LocalAttachStreamValidator::new();
    assert_eq!(
        validator.state(),
        LocalAttachStreamValidationState::WaitingAccepted
    );

    assert_eq!(
        validator.validate_next(&LocalAttachStreamItem::Frame(LocalClientFrame::Notice(
            LocalClientNoticeFrame {
                delivery_seq: 1,
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
                notice: LocalNotice {
                    level: LocalNoticeLevel::Info,
                    message_text: "hello".to_owned(),
                },
            },
        ))),
        Err(LocalAttachStreamOrderError::FrameBeforeAccepted)
    );
    assert_eq!(
        validator.state(),
        LocalAttachStreamValidationState::WaitingAccepted
    );

    validator
        .validate_next(&LocalAttachStreamItem::Accepted(valid_attach_accepted()))
        .expect("accepted first");
    assert_eq!(
        validator.state(),
        LocalAttachStreamValidationState::Streaming
    );

    assert_eq!(
        validator.validate_next(&LocalAttachStreamItem::Accepted(valid_attach_accepted())),
        Err(LocalAttachStreamOrderError::DuplicateAccepted)
    );

    validator
        .validate_next(&LocalAttachStreamItem::Frame(LocalClientFrame::Notice(
            LocalClientNoticeFrame {
                delivery_seq: 1,
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
                notice: LocalNotice {
                    level: LocalNoticeLevel::Info,
                    message_text: "hello".to_owned(),
                },
            },
        )))
        .expect("frame after accepted");

    validator
        .validate_next(&LocalAttachStreamItem::StreamError(LocalStreamError {
            protocol_version: current_protocol_version(),
            client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            reason: LocalStreamErrorReason::ServerShuttingDown,
            message_text: "shutdown".to_owned(),
        }))
        .expect("stream error ends stream");
    assert_eq!(validator.state(), LocalAttachStreamValidationState::Ended);

    assert_eq!(
        validator.validate_next(&LocalAttachStreamItem::Frame(LocalClientFrame::Notice(
            LocalClientNoticeFrame {
                delivery_seq: 2,
                client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
                notice: LocalNotice {
                    level: LocalNoticeLevel::Info,
                    message_text: "late".to_owned(),
                },
            },
        ))),
        Err(LocalAttachStreamOrderError::ItemAfterEnded)
    );
}

#[test]
fn attach_stream_validator_rejects_stream_error_as_first_item() {
    let mut validator = LocalAttachStreamValidator::new();

    assert_eq!(
        validator.validate_next(&LocalAttachStreamItem::StreamError(LocalStreamError {
            protocol_version: current_protocol_version(),
            client_command_id: LocalClientCommandId::new("attach-1").expect("command id"),
            reason: LocalStreamErrorReason::InternalFailure,
            message_text: "boom".to_owned(),
        })),
        Err(LocalAttachStreamOrderError::ExpectedAcceptedFirst)
    );
    assert_eq!(
        validator.state(),
        LocalAttachStreamValidationState::WaitingAccepted
    );
}

fn valid_snapshot() -> LocalClientSnapshot {
    LocalClientSnapshot {
        generated_at: 100,
        tasks: vec![valid_task_projection()],
        task_parent_edges: Vec::new(),
        history_nodes: vec![valid_history_message()],
        task_versions: vec![LocalSnapshotTaskVersion {
            task_id: "task-1".to_owned(),
            state_version: 1,
        }],
    }
}

fn valid_attach_accepted() -> AttachAccepted {
    AttachAccepted {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new("attach-1").expect("valid command id"),
    }
}

fn valid_task_projection() -> LocalTaskProjection {
    LocalTaskProjection {
        task_id: "task-1".to_owned(),
        status: LocalTaskProjectionStatus::Active,
        cursor_node_id: 1,
        model_profile_key: "default".to_owned(),
        reasoning_effort: LocalReasoningEffort::Medium,
        state_version: 1,
        created_at: 10,
        updated_at: 20,
    }
}

fn valid_history_message() -> LocalHistoryNodeProjection {
    LocalHistoryNodeProjection {
        node_id: 1,
        parent_node_id: None,
        created_at: 20,
        body: LocalHistoryNodeProjectionBody::Message {
            role: LocalMessageRole::User,
            text: String::new(),
        },
    }
}
