#![doc = include_str!("../README.md")]

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use selvedge_api::ModelProviderRegistry;
use selvedge_command_model::{
    ApiOutputEnvelope, ArchiveTask, ClientCommand, ClientCommandEnvelope, ClientCommandId,
    ClientId, ClientNotice, ClientNoticeLevel, ClientSnapshot, ClientSubscription,
    CoreOutputEnvelope, CoreOutputMessage, DeliverNotice, DeliverSnapshot, DetailLevel,
    DomainEvent, DomainEventPublishRequest, EventControlMessage, EventIngress, EventIngressSender,
    FactoryEffectId, FactoryFailure, FactoryFailureKind, FactoryOutput, FactoryOutputEnvelope,
    HistoryNodeProjection, HistoryNodeProjectionBody, ModelCallDispatchRequest, ModelCallError,
    ModelCallErrorKind, ModelCallStatusPhase, ModelCallStatusRawEvent, ModelRunId, RawEvent,
    RouterIngressMessage, RouterIngressSender, RouterShutdown, RuntimeInventoryQuery,
    RuntimeInventoryResponse, SnapshotTaskVersion, StopTaskRuntime, SubmitUserInput, TaskId,
    TaskParentProjection, TaskProjection, TaskProjectionStatus, TaskRuntimeCommand,
    TaskRuntimeExitNotice, TaskRuntimeHandle, TaskRuntimeSender, TaskRuntimeToken, TaskScope,
    ToolExecutionRequest, ToolExecutionResult, ToolExecutionRunId, ToolExecutionStatusPhase,
    ToolExecutionStatusRawEvent,
};
use selvedge_db::{DbPool, HistoryNode, TaskRow, TaskStatusRow, UnixTs};
use selvedge_domain_model::HistoryNodeId;
use selvedge_task_runtime_factory::{
    CreateChildTaskAndRuntimeCommand, EnsureMissingTaskRuntimesCommand, EnsureTaskRuntimeCommand,
    FactoryCommand, SpawnFactoryEffectError,
};
use tokio::sync::mpsc;
use tokio::task::JoinHandle;
use uuid::Uuid;

#[derive(Clone)]
pub struct RouterStartArgs {
    pub db: DbPool,
    pub events_tx: EventIngressSender,
    pub factory_executor: Arc<dyn FactoryExecutor>,
    pub api_executor: Arc<dyn ApiExecutor>,
    pub tool_executor: Arc<dyn ToolExecutor>,
    pub ingress_capacity: usize,
    pub pending_task_command_limit: usize,
}

#[derive(Debug)]
pub struct RouterHandle {
    pub router_tx: RouterIngressSender,
    pub join_handle: JoinHandle<()>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SpawnRouterError {
    MissingDbHandle,
    MissingEventsSender,
    MissingFactoryExecutor,
    MissingApiExecutor,
    MissingToolExecutor,
    InvalidIngressCapacity,
    InvalidPendingTaskCommandLimit,
    TokioSpawnFailed,
}

#[derive(Clone)]
pub struct FactorySpawnRequest {
    pub command: FactoryCommand,
    pub db: DbPool,
    pub router_tx: RouterIngressSender,
}

pub trait FactoryExecutor: Send + Sync {
    fn spawn_factory_effect(
        &self,
        request: FactorySpawnRequest,
    ) -> Result<JoinHandle<()>, SpawnFactoryEffectError>;
}

pub trait ApiExecutor: Send + Sync {
    fn spawn_model_call(
        &self,
        request: ModelCallDispatchRequest,
        router_tx: RouterIngressSender,
    ) -> Result<JoinHandle<()>, SpawnApiEffectError>;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SpawnApiEffectError {
    TokioSpawnFailed,
}

pub trait ToolExecutor: Send + Sync {
    fn spawn_tool_execution(
        &self,
        request: ToolExecutionRequest,
        router_tx: RouterIngressSender,
    ) -> Result<JoinHandle<()>, SpawnToolEffectError>;
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum SpawnToolEffectError {
    TokioSpawnFailed,
}

pub struct TokioApiExecutor {
    pub provider_registry: Arc<dyn ModelProviderRegistry>,
    pub config: selvedge_api::ApiExecutorConfig,
}

impl ApiExecutor for TokioApiExecutor {
    fn spawn_model_call(
        &self,
        request: ModelCallDispatchRequest,
        router_tx: RouterIngressSender,
    ) -> Result<JoinHandle<()>, SpawnApiEffectError> {
        let provider_registry = self.provider_registry.clone();
        let config = self.config.clone();
        Ok(tokio::spawn(async move {
            selvedge_api::execute_model_call(request, router_tx, provider_registry, config).await;
        }))
    }
}

pub fn spawn_router(args: RouterStartArgs) -> Result<RouterHandle, SpawnRouterError> {
    if args.ingress_capacity == 0 {
        return Err(SpawnRouterError::InvalidIngressCapacity);
    }
    if args.pending_task_command_limit == 0 {
        return Err(SpawnRouterError::InvalidPendingTaskCommandLimit);
    }

    let (router_tx, router_rx) = mpsc::channel(args.ingress_capacity);
    let actor = RouterActor {
        db: args.db,
        events_tx: args.events_tx,
        factory_executor: args.factory_executor,
        api_executor: args.api_executor,
        tool_executor: args.tool_executor,
        router_tx: router_tx.clone(),
        router_rx,
        pending_task_command_limit: args.pending_task_command_limit,
        runtimes: BTreeMap::new(),
        pending_creations_by_task: BTreeMap::new(),
        effects: HashMap::new(),
        waiting_task_commands: BTreeMap::new(),
        client_sessions: HashMap::new(),
        deferred_ensures: BTreeSet::new(),
        deferred_scan: false,
        in_flight_model_calls: HashMap::new(),
        in_flight_tool_executions: HashMap::new(),
    };
    let join_handle = tokio::spawn(actor.run());

    Ok(RouterHandle {
        router_tx,
        join_handle,
    })
}

struct RouterActor {
    db: DbPool,
    events_tx: EventIngressSender,
    factory_executor: Arc<dyn FactoryExecutor>,
    api_executor: Arc<dyn ApiExecutor>,
    tool_executor: Arc<dyn ToolExecutor>,
    router_tx: RouterIngressSender,
    router_rx: mpsc::Receiver<RouterIngressMessage>,
    pending_task_command_limit: usize,
    runtimes: BTreeMap<TaskId, RuntimeEntry>,
    pending_creations_by_task: BTreeMap<TaskId, FactoryEffectId>,
    effects: HashMap<FactoryEffectId, LifecycleEffect>,
    waiting_task_commands: BTreeMap<TaskId, VecDeque<PendingTaskCommand>>,
    client_sessions: HashMap<ClientId, ClientSession>,
    deferred_ensures: BTreeSet<TaskId>,
    deferred_scan: bool,
    in_flight_model_calls: HashMap<(TaskId, ModelRunId), TaskRuntimeToken>,
    in_flight_tool_executions: HashMap<(TaskId, ToolExecutionRunId), TaskRuntimeToken>,
}

struct RuntimeEntry {
    runtime_token: TaskRuntimeToken,
    task_runtime_tx: TaskRuntimeSender,
    removing: bool,
}

enum LifecycleEffect {
    CreateTaskRuntime { task_id: TaskId },
    CreateChildTaskRuntime,
    ScanMissingTaskRuntimes,
    RemoveTaskRuntime { task_id: TaskId },
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum PendingTaskCommand {
    UserInput { message_text: String },
    Archive,
    Stop,
}

#[derive(Clone)]
struct ClientSession {
    command_id: ClientCommandId,
    subscription: ClientSubscription,
}

impl RouterActor {
    async fn run(mut self) {
        while let Some(message) = self.router_rx.recv().await {
            if matches!(message, RouterIngressMessage::Shutdown(RouterShutdown)) {
                self.stop();
                break;
            }
            self.handle_message(message).await;
        }
    }

    async fn handle_message(&mut self, message: RouterIngressMessage) {
        match message {
            RouterIngressMessage::Client(envelope) => self.handle_client_command(envelope).await,
            RouterIngressMessage::Factory(envelope) => self.handle_factory_output(envelope).await,
            RouterIngressMessage::RuntimeInventoryQuery(query) => {
                self.answer_runtime_inventory(query);
            }
            RouterIngressMessage::Api(envelope) => self.route_api_output(envelope).await,
            RouterIngressMessage::Tool(result) => self.route_tool_output(result).await,
            RouterIngressMessage::RuntimeExit(notice) => self.handle_runtime_exit(notice).await,
            RouterIngressMessage::Core(envelope) => self.handle_core_output(envelope).await,
            RouterIngressMessage::PublishToEvents(event) => {
                let raw = self.domain_event_to_raw(event);
                let _ = self.events_tx.send(EventIngress::Raw(raw)).await;
            }
            RouterIngressMessage::Shutdown(_) => {}
        }
    }

    async fn handle_client_command(&mut self, envelope: ClientCommandEnvelope) {
        match envelope.command {
            ClientCommand::SubmitUserInput(input) => {
                self.handle_submit_user_input(envelope.client_id, envelope.command_id, input)
                    .await;
            }
            ClientCommand::ArchiveTask(input) => {
                self.handle_archive_task(envelope.client_id, envelope.command_id, input)
                    .await;
            }
            ClientCommand::StopTaskRuntime(input) => {
                self.handle_stop_task_runtime(envelope.client_id, envelope.command_id, input)
                    .await;
            }
            ClientCommand::EnsureTaskRuntime(input) => {
                self.ensure_task_runtime(input.task_id);
            }
            ClientCommand::EnsureMissingTaskRuntimes(_) => {
                self.ensure_missing_task_runtimes();
            }
            ClientCommand::CreateChildTaskAndRuntime(input) => {
                let effect_id = FactoryEffectId(format!("router-child-{}", Uuid::new_v4()));
                if self.effects.contains_key(&effect_id) {
                    return;
                }
                self.effects
                    .insert(effect_id.clone(), LifecycleEffect::CreateChildTaskRuntime);
                let command =
                    FactoryCommand::CreateChildTaskAndRuntime(CreateChildTaskAndRuntimeCommand {
                        effect_id,
                        parent_task_id: input.parent_task_id,
                        child_cursor_node_id: input.child_cursor_node_id,
                    });
                self.spawn_factory(command);
            }
            ClientCommand::AttachClient(input) => {
                let client_id = input.client_id.clone();
                let subscription = input.subscription.clone();
                self.client_sessions.insert(
                    client_id.clone(),
                    ClientSession {
                        command_id: envelope.command_id.clone(),
                        subscription: subscription.clone(),
                    },
                );
                let _ = self
                    .events_tx
                    .send(EventIngress::Control(
                        EventControlMessage::BeginClientHydration(
                            selvedge_command_model::BeginClientHydration {
                                client_id: input.client_id,
                                client_command_id: envelope.command_id.clone(),
                                outbound: input.output_tx,
                                subscription: subscription.clone(),
                            },
                        ),
                    ))
                    .await;
                self.deliver_snapshot(client_id, envelope.command_id, Some(subscription))
                    .await;
            }
            ClientCommand::RefreshClientSnapshot(input) => {
                let session = self.client_session(&input.client_id);
                let command_id = session
                    .as_ref()
                    .map(|session| session.command_id.clone())
                    .unwrap_or(envelope.command_id);
                let subscription = session.map(|session| session.subscription);
                self.deliver_snapshot(input.client_id, command_id, subscription)
                    .await;
            }
            ClientCommand::UpdateClientSubscription(input) => {
                let command_id = self.session_command_id(&input.client_id, envelope.command_id);
                if let Some(session) = self.client_sessions.get_mut(&input.client_id) {
                    session.subscription = input.subscription.clone();
                }
                let _ = self
                    .events_tx
                    .send(EventIngress::Control(
                        EventControlMessage::UpdateSubscription(
                            selvedge_command_model::UpdateSubscription {
                                client_id: input.client_id,
                                client_command_id: command_id,
                                subscription: input.subscription,
                            },
                        ),
                    ))
                    .await;
            }
            ClientCommand::DetachClient(input) => {
                let command_id = self.session_command_id(&input.client_id, envelope.command_id);
                let _ = self
                    .events_tx
                    .send(EventIngress::Control(EventControlMessage::DetachClient(
                        selvedge_command_model::DetachClient {
                            client_id: input.client_id.clone(),
                            client_command_id: command_id,
                            reason: selvedge_command_model::DetachReason::ClientRequested,
                        },
                    )))
                    .await;
                self.client_sessions.remove(&input.client_id);
            }
        }
    }

    async fn handle_submit_user_input(
        &mut self,
        client_id: Option<selvedge_command_model::ClientId>,
        command_id: ClientCommandId,
        input: SubmitUserInput,
    ) {
        let task_id = input.task_id;
        if self.runtime_is_removing(&task_id) {
            if let Some(client_id) = client_id {
                self.send_notice(
                    client_id,
                    command_id,
                    ClientNoticeLevel::Warning,
                    "task runtime is stopping",
                )
                .await;
            }
            return;
        }

        if self.waiting_queue_has_removal(&task_id) {
            if let Some(client_id) = client_id {
                self.send_notice(
                    client_id,
                    command_id,
                    ClientNoticeLevel::Warning,
                    "task runtime is stopping",
                )
                .await;
            }
            return;
        }

        if self.runtimes.contains_key(&task_id) {
            let command = TaskRuntimeCommand::UserInput {
                message_text: input.message_text.clone(),
            };
            if self.route_to_runtime(&task_id, command).await.is_err() {
                self.enqueue_waiting_command(
                    task_id.clone(),
                    PendingTaskCommand::UserInput {
                        message_text: input.message_text,
                    },
                );
                self.ensure_task_runtime(task_id);
            }
            return;
        }

        self.enqueue_waiting_command(
            task_id.clone(),
            PendingTaskCommand::UserInput {
                message_text: input.message_text,
            },
        );
        self.ensure_task_runtime(task_id);
    }

    async fn handle_archive_task(
        &mut self,
        client_id: Option<selvedge_command_model::ClientId>,
        command_id: ClientCommandId,
        input: ArchiveTask,
    ) {
        self.handle_removal_command(
            client_id,
            command_id,
            input.task_id,
            PendingTaskCommand::Archive,
            TaskRuntimeCommand::Archive,
        )
        .await;
    }

    async fn handle_stop_task_runtime(
        &mut self,
        client_id: Option<selvedge_command_model::ClientId>,
        command_id: ClientCommandId,
        input: StopTaskRuntime,
    ) {
        self.handle_removal_command(
            client_id,
            command_id,
            input.task_id,
            PendingTaskCommand::Stop,
            TaskRuntimeCommand::Stop,
        )
        .await;
    }

    async fn handle_removal_command(
        &mut self,
        client_id: Option<selvedge_command_model::ClientId>,
        command_id: ClientCommandId,
        task_id: TaskId,
        pending: PendingTaskCommand,
        runtime_command: TaskRuntimeCommand,
    ) {
        if self.runtime_is_removing(&task_id) {
            if matches!(pending, PendingTaskCommand::Archive) {
                self.enqueue_waiting_command(task_id.clone(), pending);
                self.deferred_ensures.insert(task_id);
                return;
            }
            if let Some(client_id) = client_id {
                self.send_notice(
                    client_id,
                    command_id,
                    ClientNoticeLevel::Warning,
                    "task runtime is stopping",
                )
                .await;
            }
            return;
        }

        if let Some(entry) = self.runtimes.get_mut(&task_id) {
            entry.removing = true;
            let effect_id = FactoryEffectId(format!("router-remove-{}", Uuid::new_v4()));
            self.effects.insert(
                effect_id,
                LifecycleEffect::RemoveTaskRuntime {
                    task_id: task_id.clone(),
                },
            );
            if self
                .route_to_runtime(&task_id, runtime_command)
                .await
                .is_err()
            {
                self.runtimes.remove(&task_id);
                self.clear_removal_effects_for_task(&task_id);
                if matches!(pending, PendingTaskCommand::Archive) {
                    self.enqueue_waiting_command(task_id.clone(), pending);
                    self.ensure_task_runtime(task_id);
                }
            }
            return;
        }

        if self.pending_creations_by_task.contains_key(&task_id) {
            self.enqueue_waiting_command(task_id, pending);
            return;
        }

        if matches!(pending, PendingTaskCommand::Archive) {
            self.enqueue_waiting_command(task_id.clone(), pending);
            self.ensure_task_runtime(task_id);
            return;
        }

        if let Some(client_id) = client_id {
            self.send_notice(
                client_id,
                command_id,
                ClientNoticeLevel::Warning,
                "task runtime is not live",
            )
            .await;
        }
    }

    fn ensure_task_runtime(&mut self, task_id: TaskId) {
        if self
            .runtimes
            .get(&task_id)
            .is_some_and(|entry| entry.removing)
        {
            self.deferred_ensures.insert(task_id);
            return;
        }
        if self.runtimes.contains_key(&task_id)
            || self.pending_creations_by_task.contains_key(&task_id)
        {
            return;
        }
        if self.scan_in_flight() {
            self.deferred_ensures.insert(task_id);
            return;
        }
        self.deferred_ensures.remove(&task_id);
        let effect_id = FactoryEffectId(format!("router-create-{}", Uuid::new_v4()));
        self.pending_creations_by_task
            .insert(task_id.clone(), effect_id.clone());
        self.effects.insert(
            effect_id.clone(),
            LifecycleEffect::CreateTaskRuntime {
                task_id: task_id.clone(),
            },
        );
        self.spawn_factory(FactoryCommand::EnsureTaskRuntime(
            EnsureTaskRuntimeCommand { effect_id, task_id },
        ));
    }

    fn ensure_missing_task_runtimes(&mut self) {
        if self.runtime_removal_in_flight() {
            self.deferred_scan = true;
            return;
        }
        let has_scan = self
            .effects
            .values()
            .any(|effect| matches!(effect, LifecycleEffect::ScanMissingTaskRuntimes));
        if has_scan {
            self.deferred_scan = true;
            return;
        }
        let effect_id = FactoryEffectId(format!("router-scan-{}", Uuid::new_v4()));
        self.effects
            .insert(effect_id.clone(), LifecycleEffect::ScanMissingTaskRuntimes);
        self.spawn_factory(FactoryCommand::EnsureMissingTaskRuntimes(
            EnsureMissingTaskRuntimesCommand { effect_id },
        ));
    }

    fn spawn_factory(&mut self, command: FactoryCommand) {
        let cleanup_command = command.clone();
        let request = FactorySpawnRequest {
            command,
            db: self.db.clone(),
            router_tx: self.router_tx.clone(),
        };
        if self.factory_executor.spawn_factory_effect(request).is_err() {
            self.clear_failed_factory_spawn(cleanup_command);
        }
    }

    async fn handle_factory_output(&mut self, envelope: FactoryOutputEnvelope) {
        let Some(effect) = self.effects.remove(&envelope.effect_id) else {
            return;
        };

        match (&effect, envelope.output) {
            (_, FactoryOutput::RuntimeCreated(created)) => {
                self.finish_task_creation_effect(&effect);
                self.register_created_runtime(created.task_id, created.runtime)
                    .await;
            }
            (_, FactoryOutput::ScanFinished(scan)) => {
                for created in scan.created {
                    self.register_created_runtime(created.task_id, created.runtime)
                        .await;
                }
                for failure in scan.failed {
                    self.send_failure_notice(FactoryFailure {
                        task_id: Some(failure.task_id),
                        kind: failure.kind,
                        message: failure.message,
                    })
                    .await;
                }
                self.retry_deferred_ensures();
                self.retry_waiting_tasks_without_runtime();
                self.retry_deferred_scan();
            }
            (LifecycleEffect::CreateTaskRuntime { task_id }, FactoryOutput::Failed(failure)) => {
                let retryable = retryable_creation_failure(&failure.kind);
                self.pending_creations_by_task.remove(task_id);
                if !retryable {
                    self.waiting_task_commands.remove(task_id);
                }
                self.send_failure_notice(failure).await;
            }
            (LifecycleEffect::CreateChildTaskRuntime, FactoryOutput::Failed(failure)) => {
                let retry_task_id = if retryable_creation_failure(&failure.kind) {
                    failure.task_id.clone()
                } else {
                    None
                };
                self.send_failure_notice(failure).await;
                if let Some(task_id) = retry_task_id {
                    self.ensure_task_runtime(task_id);
                }
            }
            (_, FactoryOutput::Failed(failure)) => {
                self.send_failure_notice(failure).await;
                if matches!(effect, LifecycleEffect::ScanMissingTaskRuntimes) {
                    self.retry_deferred_ensures();
                    self.retry_waiting_tasks_without_runtime();
                    self.retry_deferred_scan();
                }
            }
        }
    }

    async fn register_created_runtime(&mut self, task_id: TaskId, runtime: TaskRuntimeHandle) {
        self.pending_creations_by_task.remove(&task_id);
        self.deferred_ensures.remove(&task_id);
        if self.runtimes.contains_key(&task_id) {
            return;
        }

        let entry = RuntimeEntry {
            runtime_token: runtime.runtime_token,
            task_runtime_tx: runtime.task_runtime_tx,
            removing: false,
        };
        self.runtimes.insert(task_id.clone(), entry);

        let start_failed = self.should_start_before_waiting_commands(&task_id)
            && self
                .route_to_runtime(&task_id, TaskRuntimeCommand::Start)
                .await
                .is_err();
        if start_failed {
            self.runtimes.remove(&task_id);
            self.ensure_task_runtime(task_id);
            return;
        }

        self.flush_waiting_commands(task_id).await;
    }

    fn should_start_before_waiting_commands(&self, task_id: &TaskId) -> bool {
        self.waiting_task_commands
            .get(task_id)
            .is_none_or(|commands| {
                commands
                    .front()
                    .is_some_and(|command| matches!(command, PendingTaskCommand::UserInput { .. }))
            })
    }

    async fn flush_waiting_commands(&mut self, task_id: TaskId) {
        let Some(commands) = self.waiting_task_commands.remove(&task_id) else {
            return;
        };

        let mut commands = commands;
        while let Some(command) = commands.pop_front() {
            let has_later_archive = commands
                .iter()
                .any(|command| matches!(command, PendingTaskCommand::Archive));
            let is_stop = matches!(command, PendingTaskCommand::Stop);
            let pending_command = command.clone();
            let runtime_command = match command {
                PendingTaskCommand::UserInput { message_text } => {
                    TaskRuntimeCommand::UserInput { message_text }
                }
                PendingTaskCommand::Archive => TaskRuntimeCommand::Archive,
                PendingTaskCommand::Stop => TaskRuntimeCommand::Stop,
            };
            if matches!(
                runtime_command,
                TaskRuntimeCommand::Archive | TaskRuntimeCommand::Stop
            ) && let Some(entry) = self.runtimes.get_mut(&task_id)
            {
                entry.removing = true;
            }
            if self
                .route_to_runtime(&task_id, runtime_command)
                .await
                .is_err()
            {
                self.runtimes.remove(&task_id);
                self.requeue_failed_flush(task_id.clone(), pending_command, commands);
                break;
            }
            if is_stop && has_later_archive {
                self.enqueue_waiting_command(task_id.clone(), PendingTaskCommand::Archive);
                self.deferred_ensures.insert(task_id.clone());
                break;
            }
        }
    }

    async fn route_api_output(&mut self, envelope: ApiOutputEnvelope) {
        let (task_id, model_call_id, phase) = match &envelope {
            ApiOutputEnvelope::Success { correlation, .. } => (
                correlation.task_id.clone(),
                correlation.model_run_id.clone(),
                ModelCallStatusPhase::Completed,
            ),
            ApiOutputEnvelope::Failure { correlation, .. } => (
                correlation.task_id.clone(),
                correlation.model_run_id.clone(),
                ModelCallStatusPhase::Failed,
            ),
        };
        if !self.take_matching_model_call(&task_id, &model_call_id) {
            return;
        }
        let routed = self
            .route_to_runtime(&task_id, TaskRuntimeCommand::ApiModelReply(envelope))
            .await;
        self.send_model_call_status(
            task_id,
            model_call_id,
            if routed.is_ok() {
                phase
            } else {
                ModelCallStatusPhase::Discarded
            },
        )
        .await;
    }

    async fn route_tool_output(&mut self, result: ToolExecutionResult) {
        let task_id = result.task_id.clone();
        if !self.take_matching_tool_execution(&task_id, &result.tool_execution_run_id) {
            return;
        }
        let status = ToolExecutionStatusRawEvent {
            task_id: result.task_id.clone(),
            tool_execution_run_id: result.tool_execution_run_id.clone(),
            function_call_node_id: result.function_call_node_id,
            tool_name: result.tool_name.clone(),
            phase: if result.is_error {
                ToolExecutionStatusPhase::Failed
            } else {
                ToolExecutionStatusPhase::Completed
            },
        };
        let routed = self
            .route_to_runtime(&task_id, TaskRuntimeCommand::ToolResult(result))
            .await;
        self.send_tool_execution_status(ToolExecutionStatusRawEvent {
            phase: if routed.is_ok() {
                status.phase
            } else {
                ToolExecutionStatusPhase::Discarded
            },
            ..status
        })
        .await;
    }

    async fn route_to_runtime(
        &mut self,
        task_id: &TaskId,
        command: TaskRuntimeCommand,
    ) -> Result<(), ()> {
        let is_removal_command = matches!(
            command,
            TaskRuntimeCommand::Archive | TaskRuntimeCommand::Stop
        );
        let Some((sender, removing)) = self
            .runtimes
            .get(task_id)
            .map(|entry| (entry.task_runtime_tx.clone(), entry.removing))
        else {
            return Err(());
        };

        if sender.send(command).await.is_err() {
            if removing && !is_removal_command {
                return Err(());
            }
            self.runtimes.remove(task_id);
            self.clear_in_flight_for_task(task_id);
            if removing {
                self.clear_removal_effects_for_task(task_id);
                self.retry_deferred_ensures();
                self.retry_deferred_scan();
            }
            return Err(());
        }
        Ok(())
    }

    async fn handle_runtime_exit(&mut self, notice: TaskRuntimeExitNotice) {
        let should_remove = self
            .runtimes
            .get(&notice.task_id)
            .is_some_and(|entry| entry.runtime_token == notice.runtime_token);
        if should_remove {
            match &notice.reason {
                selvedge_command_model::TaskRuntimeExitReason::Archived => {
                    let raw = self.task_changed_raw_event(notice.task_id.clone());
                    let _ = self.events_tx.send(EventIngress::Raw(raw)).await;
                }
                selvedge_command_model::TaskRuntimeExitReason::DbError(message)
                | selvedge_command_model::TaskRuntimeExitReason::InternalError(message) => {
                    let _ = self
                        .events_tx
                        .send(EventIngress::Raw(RawEvent::Debug(
                            selvedge_command_model::DebugRawEvent {
                                task_id: Some(notice.task_id.clone()),
                                message_text: message.clone(),
                            },
                        )))
                        .await;
                }
                selvedge_command_model::TaskRuntimeExitReason::Stopped => {}
            }
            self.runtimes.remove(&notice.task_id);
            self.clear_in_flight_for_task(&notice.task_id);
            self.clear_removal_effects_for_task(&notice.task_id);
            self.retry_deferred_ensures();
            self.retry_deferred_scan();
        }
    }

    async fn handle_core_output(&mut self, envelope: CoreOutputEnvelope) {
        let task_id = envelope.task_id;
        if !self.runtime_token_matches(&task_id, &envelope.runtime_token) {
            return;
        }
        let runtime_token = envelope.runtime_token;
        match envelope.message {
            CoreOutputMessage::RequestModelCall(request) => {
                if !self.runtime_accepts_external_requests(&task_id) {
                    return;
                }
                let correlation = request.correlation.clone();
                self.in_flight_model_calls.insert(
                    (
                        correlation.task_id.clone(),
                        correlation.model_run_id.clone(),
                    ),
                    runtime_token.clone(),
                );
                self.send_model_call_status(
                    correlation.task_id.clone(),
                    correlation.model_run_id.clone(),
                    ModelCallStatusPhase::Requested,
                )
                .await;
                if self
                    .api_executor
                    .spawn_model_call(request, self.router_tx.clone())
                    .is_err()
                {
                    self.route_api_output(ApiOutputEnvelope::Failure {
                        correlation,
                        error: ModelCallError {
                            kind: ModelCallErrorKind::ProviderRequest,
                            message: "api executor spawn failed".to_owned(),
                        },
                    })
                    .await;
                }
            }
            CoreOutputMessage::RequestToolExecution(request) => {
                if !self.runtime_accepts_external_requests(&task_id) {
                    return;
                }
                self.in_flight_tool_executions.insert(
                    (
                        request.task_id.clone(),
                        request.tool_execution_run_id.clone(),
                    ),
                    runtime_token.clone(),
                );
                self.send_tool_execution_status(ToolExecutionStatusRawEvent {
                    task_id: request.task_id.clone(),
                    tool_execution_run_id: request.tool_execution_run_id.clone(),
                    function_call_node_id: request.function_call_node_id,
                    tool_name: request.tool_name.clone(),
                    phase: ToolExecutionStatusPhase::Requested,
                })
                .await;
                let failure = ToolExecutionResult {
                    task_id: request.task_id.clone(),
                    tool_execution_run_id: request.tool_execution_run_id.clone(),
                    function_call_node_id: request.function_call_node_id,
                    function_call_id: request.function_call_id.clone(),
                    tool_name: request.tool_name.clone(),
                    output_text: "tool executor spawn failed".to_owned(),
                    is_error: true,
                };
                if self
                    .tool_executor
                    .spawn_tool_execution(request, self.router_tx.clone())
                    .is_err()
                {
                    self.route_tool_output(failure).await;
                }
            }
            CoreOutputMessage::PublishDomainEvent(event) => {
                let raw = self.domain_event_to_raw(event);
                let _ = self.events_tx.send(EventIngress::Raw(raw)).await;
            }
            CoreOutputMessage::RuntimeReady => {
                let raw = self.task_changed_raw_event(task_id);
                let _ = self.events_tx.send(EventIngress::Raw(raw)).await;
            }
        }
    }

    fn answer_runtime_inventory(&mut self, query: RuntimeInventoryQuery) {
        let response = RuntimeInventoryResponse {
            live_task_runtimes: self.runtimes.keys().cloned().collect(),
            pending_task_runtime_effects: self
                .pending_creations_by_task
                .iter()
                .filter(|(_, effect_id)| {
                    query
                        .requesting_effect_id
                        .as_ref()
                        .is_none_or(|requesting_effect_id| requesting_effect_id != *effect_id)
                })
                .map(|(task_id, _)| task_id.clone())
                .collect(),
        };
        let _ = query.reply_to.send(response);
    }

    fn enqueue_waiting_command(&mut self, task_id: TaskId, command: PendingTaskCommand) {
        let queue = self.waiting_task_commands.entry(task_id).or_default();
        if queue.len() < self.pending_task_command_limit {
            queue.push_back(command);
        }
    }

    fn runtime_is_removing(&self, task_id: &TaskId) -> bool {
        self.runtimes
            .get(task_id)
            .is_some_and(|entry| entry.removing)
    }

    fn waiting_queue_has_removal(&self, task_id: &TaskId) -> bool {
        self.waiting_task_commands
            .get(task_id)
            .is_some_and(|commands| {
                commands.iter().any(|command| {
                    matches!(
                        command,
                        PendingTaskCommand::Archive | PendingTaskCommand::Stop
                    )
                })
            })
    }

    fn scan_in_flight(&self) -> bool {
        self.effects
            .values()
            .any(|effect| matches!(effect, LifecycleEffect::ScanMissingTaskRuntimes))
    }

    fn runtime_removal_in_flight(&self) -> bool {
        self.runtimes.values().any(|entry| entry.removing)
    }

    fn runtime_accepts_external_requests(&self, task_id: &TaskId) -> bool {
        self.runtimes
            .get(task_id)
            .is_some_and(|entry| !entry.removing)
    }

    fn runtime_token_matches(&self, task_id: &TaskId, runtime_token: &TaskRuntimeToken) -> bool {
        self.runtimes
            .get(task_id)
            .is_some_and(|entry| &entry.runtime_token == runtime_token)
    }

    fn take_matching_model_call(&mut self, task_id: &TaskId, model_call_id: &ModelRunId) -> bool {
        let key = (task_id.clone(), model_call_id.clone());
        let Some(runtime_token) = self.in_flight_model_calls.remove(&key) else {
            return false;
        };
        self.runtimes
            .get(task_id)
            .is_some_and(|entry| entry.runtime_token == runtime_token && !entry.removing)
    }

    fn take_matching_tool_execution(
        &mut self,
        task_id: &TaskId,
        tool_execution_run_id: &ToolExecutionRunId,
    ) -> bool {
        let key = (task_id.clone(), tool_execution_run_id.clone());
        let Some(runtime_token) = self.in_flight_tool_executions.remove(&key) else {
            return false;
        };
        self.runtimes
            .get(task_id)
            .is_some_and(|entry| entry.runtime_token == runtime_token && !entry.removing)
    }

    fn clear_in_flight_for_task(&mut self, task_id: &TaskId) {
        self.in_flight_model_calls
            .retain(|(in_flight_task_id, _), _| in_flight_task_id != task_id);
        self.in_flight_tool_executions
            .retain(|(in_flight_task_id, _), _| in_flight_task_id != task_id);
    }

    fn finish_task_creation_effect(&mut self, effect: &LifecycleEffect) {
        if let LifecycleEffect::CreateTaskRuntime { task_id } = effect {
            self.pending_creations_by_task.remove(task_id);
        }
    }

    fn clear_removal_effects_for_task(&mut self, task_id: &TaskId) {
        self.effects.retain(|_, effect| {
            !matches!(
                effect,
                LifecycleEffect::RemoveTaskRuntime {
                    task_id: effect_task_id,
                } if effect_task_id == task_id
            )
        });
    }

    fn clear_failed_factory_spawn(&mut self, command: FactoryCommand) {
        match command {
            FactoryCommand::EnsureTaskRuntime(command) => {
                self.effects.remove(&command.effect_id);
                self.pending_creations_by_task.remove(&command.task_id);
                self.deferred_ensures.remove(&command.task_id);
                self.try_send_debug_notice(
                    Some(command.task_id),
                    "factory spawn failed before runtime creation output",
                );
            }
            FactoryCommand::EnsureMissingTaskRuntimes(command) => {
                self.effects.remove(&command.effect_id);
                self.try_send_debug_notice(None, "factory spawn failed before scan output");
            }
            FactoryCommand::CreateChildTaskAndRuntime(command) => {
                self.effects.remove(&command.effect_id);
                self.try_send_debug_notice(
                    Some(command.parent_task_id),
                    "factory spawn failed before child runtime output",
                );
            }
        }
    }

    fn try_send_debug_notice(&self, task_id: Option<TaskId>, message_text: &str) {
        let _ = self.events_tx.try_send(EventIngress::Raw(RawEvent::Debug(
            selvedge_command_model::DebugRawEvent {
                task_id,
                message_text: message_text.to_owned(),
            },
        )));
    }

    fn session_command_id(
        &self,
        client_id: &ClientId,
        fallback: ClientCommandId,
    ) -> ClientCommandId {
        self.client_sessions
            .get(client_id)
            .map(|session| session.command_id.clone())
            .unwrap_or(fallback)
    }

    fn client_session(&self, client_id: &ClientId) -> Option<ClientSession> {
        self.client_sessions.get(client_id).cloned()
    }

    fn retry_waiting_tasks_without_runtime(&mut self) {
        let task_ids = self
            .waiting_task_commands
            .keys()
            .cloned()
            .collect::<Vec<_>>();
        for task_id in task_ids {
            if !self.runtimes.contains_key(&task_id)
                && !self.pending_creations_by_task.contains_key(&task_id)
            {
                self.ensure_task_runtime(task_id);
            }
        }
    }

    fn retry_deferred_ensures(&mut self) {
        let task_ids = std::mem::take(&mut self.deferred_ensures)
            .into_iter()
            .collect::<Vec<_>>();
        for task_id in task_ids {
            if !self.runtimes.contains_key(&task_id)
                && !self.pending_creations_by_task.contains_key(&task_id)
            {
                self.ensure_task_runtime(task_id);
            }
        }
    }

    fn retry_deferred_scan(&mut self) {
        if self.deferred_scan && !self.runtime_removal_in_flight() && !self.scan_in_flight() {
            self.deferred_scan = false;
            self.ensure_missing_task_runtimes();
        }
    }

    async fn send_model_call_status(
        &mut self,
        task_id: TaskId,
        model_call_id: selvedge_command_model::ModelCallId,
        phase: ModelCallStatusPhase,
    ) {
        let _ = self
            .events_tx
            .send(EventIngress::Raw(RawEvent::ModelCallStatus(
                ModelCallStatusRawEvent {
                    task_id,
                    model_call_id,
                    phase,
                },
            )))
            .await;
    }

    async fn send_tool_execution_status(&mut self, event: ToolExecutionStatusRawEvent) {
        let _ = self
            .events_tx
            .send(EventIngress::Raw(RawEvent::ToolExecutionStatus(event)))
            .await;
    }

    fn requeue_failed_flush(
        &mut self,
        task_id: TaskId,
        command: PendingTaskCommand,
        mut remaining: VecDeque<PendingTaskCommand>,
    ) {
        let mut commands = VecDeque::new();
        commands.push_back(command);
        commands.append(&mut remaining);
        self.waiting_task_commands.insert(task_id.clone(), commands);
        self.ensure_task_runtime(task_id);
    }

    async fn send_failure_notice(&mut self, failure: FactoryFailure) {
        let task_id = failure.task_id;
        let message_text = format!("{:?}: {}", failure.kind, failure.message);
        let _ = self
            .events_tx
            .send(EventIngress::Raw(selvedge_command_model::RawEvent::Debug(
                selvedge_command_model::DebugRawEvent {
                    task_id,
                    message_text,
                },
            )))
            .await;
    }

    async fn send_notice(
        &mut self,
        client_id: selvedge_command_model::ClientId,
        command_id: ClientCommandId,
        level: ClientNoticeLevel,
        message_text: &str,
    ) {
        let command_id = self.session_command_id(&client_id, command_id);
        let _ = self
            .events_tx
            .send(EventIngress::Control(EventControlMessage::DeliverNotice(
                DeliverNotice {
                    client_id,
                    client_command_id: command_id,
                    notice: ClientNotice {
                        level,
                        message_text: message_text.to_owned(),
                    },
                },
            )))
            .await;
    }

    async fn deliver_snapshot(
        &mut self,
        client_id: selvedge_command_model::ClientId,
        command_id: ClientCommandId,
        subscription: Option<ClientSubscription>,
    ) {
        match self.build_snapshot(subscription.as_ref()) {
            Ok(snapshot) => {
                let _ = self
                    .events_tx
                    .send(EventIngress::Control(EventControlMessage::DeliverSnapshot(
                        DeliverSnapshot {
                            client_id,
                            client_command_id: command_id,
                            snapshot,
                        },
                    )))
                    .await;
            }
            Err(error) => {
                self.send_notice(
                    client_id,
                    command_id,
                    ClientNoticeLevel::Error,
                    &format!("snapshot read failed: {error}"),
                )
                .await;
            }
        }
    }

    fn build_snapshot(
        &self,
        subscription: Option<&ClientSubscription>,
    ) -> Result<ClientSnapshot, selvedge_db::DbError> {
        let mut tasks = selvedge_db::list_active_tasks(&self.db)?;
        if let Some(ClientSubscription {
            task_scope: TaskScope::TaskIds(task_ids),
            ..
        }) = subscription
        {
            tasks.retain(|task| task_ids.contains(&task.task_id));
        }
        let included_task_ids = tasks
            .iter()
            .map(|task| task.task_id.clone())
            .collect::<std::collections::BTreeSet<_>>();
        let task_parent_edges = selvedge_db::read_task_parent_edges(&self.db)?;
        let task_versions = tasks
            .iter()
            .map(|task| SnapshotTaskVersion {
                task_id: task.task_id.clone(),
                state_version: task.state_version,
            })
            .collect();
        let history_nodes = if subscription
            .is_some_and(|subscription| subscription.detail_level == DetailLevel::Verbose)
        {
            let mut seen_node_ids = HashSet::new();
            let mut history_nodes = Vec::new();
            for task in &tasks {
                for node in
                    selvedge_db::read_history_path_from_cursor(&self.db, task.cursor_node_id)?
                {
                    if seen_node_ids.insert(node.node_id()) {
                        history_nodes.push(history_node_projection(node));
                    }
                }
            }
            history_nodes
        } else {
            Vec::new()
        };
        let tasks = tasks
            .into_iter()
            .map(|task| TaskProjection {
                task_id: task.task_id,
                status: match task.task_status {
                    TaskStatusRow::Active => TaskProjectionStatus::Active,
                    TaskStatusRow::Archived => TaskProjectionStatus::Archived,
                },
                cursor_node_id: task.cursor_node_id,
                model_profile_key: task.model_profile_key,
                reasoning_effort: task.reasoning_effort,
                state_version: task.state_version,
                created_at: task.created_at,
                updated_at: task.updated_at,
            })
            .collect();
        let task_parent_edges = task_parent_edges
            .into_iter()
            .filter(|edge| {
                included_task_ids.contains(&edge.parent_task_id)
                    && included_task_ids.contains(&edge.child_task_id)
            })
            .map(|edge| TaskParentProjection {
                parent_task_id: edge.parent_task_id,
                child_task_id: edge.child_task_id,
            })
            .collect();

        Ok(ClientSnapshot {
            generated_at: now(),
            tasks,
            task_parent_edges,
            history_nodes,
            task_versions,
        })
    }

    fn domain_event_to_raw(&self, event: DomainEventPublishRequest) -> RawEvent {
        match event.event {
            DomainEvent::TaskRuntimeReady | DomainEvent::TaskArchived => {
                self.task_changed_raw_event(event.task_id)
            }
            DomainEvent::UserMessageCommitted { node_id }
            | DomainEvent::AssistantMessageCommitted { node_id }
            | DomainEvent::ReasoningCommitted { node_id }
            | DomainEvent::FunctionCallCommitted { node_id }
            | DomainEvent::FunctionOutputCommitted { node_id } => {
                self.history_appended_raw_event(event.task_id, node_id)
            }
            DomainEvent::ErrorNotice { message } => {
                RawEvent::Debug(selvedge_command_model::DebugRawEvent {
                    task_id: Some(event.task_id),
                    message_text: message,
                })
            }
        }
    }

    fn task_changed_raw_event(&self, task_id: TaskId) -> RawEvent {
        match selvedge_db::read_task(&self.db, &task_id) {
            Ok(task) => RawEvent::TaskChanged(selvedge_command_model::TaskChangedRawEvent {
                task: task_projection(task),
            }),
            Err(error) => RawEvent::Debug(selvedge_command_model::DebugRawEvent {
                task_id: Some(task_id),
                message_text: format!("task event projection failed: {error}"),
            }),
        }
    }

    fn history_appended_raw_event(&self, task_id: TaskId, node_id: HistoryNodeId) -> RawEvent {
        match (
            selvedge_db::read_task(&self.db, &task_id),
            selvedge_db::read_history_node(&self.db, &node_id),
        ) {
            (Ok(task), Ok(node)) => {
                RawEvent::HistoryAppended(selvedge_command_model::HistoryAppendedRawEvent {
                    task_id,
                    task_state_version: task.state_version,
                    appended_nodes: vec![history_node_projection(node)],
                })
            }
            (Err(error), _) | (_, Err(error)) => {
                RawEvent::Debug(selvedge_command_model::DebugRawEvent {
                    task_id: Some(task_id),
                    message_text: format!("history event projection failed: {error}"),
                })
            }
        }
    }

    fn stop(&mut self) {
        self.runtimes.clear();
        self.pending_creations_by_task.clear();
        self.effects.clear();
        self.waiting_task_commands.clear();
        self.deferred_ensures.clear();
        self.deferred_scan = false;
        self.in_flight_model_calls.clear();
        self.in_flight_tool_executions.clear();
    }
}

fn now() -> UnixTs {
    UnixTs(
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|duration| duration.as_secs() as i64)
            .unwrap_or(0),
    )
}

fn retryable_creation_failure(kind: &FactoryFailureKind) -> bool {
    matches!(
        kind,
        FactoryFailureKind::RuntimeInventoryUnavailable | FactoryFailureKind::CoreSpawnFailed
    )
}

fn task_projection(task: TaskRow) -> TaskProjection {
    TaskProjection {
        task_id: task.task_id,
        status: match task.task_status {
            TaskStatusRow::Active => TaskProjectionStatus::Active,
            TaskStatusRow::Archived => TaskProjectionStatus::Archived,
        },
        cursor_node_id: task.cursor_node_id,
        model_profile_key: task.model_profile_key,
        reasoning_effort: task.reasoning_effort,
        state_version: task.state_version,
        created_at: task.created_at,
        updated_at: task.updated_at,
    }
}

fn history_node_projection(node: HistoryNode) -> HistoryNodeProjection {
    match node {
        HistoryNode::Message {
            node_id,
            parent_node_id,
            created_at,
            message_role,
            message_text,
        } => HistoryNodeProjection {
            node_id,
            parent_node_id,
            created_at,
            body: HistoryNodeProjectionBody::Message {
                role: message_role,
                text: message_text,
            },
        },
        HistoryNode::Reasoning {
            node_id,
            parent_node_id,
            created_at,
            reasoning_text,
        } => HistoryNodeProjection {
            node_id,
            parent_node_id,
            created_at,
            body: HistoryNodeProjectionBody::Reasoning {
                text: reasoning_text,
            },
        },
        HistoryNode::FunctionCall {
            node_id,
            parent_node_id,
            created_at,
            function_call_id,
            tool_name,
            arguments,
        } => HistoryNodeProjection {
            node_id,
            parent_node_id,
            created_at,
            body: HistoryNodeProjectionBody::FunctionCall {
                function_call_id,
                tool_name,
                arguments,
            },
        },
        HistoryNode::FunctionOutput {
            node_id,
            parent_node_id,
            created_at,
            function_call_node_id,
            function_call_id,
            tool_name,
            output_text,
            is_error,
        } => HistoryNodeProjection {
            node_id,
            parent_node_id,
            created_at,
            body: HistoryNodeProjectionBody::FunctionOutput {
                function_call_node_id,
                function_call_id,
                tool_name,
                output_text,
                is_error,
            },
        },
    }
}
