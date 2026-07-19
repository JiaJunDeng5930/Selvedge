use std::collections::HashMap;

use selvedge_command_model::{
    FactoryEffectId, FactoryFailureKind, FactoryOutput, FactorySkipReason,
};
use selvedge_core::{TaskRuntimeConfig, TaskRuntimeSpawnDeps};
use selvedge_db::{DbPool, ModelProfileKey, TaskId, UnixTs, archive_task};
use selvedge_domain_model::ModelProviderProfile;
use selvedge_task_runtime_factory::{
    FactoryCommand, FactoryEffectArgs, FactoryRuntimeInventory, run_factory_effect,
};
use selvedge_test_support::db::{
    create_root_task_with_user_message, default_model_profiles, open_memory_db,
};

#[tokio::test]
async fn ensure_task_runtime_creates_runtime_for_existing_active_task() {
    let db = open_memory_db();
    create_root(&db, "task-1");

    let (router_tx, mut router_rx) = tokio::sync::mpsc::unbounded_channel();
    let envelope = run_factory_effect(FactoryEffectArgs {
        effect_id: FactoryEffectId("factory-1".to_owned()),
        command: FactoryCommand::EnsureTaskRuntime {
            task_id: TaskId("task-1".to_owned()),
        },
        db,
        router_tx: router_tx.downgrade(),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
        runtime_inventory: empty_inventory(),
    });
    assert_eq!(envelope.effect_id, FactoryEffectId("factory-1".to_owned()));
    let FactoryOutput::RuntimeCreated(created) = envelope.output else {
        panic!("unexpected factory output");
    };
    assert_eq!(created.task_id, TaskId("task-1".to_owned()));

    assert!(router_rx.try_recv().is_err());
}

#[tokio::test]
async fn ensure_task_runtime_reports_live_and_pending_inventory() {
    let db = open_memory_db();
    create_root(&db, "live");
    let live = run_ensure_task_runtime_with_inventory(
        db,
        "live",
        vec![TaskId("live".to_owned())],
        Vec::new(),
    )
    .await;
    let FactoryOutput::Failed(failure) = live else {
        panic!("unexpected factory output");
    };
    assert_eq!(failure.kind, FactoryFailureKind::RuntimeAlreadyLive);

    let db = open_memory_db();
    create_root(&db, "pending");
    let pending = run_ensure_task_runtime_with_inventory(
        db,
        "pending",
        Vec::new(),
        vec![TaskId("pending".to_owned())],
    )
    .await;
    let FactoryOutput::Failed(failure) = pending else {
        panic!("unexpected factory output");
    };
    assert_eq!(failure.kind, FactoryFailureKind::RuntimeCreationPending);
}

#[tokio::test]
async fn ensure_task_runtime_reports_missing_and_archived_tasks() {
    let missing = run_ensure_task_runtime(open_memory_db(), "missing").await;
    let FactoryOutput::Failed(failure) = missing else {
        panic!("unexpected factory output");
    };
    assert_eq!(failure.task_id, Some(TaskId("missing".to_owned())));
    assert_eq!(failure.kind, FactoryFailureKind::TaskMissing);

    let db = open_memory_db();
    create_root(&db, "archived");
    archive_task(&db, &TaskId("archived".to_owned()), UnixTs(2)).expect("archive task");

    let archived = run_ensure_task_runtime(db, "archived").await;
    let FactoryOutput::Failed(failure) = archived else {
        panic!("unexpected factory output");
    };
    assert_eq!(failure.task_id, Some(TaskId("archived".to_owned())));
    assert_eq!(failure.kind, FactoryFailureKind::TaskArchived);
}

#[tokio::test]
async fn ensure_missing_task_runtimes_skips_live_and_pending_inventory() {
    let db = open_memory_db();
    create_root(&db, "live");
    create_root(&db, "pending");
    create_root(&db, "missing");

    let (router_tx, _router_rx) = tokio::sync::mpsc::unbounded_channel();
    let envelope = run_factory_effect(FactoryEffectArgs {
        effect_id: FactoryEffectId("factory-scan".to_owned()),
        command: FactoryCommand::EnsureMissingTaskRuntimes,
        db,
        router_tx: router_tx.downgrade(),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
        runtime_inventory: FactoryRuntimeInventory {
            live_task_runtimes: vec![TaskId("live".to_owned())],
            pending_task_runtime_effects: vec![TaskId("pending".to_owned())],
        },
    });
    assert_eq!(
        envelope.effect_id,
        FactoryEffectId("factory-scan".to_owned())
    );
    let FactoryOutput::ScanFinished(scan) = envelope.output else {
        panic!("unexpected factory output");
    };

    assert_eq!(scan.created.len(), 1);
    assert_eq!(scan.created[0].task_id, TaskId("missing".to_owned()));
    assert_eq!(scan.failed, Vec::new());
    assert_eq!(scan.skipped.len(), 2);
    assert!(scan.skipped.iter().any(|skipped| {
        skipped.task_id == TaskId("live".to_owned())
            && skipped.reason == FactorySkipReason::RuntimeAlreadyLive
    }));
    assert!(scan.skipped.iter().any(|skipped| {
        skipped.task_id == TaskId("pending".to_owned())
            && skipped.reason == FactorySkipReason::RuntimeCreationPending
    }));
}

fn create_root(db: &DbPool, task_id: &str) {
    create_root_task_with_user_message(db, task_id, "hello", UnixTs(1));
}

fn model_profiles() -> HashMap<ModelProfileKey, ModelProviderProfile> {
    default_model_profiles()
}

async fn run_ensure_task_runtime(db: DbPool, task_id: &str) -> FactoryOutput {
    let (router_tx, _router_rx) = tokio::sync::mpsc::unbounded_channel();
    run_factory_effect(FactoryEffectArgs {
        effect_id: FactoryEffectId("factory-1".to_owned()),
        command: FactoryCommand::EnsureTaskRuntime {
            task_id: TaskId(task_id.to_owned()),
        },
        db,
        router_tx: router_tx.downgrade(),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
        runtime_inventory: empty_inventory(),
    })
    .output
}

async fn run_ensure_task_runtime_with_inventory(
    db: DbPool,
    task_id: &str,
    live_task_runtimes: Vec<TaskId>,
    pending_task_runtime_effects: Vec<TaskId>,
) -> FactoryOutput {
    let (router_tx, _router_rx) = tokio::sync::mpsc::unbounded_channel();
    run_factory_effect(FactoryEffectArgs {
        effect_id: FactoryEffectId("factory-1".to_owned()),
        command: FactoryCommand::EnsureTaskRuntime {
            task_id: TaskId(task_id.to_owned()),
        },
        db,
        router_tx: router_tx.downgrade(),
        core_spawn_deps: TaskRuntimeSpawnDeps::new(TaskRuntimeConfig {
            mailbox_capacity: 8,
            model_profiles: model_profiles(),
        }),
        runtime_inventory: FactoryRuntimeInventory {
            live_task_runtimes,
            pending_task_runtime_effects,
        },
    })
    .output
}

fn empty_inventory() -> FactoryRuntimeInventory {
    FactoryRuntimeInventory {
        live_task_runtimes: Vec::new(),
        pending_task_runtime_effects: Vec::new(),
    }
}
