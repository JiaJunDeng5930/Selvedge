use std::fs;
use std::process;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rustix::io::Errno;
use rustix::process::{Pid, test_kill_process, test_kill_process_group};
use selvedge_command_model::{
    RouterIngressMessage, ToolExecutionBranch, ToolExecutionBranchTarget, ToolExecutionRequest,
    ToolExecutionRunId,
};
use selvedge_domain_model::{FunctionCallId, HistoryNodeId, TaskId, ToolName};
use selvedge_harness::{
    BASH_OUTPUT_LIMIT_BYTES, BASH_TOOL_NAME, McpConnectionSet, ToolExecutor, tool_manifest,
};
use selvedge_router::ToolExecutionSpawner;
use selvedge_test_support::db::open_memory_db;
use serde_json::Value;
use tokio::sync::mpsc;
use tokio::time::{sleep, timeout};

#[tokio::test]
async fn bash_reports_zero_nonzero_and_signal_terminal_statuses() {
    let zero = execute(vec![string_argument(
        "command",
        "printf stdout; printf stderr >&2",
    )])
    .await;
    assert!(!zero.is_error);
    assert_eq!(
        zero.output,
        serde_json::json!({
            "exit_code": 0,
            "stderr": "stderr",
            "stderr_truncated": false,
            "stdout": "stdout",
            "stdout_truncated": false
        })
    );

    let nonzero = execute(vec![string_argument(
        "command",
        "printf partial; printf failure >&2; exit 7",
    )])
    .await;
    assert!(!nonzero.is_error);
    assert_eq!(
        nonzero.output,
        serde_json::json!({
            "exit_code": 7,
            "stderr": "failure",
            "stderr_truncated": false,
            "stdout": "partial",
            "stdout_truncated": false
        })
    );

    let signalled = execute(vec![string_argument("command", "kill -TERM $$")]).await;
    assert!(!signalled.is_error);
    assert!(signalled.output["exit_code"].is_null());
}

#[tokio::test]
async fn bash_uses_login_shell_with_server_working_directory_and_environment() {
    let result = execute(vec![string_argument(
        "command",
        "printf '%s\n%s\n' \"$PWD\" \"$CARGO_MANIFEST_DIR\"; shopt -q login_shell",
    )])
    .await;
    assert!(!result.is_error, "bash failed: {}", result.output);
    let output = result.output;
    assert_eq!(output["exit_code"], 0);
    let stdout = output["stdout"].as_str().expect("stdout string");
    let mut lines = stdout.lines();
    assert_eq!(
        lines.next().map(std::path::Path::new),
        Some(
            std::env::current_dir()
                .expect("current directory")
                .as_path()
        )
    );
    assert_eq!(lines.next(), Some(env!("CARGO_MANIFEST_DIR")));
}

#[tokio::test]
async fn bash_drains_large_stdout_and_stderr_concurrently_and_marks_each_prefix() {
    let generated_bytes = BASH_OUTPUT_LIMIT_BYTES + 8192;
    let command = format!(
        "head -c {generated_bytes} /dev/zero | tr '\\0' o & \
         head -c {generated_bytes} /dev/zero | tr '\\0' e >&2 & wait"
    );
    let result = execute(vec![
        string_argument("command", &command),
        integer_argument("timeout_ms", 5_000),
    ])
    .await;
    assert!(!result.is_error, "bash failed: {}", result.output);
    let output = result.output;
    assert_eq!(output["exit_code"], 0);
    assert_eq!(
        output["stdout"].as_str().expect("stdout string").len(),
        BASH_OUTPUT_LIMIT_BYTES
    );
    assert_eq!(
        output["stderr"].as_str().expect("stderr string").len(),
        BASH_OUTPUT_LIMIT_BYTES
    );
    assert_eq!(output["stdout_truncated"], true);
    assert_eq!(output["stderr_truncated"], true);
}

#[tokio::test]
async fn bash_timeout_terminates_the_process_group_and_returns_one_terminal_error() {
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock after epoch")
        .as_nanos();
    let pid_path = std::env::temp_dir().join(format!(
        "selvedge-harness-timeout-{}-{nonce}",
        process::id()
    ));
    let command = format!(
        "sleep 30 & child=$!; printf '%s %s' \"$$\" \"$child\" > '{}'; wait",
        pid_path.display()
    );

    let result = execute(vec![
        string_argument("command", &command),
        integer_argument("timeout_ms", 300),
    ])
    .await;
    assert!(result.is_error);
    assert_eq!(
        result.output,
        serde_json::json!({
            "error": {
                "code": "command_timed_out",
                "message": "bash command timed out after 300 ms"
            }
        })
    );

    let pids = fs::read_to_string(&pid_path).expect("timeout command wrote pids");
    fs::remove_file(&pid_path).expect("remove pid file");
    let mut pids = pids.split_whitespace();
    let process_group_id = parse_pid(pids.next().expect("process group id"));
    let child_pid = parse_pid(pids.next().expect("child pid"));
    for _ in 0..50 {
        if test_kill_process_group(process_group_id) == Err(Errno::SRCH)
            && test_kill_process(child_pid) == Err(Errno::SRCH)
        {
            return;
        }
        sleep(Duration::from_millis(20)).await;
    }
    assert_eq!(test_kill_process_group(process_group_id), Err(Errno::SRCH));
    assert_eq!(test_kill_process(child_pid), Err(Errno::SRCH));
}

async fn execute(arguments: Vec<(String, Value)>) -> ToolExecutionBranch {
    let db = open_memory_db();
    for tool in tool_manifest().tools {
        selvedge_db::register_global_tool(&db, tool).expect("register harness tool");
    }
    let executor = ToolExecutor::new(db, McpConnectionSet::default());
    let request = ToolExecutionRequest {
        task_id: TaskId("task-1".to_owned()),
        tool_execution_run_id: ToolExecutionRunId("run-1".to_owned()),
        function_call_node_id: HistoryNodeId(7),
        function_call_id: FunctionCallId("call-1".to_owned()),
        tool_name: ToolName(BASH_TOOL_NAME.to_owned()),
        arguments: arguments.into_iter().collect(),
    };
    let (router_tx, mut router_rx) = mpsc::unbounded_channel();
    executor
        .spawn_tool_execution(request.clone(), router_tx.downgrade())
        .expect("spawn bash execution")
        .await
        .expect("bash execution supervisor");
    let RouterIngressMessage::Tool(result) = timeout(Duration::from_secs(10), router_rx.recv())
        .await
        .expect("tool result timeout")
        .expect("router channel open")
    else {
        panic!("unexpected router message");
    };
    assert_eq!(result.task_id, request.task_id);
    assert_eq!(result.tool_execution_run_id, request.tool_execution_run_id);
    assert_eq!(result.function_call_node_id, request.function_call_node_id);
    assert_eq!(result.function_call_id, request.function_call_id);
    assert_eq!(result.tool_name, request.tool_name);
    assert_eq!(result.branches.len(), 1);
    assert!(matches!(
        router_rx.try_recv(),
        Err(mpsc::error::TryRecvError::Empty)
    ));
    let branch = result.branches.into_iter().next().expect("calling branch");
    assert_eq!(branch.target, ToolExecutionBranchTarget::CallingTask);
    assert!(branch.messages.is_empty());
    branch
}

fn string_argument(name: &str, value: &str) -> (String, Value) {
    (name.to_owned(), Value::String(value.to_owned()))
}

fn integer_argument(name: &str, value: i64) -> (String, Value) {
    (name.to_owned(), Value::from(value))
}

fn parse_pid(value: &str) -> Pid {
    value
        .parse::<i32>()
        .ok()
        .and_then(Pid::from_raw)
        .expect("valid process id")
}
