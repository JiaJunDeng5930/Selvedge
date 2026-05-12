#![doc = include_str!("../README.md")]
//! @behavior selvedge.task.runtime Task runtime operations create or skip router-owned runtimes for active tasks.
//! @behavior selvedge.task.runtime.factory Factory operations return one router-visible result for each requested runtime effect.
//! @behavior selvedge.task.runtime.factory.run Factory effects create task runtimes, scan missing active task runtimes, or persist a child task and return one router-visible output.
//! @constraint selvedge.task.runtime.factory.one_output Each factory command returns exactly one output envelope carrying the command effect id.

use std::collections::HashSet;
use std::time::{SystemTime, UNIX_EPOCH};

use selvedge_command_model::{
    CreatedRuntimeKind, FactoryEffectId, FactoryFailure, FactoryFailureKind, FactoryOutput,
    FactoryOutputEnvelope, FactoryScanOutput, FactorySkipReason, FactorySkippedTask,
    FactoryTaskFailure, RouterIngressWeakSender, TaskRuntimeCreated,
};
use selvedge_core::{SpawnTaskRuntimeArgs, SpawnTaskRuntimeError, TaskRuntimeSpawnDeps};
use selvedge_db::{
    CreateChildTaskInput, DbError, DbPool, TaskId, UnixTs, create_child_task, list_active_tasks,
    load_active_task,
};
use selvedge_domain_model::HistoryNodeId;
use uuid::Uuid;

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.task.runtime.factory.command Factory commands ask the factory to ensure one runtime, scan missing runtimes, or create a child task runtime.
pub enum FactoryCommand {
    // @behavior selvedge.task.runtime.factory.command.ensure_task EnsureTaskRuntime requests a runtime for one existing active task.
    EnsureTaskRuntime(EnsureTaskRuntimeCommand),
    // @behavior selvedge.task.runtime.factory.command.ensure_missing EnsureMissingTaskRuntimes requests runtime creation for active tasks absent from router inventory.
    EnsureMissingTaskRuntimes(EnsureMissingTaskRuntimesCommand),
    // @behavior selvedge.task.runtime.factory.command.create_child CreateChildTaskAndRuntime requests durable child task creation followed by child runtime creation.
    CreateChildTaskAndRuntime(CreateChildTaskAndRuntimeCommand),
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.task.runtime.factory.command.ensure_task.args EnsureTaskRuntimeCommand carries the router effect id and target task id for one runtime request.
pub struct EnsureTaskRuntimeCommand {
    // @behavior selvedge.task.runtime.factory.command.ensure_task.effect_id The ensure-task effect id is copied into the factory output envelope.
    pub effect_id: FactoryEffectId,
    // @behavior selvedge.task.runtime.factory.command.ensure_task.task_id The ensure-task task id identifies the active task that should receive a runtime.
    pub task_id: TaskId,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.task.runtime.factory.command.ensure_missing.args EnsureMissingTaskRuntimesCommand carries the router effect id for one active-task scan.
pub struct EnsureMissingTaskRuntimesCommand {
    // @behavior selvedge.task.runtime.factory.command.ensure_missing.effect_id The ensure-missing effect id is copied into the factory output envelope.
    pub effect_id: FactoryEffectId,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.task.runtime.factory.command.create_child.args CreateChildTaskAndRuntimeCommand carries the router effect id, parent task id, and child cursor node id.
pub struct CreateChildTaskAndRuntimeCommand {
    // @behavior selvedge.task.runtime.factory.command.create_child.effect_id The create-child effect id is copied into the factory output envelope.
    pub effect_id: FactoryEffectId,
    // @behavior selvedge.task.runtime.factory.command.create_child.parent_task The parent task id identifies the active parent whose task settings and parent edge are used for the child.
    pub parent_task_id: TaskId,
    // @behavior selvedge.task.runtime.factory.command.create_child.cursor The child cursor node id identifies the existing history node that becomes the child task cursor.
    pub child_cursor_node_id: HistoryNodeId,
}

#[derive(Clone)]
// @behavior selvedge.task.runtime.factory.effect_args Factory effect arguments carry the requested command and all router-supplied boundaries needed to produce a factory output.
pub struct FactoryEffectArgs {
    // @behavior selvedge.task.runtime.factory.effect_args.command The factory command selects the visible factory operation.
    pub command: FactoryCommand,
    // @behavior selvedge.task.runtime.factory.effect_args.db The database pool is used to read active tasks and persist child task data.
    pub db: DbPool,
    // @behavior selvedge.task.runtime.factory.effect_args.router The weak router sender is passed to created runtimes for future router-visible output.
    pub router_tx: RouterIngressWeakSender,
    // @behavior selvedge.task.runtime.factory.effect_args.spawn_deps Runtime spawn dependencies determine the task runtime config and spawn boundary used by factory creation.
    pub core_spawn_deps: TaskRuntimeSpawnDeps,
    // @behavior selvedge.task.runtime.factory.effect_args.inventory Runtime inventory tells the factory which task runtimes are already live or pending in the router.
    pub runtime_inventory: FactoryRuntimeInventory,
}

#[derive(Clone, Debug, PartialEq, Eq)]
// @behavior selvedge.task.runtime.factory.inventory Factory runtime inventory reflects router-owned live and pending runtime state at effect admission time.
pub struct FactoryRuntimeInventory {
    // @behavior selvedge.task.runtime.factory.inventory.live Live task runtime ids are skipped during scans and rejected during single-task ensure requests.
    pub live_task_runtimes: Vec<TaskId>,
    // @behavior selvedge.task.runtime.factory.inventory.pending Pending task runtime task ids are skipped during scans and rejected during single-task ensure requests.
    pub pending_task_runtime_effects: Vec<TaskId>,
}

// @behavior selvedge.task.runtime.factory.dispatch run_factory_effect dispatches the requested factory command and returns its result in the matching effect envelope.
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

// @behavior selvedge.task.runtime.factory.create_child Factory child creation persists a child task then returns the runtime creation output for that child.
fn create_child_task_and_runtime(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    parent_task_id: TaskId,
    child_cursor_node_id: HistoryNodeId,
) -> FactoryOutput {
    let child_task_id = TaskId(format!("child-{}", Uuid::new_v4()));
    // @behavior selvedge.task.runtime.factory.create_child.persist Child task persistence happens before child runtime spawning.
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
        // @behavior selvedge.task.runtime.factory.create_child.persist_failure Child task persistence failures are mapped to parent-scoped factory failures.
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

// @behavior selvedge.task.runtime.factory.scan Factory scans active tasks and reports created, skipped, and failed runtime outcomes in one scan output.
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
    let active_tasks = match list_active_tasks(db) {
        Ok(active_tasks) => active_tasks,
        // @behavior selvedge.task.runtime.factory.scan.list_failure Active-task scan read failures return a factory failure without a task id.
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
            // @behavior selvedge.task.runtime.factory.scan.skip_live Active tasks with live runtimes are reported as skipped with RuntimeAlreadyLive.
            skipped.push(FactorySkippedTask {
                task_id: task.task_id,
                reason: FactorySkipReason::RuntimeAlreadyLive,
            });
            continue;
        }
        if pending_task_runtime_effects.contains(&task.task_id) {
            // @behavior selvedge.task.runtime.factory.scan.skip_pending Active tasks with pending runtime creation are reported as skipped with RuntimeCreationPending.
            skipped.push(FactorySkippedTask {
                task_id: task.task_id,
                reason: FactorySkipReason::RuntimeCreationPending,
            });
            continue;
        }
        let task_id = task.task_id;
        let failure_task_id = task_id.clone();
        // @behavior selvedge.task.runtime.factory.scan.spawn_result Active-task scans record each runtime creation success or failure in the scan output for that task.
        match spawn_task_runtime_created(
            db,
            router_tx,
            core_spawn_deps,
            task_id,
            CreatedRuntimeKind::ExistingTaskRuntime,
        ) {
            Ok(runtime) => created.push(runtime),
            // @behavior selvedge.task.runtime.factory.scan.spawn_failure Active-task scan spawn failures are recorded in the scan failure list for the affected task.
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

// @behavior selvedge.task.runtime.factory.ensure_one Factory ensures one active task has a runtime or returns a typed factory failure for that task.
fn ensure_task_runtime(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    runtime_inventory: &FactoryRuntimeInventory,
    task_id: TaskId,
    created_runtime_kind: CreatedRuntimeKind,
) -> FactoryOutput {
    match load_active_task(db, &task_id) {
        Ok(_) => {
            if runtime_inventory.live_task_runtimes.contains(&task_id) {
                // @behavior selvedge.task.runtime.factory.ensure_one.live A single-task ensure request for a live runtime returns RuntimeAlreadyLive for that task.
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
                // @behavior selvedge.task.runtime.factory.ensure_one.pending A single-task ensure request for a pending runtime creation returns RuntimeCreationPending for that task.
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
        // @behavior selvedge.task.runtime.factory.ensure_one.load_failure A single-task ensure request maps missing, archived, and database read failures to typed factory failures.
        Err(error) => FactoryOutput::Failed(map_load_task_failure(Some(task_id), error)),
    }
}

// @behavior selvedge.task.runtime.factory.spawn_runtime Factory runtime spawning returns a created runtime output or failed output for the requested task.
fn spawn_task_runtime(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
    core_spawn_deps: &TaskRuntimeSpawnDeps,
    task_id: TaskId,
    created_runtime_kind: CreatedRuntimeKind,
) -> FactoryOutput {
    // @behavior selvedge.task.runtime.factory.spawn_runtime.result Runtime spawn results are converted into router-visible created or failed factory outputs.
    match spawn_task_runtime_created(
        db,
        router_tx,
        core_spawn_deps,
        task_id,
        created_runtime_kind,
    ) {
        Ok(created) => FactoryOutput::RuntimeCreated(created),
        // @behavior selvedge.task.runtime.factory.spawn_runtime.failure Runtime spawn failures are returned as failed factory output for the requested task.
        Err(failure) => FactoryOutput::Failed(failure),
    }
}

// @behavior selvedge.task.runtime.factory.spawn_created Factory runtime creation returns the created runtime details or a typed factory failure.
fn spawn_task_runtime_created(
    db: &DbPool,
    router_tx: &RouterIngressWeakSender,
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
        // @behavior selvedge.task.runtime.factory.spawn_created.spawn_failure Core spawn errors are mapped to CoreSpawnFailed with a task-scoped failure message.
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
