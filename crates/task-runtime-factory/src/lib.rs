#![doc = include_str!("../README.md")]

use std::collections::HashSet;
use std::time::{SystemTime, UNIX_EPOCH};

use selvedge_command_model::{
    CreatedRuntimeKind, FactoryEffectId, FactoryFailure, FactoryFailureKind, FactoryOutput,
    FactoryOutputEnvelope, FactoryScanOutput, FactorySkipReason, FactorySkippedTask,
    FactoryTaskFailure, RouterIngressSender, TaskRuntimeCreated,
};
use selvedge_core::{SpawnTaskRuntimeArgs, SpawnTaskRuntimeError, TaskRuntimeSpawnDeps};
use selvedge_db::{
    CreateChildTaskInput, DbError, DbPool, TaskId, UnixTs, create_child_task, list_active_tasks,
    load_active_task,
};
use selvedge_domain_model::HistoryNodeId;
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FactoryCommand {
    EnsureTaskRuntime(EnsureTaskRuntimeCommand),
    EnsureMissingTaskRuntimes(EnsureMissingTaskRuntimesCommand),
    CreateChildTaskAndRuntime(CreateChildTaskAndRuntimeCommand),
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EnsureTaskRuntimeCommand {
    pub effect_id: FactoryEffectId,
    pub task_id: TaskId,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EnsureMissingTaskRuntimesCommand {
    pub effect_id: FactoryEffectId,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CreateChildTaskAndRuntimeCommand {
    pub effect_id: FactoryEffectId,
    pub parent_task_id: TaskId,
    pub child_cursor_node_id: HistoryNodeId,
}

#[derive(Clone)]
pub struct FactoryEffectArgs {
    pub command: FactoryCommand,
    pub db: DbPool,
    pub router_tx: RouterIngressSender,
    pub core_spawn_deps: TaskRuntimeSpawnDeps,
    pub runtime_inventory: FactoryRuntimeInventory,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FactoryRuntimeInventory {
    pub live_task_runtimes: Vec<TaskId>,
    pub pending_task_runtime_effects: Vec<TaskId>,
}

pub fn run_factory_effect(args: FactoryEffectArgs) -> FactoryOutputEnvelope {
    let (effect_id, output) = match args.command {
        FactoryCommand::EnsureTaskRuntime(command) => {
            let output = ensure_task_runtime(
                &args.db,
                &args.router_tx,
                &args.core_spawn_deps,
                &args.runtime_inventory,
                command.task_id,
                CreatedRuntimeKind::ExistingTaskRuntime,
            );
            (command.effect_id, output)
        }
        FactoryCommand::EnsureMissingTaskRuntimes(command) => {
            let output = ensure_missing_task_runtimes(
                &args.db,
                &args.router_tx,
                &args.core_spawn_deps,
                &args.runtime_inventory,
            );
            (command.effect_id, output)
        }
        FactoryCommand::CreateChildTaskAndRuntime(command) => {
            let output = create_child_task_and_runtime(
                &args.db,
                &args.router_tx,
                &args.core_spawn_deps,
                command.parent_task_id,
                command.child_cursor_node_id,
            );
            (command.effect_id, output)
        }
    };
    FactoryOutputEnvelope { effect_id, output }
}

fn create_child_task_and_runtime(
    db: &DbPool,
    router_tx: &RouterIngressSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    parent_task_id: TaskId,
    child_cursor_node_id: HistoryNodeId,
) -> FactoryOutput {
    let child_task_id = TaskId(format!("child-{}", Uuid::new_v4()));
    let child = match create_child_task(
        db,
        CreateChildTaskInput {
            parent_task_id: parent_task_id.clone(),
            child_task_id,
            cursor_node_id: child_cursor_node_id,
            now: now(),
        },
    ) {
        Ok(child) => child,
        Err(error) => {
            return FactoryOutput::Failed(map_create_child_failure(parent_task_id, error));
        }
    };
    spawn_task_runtime(
        db,
        router_tx,
        core_spawn_deps,
        child.task_id,
        CreatedRuntimeKind::ChildTaskRuntime,
    )
}

fn ensure_missing_task_runtimes(
    db: &DbPool,
    router_tx: &RouterIngressSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    runtime_inventory: &FactoryRuntimeInventory,
) -> FactoryOutput {
    let live_task_runtimes = runtime_inventory
        .live_task_runtimes
        .iter()
        .cloned()
        .collect::<HashSet<_>>();
    let pending_task_runtime_effects = runtime_inventory
        .pending_task_runtime_effects
        .iter()
        .cloned()
        .collect::<HashSet<_>>();
    let active_tasks = match list_active_tasks(db) {
        Ok(active_tasks) => active_tasks,
        Err(error) => {
            return FactoryOutput::Failed(FactoryFailure {
                task_id: None,
                kind: FactoryFailureKind::DbReadFailed,
                message: error.to_string(),
            });
        }
    };

    let mut created = Vec::new();
    let mut skipped = Vec::new();
    let mut failed = Vec::new();
    for task in active_tasks {
        if live_task_runtimes.contains(&task.task_id) {
            skipped.push(FactorySkippedTask {
                task_id: task.task_id,
                reason: FactorySkipReason::RuntimeAlreadyLive,
            });
            continue;
        }
        if pending_task_runtime_effects.contains(&task.task_id) {
            skipped.push(FactorySkippedTask {
                task_id: task.task_id,
                reason: FactorySkipReason::RuntimeCreationPending,
            });
            continue;
        }
        let task_id = task.task_id;
        let failure_task_id = task_id.clone();
        match spawn_task_runtime_created(
            db,
            router_tx,
            core_spawn_deps,
            task_id,
            CreatedRuntimeKind::ExistingTaskRuntime,
        ) {
            Ok(runtime) => created.push(runtime),
            Err(failure) => {
                failed.push(FactoryTaskFailure {
                    task_id: failure.task_id.unwrap_or(failure_task_id),
                    kind: failure.kind,
                    message: failure.message,
                });
            }
        }
    }

    FactoryOutput::ScanFinished(FactoryScanOutput {
        created,
        skipped,
        failed,
    })
}

fn ensure_task_runtime(
    db: &DbPool,
    router_tx: &RouterIngressSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    runtime_inventory: &FactoryRuntimeInventory,
    task_id: TaskId,
    created_runtime_kind: CreatedRuntimeKind,
) -> FactoryOutput {
    match load_active_task(db, &task_id) {
        Ok(_) => {
            if runtime_inventory.live_task_runtimes.contains(&task_id) {
                return FactoryOutput::Failed(FactoryFailure {
                    task_id: Some(task_id),
                    kind: FactoryFailureKind::RuntimeAlreadyLive,
                    message: "task runtime is already live".to_owned(),
                });
            }
            if runtime_inventory
                .pending_task_runtime_effects
                .contains(&task_id)
            {
                return FactoryOutput::Failed(FactoryFailure {
                    task_id: Some(task_id),
                    kind: FactoryFailureKind::RuntimeCreationPending,
                    message: "task runtime creation is already pending".to_owned(),
                });
            }
            spawn_task_runtime(
                db,
                router_tx,
                core_spawn_deps,
                task_id,
                created_runtime_kind,
            )
        }
        Err(error) => FactoryOutput::Failed(map_load_task_failure(Some(task_id), error)),
    }
}

fn spawn_task_runtime(
    db: &DbPool,
    router_tx: &RouterIngressSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    task_id: TaskId,
    created_runtime_kind: CreatedRuntimeKind,
) -> FactoryOutput {
    match spawn_task_runtime_created(
        db,
        router_tx,
        core_spawn_deps,
        task_id,
        created_runtime_kind,
    ) {
        Ok(created) => FactoryOutput::RuntimeCreated(created),
        Err(failure) => FactoryOutput::Failed(failure),
    }
}

fn spawn_task_runtime_created(
    db: &DbPool,
    router_tx: &RouterIngressSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    task_id: TaskId,
    created_runtime_kind: CreatedRuntimeKind,
) -> Result<TaskRuntimeCreated, FactoryFailure> {
    match core_spawn_deps
        .spawner
        .spawn_task_runtime(SpawnTaskRuntimeArgs {
            task_id: task_id.clone(),
            db: db.clone(),
            router_tx: router_tx.clone(),
            config: core_spawn_deps.config.clone(),
        }) {
        Ok(spawned) => Ok(TaskRuntimeCreated {
            task_id: spawned.task_id,
            task_runtime_tx: spawned.task_runtime_tx,
            task_runtime_control: spawned.task_runtime_control,
            created_runtime_kind,
        }),
        Err(error) => Err(FactoryFailure {
            task_id: Some(task_id),
            kind: FactoryFailureKind::CoreSpawnFailed,
            message: spawn_error_message(error),
        }),
    }
}

fn map_load_task_failure(task_id: Option<TaskId>, error: DbError) -> FactoryFailure {
    match error {
        DbError::NotFound => FactoryFailure {
            task_id,
            kind: FactoryFailureKind::TaskMissing,
            message: "task is missing".to_owned(),
        },
        DbError::TaskNotActive => FactoryFailure {
            task_id,
            kind: FactoryFailureKind::TaskArchived,
            message: "task is archived".to_owned(),
        },
        error => FactoryFailure {
            task_id,
            kind: FactoryFailureKind::DbReadFailed,
            message: error.to_string(),
        },
    }
}

fn map_create_child_failure(parent_task_id: TaskId, error: DbError) -> FactoryFailure {
    match error {
        DbError::NotFound => FactoryFailure {
            task_id: Some(parent_task_id),
            kind: FactoryFailureKind::ParentTaskMissing,
            message: "parent task is missing".to_owned(),
        },
        DbError::TaskNotActive => FactoryFailure {
            task_id: Some(parent_task_id),
            kind: FactoryFailureKind::ParentTaskArchived,
            message: "parent task is archived".to_owned(),
        },
        DbError::Constraint(message) => FactoryFailure {
            task_id: Some(parent_task_id),
            kind: FactoryFailureKind::CursorNodeMissing,
            message,
        },
        error => FactoryFailure {
            task_id: Some(parent_task_id),
            kind: FactoryFailureKind::DbWriteFailed,
            message: error.to_string(),
        },
    }
}

fn spawn_error_message(error: SpawnTaskRuntimeError) -> String {
    match error {
        SpawnTaskRuntimeError::MailboxCreateFailed => "task runtime mailbox create failed",
        SpawnTaskRuntimeError::TokioSpawnFailed => "task runtime tokio spawn failed",
    }
    .to_owned()
}

fn now() -> UnixTs {
    UnixTs(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_secs() as i64)
            .unwrap_or(0),
    )
}
