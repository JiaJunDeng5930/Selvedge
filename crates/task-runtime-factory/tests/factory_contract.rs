use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;

use selvedge_command_model::{
    CreatedRuntimeKind, FactoryEffectId, FactoryFailureKind, FactoryOutput, FactorySkipReason,
    RouterIngressFactoryMessage, RouterIngressMessage, RuntimeInventoryResponse,
};
use selvedge_core::{
    SpawnTaskRuntimeArgs, SpawnTaskRuntimeError, SpawnedTaskRuntime, TaskRuntimeConfig,
    TaskRuntimeSpawnDeps, TaskRuntimeSpawner,
};
use selvedge_db::{
    CreateRootTaskInput, DbPool, MessageRole, ModelProfileKey, NewHistoryNode,
    NewHistoryNodeContent, NewMessageNodeContent, OpenDbOptions, ReasoningEffort, TaskId, ToolName,
    ToolSpec, UnixTs, archive_task, create_history_node, create_root_task, load_active_task,
    open_db, read_task_parent_edges, read_tool_manifest_for_task, register_tool,
};
use selvedge_domain_model::ModelProviderProfile;
use selvedge_task_runtime_factory::{
    CreateChildTaskAndRuntimeCommand, EnsureMissingTaskRuntimesCommand, EnsureTaskRuntimeCommand,
    FactoryCommand, FactoryEffectArgs, spawn_factory_effect,
};

#[tokio::test]
async fn ensure_task_runtime_creates_runtime_for_existing_active_task() {
    let db = open_memory_db();
    create_root(&db, "task-1");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_factory_effect(FactoryEffectArgs {
        command: FactoryCommand::EnsureTaskRuntime(EnsureTaskRuntimeCommand {
            effect_id: FactoryEffectId("factory-1".to_owned()),
            task_id: TaskId("task-1".to_owned()),
        }),
        db,
        router_tx,
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn factory effect");
    handle.await.expect("factory task joins");

    let message = router_rx.recv().await.expect("factory output");
    let RouterIngressMessage::Factory(RouterIngressFactoryMessage::Output(envelope)) = message
    else {
        panic!("unexpected router message");
    };
    assert_eq!(envelope.effect_id, FactoryEffectId("factory-1".to_owned()));
    let FactoryOutput::RuntimeCreated(created) = envelope.output else {
        panic!("unexpected factory output");
    };
    assert_eq!(created.task_id, TaskId("task-1".to_owned()));
    assert_eq!(
        created.created_runtime_kind,
        CreatedRuntimeKind::ExistingTaskRuntime
    );

    tokio::time::timeout(Duration::from_millis(25), router_rx.recv())
        .await
        .expect_err("factory leaves runtime idle");
}

#[tokio::test]
async fn ensure_task_runtime_reports_missing_and_archived_tasks() {
    let missing = run_ensure_task_runtime(open_memory_db(), "missing").await;
    let FactoryOutput::Failed(failure) = missing else {
        panic!("unexpected factory output");
    };
    assert_eq!(failure.task_id, Some(TaskId("missing".to_owned())));
    assert_eq!(failure.kind, FactoryFailureKind::TaskMissing);

    let db = open_memory_db();
    create_root(&db, "archived");
    archive_task(&db, &TaskId("archived".to_owned()), UnixTs(2)).expect("archive task");

    let archived = run_ensure_task_runtime(db, "archived").await;
    let FactoryOutput::Failed(failure) = archived else {
        panic!("unexpected factory output");
    };
    assert_eq!(failure.task_id, Some(TaskId("archived".to_owned())));
    assert_eq!(failure.kind, FactoryFailureKind::TaskArchived);
}

#[tokio::test]
async fn ensure_missing_task_runtimes_skips_live_and_pending_inventory() {
    let db = open_memory_db();
    create_root(&db, "live");
    create_root(&db, "pending");
    create_root(&db, "missing");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_factory_effect(FactoryEffectArgs {
        command: FactoryCommand::EnsureMissingTaskRuntimes(EnsureMissingTaskRuntimesCommand {
            effect_id: FactoryEffectId("factory-scan".to_owned()),
        }),
        db,
        router_tx,
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn factory effect");

    let query = tokio::time::timeout(Duration::from_millis(50), router_rx.recv())
        .await
        .expect("runtime inventory query")
        .expect("runtime inventory message");
    let RouterIngressMessage::QueryRuntimeInventory(query) = query else {
        panic!("unexpected router message");
    };
    query
        .reply_to
        .send(RuntimeInventoryResponse {
            live_task_runtimes: vec![TaskId("live".to_owned())],
            pending_task_runtime_effects: vec![TaskId("pending".to_owned())],
        })
        .expect("send runtime inventory");

    handle.await.expect("factory task joins");
    let message = router_rx.recv().await.expect("factory output");
    let RouterIngressMessage::Factory(RouterIngressFactoryMessage::Output(envelope)) = message
    else {
        panic!("unexpected router message");
    };
    assert_eq!(
        envelope.effect_id,
        FactoryEffectId("factory-scan".to_owned())
    );
    let FactoryOutput::ScanFinished(scan) = envelope.output else {
        panic!("unexpected factory output");
    };

    assert_eq!(scan.created.len(), 1);
    assert_eq!(scan.created[0].task_id, TaskId("missing".to_owned()));
    assert_eq!(
        scan.created[0].created_runtime_kind,
        CreatedRuntimeKind::ExistingTaskRuntime
    );
    assert_eq!(scan.failed, Vec::new());
    assert_eq!(scan.skipped.len(), 2);
    assert!(scan.skipped.iter().any(|skipped| {
        skipped.task_id == TaskId("live".to_owned())
            && skipped.reason == FactorySkipReason::RuntimeAlreadyLive
    }));
    assert!(scan.skipped.iter().any(|skipped| {
        skipped.task_id == TaskId("pending".to_owned())
            && skipped.reason == FactorySkipReason::RuntimeCreationPending
    }));
}

#[tokio::test]
async fn create_child_task_and_runtime_persists_child_and_copies_parent_settings() {
    let db = open_memory_db();
    register_tool(
        &db,
        ToolSpec {
            name: "search".to_owned(),
            description: "search".to_owned(),
            parameters: Vec::new(),
        },
    )
    .expect("register tool");
    let parent_cursor_node_id = create_message_node(&db, None, MessageRole::User, "parent");
    create_root_task(
        &db,
        CreateRootTaskInput {
            task_id: TaskId("parent".to_owned()),
            cursor_node_id: parent_cursor_node_id,
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::High,
            enabled_tools: vec![ToolName("search".to_owned())],
            now: UnixTs(1),
        },
    )
    .expect("create parent task");
    let child_cursor_node_id = create_message_node(&db, None, MessageRole::User, "child cursor");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_factory_effect(FactoryEffectArgs {
        command: FactoryCommand::CreateChildTaskAndRuntime(CreateChildTaskAndRuntimeCommand {
            effect_id: FactoryEffectId("factory-child".to_owned()),
            parent_task_id: TaskId("parent".to_owned()),
            child_cursor_node_id,
        }),
        db: db.clone(),
        router_tx,
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn factory effect");
    handle.await.expect("factory task joins");

    let message = router_rx.recv().await.expect("factory output");
    let RouterIngressMessage::Factory(RouterIngressFactoryMessage::Output(envelope)) = message
    else {
        panic!("unexpected router message");
    };
    assert_eq!(
        envelope.effect_id,
        FactoryEffectId("factory-child".to_owned())
    );
    let FactoryOutput::RuntimeCreated(created) = envelope.output else {
        panic!("unexpected factory output");
    };
    assert_eq!(
        created.created_runtime_kind,
        CreatedRuntimeKind::ChildTaskRuntime
    );

    let child = load_active_task(&db, &created.task_id).expect("load child task");
    assert_eq!(child.task.cursor_node_id, child_cursor_node_id);
    assert_eq!(
        child.task.model_profile_key,
        ModelProfileKey("default".to_owned())
    );
    assert_eq!(child.task.reasoning_effort, ReasoningEffort::High);

    let manifest = read_tool_manifest_for_task(&db, &created.task_id).expect("child manifest");
    assert_eq!(manifest.tools[0].name, "search");

    let edges = read_task_parent_edges(&db).expect("read task edges");
    assert!(edges.iter().any(|edge| {
        edge.parent_task_id == TaskId("parent".to_owned()) && edge.child_task_id == created.task_id
    }));
}

#[tokio::test]
async fn ensure_missing_task_runtimes_reports_unavailable_inventory() {
    let db = open_memory_db();
    create_root(&db, "task-1");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_factory_effect(FactoryEffectArgs {
        command: FactoryCommand::EnsureMissingTaskRuntimes(EnsureMissingTaskRuntimesCommand {
            effect_id: FactoryEffectId("factory-scan".to_owned()),
        }),
        db,
        router_tx,
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn factory effect");

    let query = router_rx.recv().await.expect("runtime inventory query");
    let RouterIngressMessage::QueryRuntimeInventory(query) = query else {
        panic!("unexpected router message");
    };
    drop(query);

    handle.await.expect("factory task joins");
    let output = recv_factory_output(&mut router_rx).await;
    let FactoryOutput::Failed(failure) = output else {
        panic!("unexpected factory output");
    };
    assert_eq!(
        failure.kind,
        FactoryFailureKind::RuntimeInventoryUnavailable
    );
}

#[tokio::test]
async fn create_child_task_and_runtime_reports_parent_and_cursor_failures() {
    let missing_parent =
        run_create_child(open_memory_db(), "missing", selvedge_db::HistoryNodeId(1)).await;
    let FactoryOutput::Failed(failure) = missing_parent else {
        panic!("unexpected factory output");
    };
    assert_eq!(failure.kind, FactoryFailureKind::ParentTaskMissing);

    let db = open_memory_db();
    create_root(&db, "archived");
    archive_task(&db, &TaskId("archived".to_owned()), UnixTs(2)).expect("archive task");
    let archived_parent = run_create_child(db, "archived", selvedge_db::HistoryNodeId(1)).await;
    let FactoryOutput::Failed(failure) = archived_parent else {
        panic!("unexpected factory output");
    };
    assert_eq!(failure.kind, FactoryFailureKind::ParentTaskArchived);

    let db = open_memory_db();
    create_root(&db, "parent");
    let missing_cursor = run_create_child(db, "parent", selvedge_db::HistoryNodeId(9_999)).await;
    let FactoryOutput::Failed(failure) = missing_cursor else {
        panic!("unexpected factory output");
    };
    assert_eq!(failure.kind, FactoryFailureKind::CursorNodeMissing);
}

#[tokio::test]
async fn create_child_task_keeps_durable_child_when_runtime_spawn_fails() {
    let db = open_memory_db();
    create_root(&db, "parent");
    let child_cursor_node_id = create_message_node(&db, None, MessageRole::User, "child cursor");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_factory_effect(FactoryEffectArgs {
        command: FactoryCommand::CreateChildTaskAndRuntime(CreateChildTaskAndRuntimeCommand {
            effect_id: FactoryEffectId("factory-child".to_owned()),
            parent_task_id: TaskId("parent".to_owned()),
            child_cursor_node_id,
        }),
        db: db.clone(),
        router_tx,
        core_spawn_deps: TaskRuntimeSpawnDeps::with_spawner(
            TaskRuntimeConfig {
                mailbox_capacity: 8,
                model_profiles: model_profiles(),
            },
            Arc::new(FailingSpawner),
        ),
    })
    .expect("spawn factory effect");
    handle.await.expect("factory task joins");

    let output = recv_factory_output(&mut router_rx).await;
    let FactoryOutput::Failed(failure) = output else {
        panic!("unexpected factory output");
    };
    assert_eq!(failure.kind, FactoryFailureKind::CoreSpawnFailed);
    let child_task_id = failure.task_id.expect("child task id");
    let child = load_active_task(&db, &child_task_id).expect("child remains durable");
    assert_eq!(child.task.cursor_node_id, child_cursor_node_id);
}

fn create_root(db: &DbPool, task_id: &str) {
    let cursor_node_id = create_message_node(db, None, MessageRole::User, "hello");
    create_root_task(
        db,
        CreateRootTaskInput {
            task_id: TaskId(task_id.to_owned()),
            cursor_node_id,
            model_profile_key: ModelProfileKey("default".to_owned()),
            reasoning_effort: ReasoningEffort::Medium,
            enabled_tools: Vec::new(),
            now: UnixTs(1),
        },
    )
    .expect("create root task");
}

fn create_message_node(
    db: &DbPool,
    parent_node_id: Option<selvedge_db::HistoryNodeId>,
    message_role: MessageRole,
    message_text: &str,
) -> selvedge_db::HistoryNodeId {
    create_history_node(
        db,
        NewHistoryNode {
            parent_node_id,
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role,
                message_text: message_text.to_owned(),
            }),
            created_at: UnixTs(1),
        },
    )
    .expect("create message node")
}

fn model_profiles() -> HashMap<ModelProfileKey, ModelProviderProfile> {
    HashMap::from([(
        ModelProfileKey("default".to_owned()),
        ModelProviderProfile {
            provider_name: "provider".to_owned(),
            model_name: "model".to_owned(),
            temperature: None,
            max_output_tokens: None,
        },
    )])
}

fn open_memory_db() -> DbPool {
    open_db(OpenDbOptions {
        sqlite_path: ":memory:".to_owned(),
    })
    .expect("open db")
}

async fn run_ensure_task_runtime(db: DbPool, task_id: &str) -> FactoryOutput {
    let (router_tx, mut router_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_factory_effect(FactoryEffectArgs {
        command: FactoryCommand::EnsureTaskRuntime(EnsureTaskRuntimeCommand {
            effect_id: FactoryEffectId("factory-1".to_owned()),
            task_id: TaskId(task_id.to_owned()),
        }),
        db,
        router_tx,
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn factory effect");
    handle.await.expect("factory task joins");

    recv_factory_output(&mut router_rx).await
}

async fn run_create_child(
    db: DbPool,
    parent_task_id: &str,
    child_cursor_node_id: selvedge_db::HistoryNodeId,
) -> FactoryOutput {
    let (router_tx, mut router_rx) = tokio::sync::mpsc::channel(8);
    let handle = spawn_factory_effect(FactoryEffectArgs {
        command: FactoryCommand::CreateChildTaskAndRuntime(CreateChildTaskAndRuntimeCommand {
            effect_id: FactoryEffectId("factory-child".to_owned()),
            parent_task_id: TaskId(parent_task_id.to_owned()),
            child_cursor_node_id,
        }),
        db,
        router_tx,
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
    })
    .expect("spawn factory effect");
    handle.await.expect("factory task joins");
    recv_factory_output(&mut router_rx).await
}

async fn recv_factory_output(
    router_rx: &mut tokio::sync::mpsc::Receiver<RouterIngressMessage>,
) -> FactoryOutput {
    let message = router_rx.recv().await.expect("factory output");
    let RouterIngressMessage::Factory(RouterIngressFactoryMessage::Output(envelope)) = message
    else {
        panic!("unexpected router message");
    };
    envelope.output
}

struct FailingSpawner;

impl TaskRuntimeSpawner for FailingSpawner {
    fn spawn_task_runtime(
        &self,
        _args: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
        Err(SpawnTaskRuntimeError::TokioSpawnFailed)
    }
}
