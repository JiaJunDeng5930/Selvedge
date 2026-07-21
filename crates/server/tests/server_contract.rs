use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, LazyLock, Mutex, mpsc as std_mpsc};
use std::time::Duration;

use futures_util::StreamExt;
use selvedge_api::ApiExecutorConfig;
use selvedge_client_sync::{
    ClientSnapshotBuildFuture, ClientSnapshotBuildRequest, ClientSnapshotBuilder,
};
use selvedge_command_model::ClientSnapshot;
use selvedge_config_model::{HarnessConfig, McpServerConfig};
use selvedge_core::{TaskRuntimeConfig, TaskRuntimeSpawnDeps};
use selvedge_db::{
    CreateRootTaskInput, NewHistoryNode, NewHistoryNodeContent, NewMessageNodeContent,
    OpenDbOptions, ReasoningEffort, TaskId, ToolExecutionSource, create_history_node,
    create_root_task, load_runtime_task, open_db, read_tool_execution_source,
    read_tool_manifest_for_task,
};
use selvedge_domain_model::{ModelProfileKey, ToolName, UnixTs};
use selvedge_harness::harness_tool_catalog;
use selvedge_local_protocol::{
    AttachRejectReason, AttachRequest, CommandOutcome, CommandRejectReason, CommandRequest,
    LocalClientCommandId, LocalClientFrame, LocalClientId, LocalClientSubscription,
    LocalDetailLevel, LocalTaskScope, ReadyRequest, ReadyState,
};
use selvedge_server::{
    LocalBindingConfig, LocalOperationCommand, LocalOperationExecutor, LocalOperationFuture,
    LocalOperationProgressSender, LocalOperationSuccess, LocalhostBindTarget, ServerRuntimeState,
    ServerStartArgs, ServerStartupError, WebBindingConfig, spawn_server,
};
use selvedge_test_support::http::released_loopback_port;
use tempfile::TempDir;
use tokio::sync::Mutex as AsyncMutex;
use tokio::time::timeout;

static SERVER_TEST_LOCK: LazyLock<AsyncMutex<()>> = LazyLock::new(|| AsyncMutex::new(()));
static SERVER_TEST_HOME: LazyLock<TempDir> = LazyLock::new(|| TempDir::new().expect("temp home"));
#[tokio::test]
async fn spawn_server_initializes_ready_control_and_creates_durable_paths() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();

    let handle = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("spawn server");

    assert_eq!(handle.control.state().await, ServerRuntimeState::Ready);
    assert_eq!(
        handle.control.ready(ReadyRequest {}).await.state,
        ReadyState::Ready
    );
    assert!(home.join("selvedge.sqlite").exists());
    assert!(home.join("server.lock").exists());

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
    assert_eq!(handle.control.state().await, ServerRuntimeState::Stopped);
    assert!(home.join("server.lock").exists());

    let restarted = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("persistent lock file must be reusable after shutdown");
    restarted.control.stop().await;
    restarted.join_handle.await.expect("join restarted server");
}

#[tokio::test]
async fn startup_preserves_existing_task_tool_snapshot_and_limits() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let db = open_db(OpenDbOptions {
        sqlite_path: home.join("selvedge.sqlite").to_string_lossy().to_string(),
        max_children_per_fork: 5,
        max_task_descendants: 20,
    })
    .expect("open server database");
    let cursor_node_id = create_history_node(
        &db,
        NewHistoryNode {
            parent_node_id: None,
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: selvedge_db::MessageRole::User,
                message_text: "probe".to_owned(),
            }),
            created_at: UnixTs(1),
        },
    )
    .expect("create probe history");
    let task_id = TaskId("manifest-probe".to_owned());
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: task_id.clone(),
            cursor_node_id,
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            tools: harness_tool_catalog(&HarnessConfig::default()),
            now: UnixTs(1),
        },
    )
    .expect("create probe task");

    let before = read_tool_manifest_for_task(&db, &task_id).expect("read original manifest");
    let mut args = test_args(home.to_path_buf());
    args.harness_config.max_children_per_fork = 3;
    let handle = spawn_server(args).await.expect("spawn server");

    assert_eq!(
        read_tool_manifest_for_task(&db, &task_id).expect("read preserved manifest"),
        before
    );
    let execution = read_tool_execution_source(&db, &task_id, &ToolName("fork_task".to_owned()))
        .expect("read harness execution source");
    assert_eq!(execution.source, ToolExecutionSource::Harness);
    assert_eq!(execution.max_children_per_fork, 5);
    assert_eq!(
        load_runtime_task(&db, &task_id)
            .expect("load preserved task")
            .task
            .max_task_descendants,
        20
    );

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn singleton_lock_rejects_second_server_for_same_home() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let first = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("spawn first server");

    let second = spawn_server(test_args(home.to_path_buf())).await;

    assert!(matches!(
        second,
        Err(ServerStartupError::SingletonAlreadyRunning)
    ));

    first.control.stop().await;
    first.join_handle.await.expect("join first server");
}

#[tokio::test]
async fn singleton_lock_rejects_second_web_enabled_server_before_port_bind() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let port = unused_tcp_v4_port();
    let mut first_args = test_args(home.to_path_buf());
    first_args.web_binding = Some(WebBindingConfig {
        bind_target: LocalhostBindTarget::Ipv4 { port },
    });
    let first = spawn_server(first_args).await.expect("spawn first server");

    let mut second_args = test_args(home.to_path_buf());
    second_args.web_binding = Some(WebBindingConfig {
        bind_target: LocalhostBindTarget::Ipv4 { port },
    });
    let second = spawn_server(second_args).await;

    assert!(matches!(
        second,
        Err(ServerStartupError::SingletonAlreadyRunning)
    ));

    first.control.stop().await;
    first.join_handle.await.expect("join first server");
}

#[tokio::test]
async fn persistent_lock_file_does_not_block_server_restart() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    std::fs::write(home.join("server.lock"), "stale").expect("write stale lock");

    let handle = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("spawn server with stale lock file");

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn startup_failure_releases_persistent_lock() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let sqlite_path = home.join("selvedge.sqlite");
    let lock_path = home.join("server.lock");
    let _ = std::fs::remove_file(&lock_path);
    let _ = std::fs::remove_file(&sqlite_path);
    let _ = std::fs::remove_dir_all(&sqlite_path);
    std::fs::create_dir(&sqlite_path).expect("create sqlite path directory");

    let failed = spawn_server(test_args(home.to_path_buf())).await;

    assert!(matches!(failed, Err(ServerStartupError::DbOpenFailed(_))));
    assert!(lock_path.exists());

    std::fs::remove_dir(&sqlite_path).expect("remove sqlite path directory");
    let restarted = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("persistent lock file should be reusable");
    restarted.control.stop().await;
    restarted.join_handle.await.expect("join restarted server");
}

#[tokio::test]
async fn mcp_start_failure_releases_persistent_lock() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let lock_path = home.join("server.lock");
    let _ = std::fs::remove_file(&lock_path);
    let mut args = test_args(home.to_path_buf());
    args.mcp_servers.insert(
        "missing".to_owned(),
        McpServerConfig {
            command: home
                .join("missing-mcp-server")
                .to_string_lossy()
                .to_string(),
            args: Vec::new(),
            env: BTreeMap::new(),
            timeout_ms: 100,
        },
    );

    let failed = spawn_server(args).await;

    assert!(matches!(failed, Err(ServerStartupError::McpStartFailed(_))));
    assert!(lock_path.exists());

    let restarted = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("MCP startup failure should leave the server restartable");
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

    let mut args = test_args(home.to_path_buf());
    args.web_binding = Some(WebBindingConfig {
        bind_target: LocalhostBindTarget::Ipv4 { port: 0 },
    });

    let failed = spawn_server(args).await;

    assert!(matches!(failed, Err(ServerStartupError::InvalidBindTarget)));
    assert!(!sqlite_path.exists());
    assert!(!lock_path.exists());
}

#[tokio::test]
async fn occupied_web_bind_target_is_rejected_before_runtime_tasks_start() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let sqlite_path = home.join("selvedge.sqlite");
    let lock_path = home.join("server.lock");
    let _ = std::fs::remove_file(&lock_path);
    let _ = std::fs::remove_file(&sqlite_path);
    let listener = std::net::TcpListener::bind(("127.0.0.1", 0)).expect("bind occupied port");
    let port = listener.local_addr().expect("occupied addr").port();

    let mut args = test_args(home.to_path_buf());
    args.web_binding = Some(WebBindingConfig {
        bind_target: LocalhostBindTarget::Ipv4 { port },
    });

    let failed = spawn_server(args).await;

    assert!(matches!(
        failed,
        Err(ServerStartupError::LocalhostBindFailed(_))
    ));
    assert!(!sqlite_path.exists());
    assert!(lock_path.exists());
}

#[tokio::test]
async fn supported_command_is_accepted() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let handle = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("spawn server");
    let (_accepted, mut frames) = handle
        .control
        .attach_client(valid_attach("attach-1"))
        .await
        .expect("attach accepted");
    timeout(Duration::from_secs(1), frames.next())
        .await
        .expect("snapshot timeout")
        .expect("snapshot frame")
        .expect("snapshot frame ok");

    let accepted = handle
        .control
        .submit_command(list_models_command("command-1"))
        .await;
    assert_eq!(accepted.outcome, CommandOutcome::Accepted);

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn stop_waits_for_in_flight_command_acceptance_decision() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let (entered_tx, entered_rx) = std_mpsc::channel();
    let (release_tx, release_rx) = std_mpsc::channel();
    let handle = spawn_server(test_args_with_local_operation_executor(
        home.to_path_buf(),
        Arc::new(BlockingLocalOperationExecutor {
            entered_tx,
            release_rx: Mutex::new(release_rx),
        }),
    ))
    .await
    .expect("spawn server");
    let (_accepted, mut frames) = handle
        .control
        .attach_client(valid_attach("attach-1"))
        .await
        .expect("attach accepted");
    timeout(Duration::from_secs(1), frames.next())
        .await
        .expect("snapshot timeout")
        .expect("snapshot frame")
        .expect("snapshot frame ok");

    let runtime_handle = tokio::runtime::Handle::current();
    let submit_control = handle.control.clone();
    let submit_thread = std::thread::spawn(move || {
        runtime_handle.block_on(async move {
            submit_control
                .submit_command(list_models_command("command-1"))
                .await
        })
    });
    entered_rx
        .recv_timeout(Duration::from_secs(1))
        .expect("executor should enter command acceptance");

    let stop_control = handle.control.clone();
    let mut stop_task = tokio::spawn(async move { stop_control.stop().await });
    let stop_waited = timeout(Duration::from_millis(50), &mut stop_task)
        .await
        .is_err();

    release_tx.send(()).expect("release executor");
    assert!(stop_waited);
    let response = submit_thread.join().expect("join submit thread");
    assert_eq!(response.outcome, CommandOutcome::Accepted);
    stop_task.await.expect("join stop task");
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn unknown_command_is_rejected() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let handle = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("spawn server");

    let rejected = handle
        .control
        .submit_command(unsupported_command("command-1"))
        .await;

    assert_eq!(
        rejected.outcome,
        CommandOutcome::Rejected(CommandRejectReason::UnsupportedCommand)
    );

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn attach_client_accepts_and_streams_initial_snapshot() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let handle = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("spawn server");

    let (accepted, mut frames) = handle
        .control
        .attach_client(valid_attach("attach-1"))
        .await
        .expect("attach accepted");
    assert_eq!(
        accepted.client_command_id,
        LocalClientCommandId::new("attach-1").expect("valid command id")
    );
    let frame = timeout(Duration::from_secs(1), frames.next())
        .await
        .expect("snapshot timeout")
        .expect("snapshot frame")
        .expect("snapshot frame ok");
    assert!(matches!(frame, LocalClientFrame::Snapshot(_)));

    let rejected = match handle
        .control
        .attach_client(AttachRequest {
            client_id: LocalClientId::new("client-1").expect("valid client id"),
            client_command_id: LocalClientCommandId::new("attach-2").expect("valid command id"),
            subscription: LocalClientSubscription {
                task_scope: LocalTaskScope::TaskIds(vec![" ".to_owned()]),
                detail_level: LocalDetailLevel::Summary,
                snapshot_mode: selvedge_local_protocol::LocalSnapshotMode::CurrentState,
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

    assert_eq!(rejected.reason, AttachRejectReason::MalformedRequest);

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn dropped_attach_stream_detaches_events_session() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let handle = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("spawn server");

    for index in 0..70 {
        let (_accepted, mut frames) = handle
            .control
            .attach_client(valid_attach_for(
                &format!("client-{index}"),
                &format!("attach-{index}"),
            ))
            .await
            .expect("attach accepted");
        let frame = timeout(Duration::from_secs(1), frames.next())
            .await
            .expect("snapshot timeout")
            .expect("snapshot frame")
            .expect("snapshot frame ok");
        assert!(matches!(frame, LocalClientFrame::Snapshot(_)));
        drop(frames);
        tokio::task::yield_now().await;
    }

    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
}

#[tokio::test]
async fn stopped_server_rejects_new_command_submissions() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let handle = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("spawn server");

    handle.control.stop().await;

    let response = handle
        .control
        .submit_command(list_models_command("command-1"))
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
    let handle = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("spawn server");
    handle.control.stop().await;
    handle.join_handle.await.expect("join server");

    let other_home = TempDir::new().expect("other temp home");
    let result = spawn_server(test_args(other_home.path().to_path_buf())).await;

    assert!(matches!(
        result,
        Err(ServerStartupError::ConfigInitFailed(_))
    ));
}

#[tokio::test]
async fn relative_explicit_home_releases_lock_after_working_directory_changes() {
    let _guard = SERVER_TEST_LOCK.lock().await;
    let home = SERVER_TEST_HOME.path();
    let parent = home.parent().expect("temp home parent").to_path_buf();
    let home_name = home.file_name().expect("temp home name").to_os_string();
    let original_cwd = std::env::current_dir().expect("current dir");
    let _ = std::fs::remove_file(home.join("server.lock"));

    std::env::set_current_dir(&parent).expect("enter home parent");
    let handle = spawn_server(test_args(std::path::PathBuf::from(home_name)))
        .await
        .expect("spawn server with relative home");
    assert!(home.join("server.lock").exists());

    let other_cwd = TempDir::new().expect("other cwd");
    std::env::set_current_dir(other_cwd.path()).expect("change cwd");
    handle.control.stop().await;
    handle.join_handle.await.expect("join server");
    std::env::set_current_dir(original_cwd).expect("restore cwd");

    assert!(home.join("server.lock").exists());
    let restarted = spawn_server(test_args(home.to_path_buf()))
        .await
        .expect("relative-home lock should be reusable after shutdown");
    restarted.control.stop().await;
    restarted.join_handle.await.expect("join restarted server");
}

struct BlockingLocalOperationExecutor {
    entered_tx: std_mpsc::Sender<()>,
    release_rx: Mutex<std_mpsc::Receiver<()>>,
}

impl LocalOperationExecutor for BlockingLocalOperationExecutor {
    fn execute(
        &self,
        _command: LocalOperationCommand,
        _progress_tx: LocalOperationProgressSender,
    ) -> LocalOperationFuture {
        self.entered_tx.send(()).expect("send executor entry");
        self.release_rx
            .lock()
            .expect("release lock")
            .recv_timeout(Duration::from_secs(1))
            .expect("executor release");
        Box::pin(async {
            Ok(LocalOperationSuccess {
                message_text: "completed".to_owned(),
            })
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

struct NoopLocalOperationExecutor;

impl LocalOperationExecutor for NoopLocalOperationExecutor {
    fn execute(
        &self,
        _command: LocalOperationCommand,
        _progress_tx: LocalOperationProgressSender,
    ) -> LocalOperationFuture {
        Box::pin(async {
            Ok(LocalOperationSuccess {
                message_text: "noop".to_owned(),
            })
        })
    }
}

fn test_args(home: std::path::PathBuf) -> ServerStartArgs {
    test_args_with_local_operation_executor(home, Arc::new(NoopLocalOperationExecutor))
}

fn test_args_with_local_operation_executor(
    home: std::path::PathBuf,
    local_operation_executor: Arc<dyn LocalOperationExecutor>,
) -> ServerStartArgs {
    ServerStartArgs {
        explicit_home: Some(home),
        harness_config: selvedge_config_model::HarnessConfig::default(),
        mcp_servers: BTreeMap::new(),
        api_config: ApiExecutorConfig {
            request_timeout: Duration::from_secs(1),
            max_response_bytes: None,
        },
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            model_profiles: HashMap::<ModelProfileKey, _>::new(),
        }),
        snapshot_builder: Arc::new(EmptySnapshotBuilder),
        local_operation_executor,
        local_binding: LocalBindingConfig {
            bind_target: LocalhostBindTarget::Ipv4 { port: 0 },
        },
        web_binding: None,
    }
}

fn unused_tcp_v4_port() -> u16 {
    released_loopback_port()
}

fn unsupported_command(command_id: &str) -> CommandRequest {
    CommandRequest {
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("valid command id"),
        command_name: "send-user-input".to_owned(),
        payload: serde_json::json!({"message": "hello"}),
    }
}

fn list_models_command(command_id: &str) -> CommandRequest {
    CommandRequest {
        client_id: LocalClientId::new("client-1").expect("valid client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("valid command id"),
        command_name: "list-models".to_owned(),
        payload: serde_json::json!({}),
    }
}

fn valid_attach(command_id: &str) -> AttachRequest {
    valid_attach_for("client-1", command_id)
}

fn valid_attach_for(client_id: &str, command_id: &str) -> AttachRequest {
    AttachRequest {
        client_id: LocalClientId::new(client_id).expect("valid client id"),
        client_command_id: LocalClientCommandId::new(command_id).expect("valid command id"),
        subscription: LocalClientSubscription {
            task_scope: LocalTaskScope::AllTasks,
            detail_level: LocalDetailLevel::Summary,
            snapshot_mode: selvedge_local_protocol::LocalSnapshotMode::CurrentState,
            include_model_call_status: false,
            include_tool_execution_status: false,
            include_debug_notices: false,
        },
    }
}
