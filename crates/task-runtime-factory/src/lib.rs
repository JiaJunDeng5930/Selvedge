#![doc = include_str!("../README.md")]

use std::collections::HashSet;

use selvedge_command_model::RouterIngressWeakSender;
use selvedge_core::{SpawnTaskRuntimeArgs, SpawnedTaskRuntime, TaskRuntimeSpawnDeps};
use selvedge_db::{DbError, DbPool, TaskId, list_runtime_tasks, read_task_metadata};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum RuntimeCreationError {
    TaskMissing,
    TaskArchived,
    TaskPending,
    DbReadFailed(String),
    CoreSpawnFailed(String),
}

impl std::fmt::Display for RuntimeCreationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::TaskMissing => f.write_str("task is missing"),
            Self::TaskArchived => f.write_str("task is archived"),
            Self::TaskPending => f.write_str("task awaits its enclosing command invocation"),
            Self::DbReadFailed(message) | Self::CoreSpawnFailed(message) => f.write_str(message),
        }
    }
}

#[derive(Debug)]
pub struct RecoveredTaskRuntimes {
    pub created: Vec<SpawnedTaskRuntime>,
    pub failed: Vec<(TaskId, RuntimeCreationError)>,
}

/// The caller owns runtime uniqueness and runs this synchronous operation on a blocking worker.
pub fn create_task_runtime(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    task_id: TaskId,
) -> Result<SpawnedTaskRuntime, RuntimeCreationError> {
    let task = read_task_metadata(db, &task_id).map_err(map_db_error)?;
    if selvedge_db::task_is_pending(db, &task_id).map_err(map_db_error)? {
        return Err(RuntimeCreationError::TaskPending);
    }
    if !task.task_status.has_runtime() {
        return Err(RuntimeCreationError::TaskArchived);
    }
    spawn_task_runtime(db, router_tx, core_spawn_deps, task_id)
}

/// Recover only the durable admitted invocation, including one owned by an archived task.
pub fn create_command_recovery_runtime(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    invocation: &selvedge_db::CommandInvocationId,
) -> Result<SpawnedTaskRuntime, RuntimeCreationError> {
    selvedge_db::read_admitted_command_call(db, invocation).map_err(map_db_error)?;
    spawn_task_runtime(db, router_tx, core_spawn_deps, invocation.task_id.clone())
}

pub fn recover_task_runtimes(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    live_task_ids: &HashSet<TaskId>,
) -> Result<RecoveredTaskRuntimes, RuntimeCreationError> {
    let tasks = list_runtime_tasks(db).map_err(map_db_error)?;
    let mut recovered = RecoveredTaskRuntimes {
        created: Vec::new(),
        failed: Vec::new(),
    };
    for task in tasks {
        if live_task_ids.contains(&task.task_id)
            || selvedge_db::task_is_pending(db, &task.task_id).map_err(map_db_error)?
        {
            continue;
        }
        match spawn_task_runtime(db, router_tx, core_spawn_deps, task.task_id.clone()) {
            Ok(runtime) => recovered.created.push(runtime),
            Err(error) => recovered.failed.push((task.task_id, error)),
        }
    }
    Ok(recovered)
}

fn spawn_task_runtime(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    task_id: TaskId,
) -> Result<SpawnedTaskRuntime, RuntimeCreationError> {
    core_spawn_deps
        .spawner
        .spawn_task_runtime(SpawnTaskRuntimeArgs {
            task_id,
            db: db.clone(),
            router_tx: router_tx.clone(),
            config: core_spawn_deps.config.clone(),
        })
        .map_err(|error| {
            RuntimeCreationError::CoreSpawnFailed(format!("task runtime spawn failed: {error:?}"))
        })
}

fn map_db_error(error: DbError) -> RuntimeCreationError {
    match error {
        DbError::NotFound => RuntimeCreationError::TaskMissing,
        error => RuntimeCreationError::DbReadFailed(error.to_string()),
    }
}
