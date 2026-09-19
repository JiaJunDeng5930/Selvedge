use selvedge_db::*;
use selvedge_domain_model::{CommandOperation, CommandOperationId};
use serde_json::{Value, json};
use std::sync::Arc;

fn database() -> DbPool {
    open_db(OpenDbOptions {
        sqlite_path: ":memory:".into(),
        max_children_per_fork: 4,
        max_task_descendants: 20,
    })
    .expect("valid command contract operation")
}
fn root(db: &DbPool, name: &str) -> TaskId {
    let node = create_history_node(
        db,
        NewHistoryNode {
            parent_node_id: None,
            content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                message_role: MessageRole::User,
                message_text: "run".into(),
            }),
            created_at: UnixTs(1),
        },
    )
    .expect("valid command contract operation");
    create_root_task(
        db,
        CreateRootTaskInput {
            task_id: TaskId(name.into()),
            cursor_node_id: node,
            model_config: Arc::new(
                TaskModelConfig::new(ModelProfileKey("default".into()), ReasoningEffort::Medium)
                    .expect("valid command contract operation"),
            ),
            tools: vec![TaskToolSpec {
                tool: ToolSpec {
                    name: "exec_cmd".into(),
                    description: "run".into(),
                    input_schema: JsonObject::new(),
                },
                execution_source: ToolExecutionSource::Harness,
                recovery_policy: ToolRecoveryPolicy::RetrySafe,
            }],
            now: UnixTs(1),
        },
    )
    .expect("valid command contract operation")
    .task_id
}
fn invocation(db: &DbPool, task: &TaskId, id: &str) -> CommandInvocationId {
    let nodes = append_model_reply_with_tool_calls_and_move_cursor(
        db,
        task,
        None,
        vec![NewFunctionCallNodeContent {
            function_call_id: FunctionCallId(id.into()),
            tool_name: ToolName("exec_cmd".into()),
            arguments: JsonObject::new(),
        }],
        UnixTs(2),
    )
    .expect("valid command contract operation");
    let invocation = CommandInvocationId {
        task_id: task.clone(),
        function_call_node_id: nodes[0],
    };
    admit_command_invocation(
        db,
        &invocation,
        &FunctionCallId(id.into()),
        &ToolName("exec_cmd".into()),
    )
    .expect("valid command contract operation");
    invocation
}
fn context(
    inv: &CommandInvocationId,
    ordinal: u64,
    name: &str,
    arguments: Value,
) -> CommandOperationContext {
    CommandOperationContext {
        caller_task_id: inv.task_id.clone(),
        mode: ToolExecutionMode::Normal,
        operation: Some(CommandOperation {
            id: CommandOperationId {
                invocation: inv.clone(),
                ordinal,
            },
            command: name.into(),
            arguments,
        }),
    }
}
fn finish(
    db: &DbPool,
    inv: &CommandInvocationId,
    id: &str,
    is_error: bool,
) -> Result<CommitToolResultBranchesResult, DbError> {
    let env = read_command_environment(db, &inv.task_id)?;
    commit_tool_result_branches_with_environment(
        db,
        CommitToolResultBranchesInput {
            calling_task_id: inv.task_id.clone(),
            function_call_node_id: inv.function_call_node_id,
            function_call_id: FunctionCallId(id.into()),
            tool_name: ToolName("exec_cmd".into()),
            branches: vec![ToolResultBranch {
                target: ToolResultBranchTarget::CallingTask,
                output: json!("done"),
                is_error,
                user_messages: vec![],
            }],
            now: UnixTs(9),
        },
        &CommandEnvironmentCommit {
            new_child_environment_mode: CommandEnvironmentMode::Shared,
            environment_id: env.environment_id,
            invocation: inv.clone(),
            expected_revision: env.revision,
            checkpoint: vec![1, 2, 3],
            base_checkpoint: vec![0],
        },
    )
}
#[test]
fn effect_and_saved_result_replay_once_and_reject_mismatch() {
    let db = database();
    let task = root(&db, "root");
    let inv = invocation(&db, &task, "c1");
    let ctx = context(&inv, 0, "send", json!({"task":"root","message":"hello"}));
    assert!(
        !queue_user_input_with_context(
            &db,
            &task,
            "hello".into(),
            UnixTs(3),
            &ctx,
            json!({"queued":true})
        )
        .expect("valid command contract operation")
        .replayed
    );
    assert!(
        queue_user_input_with_context(&db, &task, "hello".into(), UnixTs(3), &ctx, Value::Null)
            .expect("valid command contract operation")
            .replayed
    );
    assert_eq!(
        load_runtime_task(&db, &task)
            .expect("valid command contract operation")
            .queued_input_count,
        1
    );
    let changed = context(&inv, 0, "send", json!({"task":"root","message":"changed"}));
    assert_eq!(
        queue_user_input_with_context(
            &db,
            &task,
            "changed".into(),
            UnixTs(4),
            &changed,
            Value::Null
        )
        .expect_err("reject mismatched replay"),
        DbError::CommandOperationMismatch
    );
    assert_eq!(
        load_runtime_task(&db, &task)
            .expect("valid command contract operation")
            .queued_input_count,
        1
    );
}
#[test]
fn pending_forks_are_readable_writable_and_finalize_on_error_with_modes() {
    let db = database();
    let task = root(&db, "root");
    let inv = invocation(&db, &task, "c1");
    for (i, mode) in [
        CommandEnvironmentMode::Shared,
        CommandEnvironmentMode::Copy,
        CommandEnvironmentMode::New,
    ]
    .into_iter()
    .enumerate()
    {
        let child = TaskId(format!("child{i}"));
        let ctx = context(&inv, i as u64, "fork", json!(i));
        create_pending_command_children(
            &db,
            &ctx,
            vec![(child.clone(), vec!["initial".into()])],
            mode,
            UnixTs(3),
        )
        .expect("valid command contract operation");
        assert!(task_is_pending(&db, &child).expect("valid command contract operation"));
        assert!(load_runtime_task(&db, &child).is_err());
        let send = context(&inv, 10 + i as u64, "send", json!(child.0));
        queue_user_input_with_context(&db, &child, "next".into(), UnixTs(4), &send, json!(true))
            .expect("valid command contract operation");
        assert_eq!(
            read_task_metadata(&db, &child)
                .expect("valid command contract operation")
                .task_id,
            child
        );
    }
    assert_eq!(
        list_runtime_tasks(&db)
            .expect("valid command contract operation")
            .len(),
        1
    );
    let result = finish(&db, &inv, "c1", true).expect("valid command contract operation");
    assert_eq!(result.created_child_task_ids.len(), 3);
    let parent = read_command_environment(&db, &task).expect("valid command contract operation");
    assert_eq!(parent.checkpoint, vec![1, 2, 3]);
    assert_eq!(parent.revision, 1);
    let shared = read_command_environment(&db, &TaskId("child0".into()))
        .expect("valid command contract operation");
    let copied = read_command_environment(&db, &TaskId("child1".into()))
        .expect("valid command contract operation");
    let new = read_command_environment(&db, &TaskId("child2".into()))
        .expect("valid command contract operation");
    assert_eq!(parent.environment_id, shared.environment_id);
    assert_ne!(parent.environment_id, copied.environment_id);
    assert_eq!(copied.checkpoint, parent.checkpoint);
    assert_eq!(new.checkpoint, vec![0]);
    for child in result.created_child_task_ids {
        assert!(!task_is_pending(&db, &child).expect("valid command contract operation"));
        assert_eq!(
            load_runtime_task(&db, &child)
                .expect("valid command contract operation")
                .queued_input_count,
            0
        );
    }
    transition_task_status(&db, &task, TaskLifecycleEvent::Archive, UnixTs(10))
        .expect("valid command contract operation");
    assert_eq!(
        read_command_environment(&db, &TaskId("child0".into()))
            .expect("valid command contract operation")
            .checkpoint,
        vec![1, 2, 3]
    );
}
#[test]
fn invalid_output_rolls_back_checkpoint_and_pending_child_finalization() {
    let db = database();
    let task = root(&db, "root");
    let inv = invocation(&db, &task, "c1");
    let child = TaskId("child".into());
    create_pending_command_child(
        &db,
        &context(&inv, 0, "fork", json!({})),
        child.clone(),
        CommandEnvironmentMode::Copy,
        vec![],
        UnixTs(3),
    )
    .expect("valid command contract operation");
    assert!(finish(&db, &inv, "wrong-id", false).is_err());
    let env = read_command_environment(&db, &task).expect("valid command contract operation");
    assert!(env.checkpoint.is_empty());
    assert_eq!(env.revision, 0);
    assert_eq!(env.admitted_invocation, Some(inv.clone()));
    assert!(task_is_pending(&db, &child).expect("valid command contract operation"));
    finish(&db, &inv, "c1", false).expect("valid command contract operation");
}
#[test]
fn external_effect_admission_is_not_retry_safe_and_observations_replay() {
    let db = database();
    let task = root(&db, "root");
    let inv = invocation(&db, &task, "c1");
    let mut ctx = context(&inv, 0, "shell", json!("ls"));
    assert_eq!(
        admit_external_command_operation(&db, &ctx).expect("valid command contract operation"),
        CommandOperationAdmission::Execute
    );
    ctx.mode = ToolExecutionMode::Startup;
    assert_eq!(
        admit_external_command_operation(&db, &ctx).expect("valid command contract operation"),
        CommandOperationAdmission::OutcomeUnknown
    );
    complete_external_command_operation(&db, &ctx, json!("saved"))
        .expect("valid command contract operation");
    assert_eq!(
        admit_external_command_operation(&db, &ctx).expect("valid command contract operation"),
        CommandOperationAdmission::Completed(json!("saved"))
    );
    let mut denied = context(&inv, 1, "shell", json!("touch file"));
    denied.mode = ToolExecutionMode::Startup;
    assert!(admit_external_command_operation(&db, &denied).is_err());
    let observation = context(&inv, 7, "module", json!("a.js"));
    save_command_observation(&db, &observation, json!("original source"))
        .expect("valid command contract operation");
    assert_eq!(
        save_command_observation(&db, &observation, json!("changed source"))
            .expect("valid command contract operation")
            .result,
        json!("original source")
    );
    assert_eq!(
        command_operation_replay_length(&db, &inv).expect("valid command contract operation"),
        8
    );
}
#[test]
fn scope_is_checked_in_transaction_and_self_lifecycle_is_deferred() {
    let db = database();
    let task = root(&db, "root");
    let other = root(&db, "other");
    let inv = invocation(&db, &task, "c1");
    let ctx = context(&inv, 0, "send", json!("other"));
    assert!(
        queue_user_input_with_context(&db, &other, "denied".into(), UnixTs(3), &ctx, Value::Null)
            .is_err()
    );
    assert_eq!(
        load_runtime_task(&db, &other)
            .expect("valid command contract operation")
            .queued_input_count,
        0
    );
    let archive = context(&inv, 1, "archive", json!("root"));
    let saved = transition_task_status_with_context(
        &db,
        &task,
        TaskLifecycleEvent::Archive,
        UnixTs(3),
        &archive,
        json!({}),
    )
    .expect("valid command contract operation");
    assert_eq!(saved.result["deferred"], true);
    assert_eq!(
        read_task_status(&db, &task).expect("valid command contract operation"),
        TaskStatus::Active
    );
    assert!(
        transition_task_status_with_context(
            &db,
            &task,
            TaskLifecycleEvent::Unfreeze,
            UnixTs(4),
            &context(&inv, 2, "unfreeze", json!({})),
            Value::Null
        )
        .is_err()
    );
    finish(&db, &inv, "c1", false).expect("valid command contract operation");
    assert_eq!(
        read_task_status(&db, &task).expect("valid command contract operation"),
        TaskStatus::Archived
    );
}

#[test]
fn caller_scope_allows_direct_child_but_rejects_parent_grandchild_and_unrelated() {
    let db = database();
    let parent = root(&db, "parent");
    // Use normal fork calls without script admission for this legacy contract.
    let make_child = |parent: &TaskId, name: &str| {
        let call = append_model_reply_with_tool_calls_and_move_cursor(
            &db,
            parent,
            None,
            vec![NewFunctionCallNodeContent {
                function_call_id: FunctionCallId(name.into()),
                tool_name: ToolName("exec_cmd".into()),
                arguments: JsonObject::new(),
            }],
            UnixTs(3),
        )
        .expect("valid command contract operation")[0];
        let child = TaskId(name.into());
        commit_tool_result_branches(
            &db,
            CommitToolResultBranchesInput {
                calling_task_id: parent.clone(),
                function_call_node_id: call,
                function_call_id: FunctionCallId(name.into()),
                tool_name: ToolName("exec_cmd".into()),
                branches: vec![
                    ToolResultBranch {
                        target: ToolResultBranchTarget::CallingTask,
                        output: Value::Null,
                        is_error: false,
                        user_messages: vec![],
                    },
                    ToolResultBranch {
                        target: ToolResultBranchTarget::NewChildTask(child.clone()),
                        output: Value::Null,
                        is_error: false,
                        user_messages: vec![],
                    },
                ],
                now: UnixTs(3),
            },
        )
        .expect("valid command contract operation");
        child
    };
    let child = make_child(&parent, "child");
    let grandchild = make_child(&child, "grandchild");
    let other = root(&db, "other");
    let caller = CommandOperationContext {
        caller_task_id: parent.clone(),
        mode: ToolExecutionMode::Startup,
        operation: None,
    };
    assert!(
        queue_user_input_with_context(
            &db,
            &child,
            "allowed".into(),
            UnixTs(4),
            &caller,
            Value::Null
        )
        .is_ok()
    );
    for target in [&grandchild, &other] {
        assert!(
            queue_user_input_with_context(
                &db,
                target,
                "denied".into(),
                UnixTs(4),
                &caller,
                Value::Null
            )
            .is_err()
        );
        assert_eq!(
            load_runtime_task(&db, target)
                .expect("valid command contract operation")
                .queued_input_count,
            0
        );
    }
    let child_scope = CommandOperationContext {
        caller_task_id: child.clone(),
        mode: ToolExecutionMode::Normal,
        operation: None,
    };
    assert!(
        queue_user_input_with_context(
            &db,
            &parent,
            "denied".into(),
            UnixTs(4),
            &child_scope,
            Value::Null
        )
        .is_err()
    );
    let parent_env =
        read_command_environment(&db, &parent).expect("valid command contract operation");
    assert_eq!(
        read_command_environment(&db, &child)
            .expect("valid command contract operation")
            .environment_id,
        parent_env.environment_id
    );
    assert_eq!(
        read_command_environment(&db, &grandchild)
            .expect("valid command contract operation")
            .environment_id,
        parent_env.environment_id
    );
}

#[test]
fn existing_admission_recovers_after_archive_and_child_batch_failure_rolls_back() {
    let db = database();
    let task = root(&db, "root");
    let inv = invocation(&db, &task, "c1");
    let child = TaskId("child".into());
    let ctx = context(&inv, 0, "fork", json!({"count":2}));
    assert!(
        create_pending_command_children(
            &db,
            &ctx,
            vec![(child.clone(), vec![]), (child.clone(), vec![])],
            CommandEnvironmentMode::Shared,
            UnixTs(3)
        )
        .is_err()
    );
    assert!(read_task_metadata(&db, &child).is_err());
    assert_eq!(
        read_command_operation(&db, &ctx).expect("valid command contract operation"),
        None
    );
    transition_task_status(&db, &task, TaskLifecycleEvent::Archive, UnixTs(4))
        .expect("valid command contract operation");
    assert_eq!(
        read_admitted_command_call(&db, &inv)
            .expect("valid command contract operation")
            .function_call_id,
        FunctionCallId("c1".into())
    );
    admit_command_invocation(
        &db,
        &inv,
        &FunctionCallId("c1".into()),
        &ToolName("exec_cmd".into()),
    )
    .expect("valid command contract operation");
    finish(&db, &inv, "c1", true).expect("valid command contract operation");
    assert_eq!(
        read_task_status(&db, &task).expect("valid command contract operation"),
        TaskStatus::Archived
    );
    assert_eq!(
        read_command_environment(&db, &task)
            .expect("valid command contract operation")
            .revision,
        1
    );
    assert!(read_admitted_command_call(&db, &inv).is_err());
}

#[test]
fn admitted_invocation_listing_includes_inactive_owners_until_completion() {
    let db = database();
    let mut expected = Vec::new();
    for (name, event) in [
        ("archived", TaskLifecycleEvent::Archive),
        ("frozen", TaskLifecycleEvent::Freeze),
        ("stopped", TaskLifecycleEvent::Stop),
    ] {
        let task = root(&db, name);
        let inv = invocation(&db, &task, name);
        create_pending_command_child(
            &db,
            &context(&inv, 0, "fork", json!({})),
            TaskId(format!("{name}-child")),
            CommandEnvironmentMode::Shared,
            vec![],
            UnixTs(3),
        )
        .expect("create child awaiting parent completion");
        transition_task_status(&db, &task, event, UnixTs(4)).expect("make admitted owner inactive");
        expected.push(inv);
    }
    let idle = root(&db, "idle");
    assert_eq!(
        list_admitted_command_invocations(&db).expect("list admitted inactive owners"),
        expected,
    );
    assert!(
        read_command_environment(&db, &idle)
            .expect("read unadmitted environment")
            .admitted_invocation
            .is_none()
    );
    for inv in &expected {
        finish(&db, inv, &inv.task_id.0, false).expect("complete inactive owner admission");
    }
    assert!(
        list_admitted_command_invocations(&db)
            .expect("list after recovery commits")
            .is_empty()
    );
}

#[test]
fn deferred_lifecycle_does_not_overwrite_later_committed_transitions_on_recovery() {
    use TaskLifecycleEvent::{Archive, Freeze, Stop, Unfreeze};
    let cases = [
        (vec![Freeze], vec![Archive], TaskStatus::Archived),
        (vec![Stop], vec![Archive], TaskStatus::Archived),
        (vec![Freeze], vec![Stop], TaskStatus::Stopped),
        (vec![Stop], vec![Freeze], TaskStatus::Frozen),
        (vec![Freeze, Unfreeze], vec![Freeze], TaskStatus::Frozen),
        (vec![Stop], vec![Freeze, Unfreeze], TaskStatus::Active),
        (vec![Freeze, Unfreeze], vec![], TaskStatus::Active),
        (vec![Freeze], vec![], TaskStatus::Frozen),
    ];
    for (deferred, external, expected) in cases {
        let db = database();
        let task = root(&db, "root");
        let inv = invocation(&db, &task, "c1");
        let child = TaskId("pending-child".into());
        create_pending_command_child(
            &db,
            &context(&inv, 0, "fork", json!({})),
            child.clone(),
            CommandEnvironmentMode::Copy,
            vec![],
            UnixTs(3),
        )
        .expect("prepare a child before interrupted invocation");
        let mut replay = Vec::new();
        for (index, event) in deferred.into_iter().enumerate() {
            let ctx = context(
                &inv,
                index as u64 + 1,
                "lifecycle",
                json!(format!("{event:?}")),
            );
            let outcome = transition_task_status_with_context(
                &db,
                &task,
                event,
                UnixTs(4),
                &ctx,
                Value::Null,
            )
            .expect("stage legal lifecycle event");
            replay.push((ctx, event, outcome.result));
        }
        // A self-message during the busy invocation is queued; it must not make
        // an otherwise uncontested deferred lifecycle sequence appear stale.
        queue_user_input_with_context(
            &db,
            &task,
            "self-message".into(),
            UnixTs(5),
            &context(&inv, 10, "send", json!({})),
            Value::Null,
        )
        .expect("queue self input without changing active task state version");
        for event in external {
            transition_task_status(&db, &task, event, UnixTs(6))
                .expect("commit an external lifecycle change after deferral");
        }
        admit_command_invocation(
            &db,
            &inv,
            &FunctionCallId("c1".into()),
            &ToolName("exec_cmd".into()),
        )
        .expect("recover the already admitted invocation regardless of lifecycle");
        for (mut ctx, event, saved) in replay {
            ctx.mode = ToolExecutionMode::Startup;
            let outcome = transition_task_status_with_context(
                &db,
                &task,
                event,
                UnixTs(7),
                &ctx,
                Value::Null,
            )
            .expect("startup recovery reuses recorded deferred result");
            assert!(outcome.replayed);
            assert_eq!(outcome.result, saved);
        }
        finish(&db, &inv, "c1", false)
            .expect("complete checkpoint and child despite lifecycle conflict");
        assert_eq!(
            read_task_status(&db, &task).expect("read completed status"),
            expected
        );
        assert!(!task_is_pending(&db, &child).expect("pending child finalized"));
        assert_eq!(
            read_command_environment(&db, &child)
                .expect("copy child environment")
                .checkpoint,
            vec![1, 2, 3]
        );
        let environment = read_command_environment(&db, &task).expect("completed environment");
        assert_eq!(environment.revision, 1);
        assert!(environment.admitted_invocation.is_none());
        assert!(read_admitted_command_call(&db, &inv).is_err());
    }
}

#[test]
fn task_scope_preflight_is_read_only_and_rejects_unrelated_tasks() {
    let db = database();
    let task = root(&db, "root");
    let unrelated = root(&db, "unrelated");
    let inv = invocation(&db, &task, "c1");
    let ctx = context(&inv, 0, "send", json!({}));
    let before = read_task_metadata(&db, &task).expect("read caller before scope check");
    validate_command_task_scope(&db, &ctx, &task).expect("allow caller scope");
    assert!(validate_command_task_scope(&db, &ctx, &unrelated).is_err());
    assert_eq!(
        read_task_metadata(&db, &task).expect("read caller after scope check"),
        before
    );
    assert_eq!(
        read_command_operation(&db, &ctx).expect("scope check does not save journal result"),
        None
    );
}

#[test]
fn own_reactivation_advances_uncontested_deferral_but_does_not_hide_external_conflicts() {
    for external_conflict in [false, true] {
        let db = database();
        let task = root(&db, "root");
        let inv = invocation(&db, &task, "c1");
        let mut archive = context(&inv, 0, "archive", json!({}));
        archive.mode = ToolExecutionMode::Startup;
        if !external_conflict {
            transition_task_status(&db, &task, TaskLifecycleEvent::Stop, UnixTs(3))
                .expect("recover an already stopped caller");
        }
        transition_task_status_with_context(
            &db,
            &task,
            TaskLifecycleEvent::Archive,
            UnixTs(4),
            &archive,
            Value::Null,
        )
        .expect("defer archive during recovery");
        if external_conflict {
            transition_task_status(&db, &task, TaskLifecycleEvent::Stop, UnixTs(5))
                .expect("external stop supersedes the deferred archive");
        }
        let mut send = context(&inv, 1, "send", json!({"message":"resume"}));
        send.mode = ToolExecutionMode::Startup;
        queue_user_input_with_context(&db, &task, "resume".into(), UnixTs(6), &send, Value::Null)
            .expect("same invocation reactivates its stopped caller");
        assert_eq!(
            read_task_status(&db, &task).expect("reactivated caller status"),
            TaskStatus::Active
        );
        assert!(
            queue_user_input_with_context(
                &db,
                &task,
                "resume".into(),
                UnixTs(7),
                &send,
                Value::Null
            )
            .expect("saved input result replays without another effect")
            .replayed
        );
        finish(&db, &inv, "c1", false).expect("commit prepared checkpoint and lifecycle decision");
        let expected = if external_conflict {
            TaskStatus::Active
        } else {
            TaskStatus::Archived
        };
        assert_eq!(
            read_task_status(&db, &task).expect("final caller status"),
            expected
        );
    }
}
