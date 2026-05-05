use std::collections::HashMap;
use std::sync::{Arc, LazyLock, Mutex, mpsc as std_mpsc};
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
    ServerRuntimeState, ServerStartArgs, ServerStartupError, WebBindingConfig, spawn_server,
};
use tempfile::TempDir;
use tokio::sync::Mutex as AsyncMutex;
use tokio::task::JoinHandle;
use tokio::time::timeout;

static SERVER_TEST_LOCK: LazyLock<AsyncMutex<()>> = LazyLock::new(|| AsyncMutex::new(()));
static SERVER_TEST_HOME: LazyLock<TempDir> = LazyLock::new(|| TempDir::new().expect("temp home"));

#[tokio::test]
async fn spawn_server_initializes_ready_control_and_creates_durable_paths() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let mapper = Arc::new(RecordingMapper::new());

    let handle = spawn_server(test_args(home.to_path_buf(), mapper.clone())).expect("spawn server");

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
    let mismatched_ready = handle
        .control
        .ready(ReadyRequest {
            protocol_version: ProtocolVersion(2),
        })
        .await;
    assert_eq!(
        mismatched_ready.protocol_version,
        current_protocol_version()
    );
    assert_eq!(mismatched_ready.state, ReadyState::NotReady);
    assert!(home.join("selvedge.sqlite").exists());
    assert!(home.join("server.lock").exists());

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
    assert_eq!(handle.control.state().await, ServerRuntimeState::Stopped);
    assert!(!home.join("server.lock").exists());
}

#[tokio::test]
async fn singleton_lock_rejects_second_server_for_same_home() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let first = spawn_server(test_args(
        home.to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ))
    .expect("spawn first server");

    let second = spawn_server(test_args(
        home.to_path_buf(),
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
async fn stale_lock_file_does_not_block_server_restart() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    std::fs::write(home.join("server.lock"), "stale").expect("write stale lock");

    let handle = spawn_server(test_args(
        home.to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ))
    .expect("spawn server with stale lock file");

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn startup_failure_after_lock_removes_recoverable_lock_file() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let sqlite_path = home.join("selvedge.sqlite");
    let lock_path = home.join("server.lock");
    let _ = std::fs::remove_file(&lock_path);
    let _ = std::fs::remove_file(&sqlite_path);
    let _ = std::fs::remove_dir_all(&sqlite_path);
    std::fs::create_dir(&sqlite_path).expect("create sqlite path directory");

    let failed = spawn_server(test_args(
        home.to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ));

    assert!(matches!(failed, Err(ServerStartupError::DbOpenFailed(_))));
    assert!(!lock_path.exists());

    std::fs::remove_dir(&sqlite_path).expect("remove sqlite path directory");
    let restarted = spawn_server(test_args(
        home.to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ))
    .expect("stale lock file should remain recoverable");
    restarted.control.stop().await;
    restarted.join_handle.await.expect("join restarted server");
}

#[tokio::test]
async fn invalid_web_bind_target_is_rejected_before_durable_startup_side_effects() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let sqlite_path = home.join("selvedge.sqlite");
    let lock_path = home.join("server.lock");
    let _ = std::fs::remove_file(&lock_path);
    let _ = std::fs::remove_file(&sqlite_path);

    let mut args = test_args(home.to_path_buf(), Arc::new(RecordingMapper::new()));
    args.web_binding = Some(WebBindingConfig {
        bind_target: LocalhostBindTarget::Ipv4 { port: 0 },
    });

    let failed = spawn_server(args);

    assert!(matches!(failed, Err(ServerStartupError::InvalidBindTarget)));
    assert!(!sqlite_path.exists());
    assert!(!lock_path.exists());
}

#[tokio::test]
async fn command_submit_validates_protocol_and_maps_to_router_mailbox() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let mapper = Arc::new(RecordingMapper::new());
    let handle = spawn_server(test_args(home.to_path_buf(), mapper.clone())).expect("spawn server");

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
async fn stop_waits_for_in_flight_command_acceptance_decision() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let (entered_tx, entered_rx) = std_mpsc::channel();
    let (release_tx, release_rx) = std_mpsc::channel();
    let handle = spawn_server(test_args(
        home.to_path_buf(),
        Arc::new(BlockingMapper {
            entered_tx,
            release_rx: Mutex::new(release_rx),
        }),
    ))
    .expect("spawn server");

    let runtime_handle = tokio::runtime::Handle::current();
    let submit_control = handle.control.clone();
    let submit_thread = std::thread::spawn(move || {
        runtime_handle.block_on(async move {
            submit_control
                .submit_command(valid_command("command-1"))
                .await
        })
    });
    entered_rx
        .recv_timeout(Duration::from_secs(1))
        .expect("mapper should enter command acceptance");

    let stop_control = handle.control.clone();
    let mut stop_task = tokio::spawn(async move { stop_control.stop().await });
    let stop_waited = timeout(Duration::from_millis(50), &mut stop_task)
        .await
        .is_err();

    release_tx.send(()).expect("release mapper");
    assert!(stop_waited);
    let response = submit_thread.join().expect("join submit thread");
    assert_eq!(response.outcome, CommandOutcome::Accepted);
    stop_task.await.expect("join stop task");
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn command_mapper_can_reject_unsupported_local_command() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let handle = spawn_server(test_args(home.to_path_buf(), Arc::new(RejectingMapper)))
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
async fn attach_client_defers_accepted_stream_until_client_sync_hydration_exists() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let handle = spawn_server(test_args(
        home.to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ))
    .expect("spawn server");

    let deferred = match handle.control.attach_client(valid_attach("attach-1")).await {
        Ok(_) => panic!("server stage should defer accepted attach streams"),
        Err(rejected) => rejected,
    };
    assert_eq!(deferred.reason, CommandRejectReason::ServerNotReady);

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
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let handle = spawn_server(test_args(
        home.to_path_buf(),
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

#[tokio::test]
async fn initialized_config_rejects_mismatched_explicit_home() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let handle = spawn_server(test_args(
        home.to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ))
    .expect("spawn server");
    handle.control.stop().await;
    handle.join_handle.await.expect("join server");

    let other_home = TempDir::new().expect("other temp home");
    let result = spawn_server(test_args(
        other_home.path().to_path_buf(),
        Arc::new(RecordingMapper::new()),
    ));

    assert!(matches!(
        result,
        Err(ServerStartupError::ConfigInitFailed(_))
    ));
}

#[tokio::test]
async fn relative_explicit_home_cleans_lock_after_working_directory_changes() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let parent = home.parent().expect("temp home parent").to_path_buf();
    let home_name = home.file_name().expect("temp home name").to_os_string();
    let original_cwd = std::env::current_dir().expect("current dir");
    let _ = std::fs::remove_file(home.join("server.lock"));

    std::env::set_current_dir(&parent).expect("enter home parent");
    let handle = spawn_server(test_args(
        std::path::PathBuf::from(home_name),
        Arc::new(RecordingMapper::new()),
    ))
    .expect("spawn server with relative home");
    assert!(home.join("server.lock").exists());

    let other_cwd = TempDir::new().expect("other cwd");
    std::env::set_current_dir(other_cwd.path()).expect("change cwd");
    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
    std::env::set_current_dir(original_cwd).expect("restore cwd");

    assert!(!home.join("server.lock").exists());
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

struct BlockingMapper {
    entered_tx: std_mpsc::Sender<()>,
    release_rx: Mutex<std_mpsc::Receiver<()>>,
}

impl LocalCommandMapper for BlockingMapper {
    fn map_command(
        &self,
        _request: CommandRequest,
    ) -> Result<RouterCommandEnvelope, ServerRequestError> {
        self.entered_tx.send(()).expect("send mapper entry");
        self.release_rx
            .lock()
            .expect("release lock")
            .recv_timeout(Duration::from_secs(1))
            .expect("mapper release");
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
