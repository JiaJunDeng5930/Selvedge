use std::collections::HashSet;
use std::sync::Arc;

use selvedge_core::{
    SpawnTaskRuntimeArgs, SpawnTaskRuntimeError, SpawnedTaskRuntime, TaskRuntimeConfig,
    TaskRuntimeSpawnDeps, TaskRuntimeSpawner,
};
use selvedge_db::{TaskId, UnixTs, transition_task_status};
use selvedge_domain_model::TaskLifecycleEvent;
use selvedge_task_runtime_factory::{
    RuntimeCreationError, create_task_runtime, recover_task_runtimes,
};
use selvedge_test_support::db::{
    create_root_task_with_user_message, default_model_profiles, open_memory_db,
};

#[tokio::test]
async fn create_runtime_returns_typed_missing_and_archived_failures() {
    let db = open_memory_db();
    let (router_tx, _router_rx) = tokio::sync::mpsc::unbounded_channel();
    let deps = TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
        model_profiles: default_model_profiles(),
    });
    let missing = create_task_runtime(
        &db,
        &router_tx.downgrade(),
        &deps,
        TaskId("missing".to_owned()),
    );
    assert_eq!(
        missing.expect_err("missing task"),
        RuntimeCreationError::TaskMissing
    );
    create_root_task_with_user_message(&db, "archived", "hello", UnixTs(1));
    transition_task_status(
        &db,
        &TaskId("archived".to_owned()),
        TaskLifecycleEvent::Archive,
        UnixTs(2),
    )
    .expect("archive");
    let archived = create_task_runtime(
        &db,
        &router_tx.downgrade(),
        &deps,
        TaskId("archived".to_owned()),
    );
    assert_eq!(
        archived.expect_err("archived task"),
        RuntimeCreationError::TaskArchived
    );
}

#[tokio::test]
async fn recovery_starts_non_archived_tasks_except_live_inventory() {
    let db = open_memory_db();
    for id in ["live", "active", "frozen", "stopped", "archived"] {
        create_root_task_with_user_message(&db, id, "hello", UnixTs(1));
    }
    for (id, event) in [
        ("frozen", TaskLifecycleEvent::Freeze),
        ("stopped", TaskLifecycleEvent::Stop),
        ("archived", TaskLifecycleEvent::Archive),
    ] {
        transition_task_status(&db, &TaskId(id.to_owned()), event, UnixTs(2)).expect("transition");
    }
    let (router_tx, _router_rx) = tokio::sync::mpsc::unbounded_channel();
    let deps = TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
        model_profiles: default_model_profiles(),
    });
    let recovered = recover_task_runtimes(
        &db,
        &router_tx.downgrade(),
        &deps,
        &HashSet::from([TaskId("live".to_owned())]),
    )
    .expect("recover");
    assert!(recovered.failed.is_empty());
    assert_eq!(
        recovered
            .created
            .iter()
            .map(|runtime| runtime.task_id.0.as_str())
            .collect::<HashSet<_>>(),
        HashSet::from(["active", "frozen", "stopped"])
    );
    for runtime in recovered.created {
        runtime.task_runtime_control.shutdown().await;
    }
}

#[tokio::test]
async fn injected_spawner_failure_is_reported_by_create_and_recovery() {
    let db = open_memory_db();
    create_root_task_with_user_message(&db, "task", "hello", UnixTs(1));
    let (router_tx, _router_rx) = tokio::sync::mpsc::unbounded_channel();
    let deps = TaskRuntimeSpawnDeps::with_spawner(
        TaskRuntimeConfig {
            model_profiles: default_model_profiles(),
        },
        Arc::new(FailingSpawner),
    );
    assert!(matches!(
        create_task_runtime(
            &db,
            &router_tx.downgrade(),
            &deps,
            TaskId("task".to_owned())
        ),
        Err(RuntimeCreationError::CoreSpawnFailed(_))
    ));
    let recovered = recover_task_runtimes(&db, &router_tx.downgrade(), &deps, &HashSet::new())
        .expect("recover");
    assert!(recovered.created.is_empty());
    assert!(
        matches!(recovered.failed.as_slice(), [(TaskId(id), RuntimeCreationError::CoreSpawnFailed(_))] if id == "task")
    );
}

struct FailingSpawner;
impl TaskRuntimeSpawner for FailingSpawner {
    fn spawn_task_runtime(
        &self,
        _: SpawnTaskRuntimeArgs,
    ) -> Result<SpawnedTaskRuntime, SpawnTaskRuntimeError> {
        Err(SpawnTaskRuntimeError::TokioSpawnFailed)
    }
}

#[tokio::test]
async fn pending_command_child_is_held_by_creation_and_recovery() {
    use selvedge_domain_model::{
        CommandEnvironmentMode, CommandInvocationId, CommandOperation, CommandOperationContext,
        CommandOperationId, FunctionCallId, JsonObject, ToolExecutionMode, ToolName,
    };
    let db = open_memory_db();
    let root = create_command_task(&db, "parent");
    let call_id = FunctionCallId("call".into());
    let tool_name = ToolName("exec_cmd".into());
    let call = selvedge_db::append_model_reply_with_tool_calls_and_move_cursor(
        &db,
        &root.task_id,
        None,
        vec![selvedge_db::NewFunctionCallNodeContent {
            function_call_id: call_id.clone(),
            tool_name: tool_name.clone(),
            arguments: JsonObject::new(),
        }],
        UnixTs(2),
    )
    .expect("command operation succeeds")[0];
    let invocation = CommandInvocationId {
        task_id: root.task_id.clone(),
        function_call_node_id: call,
    };
    selvedge_db::admit_command_invocation(&db, &invocation, &call_id, &tool_name)
        .expect("command operation succeeds");
    let context = CommandOperationContext {
        caller_task_id: root.task_id,
        mode: ToolExecutionMode::Normal,
        operation: Some(CommandOperation {
            id: CommandOperationId {
                invocation,
                ordinal: 0,
            },
            command: "tasks.fork".into(),
            arguments: Default::default(),
        }),
    };
    let child = TaskId("child".into());
    selvedge_db::create_pending_command_child(
        &db,
        &context,
        child.clone(),
        CommandEnvironmentMode::Shared,
        vec![],
        UnixTs(3),
    )
    .expect("command operation succeeds");
    let (router_tx, _router_rx) = tokio::sync::mpsc::unbounded_channel();
    let deps = TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
        model_profiles: default_model_profiles(),
    });
    assert_eq!(
        create_task_runtime(&db, &router_tx.downgrade(), &deps, child.clone())
            .expect_err("pending child cannot start"),
        RuntimeCreationError::TaskPending
    );
    let recovered = recover_task_runtimes(&db, &router_tx.downgrade(), &deps, &HashSet::new())
        .expect("command operation succeeds");
    assert!(
        recovered
            .created
            .iter()
            .all(|runtime| runtime.task_id != child)
    );
    for runtime in recovered.created {
        runtime.task_runtime_control.shutdown().await;
    }
}

fn create_command_task(db: &selvedge_db::DbPool, id: &str) -> selvedge_db::TaskRow {
    selvedge_test_support::db::create_root_task_with_user_message_and_tools(
        db,
        id,
        "hello",
        vec![selvedge_db::TaskToolSpec {
            tool: selvedge_domain_model::ToolSpec {
                name: "exec_cmd".into(),
                description: "command".into(),
                input_schema: [("type".into(), "object".into())].into_iter().collect(),
            },
            execution_source: selvedge_db::ToolExecutionSource::Harness,
            recovery_policy: selvedge_db::ToolRecoveryPolicy::RetrySafe,
        }],
        UnixTs(1),
    )
}
