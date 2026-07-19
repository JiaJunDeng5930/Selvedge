use std::time::Duration;

use selvedge_command_model::{
    RouterIngressMessage, ToolExecutionBranchTarget, ToolExecutionRequest, ToolExecutionResult,
    ToolExecutionRunId,
};
use selvedge_db::{DbPool, register_global_tool};
use selvedge_domain_model::{FunctionCallId, HistoryNodeId, JsonObject, TaskId, ToolName, UnixTs};
use selvedge_harness::{
    FORK_TASK_TOOL_NAME, McpConnectionSet, READ_TASK_TOOL_NAME, ToolExecutor, tool_manifest,
};
use selvedge_router::ToolExecutionSpawner;
use selvedge_test_support::db::{create_root_task_with_user_message, open_memory_db};
use serde_json::Value;
use tokio::sync::mpsc;

#[tokio::test]
async fn fork_executor_returns_numbered_branches_and_aligned_messages() {
    let db = open_memory_db();
    let executor = executor(db.clone());
    let result = execute(
        &executor,
        request(
            FORK_TASK_TOOL_NAME,
            vec![
                ("child_count".to_owned(), Value::from(3)),
                (
                    "messages".to_owned(),
                    Value::Array(vec![
                        Value::String("research".to_owned()),
                        Value::String("implement".to_owned()),
                        Value::String("review".to_owned()),
                    ]),
                ),
            ],
        ),
    )
    .await;

    assert_eq!(result.branches.len(), 4);
    assert_eq!(
        result.branches[0].target,
        ToolExecutionBranchTarget::CallingTask
    );
    assert_eq!(result.branches[0].output, Value::from(0));
    assert!(!result.branches[0].is_error);
    assert!(result.branches[0].messages.is_empty());

    let mut child_ids = Vec::new();
    for (index, branch) in result.branches[1..].iter().enumerate() {
        let ToolExecutionBranchTarget::NewChildTask { task_id } = &branch.target else {
            panic!("expected child branch");
        };
        child_ids.push(task_id.clone());
        assert_eq!(branch.output, Value::from(index + 1));
        assert!(!branch.is_error);
    }
    assert_eq!(result.branches[1].messages, vec!["research"]);
    assert_eq!(result.branches[2].messages, vec!["implement"]);
    assert_eq!(result.branches[3].messages, vec!["review"]);
    child_ids.sort();
    child_ids.dedup();
    assert_eq!(child_ids.len(), 3);
    assert!(
        selvedge_db::list_active_tasks(&db)
            .expect("list active tasks")
            .is_empty()
    );
}

#[tokio::test]
async fn fork_without_messages_leaves_child_follow_up_messages_empty() {
    let executor = executor(open_memory_db());
    let result = execute(
        &executor,
        request(
            FORK_TASK_TOOL_NAME,
            vec![("child_count".to_owned(), Value::from(2))],
        ),
    )
    .await;

    assert_eq!(result.branches.len(), 3);
    assert!(
        result
            .branches
            .iter()
            .all(|branch| branch.messages.is_empty())
    );
}

#[tokio::test]
async fn ordinary_tool_returns_one_calling_task_branch() {
    let db = open_memory_db();
    create_root_task_with_user_message(&db, "task-1", "hello", UnixTs(1));
    let executor = executor(db);
    let result = execute(&executor, request(READ_TASK_TOOL_NAME, Vec::new())).await;

    assert_eq!(result.branches.len(), 1);
    let branch = &result.branches[0];
    assert_eq!(branch.target, ToolExecutionBranchTarget::CallingTask);
    assert!(!branch.is_error);
    assert!(branch.messages.is_empty());
    assert_eq!(branch.output["task_id"], "task-1");
    assert_eq!(branch.output["status"], "active");
}

async fn execute(executor: &ToolExecutor, request: ToolExecutionRequest) -> ToolExecutionResult {
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();
    let expected = request.clone();
    executor
        .spawn_tool_execution(request, router_tx.downgrade())
        .expect("spawn tool execution")
        .await
        .expect("tool execution supervisor");
    let RouterIngressMessage::Tool(result) =
        tokio::time::timeout(Duration::from_secs(1), router_rx.recv())
            .await
            .expect("tool result timeout")
            .expect("router channel open")
    else {
        panic!("unexpected router message");
    };
    assert_eq!(result.task_id, expected.task_id);
    assert_eq!(result.tool_execution_run_id, expected.tool_execution_run_id);
    assert_eq!(result.function_call_node_id, expected.function_call_node_id);
    assert_eq!(result.function_call_id, expected.function_call_id);
    assert_eq!(result.tool_name, expected.tool_name);
    assert!(matches!(
        router_rx.try_recv(),
        Err(mpsc::error::TryRecvError::Empty)
    ));
    result
}

fn executor(db: DbPool) -> ToolExecutor {
    for tool in tool_manifest().tools {
        register_global_tool(&db, tool).expect("register harness tool");
    }
    ToolExecutor::new(db, McpConnectionSet::default())
}

fn request(tool_name: &str, arguments: Vec<(String, Value)>) -> ToolExecutionRequest {
    ToolExecutionRequest {
        task_id: TaskId("task-1".to_owned()),
        tool_execution_run_id: ToolExecutionRunId("run-1".to_owned()),
        function_call_node_id: HistoryNodeId(7),
        function_call_id: FunctionCallId("call-1".to_owned()),
        tool_name: ToolName(tool_name.to_owned()),
        arguments: JsonObject::from_iter(arguments),
    }
}
