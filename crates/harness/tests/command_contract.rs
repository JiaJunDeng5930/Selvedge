use std::time::Duration;

use selvedge_command_model::{
    RouterCommand, RouterIngressMessage, ToolExecutionBranchTarget, ToolExecutionRequest,
    ToolExecutionResult, ToolExecutionRunId,
};
use selvedge_db::*;
use selvedge_domain_model::{CommandOperation, CommandOperationId};
use selvedge_harness::{
    EXEC_CMD_TOOL_NAME, FORK_TASK_TOOL_NAME, McpConnectionSet, ToolExecutor, harness_tool_catalog,
};
use selvedge_router::ToolExecutionSpawner;
use selvedge_test_support::db::{create_root_task_with_user_message_and_tools, open_memory_db};
use serde_json::{Value, json};
use tokio::sync::mpsc;

struct Fixture {
    db: DbPool,
    executor: ToolExecutor,
}
impl Fixture {
    fn new() -> Self {
        let db = open_memory_db();
        create_root_task_with_user_message_and_tools(
            &db,
            "root",
            "test",
            harness_tool_catalog(&Default::default()),
            now(),
        );
        Self {
            executor: ToolExecutor::new(db.clone(), McpConnectionSet::default()),
            db,
        }
    }
    fn request(&self, task: &str, tool: &str, arguments: Value) -> ToolExecutionRequest {
        let task_id = TaskId(task.into());
        let tool_name = ToolName(tool.into());
        let function_call_id = FunctionCallId(uuid::Uuid::new_v4().to_string());
        let arguments = arguments
            .as_object()
            .expect("object command arguments")
            .iter()
            .map(|(key, value)| (key.clone(), value.clone()))
            .collect();
        let call = NewFunctionCallNodeContent {
            function_call_id: function_call_id.clone(),
            tool_name: tool_name.clone(),
            arguments,
        };
        let args = call.arguments.clone();
        let node = append_model_reply_with_tool_calls_and_move_cursor(
            &self.db,
            &task_id,
            None,
            vec![call],
            now(),
        )
        .expect("persist open function call")[0];
        ToolExecutionRequest {
            task_id,
            tool_name,
            function_call_id,
            arguments: args,
            function_call_node_id: node,
            tool_execution_run_id: ToolExecutionRunId(uuid::Uuid::new_v4().to_string()),
            execution_mode: ToolExecutionMode::Normal,
        }
    }
    async fn execute(&self, request: ToolExecutionRequest) -> ToolExecutionResult {
        let (tx, mut rx) = mpsc::unbounded_channel();
        let handle = self
            .executor
            .spawn_tool_execution(request, tx.downgrade())
            .expect("spawn command execution");
        let result =
            tokio::time::timeout(Duration::from_secs(35), async {
                loop {
                    match rx.recv().await.expect("router remains connected") {
                        RouterIngressMessage::Tool(result) => break result,
                        RouterIngressMessage::Command(RouterCommand::SendTaskInput {
                            task_id,
                            message_text,
                            context,
                            responder,
                        }) => {
                            let value = queue_user_input_with_context(
                                &self.db,
                                &task_id,
                                message_text,
                                now(),
                                &context,
                                json!({"disposition":"queued"}),
                            );
                            responder.settle(value.map(|value| value.result).map_err(|_| {
                                selvedge_command_model::TaskCommandError::InvalidCommand
                            }));
                        }
                        RouterIngressMessage::Command(RouterCommand::ChangeTaskStatus {
                            task_id,
                            event,
                            context,
                            responder,
                        }) => {
                            let value = transition_task_status_with_context(
                                &self.db,
                                &task_id,
                                event,
                                now(),
                                &context,
                                json!({"ok":true}),
                            );
                            responder.settle(value.map(|value| value.result).map_err(|_| {
                                selvedge_command_model::TaskCommandError::InvalidCommand
                            }));
                        }
                        other => panic!("unexpected router request: {other:?}"),
                    }
                }
            })
            .await
            .expect("execution completes");
        handle.await.expect("join execution supervisor");
        result
    }
    fn commit(&self, result: ToolExecutionResult) {
        let prepared = result
            .prepared_environment
            .as_ref()
            .expect("prepared environment");
        let input = CommitToolResultBranchesInput {
            calling_task_id: result.task_id.clone(),
            function_call_node_id: result.function_call_node_id,
            function_call_id: result.function_call_id.clone(),
            tool_name: result.tool_name.clone(),
            now: now(),
            branches: result
                .branches
                .iter()
                .map(|branch| ToolResultBranch {
                    target: match &branch.target {
                        ToolExecutionBranchTarget::CallingTask => {
                            ToolResultBranchTarget::CallingTask
                        }
                        ToolExecutionBranchTarget::NewChildTask { task_id } => {
                            ToolResultBranchTarget::NewChildTask(task_id.clone())
                        }
                    },
                    output: branch.output.clone(),
                    is_error: branch.is_error,
                    user_messages: branch.messages.clone(),
                })
                .collect(),
        };
        commit_tool_result_branches_with_environment(&self.db, input, &prepared.commit)
            .expect("atomically commit prepared environment");
    }
    async fn run(&self, task: &str, source: &str) -> Value {
        let result = self
            .execute(self.request(task, EXEC_CMD_TOOL_NAME, json!({"code":source})))
            .await;
        assert!(
            !result.branches[0].is_error,
            "{}",
            result.branches[0].output
        );
        let value = result.branches[0].output["value"].clone();
        self.commit(result);
        value
    }
}

#[tokio::test]
async fn ordinary_fork_shares_copies_or_resets_committed_closures() {
    let fixture = Fixture::new();
    fixture
        .run(
            "root",
            "let count = 1; function bump() { return ++count; }; count",
        )
        .await;
    for (mode, expected) in [("shared", 2), ("copy", 3), ("new", 0)] {
        let result = fixture
            .execute(fixture.request(
                "root",
                FORK_TASK_TOOL_NAME,
                json!({"child_count":1,"environment":mode}),
            ))
            .await;
        assert!(!result.branches[0].is_error, "{:?}", result.branches);
        let ToolExecutionBranchTarget::NewChildTask { task_id } = result.branches[1].target.clone()
        else {
            panic!()
        };
        fixture.commit(result);
        let value = fixture
            .run(&task_id.0, "typeof bump === 'undefined' ? 0 : bump()")
            .await;
        assert_eq!(value, expected);
    }
    assert_eq!(fixture.run("root", "count").await, 2);
}

#[tokio::test]
async fn script_fork_is_readable_and_sendable_before_commit_and_copies_final_state() {
    let fixture = Fixture::new();
    let mut request = fixture.request("root", EXEC_CMD_TOOL_NAME, json!({"code":
        "let count = 1; const created = await tasks.fork({child_count:1,environment:'copy'}); const child = created.children[0]; await tasks.send({task_id:child,message:'hello'}); const before = await tasks.read({task_id:child}); count=7; ({child, queued:before.queued_message_count})"}));
    request.execution_mode = ToolExecutionMode::Startup;
    let result = fixture.execute(request).await;
    assert!(
        !result.branches[0].is_error,
        "{}",
        result.branches[0].output
    );
    let value = result.branches[0].output["value"].clone();
    let child = value["child"].as_str().expect("child task id");
    assert_eq!(value["queued"], 1);
    assert!(
        task_is_pending(&fixture.db, &TaskId(child.into())).expect("pending child before commit")
    );
    fixture.commit(result);
    assert!(
        !task_is_pending(&fixture.db, &TaskId(child.into())).expect("published child after commit")
    );
    assert_eq!(fixture.run(child, "count").await, 7);
}

#[tokio::test]
async fn startup_external_denials_are_errors_and_leave_files_untouched() {
    let fixture = Fixture::new();
    let path = std::env::temp_dir().join(format!("selvedge-denied-{}", uuid::Uuid::new_v4()));
    let source = format!(
        "await tools.exec_bash({{command:'touch {}'}}); await tools.write_file({{path:{},content:'x'}})",
        path.display(),
        serde_json::to_string(&path).expect("encode path")
    );
    let mut request = fixture.request("root", EXEC_CMD_TOOL_NAME, json!({"code":source}));
    request.execution_mode = ToolExecutionMode::Startup;
    let result = fixture.execute(request).await;
    assert!(result.branches[0].is_error);
    assert!(!path.exists());
    fixture.commit(result);
}

#[tokio::test]
async fn interrupted_fork_replay_reuses_child_and_applies_script_state_once() {
    let fixture = Fixture::new();
    fixture.run("root", "let count=0").await;
    let request = fixture.request(
        "root",
        EXEC_CMD_TOOL_NAME,
        json!({"code":"count++; await tasks.fork({child_count:1})"}),
    );
    let first = fixture.execute(request.clone()).await;
    assert!(!first.branches[0].is_error, "{}", first.branches[0].output);
    let children = first.branches[0].output["value"]["children"].clone();
    drop(first); // Simulate interruption between execution and the core's atomic commit.
    let mut retry = request;
    retry.execution_mode = ToolExecutionMode::Startup;
    let second = fixture.execute(retry).await;
    assert_eq!(second.branches[0].output["value"]["children"], children);
    fixture.commit(second);
    assert_eq!(fixture.run("root", "count").await, 1);
    assert_eq!(
        list_runtime_tasks(&fixture.db)
            .expect("list tasks after replay")
            .len(),
        2
    );
}

#[tokio::test]
async fn replay_mismatch_and_skipped_prefix_keep_committed_state() {
    for source in [
        "count=8; try { await tasks.read({limit:2}) } catch (_) {}; await tasks.fork({child_count:1})",
        "count=9; 42",
    ] {
        let fixture = Fixture::new();
        fixture.run("root", "let count=1").await;
        let request = fixture.request("root", EXEC_CMD_TOOL_NAME, json!({"code":source}));
        let invocation = CommandInvocationId {
            task_id: request.task_id.clone(),
            function_call_node_id: request.function_call_node_id,
        };
        admit_command_invocation(
            &fixture.db,
            &invocation,
            &request.function_call_id,
            &request.tool_name,
        )
        .expect("admit interrupted invocation");
        let context = CommandOperationContext {
            caller_task_id: request.task_id.clone(),
            mode: ToolExecutionMode::Normal,
            operation: Some(CommandOperation {
                id: CommandOperationId {
                    invocation,
                    ordinal: 0,
                },
                command: "tasks.read".into(),
                arguments: json!({"limit":1}),
            }),
        };
        save_command_observation(&fixture.db, &context, json!({"saved":true}))
            .expect("record previous host observation");
        let result = fixture.execute(request).await;
        assert!(result.branches[0].is_error);
        assert_eq!(
            result.branches[0].output["error"]["code"],
            "command_replay_mismatch"
        );
        fixture.commit(result);
        assert_eq!(fixture.run("root", "count").await, 1);
        assert_eq!(
            list_runtime_tasks(&fixture.db)
                .expect("list tasks after mismatch")
                .len(),
            1
        );
    }
}

#[tokio::test]
async fn copied_async_function_uses_current_caller_and_shared_state_outlives_parent() {
    let fixture = Fixture::new();
    let child = fixture.run("root", "async function identify() { await Promise.resolve(); return await tasks.read(); }; const group = await tasks.fork({child_count:1}); group.children[0]").await;
    let child = child.as_str().expect("child task id");
    assert_eq!(
        fixture.run(child, "(await identify()).task_id").await,
        child
    );
    let denied = fixture
        .execute(fixture.request(
            child,
            EXEC_CMD_TOOL_NAME,
            json!({"code":"await Promise.resolve(); await tasks.archive({task_id:'root'})"}),
        ))
        .await;
    assert!(denied.branches[0].is_error);
    fixture.commit(denied);
    transition_task_status(
        &fixture.db,
        &TaskId("root".into()),
        TaskLifecycleEvent::Archive,
        now(),
    )
    .expect("archive original parent");
    assert_eq!(
        fixture.run(child, "(await identify()).task_id").await,
        child
    );
}

#[tokio::test]
async fn shared_task_waits_for_prepared_environment_commit() {
    let fixture = Fixture::new();
    let child = fixture
        .run(
            "root",
            "let count=0; (await tasks.fork({child_count:1})).children[0]",
        )
        .await;
    let child = child.as_str().expect("shared child task id");
    let first = fixture
        .execute(fixture.request("root", EXEC_CMD_TOOL_NAME, json!({"code":"count=5"})))
        .await;
    assert!(!first.branches[0].is_error);
    let request = fixture.request(child, EXEC_CMD_TOOL_NAME, json!({"code":"count"}));
    let (tx, mut rx) = mpsc::unbounded_channel();
    let handle = fixture
        .executor
        .spawn_tool_execution(request, tx.downgrade())
        .expect("spawn shared child invocation");
    assert!(
        tokio::time::timeout(Duration::from_millis(50), rx.recv())
            .await
            .is_err()
    );
    fixture.commit(first);
    let RouterIngressMessage::Tool(second) =
        tokio::time::timeout(Duration::from_secs(35), rx.recv())
            .await
            .expect("shared invocation completes")
            .expect("terminal tool result")
    else {
        panic!("expected tool result")
    };
    assert_eq!(second.branches[0].output["value"], 5);
    handle.await.expect("join shared execution");
    fixture.commit(second);
}

#[tokio::test]
async fn module_state_and_source_survive_environment_copy() {
    let fixture = Fixture::new();
    let path = std::env::temp_dir().join(format!("selvedge-module-{}.js", uuid::Uuid::new_v4()));
    std::fs::write(
        &path,
        "let value=0; exports.increment = function increment() { return ++value; };",
    )
    .expect("create local module fixture");
    let source = format!(
        "const extension = await modules.load({}); extension.increment()",
        serde_json::to_string(&path).expect("encode module path")
    );
    assert_eq!(fixture.run("root", &source).await, 1);
    let child = fixture
        .run(
            "root",
            "(await tasks.fork({child_count:1,environment:'copy'})).children[0]",
        )
        .await;
    let child = child.as_str().expect("copied child task id");
    std::fs::remove_file(&path).expect("remove loaded module file");
    assert_eq!(fixture.run(child, "extension.increment()").await, 2);
    assert_eq!(fixture.run("root", "extension.increment()").await, 2);
    assert!(
        fixture
            .run(child, "extension.increment.toString()")
            .await
            .as_str()
            .expect("source is a string")
            .contains("++value")
    );
}

#[tokio::test]
async fn completed_shell_effect_is_replayed_on_startup_without_reexecution() {
    let fixture = Fixture::new();
    let path = std::env::temp_dir().join(format!("selvedge-shell-replay-{}", uuid::Uuid::new_v4()));
    let command = format!("printf x >> '{}'", path.display());
    let source = format!("await tools.exec_bash({})", json!({"command":command}));
    let request = fixture.request("root", EXEC_CMD_TOOL_NAME, json!({"code":source}));
    let first = fixture.execute(request.clone()).await;
    assert!(!first.branches[0].is_error, "{}", first.branches[0].output);
    drop(first);
    let mut retry = request;
    retry.execution_mode = ToolExecutionMode::Startup;
    let second = fixture.execute(retry).await;
    assert!(
        !second.branches[0].is_error,
        "{}",
        second.branches[0].output
    );
    fixture.commit(second);
    assert_eq!(
        std::fs::read_to_string(&path).expect("read shell side effect"),
        "x"
    );
    std::fs::remove_file(path).expect("remove shell output fixture");
}

#[tokio::test]
async fn missing_module_is_catchable_and_preserves_settled_state() {
    let fixture = Fixture::new();
    let path = std::env::temp_dir().join(format!("selvedge-missing-{}.js", uuid::Uuid::new_v4()));
    let source = format!(
        "let value=1; try {{ await modules.load({}); }} catch (_) {{ value=2; }}; value",
        serde_json::to_string(&path).expect("encode missing module path")
    );
    let result = fixture
        .execute(fixture.request("root", EXEC_CMD_TOOL_NAME, json!({"code":source})))
        .await;
    assert!(result.branches[0].is_error);
    assert_eq!(result.branches[0].output["value"], 2);
    fixture.commit(result);
    assert_eq!(fixture.run("root", "value").await, 2);
}

#[tokio::test]
async fn self_archive_takes_effect_only_with_outer_output() {
    let fixture = Fixture::new();
    let result = fixture
        .execute(fixture.request(
            "root",
            EXEC_CMD_TOOL_NAME,
            json!({"code":"await tasks.archive(); (await tasks.read()).status"}),
        ))
        .await;
    assert!(
        !result.branches[0].is_error,
        "{}",
        result.branches[0].output
    );
    assert_eq!(result.branches[0].output["value"], "active");
    let task_id = TaskId("root".into());
    let read = || {
        read_task(
            &fixture.db,
            ReadTaskInput {
                task_id: task_id.clone(),
                after_node_id: None,
                limit: 100,
            },
        )
        .expect("read task lifecycle")
    };
    assert_eq!(read().task_status, TaskStatus::Active);
    fixture.commit(result);
    assert_eq!(read().task_status, TaskStatus::Archived);
}

fn now() -> UnixTs {
    UnixTs(
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("system clock after Unix epoch")
            .as_secs() as i64,
    )
}

#[tokio::test]
async fn admitted_invocation_finalizes_even_when_its_tool_becomes_unavailable() {
    let fixture = Fixture::new();
    fixture.run("root", "let count=1").await;
    let request = fixture.request("root", EXEC_CMD_TOOL_NAME, json!({"code":"count=2"}));
    let first = fixture.execute(request.clone()).await;
    assert!(first.prepared_environment.is_some());
    drop(first);
    let tools = harness_tool_catalog(&Default::default())
        .into_iter()
        .filter(|tool| tool.tool.name != EXEC_CMD_TOOL_NAME)
        .collect();
    reconcile_task_tool_availability(&fixture.db, tools).expect("mark command tool unavailable");
    let retry = fixture.execute(request).await;
    assert!(retry.branches[0].is_error);
    assert_eq!(
        retry.branches[0].output["error"]["code"],
        "tool_unavailable"
    );
    fixture.commit(retry);
    let row = read_command_environment(&fixture.db, &TaskId("root".into()))
        .expect("read finalized environment");
    assert!(row.admitted_invocation.is_none());
    reconcile_task_tool_availability(&fixture.db, harness_tool_catalog(&Default::default()))
        .expect("restore tool availability");
    assert_eq!(fixture.run("root", "count").await, 1);
}
