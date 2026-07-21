#![doc = include_str!("../README.md")]

use std::collections::HashSet;

use selvedge_command_model::{
    FactoryEffectId, FactoryFailure, FactoryFailureKind, FactoryOutput, FactoryOutputEnvelope,
    FactoryScanOutput, FactorySkipReason, FactorySkippedTask, FactoryTaskFailure,
    RouterIngressWeakSender, TaskRuntimeCreated,
};
use selvedge_core::{SpawnTaskRuntimeArgs, SpawnTaskRuntimeError, TaskRuntimeSpawnDeps};
use selvedge_db::{DbError, DbPool, TaskId, list_runtime_tasks, load_runtime_task};

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FactoryCommand {
    EnsureTaskRuntime { task_id: TaskId },
    EnsureMissingTaskRuntimes,
}

#[derive(Clone)]
pub struct FactoryEffectArgs {
    pub effect_id: FactoryEffectId,
    pub command: FactoryCommand,
    pub db: DbPool,
    pub router_tx: RouterIngressWeakSender,
    pub core_spawn_deps: TaskRuntimeSpawnDeps,
    pub runtime_inventory: FactoryRuntimeInventory,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FactoryRuntimeInventory {
    pub live_task_runtimes: Vec<TaskId>,
    pub pending_task_runtime_effects: Vec<TaskId>,
}

pub fn run_factory_effect(args: FactoryEffectArgs) -> FactoryOutputEnvelope {
    let output = match args.command {
        FactoryCommand::EnsureTaskRuntime { task_id } => ensure_task_runtime(
            &args.db,
            &args.router_tx,
            &args.core_spawn_deps,
            &args.runtime_inventory,
            task_id,
        ),
        FactoryCommand::EnsureMissingTaskRuntimes => ensure_missing_task_runtimes(
            &args.db,
            &args.router_tx,
            &args.core_spawn_deps,
            &args.runtime_inventory,
        ),
    };
    FactoryOutputEnvelope {
        effect_id: args.effect_id,
        output,
    }
}

fn ensure_missing_task_runtimes(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
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
    let runtime_tasks = match list_runtime_tasks(db) {
        Ok(runtime_tasks) => runtime_tasks,
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
    for task in runtime_tasks {
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
        match spawn_task_runtime_created(db, router_tx, core_spawn_deps, task_id) {
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
    router_tx: &RouterIngressWeakSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    runtime_inventory: &FactoryRuntimeInventory,
    task_id: TaskId,
) -> FactoryOutput {
    match load_runtime_task(db, &task_id) {
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
            spawn_task_runtime(db, router_tx, core_spawn_deps, task_id)
        }
        Err(error) => FactoryOutput::Failed(map_load_task_failure(Some(task_id), error)),
    }
}

fn spawn_task_runtime(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    task_id: TaskId,
) -> FactoryOutput {
    match spawn_task_runtime_created(db, router_tx, core_spawn_deps, task_id) {
        Ok(created) => FactoryOutput::RuntimeCreated(created),
        Err(failure) => FactoryOutput::Failed(failure),
    }
}

fn spawn_task_runtime_created(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    task_id: TaskId,
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
        DbError::InvalidTaskStatus {
            status: selvedge_command_model::TaskStatus::Archived,
        } => FactoryFailure {
            task_id,
            kind: FactoryFailureKind::TaskArchived,
            message: "task is archived".to_owned(),
        },
        error @ DbError::InvalidTaskStatus { .. } => FactoryFailure {
            task_id,
            kind: FactoryFailureKind::DbReadFailed,
            message: error.to_string(),
        },
        DbError::StaleFunctionCall | DbError::HistoryCursorNotOnTask => FactoryFailure {
            task_id,
            kind: FactoryFailureKind::DbReadFailed,
            message: error.to_string(),
        },
        error => FactoryFailure {
            task_id,
            kind: FactoryFailureKind::DbReadFailed,
            message: error.to_string(),
        },
    }
}

fn spawn_error_message(error: SpawnTaskRuntimeError) -> String {
    match error {
        SpawnTaskRuntimeError::TokioSpawnFailed => "task runtime tokio spawn failed",
    }
    .to_owned()
}
