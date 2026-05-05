use std::sync::Arc;

use selvedge_local_protocol::{
    AttachRequest, CommandOutcome, CommandRequest, CommandResponse, LocalClientCommandId,
    LocalClientId, LocalClientSubscription, LocalDetailLevel, LocalTaskScope, ReadyRequest,
    ReadyResponse, ReadyState, current_protocol_version,
};
use selvedge_web::{
    AttachRejectedOrBridgeError, WebAttachFuture, WebBridge, WebBridgeFuture, WebExitStatus,
    WebLocalhostBind, WebLocalhostHost, WebRuntimeState, WebStartArgs, WebStartError,
    spawn_web_surface,
};

#[tokio::test]
async fn spawn_web_surface_exposes_control_handle_and_stop_status() {
    let handle = spawn_web_surface(WebStartArgs {
        bind: loopback_bind(),
        bridge: Arc::new(StaticBridge),
    })
    .expect("valid web start args");

    assert_eq!(handle.control.state().await, WebRuntimeState::Listening);

    handle.control.stop().await;

    assert_eq!(
        handle.join_handle.await.expect("join web task"),
        WebExitStatus::Stopped
    );
}

#[test]
fn spawn_web_surface_rejects_zero_port() {
    let result = spawn_web_surface(WebStartArgs {
        bind: WebLocalhostBind {
            host: WebLocalhostHost::Ipv4Loopback,
            port: 0,
        },
        bridge: Arc::new(StaticBridge),
    });

    assert!(matches!(result, Err(WebStartError::InvalidBindTarget)));
}

#[test]
fn web_bridge_trait_exposes_ready_command_and_attach_futures() {
    let bridge = StaticBridge;
    let ready: WebBridgeFuture<ReadyResponse> = bridge.ready(ReadyRequest {
        protocol_version: current_protocol_version(),
    });
    let command: WebBridgeFuture<CommandResponse> = bridge.submit_command(valid_command_request());
    let attach: WebAttachFuture = bridge.attach(valid_attach_request());

    drop((ready, command, attach));
}

struct StaticBridge;

impl WebBridge for StaticBridge {
    fn ready(&self, _request: ReadyRequest) -> WebBridgeFuture<ReadyResponse> {
        Box::pin(async {
            Ok(ReadyResponse {
                protocol_version: current_protocol_version(),
                state: ReadyState::Ready,
            })
        })
    }

    fn submit_command(&self, request: CommandRequest) -> WebBridgeFuture<CommandResponse> {
        Box::pin(async move {
            Ok(CommandResponse {
                protocol_version: current_protocol_version(),
                client_command_id: request.client_command_id,
                outcome: CommandOutcome::Accepted,
            })
        })
    }

    fn attach(&self, _request: AttachRequest) -> WebAttachFuture {
        Box::pin(async {
            Err(AttachRejectedOrBridgeError::Bridge(
                selvedge_web::WebBridgeError::ServerNotReady,
            ))
        })
    }
}

fn loopback_bind() -> WebLocalhostBind {
    WebLocalhostBind {
        host: WebLocalhostHost::Ipv4Loopback,
        port: 4173,
    }
}

fn valid_command_request() -> CommandRequest {
    CommandRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new("command-1").expect("valid command id"),
        command_name: "send-user-input".to_owned(),
        payload: serde_json::json!({ "message": "hello" }),
    }
}

fn valid_attach_request() -> AttachRequest {
    AttachRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new("attach-1").expect("valid command id"),
        subscription: LocalClientSubscription {
            task_scope: LocalTaskScope::AllTasks,
            detail_level: LocalDetailLevel::Summary,
            include_model_call_status: false,
            include_tool_execution_status: false,
            include_debug_notices: false,
        },
    }
}
