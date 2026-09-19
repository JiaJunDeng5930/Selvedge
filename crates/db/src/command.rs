use super::*;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CommandEnvironmentRow {
    pub environment_id: CommandEnvironmentId,
    pub checkpoint: Vec<u8>,
    pub revision: u64,
    pub admitted_invocation: Option<CommandInvocationId>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct CommandOperationOutcome {
    pub result: Value,
    pub replayed: bool,
}

#[derive(Clone, Debug, PartialEq)]
pub enum CommandOperationAdmission {
    Execute,
    Completed(Value),
    OutcomeUnknown,
}

pub(super) fn create_root_environment_in_tx(tx: &Connection, task: &TaskId) -> Result<(), DbError> {
    tx.execute("INSERT INTO command_environments(environment_id, checkpoint, revision) VALUES(lower(hex(randomblob(16))), x'', 0)", []).map_err(map_error)?;
    tx.execute("INSERT INTO task_command_environments(task_id, environment_id) SELECT ?1, environment_id FROM command_environments WHERE rowid = last_insert_rowid()", [&task.0]).map_err(map_error)?;
    Ok(())
}

pub(super) fn share_child_environment_in_tx(
    tx: &Connection,
    parent: &TaskId,
    child: &TaskId,
) -> Result<(), DbError> {
    tx.execute("INSERT INTO task_command_environments(task_id, environment_id) SELECT ?1, environment_id FROM task_command_environments WHERE task_id = ?2", params![child.0, parent.0]).map_err(map_error)?;
    Ok(())
}

fn environment_in_tx(tx: &Connection, task: &TaskId) -> Result<CommandEnvironmentRow, DbError> {
    let (id, checkpoint, revision, caller, call): (String, Vec<u8>, i64, Option<String>, Option<i64>) = tx.query_row("SELECT e.environment_id, e.checkpoint, e.revision, e.admitted_task_id, e.admitted_call_node_id FROM command_environments e JOIN task_command_environments t USING(environment_id) WHERE t.task_id = ?1", [&task.0], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get(4)?))).optional().map_err(map_error)?.ok_or(DbError::NotFound)?;
    Ok(CommandEnvironmentRow {
        environment_id: CommandEnvironmentId(id),
        checkpoint,
        revision: i64_to_u64(revision)?,
        admitted_invocation: caller.zip(call).map(|(task, call)| CommandInvocationId {
            task_id: TaskId(task),
            function_call_node_id: HistoryNodeId(call),
        }),
    })
}

pub fn read_command_environment(
    db: &DbPool,
    task_id: &TaskId,
) -> Result<CommandEnvironmentRow, DbError> {
    environment_in_tx(&*db.connection()?, task_id)
}

pub fn admit_command_invocation(
    db: &DbPool,
    invocation: &CommandInvocationId,
    function_call_id: &FunctionCallId,
    tool_name: &ToolName,
) -> Result<CommandEnvironmentRow, DbError> {
    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    ensure_not_pending_in_tx(&tx, &invocation.task_id)?;
    let task = read_task_in_connection(&tx, &invocation.task_id)?;
    ensure_current_path_contains_open_function_call(
        &tx,
        task.cursor_node_id.0,
        &NewFunctionOutputNodeContent {
            function_call_node_id: invocation.function_call_node_id,
            function_call_id: function_call_id.clone(),
            tool_name: tool_name.clone(),
            output: Value::Null,
            is_error: false,
        },
    )?;
    let row = environment_in_tx(&tx, &invocation.task_id)?;
    if row.admitted_invocation.is_none() && !task.task_status.accepts_history_writes() {
        return Err(DbError::InvalidTaskStatus {
            status: task.task_status,
        });
    }
    if let Some(owner) = &row.admitted_invocation {
        if owner != invocation {
            return Err(DbError::CommandEnvironmentBusy {
                invocation: owner.clone(),
            });
        }
    } else {
        tx.execute("UPDATE command_environments SET admitted_task_id=?1, admitted_call_node_id=?2 WHERE environment_id=?3", params![invocation.task_id.0, invocation.function_call_node_id.0, row.environment_id.0]).map_err(map_error)?;
    }
    let row = environment_in_tx(&tx, &invocation.task_id)?;
    tx.commit().map_err(map_error)?;
    Ok(row)
}

pub fn task_is_pending(db: &DbPool, task: &TaskId) -> Result<bool, DbError> {
    let connection = db.connection()?;
    ensure_task_exists(&connection, task)?;
    pending_in_tx(&connection, task)
}

fn pending_in_tx(tx: &Connection, task: &TaskId) -> Result<bool, DbError> {
    tx.query_row(
        "SELECT EXISTS(SELECT 1 FROM pending_command_children WHERE child_task_id=?1)",
        [&task.0],
        |r| r.get(0),
    )
    .map_err(map_error)
}

pub(super) fn ensure_not_pending_in_tx(tx: &Connection, task: &TaskId) -> Result<(), DbError> {
    if pending_in_tx(tx, task)? {
        return Err(DbError::Constraint(
            "command child awaits enclosing invocation commit".into(),
        ));
    }
    Ok(())
}

fn validate_context(tx: &Connection, context: &CommandOperationContext) -> Result<(), DbError> {
    ensure_task_exists(tx, &context.caller_task_id)?;
    if let Some(operation) = &context.operation {
        if operation.id.invocation.task_id != context.caller_task_id {
            return Err(DbError::Constraint(
                "operation caller differs from trusted scope".into(),
            ));
        }
        let environment = environment_in_tx(tx, &context.caller_task_id)?;
        if environment.admitted_invocation.as_ref() != Some(&operation.id.invocation) {
            return Err(DbError::Constraint(
                "command invocation is not admitted".into(),
            ));
        }
    }
    Ok(())
}

fn check_scope(
    tx: &Connection,
    context: &CommandOperationContext,
    target: &TaskId,
) -> Result<(), DbError> {
    validate_context(tx, context)?;
    if target != &context.caller_task_id {
        let child: bool = tx.query_row("SELECT EXISTS(SELECT 1 FROM task_parent_edges WHERE parent_task_id=?1 AND child_task_id=?2)", params![context.caller_task_id.0, target.0], |r| r.get(0)).map_err(map_error)?;
        if !child {
            return Err(DbError::Constraint(
                "command target must be caller or direct child".into(),
            ));
        }
    }
    Ok(())
}

// None means absent, Some(None) means admitted external effect with unknown outcome.
fn operation_in_tx(
    tx: &Connection,
    context: &CommandOperationContext,
) -> Result<Option<Option<Value>>, DbError> {
    validate_context(tx, context)?;
    let Some(op) = &context.operation else {
        return Ok(None);
    };
    let stored: Option<(String, String, Option<String>)> = tx.query_row("SELECT command, arguments_json, result_json FROM command_operations WHERE task_id=?1 AND call_node_id=?2 AND ordinal=?3", params![op.id.invocation.task_id.0, op.id.invocation.function_call_node_id.0, u64_to_i64(op.id.ordinal)?], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).optional().map_err(map_error)?;
    stored
        .map(|(command, arguments, result)| {
            if command != op.command || decode_json_value(&arguments)? != op.arguments {
                return Err(DbError::CommandOperationMismatch);
            }
            result.map(|result| decode_json_value(&result)).transpose()
        })
        .transpose()
}

fn save_operation_in_tx(
    tx: &Connection,
    context: &CommandOperationContext,
    result: Option<&Value>,
) -> Result<(), DbError> {
    if let Some(op) = &context.operation {
        tx.execute("INSERT INTO command_operations(task_id,call_node_id,ordinal,command,arguments_json,result_json) VALUES(?1,?2,?3,?4,?5,?6)", params![op.id.invocation.task_id.0, op.id.invocation.function_call_node_id.0, u64_to_i64(op.id.ordinal)?, op.command, encode_json_value(&op.arguments)?, result.map(encode_json_value).transpose()?]).map_err(map_error)?;
    }
    Ok(())
}

pub fn read_command_operation(
    db: &DbPool,
    context: &CommandOperationContext,
) -> Result<Option<Value>, DbError> {
    match operation_in_tx(&*db.connection()?, context)? {
        Some(None) => Err(DbError::Constraint(
            "external command outcome is unknown; retry is forbidden".into(),
        )),
        Some(Some(result)) => Ok(Some(result)),
        None => Ok(None),
    }
}

pub fn save_command_observation(
    db: &DbPool,
    context: &CommandOperationContext,
    result: Value,
) -> Result<CommandOperationOutcome, DbError> {
    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    let outcome = if let Some(saved) = operation_in_tx(&tx, context)? {
        CommandOperationOutcome {
            result: saved
                .ok_or_else(|| DbError::Constraint("external command outcome is unknown".into()))?,
            replayed: true,
        }
    } else {
        save_operation_in_tx(&tx, context, Some(&result))?;
        CommandOperationOutcome {
            result,
            replayed: false,
        }
    };
    tx.commit().map_err(map_error)?;
    Ok(outcome)
}

pub fn admit_external_command_operation(
    db: &DbPool,
    context: &CommandOperationContext,
) -> Result<CommandOperationAdmission, DbError> {
    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    if context.operation.is_none() {
        return Err(DbError::Constraint(
            "external command requires durable operation identity".into(),
        ));
    }
    let result = match operation_in_tx(&tx, context)? {
        Some(Some(result)) => CommandOperationAdmission::Completed(result),
        Some(None) => CommandOperationAdmission::OutcomeUnknown,
        None => {
            if context.mode == ToolExecutionMode::Startup {
                return Err(DbError::Constraint(
                    "external commands are unavailable during startup".into(),
                ));
            }
            check_scope(&tx, context, &context.caller_task_id)?;
            save_operation_in_tx(&tx, context, None)?;
            CommandOperationAdmission::Execute
        }
    };
    tx.commit().map_err(map_error)?;
    Ok(result)
}

pub fn complete_external_command_operation(
    db: &DbPool,
    context: &CommandOperationContext,
    result: Value,
) -> Result<CommandOperationOutcome, DbError> {
    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    let saved = operation_in_tx(&tx, context)?;
    if let Some(Some(result)) = saved {
        return Ok(CommandOperationOutcome {
            result,
            replayed: true,
        });
    }
    if saved.is_none() {
        return Err(DbError::Constraint(
            "external command was not admitted".into(),
        ));
    }
    let op = context.operation.as_ref().ok_or_else(|| {
        DbError::Constraint("external command requires operation identity".into())
    })?;
    tx.execute("UPDATE command_operations SET result_json=?1 WHERE task_id=?2 AND call_node_id=?3 AND ordinal=?4", params![encode_json_value(&result)?, op.id.invocation.task_id.0, op.id.invocation.function_call_node_id.0, u64_to_i64(op.id.ordinal)?]).map_err(map_error)?;
    tx.commit().map_err(map_error)?;
    Ok(CommandOperationOutcome {
        result,
        replayed: false,
    })
}

fn mutation_transaction(
    db: &DbPool,
    target: &TaskId,
    context: &CommandOperationContext,
    result: Value,
    mutate: impl FnOnce(&rusqlite::Transaction<'_>, &mut Value) -> Result<(), DbError>,
) -> Result<CommandOperationOutcome, DbError> {
    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    check_scope(&tx, context, target)?;
    if let Some(saved) = operation_in_tx(&tx, context)? {
        return Ok(CommandOperationOutcome {
            result: saved
                .ok_or_else(|| DbError::Constraint("external command outcome is unknown".into()))?,
            replayed: true,
        });
    }
    let caller_version = if target == &context.caller_task_id && context.operation.is_some() {
        Some(read_task_in_connection(&tx, target)?.state_version)
    } else {
        None
    };
    let mut result = result;
    mutate(&tx, &mut result)?;
    if let (Some(before_version), Some(operation)) = (caller_version, &context.operation) {
        let after_version = read_task_in_connection(&tx, target)?.state_version;
        // Own writes advance an uncontested deferral together with their journal entry.
        // Never catch up a stale baseline: that would hide a prior external transition.
        tx.execute("UPDATE pending_command_lifecycle SET base_state_version=?1 WHERE task_id=?2 AND call_node_id=?3 AND base_state_version=?4", params![u64_to_i64(after_version)?, target.0, operation.id.invocation.function_call_node_id.0, u64_to_i64(before_version)?]).map_err(map_error)?;
    }
    save_operation_in_tx(&tx, context, Some(&result))?;
    tx.commit().map_err(map_error)?;
    Ok(CommandOperationOutcome {
        result,
        replayed: false,
    })
}

pub fn append_user_message_with_context(
    db: &DbPool,
    task: &TaskId,
    message_text: String,
    now: UnixTs,
    context: &CommandOperationContext,
    result: Value,
) -> Result<CommandOperationOutcome, DbError> {
    mutation_transaction(db, task, context, result, |tx, result| {
        // Pending children keep the outer call as their cursor until finalization.
        if pending_in_tx(tx, task)? {
            queue_input_in_tx(tx, task, message_text, now)?;
            *result = serde_json::json!({"task_id":task.0,"disposition":"queued"});
            return Ok(());
        }
        let row = read_task_in_connection(tx, task)?;
        let status = row
            .task_status
            .transition(TaskLifecycleEvent::UserInput)
            .ok_or(DbError::InvalidTaskStatus {
                status: row.task_status,
            })?;
        let node = insert_history_node(
            tx,
            NewHistoryNode {
                parent_node_id: Some(row.cursor_node_id),
                content: NewHistoryNodeContent::Message(NewMessageNodeContent {
                    message_role: MessageRole::User,
                    message_text,
                }),
                created_at: now,
            },
        )?;
        tx.execute("UPDATE tasks SET task_status=?1, cursor_node_id=?2, updated_at=?3, state_version=state_version+1 WHERE task_id=?4", params![task_status_to_db(status), node.0, now.0, task.0]).map_err(map_error)?;
        *result = serde_json::json!({"task_id":task.0,"disposition":"committed","node_id":node.0});
        Ok(())
    })
}

fn queue_input_in_tx(
    tx: &Connection,
    task: &TaskId,
    message_text: String,
    now: UnixTs,
) -> Result<(), DbError> {
    let row = read_task_in_connection(tx, task)?;
    let status = row
        .task_status
        .transition(TaskLifecycleEvent::UserInput)
        .ok_or(DbError::InvalidTaskStatus {
            status: row.task_status,
        })?;
    tx.execute("INSERT INTO queued_user_inputs(task_id,seq_no,message_text,queued_at) SELECT ?1,COALESCE(MAX(seq_no),0)+1,?2,?3 FROM queued_user_inputs WHERE task_id=?1", params![task.0, message_text, now.0]).map_err(map_error)?;
    if status != row.task_status {
        tx.execute("UPDATE tasks SET task_status=?1, updated_at=?2, state_version=state_version+1 WHERE task_id=?3", params![task_status_to_db(status), now.0, task.0]).map_err(map_error)?;
    }
    Ok(())
}

pub fn queue_user_input_with_context(
    db: &DbPool,
    task: &TaskId,
    message_text: String,
    now: UnixTs,
    context: &CommandOperationContext,
    result: Value,
) -> Result<CommandOperationOutcome, DbError> {
    mutation_transaction(db, task, context, result, |tx, result| {
        queue_input_in_tx(tx, task, message_text, now)?;
        *result = serde_json::json!({"task_id":task.0,"disposition":"queued"});
        Ok(())
    })
}

pub fn transition_task_status_with_context(
    db: &DbPool,
    task: &TaskId,
    event: TaskLifecycleEvent,
    now: UnixTs,
    context: &CommandOperationContext,
    result: Value,
) -> Result<CommandOperationOutcome, DbError> {
    if event == TaskLifecycleEvent::UserInput {
        return Err(DbError::Constraint(
            "user input transition requires a message".into(),
        ));
    }
    mutation_transaction(db, task, context, result, |tx, result| {
        let row = read_task_in_connection(tx, task)?;
        if task == &context.caller_task_id
            && let Some(operation) = &context.operation
        {
            let pending =
                read_pending_lifecycle(tx, &operation.id.invocation)?.unwrap_or(PendingLifecycle {
                    status: row.task_status,
                    base_state_version: row.state_version,
                });
            let status = pending
                .status
                .transition(event)
                .ok_or(DbError::InvalidTaskStatus {
                    status: pending.status,
                })?;
            tx.execute("INSERT INTO pending_command_lifecycle(task_id,call_node_id,task_status,base_state_version) VALUES(?1,?2,?3,?4) ON CONFLICT(task_id,call_node_id) DO UPDATE SET task_status=excluded.task_status", params![task.0, operation.id.invocation.function_call_node_id.0, task_status_to_db(status), u64_to_i64(pending.base_state_version)?]).map_err(map_error)?;
            *result = serde_json::json!({"task_id":task.0,"deferred":true,"task_status":task_status_to_db(status)});
        } else {
            let status = row
                .task_status
                .transition(event)
                .ok_or(DbError::InvalidTaskStatus {
                    status: row.task_status,
                })?;
            tx.execute("UPDATE tasks SET task_status=?1, updated_at=?2, state_version=state_version+1 WHERE task_id=?3", params![task_status_to_db(status), now.0, task.0]).map_err(map_error)?;
        }
        Ok(())
    })
}

pub fn create_pending_command_child(
    db: &DbPool,
    context: &CommandOperationContext,
    child_task_id: TaskId,
    mode: CommandEnvironmentMode,
    messages: Vec<String>,
    now: UnixTs,
) -> Result<CommandOperationOutcome, DbError> {
    create_pending_command_children(db, context, vec![(child_task_id, messages)], mode, now)
}

pub fn create_pending_command_children(
    db: &DbPool,
    context: &CommandOperationContext,
    children: Vec<(TaskId, Vec<String>)>,
    mode: CommandEnvironmentMode,
    now: UnixTs,
) -> Result<CommandOperationOutcome, DbError> {
    let operation = context.operation.as_ref().ok_or_else(|| {
        DbError::Constraint("pending children require command operation identity".into())
    })?;
    let result =
        serde_json::json!({"children":children.iter().map(|(id, _)| &id.0).collect::<Vec<_>>()});
    mutation_transaction(db, &context.caller_task_id, context, result, |tx, _| {
        if children.is_empty() {
            return Err(DbError::Constraint(
                "fork must create at least one child".into(),
            ));
        }
        let caller = read_task_in_connection(tx, &context.caller_task_id)?;
        if children.len() > caller.max_children_per_fork as usize {
            return Err(DbError::Constraint("fork exceeds child count limit".into()));
        }
        ensure_task_descendant_capacity_in_tx(tx, &context.caller_task_id, children.len())?;
        for (child, messages) in children {
            if messages.iter().any(String::is_empty) {
                return Err(DbError::Constraint("child messages cannot be empty".into()));
            }
            tx.execute("INSERT INTO tasks(task_id,task_status,cursor_node_id,model_profile_key,reasoning_effort,max_children_per_fork,max_task_descendants,state_version,created_at,updated_at) SELECT ?1,'active',cursor_node_id,model_profile_key,reasoning_effort,max_children_per_fork,max_task_descendants,0,?2,?2 FROM tasks WHERE task_id=?3", params![child.0, now.0, context.caller_task_id.0]).map_err(map_error)?;
            tx.execute("INSERT INTO task_parent_edges(parent_task_id,child_task_id,created_at) VALUES(?1,?2,?3)", params![context.caller_task_id.0, child.0, now.0]).map_err(map_error)?;
            tx.execute("INSERT INTO task_tools(task_id,tool_ordinal,tool_name,description_text,input_schema_json,mcp_server_id,remote_tool_name,execution_source_kind,recovery_policy) SELECT ?1,tool_ordinal,tool_name,description_text,input_schema_json,mcp_server_id,remote_tool_name,execution_source_kind,recovery_policy FROM task_tools WHERE task_id=?2", params![child.0,context.caller_task_id.0]).map_err(map_error)?;
            tx.execute("INSERT INTO task_unavailable_tools(task_id,tool_name) SELECT ?1,tool_name FROM task_unavailable_tools WHERE task_id=?2", params![child.0,context.caller_task_id.0]).map_err(map_error)?;
            share_child_environment_in_tx(tx, &context.caller_task_id, &child)?;
            tx.execute("INSERT INTO pending_command_children(child_task_id,task_id,call_node_id,environment_mode) VALUES(?1,?2,?3,?4)", params![child.0,context.caller_task_id.0,operation.id.invocation.function_call_node_id.0,mode_to_db(mode)]).map_err(map_error)?;
            for message in messages {
                queue_input_in_tx(tx, &child, message, now)?;
            }
        }
        Ok(())
    })
}

fn mode_to_db(mode: CommandEnvironmentMode) -> &'static str {
    match mode {
        CommandEnvironmentMode::Shared => "shared",
        CommandEnvironmentMode::Copy => "copy",
        CommandEnvironmentMode::New => "new",
    }
}

fn assign_final_environment(
    tx: &Connection,
    child: &TaskId,
    mode: &str,
    commit: &CommandEnvironmentCommit,
) -> Result<(), DbError> {
    match mode {
        "shared" => {}
        "copy" | "new" => {
            let checkpoint = if mode == "copy" {
                &commit.checkpoint
            } else {
                &commit.base_checkpoint
            };
            tx.execute("INSERT INTO command_environments(environment_id,checkpoint,revision) VALUES(lower(hex(randomblob(16))),?1,0)", [checkpoint]).map_err(map_error)?;
            tx.execute("UPDATE task_command_environments SET environment_id=(SELECT environment_id FROM command_environments WHERE rowid=last_insert_rowid()) WHERE task_id=?1", [&child.0]).map_err(map_error)?;
        }
        _ => return Err(DbError::Storage("invalid command environment mode".into())),
    }
    Ok(())
}

pub fn commit_tool_result_branches_with_environment(
    db: &DbPool,
    input: CommitToolResultBranchesInput,
    environment: &CommandEnvironmentCommit,
) -> Result<CommitToolResultBranchesResult, DbError> {
    let mut connection = db.connection()?;
    let tx = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(map_error)?;
    if environment.invocation.task_id != input.calling_task_id
        || environment.invocation.function_call_node_id != input.function_call_node_id
    {
        return Err(DbError::Constraint(
            "environment commit differs from outer tool identity".into(),
        ));
    }
    let row = environment_in_tx(&tx, &input.calling_task_id)?;
    if row.environment_id != environment.environment_id
        || row.revision != environment.expected_revision
        || row.admitted_invocation.as_ref() != Some(&environment.invocation)
    {
        return Err(DbError::Constraint(
            "environment commit does not match admitted revision".into(),
        ));
    }
    let output = input
        .branches
        .iter()
        .find(|b| b.target == ToolResultBranchTarget::CallingTask)
        .cloned()
        .ok_or_else(|| {
            DbError::Constraint("command completion requires calling task output".into())
        })?;
    let identity = NewFunctionOutputNodeContent {
        function_call_node_id: input.function_call_node_id,
        function_call_id: input.function_call_id.clone(),
        tool_name: input.tool_name.clone(),
        output: Value::Null,
        is_error: false,
    };
    let now = input.now;
    let mut pending = tx.prepare("SELECT child_task_id,environment_mode FROM pending_command_children WHERE task_id=?1 AND call_node_id=?2 ORDER BY child_task_id").map_err(map_error)?;
    let children: Vec<(String, String)> = pending
        .query_map(
            params![input.calling_task_id.0, input.function_call_node_id.0],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .map_err(map_error)?
        .collect::<Result<_, _>>()
        .map_err(map_error)?;
    drop(pending);
    // Only this admitted completion may write an archived caller after recovery.
    let caller = read_task_in_connection(&tx, &input.calling_task_id)?;
    if caller.task_status == TaskStatus::Archived {
        tx.execute(
            "UPDATE tasks SET task_status='stopped' WHERE task_id=?1",
            [&input.calling_task_id.0],
        )
        .map_err(map_error)?;
    }
    let mut result = commit_tool_result_branches_in_tx(&tx, input)?;
    if caller.task_status == TaskStatus::Archived {
        tx.execute(
            "UPDATE tasks SET task_status='archived' WHERE task_id=?1",
            [&environment.invocation.task_id.0],
        )
        .map_err(map_error)?;
    }
    for child in &result.created_child_task_ids {
        assign_final_environment(
            &tx,
            child,
            mode_to_db(environment.new_child_environment_mode),
            environment,
        )?;
    }
    for (child, mode) in children {
        let child = TaskId(child);
        let cursor = read_task_in_connection(&tx, &child)?.cursor_node_id;
        let new_cursor = insert_tool_result_branch_in_tx(
            &tx,
            cursor,
            &identity,
            output.output.clone(),
            output.is_error,
            vec![],
            now,
        )?;
        // A pending child may already be archived; its outer call still must settle.
        let status = read_task_in_connection(&tx, &child)?.task_status;
        if status == TaskStatus::Archived {
            tx.execute(
                "UPDATE tasks SET task_status='stopped' WHERE task_id=?1",
                [&child.0],
            )
            .map_err(map_error)?;
        }
        update_task_cursor_in_tx(&tx, &child, new_cursor, now)?;
        append_all_queued_user_inputs_in_tx(&tx, &child, now)?;
        if status == TaskStatus::Archived {
            tx.execute(
                "UPDATE tasks SET task_status='archived' WHERE task_id=?1",
                [&child.0],
            )
            .map_err(map_error)?;
        }
        assign_final_environment(&tx, &child, &mode, environment)?;
        tx.execute(
            "DELETE FROM pending_command_children WHERE child_task_id=?1",
            [&child.0],
        )
        .map_err(map_error)?;
        result.created_child_task_ids.push(child);
    }
    tx.execute("UPDATE command_environments SET checkpoint=?1,revision=revision+1,admitted_task_id=NULL,admitted_call_node_id=NULL WHERE environment_id=?2", params![environment.checkpoint,environment.environment_id.0]).map_err(map_error)?;
    if let Some(plan) = read_pending_lifecycle(&tx, &environment.invocation)? {
        // Each deferred transition was validated when staged. A later committed
        // change supersedes that result, even if its status has returned to the original.
        if caller.state_version == plan.base_state_version {
            tx.execute("UPDATE tasks SET task_status=?1,updated_at=?2,state_version=state_version+1 WHERE task_id=?3", params![task_status_to_db(plan.status), now.0, environment.invocation.task_id.0]).map_err(map_error)?;
        }
    }
    tx.execute(
        "DELETE FROM pending_command_lifecycle WHERE task_id=?1 AND call_node_id=?2",
        params![
            environment.invocation.task_id.0,
            environment.invocation.function_call_node_id.0
        ],
    )
    .map_err(map_error)?;
    tx.commit().map_err(map_error)?;
    Ok(result)
}

pub fn command_operation_replay_length(
    db: &DbPool,
    invocation: &CommandInvocationId,
) -> Result<u64, DbError> {
    let connection = db.connection()?;
    let count: i64 = connection.query_row("SELECT COALESCE(MAX(ordinal)+1,0) FROM command_operations WHERE task_id=?1 AND call_node_id=?2", params![invocation.task_id.0,invocation.function_call_node_id.0], |r| r.get(0)).map_err(map_error)?;
    i64_to_u64(count)
}

pub fn read_admitted_command_call(
    db: &DbPool,
    invocation: &CommandInvocationId,
) -> Result<OpenFunctionCall, DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    let environment = environment_in_tx(&tx, &invocation.task_id)?;
    if environment.admitted_invocation.as_ref() != Some(invocation) {
        return Err(DbError::Constraint(
            "command invocation is not admitted".into(),
        ));
    }
    let HistoryNode::FunctionCall {
        function_call_id,
        tool_name,
        arguments,
        ..
    } = read_history_node_concrete_in_connection(&tx, &invocation.function_call_node_id)?
    else {
        return Err(DbError::StaleFunctionCall);
    };
    let task = read_task_in_connection(&tx, &invocation.task_id)?;
    ensure_current_path_contains_open_function_call(
        &tx,
        task.cursor_node_id.0,
        &NewFunctionOutputNodeContent {
            function_call_node_id: invocation.function_call_node_id,
            function_call_id: function_call_id.clone(),
            tool_name: tool_name.clone(),
            output: Value::Null,
            is_error: false,
        },
    )?;
    let policies = read_task_tool_recovery_policies_in_connection(&tx, &invocation.task_id)?;
    let recovery_policy = policies
        .get(&tool_name.0)
        .copied()
        .ok_or(DbError::ToolUnavailable)?;
    Ok(OpenFunctionCall {
        function_call_node_id: invocation.function_call_node_id,
        function_call_id,
        tool_name,
        arguments,
        recovery_policy,
    })
}

/// Includes inactive owners because their pending children cannot recover independently.
pub fn list_admitted_command_invocations(db: &DbPool) -> Result<Vec<CommandInvocationId>, DbError> {
    let connection = db.connection()?;
    let mut statement = connection
        .prepare(
            "SELECT admitted_task_id, admitted_call_node_id FROM command_environments
         WHERE admitted_task_id IS NOT NULL
         ORDER BY admitted_task_id, admitted_call_node_id",
        )
        .map_err(map_error)?;
    statement
        .query_map([], |row| {
            Ok(CommandInvocationId {
                task_id: TaskId(row.get(0)?),
                function_call_node_id: HistoryNodeId(row.get(1)?),
            })
        })
        .map_err(map_error)?
        .collect::<Result<Vec<_>, _>>()
        .map_err(map_error)
}

pub fn validate_command_task_scope(
    db: &DbPool,
    context: &CommandOperationContext,
    target: &TaskId,
) -> Result<(), DbError> {
    let mut connection = db.connection()?;
    let tx = connection.transaction().map_err(map_error)?;
    check_scope(&tx, context, target)
}

struct PendingLifecycle {
    status: TaskStatus,
    base_state_version: u64,
}

fn read_pending_lifecycle(
    tx: &Connection,
    invocation: &CommandInvocationId,
) -> Result<Option<PendingLifecycle>, DbError> {
    let stored: Option<(String, i64)> = tx.query_row("SELECT task_status,base_state_version FROM pending_command_lifecycle WHERE task_id=?1 AND call_node_id=?2", params![invocation.task_id.0, invocation.function_call_node_id.0], |row| Ok((row.get(0)?, row.get(1)?))).optional().map_err(map_error)?;
    stored
        .map(|(status, base_state_version)| {
            Ok(PendingLifecycle {
                status: task_status_from_db(&status)?,
                base_state_version: i64_to_u64(base_state_version)?,
            })
        })
        .transpose()
}
