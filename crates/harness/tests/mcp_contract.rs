use std::collections::BTreeMap;
use std::fs;
use std::process;
use std::time::Duration;
use std::time::{SystemTime, UNIX_EPOCH};

use rustix::io::Errno;
use rustix::process::{Pid, test_kill_process};
use selvedge_command_model::{
    RouterIngressMessage, ToolExecutionBranch, ToolExecutionBranchTarget, ToolExecutionRequest,
    ToolExecutionRunId,
};
use selvedge_config_model::McpServerConfig;
use selvedge_db::{DbPool, TaskToolSpec};
use selvedge_domain_model::{FunctionCallId, HistoryNodeId, JsonObject, TaskId, ToolName, UnixTs};
use selvedge_harness::{McpConnectionSet, McpStartupError, ToolExecutor};
use selvedge_router::ToolExecutionSpawner;
use selvedge_test_support::db::{create_root_task_with_user_message_and_tools, open_memory_db};
use serde_json::{Value, json};
use tokio::sync::mpsc;

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/mcp_server.sh");

#[tokio::test]
async fn empty_configuration_has_no_connections_or_registrations() {
    let (connections, registrations) = McpConnectionSet::connect(&BTreeMap::new())
        .await
        .expect("empty MCP configuration");
    assert!(registrations.is_empty());
    connections.close().await;
}

#[tokio::test]
async fn discovery_paginates_and_converts_complete_catalog_routes() {
    let (connections, registrations) = McpConnectionSet::connect(&configs("catalog", 1_000))
        .await
        .expect("connect fixture");

    assert_eq!(registrations.len(), 2);
    assert_eq!(registrations[0].tool.name, "mcp__alpha_beta__echo_value");
    assert_eq!(registrations[0].tool.description, "echoes structured JSON");
    assert_eq!(
        registrations[0].tool.input_schema,
        json!({
            "type": "object",
            "properties": {"value": {}},
            "required": ["value"]
        })
        .as_object()
        .expect("object")
        .clone()
    );
    assert_eq!(
        registrations[0].execution_source,
        selvedge_db::ToolExecutionSource::Mcp {
            server_id: "alpha.beta".to_owned(),
            remote_tool_name: "echo.value".to_owned(),
        }
    );
    assert_eq!(registrations[1].tool.name, "mcp__alpha_beta__fail");
    assert_eq!(
        registrations[1].tool.description,
        "MCP tool 'fail' from server 'alpha.beta'."
    );
    connections.close().await;
}

#[tokio::test]
async fn closing_connections_terminates_mcp_process_group_descendants() {
    let marker = temp_marker("descendant-pid");
    let mut configs = configs("catalog", 1_000);
    configs
        .get_mut("alpha.beta")
        .expect("fixture config")
        .env
        .insert(
            "MCP_DESCENDANT_PID_MARKER".to_owned(),
            marker.to_string_lossy().into_owned(),
        );
    let (connections, _) = McpConnectionSet::connect(&configs)
        .await
        .expect("connect fixture");
    let descendant_pid = fs::read_to_string(&marker)
        .expect("descendant pid marker")
        .parse::<i32>()
        .ok()
        .and_then(Pid::from_raw)
        .expect("descendant pid");

    connections.close().await;

    for _ in 0..50 {
        if matches!(test_kill_process(descendant_pid), Err(Errno::SRCH)) {
            fs::remove_file(&marker).expect("remove descendant marker");
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("MCP process group descendant survived connection shutdown");
}

#[tokio::test]
async fn discovery_rejects_required_task_mode_and_closes_the_started_server() {
    let marker = close_marker();
    let mut configs = configs("required", 1_000);
    configs
        .get_mut("alpha.beta")
        .expect("fixture config")
        .env
        .insert(
            "MCP_CLOSE_MARKER".to_owned(),
            marker.to_string_lossy().into_owned(),
        );
    let error = match McpConnectionSet::connect(&configs).await {
        Err(error) => error,
        Ok((connections, _)) => {
            connections.close().await;
            panic!("required task mode must fail");
        }
    };
    assert!(matches!(
        error,
        McpStartupError::TaskModeRequired {
            server_id,
            remote_tool_name,
        } if server_id == "alpha.beta" && remote_tool_name == "task.only"
    ));
    for _ in 0..50 {
        if marker.exists() {
            assert_eq!(fs::read_to_string(&marker).expect("close marker"), "closed");
            fs::remove_file(&marker).expect("remove close marker");
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    panic!("MCP server did not close after discovery failed");
}

#[tokio::test]
async fn discovery_rejects_colliding_normalized_names() {
    let error = match McpConnectionSet::connect(&configs("collision", 1_000)).await {
        Err(error) => error,
        Ok((connections, _)) => {
            connections.close().await;
            panic!("normalized name collision must fail");
        }
    };
    assert!(matches!(
        error,
        McpStartupError::NormalizedNameCollision {
            local_name,
            first_remote_tool_name,
            second_remote_tool_name,
            ..
        } if local_name == "mcp__alpha_beta__same_name"
            && first_remote_tool_name == "same.name"
            && second_remote_tool_name == "same_name"
    ));
}

#[tokio::test]
async fn discovery_rejects_a_catalog_over_the_cumulative_byte_limit() {
    let error = match McpConnectionSet::connect(&configs("catalog-overflow", 5_000)).await {
        Err(error) => error,
        Ok((connections, _)) => {
            connections.close().await;
            panic!("oversized catalog must fail");
        }
    };
    assert!(matches!(
        error,
        McpStartupError::CatalogLimitExceeded {
            server_id,
            max_tools: 1_024,
            max_bytes: 4_194_304,
        } if server_id == "alpha.beta"
    ));
}

#[tokio::test]
async fn executor_routes_from_the_durable_catalog_and_preserves_full_error_json() {
    let db = open_memory_db();
    let marker = temp_marker("request");
    let mut configs = configs("catalog", 1_000);
    configs
        .get_mut("alpha.beta")
        .expect("fixture config")
        .env
        .insert(
            "MCP_REQUEST_MARKER".to_owned(),
            marker.to_string_lossy().into_owned(),
        );
    let (connections, registrations) = McpConnectionSet::connect(&configs)
        .await
        .expect("connect fixture");
    let executor = mcp_executor(db, connections.clone(), registrations);

    let branch = execute(
        &executor,
        request(
            "mcp__alpha_beta__echo_value",
            JsonObject::from_iter([("value".to_owned(), json!({"original": true}))]),
        ),
    )
    .await;

    assert_eq!(branch.target, ToolExecutionBranchTarget::CallingTask);
    assert!(branch.is_error);
    assert!(branch.messages.is_empty());
    assert_eq!(
        branch.output,
        json!({
            "content": [{"type": "text", "text": "remote failure"}],
            "structuredContent": {"nested": [1, true, null]},
            "isError": true,
            "_meta": {"source": "fixture"}
        })
    );
    let request: Value =
        serde_json::from_str(&fs::read_to_string(&marker).expect("captured request"))
            .expect("request JSON");
    assert_eq!(
        request["params"]["arguments"],
        json!({"value": {"original": true}})
    );
    fs::remove_file(&marker).expect("remove request marker");
    connections.close().await;
}

#[tokio::test]
async fn executor_maps_mcp_timeouts_to_one_correlated_error_branch() {
    let db = open_memory_db();
    let marker = temp_marker("cancel");
    let mut configs = configs("slow", 100);
    configs
        .get_mut("alpha.beta")
        .expect("fixture config")
        .env
        .insert(
            "MCP_CANCEL_MARKER".to_owned(),
            marker.to_string_lossy().into_owned(),
        );
    let (connections, registrations) = McpConnectionSet::connect(&configs)
        .await
        .expect("connect fixture");
    let executor = mcp_executor(db, connections.clone(), registrations);

    let branch = execute(
        &executor,
        request(
            "mcp__alpha_beta__echo_value",
            JsonObject::from_iter([("value".to_owned(), Value::Null)]),
        ),
    )
    .await;

    assert!(branch.is_error);
    assert_eq!(branch.output["error"]["code"], "mcp_call_timed_out");
    for _ in 0..50 {
        if marker.exists() {
            let notification: Value =
                serde_json::from_str(&fs::read_to_string(&marker).expect("captured cancellation"))
                    .expect("cancellation JSON");
            assert_eq!(notification["method"], "notifications/cancelled");
            assert_eq!(notification["params"]["reason"], "request timeout");
            assert!(notification["params"]["requestId"].is_number());
            fs::remove_file(&marker).expect("remove cancellation marker");
            connections.close().await;
            return;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
    connections.close().await;
    panic!("MCP server did not receive cancellation after tool timeout");
}

#[tokio::test]
async fn executor_maps_transport_close_to_one_correlated_error_branch() {
    let db = open_memory_db();
    let (connections, registrations) = McpConnectionSet::connect(&configs("disconnect", 1_000))
        .await
        .expect("connect fixture");
    let executor = mcp_executor(db, connections.clone(), registrations);

    let branch = execute(
        &executor,
        request("mcp__alpha_beta__echo_value", JsonObject::new()),
    )
    .await;

    assert!(branch.is_error);
    assert_eq!(branch.output["error"]["code"], "mcp_call_failed");
    connections.close().await;
}

#[tokio::test]
async fn executor_closes_an_mcp_connection_that_exceeds_the_frame_limit() {
    let db = open_memory_db();
    let (connections, registrations) = McpConnectionSet::connect(&configs("oversize-call", 5_000))
        .await
        .expect("connect fixture");
    let executor = mcp_executor(db, connections.clone(), registrations);

    let branch = execute(
        &executor,
        request("mcp__alpha_beta__echo_value", JsonObject::new()),
    )
    .await;

    assert!(branch.is_error);
    assert_eq!(branch.output["error"]["code"], "mcp_call_failed");
    connections.close().await;
}

#[tokio::test]
async fn executor_maps_missing_durable_route_to_one_correlated_error_branch() {
    let executor = ToolExecutor::new(open_memory_db(), McpConnectionSet::default());

    let branch = execute(&executor, request("missing", JsonObject::new())).await;

    assert!(branch.is_error);
    assert_eq!(branch.output["error"]["code"], "unknown_tool");
}

fn mcp_executor(
    db: DbPool,
    connections: McpConnectionSet,
    tools: Vec<TaskToolSpec>,
) -> ToolExecutor {
    create_root_task_with_user_message_and_tools(&db, "task-1", "hello", tools, UnixTs(1));
    ToolExecutor::new(db, connections)
}

fn configs(mode: &str, timeout_ms: u64) -> BTreeMap<String, McpServerConfig> {
    BTreeMap::from([(
        "alpha.beta".to_owned(),
        McpServerConfig {
            command: "/bin/sh".to_owned(),
            args: vec![FIXTURE.to_owned(), mode.to_owned()],
            env: BTreeMap::new(),
            timeout_ms,
        },
    )])
}

fn close_marker() -> std::path::PathBuf {
    temp_marker("close")
}

fn temp_marker(kind: &str) -> std::path::PathBuf {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock after epoch")
        .as_nanos();
    std::env::temp_dir().join(format!("selvedge-mcp-{kind}-{}-{nonce}", process::id()))
}

async fn execute(executor: &ToolExecutor, request: ToolExecutionRequest) -> ToolExecutionBranch {
    let expected = request.clone();
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();
    executor
        .spawn_tool_execution(request, router_tx.downgrade())
        .expect("spawn tool execution")
        .await
        .expect("supervisor");
    let RouterIngressMessage::Tool(result) =
        tokio::time::timeout(Duration::from_secs(2), router_rx.recv())
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
    assert_eq!(result.branches.len(), 1);
    assert!(matches!(
        router_rx.try_recv(),
        Err(mpsc::error::TryRecvError::Empty)
    ));
    result.branches.into_iter().next().expect("one branch")
}

fn request(tool_name: &str, arguments: JsonObject) -> ToolExecutionRequest {
    ToolExecutionRequest {
        task_id: TaskId("task-1".to_owned()),
        tool_execution_run_id: ToolExecutionRunId("run-1".to_owned()),
        function_call_node_id: HistoryNodeId(7),
        function_call_id: FunctionCallId("call-1".to_owned()),
        tool_name: ToolName(tool_name.to_owned()),
        arguments,
    }
}
