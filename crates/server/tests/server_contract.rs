use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use selvedge_api::ApiExecutorConfig;
use selvedge_client_sync::{
    ClientSnapshotBuildFuture, ClientSnapshotBuildRequest, ClientSnapshotBuilder,
};
use selvedge_command_model::{
    ClientSnapshot, RouterCommand, RouterCommandEnvelope, RouterIngressWeakSender,
    ToolExecutionRequest,
};
use selvedge_core::{TaskRuntimeConfig, TaskRuntimeSpawnDeps};
use selvedge_domain_model::{ModelProfileKey, UnixTs};
use selvedge_local_protocol::{
    AttachRequest, CommandOutcome, CommandRejectReason, CommandRequest, LocalClientCommandId,
    LocalClientId, LocalClientSubscription, LocalDetailLevel, LocalTaskScope, ProtocolVersion,
    ReadyRequest, ReadyState, current_protocol_version,
};
use selvedge_router::{ToolExecutionSpawnError, ToolExecutionSpawner};
use selvedge_server::{
    LocalBindingConfig, LocalCommandMapper, LocalhostBindTarget, ServerRequestError,
    ServerRuntimeState, ServerStartArgs, ServerStartupError, spawn_server,
};
use tempfile::TempDir;
use tokio::task::JoinHandle;

#[tokio::test]
async fn spawn_server_initializes_ready_control_and_creates_durable_paths() {
    let home = TempDir::new().expect("temp home");
    let mapper = Arc::new(RecordingMapper::new());

    let handle =
        spawn_server(test_args(home.path().to_path_buf(), mapper.clone())).expect("spawn server");

    assert_eq!(handle.control.state().await, ServerRuntimeState::Ready);
    assert_eq!(
        handle
            .control
            .ready(ReadyRequest {
                protocol_version: current_protocol_version()
            })
            .await
            .state,
        ReadyState::Ready
    );
    assert!(home.path().join("selvedge.sqlite").exists());
    assert!(home.path().join("server.lock").exists());

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
    assert_eq!(handle.control.state().await, ServerRuntimeState::Stopped);
    assert!(!home.path().join("server.lock").exists());
}

#[tokio::test]
async fn singleton_lock_rejects_second_server_for_same_home() {
    let home = TempDir::new().expect("temp home");
    let first = spawn_server(test_args(
        home.path().to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ))
    .expect("spawn first server");

    let second = spawn_server(test_args(
        home.path().to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ));

    assert!(matches!(
        second,
        Err(ServerStartupError::SingletonAlreadyRunning)
    ));

    first.control.stop().await;
    first.join_handle.await.expect("join first server");
}

#[tokio::test]
async fn command_submit_validates_protocol_and_maps_to_router_mailbox() {
    let home = TempDir::new().expect("temp home");
    let mapper = Arc::new(RecordingMapper::new());
    let handle =
        spawn_server(test_args(home.path().to_path_buf(), mapper.clone())).expect("spawn server");

    let invalid = handle
        .control
        .submit_command(CommandRequest {
            protocol_version: ProtocolVersion(2),
            ..valid_command("bad-version")
        })
        .await;
    assert_eq!(
        invalid.outcome,
        CommandOutcome::Rejected(CommandRejectReason::ProtocolVersionMismatch)
    );

    let accepted = handle
        .control
        .submit_command(valid_command("command-1"))
        .await;
    assert_eq!(accepted.outcome, CommandOutcome::Accepted);
    assert_eq!(mapper.seen_commands(), vec!["send-user-input".to_owned()]);

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn command_mapper_can_reject_unsupported_local_command() {
    let home = TempDir::new().expect("temp home");
    let handle = spawn_server(test_args(
        home.path().to_path_buf(),
        Arc::new(RejectingMapper),
    ))
    .expect("spawn server");

    let rejected = handle
        .control
        .submit_command(valid_command("command-1"))
        .await;

    assert_eq!(
        rejected.outcome,
        CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand)
    );

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn attach_client_accepts_valid_subscription_and_rejects_malformed_request() {
    let home = TempDir::new().expect("temp home");
    let handle = spawn_server(test_args(
        home.path().to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ))
    .expect("spawn server");

    let accepted = handle
        .control
        .attach_client(valid_attach("attach-1"))
        .await
        .expect("valid attach request");

    assert_eq!(accepted.0.client_command_id.0, "attach-1");

    let rejected = match handle
        .control
        .attach_client(AttachRequest {
            protocol_version: current_protocol_version(),
            client_id: LocalClientId::new("client-1").expect("valid client id"),
            client_command_id: LocalClientCommandId::new("attach-2").expect("valid command id"),
            subscription: LocalClientSubscription {
                task_scope: LocalTaskScope::TaskIds(vec![" ".to_owned()]),
                detail_level: LocalDetailLevel::Summary,
                include_model_call_status: false,
                include_tool_execution_status: false,
                include_debug_notices: false,
            },
        })
        .await
    {
        Ok(_) => panic!("malformed attach request should be rejected"),
        Err(rejected) => rejected,
    };

    assert_eq!(rejected.reason, CommandRejectReason::MalformedRequest);

    let version_mismatch = match handle
        .control
        .attach_client(AttachRequest {
            protocol_version: ProtocolVersion(2),
            ..valid_attach("attach-3")
        })
        .await
    {
        Ok(_) => panic!("version-mismatched attach request should be rejected"),
        Err(rejected) => rejected,
    };
    assert_eq!(
        version_mismatch.reason,
        CommandRejectReason::ProtocolVersionMismatch
    );

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn stopped_server_rejects_new_command_submissions() {
    let home = TempDir::new().expect("temp home");
    let handle = spawn_server(test_args(
        home.path().to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ))
    .expect("spawn server");

    handle.control.stop().await;

    let response = handle
        .control
        .submit_command(valid_command("command-1"))
        .await;
    assert_eq!(
        response.outcome,
        CommandOutcome::Rejected(CommandRejectReason::ServerNotReady)
    );

    handle.join_handle.await.expect("join server");
}

struct RejectingMapper;

impl LocalCommandMapper for RejectingMapper {
    fn map_command(
        &self,
        _request: CommandRequest,
    ) -> Result<RouterCommandEnvelope, ServerRequestError> {
        Err(ServerRequestError::UnsupportedCommand)
    }
}

struct RecordingMapper {
    seen: Mutex<Vec<String>>,
}

impl RecordingMapper {
    fn new() -> Self {
        Self {
            seen: Mutex::new(Vec::new()),
        }
    }

    fn seen_commands(&self) -> Vec<String> {
        self.seen.lock().expect("mapper lock").clone()
    }
}

impl LocalCommandMapper for RecordingMapper {
    fn map_command(
        &self,
        request: CommandRequest,
    ) -> Result<RouterCommandEnvelope, ServerRequestError> {
        self.seen
            .lock()
            .expect("mapper lock")
            .push(request.command_name);
        Ok(RouterCommandEnvelope {
            client_id: None,
            client_command_id: None,
            command: RouterCommand::EnsureMissingTaskRuntimes,
        })
    }
}

struct EmptySnapshotBuilder;

impl ClientSnapshotBuilder for EmptySnapshotBuilder {
    fn build_snapshot(&self, _request: ClientSnapshotBuildRequest) -> ClientSnapshotBuildFuture {
        Box::pin(async {
            Ok(ClientSnapshot {
                generated_at: UnixTs(1),
                tasks: Vec::new(),
                task_parent_edges: Vec::new(),
                history_nodes: Vec::new(),
                task_versions: Vec::new(),
            })
        })
    }
}

struct NoopToolExecutor;

impl ToolExecutionSpawner for NoopToolExecutor {
    fn spawn_tool_execution(
        &self,
        _request: ToolExecutionRequest,
        _router_tx: RouterIngressWeakSender,
    ) -> Result<JoinHandle<()>, ToolExecutionSpawnError> {
        Err(ToolExecutionSpawnError::ToolExecutorUnavailable)
    }
}

fn test_args(home: std::path::PathBuf, mapper: Arc<dyn LocalCommandMapper>) -> ServerStartArgs {
    ServerStartArgs {
        explicit_home: Some(home),
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        tool_executor: Arc::new(NoopToolExecutor),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 4,
            model_profiles: HashMap::<ModelProfileKey, _>::new(),
        }),
        snapshot_builder: Arc::new(EmptySnapshotBuilder),
        command_mapper: mapper,
        local_binding: LocalBindingConfig {
            bind_target: LocalhostBindTarget::Ipv4 { port: 0 },
        },
        web_binding: None,
    }
}

fn valid_command(command_id: &str) -> CommandRequest {
    CommandRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("valid command id"),
        command_name: "send-user-input".to_owned(),
        payload: serde_json::json!({"message": "hello"}),
    }
}

fn valid_attach(command_id: &str) -> AttachRequest {
    AttachRequest {
        protocol_version: current_protocol_version(),
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("valid command id"),
        subscription: LocalClientSubscription {
            task_scope: LocalTaskScope::AllTasks,
            detail_level: LocalDetailLevel::Summary,
            include_model_call_status: false,
            include_tool_execution_status: false,
            include_debug_notices: false,
        },
    }
}
